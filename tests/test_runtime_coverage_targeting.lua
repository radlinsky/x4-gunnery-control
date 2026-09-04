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

-- Cover both developer sweep views. The read-only variant must freshly inspect
-- hardware without relying on session reconciliation.
local groupBuffer = { [0] = { path = "p", group = "g", contextid = 5 } }
fix.ffiStub.new = function() return groupBuffer end
fix.C.GetNumUpgradeGroups = function() return 1 end
fix.C.GetUpgradeGroups2 = function() return 1 end
fix.C.GetUpgradeGroupInfo2 = function()
    return { count = 1, currentcomponent = 27, currentmacro = "", slotsize = "", total = 1, operational = 1 }
end
fix.C.GetNumUpgradeSlots = function() return 1 end
fix.C.GetUpgradeSlotCurrentComponent = function() return 27 end
fix.C.GetUpgradeSlotGroup = function() return { path = "p", group = "g" } end
fix.C.GetTurretGroupMode2 = function() return "attack" end
fix.C.IsTurretGroupArmed = function() return false end
fix.C.IsPlayerCameraTargetViewPossible = function() return true end
fix.C.GetComponentName = function(component) return component == session.shipID and "Test Ship" or "Test Turret" end
GetComponentData = function(_, field)
    if field == "macro" then return "test_macro" end
    if field == "isplayerowned" then return true end
end
local fresh = fix.API.getCurrentShipSweepReadOnly()
assert(fresh and #fresh.groups == 1 and #fresh.groups[1].members == 1,
    "read-only current-ship sweep must inspect the current hardware")
local reconciled = fix.API.getCurrentShipSweep()
assert(reconciled and #reconciled.groups == 1 and #reconciled.groups[1].members == 1,
    "legacy current-ship sweep must still refresh and return groups")

-- Onboard sessions (standing, no gunner seat) must still get a fresh
-- read-only sweep while the session context holds, and must be rejected once
-- the player is no longer aboard the session's ship.
session.origin = "onboard"
fix.C.GetPlayerCurrentControlGroup = function() return "main" end
fix.C.GetPlayerOccupiedShipID = function() return session.shipID end
local onboard = fix.API.getCurrentShipSweepReadOnly()
assert(onboard and #onboard.groups == 1 and #onboard.groups[1].members == 1,
    "read-only sweep must work for an onboard session without a gunner seat")
fix.C.GetPlayerOccupiedShipID = function() return session.shipID + 1 end
local rejected, reason = fix.API.getCurrentShipSweepReadOnly()
assert(rejected == nil and reason ~= nil,
    "read-only sweep must reject a session whose occupied ship no longer matches")
print("runtime coverage targeting tests passed")
