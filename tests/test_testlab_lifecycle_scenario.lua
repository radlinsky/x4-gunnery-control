-- test_testlab_lifecycle_scenario.lua
-- Reusable Test Lab scenario validation, flat Lua->MD transport, fail-closed
-- census guards, exact-group activation, request correlation, and lifecycle.

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
    -- Permanent tests always supply a synthetic scenario (or deliberately no
    -- scenario). The mutable live scenario_spec.lua is not a unit-test fixture.
    X4GunneryTestLabScenarioSpec = spec ~= "absent" and spec or nil
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

    local function openFromGunnery(open)
        local phase = open.phase
        fix.gcMenu.onShowMenu()
        local session = fix.API.getSession()
        assert(session, "expected a Gunnery session before opening Test Lab")
        session.checkedGroupKeys = { [X4GunneryState.groupKey(5, "p", "g")] = true }
        session.phase = phase
        if phase ~= "console" then
            session.controlMode = open.controlMode
            session.cameraMemberID = 27
        end
        if open.direct then
            session.committedBaseline = { {
                shipID = session.shipID, kind = "group", contextID = 5,
                path = "p", group = "g", mode = "attack", armed = false,
            } }
            groupMode, groupArmed = "autoassist", true
        end
        fix.gcMenu.display()
        local button = fix.buttonByText(ReadText(20991, 32))
        assert(button and button.handlers.onClick,
            open.label .. " must expose the Test Lab button")
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

