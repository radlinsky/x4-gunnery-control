-- test_runtime_camera.lua
-- Camera gates, POV, callback ordering, soft-target restore, re-pointing.

local fix = dofile("tests/support/runtime_fixture.lua").load()
local gcMenu = fix.gcMenu
local API    = fix.API
local C      = fix.C

-- A reusable group that has one camera-capable member (componentID 27).
-- Several tests mutate session around this group.
local grp27 = {
    key = "grp27", kind = "group", contextID = 5, path = "p", group = "g",
    componentID = 27, displayName = "G27", totalCount = 1, operationalCount = 1,
    mode = "attack", armed = false, members = {
        { componentID = 27, displayName = "T1", operational = true,
          cameraSupported = true, componentKey = "27" }
    }
}

-- ── 34. Esc out of a cinematic returns to the manual panel ──────────────────
-- The cutscene runs with duration 999999 and cinematicmode's HUD-off state; if
-- Esc falls through to the ordinary close path it keeps running invisibly under
-- the panels until the session ends.
gcMenu.onShowMenu()
local sess34 = API.getSession()
assert(sess34 ~= nil, "expected session for cinematic Esc test")
sess34.groups = { grp27 }
sess34.checkedGroupKeys = { ["grp27"] = true }
sess34.phase = "engaged"
sess34.controlMode = "direct"
sess34.cameraMemberID = 27
sess34.povAnchor, sess34.povMode = "target", "cinematic"
gcMenu.onCloseElement("back")
assert(sess34.povMode == "manual",
    "Esc from a cinematic must return to the manual POV; povMode=" .. tostring(sess34.povMode))
assert(sess34.povAnchor == "turret",
    "Esc from a cinematic must return to the default turret anchor; povAnchor=" .. tostring(sess34.povAnchor))
assert(sess34.phase == "engaged",
    "Esc from a cinematic must stay in the engaged phase; phase=" .. tostring(sess34.phase))

-- ── 35. the engine ending the cutscene syncs the panel back ─────────────────
-- The player's first Esc during a cinematic goes to the cutscene, not to our
-- frame. Without this the panel still believes the cinematic is current: one
-- more Esc to repaint it, a third to actually go back a menu.
local clock = 0
getElapsedTime = function() return clock end

gcMenu.onShowMenu()
local sess35 = API.getSession()
assert(sess35 ~= nil, "expected session for cutscene sync test")
sess35.groups = { grp27 }
sess35.checkedGroupKeys = { ["grp27"] = true }
sess35.phase = "engaged"
sess35.controlMode = "auto"
sess35.cameraMemberID = 27
sess35.povAnchor, sess35.povMode = "target", "cinematic"
C.IsFullscreenCutsceneActive = function() return true end
clock = clock + 10
gcMenu.onUpdate()
assert(sess35.povMode == "cinematic",
    "a running cutscene must leave the cinematic POV alone")
C.IsFullscreenCutsceneActive = function() return false end
clock = clock + 10
gcMenu.onUpdate()
assert(sess35.povMode == "manual" and sess35.povAnchor == "turret",
    "an externally ended cutscene must return to Turret POV manual; got "
    .. tostring(sess35.povAnchor) .. "/" .. tostring(sess35.povMode))

-- A cinematic that has not been seen running yet must not be cancelled: the
-- retarget restart briefly leaves no cutscene active.
sess35.povAnchor, sess35.povMode = "target", "cinematic"
C.IsFullscreenCutsceneActive = function() return true end
clock = clock + 10
gcMenu.onUpdate()                                     -- observes it running
X4GunneryControlAPI.sendCutsceneAimStart("turret")    -- retarget restart
C.IsFullscreenCutsceneActive = function() return false end
clock = clock + 10
gcMenu.onUpdate()
assert(sess35.povMode == "cinematic",
    "the gap between a cutscene stop and its restart must not cancel the cinematic")

