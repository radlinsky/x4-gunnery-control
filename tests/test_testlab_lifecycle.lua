-- Test Lab close ownership: operator exits return to the parked Gunnery menu,
-- while player-context/load teardown closes without resurrecting it.

local function loadHarness(spec, realTime)
    -- This file builds several isolated runtimes in one Lua process. require()
    -- otherwise retains the first fixture's ffi table, so later C write spies
    -- would observe a different table from gunnery_control.lua.
    package.loaded["ffi"] = nil
    local fix = dofile("tests/support/runtime_fixture.lua").load()
    GetCurRealTime = function() return realTime or 0 end
    local handoffs, plainCloses = {}, {}
    local reentered = false

    -- testlab.lua uses clearMenu(), while the production runtime fixture models
    -- live frame rebuilds through clearDataForRefresh(). They are equivalent for
    -- this focused menu-ownership test.
    Helper.clearMenu = function(menu)
        Helper.clearDataForRefresh(menu)
        if menu then menu.frames = {} end
    end
    Helper.getMenu = function(name)
        for _, candidate in ipairs(Menus or {}) do
            if candidate.name == name then return candidate end
        end
    end
    Helper.closeMenu = function(from, reason)
        plainCloses[#plainCloses + 1] = { from = from, reason = reason }
    end
    Helper.closeMenuAndOpenNewMenu = function(from, destination, params, keepHUD)
        handoffs[#handoffs + 1] = {
            from = from, destination = destination, params = params, keepHUD = keepHUD,
        }
        -- Model a Helper implementation which reports the source close while
        -- processing the transition. The Test Lab must not request a second
        -- reopen from this re-entrant callback.
        if from and from.name == "X4GunneryTestLab" and not reentered then
            reentered = true
            from.onCloseElement("close")
        end
    end

    X4GunneryTestLabState = nil
    dofile("testlab/x4_gunnery_control_testlab/ui/testlab_state.lua")
    -- X4 loads ui.xml <file> entries in order, so the spec global is already
    -- published by the time testlab.lua runs. `spec` defaults to the shipped
    -- file so the ordinary lifecycle cases exercise the real load path.
    if spec == nil then
        dofile("testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua")
    else
        X4GunneryTestLabScenarioSpec = spec ~= "absent" and spec or nil
    end
    local ok, err = pcall(dofile, "testlab/x4_gunnery_control_testlab/ui/testlab.lua")
    assert(ok, "testlab.lua failed to load: " .. tostring(err))

    local testMenu
    for _, candidate in ipairs(Menus) do
        if candidate.name == "X4GunneryTestLab" then testMenu = candidate; break end
    end
    assert(testMenu, "X4GunneryTestLab was not registered")

    -- Keep one camera-capable group stable across the Gunnery close/reopen and
    -- model the actual directed state separately from its saved Direct snapshot.
    local groupBuffer = { [0] = { path = "p", group = "g", contextid = 5 } }
    local groupMode, groupArmed = "attack", false
    local modeWrites, armedWrites = 0, 0
    fix.ffiStub.new = function() return groupBuffer end
    fix.C.GetNumUpgradeGroups = function() return 1 end
    fix.C.GetUpgradeGroups2 = function() return 1 end
    fix.C.GetUpgradeGroupInfo2 = function()
        return {
            count = 1, currentcomponent = 27, currentmacro = "", slotsize = "",
            total = 1, operational = 1,
        }
    end
    fix.C.GetNumUpgradeSlots = function() return 1 end
    fix.C.GetUpgradeSlotCurrentComponent = function() return 27 end
    fix.C.GetUpgradeSlotGroup = function() return { path = "p", group = "g" } end
    fix.C.GetTurretGroupMode2 = function() return groupMode end
    fix.C.IsTurretGroupArmed = function() return groupArmed end
    fix.C.SetTurretGroupMode2 = function(_, _, _, _, value)
        modeWrites = modeWrites + 1
        groupMode = value
    end
    fix.C.SetTurretGroupArmed = function(_, _, _, _, value)
        armedWrites = armedWrites + 1
        groupArmed = value
    end
    fix.C.IsComponentOperational = function() return true end
    fix.C.IsPlayerCameraTargetViewPossible = function() return true end
    fix.C.GetComponentName = function() return "Test Ship" end
    GetComponentData = function(_, field)
        if field == "macro" then return "test_ship_macro" end
        if field == "isplayerowned" then return true end
        return nil
    end

    local function countHandoffs(fromName, destination)
        local count = 0
        for _, call in ipairs(handoffs) do
            if call.from and call.from.name == fromName and call.destination == destination then
                count = count + 1
            end
        end
        return count
    end

    local function openFromGunnery(spec)
        local phase = spec.phase
        fix.gcMenu.onShowMenu()
        local session = fix.API.getSession()
        assert(session, "expected a Gunnery session before opening Test Lab")
        session.checkedGroupKeys = { [X4GunneryState.groupKey(5, "p", "g")] = true }
        session.phase = phase
        if phase ~= "console" then
            session.controlMode = spec.controlMode
            session.cameraMemberID = 27
        end
        if spec.direct then
            session.committedBaseline = { {
                shipID = session.shipID, kind = "group", contextID = 5,
                path = "p", group = "g", mode = "attack", armed = false,
            } }
            -- Direct owns the group as autoassist/armed while the baseline
            -- retains the exact settings that later teardown must restore.
            groupMode, groupArmed = "autoassist", true
        end
        fix.gcMenu.display()
        local button = fix.buttonByText(ReadText(20991, 32))
        assert(button and button.handlers.onClick,
            spec.label .. " must expose the Test Lab button")
        button.handlers.onClick()
        assert(countHandoffs("X4GunneryMenu", "X4GunneryTestLab") == 1,
            "opening Test Lab must request exactly one main-to-lab handoff")
        assert(session.lifecycle == X4GunneryState.lifecycle.reopening,
            "opening Test Lab must park the session in reopening lifecycle")
        testMenu.onShowMenu()
        return session
    end

    return {
        fix = fix,
        testMenu = testMenu,
        handoffs = handoffs,
        plainCloses = plainCloses,
        countHandoffs = countHandoffs,
        openFromGunnery = openFromGunnery,
        getWrites = function() return { mode = modeWrites, armed = armedWrites } end,
    }
end

-- Standard close must hand console, a real Direct target-select, Auto engaged,
-- and a separate Direct-engaged session back to the same Gunnery session. The
-- Helper re-entry plus the explicit duplicate below prove the handoff is
-- requested once, and the normal close path must add no Test Lab success log.
local standardCloseCases = {
    { label = "console", phase = "console" },
    { label = "Direct target-select", phase = "target_select", controlMode = "direct", direct = true },
    { label = "Auto engaged", phase = "engaged", controlMode = "auto" },
    { label = "Direct engaged", phase = "engaged", controlMode = "direct", direct = true },
}
for _, spec in ipairs(standardCloseCases) do
    local harness = loadHarness()
    local session = harness.openFromGunnery(spec)
    local logBefore = #harness.fix.getCapturedLog()

    harness.testMenu.onCloseElement("close")
    harness.testMenu.onCloseElement("close")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 1,
        "standard close from " .. spec.label .. " must reopen Gunnery exactly once")
    for index = logBefore + 1, #harness.fix.getCapturedLog() do
        assert(not string.find(harness.fix.getCapturedLog()[index], "[X4GC TEST]", 1, true),
            "standard Test Lab close must be log-silent")
    end
    local writesBeforeResume = harness.getWrites()
    assert(writesBeforeResume.mode == 0 and writesBeforeResume.armed == 0,
        "Test Lab close from " .. spec.label .. " must not restore turret settings")

    harness.fix.gcMenu.onShowMenu()
    assert(harness.fix.API.getSession() == session,
        "standard close from " .. spec.label .. " must resume the parked session object")
    assert(session.phase == spec.phase,
        "standard close must preserve " .. spec.label .. " phase; got " .. tostring(session.phase))
    assert(session.lifecycle == X4GunneryState.lifecycle.owned,
        "resumed " .. spec.label .. " session must regain owned lifecycle")

    local writesAfterResume = harness.getWrites()
    assert(writesAfterResume.mode == 0 and writesAfterResume.armed == 0,
        "resuming " .. spec.label .. " must not restore turret settings")
    if spec.direct then
        assert(#session.committedBaseline == 1,
            spec.label .. " must retain the matching committedBaseline entry")
        local snapshot = session.committedBaseline[1]
        assert(#session.groups == 1 and session.groups[1].kind == "group",
            spec.label .. " must retain the matching live turret group")
        assert(tostring(session.groups[1].contextID) == "5"
            and session.groups[1].path == "p" and session.groups[1].group == "g",
            spec.label .. " live turret group must still match its baseline locator")
        assert(snapshot.shipID == session.shipID and snapshot.contextID == 5
            and snapshot.path == "p" and snapshot.group == "g"
            and snapshot.mode == "attack" and snapshot.armed == false,
            spec.label .. " must preserve the original committedBaseline entry unchanged")

        harness.fix.API.endForMovement()
        local teardownWrites = harness.getWrites()
        assert(harness.fix.API.getSession() == nil,
            spec.label .. " teardown must discard the resumed session")
        assert(teardownWrites.mode == 1 and teardownWrites.armed == 1,
            spec.label .. " must restore mode and armed exactly once at later teardown; got "
            .. tostring(teardownWrites.mode) .. "/" .. tostring(teardownWrites.armed))
        -- committedBaseline persists for the session lifetime (never cleared by releaseDirect).
        -- Correct teardown is confirmed by the turret-write counts above and getSession() == nil.
        assert(#session.committedBaseline == 1,
            spec.label .. " teardown must leave committedBaseline intact (revert data is not erased)")
    end
