-- test_runtime_targeting_surface.lua
-- Bounded IN RANGE dispatch and station surface size resolution.

local fix = dofile("tests/support/runtime_fixture.lua").load()
local gcMenu = fix.gcMenu
local API    = fix.API
local C      = fix.C

-- Shared clock for getElapsedTime; tests advance it explicitly.
local clock = 100
getElapsedTime = function() return clock end

-- A reusable group used across many rendering and targeting tests.
local grp27 = fix.makeGroup{
    key = "grp27", displayName = "G27",
    members = { { componentID = 27, displayName = "T1", operational = true,
                  cameraSupported = true, componentKey = "27" } },
}

-- Bring the module into a known state.
local ok_init, err_init = pcall(function() gcMenu.onShowMenu() end)
assert(ok_init, "onShowMenu() raised: " .. tostring(err_init))
local sess = API.getSession()
assert(sess ~= nil, "expected a live session after onShowMenu()")
-- Sections 58-60 call API.getSession() without a fresh onShowMenu(), so they
-- inherit whatever the current session holds. Pre-populate the minimal group
-- state that section 58's seed58() needs to fire engageability_begin.
-- Also set gcMenu.shown = true, which section 57 (engageability) left behind
-- in the original file; callbacks in section 59 guard on menu.shown.
-- (In the original file this state was left by section 57/engageability.)
sess.groups = {
    { key = "selected", members = {
        { componentID = 101, operational = true },
        { componentID = 102, operational = true },
    } },
}
sess.checkedGroupKeys = { selected = true }
-- Patch GetUpgradeSlotGroup to return a table so that any readGroups() call
-- triggered by onUpdate does not crash (default fixture returns the number 0).
C.GetUpgradeSlotGroup = function() return { path = "p", group = "g" } end
gcMenu.shown = true

