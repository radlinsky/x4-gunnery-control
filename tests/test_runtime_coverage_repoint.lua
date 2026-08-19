local fix = dofile("tests/support/runtime_fixture.lua").load()
fix.gcMenu.onShowMenu()
local session = fix.API.getSession()
session.phase, session.controlMode, session.repointTargetID = "engaged", "auto", 99
local attempts = 0
fix.C.SetSofttarget = function()
    attempts = attempts + 1
    if attempts == 1 then error("transient") end
    return false
end
fix.API.runSessionWatchdog()
assert(attempts == 2, "watchdog re-point retries one exception then abandons refusal")
assert(session.repointTargetID == nil, "abandoned re-point must leave nothing pending")
assert(session.repointResumeRetry == nil, "abandoned re-point must leave no resume grant")
assert(session.repointRetryArmed == nil, "abandoned re-point must leave no armed retry")
fix.API.runSessionWatchdog()
assert(attempts == 2, "an abandoned re-point must not be retried on a later watchdog tick")
local requestsBefore = #fix.uiTriggeredEvents
fix.fireUIEvent("gameLoadingDone")
assert(#fix.uiTriggeredEvents == requestsBefore + 1,
    "gameLoadingDone must force a new state_request, abandoning the dead pre-load one")
assert(fix.uiTriggeredEvents[#fix.uiTriggeredEvents].control == "state_request",
    "gameLoadingDone forced request must emit state_request")

-- A generic (non-resume) Direct-mode re-point keeps the standing contract:
-- a normal SetSofttarget refusal abandons immediately and is never retried,
-- because only the explicit resume handoff carries the one-retry allowance.
do
    local fix2 = dofile("tests/support/runtime_fixture.lua").load()
    fix2.gcMenu.onShowMenu()
    local session2 = fix2.API.getSession()
    session2.phase, session2.controlMode = "engaged", "direct"
    session2.aimTargetID = 99
    session2.repointTargetID = 99
    local genericAttempts = 0
    fix2.C.SetSofttarget = function()
        genericAttempts = genericAttempts + 1
        return false
    end
    fix2.API.runSessionWatchdog()
    assert(genericAttempts == 1, "generic refusal must not be retried immediately")
    assert(session2.repointTargetID == nil, "generic refusal must abandon, not stay pending")
    assert(session2.repointResumeRetry == nil, "generic refusal must leave no resume grant")
    assert(session2.repointRetryArmed == nil, "generic refusal must leave no armed retry")
    fix2.API.runSessionWatchdog()
    assert(genericAttempts == 1, "generic refusal must not schedule a later retry")
end

print("runtime coverage repoint tests passed")