end

-- Abort remains an operator exit: it clears the sweep, returns once, and is
-- allowed to emit its single explicit abort record (not a routine success log).
do
    local harness = loadHarness()
    harness.openFromGunnery({ label = "console", phase = "console" })
    local start = harness.fix.buttonByText(ReadText(20992, 2))
    assert(start and start.handlers.onClick, "Test Lab must expose Start Sweep")
    start.handlers.onClick()
    local abort = harness.fix.buttonByText(ReadText(20992, 9))
    assert(abort and abort.handlers.onClick, "an active sweep must expose Abort")
    abort.handlers.onClick()
    harness.testMenu.onCloseElement("close")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 1,
        "Abort must return to Gunnery exactly once")

    harness.testMenu.onShowMenu()
    assert(harness.fix.buttonByText(ReadText(20992, 2)) ~= nil,
        "Abort must clear the sweep before a later Test Lab opening")
    assert(harness.fix.buttonByText(ReadText(20992, 9)) == nil,
        "Abort must not leave a stale sweep action behind")
end

-- Player movement and game loads are safety teardown, not operator exits.
-- Their eventual menu close must stay local and remain idempotent.
for _, contextEvent in ipairs({ "playerGetUp", "gameLoadingDone" }) do
    local harness = loadHarness()
    harness.openFromGunnery({ label = "console", phase = "console" })
    local start = harness.fix.buttonByText(ReadText(20992, 2))
    start.handlers.onClick()

    if contextEvent == "gameLoadingDone" then
        harness.fix.fireUIEvent(contextEvent)
    else
        harness.fix.fireEvent(contextEvent)
    end
    harness.testMenu.onCloseElement("close")
    harness.testMenu.onCloseElement("close")

    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        contextEvent .. " cleanup must not reopen Gunnery")
    assert(#harness.plainCloses >= 1,
        contextEvent .. " cleanup must allow the Test Lab to close locally")