-- A full page is dispatched one target at a time; a selected target wins first.
do
    local session = API.getSession()
    assert(API.rangeText(nil) == "0 / 0 IN RANGE"
        and API.rangeText({ count = 2, total = 3 }) == "2 / 3 IN RANGE",
        "IN RANGE always formats ordinary numeric numerator and denominator")
    local oldClass, oldContext, oldData = C.IsComponentClass, C.GetContextByClass, GetComponentData
    C.IsComponentClass = function(object, class)
        local value = tonumber(tostring(object))
        return (value == 801 and class == "ship") or (value == 802 and class == "engine")
    end
    C.GetContextByClass = function(object)
        return tonumber(tostring(object)) == 802 and 801 or 0
    end
    GetComponentData = function(_, key) return key == "maxspeed" and 100 or false end
    assert(API.rangeMovingTarget(801) and API.rangeMovingTarget(802)
        and not API.rangeMovingTarget(803), "only moving ships and their engines get the range allowance")
    GetComponentData = function(_, key) return key == "maxspeed" and 0 or false end
    assert(not API.rangeMovingTarget(801) and not API.rangeMovingTarget(802),
        "stationary-capability ships and engines get no allowance")
    C.IsComponentClass, C.GetContextByClass, GetComponentData = oldClass, oldContext, oldData
    session.phase, session.controlMode = "target_select", nil
    session.groups = {{ key = "selected", members = {
        { componentID = 101, operational = true },
        { componentID = 102, operational = true },
    } }}
    session.checkedGroupKeys = { selected = true }
    local targets = {}
    for target = 701, 720 do targets[#targets + 1] = target end
    API.setRangeTargets(targets, 720)
    local events = {}
    local savedAdd = AddUITriggeredEvent
    AddUITriggeredEvent = function(_, control, params)
        events[#events + 1] = { control = control, params = params }
    end
    API.runRangeSweep(clock)
    assert(#events == 4 and events[1].control == "in_range_begin"
        and events[1].params.targetid == "720" and events[1].params.members == 2
        and events[4].control == "in_range_commit",
        "IN RANGE must request only the selected target with exact selected members")
    API.runRangeSweep(clock)
    assert(#events == 4, "IN RANGE must not overlap pending MD work")
    clock = clock + 2.1
    API.runRangeSweep(clock)
    assert(#events == 8, "timed-out work must be replaced by one request")
    events = { unpack(events, 5) }
    local nonce = events[1].params.nonce
    assert(events[1].params.targetid == "701", "timeout must let the rest of the page advance")
    fix.fireEvent("X4GunneryControl.InRangeResult", "x4gcr1:" .. nonce .. ":701:1:2")
    assert(API.rangeResult(701).count == 1 and API.rangeResult(701).total == 2,
        "IN RANGE must accept an ordinary numeric result")
    clock = clock + 0.25
    API.runRangeSweep(clock)
    assert(#events == 8 and events[5].params.targetid == "702",
        "IN RANGE must spread a 20-row page across update ticks")
    API.setRangeTargets({ 800 }, 800)
    fix.fireEvent("X4GunneryControl.InRangeResult", "x4gcr1:" .. events[5].params.nonce .. ":702:2:2")
    assert(API.rangeResult(702) == nil, "obsolete page result must be discarded")
    API.setRangeTargets(targets, 720)
    local firstTick, firstComplete, peak = clock, nil, 0
    for tick = 1, 120 do
        clock = clock + 0.25
        local before = #events
        API.runRangeSweep(clock)
        local work = #events - before
        peak = math.max(peak, work)
        if work > 0 then
            assert(work == 4, "one update must dispatch at most one target and two members")
            local begin = events[before + 1].params
            fix.fireEvent("X4GunneryControl.InRangeResult",
                "x4gcr1:" .. begin.nonce .. ":" .. begin.targetid .. ":1:2")
        end
        local complete = 0
        for _, target in ipairs(targets) do
            if API.rangeResult(target) then complete = complete + 1 end
        end
        if complete == 20 then firstComplete = clock - firstTick; break end
    end
    assert(firstComplete and peak == 4, "full page must complete with bounded per-update work")
    print(string.format("offline IN RANGE 20-row sweep: peak 1 target / 2 members / %d events per update; first complete %.2fs", peak, firstComplete))
    session.checkedGroupKeys = {}
    API.setRangeTargets({ 900 }, 900)
    clock = clock + 0.25
    API.runRangeSweep(clock)
    assert(API.rangeResult(900).count == 0 and API.rangeResult(900).total == 0,
        "no selected operational turret must settle as 0 / 0")
    API.runRangeSweep(clock + 0.25)
    local many = {}
    for member = 1, 19 do many[#many + 1] = { componentID = 2000 + member, operational = true } end
    session.groups = {{ key = "many", members = many }}
    session.checkedGroupKeys = { many = true }
    API.setRangeTargets({ 950 }, 950)
    local expectedChunks = { 8, 8, 3 }
    for _, chunkSize in ipairs(expectedChunks) do
        clock = clock + 0.25
        local before = #events
        API.runRangeSweep(clock)
        assert(#events - before == chunkSize + 2 and events[before + 1].params.members == chunkSize,
            "large turret selection must dispatch at most eight members per update")
        local begin = events[before + 1].params
        fix.fireEvent("X4GunneryControl.InRangeResult",
            "x4gcr1:" .. begin.nonce .. ":950:" .. chunkSize .. ":" .. chunkSize)
        if chunkSize ~= 3 then
            assert(API.rangeResult(950) == nil, "partial target result must not publish")
        end
    end
    assert(API.rangeResult(950).count == 19 and API.rangeResult(950).total == 19,
        "completed chunks must publish one exact aggregate result")
    local heavyTargets = {}
    for target = 970, 989 do heavyTargets[#heavyTargets + 1] = target end
    API.setRangeTargets(heavyTargets, 989)
    local heavyStart, heavyComplete, heavyWork, heavyPeak = clock, nil, 0, 0
    for _ = 1, 300 do
        clock = clock + 0.25
        local before = #events
        API.runRangeSweep(clock)
        if #events > before then
            local begin = events[before + 1].params
            local work = begin.members
            heavyWork, heavyPeak = heavyWork + work, math.max(heavyPeak, work)
            assert(work <= 8 and #events - before == work + 2,
                "heavy page must keep each update within eight turret checks")
            fix.fireEvent("X4GunneryControl.InRangeResult",
                "x4gcr1:" .. begin.nonce .. ":" .. begin.targetid .. ":" .. work .. ":" .. work)
        end
        local complete = 0
        for _, target in ipairs(heavyTargets) do
            if API.rangeResult(target) then complete = complete + 1 end
        end
        if complete == 20 then heavyComplete = clock - heavyStart; break end
    end
    assert(heavyComplete and heavyPeak == 8 and heavyWork >= 380,
        "heavy page must complete with bounded per-update work")
    print(string.format("offline IN RANGE 20-row heavy sweep: peak %d checks/update; total %d checks; first complete %.2fs",
        heavyPeak, heavyWork, heavyComplete))
    AddUITriggeredEvent = savedAdd
end

-- ── 60. station surfaces resolve size from the exact installed module slot ─
do
    local sess60 = API.getSession()
    sess60.phase, sess60.controlMode = "engaged", "direct"
    sess60.targetObjectID, sess60.aimTargetID = 12000, 12000
    sess60.surfaceTypeFilter, sess60.surfaceMacroFilter = "any", "any"
    sess60.surfaceBrowser = X4GunneryState.newSurfaceBrowser(nil)
    C.IsComponentClass = function(component, class)
        return class == "station" and tonumber(tostring(component)) == 12000
    end
    C.GetNumStationModules = function() return 1 end
    C.GetStationModules = function(result)
        result[0] = 12001
        return 1
    end
    C.GetNumUpgradeSlots = function(destructible, _, upgrade)
        if tonumber(tostring(destructible)) ~= 12001 then return 0 end
        if upgrade == "turret" then return 2 end
        if upgrade == "shield" then return 1 end
        return 0
    end
    C.GetUpgradeSlotCurrentComponent = function(_, upgrade, slot)
        if upgrade == "turret" then return 12001 + slot end
        return 12004
    end
    local installedMacroCalls60 = {}
    C.GetUpgradeSlotCurrentMacro = function(object, module, upgrade, slot)
        installedMacroCalls60[#installedMacroCalls60 + 1] = {
            object = tonumber(tostring(object)), module = tonumber(tostring(module)),
            upgrade = upgrade, slot = slot,
        }
        if upgrade == "shield" then return "shield_xen_l_standard_01_mk2_macro" end
        return slot == 1 and "turret_xen_l_laser_01_mk1_macro"
            or "turret_xen_m_laser_02_mk1_macro"
    end
    C.IsComponentOperational = function() return true end
    C.GetComponentName = function(component)
        return ({ [12002] = "XEN L Graviton Turret Mk1",
            [12003] = "XEN M Impulse Turret Mk1",
            [12004] = "XEN L Shield Generator Mk2" })[tonumber(tostring(component))] or "Station"
    end
    C.GetDistanceBetween = function() return 30000 end
    GetMacroData = function(macro, key)
        if key == "name" then return ({
            turret_xen_l_laser_01_mk1_macro = "XEN L Graviton Turret Mk1",
            turret_xen_m_laser_02_mk1_macro = "XEN M Impulse Turret Mk1",
            shield_xen_l_standard_01_mk2_macro = "XEN L Shield Generator Mk2",
        })[macro] or "" end
        return ""
    end
    GetComponentData = function(_, ...)
        local values = {}
        for _, key in ipairs({...}) do
            if key == "shieldmax" or key == "shieldpercent" then values[#values + 1] = 0
            elseif key == "hullpercent" then values[#values + 1] = 100
            else values[#values + 1] = false end
        end
        return unpack(values)
    end
    gcMenu.display()
    local rangeProgress60
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if entry.row == "surface_range_progress" then rangeProgress60 = entry.text end
    end
    assert(type(rangeProgress60) == "function" and rangeProgress60():find("IN RANGE", 1, true),
        "surface page must expose text-only IN RANGE progress")
    sess60.groups = {{ key = "selected", members = {{ componentID = 101, operational = true }} }}
    sess60.checkedGroupKeys = { selected = true }
    API.setRangeTargets({ 12002, 12003, 12004 }, 12000)
    local savedRangeAdd60, rangeEvents60 = AddUITriggeredEvent, {}
    AddUITriggeredEvent = function(_, control, params)
        rangeEvents60[#rangeEvents60 + 1] = { control = control, params = params }
    end
    API.runRangeSweep(clock)
    local selectedNonce60 = rangeEvents60[1].params.nonce
    fix.fireEvent("X4GunneryControl.InRangeResult", "x4gcr1:" .. selectedNonce60 .. ":12000:1:1")
    clock = clock + 0.25
    API.runRangeSweep(clock)
    local pageNonce60 = rangeEvents60[4].params.nonce
    fix.fireEvent("X4GunneryControl.InRangeResult", "x4gcr1:" .. pageNonce60 .. ":12002:1:1")
    assert(rangeProgress60():find("1/3 scanned", 1, true),
        "surface progress must include completed visible rows")
    AddUITriggeredEvent = savedRangeAdd60
    assert(#installedMacroCalls60 == 3,
        "60: every station surface needs one exact installed-equipment lookup")
    for _, call in ipairs(installedMacroCalls60) do
        assert(call.object == 12000 and call.module == 12001,
            "60: station equipment macro lookup must identify root station and exact module")
    end
    local stationSurfaceLabels60, stationSurfaceOrder60 = {}, {}
    for _, entry in ipairs(fix.getCreatedTexts()) do
        local row = tostring(entry.row)
        if (row == "12002" or row == "12003" or row == "12004") and entry.column == 1 then
            stationSurfaceLabels60[row] = entry.text
            stationSurfaceOrder60[#stationSurfaceOrder60 + 1] = row
        end
    end
    assert(table.concat(stationSurfaceOrder60, ",") == "12002,12004,12003",
        "60: installed sizes must sort L turret, L shield, then M turret")
    assert(stationSurfaceLabels60["12002"] == "XEN L Graviton Turret Mk1"
            and stationSurfaceLabels60["12003"] == "XEN M Impulse Turret Mk1"
            and stationSurfaceLabels60["12004"] == "XEN L Shield Generator Mk2",
        "60: station rows must contain only engine-provided equipment names")
end


print("runtime targeting surface tests passed")
