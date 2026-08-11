-- Coverage for onDirectTargetOwnerChanged (step 6: ownership-change cease_fire
-- replacement). Every branch of the handler must execute so the coverage gate
-- does not reject the new lines in ui/gunnery_control.lua.
--
-- The handler is registered as "X4GunneryControl.DirectTargetLost" during
-- init(). The fixture captures RegisterEvent calls, so fix.fireEvent drives it
-- exactly as MD would: name=event-name, param=target-component.

local fix = dofile("tests/support/runtime_fixture.lua").load()
fix.gcMenu.onShowMenu()
local session = fix.API.getSession()

-- Build a minimal group so engageTarget can succeed later.
local grp = {
    key = "grp", kind = "group", contextID = 5, path = "p", group = "g",
    componentID = 27, displayName = "G", totalCount = 1, operationalCount = 1,
    mode = "attackenemies", armed = true,
    members = { { componentID = 27, displayName = "T1", operational = true,
                  cameraSupported = true, componentKey = "27" } },
}
session.groups = { grp }
session.checkedGroupKeys = { grp = true }
session.cameraMemberID = 27
session.staged = { grp = { mode = "attackenemies", armed = true } }

-- Stub out FFI calls needed for engageTarget.
fix.C.SetSofttarget = function() return true end
fix.C.SetPlayerCameraTargetView = function() return true end
fix.C.GetContextByClass = function(comp) return comp end
fix.C.IsComponentOperational = function() return true end
GetComponentData = function(_, key)
    if key == "isplayerowned" then return false end
    return nil
end

-- Drive a real engageTarget so session is in the engaged/direct state.
-- controlMode must be nil (not "direct") so engageTarget takes the
-- first-engagement branch that arms the checked groups in attackenemies.
session.phase = "target_select"
session.controlMode = nil
local engaged = fix.API.engageTarget(99)
assert(engaged, "precondition: engageTarget must succeed")
assert(session.phase == "engaged" and session.controlMode == "direct",
    "precondition: session must be in engaged/direct")

-- Capture AddUITriggeredEvent calls after engagement so we can count re-issues.
local captured = {}
AddUITriggeredEvent = function(screen, control, params)
    captured[#captured + 1] = { screen = screen, control = control, params = params }
end

-- ── Branch 1: no session (handler must return silently) ──────────────────────
local savedSession = session
fix.API.getSession()   -- just to confirm there is one
-- Temporarily nil out the session by driving an onCloseElement on the console phase.
-- Easiest: call the handler directly with no session in place.
-- The handler reads the module-local `session`; we cannot nil it from outside,
-- but we CAN drive it through the registered event with a state that triggers
-- the early return. Use phase="console" (not "engaged") to hit guard 2.
do
    local prevCapLen = #captured
    -- Guard 2: phase != "engaged"
    session.phase = "console"
    fix.fireEvent("X4GunneryControl.DirectTargetLost", 99)
    assert(#captured == prevCapLen,
        "handler must silently return when phase is not engaged (console)")
    session.phase = "engaged"
end

-- ── Branch 2: controlMode != "direct" ────────────────────────────────────────
do
    local prevCapLen = #captured
    session.controlMode = "auto"
    fix.fireEvent("X4GunneryControl.DirectTargetLost", 99)
    assert(#captured == prevCapLen,
        "handler must silently return when controlMode is not direct")
    session.controlMode = "direct"
end

-- ── Branch 3: param does not match the current engaged target ────────────────
do
    local prevCapLen = #captured
    -- session.targetObjectID was set by engageTarget to targetRoot(99).
    -- Pass a different id (55) as param.
    fix.fireEvent("X4GunneryControl.DirectTargetLost", 55)
    assert(#captured == prevCapLen,
        "handler must silently return when param does not match targetObjectID")
end

-- ── Branch 4: success path — ownership changed, re-issue fires ───────────────
do
    local prevCapLen = #captured
    -- param matches session.targetObjectID (99). The handler must call
    -- emitDirectFallback, which emits direct_fallback + direct_watch.
    fix.fireEvent("X4GunneryControl.DirectTargetLost", 99)
    local newEvents = #captured - prevCapLen
    assert(newEvents >= 2,
        "ownership-change handler must emit direct_fallback + direct_watch; got "
        .. tostring(newEvents) .. " event(s)")
    local sawFallback, sawWatch = false, false
    for i = prevCapLen + 1, #captured do
        if captured[i].control == "direct_fallback" then sawFallback = true end
        if captured[i].control == "direct_watch"    then sawWatch    = true end
    end
    assert(sawFallback,
        "ownership-change re-issue must emit direct_fallback")
    assert(sawWatch,
        "ownership-change re-issue must emit direct_watch (arms the new listener)")
end

-- ── emitDirectFallback: verify direct_watch is paired with direct_fallback ───
-- Exercise the path through a fresh engageTarget so line 405 (the watch emit)
-- is hit even if the branch-4 path above didn't reach it for some reason.
do
    session.phase = "target_select"
    session.controlMode = "direct"
    local evsBefore = #captured
    local ok = fix.API.engageTarget(99)
    assert(ok, "second engageTarget must succeed")
    local watchCount, fallbackCount = 0, 0
    for i = evsBefore + 1, #captured do
        if captured[i].control == "direct_watch"    then watchCount    = watchCount    + 1 end
        if captured[i].control == "direct_fallback" then fallbackCount = fallbackCount + 1 end
    end
    assert(fallbackCount >= 1,
        "engageTarget must emit at least one direct_fallback; got " .. tostring(fallbackCount))
    assert(watchCount >= 1,
        "engageTarget must emit at least one direct_watch; got " .. tostring(watchCount))
    assert(watchCount == fallbackCount,
        "direct_watch and direct_fallback must be emitted in pairs; fallback="
        .. tostring(fallbackCount) .. " watch=" .. tostring(watchCount))
end

print("runtime coverage ownership tests passed")