local function scenarioEvents(harness)
    local events = {}
    for _, event in ipairs(harness.fix.uiTriggeredEvents) do
        if event.screen == "X4GunneryTestLabScenario" then events[#events + 1] = event end
    end
    return events
end

local function copyWith(base, overrides)
    local result = {}
    for key, value in pairs(base or {}) do result[key] = value end
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local function group(overrides)
    return copyWith({
        macro = "target_macro",
        faction = "xenon",
        count = 1,
        distance = 1000,
        behaviour = "wait",
    }, overrides)
end

local function localScenario(id, groupOverrides)
    return {
        id = id,
        enabled = false,
        setup = {
            shipMacro = "test_ship_macro",
            shipLabel = "Test Ship",
            turretGroup = "g",
            turretLabel = "Test Group",
            expectedTurrets = 1,
        },
        groups = { group(groupOverrides) },
        stations = {},
    }
end

local function requestScenario(harness)
    local create = harness.fix.buttonByText(ReadText(20992, 25))
    assert(create and create.handlers.onClick, "Test Lab must expose Create test scenario")
    create.handlers.onClick()
    local events = scenarioEvents(harness)
    assert(events[1] and type(events[1].params.requestId) == "string",
        "scenario Create must emit a correlated request id")
    return events, events[1].params.requestId
end

local ready8Order = {
    "spawned", "stations", "modules", "turrets", "missileTurrets", "shields", "engines",
    "safeFixtures", "safeWeapons", "unsafeWeapons", "defenceUnits", "hostiles", "repairFixtures",
    "shooters", "shooterMissileTurrets", "guided", "dumbfire", "ammo",
    "loadoutFailures", "locationFailures", "shooterWeapons", "shooterTurrets",
    "shooterBeam", "shooterPlasma", "preflightFailures", "geometrySplits",
}

local function ready8(requestId, specId, values)
    local parts = { "x4gct8", requestId, specId }
    for _, field in ipairs(ready8Order) do
        parts[#parts + 1] = tostring((values or {})[field] or 0)
    end
    return table.concat(parts, ":")
end

-- Flat transport uses only scalars and stable defaults. This synthetic spec
-- deliberately exercises explicit and omitted fields without pinning the live
-- scenario file or any historical fixture identity.
do
    local harness = loadHarness({
        id = "flat-transport",
        enabled = true,
        groups = {
            group({
                label = "explicit",
                distance = -250,
                spread = 12,
                x = 40, y = -50,
                ox = 1, oy = 2, oz = 3,
                hostile = true, holdFire = true, repairGuard = true,
                yaw = 15, pitch = -20, roll = 25,
                preserveOrientation = true,
            }),
            group({ label = "defaults" }),
        },
        stations = {},
    })
    local events = scenarioEvents(harness)
    assert(#events == 4, "flat spec must stream begin + 2 groups + commit")
    assert(events[1].control == "scenario_begin"
            and events[1].params.specId == "flat-transport"
            and events[1].params.anchorX == 0
            and events[1].params.anchorY == 0
            and events[1].params.anchorZ == 0,
        "scenario_begin must transport scalar identity and default anchor values")
    local explicit = events[2].params
    assert(explicit.distance == -250 and explicit.spread == 12
            and explicit.x == 40 and explicit.y == -50
            and explicit.ox == 1 and explicit.oy == 2 and explicit.oz == 3
            and explicit.yaw == 15 and explicit.pitch == -20 and explicit.roll == 25
            and explicit.preserveOrientation == true,
        "explicit group scalars must survive Lua-to-MD transport")
    local defaults = events[3].params
    assert(defaults.x == 0 and defaults.y == 0
            and defaults.ox == 0 and defaults.oy == 0 and defaults.oz == 0
            and defaults.yaw == 0 and defaults.pitch == 0 and defaults.roll == 0
            and defaults.preserveOrientation == false,
        "omitted optional group scalars must use stable flat defaults")
    for index = 1, 3 do
        for _, value in pairs(events[index].params or {}) do
            assert(type(value) ~= "table",
                "scenario transport must not pass nested Lua tables to MD")
        end
    end
end

-- Representative malformed inputs fail closed without raising or spawning.
-- These cases cover the validator boundary rather than every historical field.
local malformed = {
    { label = "not a table", spec = 42, reason = "spec_is_not_a_table" },
    { label = "missing id", spec = { enabled = true, groups = { group() } },
      reason = "spec.id_must_be" },
    { label = "bad group macro",
      spec = { id = "bad-macro", enabled = true,
          groups = { group({ macro = "" }) } },
      reason = "groups_1_.macro" },
    { label = "non-finite orientation",
      spec = { id = "bad-angle", enabled = true,
          groups = { group({ pitch = math.huge }) } },
      reason = "groups_1_.pitch_must_be_a_finite_number" },
    { label = "remote without location",
      spec = { id = "remote-no-location", enabled = false,
          setup = {
              remote = true, shipMacro = "remote_ship_macro", shipLabel = "Remote Ship",
              turretGroup = "g", turretLabel = "Remote Group", expectedTurrets = 1,
          },
          groups = { group() } },
      reason = "remote_setup_requires_spec.location" },
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
    local rerun = harness.fix.buttonByText(ReadText(20992, 25))
    assert(rerun and rerun.handlers.onClick,
        "the Create control must still render with a malformed spec")
    rerun.handlers.onClick()
    assert(#scenarioEvents(harness) == 0,
        "forcing a malformed spec (" .. case.label .. ") must still spawn nothing")
    if case.reason then
        assert(harness.fix.logContains(case.reason),
            "rejecting " .. case.label .. " must log a useful validation reason")
    end
end

-- Safety and repair census must fail closed. The same small synthetic fixture
-- proves both the successful exact census and an unsafe result.
local function guardedScenario(id)
    return localScenario(id, {
        hostile = true,
        holdFire = true,
        repairGuard = true,
    })
end

do
    local harness = loadHarness(guardedScenario("guarded-ready"))
    harness.openFromGunnery({ label = "console", phase = "console" })
    local _, requestId = requestScenario(harness)
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        ready8(requestId, "guarded-ready", {
            spawned = 1, safeFixtures = 1, safeWeapons = 1,
            hostiles = 1, repairFixtures = 1,
        }))
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 1,
        "an exact safety/repair census must complete scenario setup")
    assert(harness.fix.logContains("repair_fixtures=1"),
        "READY must record the correlated repair-guard census")
end

do
    local harness = loadHarness(guardedScenario("guarded-unsafe"))
    harness.openFromGunnery({ label = "console", phase = "console" })
    local _, requestId = requestScenario(harness)
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        ready8(requestId, "guarded-unsafe", {
            spawned = 1, safeFixtures = 1, safeWeapons = 1, unsafeWeapons = 1,
            hostiles = 1, repairFixtures = 1,
        }))
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "an unsafe weapon census must keep Test Lab open")
    assert(harness.fix.logContains("unsafe_weapons=1"),
        "unsafe census failure must log the observed unsafe count")
