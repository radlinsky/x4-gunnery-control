-- test_runtime_lifecycle.lua
-- Chair ingress/egress, Map, menu ownership, notify events, teardown, startAutoEngage.

local fix = dofile("tests/support/runtime_fixture.lua").load()
local gcMenu = fix.gcMenu
local API    = fix.API
local C      = fix.C

-- A reusable group used across several lifecycle tests.
local grp27 = fix.makeGroup{
    key = "grp27", displayName = "G27",
    members = { { componentID = 27, displayName = "T1", operational = true,
                  cameraSupported = true, componentKey = "27" } },
}

-- ── 36. get-up discards the session now but closes the frames a tick later ───
-- Vanilla closes from the playerGetUp event rather than inside its Get Up
-- handler (menu_docked.lua:283,1442); closing synchronously unregisters our
-- view in the middle of the engine's get-up transition.
gcMenu.onShowMenu()
local sess36 = API.getSession()
assert(sess36 ~= nil, "expected session for teardown ordering test")
sess36.phase = "console"
local mark36 = fix.callbackCheckpoint()
fix.resetCloseMenuCalls()
gcMenu.onCloseElement("close")
assert(API.getSession() == nil, "get-up must discard the session immediately")
assert(fix.getCloseMenuCalls() == 0,
    "get-up must not close the frames in the same call as GetUp(); closeMenu ran "
    .. tostring(fix.getCloseMenuCalls()) .. " time(s)")
fix.drainCallbacksSince(mark36)
assert(fix.getCloseMenuCalls() == 1,
    "the deferred callback must close the menu exactly once; got " .. tostring(fix.getCloseMenuCalls()))

-- ── 37. teardown must not unregister our views before closing the menu ───────
-- helper.lua's closeMenu() untracks the menu first (C.RemoveTrackedMenu) and
-- only then lets clearMenu() unregister the views (helper.lua:1908-1947).
-- Unregistering first hid the view while the menu was still tracked, and after
-- a session that opened a playerControls frame the engine then stopped
-- delivering Esc to the game menu until another menu opened and closed.
gcMenu.onShowMenu()
local sess37 = API.getSession()
assert(sess37 ~= nil, "expected session for teardown order test")
sess37.groups = { grp27 }
sess37.checkedGroupKeys = { ["grp27"] = true }
sess37.phase = "engaged"
sess37.controlMode = "direct"
sess37.directSnapshots = {}
sess37.cameraMemberID = 27
sess37.targetObjectID = 500
gcMenu.display()
assert(fix.getFrameCount() == 2, "precondition: two frames must be registered")
fix.resetTeardownTrace()
local mark37 = fix.callbackCheckpoint()
gcMenu.onCloseElement("close")
fix.drainCallbacksSince(mark37)
local trace37 = fix.getTeardownTrace()
assert(trace37[1] == "close",
    "get-up must close the menu before touching its views; trace was "
    .. table.concat(trace37, ","))

