-- test_runtime_persistence.lua
-- MD event ordering, save/restore, map-suspend/resume, payload handling.

local fix = dofile("tests/support/runtime_fixture.lua").load()
local gcMenu = fix.gcMenu
local API    = fix.API

-- Bring the module into a known state with a live session.
local ok_init, err_init = pcall(function() gcMenu.onShowMenu() end)
assert(ok_init, "onShowMenu() raised during persistence test setup: " .. tostring(err_init))

-- ── 11. map-suspended session resume (Change 1) ─────────────────────────────
-- Confirmed-live bug: closing the Map while seated resets the session to
-- console because DockedMenu re-opens ~70 ms after the MapMenu cleanup
-- callback, before the `reopening` lifecycle transition can complete.
-- The fix: a map-suspended session for the *same* ship must be treated as
-- resumable in onShowMenu(), keeping its phase and not recreating the session.

-- 11a: same ship — session must survive with its phase intact.
-- Reset to a known good state first.
local sess11 = API.getSession()
assert(sess11 ~= nil, "expected a live session for map-suspend resume test")
sess11.shipID    = 42                              -- matches playerShip() stub (id(42)=42)
sess11.phase     = "target_select"
sess11.lifecycle = X4GunneryState.lifecycle.suspendedMap
local preResumeSess = sess11

gcMenu.onShowMenu()

local postResumeSess = API.getSession()
assert(postResumeSess == preResumeSess,
    "BUG (same ship): map-suspended session was discarded and recreated; "
    .. "expected same session object after onShowMenu()")
assert(postResumeSess.phase == "target_select",
    "BUG (same ship): phase was reset to '"
    .. tostring(postResumeSess.phase)
    .. "' instead of 'target_select' after map-suspend resume")
assert(postResumeSess.lifecycle == X4GunneryState.lifecycle.owned,
    "BUG (same ship): lifecycle should be 'owned' after resume, got '"
    .. tostring(postResumeSess.lifecycle) .. "'")
assert(fix.logContains("session resumed from map suspend"),
    "expected 'session resumed from map suspend' in log after map-suspend resume")

-- 11b: different ship — session must still be discarded and recreated.
-- The ship-identity guard must not be weakened by the fix.
local sess11b = API.getSession()
assert(sess11b ~= nil, "expected a live session for different-ship guard test")
sess11b.shipID    = 99                             -- differs from playerShip()=42
sess11b.phase     = "target_select"
sess11b.lifecycle = X4GunneryState.lifecycle.suspendedMap
local preDiscardSess = sess11b

gcMenu.onShowMenu()

local postDiscardSess = API.getSession()
assert(postDiscardSess ~= preDiscardSess,
    "BUG (different ship): map-suspended session for wrong ship was NOT discarded; "
    .. "the ship-identity guard is broken")
assert(postDiscardSess.phase == "console",
    "BUG (different ship): recreated session should start at console, got '"
    .. tostring(postDiscardSess.phase) .. "'")
assert(postDiscardSess.lifecycle == X4GunneryState.lifecycle.owned,
    "BUG (different ship): recreated session lifecycle should be 'owned', got '"
    .. tostring(postDiscardSess.lifecycle) .. "'")

-- ── 49. Atomic restore rejects foreign/malformed payloads ──────────────────
assert(type(API.onRestoreEnvelope) == "function")
local live49, epoch49 = API.getSession(), API.getSessionEpoch()
local callbacks49, events49 = #fix.pendingCallbacks, #fix.uiTriggeredEvents
local cameraCalls49 = 0
local originalCamera49 = fix.C.SetPlayerCameraTargetView
fix.C.SetPlayerCameraTargetView = function(...) cameraCalls49 = cameraCalls49 + 1; return true end
local payload49 = X4GunneryState.encode(X4GunneryState.saveState({
    shipID = 42, shipName = "another ship", phase = "engaged", controlMode = "auto",
    povAnchor = "turret", povMode = "manual", checkedGroupKeys = {}, groups = {}, directSnapshots = {},
}))
API.onRestoreEnvelope({ generation = 1, target = 0, payload = payload49 })
assert(API.getSession() == live49 and API.getSessionEpoch() == epoch49,
    "foreign restore must preserve the exact live session and epoch")
assert(cameraCalls49 == 0, "foreign restore must not enter a camera")
assert(#fix.pendingCallbacks == callbacks49 and #fix.uiTriggeredEvents == events49,
    "foreign restore must not schedule callbacks or rewrite MD state")
for _, bad in ipairs({ "", "garbage" }) do
    assert(pcall(API.onRestoreEnvelope, { generation = 2, target = 0, payload = bad }),
        "malformed envelope must not throw")
    assert(API.getSession() == live49 and API.getSessionEpoch() == epoch49,
        "malformed restore must not replace the session")
end
assert(pcall(API.onRestoreEnvelope, { generation = 2, target = 0, payload = nil }),
    "nil restore payload must not throw")
assert(pcall(API.onRestoreEnvelope, { generation = 2, target = 0, payload = {} }),
    "table restore payload must not throw")
assert(API.getSession() == live49 and API.getSessionEpoch() == epoch49,
    "nil/table restore payloads must not replace the session")

local oldControl49 = fix.C.GetPlayerCurrentControlGroup
fix.C.GetPlayerCurrentControlGroup = function() return "" end
local seatedSession49, seatedEpoch49 = API.getSession(), API.getSessionEpoch()
local seatedCallbacks49, seatedEvents49 = #fix.pendingCallbacks, #fix.uiTriggeredEvents
assert(pcall(API.onRestoreEnvelope, { generation = 3, target = 0, payload = payload49 }),
    "not-seated restore must not throw")
assert(API.getSession() == seatedSession49 and API.getSessionEpoch() == seatedEpoch49
    and cameraCalls49 == 0 and #fix.pendingCallbacks == seatedCallbacks49
    and #fix.uiTriggeredEvents == seatedEvents49,
    "not-seated restore must leave session, epoch, camera, callbacks, and MD events unchanged")
fix.C.GetPlayerCurrentControlGroup = oldControl49
fix.C.SetPlayerCameraTargetView = originalCamera49

print("runtime persistence tests passed")