end

-- Scenario spec transport. The spec is replayed on every UI load as a flat
-- begin/group.../commit stream, because MD cannot be handed a nested table.
local function scenarioEvents(harness)
    local events = {}
    for _, event in ipairs(harness.fix.uiTriggeredEvents) do
        if event.screen == "X4GunneryTestLabScenario" then events[#events + 1] = event end
    end
    return events
end

-- An enabled spec fires begin, one group event per group, then commit, with the
-- spec's own values and force=false (the load-time send must never force).
do
    local harness = loadHarness({
        id = "m6-lone-hostile",
        enabled = true,
        groups = {
            { label = "hostile", macro = "ship_xen_s_fighter_01_a_macro", faction = "xenon",
              count = 1, distance = 4000, behaviour = "wait", hostile = true,
              holdFire = true, stripDefenceUnits = true, repairGuard = true },
            { label = "platform", macro = "ship_arg_l_destroyer_01_a_macro", faction = "player",
              count = 2, distance = 2000, behaviour = "none" },
        },
    })
    local events = scenarioEvents(harness)
    assert(#events == 4, "enabled spec must fire begin + 2 groups + commit; got " .. #events)
    assert(events[1].control == "scenario_begin", "first event must be scenario_begin")
    assert(events[1].params.specId == "m6-lone-hostile", "begin must carry the spec id")
    assert(events[1].params.force == false, "the load-time send must not force a respawn")
    assert(events[1].params.requestId == "", "load-time replay must not request an operator acknowledgement")
    assert(events[2].control == "scenario_group" and events[3].control == "scenario_group",
        "one scenario_group event per spec group")
    assert(events[2].params.macro == "ship_xen_s_fighter_01_a_macro"
        and events[2].params.faction == "xenon" and events[2].params.count == 1
        and events[2].params.distance == 4000 and events[2].params.behaviour == "wait"
        and events[2].params.hostile == true and events[2].params.spread == 0
        and events[2].params.x == 0 and events[2].params.y == 0
        and events[2].params.holdFire == true
        and events[2].params.stripDefenceUnits == true
        and events[2].params.repairGuard == true,
        "group payload must carry the spec values, with spread/x/y defaulted to 0")
    assert(events[3].params.count == 2 and events[3].params.behaviour == "none"
        and events[3].params.hostile == false and events[3].params.repairGuard == false,
        "a non-hostile group must send hostile=false rather than nil")
    for _, event in ipairs(events) do
        assert(type(event.params) ~= "table" or event.params.groups == nil,
            "no event may carry a nested table; MD only accepts flat scalars")
    end
    assert(events[4].control == "scenario_commit", "last event must be scenario_commit")
end

-- Station recipes use the same flat transport and may be the only fixture
-- object. Readiness depends on the correlated operational component census,
-- not merely on create_station returning a visible shell.
do
    local harness = loadHarness({
        id = "station-transport",
        enabled = true,
        groups = {},
        stations = {
            { label = "Surface fixture", recipe = "xen_defence", faction = "xenon",
              distance = 30000, expectedModules = 5, minSurfaces = 100,
              hostile = true, holdFire = true },
        },
    })
    local events = scenarioEvents(harness)
    assert(#events == 3, "station-only spec must fire begin + station + commit; got " .. #events)
    assert(events[2].control == "scenario_station",
        "station recipe must use its own flat streamed event")
    assert(events[2].params.recipe == "xen_defence"
        and events[2].params.expectedModules == 5
        and events[2].params.minSurfaces == 100
        and events[2].params.distance == 30000
        and events[2].params.x == 0 and events[2].params.y == 0
        and events[2].params.spread == 0 and events[2].params.hostile == true
        and events[2].params.holdFire == true,
        "station event must carry the validated recipe, placement, and census thresholds")
    assert(events[3].control == "scenario_commit", "station stream must end with commit")
end

local function stationScenarioHarness(id)
    local harness = loadHarness({
        id = id, enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = {},
        stations = {
            { label = "Surface fixture", recipe = "xen_defence", faction = "xenon",
              distance = 30000, expectedModules = 5, minSurfaces = 100,
              holdFire = true },
        },
    })
    harness.openFromGunnery({ label = "console", phase = "console" })
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    return harness, scenarioEvents(harness)[1].params.requestId
end

do
    local harness, requestId = stationScenarioHarness("station-census-low")
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct3:" .. requestId .. ":station-census-low:0:1:5:69:0:25:0:1:69:0")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "a station shell below the 100-surface threshold must keep Test Lab open")
    assert(harness.fix.logContains("action=failed")
            and harness.fix.logContains("operational_surfaces=99"),
        "a low station census must emit the exact machine-readable surface count")
end

do
    local harness, requestId = stationScenarioHarness("station-census-ready")
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct3:" .. requestId .. ":station-census-ready:0:1:5:70:0:25:0:1:70:0")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 1,
        "a matching station/module/surface census must return to Gunnery")
    assert(harness.fix.logContains("action=ready")
            and harness.fix.logContains("operational_surfaces=100")
            and harness.fix.logContains("spawned_stations=1"),
        "station readiness must record its correlated operational census")
end

do
    local harness, requestId = stationScenarioHarness("station-safety-failed")
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct3:" .. requestId .. ":station-safety-failed:0:1:5:70:0:25:0:1:69:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "an armed station weapon must keep Test Lab open")
    assert(harness.fix.logContains("action=failed")
            and harness.fix.logContains("unsafe_weapons=1"),
        "station safety failure must record the unsafe weapon census")
end

do
    local harness, requestId = stationScenarioHarness("station-drones-failed")
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct4:" .. requestId .. ":station-drones-failed:0:1:5:70:0:25:0:1:70:0:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "a remaining defence drone must keep Test Lab open")
    assert(harness.fix.logContains("action=failed")
            and harness.fix.logContains("defence_units=1"),
        "drone safety failure must record the remaining defence-unit census")
