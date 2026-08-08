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

-- ── 49. RestoreSession handler accepts the string transport ──────────────────
-- raise_lua_event carries ONE SCALAR. A table arrives as nil, live-confirmed
-- twice (2026-08-06 and again 2026-08-08, where MD logged a fully populated
-- State.$active on the same tick this handler logged "payload type=nil"). So
-- the payload is an encoded string, and the old $-prefixed table handling this
-- block used to test was code for a contract the engine never delivers.
--
-- What the payload MEANS -- path+group matching, contextID re-resolution,
-- dropping groups that no longer exist -- is covered in test_gunnery_state.lua
-- against the pure functions. This block only proves the handler is wired to
-- the decoder and cannot be crashed by what MD hands it.

assert(type(X4GunneryControlAPI.onRestoreSession) == "function",
    "X4GunneryControlAPI.onRestoreSession must be exposed; add TestAPI.onRestoreSession in gunnery_control.lua")

-- 49a: a well-formed encoded payload is decoded and reported, not rejected.
local payload49 = X4GunneryState.encode(X4GunneryState.saveState({
    shipID = 42, phase = "console", povAnchor = "turret", povMode = "manual",
    checkedGroupKeys = {}, groups = {}, directSnapshots = {
        { kind = "group", shipID = 42, contextID = 1, path = "p49",
          group = "A", mode = "defend", armed = false },
    },
}))
assert(type(payload49) == "string" and payload49 ~= "",
    "saveState/encode must produce a non-empty string; got " .. tostring(payload49))
X4GunneryControlAPI.onRestoreSession(nil, payload49)
assert(fix.logContains("RestoreSession: restored=true"),
    "RestoreSession must decode a well-formed string payload and report restored=true")

-- 49b: the shapes MD can actually hand back must not throw. nil is what a table
-- payload degrades to, and is the exact value that used to reach this handler.
for _, bad in ipairs({ "", "garbage", "=;,=", "t=session" }) do
    local ok49 = pcall(X4GunneryControlAPI.onRestoreSession, nil, bad)
    assert(ok49, "RestoreSession must not throw on payload " .. string.format("%q", bad))
end
assert(pcall(X4GunneryControlAPI.onRestoreSession, nil, nil),
    "RestoreSession must not throw on a nil payload")
assert(pcall(X4GunneryControlAPI.onRestoreSession, nil, { "a table" }),
    "RestoreSession must not throw if a table somehow arrives")

print("runtime persistence tests passed")
