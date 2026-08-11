-- Keep this in its own process: the fixture's camera callback queue is part of
-- the behavior under test, and the coverage runner executes every suite that
-- way too.
local fix = dofile("tests/support/runtime_fixture.lua").load()
local group = {
    key = "g", kind = "group", contextID = 5, path = "p", group = "g",
    componentID = 27, operationalCount = 1, totalCount = 1, mode = "attack", armed = false,
    members = { { componentID = 27, operational = true, cameraSupported = true } },
}
fix.gcMenu.onShowMenu()
local session = fix.API.getSession()
session.groups, session.checkedGroupKeys = { group }, { g = true }
session.phase, session.controlMode, session.cameraMemberID = "engaged", "auto", 27
local focusReads, ready = 0, false
fix.C.GetExternalTargetViewComponent = function()
    focusReads = focusReads + 1
    return focusReads >= 2 and 27 or 7
end
local mark = fix.callbackCheckpoint()
assert(fix.API.enterCamera(group.members[1], { onReady = function(member)
    ready = member.componentID == 27
end }))
fix.drainCallbacksSince(mark)
assert(ready, "camera ready callback must run after retry gate success")

session.phase, session.controlMode = "engaged", "direct"
session.cameraMemberID = 27
session.directSnapshots = { {
    shipID = session.shipID, kind = "group", contextID = 5, path = "p", group = "g",
    mode = "defend", armed = false,
} }
fix.C.GetExternalTargetViewComponent = function() return 7 end
mark = fix.callbackCheckpoint()
assert(fix.API.enterCamera(group.members[1]))
fix.drainCallbacksSince(mark)
assert(session.phase == "console", "normal camera-gate failure must return to console")
print("runtime coverage camera tests passed")