end

-- A disabled synthetic scenario is inert until Create. Matching READY is
-- correlated by request/spec id, then and only then replaces the checked-group
-- state with the exact raw group and arms observation.
do
    local harness = loadHarness(localScenario("local-lifecycle"))
    assert(#scenarioEvents(harness) == 0, "a disabled setup spec must be inert on load")

    local session = harness.openFromGunnery({ label = "console", phase = "console" })
    local selectedKey = X4GunneryState.groupKey(5, "p", "g")
    session.staged[selectedKey] = nil
    session.checkedGroupKeys.extra = true
    session.staged.extra = { mode = "defend", preTickMode = "attack" }

    local events, requestId = requestScenario(harness)
    assert(#events == 3 and events[1].params.force == true and requestId:match("_1$"),
        "Create must force one correlated begin/group/commit stream")
    assert(session.checkedGroupKeys[selectedKey] == true and session.checkedGroupKeys.extra == true
            and session.staged.extra.mode == "defend",
        "preflight must not mutate checked or staged state")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "Test Lab must wait for matching acknowledgement")

    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:stale_1:local-lifecycle:1")
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:" .. requestId .. ":wrong-spec:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "stale-request and wrong-spec acknowledgements must be ignored")

    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:" .. requestId .. ":local-lifecycle:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 1,
        "matching complete acknowledgement must return to Gunnery exactly once")
    assert(session.checkedGroupKeys[selectedKey] == true and session.checkedGroupKeys.extra == nil,
        "successful acknowledgement must leave only the exact raw group selected")
    assert(session.staged[selectedKey] and session.staged[selectedKey].armed == false,
        "fresh exact-group selection must preserve its live disarmed state")

    local observing = false
    for _, event in ipairs(harness.fix.uiTriggeredEvents) do
        if event.control == "observe_toggle" and event.params.enabled == true then observing = true end
    end
    assert(observing, "successful scenario creation must arm reusable observation")
end

