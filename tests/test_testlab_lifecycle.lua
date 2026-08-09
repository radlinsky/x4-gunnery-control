-- Test Lab close ownership: operator exits return to the parked Gunnery menu,
-- while player-context/load teardown closes without resurrecting it.

local function loadHarness(spec)
    -- This file builds several isolated runtimes in one Lua process. require()
    -- otherwise retains the first fixture's ffi table, so later C write spies
    -- would observe a different table from gunnery_control.lua.
    package.loaded["ffi"] = nil
    local fix = dofile("tests/support/runtime_fixture.lua").load()
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
            session.directSnapshots = { {
                shipID = session.shipID, kind = "group", contextID = 5,
                path = "p", group = "g", mode = "attack", armed = false,
            } }
            -- Direct owns the group as autoassist/armed while the snapshot
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
        assert(#session.directSnapshots == 1,
            spec.label .. " must retain ownership of its matching Direct snapshot")
        local snapshot = session.directSnapshots[1]
        assert(#session.groups == 1 and session.groups[1].kind == "group",
            spec.label .. " must retain the matching live turret group")
        assert(tostring(session.groups[1].contextID) == "5"
            and session.groups[1].path == "p" and session.groups[1].group == "g",
            spec.label .. " live turret group must still match its snapshot locator")
        assert(snapshot.shipID == session.shipID and snapshot.contextID == 5
            and snapshot.path == "p" and snapshot.group == "g"
            and snapshot.mode == "attack" and snapshot.armed == false,
            spec.label .. " must preserve the original Direct snapshot unchanged")

        harness.fix.API.endForMovement()
        local teardownWrites = harness.getWrites()
        assert(harness.fix.API.getSession() == nil,
            spec.label .. " teardown must discard the resumed session")
        assert(teardownWrites.mode == 1 and teardownWrites.armed == 1,
            spec.label .. " must restore mode and armed exactly once at later teardown; got "
            .. tostring(teardownWrites.mode) .. "/" .. tostring(teardownWrites.armed))
        assert(#session.directSnapshots == 0,
            spec.label .. " teardown must release snapshot ownership")
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
              count = 1, distance = 4000, behaviour = "wait", hostile = true },
            { label = "platform", macro = "ship_arg_l_destroyer_01_a_macro", faction = "player",
              count = 2, distance = 2000, behaviour = "none" },
        },
    })
    local events = scenarioEvents(harness)
    assert(#events == 4, "enabled spec must fire begin + 2 groups + commit; got " .. #events)
    assert(events[1].control == "scenario_begin", "first event must be scenario_begin")
    assert(events[1].params.specId == "m6-lone-hostile", "begin must carry the spec id")
    assert(events[1].params.force == false, "the load-time send must not force a respawn")
    assert(events[2].control == "scenario_group" and events[3].control == "scenario_group",
        "one scenario_group event per spec group")
    assert(events[2].params.macro == "ship_xen_s_fighter_01_a_macro"
        and events[2].params.faction == "xenon" and events[2].params.count == 1
        and events[2].params.distance == 4000 and events[2].params.behaviour == "wait"
        and events[2].params.hostile == true and events[2].params.spread == 0,
        "group payload must carry the spec values, with spread defaulted to 0")
    assert(events[3].params.count == 2 and events[3].params.behaviour == "none"
        and events[3].params.hostile == false,
        "a non-hostile group must send hostile=false rather than nil")
    for _, event in ipairs(events) do
        assert(type(event.params) ~= "table" or event.params.groups == nil,
            "no event may carry a nested table; MD only accepts flat scalars")
    end
    assert(events[4].control == "scenario_commit", "last event must be scenario_commit")
end

-- A disabled spec is inert: it stays on disk but a Reload UI spawns nothing.
do
    local harness = loadHarness({
        id = "parked", enabled = false,
        groups = { { macro = "m", faction = "xenon", count = 1, distance = 1000 } },
    })
    assert(#scenarioEvents(harness) == 0, "a disabled spec must fire nothing on load")

    -- The on-demand button forces the same spec through, so the owner can spawn
    -- a parked fixture without the agent touching the file.
    harness.openFromGunnery({ label = "console", phase = "console" })
    local rerun = harness.fix.buttonByText(ReadText(20992, 25))
    assert(rerun and rerun.handlers.onClick, "Test Lab must expose the re-run button")
    rerun.handlers.onClick()
    local events = scenarioEvents(harness)
    assert(#events == 3 and events[1].params.force == true,
        "the re-run button must force the current spec even when it is disabled")
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
