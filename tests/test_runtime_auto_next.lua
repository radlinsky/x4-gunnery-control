-- Automatic replacement uses fresh range evidence; only the top-ranked candidate may select before the sweep completes.
local fix = dofile("tests/support/runtime_fixture.lua").load()
local API, menu, C = fix.API, fix.gcMenu, fix.C
local now, soft = 100, 0
getElapsedTime = function() return now end
local alive, enemy, ships, stations, surfaces, sizes, distances = {}, {}, {}, {}, {}, {}, {}
local events, choices = {}, {}
AddUITriggeredEvent = function(_, control, params)
    assert(not control:find("engageability") and not control:find("clear"),
        "Auto-next must never request ENGAGEABLE or CLEAR")
    events[#events + 1] = { control = control, params = params }
end
C.GetSofttarget2 = function() return { softtargetID = soft, softtargetConnectionName = "" } end
C.SetSofttarget = function(target) soft = target; choices[#choices + 1] = target; return true end
C.IsComponentOperational = function(target) return alive[tonumber(target)] == true end
C.IsComponentClass = function(target, class)
    return (class == "ship" and tonumber(target) < 700 and tonumber(target) ~= 99)
        or (class == "station" and tonumber(target) == 99)
end
C.GetContextByClass = function(target)
    if tonumber(target) >= 700 and tonumber(target) < 800 then return 600 end
    return target
end
C.GetDistanceBetween = function(_, target) return distances[tonumber(target)] or 1000 end
C.GetNumUpgradeSlots = function(target, _, kind)
    return tonumber(target) == 600 and kind == "turret" and #surfaces or 0
end
C.GetUpgradeSlotCurrentComponent = function(_, _, slot) return surfaces[slot] end
C.GetUpgradeSlotCurrentMacro = function(_, _, _, slot) return sizes[surfaces[slot]] or "M" end
GetMacroData = function(macro, key) return key == "size" and macro or "Equipment" end
GetPlayerContextByClass = function() return 1 end
GetContainedShips = function() return ships end
GetContainedStations = function() return stations end
GetComponentData = function(target, ...)
    local values = {}
    for _, key in ipairs({...}) do
        local value = false
        if key == "isenemy" then value = enemy[tonumber(target)] ~= "hostile" and enemy[tonumber(target)] ~= "neutral"
        elseif key == "ishostile" then value = enemy[tonumber(target)] == "hostile"
        elseif key == "isknown" or key == "isradarvisible" then value = true
        elseif key == "maxradarrange" then value = 40000 end
        values[#values + 1] = value
    end
    return unpack(values)
end
local originalDisplay, displays = menu.display, 0
-- Browser visibility is asserted separately from scanner ownership.
menu.display = function() displays = displays + 1 end
local function setup(surface, count)
    menu.onShowMenu()
    local session = API.getSession()
    alive, enemy, ships, stations, surfaces, sizes, distances =
        { [600] = true, [27] = true, [28] = true }, {}, {}, {}, {}, {}, {}
    for i = 1, count or 0 do surfaces[i] = 701 + i; alive[701 + i] = true end
    local group = { key = "g", kind = "group", contextID = 5, path = "p", group = "g",
        totalCount = 2, operationalCount = 2, mode = "attack", armed = true,
        members = { { componentID = 27, operational = true, cameraSupported = true },
                    { componentID = 28, operational = true, cameraSupported = true } } }
    session.groups, session.checkedGroupKeys = { group }, { g = true }
    session.phase, session.controlMode = "engaged", "direct"
    session.cameraMemberID, session.aimTargetID, session.targetObjectID = 27, surface and 701 or 500,  surface and 600 or 500
    session.povAnchor, session.povMode = "turret", "manual"
    soft = session.aimTargetID
    events, choices, displays = {}, {}, 0
    API.updateAimTarget()
    return session
end
local function pending()
    for i = #events, 1, -1 do
        if events[i].control == "in_range_begin" then return events[i].params end
    end
end
local function reply(request, bits)
    fix.fireEvent("X4GunneryControl.InRangeResult", "x4gcr2:" .. request.nonce .. ":" .. request.weaponid .. ":" .. bits)
end
local function pass(bits)
    local mark = #events
    API.runRangeSweep(now)
    local request = pending()
    assert(request and #events > mark, "expected a fresh turret pass")
    reply(request, bits)
    return request
end
local function finish(bits)
    reply(pending(), bits)
    pass(bits)
    API.updateAimTarget()
end

-- Size precedes distance, count never ranks, and a partial positive on a lower-ranked candidate cannot select.
local s = setup(true, 3)
-- Start again after setting metadata so the production enumeration sorts it.
s.targetFallback = nil
sizes[702], sizes[703], sizes[704] = "L", "M", "L"
distances[702], distances[704] = 2000, 1000
API.updateAimTarget()
assert(events[#events - 3].params.target == 704, "largest then nearest surface must scan first")
reply(pending(), "010")
API.updateAimTarget()
assert(#choices == 0, "a partial positive on a lower-ranked surface cannot engage")
pass("110")
API.updateAimTarget()
assert(s.aimTargetID == 704 and #choices == 1, "first qualifying surface wins over higher count")

-- A larger zero-range candidate loses to a smaller positive candidate.
s = setup(true, 2)
reply(pending(), "01"); pass("01"); API.updateAimTarget()
assert(s.aimTargetID == 703, "zero-range surface must never win its metadata rank")

-- Original-root retries have no three-attempt cap.
s = setup(true, 1)
for _ = 1, 4 do
    reply(pending(), "0") -- second turret never replies
    API.runRangeSweep(now)
    now = now + 2.1
    API.runRangeSweep(now); API.updateAimTarget()
    assert(s.targetFallback.stage == "surfaces" and #choices == 0)
end
finish("0")
assert(s.targetFallback.stage == "hull", "a complete zero sweep moves on to the hull")
for _ = 1, 4 do
    now = now + 2.1; API.runRangeSweep(now); API.updateAimTarget()
    assert(s.targetFallback.stage == "hull", "hull retries must not consume browser budget")
end
finish("1"); assert(s.aimTargetID == 600)

-- Losing the root mid-surface scan skips directly to the visible browser.
s = setup(true, 1)
local obsoleteSurface = pending()
alive[600], alive[99], ships = false, true, { 99 }
API.updateAimTarget()
assert(s.phase == "target_select" and s.targetFallback.stage == "objects")
reply(obsoleteSurface, "1"); assert(#choices == 0)
finish("1"); assert(s.aimTargetID == 99)

-- Complete surface pages, original hull, visible browser, and equal relations.
s = setup(true, 21)
finish(string.rep("0", 20))
assert(s.targetFallback.page == 2 and s.targetFallback.stage == "surfaces")
finish("0")
assert(s.targetFallback.stage == "hull")
ships, stations = { 98 }, { 99 }
alive[98], alive[99], enemy[99] = true, true, "hostile"
distances[98], distances[99] = 2000, 500
finish("0")
assert(s.phase == "target_select" and displays > 0 and s.targetFallback.stage == "objects", "browser must visibly open before scanning")
finish("111")
assert(s.aimTargetID == 99 and s.targetObjectID == 99 and s.phase == "engaged", "closer hostile station must beat enemy ship")

-- Hull requires range too, with no browser attempt budget consumed.
s = setup(true, 1)
finish("0")
assert(s.targetFallback.stage == "hull")
finish("1")
assert(s.aimTargetID == 600 and s.targetFallback == nil)

-- Ordinary loss with no eligible objects returns immediately without a scan.
s = setup(false)
assert(s.phase == "target_select" and s.targetFallback == nil)
assert(not pending(), "no candidates must not start a range scan")

local function objectSetup(count)
    s = setup(false)
    ships = {}
    for i = 1, count or 1 do ships[i] = 100 + i; alive[100 + i] = true end
    s.phase, s.aimTargetID, s.targetObjectID = "engaged", 500, 500
    soft = 500
    API.updateAimTarget()
    assert(s.phase == "target_select" and s.targetFallback.attempts == 1)
end
-- A whole-browser attempt spans transport batches; a farther partial positive waits for the sweep.
objectSetup(21)
distances[121] = 500
reply(pending(), string.rep("1", 20))
API.updateAimTarget(); assert(#choices == 0)
pass("0")
API.updateAimTarget(); assert(#choices == 0, "second turret still required")
pass(string.rep("0", 20)); pass("0")
API.updateAimTarget(); assert(s.aimTargetID == 101)

-- The nearest candidate engages on its first IN RANGE turret without waiting for the sweep.
objectSetup(2); distances[102] = 500
reply(pending(), "01"); API.updateAimTarget()
assert(s.aimTargetID == 102 and #choices == 1, "top-ranked positive must engage early")

-- Neutral candidates do not start a browser scan, and a disabled option scans nothing.
s = setup(false)
ships, alive[101], enemy[101] = { 101 }, true, "neutral"
s.phase, s.aimTargetID, s.targetObjectID = "engaged", 500, 500
API.updateAimTarget(); assert(s.targetFallback == nil and not pending())
-- A forced soft target such as a missile is not a ship/station candidate.
ships, soft, alive[900] = {}, 900, true
s.phase, s.aimTargetID, s.targetObjectID = "engaged", 500, 500
API.updateAimTarget(); assert(s.targetFallback == nil and not pending())
enemy[101], s.autoNextTarget = nil, false
s.phase, s.aimTargetID, s.targetObjectID = "engaged", 500, 500
API.updateAimTarget(); assert(s.targetFallback == nil and not pending())

-- Browser ranking uses distance when the complete sweep is consumed.
objectSetup(2)
reply(pending(), "11"); pass("11")
distances[102] = 500
API.updateAimTarget(); assert(s.aimTargetID == 102, "moving nearer candidate must win")

-- Three attempts include malformed replies/timeouts and complete zero sweeps.
objectSetup()
local late = pending()
reply(late, "11") -- wrong length, remains incomplete
now = now + 2.1; API.runRangeSweep(now); API.updateAimTarget()
assert(s.targetFallback.attempts == 2)
reply(late, "1"); API.updateAimTarget(); assert(#choices == 0, "old attempt must not select")
finish("0")
assert(s.targetFallback.attempts == 3)
now = now + 2.1; API.runRangeSweep(now); API.updateAimTarget()
assert(s.phase == "target_select" and s.targetFallback == nil and #choices == 0)
local begins = 0
for _, event in ipairs(events) do if event.control == "in_range_begin" then begins = begins + 1 end end
assert(begins == 4, "two failed attempts and one two-turret sweep, never a fourth attempt")

-- Disabling Auto-next, changing membership, manual engagement, and a new session reject late replies.
objectSetup(); late = pending(); s.autoNextTarget = false
reply(late, "1"); API.updateAimTarget()
assert(s.targetFallback == nil and #choices == 0)
objectSetup(); late = pending(); s.checkedGroupKeys = {}
reply(late, "1"); now = now + 2.1; API.runRangeSweep(now); API.updateAimTarget()
assert(#choices == 0 and s.targetFallback.attempts == 2)
objectSetup(); late = pending(); alive[102] = true
assert(API.engageTarget(102)); reply(late, "1"); API.updateAimTarget()
assert(s.aimTargetID == 102 and #choices == 1)
objectSetup(); late = pending(); setup(false); reply(late, "1")
assert(#choices == 0)

-- Manual tracking of an operational neutral target remains unchanged.
s = setup(false)
s.phase, s.aimTargetID, s.targetObjectID = "engaged", 500, 500
soft, alive[500], enemy[500] = 500, true, "neutral"
API.updateAimTarget()
assert(s.phase == "engaged" and s.aimTargetID == 500 and s.targetFallback == nil)

-- A membership change after completion invalidates the entire result.
objectSetup(); reply(pending(), "1"); pass("1"); s.checkedGroupKeys = {}
API.updateAimTarget()
assert(#choices == 0 and s.targetFallback.attempts == 2)

-- Leaving Direct cancels without forcing a new browser transition.
objectSetup(); late = pending(); s.controlMode, s.phase = nil, "console"
reply(late, "1"); API.updateAimTarget()
assert(s.targetFallback == nil and s.phase == "console" and #choices == 0)

-- Parking cancels the sweep even though it retains the same session; the
-- resumed browser starts a fresh one.
objectSetup(); late = pending()
local labOpened = false
API.registerTestLab({ open = function() labOpened = true end })
originalDisplay()
local lab = assert(fix.buttonByText("text:20991:32"))
lab.handlers.onClick()
assert(labOpened and s.targetFallback == nil)
reply(late, "1")
assert(#choices == 0, "parked session must reject a late positive")
-- This stubbed ship has no readable turret groups; keep the session's groups.
local retainSelection = X4GunneryState.retainSelection
X4GunneryState.retainSelection = function() end
menu.onShowMenu()
X4GunneryState.retainSelection = retainSelection
assert(API.getSession() == s and s.phase == "target_select")
assert(pending() ~= late and s.targetFallback.attempts == 1, "resume must start a fresh Auto-next scan")
finish("1"); assert(s.aimTargetID == 101 and #choices == 1)
API.registerTestLab(nil)

-- A candidate lost after a complete sweep is skipped; the other results still select.
objectSetup(2); reply(pending(), "01"); pass("01"); alive[101] = false
API.updateAimTarget()
assert(s.aimTargetID == 102 and #choices == 1, "a lost browser candidate must not discard the sweep")
s = setup(true, 2); reply(pending(), "11"); pass("11"); alive[702] = false
API.updateAimTarget()
assert(s.aimTargetID == 703 and #choices == 1, "a lost surface must not discard the page")

-- A lost or unattackable sole candidate cannot be selected.
objectSetup(); reply(pending(), "1"); pass("1"); alive[101] = false
API.updateAimTarget(); assert(s.targetFallback == nil and #choices == 0)
objectSetup(); reply(pending(), "1"); pass("1")
local oldData = GetComponentData
GetComponentData = function(target, ...)
    if tonumber(target) == 101 then return false, false end
    return oldData(target, ...)
end
API.updateAimTarget(); assert(s.targetFallback == nil and #choices == 0)
GetComponentData = oldData
-- Auto-next restores the player's POV after the browser's Turret POV; a manual pick does not.
local function lostWithPov(anchor, mode)
    s = setup(false)
    ships, alive[101] = { 101 }, true
    s.phase, s.aimTargetID, s.targetObjectID = "engaged", 500, 500
    s.povAnchor, s.povMode, soft = anchor, mode, 500
    events = {}
    API.updateAimTarget()
    assert(s.phase == "target_select" and s.povAnchor == "turret" and s.povMode == "manual")
end
lostWithPov("target", "manual")
finish("1")
assert(s.aimTargetID == 101 and s.povAnchor == "target" and s.povMode == "manual",
    "Auto-next must keep Target POV")
lostWithPov("target", "cinematic")
local stops = 0
for _, e in ipairs(events) do if e.control == "cutscene_aim_stop" then stops = stops + 1 end end
assert(stops >= 1, "the loss must stop the running cutscene")
finish("1")
assert(s.aimTargetID == 101 and s.povAnchor == "target" and s.povMode == "cinematic",
    "Auto-next must keep the cinematic Target POV")
lostWithPov("target", "cinematic")
assert(API.engageTarget(101))
assert(s.povAnchor == "turret" and s.povMode == "manual", "a manual pick starts in Turret POV manual")
menu.display = originalDisplay
print("runtime Auto-next IN RANGE tests passed")
