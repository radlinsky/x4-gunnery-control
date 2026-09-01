-- Test Lab close ownership: operator exits return to the parked Gunnery menu,
-- while player-context/load teardown closes without resurrecting it.
-- Scenario creation/acknowledgement behavior lives in
-- test_testlab_lifecycle_scenario.lua.

local function loadHarness()
    -- This file builds several isolated runtimes in one Lua process. require()
    -- otherwise retains the first fixture's ffi table, so later C write spies
    -- would observe a different table from gunnery_control.lua.
    package.loaded["ffi"] = nil
    local fix = dofile("tests/support/runtime_fixture.lua").load()
    GetCurRealTime = function() return 0 end
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
    -- The live scenario file is mutable operator input and irrelevant to menu
    -- ownership. Keep this regression isolated from whatever live fixture is
    -- currently authored.
    X4GunneryTestLabScenarioSpec = nil
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

print("testlab lifecycle tests passed")
