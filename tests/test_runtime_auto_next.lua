-- Automatic replacement must use fresh complete range evidence at every stage.
local fix = dofile("tests/support/runtime_fixture.lua").load()
local API, menu, C = fix.API, fix.gcMenu, fix.C
local now, soft = 100, 0
getElapsedTime = function() return now end
local alive, enemy, ships, stations, surfaces, sizes, distances = {}, {}, {}, {}, {}, {}, {}
local events, choices = {}, {}
AddUITriggeredEvent = function(_, control, params)
    assert(not control:find("engageability"), "Auto-next must never request ENGAGEABLE")
    events[#events + 1] = { control = control, params = params }
end
C.GetSofttarget2 = function() return { softtargetID = soft, softtargetConnectionName = "" } end
C.SetSofttarget = function(target) soft = target; choices[#choices + 1] = target; return true end
C.IsComponentOperational = function(target) return alive[tonumber(target)] == true end
C.IsComponentClass = function(target, class)
    return class == "ship" and tonumber(target) < 700
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
        if key == "isenemy" then value = enemy[tonumber(target)] ~= "hostile"
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

-- Size precedes distance, count never ranks, and a partial positive cannot select.
local s = setup(true, 3)
-- Start again after setting metadata so the production enumeration sorts it.
s.targetFallback = nil
sizes[702], sizes[703], sizes[704] = "L", "M", "L"
distances[702], distances[704] = 2000, 1000
API.updateAimTarget()
assert(events[#events - 3].params.target == 704, "largest then nearest surface must scan first")
reply(pending(), "100")
API.updateAimTarget()
assert(#choices == 0, "partial positive cannot engage")
pass("110")
API.updateAimTarget()
assert(s.aimTargetID == 704 and #choices == 1, "first qualifying surface wins over higher count")

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
-- A whole-browser attempt spans transport batches, never selects a partial page.
objectSetup(21)
reply(pending(), string.rep("1", 20))
API.updateAimTarget(); assert(#choices == 0)
pass("0")
API.updateAimTarget(); assert(#choices == 0, "second turret still required")
pass(string.rep("0", 20)); pass("0")
API.updateAimTarget(); assert(s.aimTargetID == 101)

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

-- Destruction and ownership changes invalidate a complete sweep before selection.
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
menu.display = originalDisplay
print("runtime Auto-next IN RANGE tests passed")
