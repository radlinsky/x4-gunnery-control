local fix = dofile("tests/support/runtime_fixture.lua").load()
local group = {
    key = "g", kind = "group", contextID = 5, path = "p", group = "g",
    componentID = 27, operationalCount = 1, totalCount = 1, mode = "attack", armed = false,
    members = { { componentID = 27, operational = true, cameraSupported = true } },
}
fix.gcMenu.onShowMenu()
local session = fix.API.getSession()
session.groups, session.checkedGroupKeys, session.cameraMemberID = { group }, { g = true }, 27
fix.C.GetExternalTargetViewComponent = function() return 27 end
assert(fix.API.startAutoEngage({ group }), "Auto entry must succeed with a camera member")
assert(fix.uiTriggeredEvents[#fix.uiTriggeredEvents].control == "session_commit",
    "Auto entry must commit its session")

session.phase, session.controlMode, session.directSnapshots = "target_select", nil, {}
fix.C.GetContextByClass = function(_, class)
    if class == "container" then return 98 end
    return 42
end
assert(fix.API.engageTarget(99), "Direct entry must accept an external target")
assert(session.phase == "engaged" and session.controlMode == "direct",
    "Direct entry must build the engaged session")

-- The refusal branch: a player-owned root is rejected, so entering Direct
-- against one leaves the existing engagement untouched.
GetComponentData = function(_, key)
    if key == "isplayerowned" then return true end
    return nil
end
assert(not fix.API.engageTarget(99), "Direct entry must refuse a player-owned target")
GetComponentData = function() return nil end
print("runtime coverage engagement tests passed")
