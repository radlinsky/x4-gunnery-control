-- test_runtime_init_smoke.lua
-- Module load and init: verifies the concise startup record and quiet normal
-- watchdog ticks.

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

-- ── 6. assertion 1: one accurate startup message ────────────────────────────
local startupCount = 0
for _, line in ipairs(fix.getCapturedLog()) do
    if string.find(line, "[X4GC] UI initialized", 1, true) then
        startupCount = startupCount + 1
        assert(line == "[X4GC] UI initialized; build=2026-08-08-pr-review",
            "startup line must carry the current build label; got: " .. line)
    end
end
assert(startupCount == 1, "expected exactly one startup line, got " .. tostring(startupCount))
assert(type(fix.registeredEvents.playerGetUp) == "table"
    and type(fix.registeredEvents["X4GunneryControl.RestoreGrant"]) == "table",
    "fixture must expose RegisterEvent captures by event name")
assert(#fix.uiTriggeredEvents >= 1
    and fix.uiTriggeredEvents[1].screen == "X4GunneryControl"
    and fix.uiTriggeredEvents[1].control == "state_request",
    "fixture must expose AddUITriggeredEvent captures")

-- ── 7. assertion 2: normal watchdog work is log-silent ──────────────────────
-- init() ends with sessionWatchdog(), which calls
-- Helper.addDelayedOneTimeCallbackOnUpdate(sessionWatchdog, ...).
-- registerUIHooks may queue a retry first; initWatchdog captured the watchdog
-- identity before this test adds any scheduler-contract callbacks.
-- We invoke it exactly once; it will attempt to re-register itself (fine,
-- we just accumulate another entry) and, because no session exists yet on the
-- first tick, it logs nothing extra and exits. We need a session to exist so
-- that normal scheduler work remains silent.
--
-- Simulate the simplest path: create a session directly in the module's
-- shared state table, then fire the watchdog once.
--
-- The module doesn't export `session`, but X4GunneryControlAPI is global.
-- The easiest way to get logSession called is to call menu.onShowMenu() via
-- the Menus table that was populated by init(). However that requires a full
-- Helper.registerMenu frame path.
--
-- A fresh session (via menu.onShowMenu stub path) works because
-- onShowMenu calls menu.display() which needs a working frame.
-- Instead, we note that the first pendingCallback IS sessionWatchdog.
-- On first call with session==nil it does nothing and re-registers.
-- We must set session before calling it.
--
-- Access is indirect: we can grab the Menus entry for "X4GunneryMenu" and
-- call onShowMenu. But display() would recurse into Helper.createFrameHandle
-- which we have stubbed. Let's try that path.

local ok2, err2 = pcall(function() gcMenu.onShowMenu() end)
assert(ok2, "menu.onShowMenu() raised: " .. tostring(err2))

local logBefore = #fix.getCapturedLog()
assert(initWatchdog ~= nil, "no delayed callbacks were registered")
local ok3, err3 = pcall(fix.runCallback, initWatchdog)
assert(ok3, "sessionWatchdog() raised: " .. tostring(err3))

assert(#fix.getCapturedLog() == logBefore,
    "a normal menu open and watchdog tick must not add default telemetry")

print("runtime init smoke tests passed")
