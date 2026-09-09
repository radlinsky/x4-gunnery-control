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

-- ── 37. engaged replaces Helper4; teardown closes before unregistering ──────
-- helper.lua's closeMenu() untracks the menu first (C.RemoveTrackedMenu) and
-- only then lets clearMenu() unregister the views (helper.lua:1908-1947).
-- Unregistering first hid the view while the menu was still tracked, and after
-- a session that opened a playerControls frame the engine then stopped
-- delivering Esc to the game menu until another menu opened and closed.
gcMenu.onShowMenu()
local sess37 = API.getSession()
assert(sess37 ~= nil, "expected session for teardown order test")
local function findView37(id, name)
    for _, entry in ipairs(fix.View.menus) do
        if entry.id == id and entry.name == name then return entry end
    end
end
assert(findView37("Helper4", gcMenu.name),
    "precondition: the console must own its normal Helper4 registration")
fix.View.registerMenu("Helper2", "External", nil, nil, {}, "ExternalOverlay", {})
sess37.groups = { grp27 }
sess37.checkedGroupKeys = { ["grp27"] = true }
sess37.phase = "engaged"
sess37.controlMode = "direct"
sess37.directSnapshots = {}
sess37.cameraMemberID = 27
sess37.targetObjectID = 500
gcMenu.display()
assert(findView37("X4GunneryOverlay", gcMenu.name),
    "engaged transition must register the persistent Gunnery overlay")
assert(not findView37("Helper4", gcMenu.name),
    "engaged transition must unregister the prior Gunnery Helper4 frame")
assert(findView37("Helper2", "ExternalOverlay"),
    "engaged transition must not unregister an unrelated external menu")
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

-- ── 54. an ordinary unknown overlay preserves an engaged session ────────
-- Helper replaces its ordinary menu registration when a third-party overlay
-- opens. The persistent Gunnery registration and independent engaged updater
-- must survive that handoff without rebuilding the frame or touching camera,
-- target, group, or POV state. The external name is deliberately arbitrary:
-- this contract must not depend on a production allowlist.
gcMenu.onShowMenu()
local sess54 = API.getSession()
assert(sess54 ~= nil, "expected session for ordinary external-overlay test (54)")
local grp54 = fix.makeGroup{
    key = "grp54", displayName = "External-overlay directed group",
    members = { { componentID = 54, displayName = "T54", operational = true,
                  cameraSupported = true, componentKey = "54" } },
}
sess54.groups = { grp54 }
sess54.checkedGroupKeys = { ["grp54"] = true }
sess54.staged = { grp54 = { mode = "attack", armed = false } }
sess54.cameraMemberID = 54
fix.C.SetSofttarget = function() return true end
fix.C.SetPlayerCameraTargetView = function() return true end
fix.C.GetContextByClass = function(component, class, force)
    if class == "container" and force == true then return 500 end
    return 42
end
fix.C.GetExternalTargetViewComponent = function() return 54 end
local mark54 = fix.callbackCheckpoint()
assert(API.engageTarget(501), "ordinary-overlay precondition: Direct engagement must succeed")
fix.drainCallbacksSince(mark54)
assert(API.getSession() == sess54
        and sess54.phase == "engaged" and sess54.controlMode == "direct",
    "ordinary-overlay precondition: the real Direct engagement must remain current")
assert(sess54.targetObjectID == 500 and sess54.aimTargetID == 501,
    "ordinary-overlay precondition: Direct engagement must retain root and aim targets")
sess54.povAnchor, sess54.povMode = "target", "manual"

local function findView54(id)
    for _, entry in ipairs(fix.View.menus) do
        if entry.id == id then return entry end
    end
end
local overlay54 = findView54("X4GunneryOverlay")
assert(overlay54 and overlay54.type == "X4GunneryOverlay"
        and overlay54.properties and overlay54.properties.layer == 0,
    "engaged Gunnery must own its layer-0 X4GunneryOverlay registration")
local frame54 = gcMenu.frame
local updater54 = fix.getOnUpdateCallback()
assert(updater54 ~= nil,
    "engaged Gunnery must install its independent updater before an external overlay opens")

-- Opening an ordinary Helper-owned menu first clears the previous Helper view.
-- Gunnery's custom layer-0 registration must not match that clear.
fix.View.clearMenus({ Helper = true })
assert(findView54("X4GunneryOverlay") == overlay54,
    "View.clearMenus({ Helper = true }) must preserve the same Gunnery overlay registration")
