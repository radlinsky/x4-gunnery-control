-- Fire-control observability: the Test Lab's Lua half.
--
-- MD owns the sample loop and every log line, so what is asserted here is only
-- the narrow contract between the two: the toggle really flips and really tells
-- MD which way, the marker fires unconditionally, and the state pusher stays
-- silent while disabled. The last one matters most -- a pusher that ran while
-- disabled would keep feeding MD stale soft targets after the owner switched
-- logging off, and nothing downstream would notice.

package.loaded["ffi"] = nil
local fix = dofile("tests/support/runtime_fixture.lua").load()

Helper.clearMenu = function(menu)
    Helper.clearDataForRefresh(menu)
    if menu then menu.frames = {} end
end
Helper.getMenu = function(name)
    for _, candidate in ipairs(Menus or {}) do
        if candidate.name == name then return candidate end
    end
end
Helper.closeMenuAndOpenNewMenu = function() end
Helper.closeMenu = function() end

X4GunneryTestLabState = nil
dofile("testlab/x4_gunnery_control_testlab/ui/testlab_state.lua")
dofile("testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua")
assert(pcall(dofile, "testlab/x4_gunnery_control_testlab/ui/testlab.lua"))

local testMenu
for _, candidate in ipairs(Menus) do
    if candidate.name == "X4GunneryTestLab" then testMenu = candidate; break end
end
assert(testMenu, "X4GunneryTestLab was not registered")

-- ReadText in the fixture returns "text:<page>:<id>", so ids 29 and 30 are the
-- toggle and the marker. Matching on the id prefix keeps the test indifferent
-- to the ON/OFF suffix the toggle appends to its own label.
local TOGGLE, MARK = "text:20992:29", "text:20992:30"

