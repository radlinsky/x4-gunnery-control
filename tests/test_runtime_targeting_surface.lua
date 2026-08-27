-- test_runtime_targeting_surface.lua
-- Surface browser: row render/sort with engageability results, health pinning,
-- 20-row lazy page requests, and station surface size resolution.

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

-- ── 58. target/surface rows render and sort complete engageability results ────────
do
    local sess58 = API.getSession()
    sess58.phase, sess58.controlMode = "console", nil
    sess58.checkedGroupKeys = { selected = true }
    local savedAdd58, events58 = AddUITriggeredEvent, {}
    AddUITriggeredEvent = function(screen, control, params)
        events58[#events58 + 1] = { screen = screen, control = control, params = params }
    end
    local function seed58(target, on)
        events58 = {}
        local result = API.requestEngageability(target)
        local nonce
        for _, event in ipairs(events58) do
            if event.control == "engageability_begin" then nonce = event.params.nonce end
        end
        fix.fireEvent("X4GunneryControl.EngageabilityResult", "x4gce3:" .. nonce .. ":" .. target .. ":" .. on .. ":2:2")
        fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete", "x4gce2c:" .. nonce .. ":1:1")
        return result
    end
    seed58(701, 2); seed58(702, 0); seed58(703, 1); seed58(704, 0)
    seed58(801, 2); seed58(802, 0)
    AddUITriggeredEvent = savedAdd58

    sess58.phase, sess58.controlMode = "engaged", "direct"
    sess58.targetObjectID, sess58.aimTargetID = 900, 900
    sess58.surfaceTypeFilter, sess58.surfaceMacroFilter = "any", "any"
    GetPlayerContextByClass = function() return nil end
    C.IsComponentClass = function() return false end
    C.GetNumUpgradeSlots = function(_, _, upgrade)
        if upgrade == "turret" then return 4 end
        if upgrade == "shield" then return 1 end
        return 0
    end
    C.GetUpgradeSlotCurrentComponent = function(_, upgrade, slot)
        if upgrade == "turret" then return 700 + slot end
        return 703
    end
    C.IsComponentOperational = function() return true end
    C.GetComponentName = function(component)
        local names = { [701] = "Alpha", [702] = "Beta", [703] = "Shield", [704] = "Gamma", [801] = "Zulu", [802] = "Alpha" }
        return names[tonumber(tostring(component))] or "Target"
    end
    GetComponentData = function(_, ...)
        local vals = {}
        for _, key in ipairs({...}) do
            if key == "maxradarrange" then vals[#vals + 1] = 40000
            elseif key == "isplayerowned" then vals[#vals + 1] = false
            elseif key == "isenemy" then vals[#vals + 1] = true
            elseif key == "isknown" or key == "isradarvisible" then vals[#vals + 1] = true
            else vals[#vals + 1] = false end
        end
        return unpack(vals)
    end
    C.GetContextByClass = function(component)
        return tonumber(tostring(component)) == 704 and 900 or component
    end
    local suggestedClick58 = false
    assert(API.suggestTestEngagement(704, function() suggestedClick58 = true end),
        "58: Test Lab must be able to mark an exact surface without selecting it")
    gcMenu.display()
    local renderedSurfaces58 = {}
    local markedSurface58
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if entry.column == 4 and tonumber(tostring(entry.row)) then
            renderedSurfaces58[tostring(entry.row)] = entry.text
        end
        if tostring(entry.row) == "704" and entry.column == 1 then markedSurface58 = entry.text end
    end
    assert(renderedSurfaces58["701"] == "2 / 2  " .. ReadText(20991, 89),
        "58: complete surface solution must render the aggregate ENGAGEABLE label")
    assert(renderedSurfaces58["702"] == "0 / 2" and renderedSurfaces58["703"] == "1 / 2",
        "58: incomplete surface solutions must render their exact binary counts")
    assert(markedSurface58 == "[TEST TARGET] Gamma" and not suggestedClick58,
        "58: the exact qualified surface must be visibly marked without being designated")
    local surfaceButton58
    for _, button in ipairs(fix.getCreatedButtons()) do
        if button.text == ReadText(20991, 60) then surfaceButton58 = button; break end
    end
    assert(surfaceButton58, "58: surface solution rows were not rendered")
    surfaceButton58.handlers.onClick()

    sess58.phase, sess58.controlMode = "target_select", nil
    C.GetSofttarget2 = function() return { softtargetID = 801, softtargetConnectionName = "" } end
    GetPlayerContextByClass = function() return 1 end
    GetContainedShips = function() return { 801, 802, 900 } end
    GetContainedStations = function() return {} end
    C.GetContextByClass = function(component) return component end
    C.GetDistanceBetween = function() return 1000 end
    gcMenu.display()
    local targetOrder58, targetSolutions58, markedRoot58 = {}, {}, nil
    for _, entry in ipairs(fix.getCreatedTexts()) do
        local row = tostring(entry.row)
        if (row == "801" or row == "802") and entry.column == 8 then
            targetOrder58[#targetOrder58 + 1] = row
            targetSolutions58[row] = entry.text
        end
        if row == "900" and entry.column == 1 then markedRoot58 = entry.text end
    end
    assert(table.concat(targetOrder58, ",") == "801,802",
        "58: an all-on-engageability target must sort before an incomplete target")
    assert(targetSolutions58["801"] == "2 / 2  " .. ReadText(20991, 89)
            and targetSolutions58["802"] == "0 / 2",
        "58: target rows must bind the exact aggregate solution text to column 8")
    assert(markedRoot58 == "[TEST TARGET] Target" and not suggestedClick58,
        "58: the qualified surface's root must be visibly marked for the owner's first click")
    local log58 = table.concat(fix.getCapturedLog(), "\n")
    assert(log58:find('event=surface_browser action=row target=900 component=701 name="Alpha"', 1, true)
            and log58:find('macro="" position=1 engageability_state=complete engageability_engageable=2 engageability_known=2 engageability_total=2 engageability_text="2 / 2  text:20991:89"', 1, true),
        "58: surface-row audit must prove first position and the displayed complete solution")
    assert(log58:find('event=target_browser action=row component=801 name="Zulu"', 1, true)
            and log58:find('position=1 engageability_state=complete engageability_engageable=2 engageability_known=2 engageability_total=2 engageability_text="2 / 2  text:20991:89"', 1, true),
        "58: target-row audit must prove all-on-solution ordering and displayed value")
end

-- ── 59. surface browser pins health and lazily requests exact 20-row pages ──
do
    local sess59 = API.getSession()
    sess59.phase, sess59.controlMode = "engaged", "direct"
    sess59.targetObjectID, sess59.aimTargetID = 10000, 10000
    sess59.surfaceTypeFilter, sess59.surfaceMacroFilter = "any", "any"
    sess59.surfaceBrowser = X4GunneryState.newSurfaceBrowser(nil)
    sess59.groups = {
        { key = "page_group", operationalCount = 2, totalCount = 2, members = {
            { componentID = 11001, operational = true },
            { componentID = 11002, operational = true },
        } },
    }
    sess59.checkedGroupKeys = { page_group = true }
    C.IsComponentClass = function() return false end
    C.GetNumUpgradeSlots = function(_, _, upgrade) return upgrade == "turret" and 41 or 0 end
    C.GetUpgradeSlotCurrentComponent = function(_, _, slot) return 10000 + slot end
    C.GetUpgradeSlotCurrentMacro = function(_, _, _, slot)
        return slot >= 22 and "turret_test_l_laser_macro" or "turret_test_m_laser_macro"
    end
    C.IsComponentOperational = function() return true end
    C.GetComponentName = function(component) return "Surface " .. tostring(component) end
    local distanceOffset59 = 0
    C.GetDistanceBetween = function(_, component)
        return (tonumber(tostring(component)) - 10000) * 1000 + distanceOffset59
    end
    local shieldCapacity59, shieldPercent59, hullPercent59 = 0, 0, 73
    GetComponentData = function(component, ...)
        local vals = {}
        for _, key in ipairs({...}) do
            if key == "macro" then vals[#vals + 1] = "turret_m"
            elseif key == "shieldmax" then vals[#vals + 1] = shieldCapacity59
            elseif key == "shieldpercent" then vals[#vals + 1] = shieldPercent59
            elseif key == "hullpercent" then vals[#vals + 1] = hullPercent59
            elseif key == "isplayerowned" then vals[#vals + 1] = false
            elseif key == "maxradarrange" then vals[#vals + 1] = 40000
            else vals[#vals + 1] = false end
        end
        return unpack(vals)
    end
    GetMacroData = function(macro, key)
        if key == "name" then return "Medium Turret" end
        if key == "size" then return "" end
        return ""
    end
    local savedAdd59, targetEvents59, activeNonce59, nonceByTarget59 = AddUITriggeredEvent, {}, nil, {}
    AddUITriggeredEvent = function(screen, control, params)
        if control == "engageability_begin" then activeNonce59 = params.nonce end
        if control == "engageability_target" then
            local target = tostring(params.target)
            targetEvents59[#targetEvents59 + 1] = target
            nonceByTarget59[target] = activeNonce59
        end
        savedAdd59(screen, control, params)
    end
    gcMenu.display()
    assert(#targetEvents59 == 21,
        "59: initial surface render must request pinned target plus exactly 20 alternatives; got "
            .. tostring(#targetEvents59))
    local pageOneRows59 = {}
    for _, entry in ipairs(fix.getCreatedTexts()) do
        local row = tonumber(tostring(entry.row))
        if row and row >= 10001 and row <= 10041 then pageOneRows59[row] = true end
    end
    local pageOneCount59 = 0
    for _ in pairs(pageOneRows59) do pageOneCount59 = pageOneCount59 + 1 end
    assert(pageOneCount59 == 20 and pageOneRows59[10022] and pageOneRows59[10041]
            and not pageOneRows59[10001],
        "59: page one must contain 20 installed L elements ahead of nearer M elements")
    local pinnedDistance59, pinnedShield59, pinnedHull59, largeRow59
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if entry.row == "surface_pinned" and entry.column == 3 then pinnedDistance59 = entry.text end
        if entry.row == "surface_pinned" and entry.column == 5 then pinnedShield59 = entry.text end
        if entry.row == "surface_pinned_hull" and entry.column == 5 then pinnedHull59 = entry.text end
        if tostring(entry.row) == "10022" and entry.column == 1 then largeRow59 = entry.text end
    end
    assert(type(pinnedDistance59) == "function" and pinnedDistance59() == "0.0 km",
        "59: pinned distance must be function-backed and initialized with the pinned solution")
    assert(type(pinnedShield59) == "function" and type(pinnedHull59) == "function",
        "59: both pinned health rows must be function-backed for in-place element-frame updates")
    assert(pinnedShield59() == ReadText(20991, 98) .. " -"
            and pinnedHull59() == ReadText(20991, 99) .. " 73%",
        "59: zero shield capacity and hull percent must display on separate pinned rows")
    shieldCapacity59, shieldPercent59, hullPercent59 = 100, 0, 41
    assert(pinnedShield59() == ReadText(20991, 98) .. " 0%"
            and pinnedHull59() == ReadText(20991, 99) .. " 41%",
        "59: shielded component at zero must display Shield 0% above its exact hull percent")
    assert(largeRow59 == "Surface 10022",
        "59: surface rows must display only the engine-provided equipment name")
    local pinnedRepaintMark59 = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.EngageabilityResult",
        "x4gce3:" .. nonceByTarget59["10000"] .. ":10000:1:2:2")
    fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete",
        "x4gce2c:" .. nonceByTarget59["10000"] .. ":1:1")
    assert(fix.callbackCheckpoint() == pinnedRepaintMark59 + 1,
        "59: pinned result must schedule one isolated element-frame update")
    fix.drainCallbacksSince(pinnedRepaintMark59)
    local log59 = table.concat(fix.getCapturedLog(), "\n")
    assert(log59:find("event=surface_pinned action=refresh component=10000", 1, true)
            and log59:find("engageability_engageable=1 engageability_known=2 engageability_total=2 distance=0 shield_capacity=true shield_percent=0 hull_percent=41", 1, true),
        "59: pinned refresh audit must carry exact engageability, distance, and live health values")

    targetEvents59 = {}
    local nextPage59 = fix.buttonByText(ReadText(20991, 95))
    assert(nextPage59 and nextPage59.active, "59: Next Page must be active for 41 alternatives")
    nextPage59.handlers.onClick()
    assert(#targetEvents59 == 20, "59: opening page two must request only its 20 alternatives")
    local pageTwoRows59 = {}
    for _, entry in ipairs(fix.getCreatedTexts()) do
        local row = tonumber(tostring(entry.row))
        if row and row >= 10001 and row <= 10041 then pageTwoRows59[row] = true end
    end
    assert(pageTwoRows59[10001] and pageTwoRows59[10020]
            and not pageTwoRows59[10021] and not pageTwoRows59[10022],
        "59: page two must contain the first 20 medium slots after all large slots")

    local pageTwoDistance59, mediumFallbackRow59
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if tostring(entry.row) == "10001" and entry.column == 3 then pageTwoDistance59 = entry.text end
        if tostring(entry.row) == "10001" and entry.column == 1 then mediumFallbackRow59 = entry.text end
    end
    assert(pageTwoDistance59 == "1.0 km",
        "59: alternative distance must be captured alongside that page's engageability batch")
    assert(mediumFallbackRow59 == "Surface 10001",
        "59: medium surface rows must not append redundant type or size text")

    distanceOffset59 = 5000
    targetEvents59 = {}
    local previousPage59 = fix.buttonByText(ReadText(20991, 94))
    previousPage59.handlers.onClick()
    assert(#targetEvents59 == 0, "59: returning to cached page one must issue no solution requests")
    local cachedPageDistance59
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if tostring(entry.row) == "10022" and entry.column == 3 then cachedPageDistance59 = entry.text end
    end
    assert(cachedPageDistance59 == "22.0 km",
        "59: revisiting a cached page must retain the distance captured with its engageability batch")
    local autoRefresh59
    for _, checkbox in ipairs(fix.getCreatedCheckBoxes()) do
        if checkbox.row == "surface_auto_refresh" then autoRefresh59 = checkbox end
    end
    assert(autoRefresh59 and autoRefresh59.checked == false,
        "59: ten-second refresh must be visible and unchecked by default")
    autoRefresh59.handlers.onClick()
    assert(sess59.surfaceBrowser.autoRefresh == true,
        "59: clicking ten-second refresh must enable only session browser state")
    targetEvents59, nonceByTarget59 = {}, {}
    C.GetPlayerCurrentControlGroup = function() return "gunnercontrol" end
    C.GetPlayerOccupiedShipID = function() return sess59.shipID end
    clock = clock + 10
    gcMenu.onUpdate()
    assert(#targetEvents59 == 21,
        "59: automatic refresh must recalculate pinned plus current 20-row page only; got "
            .. tostring(#targetEvents59) .. " phase=" .. tostring(sess59.phase)
            .. " next=" .. tostring(sess59.surfaceBrowser.nextAutoRefreshAt)
            .. " now=" .. tostring(clock))
    local refreshedPinnedDistance59, refreshedPageDistance59
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if entry.row == "surface_pinned" and entry.column == 3 then refreshedPinnedDistance59 = entry.text end
        if tostring(entry.row) == "10022" and entry.column == 3 then refreshedPageDistance59 = entry.text end
    end
    assert(type(refreshedPinnedDistance59) == "function" and refreshedPinnedDistance59() == "5.0 km",
        "59: pinned distance must refresh on the same one-second tick as its engageability")
    assert(refreshedPageDistance59 == "27.0 km",
        "59: automatic page refresh must recapture distance with the new 20-row solution batch")
    log59 = table.concat(fix.getCapturedLog(), "\n")
    assert(log59:find("event=surface_refresh action=fire reason=automatic root=10000 page=1", 1, true)
            and log59:find("event=surface_snapshot action=create reason=automatic root=10000", 1, true),
        "59: automatic refresh needs one firing record and one matching snapshot record")
    assert(log59:find('event=surface_page action=request generation=', 1, true)
            and log59:find('requested=20 selected_total=2 selected_signature="11001,11002"', 1, true),
        "59: page request audit must identify exact bounded membership and selected turrets")

    -- X4 keeps updating UI frames while the simulation is paused. A paused
    -- elapsed clock must not repeatedly satisfy the same pinned/automatic
    -- refresh deadline and recursively request another engageability batch.
    targetEvents59 = {}
    C.IsGamePaused = function() return true end
    clock = clock + 20
    gcMenu.onUpdate()
    assert(#targetEvents59 == 0,
        "59: paused UI updates must issue no pinned or automatic surface requests; got "
            .. tostring(#targetEvents59))
    C.IsGamePaused = function() return false end

    sess59.aimTargetID = 10001
    sess59.surfaceBrowser.pendingReason = "open"
    gcMenu.display()
    local parentHull59
    for _, button in ipairs(fix.getCreatedButtons()) do
        if button.row == "surface_parent_hull" then parentHull59 = button end
    end
    assert(parentHull59 and parentHull59.text == ReadText(20991, 58),
        "59: a pinned surface must retain a direct parent-hull action")
    AddUITriggeredEvent = savedAdd59
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