-- ── 42. a soft target that was empty is restored by clearing, not by zero ────
-- No vanilla call ever passes 0 to SetSofttarget; RemoveSofttarget() is the
-- engine's clear (targetsystem.lua:1747,2097,2130, and our own Test Lab path).
-- Passing 0 leaves the soft target on the turret enterCamera borrowed, i.e. on
-- a component of the player's own ship, which is a state vanilla never creates.
local removeSofttargetCalls42 = 0
local softtargetSets42 = {}
RemoveSofttarget = function() removeSofttargetCalls42 = removeSofttargetCalls42 + 1 end
C.SetSofttarget = function(cid)
    softtargetSets42[#softtargetSets42 + 1] = tostring(cid)
    return true
end
-- Nothing targeted before the session, which is the ordinary case.
C.GetSofttarget2 = function()
    return { softtargetID = 0, softtargetConnectionName = "" }
end
gcMenu.onShowMenu()
local sess42 = API.getSession()
assert(sess42 ~= nil, "expected session for softtarget restore test")
sess42.groups = { grp27 }
sess42.checkedGroupKeys = { ["grp27"] = true }
sess42.phase = "console"
C.IsComponentOperational = function() return true end
-- enterCamera's camera gate retries while the focus does not match the turret,
-- which is the path that borrows and then restores the soft target.
C.GetExternalTargetViewComponent = function() return 7 end
local mark42 = fix.callbackCheckpoint()
assert(API.startTargetSelection(X4GunneryState.checkedGroups(sess42)) == true,
    "camera-entry setup must start target selection")
fix.drainCallbacksSince(mark42)
assert(removeSofttargetCalls42 > 0,
    "restoring an empty soft target must call RemoveSofttarget()")
for _, cid in ipairs(softtargetSets42) do
    assert(cid ~= "0",
        "SetSofttarget(0) is not a documented clear; use RemoveSofttarget()")
end

-- ── 43. get-up never leaves the soft target on the player's own ship ─────────
-- enterCamera borrows the soft target to force the camera onto a turret. If a
-- borrowed one survives the session the player stands up still soft-targeting
-- their own turret.
gcMenu.onShowMenu()
local sess43 = API.getSession()
assert(sess43 ~= nil, "expected session for softtarget teardown test")
sess43.phase = "console"
-- Soft target 27 resolves to the session's own ship.
C.GetSofttarget2 = function()
    return { softtargetID = 27, softtargetConnectionName = "" }
end
C.GetContextByClass = function() return sess43.shipID end
local removeSofttargetCalls43 = 0
RemoveSofttarget = function() removeSofttargetCalls43 = removeSofttargetCalls43 + 1 end
gcMenu.onCloseElement("close")
assert(removeSofttargetCalls43 > 0,
    "get-up must clear a soft target that points at the player's own ship")

-- ── 53. camera gate accepts the container X4 returns on small ships ──────────
-- Issue #11: on an M-class ship (Katana) SetPlayerCameraTargetView(turret) is
-- accepted but GetExternalTargetViewComponent() reads back the turret's
-- *container* (the ship). The old gate compared against the turret id only, saw
-- a mismatch, and bounced the player from target_select to the console after
-- ~30 ms, so Direct-control was unusable there. The container is a match.
do
    local savedContextByClass53 = C.GetContextByClass
    local savedFocus53           = C.GetExternalTargetViewComponent
    local savedOperational53     = C.IsComponentOperational

    local grp53 = {
        key = "grp53", kind = "group", contextID = 5, path = "p", group = "g",
        componentID = 60, displayName = "Katana Front", totalCount = 1, operationalCount = 1,
        mode = "attack", armed = false, members = {
            { componentID = 60, displayName = "T1", operational = true,
              cameraSupported = true, componentKey = "60" }
        }
    }
    local function startSelection53()
        gcMenu.onShowMenu()
        local sess = API.getSession()
        assert(sess ~= nil, "expected session for camera gate test (53)")
        sess.groups = { grp53 }
        sess.checkedGroupKeys = { ["grp53"] = true }
        sess.phase = "console"
        local mark = fix.callbackCheckpoint()
        assert(API.startTargetSelection(X4GunneryState.checkedGroups(sess)) == true,
            "53: startTargetSelection must return true for a mutable operational group")
        -- Drain the chained camera callbacks (0.05 s + 0.05 s) plus the deferred display.
        fix.drainCallbacksSince(mark)
        return sess
    end

    C.IsComponentOperational = function() return true end
    -- Turret 60 lives in ship 99, and the engine resolves the target view to it.
    C.GetContextByClass = function() return 99 end
    C.GetExternalTargetViewComponent = function() return 99 end

    local capturedLog53 = fix.getCapturedLog()
    local logLen53 = #capturedLog53
    local sess53 = startSelection53()
    assert(sess53.phase == "target_select",
        "BUG (issue #11): the camera gate must accept the container the engine "
        .. "returns; phase was '" .. tostring(sess53.phase) .. "' instead of 'target_select'")
    for i = logLen53 + 1, #capturedLog53 do
        assert(not string.find(capturedLog53[i], "camera gate failed", 1, true),
            "53: resolving to the container must not log a camera gate failure")
    end

    -- 53b: a focus that is neither the turret nor its container is a real
    -- failure — but it must cost the player the camera, not the target browser.
    C.GetExternalTargetViewComponent = function() return 12345 end
    local logLen53b = #capturedLog53
    local sess53b = startSelection53()
    assert(sess53b.phase == "target_select",
        "BUG: a failed camera must leave the player in target_select, not bounce "
        .. "them to the console; phase was '" .. tostring(sess53b.phase) .. "'")
    local logged53b = false
    for i = logLen53b + 1, #capturedLog53 do
        if string.find(capturedLog53[i], "camera gate failed", 1, true) then logged53b = true end
    end
    assert(logged53b, "53b: an unrelated camera focus must still log the gate failure")

    C.GetContextByClass              = savedContextByClass53
    C.GetExternalTargetViewComponent = savedFocus53
    C.IsComponentOperational         = savedOperational53
end

print("runtime camera tests passed")
