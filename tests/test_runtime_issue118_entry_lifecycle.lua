-- Issue #118: the one lifecycle gap not covered by existing onboard tests.
local fix = dofile("tests/support/runtime_fixture.lua").load()
local State = X4GunneryState
local control, opens, mapCloses = "cockpit", 0, 0
local map = { name = "MapMenu", shown = false }
local docked = { name = "DockedMenu", shown = false }
local dockedCallback
docked.registerCallback = function(_, callback) dockedCallback = callback end
map.onCloseElement = function() mapCloses = mapCloses + 1; map.shown = false end
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
    opens = opens + 1
    fix.gcMenu.shown = true
    fix.gcMenu.onShowMenu()
end
-- init() ran before these menu stubs existed; gameLoadingDone re-runs the hooks.
fix.fireUIEvent("gameLoadingDone")
Helper.closeMenuAndOpenNewMenu = function()
    error("physical release must not replace DockedMenu during the get-up transition")
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
fix.fireUIEvent("gameplanchange", "cockpit")
fix.fireUIEvent("gameplanchange", "cockpit")
fix.drainCallbacksSince(mark)
local releases, release = 0, nil
for _, event in ipairs(fix.uiTriggeredEvents) do
    if event.screen == "X4GunneryControl" and event.control == "chair_release" then
        releases, release = releases + 1, event
    end
end
assert(releases == 1 and release.params.ship == 42, "physical ingress must emit one release for the observed ship")
assert(opens == 1, "physical ingress must not open Gunnery Control before stopped-control")
assert(fix.API.getSession() == nil, "no session may exist before stopped-control")

-- MD's event_player_stopped_control is the release boundary; stale Lua
-- control-group readback is not a second gate.
fix.fireEvent("X4GunneryControl.OpenOnboardReleased", release.params.ship)
session = fix.API.getSession()
assert(session and session.origin == "onboard" and session.lifecycle == State.lifecycle.reopening,
    "released physical ingress must create a standing onboard handoff")
-- Vanilla closes DockedMenu from playerGetUp; until then the handoff waits
-- rather than replacing it mid-transition.
fix.API.runSessionWatchdog()
assert(opens == 1 and fix.API.getSession() == session,
    "handoff must wait while vanilla DockedMenu is still visible")
assert(dockedCallback, "the DockedMenu display hook must be registered")
dockedCallback()
assert(opens == 1 and fix.API.getSession() == session,
    "a late DockedMenu callback must only recheck the pending handoff")
docked.shown = false
fix.fireEvent("playerGetUp")
assert(fix.API.getSession() == session, "late playerGetUp must not destroy a standing onboard handoff")
fix.API.runSessionWatchdog()
assert(opens == 2 and session.lifecycle == State.lifecycle.owned,
    "released handoff must open once after vanilla DockedMenu cleanup")
assert(mapCloses == 1, "physical handoff must not invoke Map teardown")
fix.API.runSessionWatchdog()
assert(opens == 2, "physical reopen must remain one-shot")
control = "cockpit"

session.phase = "console"
fix.gcMenu.onCloseElement("close")
assert(fix.API.getSession() == nil)
fix.gcMenu.shown = false
session = openViaMap()
assert(mapCloses == 2, "Map re-entry must still use its own cleanup path")
assert(opens == 3, "Map re-entry must remain reusable after physical handoff")
fix.fireEvent("playerGetUp")
assert(fix.API.getSession() == session, "Map-origin onboard session must not become seat-bound")
fix.fireEvent("playerUndock")
assert(fix.API.getSession() == nil, "playerUndock must remain an unconditional teardown")

-- An unrelated menu is not the vanilla DockedMenu cleanup: cancel the one-shot.
fix.gcMenu.shown = false
control = "gunnercontrol"
fix.fireEvent("X4GunneryControl.OpenOnboardReleased", 42)
session = fix.API.getSession()
assert(session and session.lifecycle == State.lifecycle.reopening)
map.shown = true
fix.API.runSessionWatchdog()
assert(fix.API.getSession() == nil and opens == 3,
    "a non-DockedMenu external menu must cancel the pending handoff without opening")
map.shown = false

-- The player left the ship before the handoff completed.
fix.fireEvent("X4GunneryControl.OpenOnboardReleased", 42)
assert(fix.API.getSession(), "handoff must be recreatable after cancellation")
fix.C.GetContextByClass = function() return 77 end
fix.API.runSessionWatchdog()
assert(fix.API.getSession() == nil and opens == 3,
    "a stale released handoff must end instead of opening Gunnery Control")

-- With no onboard session standing, get-up stays the ordinary teardown.
fix.fireEvent("playerGetUp")
assert(fix.API.getSession() == nil)

print("Issue #118 entry lifecycle regression tests passed")
