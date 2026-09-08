-- Issue #118: the one lifecycle gap not covered by existing onboard tests.
local fix = dofile("tests/support/runtime_fixture.lua").load()
local State = X4GunneryState
local control, replacements = "cockpit", 0
local map = { name = "MapMenu", shown = false }
local docked = { name = "DockedMenu", shown = false }
map.onCloseElement = function() map.shown = false end
table.insert(Menus, map); table.insert(Menus, docked)
fix.C.GetPlayerCurrentControlGroup = function() return control end
GetComponentData = function(_, key) if key == "isplayerowned" then return true end end
fix.C.GetNumUpgradeGroups = function() return 1 end
fix.C.GetUpgradeGroups2 = function() return 1 end
fix.C.GetUpgradeGroupInfo2 = function()
    return { count = 1, currentcomponent = 27, currentmacro = "", slotsize = "", total = 1, operational = 1 }
end
fix.C.IsComponentOperational = function() return true end
fix.ffiStub.new = function() return { [0] = { path = "p", group = "g", contextid = 5 } } end
Helper.getMenu = function(name) return name == "MapMenu" and map or name == "DockedMenu" and docked or nil end
OpenMenu = function(name)
    assert(name == "X4GunneryMenu")
    fix.gcMenu.shown = true
    fix.gcMenu.onShowMenu()
end
Helper.closeMenuAndOpenNewMenu = function(from, name)
    assert(from == docked and name == "X4GunneryMenu")
    replacements = replacements + 1
    docked.shown, fix.gcMenu.shown = false, true
    fix.gcMenu.onShowMenu()
end

local function openViaMap()
    map.shown = true
    local mark = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.OpenOnboard", 42)
    local session = fix.API.getSession()
    assert(session and session.origin == "onboard" and session.lifecycle == State.lifecycle.suspendedMap)
    fix.drainCallbacksSince(mark)
    assert(not map.shown)
    fix.API.runSessionWatchdog()
    session = fix.API.getSession()
    assert(session and session.lifecycle == State.lifecycle.owned)
    return session
end

-- Known failing sequence: Map -> exit -> physical console while vanilla DockedMenu is visible.
local session = openViaMap()
session.phase = "console"
fix.gcMenu.onCloseElement("close")
assert(fix.API.getSession() == nil)
fix.gcMenu.shown = false

control, docked.shown = "gunnercontrol", true
fix.resetUITriggeredEvents()
local mark = fix.callbackCheckpoint()
fix.API.runSessionWatchdog(); fix.API.runSessionWatchdog()
fix.drainCallbacksSince(mark)
local releases, release = 0, nil
for _, event in ipairs(fix.uiTriggeredEvents) do
    if event.screen == "X4GunneryControl" and event.control == "chair_release" then
        releases, release = releases + 1, event
    end
end
assert(releases == 1 and release.params.ship == 42, "physical ingress must emit one release for the observed ship")
assert(fix.API.getSession() == nil, "no session may exist before stopped-control")

control = "cockpit"
fix.fireEvent("X4GunneryControl.OpenOnboardReleased", release.params.ship)
session = fix.API.getSession()
assert(session and session.origin == "onboard" and session.lifecycle == State.lifecycle.reopening,
    "released physical ingress must create a standing onboard handoff")
assert(replacements == 0, "MD release event must not replace DockedMenu directly")
fix.fireEvent("playerGetUp")
assert(fix.API.getSession() == session, "playerGetUp must not destroy a standing onboard handoff")
fix.API.runSessionWatchdog()
assert(replacements == 1 and session.lifecycle == State.lifecycle.owned,
    "DockedMenu must be replaced once and converge to normal owned lifecycle")
fix.API.runSessionWatchdog()
assert(replacements == 1, "physical replacement must remain one-shot")

session.phase = "console"
fix.gcMenu.onCloseElement("close")
assert(fix.API.getSession() == nil)
fix.gcMenu.shown = false
session = openViaMap()
fix.fireEvent("playerGetUp")
assert(fix.API.getSession() == session, "Map-origin onboard session must not become seat-bound")
fix.fireEvent("playerUndock")
assert(fix.API.getSession() == nil, "playerUndock must remain an unconditional teardown")

print("Issue #118 entry lifecycle regression tests passed")
