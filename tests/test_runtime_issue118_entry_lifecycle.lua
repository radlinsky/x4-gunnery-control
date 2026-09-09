-- Issue #118: the one lifecycle gap not covered by existing onboard tests.
local fix = dofile("tests/support/runtime_fixture.lua").load()
local State = X4GunneryState
local control, opens, mapCloses = "cockpit", 0, 0
local getUps, getUpResult = 0, true
local map = { name = "MapMenu", shown = false }
local docked = { name = "DockedMenu", shown = false }
local dockedCallback
docked.registerCallback = function(_, callback) dockedCallback = callback end
map.onCloseElement = function() mapCloses = mapCloses + 1; map.shown = false end
table.insert(Menus, map); table.insert(Menus, docked)
fix.C.GetPlayerCurrentControlGroup = function() return control end
fix.C.GetUp = function()
    getUps = getUps + 1
    if getUpResult then control = "" end
    return getUpResult
end
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

local function assertNoChairRelease(message)
    for _, event in ipairs(fix.uiTriggeredEvents) do
        assert(not (event.screen == "X4GunneryControl" and event.control == "chair_release"), message)
    end
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
getUps, getUpResult = 0, true
fix.resetUITriggeredEvents()
local mark = fix.callbackCheckpoint()
fix.fireUIEvent("gameplanchange", "cockpit")
fix.fireUIEvent("gameplanchange", "cockpit")
fix.drainCallbacksSince(mark)
assert(getUps == 1, "physical ingress must use vanilla Get Up exactly once")
assertNoChairRelease("physical ingress must not depend on the unproven chair_release MD bridge")
assert(opens == 1, "physical ingress must not open Gunnery Control before DockedMenu cleanup")
assert(fix.API.getSession() == nil,
    "successful Get Up must wait for playerGetUp before creating a session")

-- Repeated menu signals while X4 is completing Get Up must not request it again.
fix.fireUIEvent("gameplanchange", "cockpit")
dockedCallback()
fix.drainCallbacksSince(mark)
assert(getUps == 1, "pending physical ingress must suppress duplicate Get Up requests")
assert(fix.API.getSession() == nil,
    "duplicate ingress before playerGetUp must not create a session")

fix.fireEvent("playerGetUp")
session = fix.API.getSession()
assert(session and session.origin == "onboard" and session.lifecycle == State.lifecycle.reopening,
    "playerGetUp must create the standing onboard handoff")
assert(session.shipID == 42 and session.physicalReleasePending == true,
    "playerGetUp must consume the exact observed ship into one physical handoff")

-- The playerGetUp handler creates the handoff, but vanilla DockedMenu must still
-- finish its own cleanup before Gunnery replaces it.
fix.API.runSessionWatchdog()
assert(opens == 1 and fix.API.getSession() == session,
    "handoff must wait while vanilla DockedMenu is still visible")
assert(dockedCallback, "the DockedMenu display hook must be registered")
dockedCallback()
assert(opens == 1 and fix.API.getSession() == session,
    "a late DockedMenu callback must only recheck the pending handoff")
docked.shown = false
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
fix.gcMenu.shown = false

-- If the engine refuses Get Up, do not create a standing session or fall back
-- to the old MD bridge. The next physical interaction must start cleanly.
control, docked.shown = "gunnercontrol", true
getUps, getUpResult = 0, false
fix.resetUITriggeredEvents()
mark = fix.callbackCheckpoint()
fix.fireUIEvent("gameplanchange", "cockpit")
fix.drainCallbacksSince(mark)
assert(getUps == 1, "a physical ingress attempt must call Get Up once even when X4 refuses it")
assertNoChairRelease("Get Up refusal must not fall back to chair_release")
assert(fix.API.getSession() == nil, "Get Up refusal must not leave a ghost onboard session")
assert(opens == 3, "Get Up refusal must not open Gunnery Control")

-- A successful retry proves refusal left no pending ingress. Undock must then
-- clear that pending ship before playerGetUp can consume it.
getUpResult = true
mark = fix.callbackCheckpoint()
fix.fireUIEvent("gameplanchange", "cockpit")
fix.drainCallbacksSince(mark)
assert(getUps == 2 and fix.API.getSession() == nil,
    "Get Up refusal must leave physical ingress immediately retryable")
fix.fireEvent("playerUndock")
fix.fireEvent("playerGetUp")
assert(fix.API.getSession() == nil,
    "playerUndock must clear pending physical ingress before playerGetUp")

control = "gunnercontrol"
mark = fix.callbackCheckpoint()
fix.fireUIEvent("gameplanchange", "cockpit")
fix.drainCallbacksSince(mark)
assert(getUps == 3 and fix.API.getSession() == nil,
    "physical ingress must restart cleanly after playerUndock")
fix.fireEvent("playerUndock")
docked.shown = false

-- Keep the old uniquely named MD completion event as a compatibility receiver:
-- an already-pending release from a save may still arrive after this correction.
-- An unrelated menu is not the vanilla DockedMenu cleanup: cancel the one-shot.
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
