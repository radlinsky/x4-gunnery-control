-- test_runtime_init_smoke.lua
-- Module load and init: verifies that load + init() succeed and that
-- sessionWatchdog -> logSession runs without the
-- "attempt to concatenate a function value" class of bug.

local fix = dofile("tests/support/runtime_fixture.lua").load()
local gcMenu = fix.gcMenu
local API    = fix.API
-- init queues the watchdog after the UI-hook retry. Keep its identity before
-- the scheduler contract schedules its own test callbacks.
local initWatchdog = fix.pendingCallbacks[#fix.pendingCallbacks]

-- The scheduler must isolate the action under test from the init watchdog and
-- hook retry already in the queue. It executes post-mark work in due-time order
-- and follows descendants once without draining recurring pre-mark callbacks.
local schedulerOrder = {}
local schedulerMark = fix.callbackCheckpoint()
Helper.addDelayedOneTimeCallbackOnUpdate(function()
    schedulerOrder[#schedulerOrder + 1] = "parent"
    Helper.addDelayedOneTimeCallbackOnUpdate(function()
        schedulerOrder[#schedulerOrder + 1] = "descendant"
    end, false, 15)
end, false, 10)
Helper.addDelayedOneTimeCallbackOnUpdate(function()
    schedulerOrder[#schedulerOrder + 1] = "earlier"
end, false, 5)
fix.drainCallbacksSince(schedulerMark)
assert(table.concat(schedulerOrder, ",") == "earlier,parent,descendant",
    "checkpoint drain must run post-mark callbacks and descendants in time order")
assert(fix.callbackCheckpoint() == schedulerMark + 3,
    "checkpoint drain must leave pre-mark recurring callbacks queued")

-- ── 6. assertion 1: init messages ───────────────────────────────────────────
assert(fix.logContains("[X4GC] initializing UI"),
    "expected '[X4GC] initializing UI' in captured log; got:\n"
    .. table.concat(fix.getCapturedLog(), "\n"))
assert(fix.logContains("[X4GC] UI initialized"),
    "expected '[X4GC] UI initialized' in captured log; got:\n"
    .. table.concat(fix.getCapturedLog(), "\n"))
assert(type(fix.registeredEvents.playerGetUp) == "table"
    and type(fix.registeredEvents["X4GunneryControl.RestoreGrant"]) == "table",
    "fixture must expose RegisterEvent captures by event name")
assert(#fix.uiTriggeredEvents >= 1
    and fix.uiTriggeredEvents[1].screen == "X4GunneryControl"
    and fix.uiTriggeredEvents[1].control == "state_request",
    "fixture must expose AddUITriggeredEvent captures")

-- ── 7. assertion 2: drive sessionWatchdog -> logSession ─────────────────────
-- init() ends with sessionWatchdog(), which calls
-- Helper.addDelayedOneTimeCallbackOnUpdate(sessionWatchdog, ...).
-- registerUIHooks may queue a retry first; initWatchdog captured the watchdog
-- identity before this test adds any scheduler-contract callbacks.
-- We invoke it exactly once; it will attempt to re-register itself (fine,
-- we just accumulate another entry) and, because no session exists yet on the
-- first tick, it logs nothing extra and exits. We need a session to exist so
-- that the signature changes from nil to something, triggering logSession.
--
-- Simulate the simplest path: create a session directly in the module's
-- shared state table, then fire the watchdog once.
--
-- The module doesn't export `session`, but X4GunneryControlAPI is global.
-- The easiest way to get logSession called is to call menu.onShowMenu() via
-- the Menus table that was populated by init(). However that requires a full
-- Helper.registerMenu frame path.
--
-- Better: sessionWatchdog calls logSession when the signature changes.
-- A fresh session (via menu.onShowMenu stub path) would work, but
-- onShowMenu calls menu.display() which needs a working frame.
-- Instead, we note that the first pendingCallback IS sessionWatchdog.
-- On first call with session==nil it does nothing and re-registers.
-- We must set session before calling it.
--
-- Access is indirect: we can grab the Menus entry for "X4GunneryMenu" and
-- call onShowMenu. But display() would recurse into Helper.createFrameHandle
-- which we have stubbed. Let's try that path.

local logBefore = #fix.getCapturedLog()
local ok2, err2 = pcall(function() gcMenu.onShowMenu() end)
assert(ok2, "menu.onShowMenu() raised: " .. tostring(err2))

-- Fire the watchdog captured at init. The session now has a state signature,
-- so logSession("watchdog state changed") will be emitted.
assert(initWatchdog ~= nil, "no delayed callbacks were registered")
local ok3, err3 = pcall(fix.runCallback, initWatchdog)
assert(ok3, "sessionWatchdog() raised: " .. tostring(err3))

-- ── 8. assertion 3: logSession output contains required fields ───────────────
local found = nil
for _, line in ipairs(fix.getCapturedLog()) do
    if string.find(line, "lifecycle=", 1, true)
        and string.find(line, "phase=", 1, true)
        and string.find(line, "epoch=", 1, true)
        and string.find(line, "extmenu=", 1, true) then
        found = line
        break
    end
end
assert(found,
    "expected a logSession line with lifecycle=, phase=, epoch=, extmenu= but none found.\nLog:\n"
    .. table.concat(fix.getCapturedLog(), "\n"))

-- ── 9. assertion 4: extmenu= is not a raw function/table reference ───────────
-- A regression where activeExternalMenuName (the function) is concatenated
-- directly produces something like "function: 0x55a1b2c3" or raises an error.
-- We check the captured log lines for any suspicious extmenu= value.
local function extractExtmenu(line)
    local v = string.match(line, "extmenu=([^;]*)")
    return v
end

for _, line in ipairs(fix.getCapturedLog()) do
    if string.find(line, "extmenu=", 1, true) then
        local val = extractExtmenu(line)
        assert(val ~= nil, "extmenu field present but could not be extracted from: " .. line)
        assert(not string.find(val, "^function:"),
            "extmenu= contains a raw function reference; the bug is present. Line: " .. line)
        assert(not string.find(val, "^table:"),
            "extmenu= contains a raw table reference. Line: " .. line)
    end
end

print("runtime init smoke tests passed")
