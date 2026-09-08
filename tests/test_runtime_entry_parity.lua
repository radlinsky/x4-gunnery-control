-- Issue #118 Task 3: physical-console and Map entry converge on the same
-- onboard lifecycle after the source-backed control-position release.

local function installOneGroup(fix)
    local groupBuffer = { [0] = { path = "p", group = "g", contextid = 5 } }
    fix.C.GetNumUpgradeGroups = function() return 1 end
    fix.C.GetUpgradeGroups2 = function() return 1 end
    fix.C.GetUpgradeGroupInfo2 = function()
        return {
            count = 1, currentcomponent = 27, currentmacro = "", slotsize = "",
            total = 1, operational = 1,
        }
    end
    fix.C.IsComponentOperational = function() return true end
    fix.ffiStub.new = function() return groupBuffer end
end

local function setup(initialControl)
    local fix = dofile("tests/support/runtime_fixture.lua").load()
    local env = {
        fix = fix,
        State = X4GunneryState,
        control = initialControl or "cockpit",
        ship = 42,
        owned = true,
        opens = {},
    }

    fix.C.GetPlayerCurrentControlGroup = function() return env.control end
    fix.C.GetPlayerOccupiedShipID = function() return env.ship end
    fix.C.GetContextByClass = function() return env.ship end
    fix.C.IsComponentClass = function() return true end
    GetComponentData = function(_, key)
        if key == "isplayerowned" then return env.owned end
        return nil
    end
    installOneGroup(fix)
    Helper.getMenu = function() return nil end
    OpenMenu = function(name)
        env.opens[#env.opens + 1] = name
    end
    return env
end

local function releaseEvents(fix)
    local found = {}
    for _, event in ipairs(fix.uiTriggeredEvents) do
        if event.screen == "X4GunneryControl" and event.control == "chair_release" then
            found[#found + 1] = event
        end
    end
    return found
end

local function requestChairRelease(env)
    local fix = env.fix
    fix.resetUITriggeredEvents()
    local mark = fix.callbackCheckpoint()
    -- UI Extensions and gameplanchange can both report the same ingress. The
    -- Lua-side redirectPending guard must collapse duplicates in the deferred
    -- redirect window before MD applies its own one-shot pending guard.
    fix.fireUIEvent("gameplanchange", "cockpit")
    fix.fireUIEvent("gameplanchange", "cockpit")
    fix.drainCallbacksSince(mark)

    local releases = releaseEvents(fix)
    assert(#releases == 1,
        "duplicate physical ingress must emit one chair_release during the redirect window; got "
        .. tostring(#releases))
    assert(releases[1].params.ship == 42,
        "chair_release must carry the exact observed ship; got "
        .. tostring(releases[1].params.ship))
    assert(fix.API.getSession() == nil,
        "physical ingress must not create a Gunnery session before stopped-control completion")
    return releases[1]
end

local function assertParkedOnboard(env, label)
    local session = env.fix.API.getSession()
    assert(session, label .. ": expected onboard session")
    assert(session.origin == "onboard", label .. ": origin must be onboard")
    assert(session.lifecycle == env.State.lifecycle.suspendedMap,
        label .. ": entry must park at suspendedMap before reopen")
    assert(env.State.normID(session.shipID) == "42",
        label .. ": session must retain ship 42; got " .. tostring(session.shipID))
    assert(#session.groups == 1, label .. ": expected the same one usable turret group")
    assert(next(session.committedBaseline or {}) ~= nil,
        label .. ": onboard ingress must seed the committed baseline before reopen")
    return session
end

local function reopenParkedOnboard(env, label)
    env.opens = {}
    env.fix.API.runSessionWatchdog()
    assert(#env.opens == 1 and env.opens[1] == "X4GunneryMenu",
        label .. ": parked onboard session must request exactly one Gunnery reopen")
    local session = env.fix.API.getSession()
    assert(session and session.lifecycle == env.State.lifecycle.reopening,
        label .. ": watchdog reopen must transition to reopening")
    env.fix.gcMenu.onShowMenu()
    session = env.fix.API.getSession()
    assert(session and session.origin == "onboard"
            and session.lifecycle == env.State.lifecycle.owned,
        label .. ": displayed session must converge to owned onboard lifecycle")
    return session
end

local function leaveOnboard(env, label)
    local getUpCalls = 0
    env.fix.C.GetUp = function()
        getUpCalls = getUpCalls + 1
        return true
    end
    local mark = env.fix.callbackCheckpoint()
    env.fix.gcMenu.onCloseElement("close")
    assert(env.fix.API.getSession() == nil, label .. ": exit must discard the onboard session")
    assert(getUpCalls == 0, label .. ": onboard exit must not call GetUp()")
    env.fix.drainCallbacksSince(mark)
    env.fix.gcMenu.shown = false
end

-- ── A. Physical release and normal Map ingress converge before and after reopen ──
do
    local physical = setup("gunnercontrol")
    local release = requestChairRelease(physical)
    -- Model the source-backed MD completion boundary: leave_control_position has
    -- completed, event_player_stopped_control fired, and MD raises OpenOnboard.
    physical.control = "cockpit"
    physical.fix.fireEvent("X4GunneryControl.OpenOnboard", release.params.ship)
    local physicalParked = assertParkedOnboard(physical, "physical route")

    -- A duplicate completion event must not replace the accepted session.
    physical.fix.fireEvent("X4GunneryControl.OpenOnboard", release.params.ship)
    assert(physical.fix.API.getSession() == physicalParked,
        "duplicate OpenOnboard completion must not replace the live onboard session")

    local map = setup("cockpit")
    map.fix.fireEvent("X4GunneryControl.OpenOnboard", 42)
    local mapParked = assertParkedOnboard(map, "Map route")

    assert(physicalParked.origin == mapParked.origin
            and physicalParked.lifecycle == mapParked.lifecycle
            and physical.State.normID(physicalParked.shipID) == map.State.normID(mapParked.shipID)
            and #physicalParked.groups == #mapParked.groups,
        "physical and Map routes must converge on the same parked onboard state")

    local physicalOwned = reopenParkedOnboard(physical, "physical route")
    local mapOwned = reopenParkedOnboard(map, "Map route")
    assert(physicalOwned.origin == mapOwned.origin
            and physicalOwned.lifecycle == mapOwned.lifecycle,
        "physical and Map routes must converge on the same owned onboard lifecycle")
end

-- ── B. Context drift cancels the handoff instead of opening a stale session ────
do
    local beforeCompletion = setup("gunnercontrol")
    local release = requestChairRelease(beforeCompletion)
    beforeCompletion.control = "cockpit"
    beforeCompletion.ship = 99
    beforeCompletion.fix.fireEvent("X4GunneryControl.OpenOnboard", release.params.ship)
    assert(beforeCompletion.fix.API.getSession() == nil,
        "OpenOnboard must refuse a release completion after the player changed ships")

    local afterCompletion = setup("gunnercontrol")
    local accepted = requestChairRelease(afterCompletion)
    afterCompletion.control = "cockpit"
    afterCompletion.fix.fireEvent("X4GunneryControl.OpenOnboard", accepted.params.ship)
    assertParkedOnboard(afterCompletion, "drift-after-completion")
    afterCompletion.ship = 99
    afterCompletion.fix.API.runSessionWatchdog()
    assert(afterCompletion.fix.API.getSession() == nil,
        "parked onboard handoff must be cancelled if ship context drifts before reopen")
    assert(#afterCompletion.opens == 0,
        "context-drifted handoff must not request Gunnery reopen")
end

-- ── C. Exit and re-entry remain equivalent through both natural launchers ─────
do
    local env = setup("gunnercontrol")

    local release1 = requestChairRelease(env)
    env.control = "cockpit"
    env.fix.fireEvent("X4GunneryControl.OpenOnboard", release1.params.ship)
    assertParkedOnboard(env, "physical first entry")
    reopenParkedOnboard(env, "physical first entry")
    leaveOnboard(env, "physical first exit")

    -- Re-enter through the normal Map/right-click path while standing.
    env.control = "cockpit"
    env.ship = 42
    env.owned = true
    env.fix.fireEvent("X4GunneryControl.OpenOnboard", 42)
    assertParkedOnboard(env, "Map re-entry")
    reopenParkedOnboard(env, "Map re-entry")
    leaveOnboard(env, "Map re-entry exit")

    -- Re-enter through the physical console again. The prior onboard sessions
    -- must not leave state that blocks or changes the release handoff.
    env.control = "gunnercontrol"
    local release2 = requestChairRelease(env)
    env.control = "cockpit"
    env.fix.fireEvent("X4GunneryControl.OpenOnboard", release2.params.ship)
    assertParkedOnboard(env, "physical re-entry")
    reopenParkedOnboard(env, "physical re-entry")
end

print("Issue #118 entry parity runtime tests passed")