-- selectAll is a reusable activation mode. It must verify the complete member
-- macro multiset and select all mutable groups without retaining a single-group
-- selection.
do
    local harness = loadHarness({
        id = "select-all",
        enabled = false,
        setup = {
            shipMacro = "synthetic_ship_macro",
            shipLabel = "Synthetic Ship",
            turretGroup = "ignored",
            turretLabel = "Synthetic Turrets",
            selectAll = true,
            expectedTurrets = 2,
            expectedMemberMacros = { "weapon_a_macro", "weapon_b_macro" },
        },
        groups = { group() },
        stations = {},
    })
    local groupBuffer = {
        [0] = { path = "p", group = "g1", contextid = 5 },
        [1] = { path = "p", group = "g2", contextid = 5 },
    }
    harness.fix.ffiStub.new = function() return groupBuffer end
    harness.fix.C.GetNumUpgradeGroups = function() return 2 end
    harness.fix.C.GetUpgradeGroups2 = function() return 2 end
    harness.fix.C.GetUpgradeGroupInfo2 = function(_, _, _, _, rawGroup)
        if rawGroup == "g2" then
            return { count = 1, currentcomponent = 28, currentmacro = "weapon_b_macro",
                slotsize = "medium", total = 1, operational = 1 }
        end
        return { count = 1, currentcomponent = 27, currentmacro = "weapon_a_macro",
            slotsize = "medium", total = 1, operational = 1 }
    end
    harness.fix.C.GetNumUpgradeSlots = function() return 2 end
    harness.fix.C.GetUpgradeSlotCurrentComponent = function(_, _, slot)
        return slot == 1 and 27 or 28
    end
    harness.fix.C.GetUpgradeSlotGroup = function(_, _, _, slot)
        return { path = "p", group = slot == 1 and "g1" or "g2" }
    end
    GetComponentData = function(component, field)
        if field == "macro" then
            local id = tonumber(component)
            if id == 27 then return "weapon_a_macro" end
            if id == 28 then return "weapon_b_macro" end
            return "synthetic_ship_macro"
        end
        if field == "isplayerowned" then return true end
    end
    harness.fix.C.GetComponentName = function(component)
        local id = tonumber(component)
        if id == 27 then return "Weapon A" end
        if id == 28 then return "Weapon B" end
        return "Synthetic Ship"
    end

    local session = harness.openFromGunnery({ label = "console", phase = "console" })
    local _, requestId = requestScenario(harness)
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:" .. requestId .. ":select-all:1")

    local key1 = X4GunneryState.groupKey(5, "p", "g1")
    local key2 = X4GunneryState.groupKey(5, "p", "g2")
    local count = 0
    for key in pairs(session.checkedGroupKeys or {}) do
        count = count + 1
        assert(key == key1 or key == key2,
            "selectAll must not retain unrelated checked groups")
    end
    assert(count == 2 and session.checkedGroupKeys[key1] and session.checkedGroupKeys[key2],
        "selectAll must activate every verified mutable group")
    assert(session.selectedGroupKey == nil,
        "selectAll activation must not claim one exact group as the selected group")
end

-- Replacing an engaged fixture must suppress the parked aim target that MD just
-- destroyed. Observation resumes only after Gunnery reports a distinct target.
do
    local harness = loadHarness(localScenario("stale-observe-target"))
    local session = harness.openFromGunnery({
        label = "Direct engaged", phase = "engaged", controlMode = "direct", direct = true,
    })
    session.aimTargetID = 9001
    local _, requestId = requestScenario(harness)
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:" .. requestId .. ":stale-observe-target:1")

    local staleState, staleMark = false, false
    for _, event in ipairs(harness.fix.uiTriggeredEvents) do
        if event.control == "observe_state" and event.params.aimtgt == 9001 then staleState = true end
        if event.control == "observe_mark" then staleMark = true end
    end
    assert(not staleState and not staleMark,
        "READY must not publish or mark the destroyed pre-replacement aim target")

    session.aimTargetID = 9002
    local callback = harness.fix.pendingCallbacks[#harness.fix.pendingCallbacks]
    assert(callback, "arming observation must schedule its next state push")
    harness.fix.runCallback(callback)
    local newState, newMark = false, false
    for _, event in ipairs(harness.fix.uiTriggeredEvents) do
        if event.control == "observe_state" and event.params.aimtgt == 9002 then newState = true end
        if event.control == "observe_mark" then newMark = true end
    end
    assert(newState and newMark,
        "a distinct post-replacement aim target must resume state and automatic capture")
end

-- Consecutive Test Lab Lua lifetimes may clear every Lua global. Engine real
-- time still advances, so their first request IDs cannot collide.
do
    local function firstRequestId(realTime)
        local harness = loadHarness(localScenario("generation"), realTime)
        harness.openFromGunnery({ label = "console", phase = "console" })
        local _, requestId = requestScenario(harness)
        return requestId
    end
    X4GunneryTestLabRuntime = nil
    local first = firstRequestId(100.125)
    X4GunneryTestLabRuntime = nil
    local second = firstRequestId(101.250)
    assert(first ~= second and first:match("_1$") and second:match("_1$"),
        "consecutive UI lifetimes must generate distinct first-request IDs")
end

-- Wrong preflight identity must not despawn anything or alter the operator's
-- selection.
do
    local spec = localScenario("preflight-guard")
    spec.setup.shipLabel = "Required Ship"
    local harness = loadHarness(spec)
    local session = harness.openFromGunnery({ label = "console", phase = "console" })
    local before = {}
    for key, value in pairs(session.checkedGroupKeys) do before[key] = value end
    harness.fix.buttonByText(ReadText(20992, 25)).handlers.onClick()
    assert(#scenarioEvents(harness) == 0,
        "wrong exact ship identity must fail before any scenario event")
    for key, value in pairs(before) do
        assert(session.checkedGroupKeys[key] == value,
            "preflight failure must preserve checked groups")
    end
end

-- Partial census acknowledgement is consumed as a failure and leaves the parked
-- Gunnery selection untouched.
do
    local harness = loadHarness(localScenario("ack-count-guard", { count = 2 }))
    local session = harness.openFromGunnery({ label = "console", phase = "console" })
    session.checkedGroupKeys.extra = true
    session.staged.extra = { mode = "defend", preTickMode = "attack" }
    local _, requestId = requestScenario(harness)
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:" .. requestId .. ":ack-count-guard:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "partial spawn acknowledgement must keep Test Lab open")
    assert(harness.fix.logContains("action=failed"),
        "partial spawn acknowledgement must emit a machine-readable failure")
    assert(session.checkedGroupKeys.extra == true and session.staged.extra.mode == "defend",
        "partial acknowledgement must preserve checked and staged state")