end

do
    local harness = loadHarness({
        id = "hostility-failed", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = {
            { label = "Hostile target", macro = "target_macro", faction = "xenon",
              count = 1, distance = 5000, behaviour = "wait", hostile = true,
              holdFire = true, stripDefenceUnits = true },
        },
        stations = {},
    })
    harness.openFromGunnery({ label = "console", phase = "console" })
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    local requestId = scenarioEvents(harness)[1].params.requestId
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct5:" .. requestId .. ":hostility-failed:1:0:0:0:0:0:0:1:15:0:0:0")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "a neutral requested-hostile target must keep Test Lab open")
    assert(harness.fix.logContains("action=failed")
            and harness.fix.logContains("expected_hostiles=1")
            and harness.fix.logContains("hostiles=0"),
        "hostility failure must record the expected and actual attackable census")
end

-- Repair guards are acknowledged independently from HOLD FIRE. A fixture that
-- is safe but not actually registered for post-hit repair must not start a
-- destructive attribution run.
do
    local harness = loadHarness({
        id = "repair-guard-ready", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = {
            { label = "Repaired target", macro = "target_macro", faction = "xenon",
              count = 1, distance = 3000, behaviour = "wait", hostile = true,
              holdFire = true, stripDefenceUnits = true, repairGuard = true },
        },
        stations = {},
    })
    harness.openFromGunnery({ label = "console", phase = "console" })
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    local requestId = scenarioEvents(harness)[1].params.requestId
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct6:" .. requestId .. ":repair-guard-ready:1:0:0:0:0:0:0:1:15:0:0:1:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 1,
        "an exact repair-guard census must complete scenario setup")
    assert(harness.fix.logContains("repair_fixtures=1"),
        "READY must record the correlated repair-guard fixture count")
