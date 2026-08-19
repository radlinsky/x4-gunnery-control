-- test_runtime_targeting_browser.lua
-- Target-count memo, group readback (duplicate names, padded IDs),
-- player-faction exclusion, target browser (class/macro metadata),
-- and surface-type/macro filters.

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

-- ── 51. hasMultipleTargets memo: two quick repaints share one sweep ─────────
-- readTargetCandidates() is always fresh (no full-list cache).  Only the
-- target-count boolean used by the cycle-target buttons is memoised via
-- hasMultipleTargets(), which keeps a 1 s TTL.  Two back-to-back engaged-mode
-- display() calls within that TTL must only sweep once.  The target-browser
-- path (target_select phase) calls readTargetCandidates() directly and must
-- always sweep.  Delete the memo in hasMultipleTargets() to make this fail.

local shipScanCount51 = 0
GetContainedShips = function() shipScanCount51 = shipScanCount51 + 1; return { 98 } end
GetContainedStations = function() return {} end
GetPlayerContextByClass = function() return 1 end
C.GetContextByClass = function(comp, cls, self_) return comp end
C.IsComponentOperational = function() return true end
C.GetDistanceBetween = function() return 1000 end
GetComponentData = function(component, ...)
    local keys, vals = {...}, {}
    for _, k in ipairs(keys) do
        if k == "isenemy" then vals[#vals + 1] = true
        elseif k == "ishostile" then vals[#vals + 1] = false
        elseif k == "isfriend" then vals[#vals + 1] = false
        elseif k == "isknown" then vals[#vals + 1] = true
        elseif k == "isradarvisible" then vals[#vals + 1] = true
        elseif k == "maxradarrange" then vals[#vals + 1] = 40000
        elseif k == "isplayerowned" then vals[#vals + 1] = false  -- enemy ship, not player-owned
        else vals[#vals + 1] = nil
        end
    end
    return unpack(vals)
end

gcMenu.onShowMenu()
local sess51 = API.getSession()
assert(sess51 ~= nil, "expected session for cache test (51)")

-- Set up a direct/engaged session with two snapshots so the compact panel renders.
local grp51 = fix.makeGroup{
    key = "grp51", displayName = "G51",
    members = { { componentID = 27, displayName = "T1", operational = true,
                  cameraSupported = true, componentKey = "27" } },
}
sess51.groups = { grp51 }
sess51.checkedGroupKeys = { ["grp51"] = true }
sess51.phase = "engaged"
sess51.controlMode = "direct"
sess51.committedBaseline = { { kind = "group", contextID = 5, path = "p", group = "g",
    shipID = sess51.shipID, mode = "attack", armed = false } }
sess51.cameraMemberID = 27
sess51.targetObjectID = 98
sess51.aimTargetID = 98

-- Move the clock forward so the hasMultipleTargets memo from any prior test is stale.
clock = clock + 100
getElapsedTime = function() return clock end

-- First display() (engaged/direct): hasMultipleTargets memo is stale, must sweep.
shipScanCount51 = 0
local ok51a, err51a = pcall(function() gcMenu.display() end)
assert(ok51a, "display() raised on first call (test 51): " .. tostring(err51a))
local sweepsAfterFirst = shipScanCount51
assert(sweepsAfterFirst >= 1,
    "first display() must call GetContainedShips at least once; got " .. tostring(sweepsAfterFirst))

-- Second display() immediately (same clock): hasMultipleTargets memo is live, must not re-sweep.
-- readTargetCandidates() is always fresh but is NOT called in engaged/direct mode
-- (only hasMultipleTargets() is, for the cycle-button active state).
shipScanCount51 = 0
local ok51b, err51b = pcall(function() gcMenu.display() end)
assert(ok51b, "display() raised on second call (test 51): " .. tostring(err51b))
assert(shipScanCount51 == 0,
    "second display() within the TTL must not rescan; GetContainedShips was called "
    .. tostring(shipScanCount51) .. " time(s). hasMultipleTargets memo is not working.")

-- Target-browser path (target_select): readTargetCandidates() is always fresh,
-- must always sweep even within the TTL.
sess51.phase = "target_select"
shipScanCount51 = 0
local ok51c, err51c = pcall(function() gcMenu.display() end)
assert(ok51c, "display() raised in browser phase (test 51): " .. tostring(err51c))
assert(shipScanCount51 >= 1,
    "target-browser display() must always sweep; GetContainedShips was called "
    .. tostring(shipScanCount51) .. " time(s)")

-- ── 52. readGroups: duplicate path+group names must stay controllable ─────
-- Two groups sharing path+group but with different contextIDs. The slot API
-- returns no contextID, so slot->group attribution is a guess -- but mode and
-- armed commands address contextID+path+group directly and are always exact.
-- So a duplicate name must never make a group read-only.
--
-- The 2-turrets-per-group shape is the one that matters: only one slot per
-- group carries the group's representative componentID, so any scheme that
-- keys off "did this slot match" fails on the other slots.

do
    local savedGetNumUpgradeGroups  = C.GetNumUpgradeGroups
    local savedGetUpgradeGroups2    = C.GetUpgradeGroups2
    local savedGetUpgradeGroupInfo2 = C.GetUpgradeGroupInfo2
    local savedGetNumUpgradeSlots   = C.GetNumUpgradeSlots
    local savedGetUpgradeSlotCurrentComponent = C.GetUpgradeSlotCurrentComponent
    local savedGetUpgradeSlotGroup  = C.GetUpgradeSlotGroup
    local savedFfiNew               = fix.ffiStub.new

    -- ffi.new must hand back a 0-based buffer of UpgradeGroup2-shaped entries.
    local groupBuffer = {}
    groupBuffer[0] = { path = "p", group = "grp_front", contextid = 10 }
    groupBuffer[1] = { path = "p", group = "grp_front", contextid = 20 }
    local turretsPerGroup, slotComponents = 2, {}

    C.GetNumUpgradeGroups  = function() return 2 end
    C.GetUpgradeGroups2    = function() return 2 end
    C.GetUpgradeGroupInfo2 = function(ship, macro, ctxid)
        -- Each group reports ONE representative component: 101 for ctx 10,
        -- 102 for ctx 20. The group's other turrets are not reported here.
        return { count = turretsPerGroup, currentcomponent = (tostring(ctxid) == "10") and 101 or 102,
                 currentmacro = "turret_bor_m_railgun_02_mk1_macro", slotsize = "",
                 total = turretsPerGroup, operational = turretsPerGroup }
    end
    C.GetNumUpgradeSlots             = function() return #slotComponents end
    C.GetUpgradeSlotCurrentComponent = function(ship, tag, slot) return slotComponents[slot] or 0 end
    C.GetUpgradeSlotGroup            = function() return { path = "p", group = "grp_front" } end
    fix.ffiStub.new                  = function() return groupBuffer end

    local function groupByContext(groups, ctx)
        for _, g in ipairs(groups) do
            if g.kind == "group" and tostring(g.contextID) == ctx then return g end
        end
    end
    local function hasMember(group, componentID)
        for _, m in ipairs(group.members or {}) do
            if tostring(m.componentID) == tostring(componentID) then return true end
        end
        return false
    end

    -- 52a: two turrets per group. Slots 1/3 carry the representatives (101,
    --      102); slots 2/4 carry non-representative turrets (103, 104) that
    --      match no group's componentID.
    turretsPerGroup = 2
    slotComponents = { 101, 103, 102, 104 }
    local groups52a = X4GunneryControlAPI.readGroups(42)
    local front52a, rear52a = groupByContext(groups52a, "10"), groupByContext(groups52a, "20")
    assert(front52a and rear52a,
        "52a: expected group entries for contextID 10 and 20")
    assert(X4GunneryState.canMutate(front52a) and X4GunneryState.canMutate(rear52a),
        "52a BUG: a duplicate path+group name must not make a group read-only. "
        .. "Mode/armed commands address contextID+path+group, which is exact. Got canMutate "
        .. tostring(X4GunneryState.canMutate(front52a)) .. "/" .. tostring(X4GunneryState.canMutate(rear52a)))
    assert(front52a.ambiguous == nil and rear52a.ambiguous == nil,
        "52a: readGroups must not set an ambiguous flag any more")
    assert(hasMember(front52a, 101),
        "52a: the slot carrying group 10's representative component (101) must be listed under group 10")
    assert(hasMember(rear52a, 102),
        "52a: the slot carrying group 20's representative component (102) must be listed under group 20")
    assert(front52a.members[1].macro == "turret_bor_m_railgun_02_mk1_macro"
            and rear52a.members[1].macro == "turret_bor_m_railgun_02_mk1_macro",
        "52a: every member must retain its authoritative group currentmacro for arc lookup")
    local members52a = #front52a.members + #rear52a.members
    assert(members52a == #slotComponents,
        "52a: every turret slot must appear exactly once across the groups; expected "
        .. tostring(#slotComponents) .. " members, got " .. tostring(members52a))

    -- 52b: one turret per group -- the common case, and the only shape the
    --      previous fix handled. Both groups still resolve and stay mutable.
    turretsPerGroup = 1
    slotComponents = { 101, 102 }
    local groups52b = X4GunneryControlAPI.readGroups(42)
    local front52b, rear52b = groupByContext(groups52b, "10"), groupByContext(groups52b, "20")
    assert(front52b and rear52b, "52b: expected group entries for contextID 10 and 20")
    assert(X4GunneryState.canMutate(front52b) and X4GunneryState.canMutate(rear52b),
        "52b: single-turret duplicate-named groups must be mutable")
    assert(hasMember(front52b, 101) and hasMember(rear52b, 102),
        "52b: each representative component must land in its own group")

    C.GetNumUpgradeGroups             = savedGetNumUpgradeGroups
    C.GetUpgradeGroups2               = savedGetUpgradeGroups2
    C.GetUpgradeGroupInfo2            = savedGetUpgradeGroupInfo2
    C.GetNumUpgradeSlots              = savedGetNumUpgradeSlots
    C.GetUpgradeSlotCurrentComponent  = savedGetUpgradeSlotCurrentComponent
    C.GetUpgradeSlotGroup             = savedGetUpgradeSlotGroup
    fix.ffiStub.new                   = savedFfiNew
end

-- ── 55 (readGroups padded IDs). readGroups: padded group IDs from two different APIs still attribute ──
-- GetUpgradeGroups2 and GetUpgradeSlotGroup are separate engine APIs. The ship
-- XML pads group= attributes with spaces, inconsistently. If one API returns
-- "grp_front " and the other returns " grp_front", the candidate key lookup
-- fails silently and the turret falls through to a "single" entry.
-- Both sides are trimmed only when building/looking up the internal candidate
-- key; entry.path/group and all engine-facing values stay byte-exact.

do
    local savedGetNumUpgradeGroups  = C.GetNumUpgradeGroups
    local savedGetUpgradeGroups2    = C.GetUpgradeGroups2
    local savedGetUpgradeGroupInfo2 = C.GetUpgradeGroupInfo2
    local savedGetNumUpgradeSlots   = C.GetNumUpgradeSlots
    local savedGetUpgradeSlotCurrentComponent = C.GetUpgradeSlotCurrentComponent
    local savedGetUpgradeSlotGroup  = C.GetUpgradeSlotGroup
    local savedFfiNew               = fix.ffiStub.new

    -- GetUpgradeGroups2 returns group id with trailing space.
    local groupBuffer55 = {}
    groupBuffer55[0] = { path = "p55", group = "grp_front_up_left ", contextid = 10 }
    fix.ffiStub.new = function() return groupBuffer55 end

    C.GetNumUpgradeGroups  = function() return 1 end
    C.GetUpgradeGroups2    = function() return 1 end
    C.GetUpgradeGroupInfo2 = function()
        return { count = 1, currentcomponent = 201, currentmacro = "", slotsize = "",
                 total = 1, operational = 1 }
    end
    C.GetNumUpgradeSlots = function() return 1 end
    C.GetUpgradeSlotCurrentComponent = function() return 201 end
    -- GetUpgradeSlotGroup returns the same group but with LEADING space instead.
    C.GetUpgradeSlotGroup = function()
        return { path = "p55", group = " grp_front_up_left" }
    end

    local groups55 = X4GunneryControlAPI.readGroups(42)

    -- Without the fix the turret falls through to a "single" entry.
    -- With the fix there is exactly one "group" entry and no "single" entry.
    local groupEntry55, singleEntry55 = nil, nil
    for _, g in ipairs(groups55) do
        if g.kind == "group" then groupEntry55 = g end
        if g.kind == "single" then singleEntry55 = g end
    end
    assert(groupEntry55 ~= nil,
        "55 BUG: padded group id mismatch between GetUpgradeGroups2 and GetUpgradeSlotGroup "
        .. "must not prevent turret attribution; expected a 'group' entry but got none")
    assert(singleEntry55 == nil,
        "55 BUG: turret fell through to a 'single' entry due to padded key mismatch; "
        .. "the candidate key lookup must trim both path and group")
    assert(#groupEntry55.members == 1,
        "55: the turret must be a member of the group entry; got "
        .. tostring(#(groupEntry55 and groupEntry55.members or {})) .. " members")
    -- The stored group field must stay byte-exact (not trimmed).
    assert(groupEntry55.group == "grp_front_up_left ",
        "55: entry.group must be the raw (untrimmed) value from the engine; got '"
        .. tostring(groupEntry55.group) .. "'")

    C.GetNumUpgradeGroups             = savedGetNumUpgradeGroups
    C.GetUpgradeGroups2               = savedGetUpgradeGroups2
    C.GetUpgradeGroupInfo2            = savedGetUpgradeGroupInfo2
    C.GetNumUpgradeSlots              = savedGetNumUpgradeSlots
    C.GetUpgradeSlotCurrentComponent  = savedGetUpgradeSlotCurrentComponent
    C.GetUpgradeSlotGroup             = savedGetUpgradeSlotGroup
    fix.ffiStub.new                   = savedFfiNew
end

-- ── 56. player-faction objects are never offered as engagement targets ─────────
-- Player-owned ships and stations must be excluded from readTargetCandidates()
-- regardless of whether they arrive via the sector sweep or as the current soft
-- target (force=true). The check lives in isEligibleEngagementTarget so force
-- cannot skip it.
do
    gcMenu.onShowMenu()
    local sess56 = API.getSession()
    assert(sess56 ~= nil, "expected session for player-faction exclusion test")
    sess56.phase = "target_select"

    GetPlayerContextByClass = function() return 1 end
    C.GetContextByClass = function(comp) return comp end
    C.GetDistanceBetween = function() return 500 end
    C.IsComponentOperational = function() return true end

    -- 200 = player-owned ship; 201 = player-owned station; 300 = hostile ship.
    -- 400 = friendly-but-not-player-owned ship (must remain selectable).
    GetContainedShips    = function() return { 200, 300, 400 } end
    GetContainedStations = function() return { 201 } end

    GetComponentData = function(component, ...)
        local keys, vals = {...}, {}
        local comp = tonumber(tostring(component)) or 0
        for _, k in ipairs(keys) do
            if k == "isplayerowned" then
                -- Only the two player-owned objects return true.
                vals[#vals + 1] = (comp == 200 or comp == 201)
            elseif k == "isenemy" then
                vals[#vals + 1] = (comp == 300)
            elseif k == "ishostile" then vals[#vals + 1] = false
            elseif k == "isfriend"  then vals[#vals + 1] = (comp == 400)
            elseif k == "isknown"   then vals[#vals + 1] = true
            elseif k == "isradarvisible" then vals[#vals + 1] = true
            elseif k == "maxradarrange"  then vals[#vals + 1] = 40000
            else vals[#vals + 1] = nil
            end
        end
        return unpack(vals)
    end

    -- 56a: player-owned ship excluded from sector sweep.
    -- 56b: player-owned station excluded from sector sweep.
    -- 56c: hostile ship still included.
    -- 56d: non-player-faction friendly still included.
    gcMenu.display()
    local rows56 = fix.getCreatedButtons()
    local function foundID(id)
        -- The target browser renders each candidate's name; the stubs return
        -- C.GetComponentName -> "0" for everything, so distinguish by checking
        -- that isEligibleEngagementTarget would have accepted it.
        -- Drive it directly through the TestAPI's readTargetCandidates path
        -- (target_select phase display calls readTargetCandidates internally).
        -- We verify the results by asking isEligibleEngagementTarget per id.
        local ok, _ = isEligibleEngagementTarget(id)
        return ok
    end

    -- Direct eligibility probe: the function is module-local but called through
    -- the tested code path above. Re-drive it via the public cycleTarget path
    -- which internally calls readTargetCandidates and builds from it.
    -- Use the TestAPI to count candidates instead.
    assert(type(X4GunneryControlAPI.readTargetCandidates) == "function"
        or type(X4GunneryControlAPI.cycleTarget) == "function",
        "readTargetCandidates or cycleTarget must be accessible for test 56")

    -- Drive via cycleTarget: set sess to direct/engaged so cycleTarget reads the list.
    local grp56 = fix.makeGroup{
        key = "grp56", displayName = "G56",
        members = { { componentID = 27, displayName = "T1", operational = true,
                      cameraSupported = true, componentKey = "27" } },
    }
    sess56.groups = { grp56 }
    sess56.checkedGroupKeys = { ["grp56"] = true }
    sess56.phase = "engaged"
    sess56.controlMode = "direct"
    sess56.committedBaseline = { { kind = "group", contextID = 5, path = "p", group = "g",
        shipID = sess56.shipID, mode = "attack", armed = false } }
    sess56.cameraMemberID = 27
    -- Start at hostile 300; cycle should find 400 (the friendly non-player), not 200/201.
    sess56.targetObjectID = 300
    sess56.aimTargetID = 300
    C.SetPlayerCameraTargetView = function() return true end
    C.SetSofttarget = function() return true end

    -- Advance clock so hasMultipleTargets memo from earlier tests is stale.
    clock = clock + 200

    -- Cycle forward; the only other candidate must be 400 (friendly non-player-owned).
    -- 200 (player ship) and 201 (player station) must not appear.
    X4GunneryControlAPI.cycleTarget(1)
    local after56 = sess56.targetObjectID
    assert(tostring(after56) ~= "200",
        "56a BUG: player-owned ship 200 appeared as a cycle target; "
        .. "isEligibleEngagementTarget must reject isplayerowned=true")
    assert(tostring(after56) ~= "201",
        "56b BUG: player-owned station 201 appeared as a cycle target; "
        .. "isEligibleEngagementTarget must reject isplayerowned=true")
    assert(tostring(after56) == "400",
        "56c/d: after cycling from hostile 300 the only remaining target must be "
        .. "friendly non-player-owned 400; got " .. tostring(after56))

    -- 56e: player-owned soft target excluded even with force=true.
    -- Set the soft target to the player-owned ship and verify it is not added.
    local savedGetSofttarget = C.GetSofttarget2
    C.GetSofttarget2 = function()
        return { softtargetID = 200, softtargetConnectionName = "" }
    end
    sess56.phase = "target_select"
    -- A forced player-owned soft target must not appear; cycle after resetting
    -- targetObjectID to something else.
    sess56.targetObjectID = 300
    sess56.aimTargetID = 300
    sess56.phase = "engaged"
    sess56.controlMode = "direct"
    clock = clock + 200
    X4GunneryControlAPI.cycleTarget(1)
    local afterSoft56 = sess56.targetObjectID
    assert(tostring(afterSoft56) ~= "200",
        "56e BUG: player-owned soft target 200 (force=true path) must be excluded; "
        .. "the isplayerowned check must fire before force can bypass visibility")
    C.GetSofttarget2 = savedGetSofttarget
end

-- ── 57. target browser exposes class/macro metadata and a top refresh ───────
do
    gcMenu.onShowMenu()
    local sess57 = API.getSession()
    sess57.phase = "target_select"
    GetPlayerContextByClass = function() return 1 end
    GetContainedShips = function() return { 570, 572, 573, 574, 575, 576 } end
    GetContainedStations = function() return { 571 } end
    C.GetContextByClass = function(comp) return comp end
    local classByComponent57 = {
        [570] = "ship_l", [573] = "ship_s", [574] = "ship_m", [575] = "ship_xl",
        [571] = "station",
    }
    C.IsComponentClass = function(component, class)
        local comp = tonumber(tostring(component))
        return classByComponent57[comp] == class
    end
    C.GetDistanceBetween = function(_, target) return tonumber(tostring(target)) == 570 and 2500 or 4000 end
    C.GetSofttarget2 = function() return { softtargetID = 570, softtargetConnectionName = "" } end
    local typeByMacro57 = {
        ship_xen_s_fighter_01_a_macro = "N",
        ship_xen_m_fighter_01_a_macro = "P",
        ship_arg_l_destroyer_01_a_macro = "Behemoth Vanguard",
        ship_arg_xl_carrier_01_a_macro = "Colossus Vanguard",
        station_arg_defence_disc_macro = "Argon Defence Platform",
    }
    GetMacroData = function(macro, field)
        return field == "name" and typeByMacro57[macro] or ""
    end
    GetComponentData = function(component, ...)
        local keys, vals, comp = {...}, {}, tonumber(tostring(component))
        for _, key in ipairs(keys) do
            if key == "isplayerowned" then vals[#vals + 1] = false
            elseif key == "isenemy" then vals[#vals + 1] = true
            elseif key == "ishostile" or key == "isfriend" then vals[#vals + 1] = false
            elseif key == "isknown" or key == "isradarvisible" then vals[#vals + 1] = true
            elseif key == "maxradarrange" then vals[#vals + 1] = 40000
            -- Live X4 9.00 returns numeric class ids (for example 91-94 for the
            -- four ship sizes), not the class-name strings used by the old
            -- test double. Classification must go through IsComponentClass.
            elseif key == "classid" then
                vals[#vals + 1] = ({ [573] = 91, [574] = 92, [570] = 93, [575] = 94, [571] = 95 })[comp] or 96
            elseif key == "macro" then
                vals[#vals + 1] = ({
                    [573] = "ship_xen_s_fighter_01_a_macro",
                    [574] = "ship_xen_m_fighter_01_a_macro",
                    [570] = "ship_arg_l_destroyer_01_a_macro",
                    [575] = "ship_arg_xl_carrier_01_a_macro",
                    [571] = "station_arg_defence_disc_macro",
                })[comp] or (comp == 572 and "unknown_object_macro" or "")
            else vals[#vals + 1] = nil end
        end
        return unpack(vals)
    end
    local candidates57 = API.readTargetCandidates()
    assert(#candidates57 == 7, "57: expected four ship sizes, station, and two fallback candidates")
    local byID57 = {}
    for _, candidate in ipairs(candidates57) do byID57[tostring(candidate.componentID)] = candidate end
    assert(byID57["570"].class == "L Ship", "57: L ship class label missing")
    assert(byID57["570"].macro == "ship_arg_l_destroyer_01_a_macro", "57: ship macro missing")
    assert(byID57["570"].typeName == "Behemoth Vanguard", "57: localized ship type missing")
    assert(byID57["573"].class == "S Ship", "57: S ship class label missing")
    assert(byID57["574"].class == "M Ship", "57: M ship class label missing")
    assert(byID57["575"].class == "XL Ship", "57: XL ship class label missing")
    assert(byID57["571"].class == ReadText(20991, 45), "57: station class label missing")
    assert(byID57["572"].class == ReadText(20991, 44), "57: unknown ship class must fall back to kind")
    assert(byID57["572"].typeName == ReadText(20991, 51), "57: unknown macro name must not expose raw macro")
    assert(byID57["576"].typeName == ReadText(20991, 51), "57: missing macro must render Unknown Object")
    C.GetSofttarget2 = function() return { softtargetID = 571, softtargetConnectionName = "" } end
    local stationCurrent57 = API.readTargetCandidates()
    local currentStation57
    for _, candidate in ipairs(stationCurrent57) do
        if tostring(candidate.componentID) == "571" then currentStation57 = candidate end
    end
    assert(currentStation57 and currentStation57.class == ReadText(20991, 45),
        "57: current soft-target station must retain localized Station class")
    C.GetSofttarget2 = function() return { softtargetID = 570, softtargetConnectionName = "" } end
    gcMenu.display()
    local rendered57 = {}
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if entry.row == "570" or entry.row == "573" or entry.row == "574" or entry.row == "575" then
            rendered57[entry.row] = rendered57[entry.row] or {}
            rendered57[entry.row][entry.column] = entry.text
        end
    end
    local expectedRendered57 = {
        ["573"] = { class = "S Ship", typeName = "N", macro = "ship_xen_s_fighter_01_a_macro" },
        ["574"] = { class = "M Ship", typeName = "P", macro = "ship_xen_m_fighter_01_a_macro" },
        ["570"] = { class = "L Ship", typeName = "Behemoth Vanguard", macro = "ship_arg_l_destroyer_01_a_macro" },
        ["575"] = { class = "XL Ship", typeName = "Colossus Vanguard", macro = "ship_arg_xl_carrier_01_a_macro" },
    }
    for component, expected in pairs(expectedRendered57) do
        assert(rendered57[component] and rendered57[component][3] == expected.class,
            "57: " .. expected.class .. " must be bound to rendered column 3")
        assert(rendered57[component][4] == expected.typeName,
            "57: " .. expected.class .. " localized type must be bound to rendered column 4")
    end
    local refreshButtons57 = {}
    for _, button in ipairs(fix.getCreatedButtons()) do
        if button.text == ReadText(20991, 15) then refreshButtons57[#refreshButtons57 + 1] = button end
    end
    assert(#refreshButtons57 >= 2, "57: target browser needs refresh controls at top and bottom")
    refreshButtons57[1].handlers.onClick()
    local refreshedButtons57 = {}
    for _, button in ipairs(fix.getCreatedButtons()) do
        if button.text == ReadText(20991, 15) then refreshedButtons57[#refreshedButtons57 + 1] = button end
    end
    refreshedButtons57[#refreshedButtons57].handlers.onClick()
    local log57 = table.concat(fix.getCapturedLog(), "\n")
    assert(log57:find("event=target_browser action=refresh location=top", 1, true),
        "57: top refresh click needs audit evidence")
    assert(log57:find("event=target_browser action=refresh location=bottom", 1, true),
        "57: bottom refresh click needs audit evidence")
    assert(log57:find("event=target_browser action=rendered candidates=7 class_values=7 type_values=7", 1, true),
        "57: rendered target metadata needs aggregate audit evidence")
    for component, expected in pairs(expectedRendered57) do
        local evidence = 'event=target_browser action=row component=' .. component
            .. ' name="0" class="' .. expected.class .. '" type="' .. expected.typeName
            .. '" macro="' .. expected.macro .. '"'
        assert(log57:find(evidence, 1, true),
            "57: rendered row audit needs exact " .. expected.class .. " component/class/macro evidence")
    end
end

-- ── 58. surface type/macro filters use live operational component macros ────
do
    local sess57 = API.getSession()
    sess57.phase, sess57.controlMode = "engaged", "direct"
    sess57.targetObjectID, sess57.aimTargetID = 600, 600
    sess57.surfaceTypeFilter, sess57.surfaceMacroFilter = "any", "any"
    C.IsComponentClass = function() return false end
    GetPlayerContextByClass = function() return nil end
    C.GetNumUpgradeSlots = function(_, _, upgrade) return upgrade == "turret" and 2 or 0 end
    C.GetUpgradeSlotCurrentComponent = function(_, _, slot) return 700 + slot end
    C.GetUpgradeSlotCurrentMacro = function(object, _, _, slot)
        if tonumber(tostring(object):match("%d+")) == 601 then return "turret_m" end
        return slot == 1 and "turret_l" or "turret_m"
    end
    C.IsComponentOperational = function() return true end
    GetComponentData = function(component, ...)
        local vals = {}
        for _, key in ipairs({...}) do
            if key == "macro" then vals[#vals + 1] = tonumber(tostring(component)) == 701 and "turret_l" or "turret_m"
            elseif key == "isplayerowned" then vals[#vals + 1] = false
            elseif key == "maxradarrange" then vals[#vals + 1] = 40000
            else vals[#vals + 1] = false end
        end
        return unpack(vals)
    end
    GetMacroData = function(macro, key)
        if key == "name" then return macro == "turret_l" and "Large Turret" or "Medium Turret" end
        return ""
    end
    gcMenu.display()
    local function rowDropdown(fixture, rowID)
        for _, dropdown in ipairs(fixture.getCreatedDropDowns()) do
            if dropdown.row == rowID then return dropdown end
        end
    end
    local dropdowns57 = fix.getCreatedDropDowns()
    assert(#dropdowns57 >= 2, "57: surface panel needs type and macro dropdowns")
    assert(rowDropdown(fix, "surface_type_filter").startOption == "any",
        "57: surface type filter must render at Any")
    assert(#rowDropdown(fix, "surface_macro_filter").options == 3,
        "57: surface equipment filter must offer Any plus both localized turret names")
    rowDropdown(fix, "surface_type_filter").handlers.onDropDownConfirmed(nil, "turret")
    assert(sess57.surfaceTypeFilter == "turret" and sess57.surfaceMacroFilter == "any",
        "57: changing type must apply it and reset macro to Any")
    gcMenu.display()
    rowDropdown(fix, "surface_macro_filter").handlers.onDropDownConfirmed(nil, "turret_l")
    assert(sess57.surfaceMacroFilter == "turret_l", "57: macro lock was not retained")
    local surfaceRefresh57
    for _, button in ipairs(fix.getCreatedButtons()) do
        if button.row == "surface_refresh" then surfaceRefresh57 = button end
    end
    assert(surfaceRefresh57, "57: top surface Refresh button missing")
    C.GetUpgradeSlotGroup = function() return { path = "", group = "" } end
    surfaceRefresh57.handlers.onClick()
    local log58 = table.concat(fix.getCapturedLog(), "\n")
    assert(log58:find("event=surface_browser action=filter kind=type value=turret equipment_reset=any target=600", 1, true),
        "57: type filter change needs audit evidence")
    assert(log58:find("event=surface_browser action=filter kind=equipment value=turret_l target=600", 1, true),
        "57: equipment filter change needs audit evidence")
    assert(log58:find("event=surface_browser action=refresh location=top target=600", 1, true),
        "57: surface Refresh needs audit evidence")
    assert(log58:find("event=surface_browser action=rendered target=600 target_name=\"0\"", 1, true)
            and log58:find("type_filter=turret equipment_filter=turret_l all=2 alternatives=1 equipment_options=2", 1, true),
        "57: filtered surface render needs exact count/filter evidence")
    local sawFilteredSurface57 = false
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if tostring(entry.row) == "701" then
            sawFilteredSurface57 = true
        end
    end
    assert(sawFilteredSurface57, "57: filtered page must bind the matching equipment row")

    GetMacroData = function() return "" end
    sess57.surfaceTypeFilter, sess57.surfaceMacroFilter = "any", "any"
    gcMenu.display()
    dropdowns57 = fix.getCreatedDropDowns()
    local fallbackEquipment = dropdowns57[#dropdowns57]
    assert(fallbackEquipment.row == "surface_macro_filter"
            and #fallbackEquipment.options == 1,
        "57: unresolved equipment names must not create indistinguishable dropdown choices")

    GetMacroData = function(macro, key)
        if key == "name" then return macro == "turret_l" and "Large Turret" or "Medium Turret" end
        return ""
    end
    C.GetNumUpgradeSlots = function(destructible, _, upgrade)
        if upgrade ~= "turret" then return 0 end
        return tonumber(tostring(destructible):match("%d+")) == 601 and 1 or 2
    end
    C.GetUpgradeSlotCurrentComponent = function(destructible, _, slot)
        return tonumber(tostring(destructible):match("%d+")) == 601 and 702 or 700 + slot
    end
    sess57.targetObjectID, sess57.surfaceTypeFilter, sess57.surfaceMacroFilter = 601, "turret", "turret_l"
    gcMenu.display()
    assert(sess57.surfaceMacroFilter == "any",
        "57: changing to a target without the selected equipment must reset to Any")

    sess57.targetObjectID, sess57.surfaceMacroFilter = 600, "turret_l"
    C.GetNumUpgradeSlots = function() return 0 end
    gcMenu.display()
    assert(sess57.surfaceMacroFilter == "any",
        "57: disappearance of the last matching component must reset to Any")
    log58 = table.concat(fix.getCapturedLog(), "\n")
    assert(log58:find("event=surface_browser action=filter_reset kind=equipment reason=unavailable previous=turret_l target=601", 1, true),
        "57: target-change equipment reset needs exact audit evidence")
    assert(log58:find("event=surface_browser action=filter_reset kind=equipment reason=unavailable previous=turret_l target=600", 1, true),
        "57: component-disappearance equipment reset needs exact audit evidence")
end

print("runtime targeting browser tests passed")
