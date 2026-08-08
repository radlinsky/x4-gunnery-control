local fix = dofile("tests/support/runtime_fixture.lua").load()
fix.gcMenu.onShowMenu()
local session, State = fix.API.getSession(), X4GunneryState
local consolePayload = State.encode(State.saveState({
    shipID = session.shipID, shipName = session.shipName, phase = "target_select",
    groups = {}, checkedGroupKeys = {}, directSnapshots = {},
}))
fix.API.onRestoreEnvelope({ generation = 1, target = 0, payload = consolePayload })
assert(fix.API.getSession().phase == "console", "non-engaged restore must return to console")

-- readGroups' fixture defaults to no groups, so install one live group for
-- the accepted engaged restore and make its camera focus pass immediately.
local groupBuffer = { [0] = { path = "p", group = "g", contextid = 5 } }
fix.C.GetNumUpgradeGroups = function() return 1 end
fix.C.GetUpgradeGroups2 = function() return 1 end
fix.C.GetUpgradeGroupInfo2 = function()
    return { count = 1, currentcomponent = 27, currentmacro = "", slotsize = "", total = 1, operational = 1 }
end
fix.C.GetNumUpgradeSlots = function() return 1 end
fix.C.GetUpgradeSlotCurrentComponent = function() return 27 end
fix.C.GetUpgradeSlotGroup = function() return { path = "p", group = "g" } end
fix.C.IsComponentOperational = function() return true end
fix.C.IsPlayerCameraTargetViewPossible = function() return true end
fix.C.GetExternalTargetViewComponent = function() return 27 end
fix.ffiStub.new = function() return groupBuffer end
local source = State.newSession(42, "gunnercontrol")
source.shipName, source.phase, source.controlMode = "0", "engaged", "auto"
source.groups = { { key = State.groupKey(5, "p", "g"), contextID = 5, path = "p", group = "g",
    members = { { componentID = 27, operational = true, cameraSupported = true } } } }
source.checkedGroupKeys = { [source.groups[1].key] = true }
source.cameraMemberID, source.aimTargetID = 27, 99
-- Chair-ingress delivers into an already open menu; a load/reload waits for it.
fix.gcMenu.shown = true
fix.API.onRestoreEnvelope({ generation = 2, target = 99, payload = State.encode(State.saveState(source)) })
assert(fix.API.getSession().repointTargetID == 99, "engaged restore must queue target re-point")
fix.gcMenu.shown = false
fix.API.onRestoreEnvelope({ generation = 3, target = 99, payload = State.encode(State.saveState(source)) })
assert(fix.API.getSession().lifecycle == State.lifecycle.reopening,
    "closed-menu restore must await the menu through reopening lifecycle")
print("runtime coverage restore tests passed")