end

do
    local harness = loadHarness({
        id = "repair-guard-missing", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = {
            { label = "Repaired target", macro = "target_macro", faction = "xenon",
              count = 1, distance = 3000, behaviour = "wait", hostile = true,
              holdFire = true, stripDefenceUnits = true, repairGuard = true },
        },
        stations = {},
    })
    harness.openFromGunnery({ label = "console", phase = "console" })
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    local requestId = scenarioEvents(harness)[1].params.requestId
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct6:" .. requestId .. ":repair-guard-missing:1:0:0:0:0:0:0:1:15:0:0:1:0")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "a missing repair guard must keep Test Lab open")
    assert(harness.fix.logContains("expected_repair_fixtures=1")
            and harness.fix.logContains("repair_fixtures=0"),
        "repair-guard failure must log expected and actual counts")
end

-- x/y bearing offsets: when set they are forwarded as scalars; when omitted
-- they default to 0.  Both cases must still produce a flat (non-nested) payload.
do
    -- With x and y explicitly set.
    local harness = loadHarness({
        id = "bearing-explicit",
        enabled = true,
        groups = {
            { macro = "ship_xen_s_fighter_01_a_macro", faction = "xenon",
              count = 1, distance = 3000, x = 1500, y = -800, behaviour = "wait" },
        },
    })
    local events = scenarioEvents(harness)
    assert(#events == 3, "bearing spec must fire begin + 1 group + commit; got " .. #events)
    assert(events[2].params.x == 1500 and events[2].params.y == -800,
        "explicit x/y must be forwarded in the group payload")
    assert(type(events[2].params.x) == "number" and type(events[2].params.y) == "number",
        "x and y must be numbers in the payload")
end
do
    -- With x and y omitted: must default to 0, not nil.
    local harness = loadHarness({
        id = "bearing-omitted",
        enabled = true,
        groups = {
            { macro = "ship_xen_s_fighter_01_a_macro", faction = "xenon",
              count = 1, distance = 3000, behaviour = "wait" },
        },
    })
    local events = scenarioEvents(harness)
    assert(#events == 3, "omitted-bearing spec must fire begin + 1 group + commit; got " .. #events)
    assert(events[2].params.x == 0 and events[2].params.y == 0,
        "omitted x/y must default to 0 in the group payload")
end

-- A disabled spec is inert on load. The one-click action preflights the exact
-- ship/group, replaces the fixture, selects only that group, and returns to
-- Gunnery only after MD acknowledges the expected ship count.
do
    local harness = loadHarness({
        id = "parked", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = { { macro = "m", faction = "xenon", count = 1, distance = 1000 } },
    })
    assert(#scenarioEvents(harness) == 0, "a disabled spec must fire nothing on load")

    local session = harness.openFromGunnery({ label = "console", phase = "console" })
    local selectedKey = X4GunneryState.groupKey(5, "p", "g")
    session.staged[selectedKey] = nil
    session.checkedGroupKeys.extra = true
    session.staged.extra = { mode = "defend", preTickMode = "attack" }
    local create = harness.fix.buttonByText(ReadText(20992, 25))
    assert(create and create.handlers.onClick, "Test Lab must expose Create test scenario")
    create.handlers.onClick()
    local events = scenarioEvents(harness)
    local requestId = events[1].params.requestId
    assert(#events == 3 and events[1].params.force == true
            and type(requestId) == "string" and requestId:match("_1$"),
        "Create test scenario must force a correlated replacement even when the spec is disabled")
    assert(harness.fix.logContains("event=scenario_runtime")
            and harness.fix.logContains("load_time="),
        "each Test Lab Lua lifetime must log its auditable engine time")
    assert(harness.fix.logContains("action=requested")
            and harness.fix.logContains("request_id=" .. requestId),
        "Create test scenario must log its exact correlated request token")
    assert(session.checkedGroupKeys[selectedKey] == true and session.checkedGroupKeys.extra == true
            and session.staged.extra.mode == "defend" and session.staged.extra.preTickMode == "attack",
        "preflight must leave checked and staged state untouched before acknowledgement")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "Test Lab must wait for MD acknowledgement before returning")
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady", "x4gct1:stale_1:parked:1")
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady", "x4gct1:" .. requestId .. ":wrong-spec:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "a stale-load or wrong-spec acknowledgement must be ignored")
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady", "x4gct1:" .. requestId .. ":parked:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 1,
        "a matching complete spawn acknowledgement must return to Gunnery exactly once")
    assert(harness.fix.logContains("action=ready")
            and harness.fix.logContains("request_id=" .. requestId),
        "successful acknowledgement must log the same request token")
    assert(session.checkedGroupKeys[selectedKey] == true and session.checkedGroupKeys.extra == nil,
        "successful acknowledgement must leave only the exact raw group selected")
    assert(session.staged[selectedKey] and session.staged[selectedKey].armed == false,
        "a freshly staged selected group must preserve its live disarmed state")
    local observingArmed = false
    for _, event in ipairs(harness.fix.uiTriggeredEvents) do
        if event.control == "observe_toggle" and event.params.enabled == true then
            observingArmed = true
        end
    end
    assert(observingArmed,
        "successful one-click scenario creation must arm automatic firing-solution observation")
