local fix = dofile("tests/support/runtime_fixture.lua").load()
local group = {
    key = "g", kind = "group", contextID = 5, path = "p", group = "g",
    componentID = 27, displayName = "Group", operationalCount = 1, totalCount = 1, mode = "attack", armed = false,
    members = { { componentID = 27, displayName = "Turret", operational = true, cameraSupported = true } },
}
fix.gcMenu.onShowMenu()
local session = fix.API.getSession()
session.groups, session.checkedGroupKeys = { group }, { g = true }
session.phase, session.controlMode, session.cameraMemberID = "engaged", "auto", 27
fix.C.GetExternalTargetViewComponent = function() return 27 end
fix.gcMenu.display()
for _, id in ipairs({ 71, 72 }) do
    local entry = fix.buttonByText("text:20991:" .. id)
    assert(entry and entry.handlers and type(entry.handlers.onClick) == "function",
        "cycle turret button must expose its production handler")
    local checkpoint = fix.callbackCheckpoint()
    entry.handlers.onClick()
    assert(fix.callbackCheckpoint() > checkpoint,
        "cycle turret button " .. tostring(id) .. " must schedule its camera gate")
end
print("runtime coverage ui tests passed")
