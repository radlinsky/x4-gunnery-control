-- Physical ingress must wait for X4's get-up lifecycle boundary.
local fix = dofile("tests/support/runtime_fixture.lua").load()
local State = X4GunneryState
local control, opens, getUps = "gunnercontrol", 0, 0
local docked = { name = "DockedMenu", shown = true }
local map = { name = "MapMenu", shown = false }
local dockedCallback

docked.registerCallback = function(_, callback) dockedCallback = callback end
map.onCloseElement = function() map.shown = false end
table.insert(Menus, docked); table.insert(Menus, map)
fix.C.GetPlayerCurrentControlGroup = function() return control end
fix.C.GetUp = function()
    getUps = getUps + 1
    control = ""
    return true
end
GetComponentData = function(_, key) if key == "isplayerowned" then return true end end
fix.C.GetNumUpgradeGroups = function() return 1 end
fix.C.GetUpgradeGroups2 = function() return 1 end
fix.C.GetUpgradeGroupInfo2 = function()
    return { count = 1, currentcomponent = 27, currentmacro = "", slotsize = "", total = 1, operational = 1 }
end
fix.C.IsComponentOperational = function() return true end
fix.ffiStub.new = function() return { [0] = { path = "p", group = "g", contextid = 5 } } end
Helper.getMenu = function(name)
    return name == "DockedMenu" and docked or name == "MapMenu" and map or nil
end
OpenMenu = function(name)
    assert(name == "X4GunneryMenu")
    opens = opens + 1
    fix.gcMenu.shown = true
    fix.gcMenu.onShowMenu()
end

-- init() ran before the DockedMenu stub existed; gameLoadingDone re-runs hooks.
fix.fireUIEvent("gameLoadingDone")
local mark = fix.callbackCheckpoint()
fix.fireUIEvent("gameplanchange", "cockpit")
fix.fireUIEvent("gameplanchange", "cockpit")
fix.drainCallbacksSince(mark)

assert(getUps == 1, "physical ingress must use C.GetUp exactly once")
assert(opens == 0, "physical ingress must not open before DockedMenu cleanup")
assert(fix.API.getSession() == nil, "physical ingress must wait for playerGetUp")

-- Duplicate signals during the engine transition must not request Get Up again.
fix.fireUIEvent("gameplanchange", "cockpit")
dockedCallback()
fix.drainCallbacksSince(mark)
assert(getUps == 1, "pending physical ingress must suppress duplicate Get Up requests")
assert(fix.API.getSession() == nil, "pending ingress must not create a session")

fix.fireEvent("playerGetUp")
local session = fix.API.getSession()
assert(session and session.origin == "onboard" and session.lifecycle == State.lifecycle.reopening,
    "playerGetUp must create the standing onboard handoff")

dockedCallback()
assert(opens == 0, "DockedMenu callback must wait for its cleanup")
fix.API.runSessionWatchdog()
assert(opens == 0, "handoff must wait while DockedMenu is visible")
docked.shown = false
fix.API.runSessionWatchdog()
assert(opens == 1 and session.lifecycle == State.lifecycle.owned,
    "handoff must open once after DockedMenu cleanup")
fix.API.runSessionWatchdog()
assert(opens == 1, "physical ingress must remain one-shot")

session.phase = "console"
fix.gcMenu.onCloseElement("close")
fix.gcMenu.shown = false

-- Map-origin onboard sessions remain valid while standing, then undock ends them.
map.shown = true
mark = fix.callbackCheckpoint()
fix.fireEvent("X4GunneryControl.OpenOnboard", 42)
fix.drainCallbacksSince(mark)
fix.API.runSessionWatchdog()
session = fix.API.getSession()
fix.fireEvent("playerGetUp")
assert(session and session.lifecycle == State.lifecycle.owned and fix.API.getSession() == session,
    "onboard playerGetUp must not end a standing session")
fix.fireEvent("playerUndock")
assert(fix.API.getSession() == nil, "playerUndock must end the standing session")
fix.gcMenu.shown = false

local function beginPhysicalHandoff()
    control, docked.shown = "gunnercontrol", true
    mark = fix.callbackCheckpoint()
    fix.fireUIEvent("gameplanchange", "cockpit")
    fix.drainCallbacksSince(mark)
    fix.fireEvent("playerGetUp")
    return fix.API.getSession()
end

-- An unrelated menu cancels a released handoff.
session = beginPhysicalHandoff()
assert(session and session.lifecycle == State.lifecycle.reopening)
map.shown = true
docked.shown = false
fix.API.runSessionWatchdog()
assert(fix.API.getSession() == nil, "an unrelated menu must cancel the physical handoff")
map.shown = false

-- Leaving the observed ship before DockedMenu cleanup invalidates the handoff.
session = beginPhysicalHandoff()
assert(session and session.lifecycle == State.lifecycle.reopening)
docked.shown = false
fix.C.GetContextByClass = function() return 77 end
fix.API.runSessionWatchdog()
assert(fix.API.getSession() == nil, "a stale ship context must cancel the physical handoff")

-- Undock also clears a Get Up request that has not reached playerGetUp yet.
fix.C.GetContextByClass = function() return 42 end
control, docked.shown = "gunnercontrol", true
mark = fix.callbackCheckpoint()
fix.fireUIEvent("gameplanchange", "cockpit")
fix.drainCallbacksSince(mark)
fix.fireEvent("playerUndock")
fix.fireEvent("playerGetUp")
assert(fix.API.getSession() == nil, "undock must clear pending physical ingress")

print("physical entry lifecycle regression test passed")