-- getCreatedButtons() rather than a cached list: every display() clears the
-- record, so the toggle must be re-found after each rebuild.
local function findButton(prefix)
    for _, button in ipairs(fix.getCreatedButtons()) do
        if type(button.text) == "string" and button.text:sub(1, #prefix) == prefix then return button end
    end
end

local function lastEvent(control)
    for index = #fix.uiTriggeredEvents, 1, -1 do
        local entry = fix.uiTriggeredEvents[index]
        if entry.control == control then return entry end
    end
end

local function countEvents(control)
    local count = 0
    for _, entry in ipairs(fix.uiTriggeredEvents) do
        if entry.control == control then count = count + 1 end
    end
    return count
end

testMenu.onShowMenu()

-- Off by default: the extension being installed must not start logging.
local toggle = findButton(TOGGLE)
assert(toggle, "fire-control logging toggle was not rendered")
assert(toggle.text:find("OFF", 1, true), "logging must start disabled, got " .. tostring(toggle.text))
assert(countEvents("observe_state") == 0, "state was pushed before logging was armed")

-- Arming sends enabled=true and primes the pusher in the same click.
toggle.handlers.onClick()
local armed = lastEvent("observe_toggle")
assert(armed and armed.screen == "X4GunneryTestLabObserve", "toggle did not reach the observe script")
assert(armed.params.enabled == true, "arming must send enabled=true")
assert(countEvents("observe_state") == 1, "arming did not push an initial state sample")
assert(findButton(TOGGLE).text:find("ON", 1, true), "toggle label did not follow state")

-- With no Direct-control session the payload carries no session fields at all.
-- This is the ordinary free-play path, where MD falls back to player.target.
local state = lastEvent("observe_state")
assert(state.params.prefer == nil, "prefer must be absent without a session")
assert(state.params.aimtgt == nil, "aimtgt must be absent without a session")

-- A session supplies the two facts MD cannot read for itself.
X4GunneryControlAPI.getSession = function()
    return { preferAllTurrets = true, aimTargetID = 4242 }
end
X4GunneryControlAPI.getTestSofttarget = function()
    return { id = "1637331", connection = "", name = "", macro = "" }
end
local observeClock = 0
getElapsedTime = function() return observeClock end
fix.runCallback(fix.pendingCallbacks[#fix.pendingCallbacks])
state = lastEvent("observe_state")
assert(state.params.prefer == true, "prefer was not forwarded from the session")
assert(state.params.aimtgt == 4242, "aimtgt was not forwarded from the session")
assert(state.params.softtgt == 1637331, "softtgt was not forwarded")
assert(countEvents("observe_mark") == 1,
    "a new Direct-control aim target must trigger one automatic engageability snapshot")
fix.runCallback(fix.pendingCallbacks[#fix.pendingCallbacks])
assert(countEvents("observe_mark") == 1,
    "an unchanged Direct-control aim target must not trigger duplicate snapshots")
observeClock = 21
fix.runCallback(fix.pendingCallbacks[#fix.pendingCallbacks])
assert(countEvents("observe_mark") == 2,
    "an aim target held for 20 seconds must trigger one settled snapshot")
observeClock = 42
fix.runCallback(fix.pendingCallbacks[#fix.pendingCallbacks])
assert(countEvents("observe_mark") == 2,
    "a settled aim target must not trigger another delayed snapshot")

-- The 20-second settled mark measures engagement time, not wall-clock time.
-- A long pause must not produce the same premature duplicate snapshot that
-- invalidated the first live arc capture.
X4GunneryControlAPI.getSession = function()
    return { preferAllTurrets = true, aimTargetID = 4243 }
end
local paused = false
X4GunneryControlAPI.isGamePaused = function() return paused end
observeClock = 43
fix.runCallback(fix.pendingCallbacks[#fix.pendingCallbacks])
assert(countEvents("observe_mark") == 3, "a changed target must start a fresh snapshot window")
paused, observeClock = true, 73
fix.runCallback(fix.pendingCallbacks[#fix.pendingCallbacks])
assert(countEvents("observe_mark") == 3, "paused wall-clock time must not settle the snapshot")
paused, observeClock = false, 74
fix.runCallback(fix.pendingCallbacks[#fix.pendingCallbacks])
assert(countEvents("observe_mark") == 3, "one unpaused second must not settle the snapshot")
observeClock = 94
fix.runCallback(fix.pendingCallbacks[#fix.pendingCallbacks])
assert(countEvents("observe_mark") == 4, "20 unpaused seconds must settle the snapshot")

-- "Nothing selected" is reported as id "0"; forwarding it would make MD prefer a
-- dead id over player.target, so it must be dropped rather than sent.
X4GunneryControlAPI.getTestSofttarget = function()
    return { id = "0", connection = "", name = "", macro = "" }
end
fix.runCallback(fix.pendingCallbacks[#fix.pendingCallbacks])
assert(lastEvent("observe_state").params.softtgt == nil, "empty soft target must not be forwarded")

-- The marker is deliberately accepted whatever the toggle says, so a mark is
-- never silently swallowed by logging having been left off.
findButton(MARK).handlers.onClick()
assert(lastEvent("observe_mark"), "marker did not reach the observe script")

-- Disarming stops the pusher. Draining the queued callback must produce no
-- further state events, which is the whole point of the guard.
findButton(TOGGLE).handlers.onClick()
assert(lastEvent("observe_toggle").params.enabled == false, "disarming must send enabled=false")
local before = countEvents("observe_state")
fix.runCallback(fix.pendingCallbacks[#fix.pendingCallbacks])
assert(countEvents("observe_state") == before, "state pusher kept running after logging was disabled")

-- A UI reload creates a fresh file-local `observing` value while MD keeps its
-- cue variables. The new instance must explicitly turn MD off so its button
-- and its listener cues cannot disagree. Loading the file again is the test
-- fixture's equivalent of ScheduleReloadUI for this companion module.
local reloadToggle = findButton(TOGGLE)
reloadToggle.handlers.onClick() -- arm again so reload exercises stale-ON state
assert(lastEvent("observe_toggle").params.enabled == true, "reload setup failed to arm logging")
assert(pcall(dofile, "testlab/x4_gunnery_control_testlab/ui/testlab.lua"),
    "reloading the Test Lab UI must succeed")
local reloadedOff = lastEvent("observe_toggle")
assert(reloadedOff and reloadedOff.params.enabled == false,
    "a fresh Test Lab UI must disable the persistent MD observer")
local reloadedMenu
for index = #Menus, 1, -1 do
    if Menus[index].name == "X4GunneryTestLab" then reloadedMenu = Menus[index]; break end
end
assert(reloadedMenu, "reloaded Test Lab menu was not registered")
reloadedMenu.onShowMenu()
assert(findButton(TOGGLE).text:find("OFF", 1, true),
    "reloaded Test Lab UI must render logging OFF")

print("testlab observability checks passed")
