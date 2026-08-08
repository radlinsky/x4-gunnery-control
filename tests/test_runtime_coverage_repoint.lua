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
local requestsBefore = #fix.uiTriggeredEvents
fix.fireUIEvent("gameLoadingDone")
assert(#fix.uiTriggeredEvents == requestsBefore,
    "gameLoadingDone must coalesce an already-outstanding persistence request")
print("runtime coverage repoint tests passed")
