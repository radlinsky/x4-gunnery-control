local fix = dofile("tests/support/runtime_fixture.lua").load()
fix.gcMenu.onShowMenu()
local session = fix.API.getSession()
session.phase, session.controlMode, session.aimTargetID = "engaged", "auto", 99
fix.C.IsComponentOperational = function() return true end
GetContainedShips, GetContainedStations = function() return {} end, function() return {} end
fix.API.updateAimTarget()
assert(session.aimTargetID == nil and session.targetObjectID == nil,
    "Auto target loss must clear target state while staying engaged")
assert(fix.uiTriggeredEvents[#fix.uiTriggeredEvents].control == "session_commit",
    "Auto target loss must persist explicit no-target state")
print("runtime coverage targeting tests passed")