end

-- Consecutive Test Lab Lua lifetimes may clear every Lua global. Engine real
-- time still advances, so their first request IDs cannot collide.
do
    local function firstRequestId(realTime)
        local harness = loadHarness({
            id = "generation", enabled = false,
            setup = {
                shipMacro = "test_ship_macro", shipLabel = "Test Ship",
                turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
            },
            groups = { { macro = "m", faction = "xenon", count = 1, distance = 1000 } },
        }, realTime)
        harness.openFromGunnery({ label = "console", phase = "console" })
        harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
        return scenarioEvents(harness)[1].params.requestId
    end
    X4GunneryTestLabRuntime = nil
    local first = firstRequestId(100.125)
    X4GunneryTestLabRuntime = nil
    local second = firstRequestId(101.250)
    assert(first ~= second and first:match("_1$") and second:match("_1$"),
        "consecutive UI lifetimes must generate distinct first-request IDs")
end

-- A preflight mismatch must not despawn the existing fixture or alter the
-- operator's selection. A partial MD acknowledgement must not return to play.
do
    local harness = loadHarness({
        id = "preflight-guards", enabled = true,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Required Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = { { macro = "m", faction = "xenon", count = 2, distance = 1000 } },
    })
    -- Ignore the automatic load-time replay; only the button attempt matters.
    for index = #harness.fix.uiTriggeredEvents, 1, -1 do
        table.remove(harness.fix.uiTriggeredEvents, index)
    end
    local session = harness.openFromGunnery({ label = "console", phase = "console" })
    local before = {}
    for key, value in pairs(session.checkedGroupKeys) do before[key] = value end
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    assert(#scenarioEvents(harness) == 0, "same-macro wrong-name preflight must not touch the field")
    for key, value in pairs(before) do
        assert(session.checkedGroupKeys[key] == value, "wrong-name preflight must preserve checked groups")
    end
end

do
    local harness = loadHarness({
        id = "ack-count-guard", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = { { macro = "m", faction = "xenon", count = 2, distance = 1000 } },
    })
    local session = harness.openFromGunnery({ label = "console", phase = "console" })
    session.checkedGroupKeys.extra = true
    session.staged.extra = { mode = "defend", preTickMode = "attack" }
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    local events = scenarioEvents(harness)
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:" .. events[1].params.requestId .. ":ack-count-guard:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "partial spawn acknowledgement must keep Test Lab open")
    assert(harness.fix.logContains("action=failed"),
        "partial spawn acknowledgement must emit a machine-readable failure")
    assert(session.checkedGroupKeys.extra == true and session.staged.extra.mode == "defend",
        "partial acknowledgement must preserve checked and staged state")
