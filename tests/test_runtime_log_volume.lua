-- Default logging is intentionally sparse: failures and one-shot lifecycle
-- transitions only. These regressions keep routine work from becoming a
-- per-tick telemetry stream.

local fix = dofile("tests/support/runtime_fixture.lua").load()
local gcMenu, API, C = fix.gcMenu, fix.API, fix.C
local State = X4GunneryState

gcMenu.onShowMenu()
local session = API.getSession()
assert(session, "log-volume test requires a live session")

local function countLogs(needle)
    local count = 0
    for _, line in ipairs(fix.getCapturedLog()) do
        if string.find(line, needle, 1, true) then count = count + 1 end
    end
    return count
end

-- Empty persistence replies are the normal no-save path and must stay silent.
local emptyBefore = #fix.getCapturedLog()
API.onRestoreEnvelope({ generation = 1, target = 0, payload = "" })
API.onRestoreEnvelope({ generation = 2, target = 0, payload = "" })
assert(#fix.getCapturedLog() == emptyBefore,
    "repeated empty restores must not add default log lines")

-- Ordinary persistence commits and cinematic start/stop are normal actions.
session.phase, session.controlMode = "engaged", "auto"
session.cameraMemberID, session.aimTargetID = 27, 99
local routineBefore = #fix.getCapturedLog()
assert(API.persistence():commit(session), "ordinary persistence commit must succeed")
API.sendCutsceneAimStart("turret")
API.sendCutsceneAimStop()
assert(#fix.getCapturedLog() == routineBefore,
    "ordinary commits and cinematic start/stop must be log-silent")

-- An impossible cinematic start is still a useful one-shot failure diagnostic.
session.cameraMemberID = nil
API.sendCutsceneAimStart("turret")
API.sendCutsceneAimStart("turret")
assert(countLogs("cutscene aim could not start: no turret resolved") == 1,
    "continuing missing cinematic turret must log once")
session.cameraMemberID = 27
API.sendCutsceneAimStart("turret")
session.cameraMemberID = nil
API.sendCutsceneAimStart("turret")
assert(countLogs("cutscene aim could not start: no turret resolved") == 2,
    "a successful cinematic start must reset the missing-turret failure latch")
session.cameraMemberID = 27

-- Each sector-enumeration source logs once while it keeps failing, resets on a
-- successful call, then logs once again for a new failure episode.
GetPlayerContextByClass = function() return 1 end
GetContainedShips = function() error("ships unavailable") end
GetContainedStations = function() error("stations unavailable") end
local scanClock = 100
getElapsedTime = function() return scanClock end
API.updateAimTarget()
scanClock = scanClock + 6
API.updateAimTarget()
assert(countLogs("GetContainedShips failed:") == 1,
    "continuing ship-scan failure must log once")
assert(countLogs("GetContainedStations failed:") == 1,
    "continuing station-scan failure must log once")
GetContainedShips = function() return {} end
GetContainedStations = function() return {} end
scanClock = scanClock + 6
API.updateAimTarget()
GetContainedShips = function() error("ships unavailable again") end
GetContainedStations = function() error("stations unavailable again") end
scanClock = scanClock + 6
API.updateAimTarget()
assert(countLogs("GetContainedShips failed:") == 2,
    "ship-scan recovery must open exactly one new failure episode")
assert(countLogs("GetContainedStations failed:") == 2,
    "station-scan recovery must open exactly one new failure episode")

-- A parked reopen that never displays retries forever. Enter through the real
-- onboard pre-open handoff so the generic reopening lifecycle and pending-resume
-- state are both established by production behavior.
fix = dofile("tests/support/runtime_fixture.lua").load()
gcMenu, API, C = fix.gcMenu, fix.API, fix.C
State = X4GunneryState
GetComponentData = function(_, key)
    if key == "isplayerowned" then return true end
    return nil
end
local groupBuffer = { [0] = { path = "p", group = "g", contextid = 5 } }
fix.ffiStub.new = function() return groupBuffer end
C.GetNumUpgradeGroups = function() return 1 end
C.GetUpgradeGroups2 = function() return 1 end
C.GetUpgradeGroupInfo2 = function()
    return {
        count = 1, currentcomponent = 27, currentmacro = "", slotsize = "",
        total = 1, operational = 1,
    }
end
C.IsComponentOperational = function() return true end

fix.fireEvent("X4GunneryControl.OpenOnboard", 42)
session = API.getSession()
assert(session and session.lifecycle == State.lifecycle.reopening,
    "onboard pre-open handoff must create a parked reopening session")

local function runFailedParkedReopen()
    local first = #fix.pendingCallbacks + 1
    API.runSessionWatchdog()
    fix.runCallback(fix.pendingCallbacks[first])
end
local reopenBefore = #fix.getCapturedLog()
runFailedParkedReopen()
assert(#fix.getCapturedLog() == reopenBefore + 1
    and countLogs("parked session reopen did not display; retrying:") == 1,
    "first failed parked reopen must add exactly one generic failure line")
runFailedParkedReopen()
assert(#fix.getCapturedLog() == reopenBefore + 1,
    "repeated failed parked reopen must remain silent in the same episode")

-- A real menu display is the success boundary that resets the retry latch.
gcMenu.onShowMenu()
session = API.getSession()
API.registerTestLab({ open = function() end })
gcMenu.display()
local testLabButton = fix.buttonByText(ReadText(20991, 32))
assert(testLabButton and testLabButton.handlers.onClick,
    "successful onboard reopen must expose the Test Lab handoff")
testLabButton.handlers.onClick()
assert(session.lifecycle == State.lifecycle.reopening,
    "Test Lab handoff must park the displayed session for another reopen")
-- This case covers the generic parked-reopen retry latch, not the Test Lab
-- handoff gap: drop the handoff marker so the watchdog owns the reopen again.
session.testLabHandoffPending = nil
gcMenu.shown = false
runFailedParkedReopen()
assert(countLogs("parked session reopen did not display; retrying:") == 2,
    "a successful parked-session display must reset the next failure episode latch")

print("runtime log-volume tests passed")