-- ── 38. every frame agrees on keepHUDVisible and paints a background ─────────
-- X4 exposes no HUD setter: a frame that replaces another on the same layer
-- with a different keepHUDVisible leaves the standing player with no HUD, and
-- nothing can turn it back on. The value must be true on every frame the menu
-- ever builds, in every phase. The background is what keeps cell text legible
-- over the live view.
local allFrames = fix.allFrames
assert(#allFrames >= 3, "expected several frames across the phases exercised above")
for i, record in ipairs(allFrames) do
    assert(record.props.keepHUDVisible == true,
        "frame #" .. i .. " (layer " .. tostring(record.props.layer) .. ") must set "
        .. "keepHUDVisible = true; got " .. tostring(record.props.keepHUDVisible))
    assert(record.background,
        "frame #" .. i .. " (layer " .. tostring(record.props.layer)
        .. ") must call setBackground so its cell text stays readable")
end

-- ── 44. leaveChair emits a notify UI event; text depends on direct snapshots ──
-- X4 engine bug: SetPlayerCameraTargetView from a turret seat leaves Esc dead
-- after the player gets up. The only observed cure is a menu that calls
-- CreateView/DisplayView (View.createView in ego_viewhelper). The helptext
-- popup emitted here is a real user-facing feature AND is the confirmed cure
-- mechanism: show_help forces that path in MD. Do NOT make this popup
-- conditional or suppress it without re-testing Esc after a camera session.
--
-- 44a: direct snapshots were held -> restored-settings text (text id 79).
-- 44b: no direct snapshots         -> disengaged text (text id 80).

C.GetSofttarget2 = function() return { softtargetID = 0, softtargetConnectionName = "" } end
C.GetContextByClass = function(...) return 42 end

-- 44a: session WITH direct snapshots.
local capturedEvents44 = {}
gcMenu.onShowMenu()
local sess44a = API.getSession()
assert(sess44a ~= nil, "expected session for notify test (44a)")
sess44a.phase = "console"
sess44a.controlMode = "direct"
AddUITriggeredEvent = function(screen, control, params)
    capturedEvents44[#capturedEvents44 + 1] = { screen = screen, control = control, params = params }
end
gcMenu.onCloseElement("close")
local notifyEvA = nil
for _, e in ipairs(capturedEvents44) do
    if e.screen == "X4GunneryControl" and e.control == "notify" then notifyEvA = e; break end
end
assert(notifyEvA ~= nil,
    "leaveChair must emit AddUITriggeredEvent('X4GunneryControl','notify',...) when in direct mode")
assert(type(notifyEvA.params) == "table",
    "notify event params must be a table")
assert(notifyEvA.params["text"] == ReadText(20991, 79),
    "notify text with direct controlMode must be ReadText(20991, 79) (restored-settings); got: "
    .. tostring(notifyEvA.params["text"]))

-- 44b: session WITHOUT direct snapshots.
local capturedEvents44b = {}
gcMenu.onShowMenu()
local sess44b = API.getSession()
assert(sess44b ~= nil, "expected session for notify test (44b)")
sess44b.phase = "console"
-- controlMode is nil by default from onShowMenu.
AddUITriggeredEvent = function(screen, control, params)
    capturedEvents44b[#capturedEvents44b + 1] = { screen = screen, control = control, params = params }
end
gcMenu.onCloseElement("close")
local notifyEvB = nil
for _, e in ipairs(capturedEvents44b) do
    if e.screen == "X4GunneryControl" and e.control == "notify" then notifyEvB = e; break end
end
assert(notifyEvB ~= nil,
    "leaveChair must emit AddUITriggeredEvent('X4GunneryControl','notify',...) when not in direct mode")
assert(notifyEvB.params["text"] == ReadText(20991, 80),
    "notify text without direct snapshots must be ReadText(20991, 80) (disengaged); got: "
    .. tostring(notifyEvB.params["text"]))

-- ── 45. playerGetUp route emits the notify exactly once ─────────────────────
-- endForMovement (registered on playerGetUp/playerUndock) sets seatLeaving=true,
-- calls endSession -> discardSession, then clears seatLeaving. discardSession
-- must emit the notify under that seatLeaving=true guard.
-- Mutation check: verify notify is emitted (would fail if seatLeaving guard
-- were inverted or if the emission were accidentally removed from discardSession).
local capturedEvents45 = {}
gcMenu.onShowMenu()
local sess45 = API.getSession()
assert(sess45 ~= nil, "expected session for playerGetUp notify test (45)")
sess45.phase = "console"
sess45.directSnapshots = {}
AddUITriggeredEvent = function(screen, control, params)
    capturedEvents45[#capturedEvents45 + 1] = { screen = screen, control = control, params = params }
end
assert(type(X4GunneryControlAPI.endForMovement) == "function",
    "X4GunneryControlAPI.endForMovement must be exposed for testing")
X4GunneryControlAPI.endForMovement()
local notifyEvts45 = {}
for _, e in ipairs(capturedEvents45) do
    if e.screen == "X4GunneryControl" and e.control == "notify" then
        notifyEvts45[#notifyEvts45 + 1] = e
    end
end
assert(#notifyEvts45 == 1,
    "playerGetUp route must emit exactly one notify event; got " .. tostring(#notifyEvts45))
assert(notifyEvts45[1].params["text"] == ReadText(20991, 80),
    "playerGetUp with no direct snapshots must use disengaged text (80); got: "
    .. tostring(notifyEvts45[1].params["text"]))

-- ── 46. playerUndock route emits the notify too ──────────────────────────────
-- Same endForMovement handler is registered for both events, so this verifies
-- the shared path covers undock as well.
-- Mutation check: assert exactly one notify (would catch accidental double-emit
-- if the emission were also left in leaveChair, which the playerGetUp path
-- does NOT go through).
local capturedEvents46 = {}
gcMenu.onShowMenu()
local sess46 = API.getSession()
assert(sess46 ~= nil, "expected session for playerUndock notify test (46)")
sess46.phase = "console"
sess46.directSnapshots = {}
AddUITriggeredEvent = function(screen, control, params)
    capturedEvents46[#capturedEvents46 + 1] = { screen = screen, control = control, params = params }
end
X4GunneryControlAPI.endForMovement()   -- same handler; reuse the same exposure
local notifyEvts46 = {}
for _, e in ipairs(capturedEvents46) do
    if e.screen == "X4GunneryControl" and e.control == "notify" then
        notifyEvts46[#notifyEvts46 + 1] = e
    end
end
assert(#notifyEvts46 == 1,
    "playerUndock route must emit exactly one notify event; got " .. tostring(#notifyEvts46))

-- ── 47. stale-session discardSession (seatLeaving=false) emits NO notify ─────
-- The "stale session before chair redirect" call in the gameplanchange handler
-- calls discardSession without ever setting seatLeaving=true. The player has
-- just sat down; a popup would be wrong and confusing.
-- Mutation check: this is the NEGATIVE case. If the seatLeaving guard were
-- removed from discardSession the assert below would catch it.
local capturedEvents47 = {}
gcMenu.onShowMenu()
local sess47 = API.getSession()
assert(sess47 ~= nil, "expected session for stale-session no-notify test (47)")
sess47.phase = "console"
-- Reach discardSession with seatLeaving=false by using a fresh onShowMenu,
-- which recreates the session (triggering "stale session at chair ingress" ->
-- discardSession without touching seatLeaving).
-- First set up a map-suspended session to ensure a discard path that bypasses
-- leaveChair: use X4GunneryState.lifecycle.owned with autoHideAt set so the
-- watchdog would call discardSession, but to be deterministic call via
-- onShowMenu (which discards a stale session with seatLeaving still false).
-- Simplest approach: set the session to a state that onShowMenu will discard
-- (different ship), confirming the "stale session before chair redirect" path.
AddUITriggeredEvent = function(screen, control, params)
    capturedEvents47[#capturedEvents47 + 1] = { screen = screen, control = control, params = params }
end
sess47.shipID = 9999   -- force mismatch so onShowMenu discards it
gcMenu.onShowMenu()
local notifyEvts47 = {}
for _, e in ipairs(capturedEvents47) do
    if e.screen == "X4GunneryControl" and e.control == "notify" then
        notifyEvts47[#notifyEvts47 + 1] = e
    end
end
assert(#notifyEvts47 == 0,
    "discardSession with seatLeaving=false must NOT emit notify; got "
    .. tostring(#notifyEvts47) .. " notify event(s). "
    .. "The seatLeaving guard in discardSession is broken or missing.")

-- ── 48. exactly one notify per teardown; double teardown does not double-emit ─
-- leaveChair calls C.GetUp(), which in-game also fires playerGetUp, so
-- endForMovement runs again for the same session. The session/epoch guards make
-- the second call a no-op (session is already nil after discardSession). Assert
-- that explicitly: endForMovement called immediately after an already-discarded
-- session emits zero notify events.
local capturedEvents48 = {}
gcMenu.onShowMenu()
local sess48 = API.getSession()
assert(sess48 ~= nil, "expected session for double-teardown test (48)")
sess48.phase = "console"
sess48.directSnapshots = {}
AddUITriggeredEvent = function(screen, control, params)
    capturedEvents48[#capturedEvents48 + 1] = { screen = screen, control = control, params = params }
end
-- First teardown via endForMovement (simulates playerGetUp route).
X4GunneryControlAPI.endForMovement()
local firstPassEvts = {}
for _, e in ipairs(capturedEvents48) do
    if e.screen == "X4GunneryControl" and e.control == "notify" then
        firstPassEvts[#firstPassEvts + 1] = e
    end
end
assert(#firstPassEvts == 1,
    "first endForMovement call must emit exactly one notify; got " .. tostring(#firstPassEvts))
-- Second teardown with no session (simulates the in-game double-fire of playerGetUp).
capturedEvents48 = {}
X4GunneryControlAPI.endForMovement()
local secondPassEvts = {}
for _, e in ipairs(capturedEvents48) do
    if e.screen == "X4GunneryControl" and e.control == "notify" then
        secondPassEvts[#secondPassEvts + 1] = e
    end
end
assert(#secondPassEvts == 0,
    "second endForMovement after session is already nil must emit zero notify events; "
    .. "the epoch/session guard is broken. Got " .. tostring(#secondPassEvts))

-- ── 50. startAutoEngage failure path clears controlMode ──────────────────────
-- Regression: beginEngaged sets session.controlMode = "auto" before trying to
-- enter the camera. When no operational camera member exists, the old code did
-- `session.phase = "console"; return false`, leaving controlMode stuck on "auto"
-- while phase said "console". returnToConsole() must be used instead so phase,
-- controlMode, povMode, cameraMemberID, and targetObjectID are all cleared together.
gcMenu.onShowMenu()
local sess50 = API.getSession()
assert(sess50 ~= nil, "expected session for startAutoEngage failure test (50)")
-- Build a group with NO operational members so cameraMember() returns nil and
-- startAutoEngage hits its first failure exit.
local grp50 = fix.makeGroup{
    key = "grp50", componentID = 30, displayName = "Empty Group", operationalCount = 0,
    members = { { componentID = 30, displayName = "T1", operational = false,
                  cameraSupported = false, componentKey = "30" } },
}
sess50.groups = { grp50 }
sess50.checkedGroupKeys = { ["grp50"] = true }
sess50.phase = "console"
sess50.controlMode = nil
-- Same arguments the console Auto-Engage button passes. startAutoEngage is
-- module-local; TestAPI exposes it, like TestAPI.endForMovement above.
local engaged50 = API.startAutoEngage(X4GunneryState.checkedGroups(sess50))
assert(engaged50 == false,
    "startAutoEngage with no operational camera member must return false; got "
    .. tostring(engaged50))
-- After the failure, phase must be "console" and controlMode must be nil.
assert(sess50.phase == "console",
    "startAutoEngage failure path must leave phase='console'; got '"
    .. tostring(sess50.phase) .. "'")
assert(sess50.controlMode == nil,
    "BUG: startAutoEngage failure path left controlMode='"
    .. tostring(sess50.controlMode)
    .. "'; State.returnToConsole must be used instead of raw phase assignment")

-- ── 55 (hookTimeoutMessage). missing kuertee UI Extensions is reported, not silent ────
-- UI Extensions is an optional dependency (its extension id differs between the
-- Nexus and Workshop releases, so a hard one disables us for half of installs).
-- Without it registerCallback is absent and the Map-reopen hook never lands; the
-- only thing standing between the player and a mod that quietly half-works is
-- this log line.
do
    local missing = API.hookTimeoutMessage({})
    assert(missing:find("UI Extensions is not loaded", 1, true),
        "a DockedMenu without registerCallback means UI Extensions is missing; got: " .. missing)
    -- A menu that does have registerCallback timed out for some other reason;
    -- blaming UI Extensions there would send players chasing the wrong fix.
    local other = API.hookTimeoutMessage({ registerCallback = function() end })
    assert(not other:find("UI Extensions", 1, true),
        "a hooked DockedMenu must not be blamed on UI Extensions; got: " .. other)
    assert(API.hookTimeoutMessage(nil):find("timed out", 1, true),
        "no DockedMenu at all is still a plain timeout")
end

-- ── 118. physical-chair ingress probes the real Map/onboard lifecycle ────────
-- This temporary experiment closes DockedMenu, opens the real MapMenu, and
-- immediately reuses onOpenOnboard so the existing suspended-Map lifecycle
-- owns the handoff. DockedMenu cleanup must not independently open Gunnery.
do
    local fix118 = dofile("tests/support/runtime_fixture.lua").load()

    local trace, mapOpens, gunneryOpens = {}, 0, 0
    OpenMenu = function(name)
        if name == "MapMenu" then
            mapOpens = mapOpens + 1
            trace[#trace + 1] = "map_open"
        elseif name == "X4GunneryMenu" then
            gunneryOpens = gunneryOpens + 1
            trace[#trace + 1] = "gunnery_open"
        end
    end
    local closeArgs
    Helper.closeMenu = function(m, reason, a, b)
        trace[#trace + 1] = "close"
        closeArgs = { m = m, reason = reason, a = a, b = b }
    end

    -- Stands in for UI Extensions: each host menu records the lifecycle hook
    -- registered by registerUIHooks and fires it from its cleanup.
    local dockedCleanupHooks, mapCleanupHooks = {}, {}
    local docked = {
        name = "DockedMenu",
        registerCallback = function(event, fn)
            if event == "cleanup" then
                dockedCleanupHooks[#dockedCleanupHooks + 1] = fn
            end
        end,
        cleanup = function()
            trace[#trace + 1] = "docked_cleanup"
            for _, fn in ipairs(dockedCleanupHooks) do fn() end
        end,
    }
    local map = {
        name = "MapMenu",
        registerCallback = function(event, fn)
            if event == "on_menu_cleanup" then
                mapCleanupHooks[#mapCleanupHooks + 1] = fn
            end
        end,
        onCloseElement = function(reason)
            trace[#trace + 1] = "map_close"
            assert(reason == "close", "onOpenOnboard must close MapMenu with reason=close")
            for _, fn in ipairs(mapCleanupHooks) do fn() end
        end,
    }
    Helper.getMenu = function(name)
        if name == "DockedMenu" then return docked end
        if name == "MapMenu" then return map end
    end

    fix118.C.GetPlayerCurrentControlGroup = function() return "gunnercontrol" end
    fix118.C.GetNumUpgradeGroups = function() return 0 end
    fix118.C.GetNumUpgradeSlots = function() return 1 end
    fix118.C.GetUpgradeSlotCurrentComponent = function() return 27 end
    fix118.C.GetUpgradeSlotGroup = function()
        return { path = "..", group = "group01" }
    end
    fix118.C.GetWeaponMode = function() return "defend" end
    fix118.C.IsWeaponArmed = function() return true end
    fix118.C.IsComponentOperational = function() return true end
    fix118.C.IsPlayerCameraTargetViewPossible = function() return true end
    GetComponentData = function(_, key)
        if key == "isplayerowned" then return true end
    end

    -- gameLoadingDone re-runs registerUIHooks now that both host menus exist.
    fix118.fireUIEvent("gameLoadingDone")
    assert(#dockedCleanupHooks == 0,
        "the chair Map probe must not register the old DockedMenu reopen callback; got "
        .. tostring(#dockedCleanupHooks))
    assert(#mapCleanupHooks == 1,
        "the existing Map lifecycle must register exactly one on_menu_cleanup callback; got "
        .. tostring(#mapCleanupHooks))

    -- Run only the redirect callback first. This exposes the state before the
    -- existing onOpenOnboard delayed Map close is allowed to run.
    local mark = fix118.callbackCheckpoint()
    fix118.fireUIEvent("gameplanchange", "cockpit")
    local redirectCallback = fix118.pendingCallbacks[#fix118.pendingCallbacks]
    fix118.runCallback(redirectCallback)

    assert(table.concat(trace, ",") == "close,docked_cleanup,map_open",
        "chair ingress must close/clean DockedMenu and request the real MapMenu; trace was "
        .. table.concat(trace, ","))
    assert(closeArgs and closeArgs.reason == "close"
        and closeArgs.a == false and closeArgs.b == false,
        "DockedMenu must be closed with the TopLevelMenu auto-fallback suppressed "
        .. "(closeMenu(docked, \"close\", false, false)); got reason="
        .. tostring(closeArgs and closeArgs.reason) .. " a="
        .. tostring(closeArgs and closeArgs.a) .. " b=" .. tostring(closeArgs and closeArgs.b))
    assert(mapOpens == 1, "chair ingress must request real MapMenu exactly once")
    local session118 = fix118.API.getSession()
    assert(session118 and session118.origin == "onboard"
        and session118.lifecycle == X4GunneryState.lifecycle.suspendedMap,
        "chair Map probe must reuse onOpenOnboard and create an onboard/suspended-Map session")
    assert(gunneryOpens == 0,
        "DockedMenu cleanup must not independently open Gunnery on the Map probe path")
    assert(fix118.logContains(
        "event=chair_map_probe stage=map_open_requested control=gunnercontrol ship=42"),
        "chair Map probe must log its control group and current ship")

    -- A later ordinary DockedMenu cleanup remains inert while Map owns the
    -- suspended session; only Map cleanup may trigger the Gunnery reopen.
    docked.cleanup()
    assert(gunneryOpens == 0,
        "ordinary DockedMenu cleanup must remain inert during the Map handoff")

    fix118.drainCallbacksSince(mark)
    assert(gunneryOpens == 1,
        "the existing onOpenOnboard close and Map cleanup callback must reopen Gunnery once")
end

print("runtime lifecycle tests passed")