end

do
    local now = 0
    local harness = loadHarness({
        id = "ack-timeout", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = { { macro = "m", faction = "xenon", count = 1, distance = 1000 } },
    })
    getElapsedTime = function() return now end
    harness.openFromGunnery({ label = "console", phase = "console" })
    local session = harness.fix.API.getSession()
    session.checkedGroupKeys.extra = true
    session.staged.extra = { mode = "defend", preTickMode = "attack" }
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    now = 11
    harness.testMenu.onUpdate()
    assert(harness.fix.logContains("action=timeout"),
        "missing spawn acknowledgement must produce a bounded timeout")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "spawn timeout must keep Test Lab open for its failure message")
    assert(session.checkedGroupKeys.extra == true and session.staged.extra.mode == "defend",
        "spawn timeout must preserve checked and staged state")
end

-- A loadout change during MD creation invalidates the result before checkbox
-- mutation, even when MD created the requested ship count.
do
    local harness = loadHarness({
        id = "loadout-changed", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = { { macro = "m", faction = "xenon", count = 1, distance = 1000 } },
    })
    local session = harness.openFromGunnery({ label = "console", phase = "console" })
    session.checkedGroupKeys.extra = true
    session.staged.extra = { mode = "defend", preTickMode = "attack" }
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    local events = scenarioEvents(harness)
    harness.fix.C.IsComponentOperational = function() return false end
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:" .. events[1].params.requestId .. ":loadout-changed:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "changed loadout must keep Test Lab open")
    assert(session.checkedGroupKeys.extra == true and session.staged.extra.mode == "defend",
        "changed loadout must preserve checked and staged state")