end

-- Missing acknowledgement has a bounded timeout and preserves the parked state.
do
    local now = 0
    local harness = loadHarness(localScenario("ack-timeout"))
    getElapsedTime = function() return now end
    local session = harness.openFromGunnery({ label = "console", phase = "console" })
    session.checkedGroupKeys.extra = true
    session.staged.extra = { mode = "defend", preTickMode = "attack" }
    requestScenario(harness)
    now = 11
    harness.testMenu.onUpdate()
    assert(harness.fix.logContains("action=timeout"),
        "missing spawn acknowledgement must produce a bounded timeout")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "spawn timeout must keep Test Lab open")
    assert(session.checkedGroupKeys.extra == true and session.staged.extra.mode == "defend",
        "spawn timeout must preserve checked and staged state")
end

-- Exact-group membership is revalidated after MD creation. A changed loadout
-- cannot mutate the parked selection even when the ship count is correct.
do
    local harness = loadHarness(localScenario("group-changed"))
    local session = harness.openFromGunnery({ label = "console", phase = "console" })
    session.checkedGroupKeys.extra = true
    session.staged.extra = { mode = "defend", preTickMode = "attack" }
    local _, requestId = requestScenario(harness)
    harness.fix.C.IsComponentOperational = function() return false end
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:" .. requestId .. ":group-changed:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 0,
        "changed exact-group membership must keep Test Lab open")
    assert(session.checkedGroupKeys.extra == true and session.staged.extra.mode == "defend",
        "changed membership must preserve checked and staged state")
end

-- Despawn is disabled while creation is pending; a stale handler must not break
-- request correlation.
do
    local harness = loadHarness(localScenario("pending-despawn"))
    harness.openFromGunnery({ label = "console", phase = "console" })
    local _, requestId = requestScenario(harness)
    local despawn = harness.fix.buttonByText(ReadText(20992, 26))
    assert(despawn.active == false, "Despawn must be disabled while creation is pending")
    local before = #scenarioEvents(harness)
    despawn.handlers.onClick()
    assert(#scenarioEvents(harness) == before
            and harness.fix.logContains("reason=creation_pending"),
        "a stale pending Despawn handler must send no cleanup event")
    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:" .. requestId .. ":pending-despawn:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 1,
        "rejected pending Despawn must preserve the matching READY handoff")
end

-- Outside an occupied remote shooter, Despawn remains available and emits one
-- cleanup event.
do
    local harness = loadHarness(localScenario("safe-despawn"))
    harness.openFromGunnery({ label = "console", phase = "console" })
    local despawn = harness.fix.buttonByText(ReadText(20992, 26))
    assert(despawn and despawn.active == true,
        "Despawn must be active when the player is not inside a protected remote shooter")
    local before = #scenarioEvents(harness)
    despawn.handlers.onClick()
    local events = scenarioEvents(harness)
    assert(#events == before + 1 and events[#events].control == "despawn_scenario",
        "active Despawn must emit exactly one cleanup event")
