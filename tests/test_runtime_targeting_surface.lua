-- test_runtime_targeting_surface.lua
-- Turret-first IN RANGE sweep and station surface size resolution.

local fix = dofile("tests/support/runtime_fixture.lua").load()
local gcMenu = fix.gcMenu
local API    = fix.API
local C      = fix.C

-- Shared clock for getElapsedTime; tests advance it explicitly.
local clock = 100
getElapsedTime = function() return clock end

gcMenu.onShowMenu()

-- Each selected turret visits a full page with the selected target first.
do
    local session = API.getSession()
    assert(API.rangeText(nil) == "0 / 0 IN RANGE"
        and API.rangeText({ count = 2, total = 3 }) == "2 / 3 IN RANGE",
        "IN RANGE always formats ordinary numeric numerator and denominator")
    local oldClass, oldContext, oldData = C.IsComponentClass, C.GetContextByClass, GetComponentData
    C.IsComponentClass = function(object, class)
        local value = tonumber(tostring(object))
        return (value == 801 and class == "ship")
            or ((value == 802 or value == 804) and class == "engine")
    end
    C.GetContextByClass = function(object)
        local value = tonumber(tostring(object))
        if value == 802 then return 801 end
        if value == 804 then return 803 end
        return 0
    end
    GetComponentData = function(_, key)
        assert(key ~= "maxspeed", "X4 Lua component data does not support maxspeed")
        return false
    end
    assert(X4GunneryState.normID(API.rangeSpeedShip(801)) == "801"
        and X4GunneryState.normID(API.rangeSpeedShip(802)) == "801"
        and API.rangeSpeedShip(803) == nil and API.rangeSpeedShip(804) == nil,
        "only ships and their engines pass a ship ID to MD for speed lookup")
    C.IsComponentClass, C.GetContextByClass, GetComponentData = oldClass, oldContext, oldData
    session.phase, session.controlMode = "target_select", nil
    local savedSofttarget, selectedTarget = C.GetSofttarget2, 720
    C.GetSofttarget2 = function() return { softtargetID = selectedTarget, softtargetConnectionName = "" } end
    local many = {}
    for member = 1, 19 do many[#many + 1] = { componentID = 2000 + member, operational = true } end
    many[#many + 1], many[#many + 2] =
        { componentID = 2999, operational = false }, { componentID = 2001, operational = true }
    session.groups = {{ key = "many", members = many }}
    session.checkedGroupKeys = { many = true }
    local targets = {}
    for target = 701, 720 do targets[#targets + 1] = target end
    API.setRangeTargets(targets, 720)
    local events = {}
    local savedAdd = AddUITriggeredEvent
    AddUITriggeredEvent = function(_, control, params)
        events[#events + 1] = { control = control, params = params }
    end
    local function pass(bits)
        local start = #events
        API.runRangeSweep(clock)
        assert(#events - start == 22 and events[start + 1].control == "in_range_begin"
            and events[start + 2].params.target == 720
            and events[start + 22].control == "in_range_commit",
            "each turret must check selected target first and all 19 other rows")
        API.runRangeSweep(clock)
        assert(#events == start + 22, "pending turret pass must not overlap")
        local begin = events[start + 1].params
        fix.fireEvent("X4GunneryControl.InRangeResult",
            "x4gcr2:" .. begin.nonce .. ":" .. tostring(begin.weapon) .. ":" .. bits)
        return begin
    end
    local sortMark = fix.callbackCheckpoint()
    pass(string.rep("1", 20))
    assert(API.rangeResult(720).count == 1 and API.rangeResult(701).count == 1,
        "first contribution must appear on every row")
    for _ = 2, 19 do pass(string.rep("0", 20)) end
    assert(API.rangeResult(720).count == 1 and API.rangeResult(720).total == 19,
        "full sweep must preserve exact denominator")
    clock = clock + 1.1
    pass(string.rep("0", 20))
    assert(API.rangeResult(720).count == 0,
        "next sweep must replace the same turret's previous contribution")
    local beforePage = #events
    API.runRangeSweep(clock)
    local stalePage = events[beforePage + 1].params
    selectedTarget = 801
    fix.fireEvent("X4GunneryControl.InRangeResult",
        "x4gcr2:" .. stalePage.nonce .. ":" .. tostring(stalePage.weapon) .. ":" .. string.rep("1", 20))
    assert(API.rangeResult(720).count == 0, "changed selection must reject an active reply")
    API.setRangeTargets({ 801 }, 801)
    assert(API.rangeResult(720) == nil, "old page must not publish")
    local beforeMembers = #events
    API.runRangeSweep(clock)
    local staleMembers = events[beforeMembers + 1].params
    session.checkedGroupKeys = {}
    fix.fireEvent("X4GunneryControl.InRangeResult",
        "x4gcr2:" .. staleMembers.nonce .. ":" .. tostring(staleMembers.weapon) .. ":1")
    assert(API.rangeResult(801) == nil, "unchecked turret must reject an active reply")
    API.setRangeTargets({ 801 }, 801)
    API.runRangeSweep(clock)
    assert(API.rangeResult(801).count == 0 and API.rangeResult(801).total == 0,
        "membership change must use the current denominator")
    session.checkedGroupKeys = { many = true }
    selectedTarget = 720
    API.setRangeTargets(targets, 720)
    local beforeTimeout = #events
    API.runRangeSweep(clock)
    local obsolete = events[beforeTimeout + 1].params
    clock = clock + 2.1
    API.runRangeSweep(clock)
    local replacement = events[#events - 21].params
    fix.fireEvent("X4GunneryControl.InRangeResult",
        "x4gcr2:" .. obsolete.nonce .. ":" .. tostring(obsolete.weapon) .. ":" .. string.rep("1", 20))
    assert(API.rangeResult(720) == nil, "timed-out reply must be rejected")
    fix.fireEvent("X4GunneryControl.InRangeResult",
        "x4gcr2:" .. replacement.nonce .. ":" .. tostring(replacement.weapon) .. ":" .. string.rep("1", 20))

    local twentyOne = {}
    for target = 701, 721 do twentyOne[#twentyOne + 1] = target end
    selectedTarget = 721
    API.setRangeTargets(twentyOne, 721)
    local boundary = #events
    API.runRangeSweep(clock)
    local firstGroup = events[boundary + 1].params
    assert(#events - boundary == 22 and events[boundary + 2].params.target == 721,
        "21 targets must start with the selected target in a bounded first group")
    fix.fireEvent("X4GunneryControl.InRangeResult",
        "x4gcr2:" .. firstGroup.nonce .. ":" .. tostring(firstGroup.weapon) .. ":" .. string.rep("0", 20))
    boundary = #events
    API.runRangeSweep(clock)
    local lastGroup = events[boundary + 1].params
    assert(#events - boundary == 3 and lastGroup.weapon == firstGroup.weapon
            and events[boundary + 2].params.target == 720,
        "the same turret must visit the 21st distinct target before advancing")
    fix.fireEvent("X4GunneryControl.InRangeResult",
        "x4gcr2:" .. lastGroup.nonce .. ":" .. tostring(lastGroup.weapon) .. ":0")
    assert(API.rangeResult(720).count == 0,
        "the final target group must replace its previous contribution")
    C.GetUpgradeSlotGroup = function() return { path = "p", group = "g" } end
    gcMenu.shown = true
    local originalDisplay, redraws = gcMenu.display, 0
    gcMenu.display = function(...)
        redraws = redraws + 1
        return originalDisplay(...)
    end
    fix.drainCallbacksSince(sortMark)
    gcMenu.display = originalDisplay
    assert(redraws > 0, "completed sweep must refresh browser ordering")
    AddUITriggeredEvent, C.GetSofttarget2 = savedAdd, savedSofttarget
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
    sess60.groups = {{ key = "selected", members = {{ componentID = 101, operational = true }} }}
    sess60.checkedGroupKeys = { selected = true }
    API.setRangeTargets({ 12002, 12003, 12004 }, 12000)
    local savedRangeAdd60, rangeEvents60 = AddUITriggeredEvent, {}
    AddUITriggeredEvent = function(_, control, params)
        rangeEvents60[#rangeEvents60 + 1] = { control = control, params = params }
    end
    API.runRangeSweep(clock)
    local request60 = rangeEvents60[1].params
    fix.fireEvent("X4GunneryControl.InRangeResult",
        "x4gcr2:" .. request60.nonce .. ":" .. tostring(request60.weapon) .. ":1000")
    assert(API.rangeResult(12000).count == 1,
        "engaged selection must accept its current turret contribution")
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