local external54 = {
    name = "ThirdPartyTelemetryWhimsy", shown = true, minimized = false,
}
Menus[#Menus + 1] = external54
fix.View.registerMenu("Helper4", "Helper", nil, nil, {}, external54.name, {})
assert(findView54("Helper4") ~= nil,
    "ordinary-overlay precondition: the unknown external Helper view must be registered")

local groups54, checked54 = sess54.groups, sess54.checkedGroupKeys
local groupMode54, groupArmed54 = grp54.mode, grp54.armed
local allFrames54, callbacks54 = #fix.allFrames, #fix.pendingCallbacks
local targetObject54, aimTarget54 = sess54.targetObjectID, sess54.aimTargetID
local cameraMember54 = sess54.cameraMemberID
local povAnchor54, povMode54 = sess54.povAnchor, sess54.povMode
local directMode54 = sess54.directMode
local cameraChanges54, cameraResets54 = 0, 0
fix.C.SetPlayerCameraTargetView = function()
    cameraChanges54 = cameraChanges54 + 1
    return true
end
fix.C.SetPlayerCameraCockpitView = function()
    cameraResets54 = cameraResets54 + 1
    return true
end
fix.resetCloseMenuCalls()
fix.resetTeardownTrace()

gcMenu.cleanup()
gcMenu.onCloseElement("close")
gcMenu.onUpdate()
fix.invokeOnUpdate()

assert(API.getSession() == sess54,
    "an unknown ordinary external overlay must preserve the exact engaged session object")
assert(sess54.groups == groups54 and sess54.groups[1] == grp54
        and grp54.mode == groupMode54 and grp54.armed == groupArmed54
        and sess54.checkedGroupKeys == checked54 and sess54.checkedGroupKeys.grp54 == true,
    "an unknown ordinary external overlay must preserve directed groups and their checked state")
assert(sess54.phase == "engaged" and sess54.controlMode == "direct"
        and sess54.directMode == directMode54,
    "an unknown ordinary external overlay must preserve Direct control and its policy")
assert(sess54.targetObjectID == targetObject54 and sess54.aimTargetID == aimTarget54,
    "an unknown ordinary external overlay must preserve root and aim targets")
assert(sess54.cameraMemberID == cameraMember54
        and sess54.povAnchor == povAnchor54 and sess54.povMode == povMode54,
    "an unknown ordinary external overlay must preserve camera-member and POV state")
assert(findView54("X4GunneryOverlay") == overlay54 and gcMenu.frame == frame54
        and #fix.allFrames == allFrames54,
    "an unknown ordinary external overlay must neither hide nor rebuild Gunnery")
assert(cameraChanges54 == 0 and cameraResets54 == 0,
    "an unknown ordinary external overlay must not change or reset the Gunnery camera")
assert(fix.getCloseMenuCalls() == 0 and #fix.getTeardownTrace() == 0
        and #fix.pendingCallbacks == callbacks54,
    "an unknown ordinary external overlay must not schedule or perform Gunnery teardown")
assert(fix.getOnUpdateCallback() == updater54,
    "the same independent engaged updater must remain installed across Helper ownership")

-- Remove only the simulated third-party menu and its ordinary Helper view.
external54.shown = false
for index, candidate in ipairs(Menus) do
    if candidate == external54 then table.remove(Menus, index); break end
end
fix.View.unregisterMenu("Helper4", true)
assert(API.getSession() == sess54 and findView54("X4GunneryOverlay") == overlay54
        and gcMenu.frame == frame54 and #fix.allFrames == allFrames54,
    "closing only the external overlay must leave the same Gunnery session and frame registered")
assert(fix.getOnUpdateCallback() == updater54
        and fix.getCloseMenuCalls() == 0 and #fix.getTeardownTrace() == 0,
    "closing only the external overlay must not reconstruct or tear down Gunnery")

-- ── 55. fullscreen takeover suspends only the engaged overlay ─────────────
-- A fullscreen menu must temporarily yield Gunnery's visual/input registration
-- without converting the takeover into a disengage/re-engage cycle. Restoration
-- reuses the retained frame descriptor; the fixture intentionally does not model
-- compositor, child-widget, or input behavior beyond the View registry.
gcMenu.onShowMenu()
local sess55 = API.getSession()
assert(sess55 ~= nil, "expected session for fullscreen-takeover test (55)")
local grp55 = fix.makeGroup{
    key = "grp55", displayName = "Fullscreen directed group",
    members = { { componentID = 55, displayName = "T55", operational = true,
                  cameraSupported = true, componentKey = "55" } },
}
sess55.groups = { grp55 }
sess55.checkedGroupKeys = { ["grp55"] = true }
sess55.staged = { grp55 = { mode = "attack", armed = false } }
sess55.cameraMemberID = 55
fix.C.SetSofttarget = function() return true end
fix.C.SetPlayerCameraTargetView = function() return true end
fix.C.GetContextByClass = function(component, class, force)
    if class == "container" and force == true then return 550 end
    return 42
end
fix.C.GetExternalTargetViewComponent = function() return 55 end
local mark55 = fix.callbackCheckpoint()
assert(API.engageTarget(551),
    "fullscreen-takeover precondition: Direct engagement must succeed")
fix.drainCallbacksSince(mark55)
assert(API.getSession() == sess55
        and sess55.phase == "engaged" and sess55.controlMode == "direct",
    "fullscreen-takeover precondition: the real Direct engagement must remain current")
assert(sess55.targetObjectID == 550 and sess55.aimTargetID == 551,
    "fullscreen-takeover precondition: Direct engagement must retain root and aim targets")
sess55.povAnchor, sess55.povMode = "target", "manual"

local function findView55(id)
    for _, entry in ipairs(fix.View.menus) do
        if entry.id == id then return entry end
    end
end
local overlay55 = findView55("X4GunneryOverlay")
assert(overlay55 ~= nil,
    "fullscreen-takeover precondition: engaged Gunnery overlay must be registered")
local session55 = sess55
local groups55, checked55 = sess55.groups, sess55.checkedGroupKeys
local groupMode55, groupArmed55 = grp55.mode, grp55.armed
local phase55, lifecycle55, controlMode55, directMode55 =
    sess55.phase, sess55.lifecycle, sess55.controlMode, sess55.directMode
local targetObject55, aimTarget55 = sess55.targetObjectID, sess55.aimTargetID
local cameraMember55 = sess55.cameraMemberID
local povAnchor55, povMode55 = sess55.povAnchor, sess55.povMode
local frame55 = gcMenu.frame
local updater55 = fix.getOnUpdateCallback()
local descriptors55 = overlay55.framedescriptors
local callback55 = overlay55.callback
local allFrames55 = #fix.allFrames
local cameraChanges55, cameraResets55 = 0, 0
fix.C.SetPlayerCameraTargetView = function()
    cameraChanges55 = cameraChanges55 + 1
    return true
end
fix.C.SetPlayerCameraCockpitView = function()
    cameraResets55 = cameraResets55 + 1
    return true
end
fix.resetCloseMenuCalls()
fix.resetTeardownTrace()

fix.setFullscreenMenuDisplayed(true)
fix.invokeOnUpdate()

assert(API.getSession() == session55,
    "fullscreen takeover must preserve the exact engaged session object")
assert(sess55.phase == phase55 and sess55.lifecycle == lifecycle55
        and sess55.controlMode == controlMode55
        and sess55.directMode == directMode55,
    "fullscreen takeover must preserve engaged Direct control and its policy")
assert(sess55.groups == groups55 and sess55.groups[1] == grp55
        and grp55.mode == groupMode55 and grp55.armed == groupArmed55
        and sess55.checkedGroupKeys == checked55 and sess55.checkedGroupKeys.grp55 == true,
    "fullscreen takeover must preserve directed groups and their checked state")
assert(sess55.targetObjectID == targetObject55 and sess55.aimTargetID == aimTarget55,
    "fullscreen takeover must preserve root and aim targets")
assert(sess55.cameraMemberID == cameraMember55
        and sess55.povAnchor == povAnchor55 and sess55.povMode == povMode55,
    "fullscreen takeover must preserve camera-member and POV state")
assert(findView55("X4GunneryOverlay") == nil,
    "fullscreen takeover must unregister only the engaged Gunnery overlay")
assert(gcMenu.frame == frame55 and #fix.allFrames == allFrames55,
    "suspending for fullscreen takeover must not build a new Gunnery frame")
assert(fix.getOnUpdateCallback() == updater55 and updater55 ~= nil,
    "fullscreen takeover must preserve the independent engaged updater")
assert(fix.getCloseMenuCalls() == 0 and #fix.getTeardownTrace() == 0,
    "fullscreen takeover must not tear down the engaged session")
assert(cameraChanges55 == 0 and cameraResets55 == 0,
    "fullscreen takeover must not change or restore the player camera")

gcMenu.display()
assert(API.getSession() == session55
        and sess55.phase == phase55 and sess55.lifecycle == lifecycle55
        and sess55.controlMode == controlMode55
        and sess55.directMode == directMode55,
    "display during fullscreen takeover must preserve the same Direct session and policy")
assert(sess55.groups == groups55 and sess55.checkedGroupKeys == checked55
        and sess55.targetObjectID == targetObject55 and sess55.aimTargetID == aimTarget55
        and sess55.cameraMemberID == cameraMember55
        and sess55.povAnchor == povAnchor55 and sess55.povMode == povMode55,
    "display during fullscreen takeover must preserve groups, targets, camera, and POV")
assert(findView55("X4GunneryOverlay") == nil
        and gcMenu.frame == frame55 and #fix.allFrames == allFrames55,
    "display during fullscreen takeover must not rebuild or re-register the overlay")
assert(fix.getOnUpdateCallback() == updater55
        and fix.getCloseMenuCalls() == 0 and #fix.getTeardownTrace() == 0,
    "display during fullscreen takeover must not replace the updater or tear down Gunnery")
assert(cameraChanges55 == 0 and cameraResets55 == 0,
    "display during fullscreen takeover must not restore or repoint the player camera")

fix.setFullscreenMenuDisplayed(false)
local registerMenu55 = fix.View.registerMenu
local restoredRegistrations55 = {}
fix.View.registerMenu = function(id, registeredType, callback, clearCallback,
        framedescriptors, name, properties)
    if id == "X4GunneryOverlay" then
        restoredRegistrations55[#restoredRegistrations55 + 1] = {
            callback = callback, framedescriptors = framedescriptors,
        }
    end
    return registerMenu55(id, registeredType, callback, clearCallback,
        framedescriptors, name, properties)
end
fix.invokeOnUpdate()
fix.View.registerMenu = registerMenu55

local restoredOverlay55 = findView55("X4GunneryOverlay")
assert(restoredOverlay55 ~= nil,
    "ending fullscreen takeover must restore the engaged Gunnery registration")
assert(#restoredRegistrations55 == 1
        and restoredRegistrations55[1].framedescriptors == descriptors55
        and restoredRegistrations55[1].callback == callback55,
    "fullscreen restoration must first reuse the retained overlay descriptor and callback")
assert(API.getSession() == session55
        and sess55.phase == phase55 and sess55.lifecycle == lifecycle55
        and sess55.controlMode == controlMode55
        and sess55.directMode == directMode55,
    "fullscreen restoration must preserve the exact engaged Direct session and policy")
assert(sess55.groups == groups55 and sess55.groups[1] == grp55
        and grp55.mode == groupMode55 and grp55.armed == groupArmed55
        and sess55.checkedGroupKeys == checked55 and sess55.checkedGroupKeys.grp55 == true,
    "fullscreen restoration must preserve directed groups and their checked state")
assert(sess55.targetObjectID == targetObject55 and sess55.aimTargetID == aimTarget55
        and sess55.cameraMemberID == cameraMember55
        and sess55.povAnchor == povAnchor55 and sess55.povMode == povMode55,
    "fullscreen restoration must preserve targets, camera member, and POV")
assert(gcMenu.frame ~= nil and #fix.allFrames == allFrames55 + 1,
    "the display requested during takeover must repaint once only after restoration")
assert(fix.getOnUpdateCallback() == updater55
        and fix.getCloseMenuCalls() == 0 and #fix.getTeardownTrace() == 0,
    "fullscreen restoration must not replace the updater or tear down Gunnery")
assert(cameraChanges55 == 0 and cameraResets55 == 0,
    "fullscreen restoration must not restore or repoint the player camera")

-- ── 56 (hookTimeoutMessage). missing kuertee UI Extensions is reported, not silent ────
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
print("runtime lifecycle tests passed")