end

-- Remote lifecycle is synthetic: Create from a safe launcher, wait for teleport,
-- activate only after exact ship/group resolution, and re-check occupancy in
-- stale Create/Despawn handlers.
do
    local harness = loadHarness({
        id = "remote-lifecycle",
        enabled = false,
        location = { sectorMacro = "synthetic_sector_macro", x = 100, y = 200, z = 300 },
        setup = {
            remote = true,
            shipMacro = "remote_ship_macro",
            shipLabel = "Remote Ship",
            turretGroup = "g",
            turretLabel = "Remote Group",
            expectedTurrets = 1,
        },
        groups = { group() },
        stations = {},
    })
    harness.openFromGunnery({ label = "safe launcher", phase = "console" })
    local events, requestId = requestScenario(harness)
    assert(events[1].params.sectorMacro == "synthetic_sector_macro"
            and events[1].params.anchorX == 100
            and events[1].params.anchorY == 200
            and events[1].params.anchorZ == 300,
        "remote begin must transport its synthetic flat location")

    harness.fix.fireEvent("X4GunneryTestLab.ScenarioReady",
        "x4gct1:" .. requestId .. ":remote-lifecycle:1")
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 1
            and harness.fix.logContains("action=remote_ready"),
        "remote READY must return to the safe launcher for teleport")

    harness.testMenu.onShowMenu()
    local createWaiting = harness.fix.buttonByText(ReadText(20992, 25))
    local despawnSafe = harness.fix.buttonByText(ReadText(20992, 26))
    assert(createWaiting and createWaiting.active == false,
        "Create must remain disabled while a remote fixture waits for teleport")
    assert(despawnSafe and despawnSafe.active == true,
        "Despawn must remain available from the safe launcher")
    local staleSafeDespawn = despawnSafe.handlers.onClick
    local before = #scenarioEvents(harness)
    createWaiting.handlers.onClick()
    assert(#scenarioEvents(harness) == before
            and harness.fix.logContains("reason=remote_fixture_already_active"),
        "a stale Create handler must reject a second remote fixture")

    GetComponentData = function(component, field)
        if field == "macro" then
            if tonumber(component) == 27 then return "remote_weapon_macro" end
            return "remote_ship_macro"
        end
        if field == "isplayerowned" then return true end
    end
    harness.fix.C.GetComponentName = function(component)
        if tonumber(component) == 27 then return "Remote Weapon" end
        return "Remote Ship"
    end

    harness.fix.gcMenu.onShowMenu()
    harness.fix.gcMenu.display()
    harness.fix.buttonByText(ReadText(20991, 32)).handlers.onClick()
    harness.testMenu.onShowMenu()
    assert(harness.countHandoffs("X4GunneryTestLab", "X4GunneryMenu") == 2
            and harness.fix.logContains("event=scenario_activate")
            and harness.fix.logContains("action=ready"),
        "opening Test Lab aboard the exact remote shooter must activate its group once")

    harness.testMenu.onShowMenu()
    local createAboard = harness.fix.buttonByText(ReadText(20992, 25))
    local despawnAboard = harness.fix.buttonByText(ReadText(20992, 26))
    assert(createAboard and createAboard.active == false,
        "Create must be disabled aboard the protected remote shooter")
    assert(despawnAboard and despawnAboard.active == false,
        "Despawn must be disabled aboard the protected remote shooter")
    before = #scenarioEvents(harness)
    createAboard.handlers.onClick()
    despawnAboard.handlers.onClick()
    staleSafeDespawn()
    assert(#scenarioEvents(harness) == before
            and harness.fix.logContains("reason=occupied_remote_shooter"),
        "current and stale remote handlers must re-check occupied-shooter safety")
end

print("testlab lifecycle scenario tests passed")