end

-- Despawn is disabled while pending. Defensive invocation cancels correlation,
-- so a queued ready event cannot return the owner to an empty field.
do
    local harness = loadHarness({
        id = "pending-despawn", enabled = false,
        setup = {
            shipMacro = "test_ship_macro", shipLabel = "Test Ship",
            turretGroup = "g", turretLabel = "Test Group", expectedTurrets = 1,
        },
        groups = { { macro = "m", faction = "xenon", count = 1, distance = 1000 } },
    })
    harness.openFromGunnery({ label = "console", phase = "console" })
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    local events = scenarioEvents(harness)
    local despawn = harness.fix.buttonByText(ReadText(20992, 26))
    assert(despawn.active == false, "Despawn must be disabled while creation is pending")
    despawn.handlers.onClick()
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:" .. events[1].params.requestId .. ":pending-despawn:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "ready after defensive Despawn cancellation must be ignored")
end

-- Malformed specs are caught, logged, and never raise. Test Lab must still open
-- and still offer despawn, because a broken spec is the moment cleanup matters.
-- `reason` is the substring the rejection must name, in the SANITIZED form the
-- log actually carries (log() replaces every non-word character with "_"), so a validator that
-- silently swallows the failure (and reports the spec as merely absent) fails
-- here rather than looking like a pass.
local malformed = {
    { label = "not a table", spec = 42, reason = "spec_is_not_a_table" },
    { label = "missing id", spec = { enabled = true, groups = {} }, reason = "spec.id_must_be" },
    { label = "non-boolean enabled", spec = { id = "x", enabled = "yes", groups = {} }, reason = "spec.enabled_must_be" },
    { label = "empty groups", spec = { id = "x", enabled = true, groups = {} }, reason = "spec.groups_is_empty" },
    { label = "group missing macro", spec = { id = "x", enabled = true,
        groups = { { faction = "xenon", count = 1, distance = 100 } } }, reason = "groups_1_.macro" },
    { label = "bad behaviour", spec = { id = "x", enabled = true,
        groups = { { macro = "m", faction = "xenon", count = 1, distance = 100, behaviour = "loiter" } } },
        reason = "groups_1_.behaviour" },
    { label = "absent global", spec = "absent" },
}
for _, case in ipairs(malformed) do
    local ok, harness = pcall(loadHarness, case.spec)
    assert(ok, "a malformed spec (" .. case.label .. ") must not raise: " .. tostring(harness))
    assert(#scenarioEvents(harness) == 0,
        "a malformed spec (" .. case.label .. ") must spawn nothing")
    harness.openFromGunnery({ label = "console", phase = "console" })
    assert(harness.fix.buttonByText(ReadText(20992, 26)) ~= nil,
        "Test Lab must still offer despawn with a malformed spec (" .. case.label .. ")")

    -- Forcing must not rescue a spec that could not be understood.
    local rerun = harness.fix.buttonByText(ReadText(20992, 25))
    assert(rerun and rerun.handlers.onClick, "the re-run button must exist with a malformed spec")
    rerun.handlers.onClick()
    assert(#scenarioEvents(harness) == 0,
        "forcing a malformed spec (" .. case.label .. ") must still spawn nothing")

    if case.reason then
        local named = false
        for _, line in ipairs(harness.fix.getCapturedLog()) do
            if string.find(line, "action=rejected", 1, true) and string.find(line, case.reason) then
                named = true
            end
        end
        assert(named, "rejecting " .. case.label .. " must log a reason naming " .. case.reason)
    end
end

-- The shipped spec file must itself stay loadable and inert, so that an
-- unrelated Reload UI never spawns whatever the last test left behind.
do
    local shipped = dofile("testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua")
    assert(type(shipped) == "table", "the shipped spec must return a table")
    assert(shipped.enabled == false,
        "the spec committed to the repository must be disabled; enable it only for a live run")
end

print("testlab lifecycle tests passed")
