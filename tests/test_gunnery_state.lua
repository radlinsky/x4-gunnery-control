local State = dofile("ui/gunnery_state.lua")
local function eq(a, b, label) assert(a == b, (label or "values differ") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

eq(State.singleKey(12), "single:12", "single key")
eq(State.groupKey(5, "foo", "bar"), "group:5:foo:bar", "group key")
eq(State.turretGroupLabel("group_front_up_left"), "Front Upper Left", "front upper left label")
eq(State.turretGroupLabel("group_back_mid_right"), "Rear Center Right", "back mid right label")
eq(State.turretGroupLabel("group_mid_bottom"), "Center Lower", "mid bottom label")
eq(State.turretGroupLabel("group_rear"), "Rear", "rear label")
eq(State.turretGroupLabel("group_center_bottom_left2"), "Center Lower Left 2", "numbered left label")
eq(State.turretGroupLabel("group_front_up_middle"), "Front Center Upper", "middle synonym label")
eq(State.turretGroupLabel("group_front_inside"), "Front Inner", "inside label")
eq(State.turretGroupLabel("group_front_left_inside"), "Front Left Inner", "lateral and radial labels remain distinct")
eq(State.turretGroupLabel("group_front_front_up_upper_left_left"), "Front Upper Left", "repeated directions deduplicate")
eq(State.turretGroupLabel("group01"), nil, "opaque group has no label")
assert(not State.isEngagementTargetAllowed(99, 99), "occupied ship is excluded")
assert(not State.isEngagementTargetAllowed("99", 99), "ID representation does not bypass exclusion")
assert(not State.isEngagementTargetAllowed(99, 0), "zero target is excluded")
assert(State.isEngagementTargetAllowed(99, 100), "another player-owned ship can be selected")
-- ULL suffix normalisation (live bug: same ship compared across FFI and id() paths)
assert(not State.isEngagementTargetAllowed("463766", "463766ULL"), "own ship excluded when shipID plain and targetRootID has ULL suffix")
assert(not State.isEngagementTargetAllowed("463766ULL", "463766"), "own ship excluded when shipID has ULL suffix and targetRootID plain")
assert(not State.isEngagementTargetAllowed("463766ULL", "463766ULL"), "own ship excluded when both sides have ULL suffix")
assert(not State.isEngagementTargetAllowed("463766ull", "463766ULL"), "ULL suffix comparison is case-insensitive")
assert(not State.isEngagementTargetAllowed("77LL", "77"), "own ship excluded when shipID has LL suffix")
assert(not State.isEngagementTargetAllowed("77", "77ll"), "own ship excluded when targetRootID has lowercase ll suffix")
-- Zero check must also be robust to ULL/LL suffix
assert(not State.isEngagementTargetAllowed(99, "0ULL"), "zero ULL target is excluded")
assert(not State.isEngagementTargetAllowed(99, "0LL"), "zero LL target is excluded")
assert(not State.isEngagementTargetAllowed(99, "0ull"), "zero lowercase ull target is excluded")
-- A genuinely different ship is still allowed even when suffix forms differ
assert(State.isEngagementTargetAllowed("463766", "463816ULL"), "different ship with ULL suffix is allowed")
assert(State.isEngagementTargetAllowed("463766ULL", "463816"), "different ship: shipID ULL, targetRootID plain, still allowed")
-- nil on either side
assert(not State.isEngagementTargetAllowed(nil, 99), "nil shipID rejected")
assert(not State.isEngagementTargetAllowed(99, nil), "nil targetRootID rejected")
-- normID is exported because the runtime compares ids across the same FFI/id()
-- boundary (targetRoot returns "463766ULL", id() returns "463766").
eq(State.normID("463766ULL"), "463766", "normID strips ULL")
eq(State.normID(463766), "463766", "normID accepts numbers")
eq(State.normID("77ll"), "77", "normID strips lowercase ll")
assert(State.isReturnablePlayerView("firstperson"), "first-person chair view resumes")
assert(State.isReturnablePlayerView("externalfirstperson"), "external first-person view resumes")
assert(State.isReturnablePlayerView("cockpit"), "cockpit view resumes")
assert(not State.isReturnablePlayerView("map"), "map is a suspended menu mode")
local groups = {
  { key = "g1", members = { { componentID = 1, operational = false } } },
  { key = "g2", members = { { componentID = 2, operational = true } } },
}
local session = State.newSession(99, "gunnercontrol")
eq(session.lifecycle, State.lifecycle.owned, "new session owns its view")
assert(State.isOwned(session), "new session is owned")
State.setLifecycle(session, State.lifecycle.suspendingMap)
assert(State.isMapSuspended(session), "map suspension is recognized")
assert(not State.isOwned(session), "suspended map session no longer owns a view")
State.setLifecycle(session, State.lifecycle.suspendedMap)
assert(State.isMapSuspended(session), "fully suspended map session is recognized")
State.setLifecycle(session, State.lifecycle.reopening)
assert(State.isMapSuspended(session), "map reopen remains an explicit suspension path")
State.setLifecycle(session, State.lifecycle.owned)
State.retainSelection(session, groups); eq(session.selectedGroupKey, "g2", "first usable group"); eq(session.selectedMemberID, 2, "first usable member")
session.selectedGroupKey, session.selectedMemberID = "g2", 2
State.retainSelection(session, groups); eq(session.selectedGroupKey, "g2", "selection is retained")
local group, member = groups[2], groups[2].members[1]
group.kind, group.mode, group.armed, group.operationalCount, group.totalCount = "group", "defend", false, 1, 1
group.contextID, group.path, group.group = 7, "path", "name"
State.beginTargetSelection(session, group, member); eq(session.phase, "target_select", "target picker phase"); eq(session.cameraMemberID, 2, "target picker camera member")
-- beginEngaged auto replaces beginWatch
State.toggleGroup(session, "g2")
State.beginEngaged(session, {}, "auto"); eq(session.phase, "engaged", "auto-engage phase"); eq(#session.committedBaseline, 0, "auto: committedBaseline empty before seeding")
-- beginEngaged direct replaces beginDirect; returns committedBaseline (seeded before engage)
group.componentID = 2
-- seed baseline so beginEngaged has something to return
State.seedBaseline(session, { group })
local snaps = State.beginEngaged(session, { group }, "direct"); eq(session.phase, "engaged", "direct-engage phase"); eq(snaps[1].mode, "defend", "snapshot mode")
local snapshot = snaps[1]
State.returnToConsole(session); eq(session.phase, "console", "camera return phase"); assert(session.cameraMemberID == nil, "camera return clears member")
session.phase = "engaged"
-- releaseDirect returns committedBaseline (does NOT clear it)
local released = State.releaseDirect(session); eq(released[1], snapshot, "release returns committedBaseline entry"); eq(session.phase, "console", "release phase")
-- Only a destroyed group (no operational turret) is unwritable. A duplicate
-- group name never blocks mutation: commands address contextID+path+group.
assert(State.canMutate(group))
local savedOperational = group.operationalCount
group.operationalCount = 0; assert(not State.canMutate(group))
group.operationalCount = savedOperational
local savedGroup = State.snapshotForSave(snapshot)
eq(savedGroup.shipID, "99", "save payload converts ship ID")
eq(savedGroup.contextID, "7", "save payload converts group context")
eq(savedGroup.path, "path", "save payload copies path")
eq(savedGroup.armed, false, "save payload preserves armed state")
local savedSingle = State.snapshotForSave({ shipID = 3, kind = "single", componentID = 4, mode = "defend", armed = true })
eq(savedSingle.componentID, "4", "save payload converts component ID")
assert(savedSingle.contextID == nil, "single payload omits group context")
-- newSession defaults
local s2 = State.newSession(55, "ctrl")
assert(s2.checkedGroupKeys ~= nil, "newSession: checkedGroupKeys exists")
assert(type(s2.checkedGroupKeys) == "table", "newSession: checkedGroupKeys is table")
eq(s2.controlMode, nil, "newSession: controlMode nil")
eq(s2.povAnchor, "turret", "newSession: povAnchor default turret")
eq(s2.povMode, "manual", "newSession: povMode default manual")
eq(s2.cameraIndex, 1, "newSession: cameraIndex default 1")
eq(s2.aimTargetID, nil, "newSession: aimTargetID nil")
eq(s2.autoNextTarget, true, "newSession: autoNextTarget defaults on")
eq(s2.surfaceTypeFilter, "any", "newSession: surface type filter defaults to Any")
eq(s2.surfaceMacroFilter, "any", "newSession: surface macro filter defaults to Any")
eq(s2.surfaceBrowser.pageSize, 20, "newSession: surface browser page size is bounded to 20")
eq(s2.surfaceBrowser.autoRefresh, false, "newSession: surface auto-refresh defaults off")
assert(type(s2.surfaceBrowser.pageResults) == "table", "newSession: page results are session-local")
assert(s2.committedBaseline ~= nil, "newSession: committedBaseline exists")
assert(type(s2.committedBaseline) == "table", "newSession: committedBaseline is table")
assert(s2.staged ~= nil, "newSession: staged exists")
assert(type(s2.staged) == "table", "newSession: staged is table")

local surfaceFixture = {
    { kindKey = "turret", macro = "turret_l", macroLabel = "Large Turret" },
    { kindKey = "turret", macro = "turret_m", macroLabel = "Medium Turret" },
    { kindKey = "shield", macro = "shield_l", macroLabel = "Large Shield" },
    { kindKey = "turret", macro = "turret_l", macroLabel = "Large Turret" },
}
local turretMacros = State.surfaceMacroOptions(surfaceFixture, "turret")
eq(#turretMacros, 2, "surfaceMacroOptions: unique macros within selected type")
eq(turretMacros[1].id, "turret_l", "surfaceMacroOptions: sorted by label")
local tiedMacros = State.surfaceMacroOptions({
    { kindKey = "turret", macro = "z_macro", macroLabel = "Same" },
    { kindKey = "turret", macro = "a_macro", macroLabel = "Same" },
}, "any")
eq(tiedMacros[1].id, "a_macro", "surfaceMacroOptions: macro id breaks equal-label ties")
local resolvedOnly = State.surfaceMacroOptions({
    { kindKey = "turret", macro = "known", macroLabel = "Known", macroLabelResolved = true },
    { kindKey = "turret", macro = "hidden_a", macroLabel = "Unknown", macroLabelResolved = false },
    { kindKey = "turret", macro = "hidden_b", macroLabel = "Unknown", macroLabelResolved = false },
}, "turret")
eq(#resolvedOnly, 1, "surfaceMacroOptions: unresolved macros are not indistinguishable choices")
eq(State.reconcileSurfaceMacroFilter(resolvedOnly, "known"), "known",
    "reconcileSurfaceMacroFilter: available selection remains active")
local reconciled, wasReset = State.reconcileSurfaceMacroFilter(resolvedOnly, "gone")
eq(reconciled, "any", "reconcileSurfaceMacroFilter: unavailable selection resets to Any")
eq(wasReset, true, "reconcileSurfaceMacroFilter: unavailable reset is reported")
eq(#State.filterSurfaceTargets(surfaceFixture, "turret", "turret_l"), 2,
    "filterSurfaceTargets: type and macro are both applied")
eq(#State.filterSurfaceTargets(surfaceFixture, "any", "shield_l"), 1,
    "filterSurfaceTargets: Any type preserves macro lock")
eq(State.normalizeSurfaceSize(" xl "), "XL", "normalizeSurfaceSize: canonical XL")
eq(State.normalizeSurfaceSize("xs"), "XS", "normalizeSurfaceSize: canonical XS")
eq(State.normalizeSurfaceSize("extralarge"), "XL", "normalizeSurfaceSize: X4 extralarge API value")
eq(State.normalizeSurfaceSize("large"), "L", "normalizeSurfaceSize: X4 large API value")
eq(State.normalizeSurfaceSize("medium"), "M", "normalizeSurfaceSize: X4 medium API value")
eq(State.normalizeSurfaceSize("small"), "S", "normalizeSurfaceSize: X4 small API value")
eq(State.normalizeSurfaceSize("extra small"), "XS", "normalizeSurfaceSize: defensive extrasmall API value")
eq(State.normalizeSurfaceSize(0), "unknown", "normalizeSurfaceSize: numeric API value is unknown")
eq(State.normalizeSurfaceSize("capital"), "unknown", "normalizeSurfaceSize: unreported class is unknown")
for index, size in ipairs({ "XL", "L", "M", "S", "XS", "unknown" }) do
    eq(State.surfaceSizeRank(size), index, "surfaceSizeRank: complete priority for " .. size)
end
local metadataFixture = {
    { componentID = "30ULL", kindKey = "shield", size = "XL", distance = 100 },
    { componentID = "20ULL", kindKey = "turret", size = "L", distance = 200 },
    { componentID = "10ULL", kindKey = "turret", size = "L", distance = 200 },
}
local typeFirst, sizeFirst = {}, {}
for index, entry in ipairs(metadataFixture) do typeFirst[index], sizeFirst[index] = entry, entry end
table.sort(typeFirst, function(a, b) return State.surfaceMetadataLess(a, b, "type_first") end)
table.sort(sizeFirst, function(a, b) return State.surfaceMetadataLess(a, b, "size_first") end)
eq(State.normID(typeFirst[1].componentID), "10", "surface comparator: type first, then stable ID")
eq(State.normID(typeFirst[2].componentID), "20", "surface comparator: equal metadata ID tie-break")
eq(State.normID(sizeFirst[1].componentID), "30", "surface comparator: size-first policy is explicit")
local validPolicy, policyError = pcall(State.surfaceMetadataLess,
    metadataFixture[1], metadataFixture[2], "implicit")
eq(validPolicy, false, "surface comparator: cross-type policy must be explicit")
assert(tostring(policyError):find("unknown surface cross%-type policy"),
    "surface comparator: invalid policy explains the contract")
local unknownDistance = {
    componentID = 2, kindKey = "turret", size = "M", distance = -1,
}
assert(State.surfaceMetadataLess(
    { componentID = 1, kindKey = "turret", size = "M", distance = 900 },
    unknownDistance, "type_first"), "surface comparator: unknown distance sorts last")
local pinnedFixture = {
    { componentID = "1ULL", kindKey = "turret", macro = "turret_l" },
    { componentID = "2ULL", kindKey = "shield", macro = "shield_l" },
    { componentID = "3ULL", kindKey = "turret", macro = "turret_l" },
}
local alternatives = State.surfaceAlternatives(pinnedFixture, 1, "turret", "turret_l")
eq(#alternatives, 1, "surfaceAlternatives: filters alternatives and excludes pinned")
eq(State.normID(alternatives[1].componentID), "3", "surfaceAlternatives: keeps matching non-pinned row")
eq(#State.surfaceAlternatives(pinnedFixture, 2, "turret", "turret_l"), 2,
    "surfaceAlternatives: pinned filter mismatch does not alter matching alternatives")
for _, boundary in ipairs({
    { count = 0, pages = 1, page1 = 0 }, { count = 1, pages = 1, page1 = 1 },
    { count = 20, pages = 1, page1 = 20 }, { count = 21, pages = 2, page1 = 20 },
    { count = 40, pages = 2, page1 = 20 }, { count = 41, pages = 3, page1 = 20 },
}) do
    local entries = {}
    for i = 1, boundary.count do entries[i] = { componentID = i } end
    local pageEntries, page, pages, first, last = State.surfacePage(entries, 1, 20)
    eq(#pageEntries, boundary.page1, "surfacePage: page-one count at " .. boundary.count)
    eq(page, 1, "surfacePage: normalized page at " .. boundary.count)
    eq(pages, boundary.pages, "surfacePage: page count at " .. boundary.count)
    if boundary.count > 0 then eq(last - first + 1, boundary.page1, "surfacePage: exact bounds") end
end
local fortyOne = {}
for i = 1, 41 do fortyOne[i] = { componentID = i } end
local finalPage, normalizedPage, pageCount, firstIndex, lastIndex = State.surfacePage(fortyOne, 3, 20)
eq(#finalPage, 1, "surfacePage: 41st alternative is alone on page three")
eq(normalizedPage, 3, "surfacePage: keeps valid page")
eq(pageCount, 3, "surfacePage: reports three pages")
eq(firstIndex, 41, "surfacePage: final first index")
eq(lastIndex, 41, "surfacePage: final last index")
eq(State.surfacePageKey(7, { { componentID = "1ULL" }, { componentID = 2 } }), "7:1,2",
    "surfacePageKey: generation and exact normalized IDs define cache identity")
assert(State.surfacePageKey(8, { { componentID = 1 }, { componentID = 2 } })
        ~= State.surfacePageKey(7, { { componentID = 1 }, { componentID = 2 } }),
    "surfacePageKey: generation invalidates same page membership")
assert(State.surfacePageKey(7, { { componentID = 2 }, { componentID = 1 } })
        ~= State.surfacePageKey(7, { { componentID = 1 }, { componentID = 2 } }),
    "surfacePageKey: membership order is part of cache identity")
assert(s2.directSnapshots == nil, "newSession: no legacy directSnapshots field")

-- toggleGroup on/off
local ts = State.newSession(1, "g")
eq(State.toggleGroup(ts, "k1"), true, "toggleGroup: first toggle returns true (checked)")
assert(ts.checkedGroupKeys["k1"] == true, "toggleGroup: key is present after check")
eq(State.toggleGroup(ts, "k1"), false, "toggleGroup: second toggle returns false (unchecked)")
assert(ts.checkedGroupKeys["k1"] == nil, "toggleGroup: key is absent after uncheck")
State.toggleGroup(ts, "k1"); State.toggleGroup(ts, "k2")
assert(ts.checkedGroupKeys["k1"] and ts.checkedGroupKeys["k2"], "toggleGroup: two keys coexist")

-- toggleAllGroups: select-all checkbox. Only mutable groups can be checked, so
-- "all" means every mutable group; a session whose mutable groups are all
-- checked toggles back to none.
local tas = State.newSession(1, "g")
tas.groups = {
    { key = "m1", operationalCount = 1, totalCount = 1 },
    { key = "dead", operationalCount = 0, totalCount = 1 },
    { key = "m2", operationalCount = 2, totalCount = 2 },
}
eq(State.toggleAllGroups(tas), true, "toggleAllGroups: returns true when it checks")
assert(tas.checkedGroupKeys["m1"] and tas.checkedGroupKeys["m2"], "toggleAllGroups: checks every mutable group")
assert(tas.checkedGroupKeys["dead"] == nil, "toggleAllGroups: never checks an immutable group")
eq(State.toggleAllGroups(tas), false, "toggleAllGroups: returns false when it clears")
assert(next(tas.checkedGroupKeys) == nil, "toggleAllGroups: clears every key")
State.toggleGroup(tas, "m1")
eq(State.toggleAllGroups(tas), true, "toggleAllGroups: a partial selection fills up rather than clearing")
assert(tas.checkedGroupKeys["m2"], "toggleAllGroups: fills in the missing group")
eq(State.allGroupsChecked(tas), true, "allGroupsChecked: true once every mutable group is checked")
State.toggleGroup(tas, "m1")
eq(State.allGroupsChecked(tas), false, "allGroupsChecked: false with one unchecked")
eq(State.allGroupsChecked(State.newSession(1, "g")), false, "allGroupsChecked: false with no groups")

-- checkedGroups order
local cgs = State.newSession(1, "g")
local grpA = { key = "A", members = { { componentID = 10, operational = true } }, kind = "group", mode = "attack", armed = true, operationalCount = 1, totalCount = 1 }
local grpB = { key = "B", members = { { componentID = 20, operational = false } }, kind = "group", mode = "defend", armed = false, operationalCount = 0, totalCount = 1 }
local grpC = { key = "C", members = { { componentID = 30, operational = true } }, kind = "group", mode = "attack", armed = false, operationalCount = 1, totalCount = 1 }
cgs.groups = { grpA, grpB, grpC }
State.toggleGroup(cgs, "C"); State.toggleGroup(cgs, "A")
local checked = State.checkedGroups(cgs)
eq(#checked, 2, "checkedGroups: count")
eq(checked[1].key, "A", "checkedGroups: A comes first (session.groups order)")
eq(checked[2].key, "C", "checkedGroups: C comes second")

-- cameraRoster: skips non-operational, preserves order across two groups
local rs = State.newSession(1, "g")
local rgrpA = { key = "A", members = {
    { componentID = 101, operational = false },
    { componentID = 102, operational = true },
}, kind = "group", mode = "attack", armed = true, operationalCount = 1, totalCount = 2 }
local rgrpB = { key = "B", members = {
    { componentID = 201, operational = true },
    { componentID = 202, operational = false },
    { componentID = 203, operational = true },
}, kind = "group", mode = "defend", armed = false, operationalCount = 2, totalCount = 3 }
rs.groups = { rgrpA, rgrpB }
State.toggleGroup(rs, "A"); State.toggleGroup(rs, "B")
local roster = State.cameraRoster(rs)
eq(#roster, 3, "cameraRoster: 3 operational members across two groups")
eq(roster[1].componentID, 102, "cameraRoster: first is A's operational member")
eq(roster[1].groupKey, "A", "cameraRoster: groupKey attached from A")
eq(roster[2].componentID, 201, "cameraRoster: second is B's first operational member")
eq(roster[2].groupKey, "B", "cameraRoster: groupKey attached from B")
eq(roster[3].componentID, 203, "cameraRoster: third is B's third operational member")

-- cameraRoster only includes checked groups
local rsUnchecked = State.newSession(1, "g")
rsUnchecked.groups = { rgrpA, rgrpB }
State.toggleGroup(rsUnchecked, "A")  -- only A checked, not B
local rosterU = State.cameraRoster(rsUnchecked)
eq(#rosterU, 1, "cameraRoster: unchecked group excluded")
eq(rosterU[1].componentID, 102, "cameraRoster: only checked group's member present")

-- cycleCamera wrapping forwards and backwards
local cs = State.newSession(1, "g")
cs.groups = { rgrpA, rgrpB }
State.toggleGroup(cs, "A"); State.toggleGroup(cs, "B")
cs.cameraIndex = 1
local m = State.cycleCamera(cs, 1)
eq(m.componentID, 201, "cycleCamera +1: from index 1 moves to 2")
eq(cs.cameraIndex, 2, "cycleCamera +1: index updated")
eq(cs.cameraMemberID, 201, "cycleCamera +1: cameraMemberID updated")
m = State.cycleCamera(cs, 1)
eq(m.componentID, 203, "cycleCamera +1: index 2 -> 3")
m = State.cycleCamera(cs, 1)
eq(m.componentID, 102, "cycleCamera +1: wraps from 3 back to 1")
eq(cs.cameraIndex, 1, "cycleCamera +1: index wraps to 1")
m = State.cycleCamera(cs, -1)
eq(m.componentID, 203, "cycleCamera -1: wraps backwards from 1 to 3")
eq(cs.cameraIndex, 3, "cycleCamera -1: index wraps to 3")

-- cycleCamera clamps stale index (only reachable with no cameraMemberID to
-- re-derive from)
cs.cameraIndex, cs.cameraMemberID = 99, nil
m = State.cycleCamera(cs, 1)
assert(m ~= nil, "cycleCamera: stale index is clamped, returns a member")

-- cycleCamera re-derives its position from cameraMemberID. Restore sets only
-- cameraMemberID, leaving cameraIndex at the newSession default of 1; without
-- re-deriving, the first cycle after a load steps from the wrong place and
-- skips a member.
local ds = State.newSession(1, "g")
ds.groups = { rgrpA, rgrpB }
State.toggleGroup(ds, "A"); State.toggleGroup(ds, "B")
ds.cameraMemberID, ds.cameraIndex = 203, 1   -- as a restore leaves it
m = State.cycleCamera(ds, 1)
eq(m.componentID, 102, "cycleCamera: wraps from the restored member, not from cameraIndex")
eq(ds.cameraIndex, 1, "cycleCamera: index resynced to the restored member before moving")
ds.cameraMemberID, ds.cameraIndex = 201, 1
m = State.cycleCamera(ds, -1)
eq(m.componentID, 102, "cycleCamera -1: steps back from the restored member")
-- normID boundary: the id may come back from FFI with a "ULL" suffix.
ds.cameraMemberID, ds.cameraIndex = "203ULL", 1
m = State.cycleCamera(ds, 1)
eq(m.componentID, 102, "cycleCamera: re-derives across the ULL id boundary")

-- cycleCamera on empty roster
local es = State.newSession(1, "g")
es.groups = { { key = "E", members = { { componentID = 999, operational = false } }, kind = "group", mode = "attack", armed = false } }
State.toggleGroup(es, "E")
local em = State.cycleCamera(es, 1)
assert(em == nil, "cycleCamera: empty roster returns nil")
assert(es.cameraMemberID == nil, "cycleCamera: empty roster leaves cameraMemberID nil")

-- beginEngaged auto: returns committedBaseline (empty before seeding), phase/controlMode/cameraMemberID set
local ba = State.newSession(99, "g")
ba.groups = { rgrpA, rgrpB }
State.toggleGroup(ba, "A"); State.toggleGroup(ba, "B")
local baSnaps = State.beginEngaged(ba, { rgrpA, rgrpB }, "auto")
eq(ba.phase, "engaged", "beginEngaged auto: phase is engaged")
eq(ba.controlMode, "auto", "beginEngaged auto: controlMode is auto")
eq(#baSnaps, 0, "beginEngaged auto: no baseline returned (not yet seeded)")
eq(#ba.committedBaseline, 0, "beginEngaged auto: committedBaseline empty before seeding")
eq(ba.cameraIndex, 1, "beginEngaged auto: cameraIndex reset to 1")
eq(ba.cameraMemberID, 102, "beginEngaged auto: cameraMemberID is first roster member")

-- Entering engaged always starts on the turret camera in manual mode, so the
-- recorded POV must match it: a stale povAnchor from an earlier visit would
-- grey out the wrong button in the panel.
local bp = State.newSession(99, "g")
bp.groups = { rgrpA }
State.toggleGroup(bp, "A")
bp.povAnchor, bp.povMode = "target", "cinematic"
State.beginEngaged(bp, { rgrpA }, "auto")
eq(bp.povAnchor, "turret", "beginEngaged resets povAnchor to turret")
eq(bp.povMode, "manual", "beginEngaged resets povMode to manual")

-- beginEngaged direct with one group: seedBaseline first so committedBaseline has entries
local bd1 = State.newSession(99, "g")
bd1.groups = { rgrpA }
State.toggleGroup(bd1, "A")
rgrpA.componentID = 555; rgrpA.contextID = 7; rgrpA.path = "path"; rgrpA.group = "name"
State.seedBaseline(bd1, { rgrpA })
local bd1Snaps = State.beginEngaged(bd1, { rgrpA }, "direct")
eq(bd1.phase, "engaged", "beginEngaged direct 1grp: phase engaged")
eq(bd1.controlMode, "direct", "beginEngaged direct 1grp: controlMode direct")
eq(#bd1Snaps, 1, "beginEngaged direct 1grp: returns committedBaseline with one entry")
eq(#bd1.committedBaseline, 1, "beginEngaged direct 1grp: committedBaseline has one entry")
eq(bd1Snaps[1].shipID, 99, "beginEngaged direct 1grp: shipID")
eq(bd1Snaps[1].kind, "group", "beginEngaged direct 1grp: kind")
eq(bd1Snaps[1].componentID, 555, "beginEngaged direct 1grp: componentID")
eq(bd1Snaps[1].contextID, 7, "beginEngaged direct 1grp: contextID")
eq(bd1Snaps[1].path, "path", "beginEngaged direct 1grp: path")
eq(bd1Snaps[1].group, "name", "beginEngaged direct 1grp: group")
eq(bd1Snaps[1].mode, "attack", "beginEngaged direct 1grp: mode")
eq(bd1Snaps[1].armed, true, "beginEngaged direct 1grp: armed")
eq(bd1.cameraMemberID, 102, "beginEngaged direct 1grp: cameraMemberID from roster")

-- beginEngaged direct with two groups
local grpD = { key = "D", members = { { componentID = 300, operational = true } },
    kind = "single", componentID = 888, contextID = 9, path = "p2", group = "g2",
    mode = "defend", armed = false, operationalCount = 1, totalCount = 1 }
local bd2 = State.newSession(99, "g")
bd2.groups = { rgrpA, grpD }
State.toggleGroup(bd2, "A"); State.toggleGroup(bd2, "D")
State.seedBaseline(bd2, { rgrpA, grpD })
local bd2Snaps = State.beginEngaged(bd2, { rgrpA, grpD }, "direct")
eq(#bd2Snaps, 2, "beginEngaged direct 2grp: two baseline entries returned")
eq(bd2Snaps[1].componentID, 555, "beginEngaged direct 2grp: first entry componentID")
eq(bd2Snaps[2].componentID, 888, "beginEngaged direct 2grp: second entry componentID")
eq(bd2Snaps[2].kind, "single", "beginEngaged direct 2grp: second entry kind")

-- releaseDirect: returns committedBaseline WITHOUT clearing it, restores console phase
local rd = State.newSession(1, "g")
rd.committedBaseline = { { shipID = 1 }, { shipID = 2 } }
rd.phase = "engaged"
local rdList = State.releaseDirect(rd)
eq(#rdList, 2, "releaseDirect: returns full committedBaseline")
eq(rd.phase, "console", "releaseDirect: phase set to console")
eq(#rd.committedBaseline, 2, "releaseDirect: committedBaseline NOT cleared (revert target stays)")
-- releaseDirect on non-engaged phase does not change phase
rd.phase = "target_select"
State.releaseDirect(rd)
eq(rd.phase, "target_select", "releaseDirect: non-engaged phase unchanged")
-- releaseDirect never returns nil
rd.committedBaseline = {}
local rdNil = State.releaseDirect(rd)
assert(rdNil ~= nil, "releaseDirect: never returns nil")
eq(#rdNil, 0, "releaseDirect: returns empty list not nil")

-- snapshotsForSave over a mixed group/single list
local snap1 = { shipID = 10, kind = "group", componentID = 100, contextID = 20, path = "p", group = "g", mode = "attack", armed = true }
local snap2 = { shipID = 11, kind = "single", componentID = 200, mode = "defend", armed = false }
local saved = State.snapshotsForSave({ snap1, snap2 })
eq(#saved, 2, "snapshotsForSave: two entries")
eq(saved[1].shipID, "10", "snapshotsForSave: first shipID stringified")
eq(saved[1].contextID, "20", "snapshotsForSave: first contextID stringified")
eq(saved[2].shipID, "11", "snapshotsForSave: second shipID stringified")
eq(saved[2].componentID, "200", "snapshotsForSave: second componentID stringified")
assert(saved[2].contextID == nil, "snapshotsForSave: single entry has no contextID")

-- snapshotsForSave on legacy single snapshot (table with .shipID, no [1])
local legacySnap = { shipID = 99, kind = "group", componentID = 77, contextID = 5, path = "lp", group = "lg", mode = "attack", armed = false }
local legacySaved = State.snapshotsForSave(legacySnap)
eq(#legacySaved, 1, "snapshotsForSave: legacy single returns one-element list")
eq(legacySaved[1].shipID, "99", "snapshotsForSave: legacy shipID stringified")

-- returnToConsole clears controlMode and resets povMode to manual
local rc = State.newSession(1, "g")
rc.controlMode = "direct"
rc.povMode = "cinematic"
rc.checkedGroupKeys["k1"] = true
State.returnToConsole(rc)
eq(rc.controlMode, nil, "returnToConsole: clears controlMode")
eq(rc.povMode, "manual", "returnToConsole: resets povMode to manual")
assert(rc.checkedGroupKeys["k1"] == true, "returnToConsole: checkedGroupKeys survive")

-- retainSelection prunes checked keys whose group vanished
local pr = State.newSession(1, "g")
State.toggleGroup(pr, "existing")
State.toggleGroup(pr, "vanished")
local existingGrp = { key = "existing", members = { { componentID = 1, operational = true } } }
State.retainSelection(pr, { existingGrp })
assert(pr.checkedGroupKeys["existing"] == true, "retainSelection: surviving group key kept")
assert(pr.checkedGroupKeys["vanished"] == nil, "retainSelection: vanished group key pruned")

-- State.cycleEntry
local ceEntries = {
    { componentID = 10 },
    { componentID = 20 },
    { componentID = 30 },
}
-- forward wrap
local ce = State.cycleEntry(ceEntries, 10, 1)
eq(ce.componentID, 20, "cycleEntry: forward from first")
ce = State.cycleEntry(ceEntries, 30, 1)
eq(ce.componentID, 10, "cycleEntry: forward wraps from last to first")
-- backward wrap
ce = State.cycleEntry(ceEntries, 10, -1)
eq(ce.componentID, 30, "cycleEntry: backward wraps from first to last")
ce = State.cycleEntry(ceEntries, 20, -1)
eq(ce.componentID, 10, "cycleEntry: backward from second")
-- missing current: return entries[1]
ce = State.cycleEntry(ceEntries, 99, 1)
eq(ce.componentID, 10, "cycleEntry: missing currentID returns first entry")
-- nil current: return entries[1]
ce = State.cycleEntry(ceEntries, nil, 1)
eq(ce.componentID, 10, "cycleEntry: nil currentID returns first entry")
-- ULL-suffixed ids match their converted form, as everywhere else
ce = State.cycleEntry({ { componentID = "10ULL" }, { componentID = "20ULL" } }, "10", 1)
eq(ce.componentID, "20ULL", "cycleEntry: normalises the ULL suffix")
-- empty list: return nil
ce = State.cycleEntry({}, 10, 1)
assert(ce == nil, "cycleEntry: empty list returns nil")
-- tostring comparison: string "20" matches numeric 20
ce = State.cycleEntry(ceEntries, "20", 1)
eq(ce.componentID, 30, "cycleEntry: string currentID matches numeric componentID")

-- State.isNullID: guards that once tested tostring(v) == "0" missed the cdata
-- form "0ULL" that FFI hands back for unset UniverseID fields. isNullID accepts
-- all three null representations so they fire correctly in game.
assert(State.isNullID(nil),    "isNullID: nil is null")
assert(State.isNullID(0),      "isNullID: numeric 0 is null")
assert(State.isNullID("0"),    "isNullID: string '0' is null")
assert(State.isNullID("0ULL"), "isNullID: '0ULL' cdata form is null")
assert(State.isNullID("0ull"), "isNullID: '0ull' lowercase cdata form is null")
assert(not State.isNullID("463766"),    "isNullID: real id is not null")
assert(not State.isNullID("463766ULL"), "isNullID: real id with ULL suffix is not null")

-- turretGroupLabel: whitespace-tolerance for vanilla XML padding.
-- The real ship XML pads group= values with spaces; assert that padded forms
-- produce the same label as their unpadded counterparts, and that
-- whitespace-only identifiers return nil.
do
    local unpaddedLeft = State.turretGroupLabel("group_front_up_left")
    local unpaddedMid  = State.turretGroupLabel("group_front_up_middle")
    -- trailing space (real: "group_front_up_left ")
    eq(State.turretGroupLabel("group_front_up_left "), unpaddedLeft,
        "trailing space must produce the same label as unpadded")
    -- leading space (real: " group_front_up_mid " — mid and middle are synonyms)
    eq(State.turretGroupLabel(" group_front_up_middle "), unpaddedMid,
        "leading+trailing space must produce the same label as unpadded")
    -- double leading space (real: "  group_front_down_mid ")
    eq(State.turretGroupLabel("  group_front_down_mid "), State.turretGroupLabel("group_front_down_mid"),
        "double leading space must produce the same label as unpadded")
    -- whitespace-only must return nil
    assert(State.turretGroupLabel("  ") == nil,
        "two-space whitespace-only identifier must return nil")
    assert(State.turretGroupLabel("   ") == nil,
        "three-space whitespace-only identifier must return nil")
end

-- Session persistence: encode/decode/saveState/restoreState.
--
-- The hostile group id below is deliberate. Vanilla pads group attributes with
-- whitespace, and the payload's own structural characters (; , = %) must not be
-- able to escape their field, or one odd group id silently corrupts the whole
-- restore.
do
    local nasty = "  group_front_up_left ;weird,=key%stuff "

    -- Round trip through the string transport, hostile id included.
    local encoded = State.encode({
        { t = "session", phase = "engaged" },
        { t = "checked", path = "../", group = nasty },
    })
    assert(not encoded:find("[;,=]%s*weird"), "raw delimiters must not survive escaping")
    local decoded = State.decode(encoded)
    eq(#decoded, 2, "round trip must return both records")
    eq(decoded[1].phase, "engaged", "session field must survive the round trip")
    eq(decoded[2].group, nasty, "a group id containing ; , = and % must survive byte-exact")
    eq(#State.decode(""), 0, "an empty payload decodes to no records")
    eq(#State.decode(nil), 0, "a nil payload decodes to no records")

    -- restoreState must match on path+group and take contextID from the live
    -- group list, because a load reassigns every contextID.
    local session = State.newSession("443760", "gunnercontrol")
    session.groups = {
        { key = "group:NEW:../:" .. nasty, contextID = "NEW", path = "../", group = nasty,
          kind = "group", componentID = "C1", mode = "attackenemies", armed = true,
          operationalCount = 1, totalCount = 1 },
        { key = "group:NEW:../:other", contextID = "NEW", path = "../", group = "other",
          kind = "group", componentID = "C2", mode = "attack", armed = false,
          operationalCount = 1, totalCount = 1 },
    }
    session.checkedGroupKeys[session.groups[1].key] = true
    -- committedBaseline replaces directSnapshots as the persistent revert target
    session.committedBaseline = {
        { kind = "group", shipID = "443760", contextID = "OLD", path = "../",
          group = nasty, mode = "attackenemies", armed = true },
    }
    session.phase, session.controlMode = "engaged", "direct"
    session.aimTargetID = "999"

    local reloaded = State.newSession("443760", "gunnercontrol")
    local ok = State.restoreState(reloaded, State.decode(State.encode(State.saveState(session))),
        session.groups)
    assert(ok, "restoreState must report that a session record was found")
    eq(reloaded.phase, "engaged", "phase must be restored")
    eq(reloaded.controlMode, "direct", "controlMode must be restored")
    eq(reloaded.aimTargetID, "999", "the target must be restored, since the engine drops it")
    eq(reloaded.checkedGroupKeys["group:NEW:../:" .. nasty], true,
        "a checked group must be re-keyed onto the live contextID")
    eq(#reloaded.committedBaseline, 1, "the committedBaseline must be restored")
    eq(reloaded.committedBaseline[1].contextID, "NEW",
        "the baseline entry must take the LIVE contextID, never the saved one")
    eq(reloaded.committedBaseline[1].mode, "attackenemies", "baseline mode must survive")
    eq(reloaded.committedBaseline[1].armed, true, "baseline armed must survive as a boolean")

    -- A group that no longer exists must be dropped, not written back.
    local orphaned = State.newSession("443760", "gunnercontrol")
    State.restoreState(orphaned, State.decode(State.encode(State.saveState(session))), {})
    eq(#orphaned.committedBaseline, 0, "a baseline entry with no live group must be dropped")
    eq(next(orphaned.checkedGroupKeys), nil, "a checked group with no live group must be dropped")

    -- Regression: a restored session must preserve the independently saved
    -- checkbox state. Reached by committing a ticked group (which writes
    -- TICK_MODE into committedBaseline) and then unticking it (which leaves
    -- the baseline alone) before saving: the payload then carries a baseline
    -- of attackenemies and an EMPTY checked set. Restore must keep it unchecked
    -- and display the unticked fallback, while retaining the baseline so
    -- standing up can still revert the committed mode.
    local committed = State.newSession("443760", "gunnercontrol")
    committed.groups = session.groups
    committed.committedBaseline = {
        { kind = "group", shipID = "443760", contextID = "OLD", path = "../",
          group = nasty, mode = State.TICK_MODE, armed = true },
    }
    assert(next(committed.checkedGroupKeys) == nil, "fixture must save with nothing checked")
    local rebound = State.newSession("443760", "gunnercontrol")
    State.restoreState(rebound, State.decode(State.encode(State.saveState(committed))), session.groups)
    eq(rebound.checkedGroupKeys["group:NEW:../:" .. nasty], nil,
        "an explicitly unticked group must remain unchecked after restore")
    eq(rebound.staged["group:NEW:../:" .. nasty].mode, State.UNTICK_FALLBACK,
        "an unticked TICK_MODE baseline must restore its Defend fallback")
    eq(rebound.committedBaseline[1].mode, State.TICK_MODE,
        "the committed TICK_MODE baseline must remain available for revert")

    -- Regression: a normal direct engagement saves the original baseline and
    -- the checked group separately. Restore must rebuild the checked group's
    -- current staged mode as TICK_MODE rather than showing the baseline mode
    -- in the dropdown while the checkbox says it is directed.
    local directSaved = State.newSession("443760", "gunnercontrol")
    directSaved.groups = session.groups
    local directKey = session.groups[1].key
    directSaved.checkedGroupKeys[directKey] = true
    directSaved.committedBaseline = {
        { kind = "group", shipID = "443760", contextID = "OLD", path = "../",
          group = nasty, mode = "defend", armed = true },
    }
    local directBack = State.newSession("443760", "gunnercontrol")
    State.restoreState(directBack, State.decode(State.encode(State.saveState(directSaved))), session.groups)
    local directRestoredKey = "group:NEW:../:" .. nasty
    eq(directBack.checkedGroupKeys[directRestoredKey], true,
        "a checked direct group must remain checked after restore")
    eq(directBack.staged[directRestoredKey].mode, State.TICK_MODE,
        "a checked direct group must restore its temporary attackenemies mode")

    -- The legacy single-snapshot fallback in snapshotsForSave still works.
    local legacy = State.newSession("443760", "gunnercontrol")
    legacy.phase, legacy.controlMode = "engaged", "direct"
    legacy.committedBaseline = { kind = "single", shipID = "443760",
        componentID = "555", mode = "defend", armed = false }
    local legacyBack = State.newSession("443760", "gunnercontrol")
    State.restoreState(legacyBack, State.decode(State.encode(State.saveState(legacy))), {})
    eq(#legacyBack.committedBaseline, 1, "a legacy single baseline must still round trip")
    eq(legacyBack.committedBaseline[1].componentID, "555", "the legacy componentID must survive")
    eq(legacyBack.committedBaseline[1].armed, false, "legacy armed=false must survive")
end

-- The save/load half: a load reassigns every id, so the same payload has to be
-- read differently from a UI reload. Group names still match; nothing addressed
-- by a bare componentID does.
do
    local saved = State.newSession("441090", "gunnercontrol")
    saved.shipName = "Behemoth"
    saved.phase, saved.controlMode = "engaged", "direct"
    saved.aimTargetID, saved.cameraMemberID = "700", "701"
    saved.groups = { { key = "group:OLD:../:aft", contextID = "OLD", path = "../", group = "aft" } }
    saved.checkedGroupKeys[saved.groups[1].key] = true
    saved.committedBaseline = {
        { kind = "group", shipID = "441090", contextID = "OLD", path = "../",
          group = "aft", mode = "attackenemies", armed = true },
        { kind = "single", shipID = "441090", componentID = "800",
          mode = "defend", armed = true },
    }
    local payload = State.encode(State.saveState(saved))
    local liveGroups = { { key = "group:2080707:../:aft", contextID = "2080707",
        path = "../", group = "aft" } }

    -- Same ship, new ids: the group baseline entry survives, the componentID-addressed
    -- values do not, because those ids now belong to arbitrary components.
    local loaded = State.newSession("2080707", "gunnercontrol")
    loaded.shipName = "Behemoth"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "a payload for this ship must restore after a load")
    eq(loaded.phase, "engaged", "phase must survive a load")
    eq(loaded.aimTargetID, nil, "a reassigned target id must be dropped, not re-pointed")
    eq(loaded.cameraMemberID, nil, "a reassigned camera member id must be dropped")
    eq(#loaded.committedBaseline, 1, "only the name-addressed baseline entry survives a load")
    eq(loaded.committedBaseline[1].contextID, "2080707", "the baseline entry takes the live contextID")
    -- restoreDirect uses committedBaseline shipID to match session ship; must be live.
    eq(loaded.committedBaseline[1].shipID, "2080707", "the baseline entry takes the live shipID")

    -- A different ship with the same group names must not be touched: this is
    -- the whole reason the name is in the payload.
    local other = State.newSession("2080707", "gunnercontrol")
    other.shipName = "Odysseus"
    eq(State.restoreState(other, State.decode(payload), liveGroups), false,
        "a payload from another ship must be refused")
    eq(#other.committedBaseline, 0, "a refused payload must write no baseline entries")
    eq(next(other.checkedGroupKeys), nil, "a refused payload must check no groups")
end

-- The POV turret. cameraMemberID is a componentID, so a load reassigns it; the
-- turret's group name and its position in that group do not change.
do
    local function shipWithTurrets(shipID, contextID, turretIDs)
        local session = State.newSession(shipID, "gunnercontrol")
        session.shipName = "Behemoth"
        local members = {}
        for _, componentID in ipairs(turretIDs) do
            members[#members + 1] = { componentID = componentID, operational = true,
                cameraSupported = true }
        end
        session.groups = { { key = "group:" .. contextID .. ":../:aft", contextID = contextID,
            path = "../", group = "aft", members = members } }
        session.checkedGroupKeys[session.groups[1].key] = true
        session.phase, session.controlMode = "engaged", "direct"
        return session
    end

    local saved = shipWithTurrets("441090", "OLD", { "801", "802", "803" })
    saved.cameraMemberID = "802"  -- the middle turret, not the first
    local payload = State.encode(State.saveState(saved))

    -- A reload keeps the ids; the same barrel must come back either way.
    local reloaded = shipWithTurrets("441090", "OLD", { "801", "802", "803" })
    State.restoreState(reloaded, State.decode(payload), saved.groups)
    eq(reloaded.cameraMemberID, "802", "a reload must return to the same turret")

    -- A load reassigns every turret id. Position within the group is what
    -- carries over, so the POV must land on the second turret again and not on
    -- whichever one happens to be listed first.
    local loaded = shipWithTurrets("2080707", "NEW", { "901", "902", "903" })
    State.restoreState(loaded, State.decode(payload), loaded.groups)
    eq(loaded.cameraMemberID, "902", "a load must return to the same turret position")

    -- firstCameraMember must hand back the member table, not the (key, id) pair
    -- firstOperationalMember returns: enterCamera reads cameraSupported off it.
    local member = State.firstCameraMember(loaded.groups)
    eq(type(member), "table", "firstCameraMember must return a member table")
    eq(member.componentID, "901", "firstCameraMember must return the first usable turret")
    eq(State.firstCameraMember({ { members = {
        { componentID = "1", operational = true, cameraSupported = false },
        { componentID = "2", operational = false, cameraSupported = true },
    } } }), nil, "a turret that cannot host the camera is not a candidate")
end

-- Reviewer branch matrix: these deliberately small cases document the edges
-- that are easy to lose in a persistence refactor.  The contract is named
-- cases plus executable-line coverage, rather than a misleading branch %.
do
    -- nil session/records and a payload without a session record are refusals.
    assert(not State.restoreState(nil, {}, {}), "matrix: nil session is refused")
    assert(not State.restoreState(State.newSession(1, "g"), nil, {}), "matrix: nil records are refused")
    assert(not State.restoreState(State.newSession(1, "g"), { { t = "checked" } }, {}),
        "matrix: no session record is refused")

    -- A complete session record is the persistence schema. Older released
    -- payloads can omit the whole stable-camera-location triplet, but no
    -- released writer omitted the phase, control, POV, flag, or ID fields.
    local function sessionRecord(values)
        local record = {
            t = "session", phase = "console", controlMode = "",
            povAnchor = "turret", povMode = "manual",
            autoNextTarget = "1",
            shipID = "old", shipName = "", aimTargetID = "", cameraMemberID = "",
            camPath = "", camGroup = "", camIndex = "",
        }
        for key, value in pairs(values or {}) do record[key] = value end
        return record
    end

    -- Every empty/nonempty saved/live ship-name pairing except two differing
    -- nonempty names is permitted. IDs still decide reload versus save/load.
    local function restoreWithNames(savedName, liveName)
        local candidate = State.newSession("new", "g")
        candidate.shipName = liveName
        return State.restoreState(candidate, {
            sessionRecord({ shipName = savedName }),
        }, {})
    end
    assert(restoreWithNames("", ""), "matrix: empty/empty ship names permit restore")
    assert(restoreWithNames("saved", ""), "matrix: saved-only ship name permits restore")
    assert(restoreWithNames("", "live"), "matrix: live-only ship name permits restore")
    assert(restoreWithNames("same", "same"), "matrix: matching ship names permit restore")
    assert(not restoreWithNames("saved", "other"), "matrix: differing ship names refuse restore")

    -- The first two emitted persistence formats had no shipName or stable
    -- camera location (and carried a now-unused targetObjectID). These are
    -- known complete legacy records, so their explicitly absent fields remain
    -- compatible without accepting a partially-present modern triplet.
    local legacyRecord = sessionRecord({ targetObjectID = "legacy-root" })
    legacyRecord.shipName = nil
    legacyRecord.camPath, legacyRecord.camGroup, legacyRecord.camIndex = nil, nil, nil
    assert(State.restoreState(State.newSession("new", "g"), { legacyRecord }, {}),
        "matrix: complete first-format session remains restorable")

    -- A positive camera index is valid persisted state even when that member
    -- has since disappeared. Restore accepts it without inventing a member so
    -- the runtime can use its safe no-camera fallback and clear MD state.
    local staleCamera = State.newSession("same", "g")
    staleCamera.shipName = "ship"
    local nonCameraGroups = { { key = "g", path = "p", group = "g", members = {
        { componentID = "dead", operational = false, cameraSupported = true },
        { componentID = "unsupported", operational = true, cameraSupported = false },
    } } }
    assert(State.restoreState(staleCamera, {
        sessionRecord({ shipID = "same", shipName = "ship", camPath = "p", camGroup = "g", camIndex = "9" }),
    }, nonCameraGroups), "matrix: missing saved camera member still restores the session")
    assert(staleCamera.cameraMemberID == nil, "matrix: missing saved camera member is not invented")
    assert(State.firstCameraMember(nonCameraGroups) == nil,
        "matrix: non-operational or unsupported restored members cannot host a camera")

    -- Malformed escapes and records never raise or manufacture saved state.
    local malformedEscapes = State.decode("t=session,shipName=bad%ZZ;not-a-field")
    assert(#malformedEscapes == 2, "matrix: malformed escape/record is tolerated")
    assert(not State.restoreState(State.newSession(1, "g"), State.decode("not-a-field"), {}),
        "matrix: malformed record cannot become a session")

    -- Parseable truncation and out-of-domain values are refusals, before a
    -- candidate is changed. This is the pure counterpart of the runtime
    -- Direct-baseline regression below.
    local unchanged = State.newSession("same", "g")
    local originalBaseline = { { shipID = "same", kind = "group", contextID = "c",
        path = "p", group = "g", mode = "defend", armed = true } }
    unchanged.phase, unchanged.controlMode = "engaged", "direct"
    unchanged.checkedGroupKeys = { live = true }
    unchanged.committedBaseline = originalBaseline
    local function assertRefused(records, label)
        assert(not State.restoreState(unchanged, records, {}), label)
        eq(unchanged.phase, "engaged", label .. ": phase is unchanged")
        eq(unchanged.controlMode, "direct", label .. ": control mode is unchanged")
        assert(unchanged.checkedGroupKeys.live, label .. ": checks are unchanged")
        assert(unchanged.committedBaseline == originalBaseline, label .. ": baseline is unchanged")
    end
    assertRefused({ { t = "session" } }, "matrix: truncated session is refused")
    for _, bad in ipairs({
        { phase = "broken" }, { controlMode = "auto" }, { povAnchor = "bridge" },
        { povMode = "orbit" }, { autoNextTarget = "true" },
        { camPath = "p", camGroup = "g", camIndex = "1.5" },
        { camPath = "p", camGroup = "", camIndex = "1" },
    }) do
        assertRefused({ sessionRecord(bad) }, "matrix: invalid session enum/form is refused")
    end
    assertRefused({ sessionRecord({ shipID = "same", phase = "engaged", controlMode = "direct" }), {
        t = "snapshot", kind = "group", shipID = "same", contextID = "c", path = "p", group = "g", mode = "attack",
    } }, "matrix: malformed snapshot is refused")
    assertRefused({ sessionRecord(), {
        t = "snapshot", kind = "group", shipID = "old", contextID = "c", path = "p", group = "g", mode = "attack", armed = "1",
    } }, "matrix: console snapshot is refused")
    assertRefused({ sessionRecord(), { t = "unknown" } }, "matrix: unknown record type is refused")

    -- A Direct session intentionally keeps its baseline while target
    -- selection is open. Legacy "snapshot" records still restore as committedBaseline
    -- to support payloads written before the rename.
    local targetSelect = State.newSession("same", "g")
    assert(State.restoreState(targetSelect, {
        sessionRecord({ shipID = "same", phase = "target_select", controlMode = "direct" }),
        { t = "snapshot", kind = "group", shipID = "same", contextID = "c", path = "p", group = "g", mode = "attack", armed = "1" },
    }, { { key = "live", contextID = "live", path = "p", group = "g" } }),
        "matrix: target-select Direct (legacy snapshot) restores")
    eq(#targetSelect.committedBaseline, 1, "matrix: legacy snapshot promoted to committedBaseline")

    -- A changed-ID load drops a component-addressed single baseline entry, while
    -- duplicate records do not make restore fail or add phantom entries.
    local changedIDs = State.newSession("new", "g")
    local changedHead = sessionRecord({ phase = "engaged", controlMode = "direct" })
    assert(not State.restoreState(changedIDs, {
        changedHead,
        { t = "baseline", kind = "single", componentID = "old-turret", mode = "defend", armed = "1" },
    }, {}), "matrix: malformed changed-ID baseline is refused")
    assert(State.restoreState(changedIDs, {
        changedHead,
        { t = "baseline", kind = "single", shipID = "old", componentID = "old-turret", mode = "defend", armed = "1" },
    }, {}), "matrix: changed-ID session restores")
    eq(#changedIDs.committedBaseline, 0, "matrix: changed-ID single baseline entry is dropped")
    local duplicates = State.newSession("same", "g")
    local duplicate = sessionRecord({ shipID = "same" })
    assert(State.restoreState(duplicates, {
        duplicate, sessionRecord({ shipID = "same" }),
    }, {}), "matrix: duplicate session records are tolerated")
    eq(#duplicates.committedBaseline, 0, "matrix: duplicate/malformed records do not manufacture baseline state")

    -- Force the no-match/closing-loop paths that normal happy-path selections
    -- skip, while preserving their public return values.
    eq(State.turretGroupLabel("group_left"), "Left", "matrix: directional slot assignment")
    assert(State.firstOperationalMember({ { members = { { componentID = 1, operational = false } } } }) == nil,
        "matrix: no operational member")
    assert(State.firstCameraMember({ { members = { { componentID = 1, operational = true, cameraSupported = false } } } }) == nil,
        "matrix: no supported camera member")
    assert(State.findMemberLocation({ groups = { { members = { { componentID = 1 } } } } }, 2) == nil,
        "matrix: missing member location")
    local retained = State.newSession(1, "g")
    retained.selectedGroupKey, retained.selectedMemberID = "g", 2
    State.retainSelection(retained, { { key = "g", members = { { componentID = 1, operational = false } } } })
    assert(retained.selectedMemberID == nil, "matrix: unsupported retained selection falls back to none")
    local checkedMatrix = State.newSession(1, "g")
    checkedMatrix.groups = {
        { key = "checked", operationalCount = 1, members = { { componentID = 1, operational = true } } },
        { key = "unchecked", operationalCount = 1, members = { { componentID = 2, operational = false } } },
        { key = "destroyed", operationalCount = 0, members = { { componentID = 3, operational = false } } },
    }
    State.toggleGroup(checkedMatrix, "checked")
    assert(not State.allGroupsChecked(checkedMatrix), "matrix: unchecked mutable group prevents all-checked")
    eq(#State.checkedGroups(checkedMatrix), 1, "matrix: checked group list excludes unchecked groups")
    eq(#State.cameraRoster(checkedMatrix), 1, "matrix: camera roster filters non-operational and unchecked members")
    eq(State.statusLabel(nil), "destroyed", "matrix: nil group status")
    eq(State.statusLabel({ operationalCount = 1, totalCount = 2 }), "damaged", "matrix: damaged status")
    eq(State.statusLabel({ operationalCount = 2, totalCount = 2 }), "operational", "matrix: operational status")
end

-- seedBaseline: seeds committedBaseline and staged from live groups
do
    local sb = State.newSession(77, "g")
    local grpGroup = { key = "group:C1:path:name", kind = "group", componentID = 10,
        contextID = "C1", path = "path", group = "name", mode = "attack", armed = true,
        operationalCount = 1, totalCount = 1 }
    local grpSingle = { key = "single:20", kind = "single", componentID = 20,
        contextID = nil, path = nil, group = nil, mode = "defend", armed = false,
        operationalCount = 1, totalCount = 1 }
    State.seedBaseline(sb, { grpGroup, grpSingle })
    eq(#sb.committedBaseline, 2, "seedBaseline: two entries in committedBaseline")
    eq(sb.committedBaseline[1].shipID, 77, "seedBaseline: shipID from session")
    eq(sb.committedBaseline[1].kind, "group", "seedBaseline: kind from group")
    eq(sb.committedBaseline[1].mode, "attack", "seedBaseline: mode from group")
    eq(sb.committedBaseline[1].armed, true, "seedBaseline: armed from group")
    eq(sb.committedBaseline[2].kind, "single", "seedBaseline: single kind")
    eq(sb.committedBaseline[2].armed, false, "seedBaseline: single armed false")
    -- staged is keyed by group.key
    local expectedKey = State.groupKey("C1", "path", "name")
    assert(sb.staged[expectedKey] ~= nil, "seedBaseline: staged has group entry")
    eq(sb.staged[expectedKey].mode, "attack", "seedBaseline: staged mode matches group")
    eq(sb.staged[expectedKey].armed, true, "seedBaseline: staged armed matches group")
    local singleKey = State.singleKey(20)
    assert(sb.staged[singleKey] ~= nil, "seedBaseline: staged has single entry")
    eq(sb.staged[singleKey].mode, "defend", "seedBaseline: single staged mode")
    -- Neither seeded group is in TICK_MODE, so neither comes up ticked.
    assert(next(sb.checkedGroupKeys) == nil,
        "seedBaseline: a group not in TICK_MODE must not be ticked")
    -- nil groups: no error
    State.seedBaseline(sb, nil)
    eq(#sb.committedBaseline, 0, "seedBaseline nil groups: clears committedBaseline")
end

-- seedBaseline ticks groups the ship is already flying in TICK_MODE. Reported
-- live 2026-08-10: a committed "Attack all enemies" change survived standing up
-- but its checkbox did not, and ticking the group by hand then recorded
-- TICK_MODE as its own preTickMode, so the checkbox stopped changing the mode
-- in either direction.
do
    local sb = State.newSession(77, "g")
    local already = { key = "group:C1:p:already", kind = "group", componentID = 10,
        contextID = "C1", path = "p", group = "already", mode = State.TICK_MODE,
        armed = true, operationalCount = 1, totalCount = 1 }
    local other = { key = "group:C1:p:other", kind = "group", componentID = 11,
        contextID = "C1", path = "p", group = "other", mode = "defend",
        armed = true, operationalCount = 1, totalCount = 1 }
    State.seedBaseline(sb, { already, other })
    local alreadyKey = State.groupKey("C1", "p", "already")
    local otherKey = State.groupKey("C1", "p", "other")
    assert(sb.checkedGroupKeys[alreadyKey] == true,
        "seedBaseline: a group already in TICK_MODE must come up ticked")
    assert(sb.checkedGroupKeys[otherKey] == nil,
        "seedBaseline: a group in another mode must come up unticked")
    assert(sb.staged[alreadyKey].preTickMode == nil,
        "seedBaseline: a seeded tick has no earlier mode to record")
    -- Unticking it falls to UNTICK_FALLBACK rather than restoring TICK_MODE.
    State.toggleGroup(sb, alreadyKey, already.armed)
    eq(sb.checkedGroupKeys[alreadyKey], nil, "seeded tick: untick clears the checkbox")
    eq(sb.staged[alreadyKey].mode, State.UNTICK_FALLBACK,
        "seeded tick: untick falls back rather than restoring TICK_MODE")
    -- And ticking it again is a real round trip, not a no-op.
    State.toggleGroup(sb, alreadyKey, already.armed)
    eq(sb.staged[alreadyKey].mode, State.TICK_MODE, "seeded tick: re-tick sets TICK_MODE")
    eq(sb.staged[alreadyKey].preTickMode, State.UNTICK_FALLBACK,
        "seeded tick: re-tick records the displaced fallback mode")
end

-- applyTick must never record TICK_MODE as preTickMode: untick would then
-- "restore" the mode the group already has and the checkbox would look dead.
do
    local sb = State.newSession(77, "g")
    local key = State.groupKey("C1", "p", "g")
    sb.staged = { [key] = { mode = State.TICK_MODE, armed = true } }
    sb.committedBaseline = {}
    State.toggleGroup(sb, key, true)
    eq(sb.checkedGroupKeys[key], true, "tick on an already-TICK_MODE group checks it")
    assert(sb.staged[key].preTickMode ~= State.TICK_MODE,
        "preTickMode must never be TICK_MODE itself")
    State.toggleGroup(sb, key, true)
    eq(sb.staged[key].mode, State.UNTICK_FALLBACK,
        "untick must fall back, not restore TICK_MODE")
end

-- baselineStagedKey is the single derivation shared by seedBaseline and every
-- reader. Regression: seedBaseline once keyed staged by group.key while the
-- readers derived the key from the entry's locator fields. For a group whose key
-- was not literally the derived form the two never met, so isStagedDirty was
-- stuck true and commitStagedToBaseline silently updated nothing.
do
    eq(State.baselineStagedKey({ kind = "group", contextID = 5, path = "p", group = "g" }),
        State.groupKey(5, "p", "g"), "baselineStagedKey: group entries use groupKey")
    eq(State.baselineStagedKey({ kind = "single", componentID = 42 }),
        State.singleKey(42), "baselineStagedKey: single entries use singleKey")

    -- A group whose .key disagrees with its locator fields must still round trip.
    local odd = State.newSession(1, "g")
    local oddGroup = { key = "an-opaque-key", kind = "group", componentID = 7,
        contextID = 5, path = "p", group = "g", mode = "attack", armed = true,
        operationalCount = 1, totalCount = 1 }
    State.seedBaseline(odd, { oddGroup })
    assert(not State.isStagedDirty(odd),
        "a freshly seeded session must be clean whatever the group's key looks like")
    State.stageMode(odd, State.baselineStagedKey(odd.committedBaseline[1]), "defend", true)
    assert(State.isStagedDirty(odd), "staging a change must mark the session dirty")
    State.commitStagedToBaseline(odd)
    eq(odd.committedBaseline[1].mode, "defend", "commit must reach the baseline entry")
    assert(not State.isStagedDirty(odd), "commit must clear the dirty flag")
end

-- stageMode and stageArmed: edit staged without touching ship
do
    local ss = State.newSession(1, "g")
    ss.staged = { ["key1"] = { mode = "attack", armed = true } }
    State.stageMode(ss, "key1", "defend")
    eq(ss.staged["key1"].mode, "defend", "stageMode: updates existing entry mode")
    eq(ss.staged["key1"].armed, true, "stageMode: armed unchanged")
    State.stageArmed(ss, "key1", false)
    eq(ss.staged["key1"].armed, false, "stageArmed: updates existing entry armed")
    eq(ss.staged["key1"].mode, "defend", "stageArmed: mode unchanged")
    -- stageMode on a missing key takes armed from the caller's live-group value.
    -- A group can appear after seedBaseline (refresh() discovers it, or a legacy
    -- payload rebuilt staged empty); defaulting armed to false there would disarm
    -- a group the player never touched as soon as the change is committed.
    State.stageMode(ss, "newkey", "patrol", true)
    eq(ss.staged["newkey"].mode, "patrol", "stageMode: new key created")
    eq(ss.staged["newkey"].armed, true, "stageMode: new key armed comes from the live group, not false")
    State.stageMode(ss, "unarmedkey", "patrol", false)
    eq(ss.staged["unarmedkey"].armed, false, "stageMode: a genuinely unarmed live group stays unarmed")
    -- stageArmed on a missing key takes mode from the caller's live-group value.
    -- "" is not a valid weapon mode, so it must never be manufactured here.
    State.stageArmed(ss, "anotherkey", true, "attack")
    eq(ss.staged["anotherkey"].armed, true, "stageArmed: new key created")
    eq(ss.staged["anotherkey"].mode, "attack", "stageArmed: new key mode comes from the live group, not \"\"")
    -- nil session/staged: no error
    State.stageMode(nil, "k", "m", false)
    State.stageArmed(nil, "k", true, "attack")
    local noStaged = State.newSession(1, "g"); noStaged.staged = nil
    State.stageMode(noStaged, "k", "m", false)
    State.stageArmed(noStaged, "k", true, "attack")
end

-- Regression: staging a mode on a group that seedBaseline never saw must not
-- clobber its armed state. This is the live hazard -- a turret group discovered
-- by a later refresh() has no staged entry, and committing a mode change for it
-- used to silently disarm it.
do
    local late = State.newSession(1, "g")
    local seeded = { key = "group:C:p:seeded", kind = "group", componentID = 1,
        contextID = "C", path = "p", group = "seeded", mode = "attack", armed = true,
        operationalCount = 1, totalCount = 1 }
    State.seedBaseline(late, { seeded })
    -- A second group turns up after the seed: live, armed, and absent from staged.
    local discovered = { key = "group:C:p:discovered", kind = "group", componentID = 2,
        contextID = "C", path = "p", group = "discovered", mode = "attack", armed = true,
        operationalCount = 1, totalCount = 1 }
    assert(late.staged[discovered.key] == nil, "regression setup: discovered group is absent from staged")
    -- The console passes the live group's armed flag through, as menu.display does.
    State.stageMode(late, discovered.key, "defend", discovered.armed)
    eq(late.staged[discovered.key].mode, "defend", "late group: staged mode is the requested one")
    eq(late.staged[discovered.key].armed, true,
        "late group: armed is preserved from the live group, not clobbered to false")
    -- And the same in the other direction: arming a late group keeps its real mode.
    local discovered2 = { key = "group:C:p:discovered2", mode = "attack", armed = false }
    State.stageArmed(late, discovered2.key, true, discovered2.mode)
    eq(late.staged[discovered2.key].mode, "attack",
        "late group: mode is preserved from the live group, not replaced by \"\"")
end

-- isStagedDirty: true when staged differs from committedBaseline
do
    local grp = { key = "group:C:p:g", kind = "group", componentID = 5,
        contextID = "C", path = "p", group = "g", mode = "attack", armed = true,
        operationalCount = 1, totalCount = 1 }
    local sd = State.newSession(1, "g")
    State.seedBaseline(sd, { grp })
    assert(not State.isStagedDirty(sd), "isStagedDirty: clean after seeding")
    State.stageMode(sd, State.groupKey("C", "p", "g"), "defend")
    assert(State.isStagedDirty(sd), "isStagedDirty: dirty after stageMode change")
    -- revert staged to match baseline
    State.stageMode(sd, State.groupKey("C", "p", "g"), "attack")
    assert(not State.isStagedDirty(sd), "isStagedDirty: clean after reverting staged")
    -- stageArmed change
    State.stageArmed(sd, State.groupKey("C", "p", "g"), false)
    assert(State.isStagedDirty(sd), "isStagedDirty: dirty after stageArmed change")
    -- nil session: false
    assert(not State.isStagedDirty(nil), "isStagedDirty: nil session is not dirty")
    -- no staged: false
    local noStaged = State.newSession(1, "g"); noStaged.staged = nil
    assert(not State.isStagedDirty(noStaged), "isStagedDirty: nil staged is not dirty")
    -- single-kind baseline entry
    local grpS = { key = "single:9", kind = "single", componentID = 9,
        mode = "defend", armed = false, operationalCount = 1, totalCount = 1 }
    local sdS = State.newSession(1, "g")
    State.seedBaseline(sdS, { grpS })
    assert(not State.isStagedDirty(sdS), "isStagedDirty: single-kind clean after seeding")
    State.stageArmed(sdS, State.singleKey(9), true)
    assert(State.isStagedDirty(sdS), "isStagedDirty: single-kind dirty after change")
end

-- commitStagedToBaseline: advances committedBaseline to match staged
do
    local grp = { key = "group:C:p:g", kind = "group", componentID = 5,
        contextID = "C", path = "p", group = "g", mode = "attack", armed = true,
        operationalCount = 1, totalCount = 1 }
    local sc = State.newSession(1, "g")
    State.seedBaseline(sc, { grp })
    State.stageMode(sc, State.groupKey("C", "p", "g"), "defend")
    State.stageArmed(sc, State.groupKey("C", "p", "g"), false)
    assert(State.isStagedDirty(sc), "commitStagedToBaseline precondition: is dirty")
    State.commitStagedToBaseline(sc)
    assert(not State.isStagedDirty(sc), "commitStagedToBaseline: no longer dirty after commit")
    eq(sc.committedBaseline[1].mode, "defend", "commitStagedToBaseline: baseline mode updated")
    eq(sc.committedBaseline[1].armed, false, "commitStagedToBaseline: baseline armed updated")
    -- single-kind entry: covers the singleKey branch
    local grpS2 = { key = "single:77", kind = "single", componentID = 77,
        mode = "attack", armed = true, operationalCount = 1, totalCount = 1 }
    local scS = State.newSession(1, "g")
    State.seedBaseline(scS, { grpS2 })
    State.stageMode(scS, State.singleKey(77), "defend")
    State.commitStagedToBaseline(scS)
    eq(scS.committedBaseline[1].mode, "defend", "commitStagedToBaseline: single-kind mode updated")
    -- nil session: no error
    State.commitStagedToBaseline(nil)
    local noStaged = State.newSession(1, "g"); noStaged.staged = nil
    State.commitStagedToBaseline(noStaged)
end

-- restoreState with t="baseline" records (new format): staged is rebuilt from baseline
do
    local bsSession = State.newSession("111", "gunnercontrol")
    bsSession.shipName = "Colossus"
    bsSession.phase = "console"
    bsSession.committedBaseline = {
        { kind = "group", shipID = "111", contextID = "CTX", path = "p", group = "g",
          mode = "defend", armed = false },
    }
    local bsLive = { { key = "group:NEWCTX:p:g", contextID = "NEWCTX", path = "p", group = "g" } }
    local bsBack = State.newSession("111", "gunnercontrol")
    bsBack.shipName = "Colossus"
    local bsOk = State.restoreState(bsBack,
        State.decode(State.encode(State.saveState(bsSession))), bsLive)
    assert(bsOk, "baseline round-trip: restore succeeds")
    eq(#bsBack.committedBaseline, 1, "baseline round-trip: one entry restored")
    eq(bsBack.committedBaseline[1].mode, "defend", "baseline round-trip: mode preserved")
    -- staged is rebuilt from restored baseline
    local bsKey = State.groupKey("NEWCTX", "p", "g")
    assert(bsBack.staged[bsKey] ~= nil, "baseline round-trip: staged rebuilt from baseline")
    eq(bsBack.staged[bsKey].mode, "defend", "baseline round-trip: staged mode from baseline")
    eq(bsBack.staged[bsKey].armed, false, "baseline round-trip: staged armed from baseline")
end

-- legacy t="snapshot" fallback: when no baseline records present, snapshots populate committedBaseline
do
    local lf = State.newSession("222", "gunnercontrol")
    lf.shipName = "Nemesis"
    -- simulate a legacy payload with only snapshot records (no baseline records)
    local legacyRecords = {
        { t = "session", phase = "engaged", controlMode = "direct",
          povAnchor = "turret", povMode = "manual",
          autoNextTarget = "1",
          shipID = "222", shipName = "Nemesis", aimTargetID = "", cameraMemberID = "" },
        { t = "snapshot", kind = "group", shipID = "222", contextID = "CTX",
          path = "p", group = "g", mode = "attack", armed = "1" },
    }
    local lfLive = { { key = "group:CTX2:p:g", contextID = "CTX2", path = "p", group = "g" } }
    local lfBack = State.newSession("222", "gunnercontrol")
    lfBack.shipName = "Nemesis"
    assert(State.restoreState(lfBack, legacyRecords, lfLive), "legacy snapshot fallback: restore ok")
    eq(#lfBack.committedBaseline, 1, "legacy snapshot fallback: snapshot promoted to committedBaseline")
    eq(lfBack.committedBaseline[1].mode, "attack", "legacy snapshot fallback: mode preserved")
    eq(lfBack.committedBaseline[1].armed, true, "legacy snapshot fallback: armed preserved")

    -- legacy single-kind snapshot with idsHeld (same shipID): must be promoted
    local lfSingleRecords = {
        { t = "session", phase = "engaged", controlMode = "direct",
          povAnchor = "turret", povMode = "manual",
          autoNextTarget = "1",
          shipID = "333", shipName = "Minotaur", aimTargetID = "", cameraMemberID = "" },
        { t = "snapshot", kind = "single", shipID = "333", componentID = "77",
          mode = "defend", armed = "0" },
    }
    local lfSingle = State.newSession("333", "gunnercontrol")
    lfSingle.shipName = "Minotaur"
    assert(State.restoreState(lfSingle, lfSingleRecords, {}), "legacy single snapshot idsHeld: restore ok")
    eq(#lfSingle.committedBaseline, 1, "legacy single snapshot idsHeld: promoted to committedBaseline")
    eq(lfSingle.committedBaseline[1].componentID, "77", "legacy single snapshot idsHeld: componentID preserved")
    eq(lfSingle.committedBaseline[1].armed, false, "legacy single snapshot idsHeld: armed=0 parsed as false")
end

-- Step 4: checkbox bound to TICK_MODE via stageMode and toggleGroup.
-- Covers the two stageMode checkbox-sync branches (lines 497-498, 500-506).

-- stageMode → tick: setting mode to TICK_MODE auto-ticks the group and records
-- preTickMode so an untick can restore the original mode.
do
    local sm = State.newSession(1, "g")
    sm.staged = { k = { mode = "defend", armed = true } }
    -- Setting to TICK_MODE on a non-TICK_MODE entry: ticks the group.
    State.stageMode(sm, "k", State.TICK_MODE, true)
    assert(sm.checkedGroupKeys["k"] == true, "stageMode→tick: checkedGroupKeys set")
    eq(sm.staged["k"].mode, State.TICK_MODE, "stageMode→tick: mode is TICK_MODE")
    eq(sm.staged["k"].preTickMode, "defend", "stageMode→tick: preTickMode records displaced mode")
    -- Setting to TICK_MODE again (already ticked): idempotent, preTickMode unchanged.
    State.stageMode(sm, "k", State.TICK_MODE, true)
    eq(sm.staged["k"].preTickMode, "defend", "stageMode→tick twice: preTickMode not overwritten")
end

-- stageMode → untick: setting mode away from TICK_MODE auto-unticks the group
-- and clears preTickMode, leaving the entry in the caller's chosen mode.
do
    local su = State.newSession(1, "g")
    su.staged = { k = { mode = State.TICK_MODE, armed = false } }
    su.checkedGroupKeys["k"] = true
    -- Setting away from TICK_MODE: unticks the group.
    State.stageMode(su, "k", "defend", false)
    assert(su.checkedGroupKeys["k"] == nil, "stageMode→untick: checkedGroupKeys cleared")
    eq(su.staged["k"].mode, "defend", "stageMode→untick: mode is the caller's choice")
    assert(su.staged["k"].preTickMode == nil, "stageMode→untick: preTickMode cleared")
    -- Confirm stageMode→untick on a group with a preTickMode in place: the
    -- caller's value wins, not preTickMode.
    su.staged["k2"] = { mode = State.TICK_MODE, armed = true, preTickMode = "missiledefence" }
    su.checkedGroupKeys["k2"] = true
    State.stageMode(su, "k2", "attack", true)
    eq(su.staged["k2"].mode, "attack", "stageMode→untick with preTickMode: caller's mode wins")
    assert(su.staged["k2"].preTickMode == nil, "stageMode→untick with preTickMode: preTickMode cleared")
end

-- toggleGroup tick: auto-sets staged mode to TICK_MODE, records preTickMode.
-- toggleGroup untick: restores preTickMode (or UNTICK_FALLBACK when none set).
do
    local tg = State.newSession(1, "g")
    tg.staged = { k = { mode = "defend", armed = true } }
    -- Tick.
    local ticked = State.toggleGroup(tg, "k", true)
    assert(ticked == true, "toggleGroup: first toggle returns true")
    assert(tg.checkedGroupKeys["k"] == true, "toggleGroup tick: key present")
    eq(tg.staged["k"].mode, State.TICK_MODE, "toggleGroup tick: mode set to TICK_MODE")
    eq(tg.staged["k"].preTickMode, "defend", "toggleGroup tick: preTickMode recorded")
    -- Untick (restores preTickMode).
    local unticked = State.toggleGroup(tg, "k", true)
    assert(unticked == false, "toggleGroup: second toggle returns false")
    assert(tg.checkedGroupKeys["k"] == nil, "toggleGroup untick: key cleared")
    eq(tg.staged["k"].mode, "defend", "toggleGroup untick: preTickMode restored")
    assert(tg.staged["k"].preTickMode == nil, "toggleGroup untick: preTickMode cleared")
    -- Untick from ticked-at-sit-down (no preTickMode): falls back to UNTICK_FALLBACK.
    tg.staged["k2"] = { mode = State.TICK_MODE, armed = true }  -- no preTickMode
    tg.checkedGroupKeys["k2"] = true
    State.toggleGroup(tg, "k2", true)
    eq(tg.staged["k2"].mode, State.UNTICK_FALLBACK,
        "toggleGroup untick without preTickMode: falls back to UNTICK_FALLBACK")
end

-- toggleAllGroups applies tick/untick side-effects to every group.
do
    local ta = State.newSession(1, "g")
    ta.groups = {
        { key = "m1", operationalCount = 1, totalCount = 1, armed = false },
        { key = "m2", operationalCount = 1, totalCount = 1, armed = true },
    }
    ta.staged = {
        m1 = { mode = "defend",  armed = false },
        m2 = { mode = "attack",  armed = true  },
    }
    -- Check all: both groups tick to TICK_MODE.
    State.toggleAllGroups(ta)
    eq(ta.staged["m1"].mode, State.TICK_MODE, "toggleAllGroups tick: m1 mode set")
    eq(ta.staged["m2"].mode, State.TICK_MODE, "toggleAllGroups tick: m2 mode set")
    eq(ta.staged["m1"].preTickMode, "defend",  "toggleAllGroups tick: m1 preTickMode saved")
    eq(ta.staged["m2"].preTickMode, "attack",  "toggleAllGroups tick: m2 preTickMode saved")
    -- Uncheck all: both groups untick restoring preTickMode.
    State.toggleAllGroups(ta)
    eq(ta.staged["m1"].mode, "defend",  "toggleAllGroups untick: m1 mode restored")
    eq(ta.staged["m2"].mode, "attack",  "toggleAllGroups untick: m2 mode restored")
    assert(ta.staged["m1"].preTickMode == nil, "toggleAllGroups untick: m1 preTickMode cleared")
    assert(ta.staged["m2"].preTickMode == nil, "toggleAllGroups untick: m2 preTickMode cleared")
    -- Partial select → fill up: only the previously-unchecked group ticks.
    ta.staged = { m1 = { mode = "defend", armed = false }, m2 = { mode = "attack", armed = true } }
    State.toggleGroup(ta, "m1", false)  -- check only m1
    State.toggleAllGroups(ta)  -- fills in m2
    assert(ta.checkedGroupKeys["m2"] == true, "toggleAllGroups partial→fill: m2 now checked")
    eq(ta.staged["m2"].mode, State.TICK_MODE, "toggleAllGroups partial→fill: m2 ticked to TICK_MODE")
    eq(ta.staged["m1"].preTickMode, "defend", "toggleAllGroups partial→fill: m1 preTickMode unchanged")
end

-- directedMode is a removed field: Direct-control now always uses attackenemies
-- (live-verified 2026-08-10), so nothing writes or reads it. A save taken by an
-- older build still carries the key, and validSessionRecord only checks known
-- keys rather than rejecting unknown ones, so such a payload must still restore.
-- Asserted rather than assumed: silently refusing an old save would strand a
-- player mid-engagement with no session to come back to.
do
    local live = {}
    local legacyRec = {
        { t = "session", phase = "engaged", controlMode = "direct",
          povAnchor = "turret", povMode = "manual",
          autoNextTarget = "1",
          shipID = "100", shipName = "Colossus", aimTargetID = "", cameraMemberID = "",
          directedMode = "autoassist" },
    }
    local restored = State.newSession("100", "gunnercontrol")
    restored.shipName = "Colossus"
    assert(State.restoreState(restored, legacyRec, live),
        "legacy payload carrying directedMode: restore accepted")
    assert(restored.directedMode == nil,
        "legacy directedMode must be ignored, not carried onto the live session")
    -- The field is no longer emitted at all.
    local dm = State.newSession("100", "gunnercontrol")
    dm.shipName = "Colossus"
    dm.phase, dm.controlMode = "engaged", "direct"
    assert(State.saveState(dm)[1].directedMode == nil,
        "saveState must not emit directedMode")
end

-- Direct-control policy: State.isDirectedMode.
assert(State.isDirectedMode("attackenemies"), "isDirectedMode: attackenemies is direct")
assert(State.isDirectedMode("autoassist"),   "isDirectedMode: autoassist is direct")
assert(not State.isDirectedMode("defend"),   "isDirectedMode: defend is ordinary")
assert(not State.isDirectedMode("attack"),   "isDirectedMode: attack is ordinary")
assert(not State.isDirectedMode(nil),        "isDirectedMode: nil is not direct")

-- Fresh session defaults directMode to "attackenemies".
do
    local s = State.newSession(1, "g")
    eq(s.directMode, "attackenemies", "newSession: default directMode is attackenemies")
end

-- seedBaseline: groups in either Direct-control mode come up checked and are
-- staged in the session's current (default) policy, not their original mode.
do
    local sb = State.newSession(77, "g")
    local atkGrp = { key = "group:C1:p:atk", kind = "group", componentID = 10,
        contextID = "C1", path = "p", group = "atk",
        mode = State.TICK_MODE, armed = true, operationalCount = 1, totalCount = 1 }
    local autoGrp = { key = "group:C1:p:auto", kind = "group", componentID = 11,
        contextID = "C1", path = "p", group = "auto",
        mode = "autoassist", armed = true, operationalCount = 1, totalCount = 1 }
    local ordGrp = { key = "group:C1:p:ord", kind = "group", componentID = 12,
        contextID = "C1", path = "p", group = "ord",
        mode = "defend", armed = false, operationalCount = 1, totalCount = 1 }
    State.seedBaseline(sb, { atkGrp, autoGrp, ordGrp })
    local atkKey   = State.groupKey("C1", "p", "atk")
    local autoKey  = State.groupKey("C1", "p", "auto")
    local ordKey   = State.groupKey("C1", "p", "ord")
    assert(sb.checkedGroupKeys[atkKey] == true,  "seedBaseline: attackenemies group is checked")
    assert(sb.checkedGroupKeys[autoKey] == true, "seedBaseline: autoassist group is checked")
    assert(sb.checkedGroupKeys[ordKey] == nil,   "seedBaseline: ordinary group is unchecked")
    -- Both direct groups are staged in the default policy (attackenemies).
    eq(sb.staged[atkKey].mode, State.TICK_MODE,  "seedBaseline: attackenemies staged in policy")
    eq(sb.staged[autoKey].mode, State.TICK_MODE, "seedBaseline: autoassist normalized to policy")
    eq(sb.staged[ordKey].mode, "defend",         "seedBaseline: ordinary stays ordinary")
    -- No preTickMode on seeded direct groups.
    assert(sb.staged[atkKey].preTickMode == nil,  "seedBaseline: no preTickMode for attackenemies seed")
    assert(sb.staged[autoKey].preTickMode == nil, "seedBaseline: no preTickMode for autoassist seed")
end

-- Ordinary tick/untick restoration.
do
    local s = State.newSession(1, "g")
    s.staged = { k = { mode = "defend", armed = true } }
    State.toggleGroup(s, "k", true)
    assert(s.checkedGroupKeys["k"] == true, "ordinary tick: checks the group")
    eq(s.staged["k"].mode, State.TICK_MODE, "ordinary tick: stages current policy")
    eq(s.staged["k"].preTickMode, "defend", "ordinary tick: records displaced ordinary mode")
    State.toggleGroup(s, "k", true)
    assert(s.checkedGroupKeys["k"] == nil,  "ordinary untick: clears the checkbox")
    eq(s.staged["k"].mode, "defend",       "ordinary untick: restores original mode")
    assert(s.staged["k"].preTickMode == nil, "ordinary untick: clears preTickMode")
end

-- Direct-mode-origin tick/untick falls back to defend.
do
    local s = State.newSession(1, "g")
    -- Group already in attackenemies (the default policy) but unchecked.
    -- applyTick should NOT record the directed mode as preTickMode.
    s.staged = { k = { mode = State.TICK_MODE, armed = true } }
    assert(s.checkedGroupKeys["k"] == nil, "setup: group is unchecked")
    State.toggleGroup(s, "k", true)  -- tick
    assert(s.checkedGroupKeys["k"] == true, "direct tick: group is checked")
    assert(s.staged["k"].preTickMode ~= State.TICK_MODE,
        "direct tick: preTickMode is not the directed mode")
    assert(s.staged["k"].preTickMode == nil,
        "direct tick: preTickMode is nil so untick falls back")
    State.toggleGroup(s, "k", true)  -- untick
    eq(s.staged["k"].mode, State.UNTICK_FALLBACK,
        "direct tick then untick: falls back to defend")
end

-- Policy change: attackenemies -> autoassist -> attackenemies while checked.
do
    local s = State.newSession(1, "g")
    s.staged = { k1 = { mode = "defend", armed = true } }
    assert(s.checkedGroupKeys["k1"] == nil, "policy setup: group is unchecked")
    State.toggleGroup(s, "k1", true)  -- tick into attackenemies
    eq(s.staged["k1"].mode, State.TICK_MODE, "policy: initial tick uses attackenemies")
    eq(s.directMode, "attackenemies", "policy: default is attackenemies")
    -- Switch to autoassist.
    local ok = State.setDirectMode(s, "autoassist")
    assert(ok, "policy: autoassist accepted")
    eq(s.directMode, "autoassist",   "policy: directMode changed")
    eq(s.staged["k1"].mode, "autoassist", "policy: checked group re-staged to new mode")
    -- Switch back to attackenemies.
    ok = State.setDirectMode(s, "attackenemies")
    assert(ok, "policy: attackenemies accepted")
    eq(s.directMode, "attackenemies", "policy: directMode changed back")
    eq(s.staged["k1"].mode, State.TICK_MODE, "policy: checked group re-staged back")
end

-- Policy change preserves ordinary preTickMode on checked groups.
do
    local s = State.newSession(1, "g")
    s.staged = { k = { mode = "defend", armed = true, preTickMode = "attack" } }
    s.checkedGroupKeys["k"] = true
    State.setDirectMode(s, "autoassist")
    assert(s.staged["k"].preTickMode == "attack",
        "policy change: preserves existing preTickMode on checked group")
end

-- toggleAllGroups obeys current policy and preserves valid preTickMode.
do
    local s = State.newSession(1, "g")
    s.groups = {
        { key = "m1", operationalCount = 1, totalCount = 1, armed = false },
        { key = "m2", operationalCount = 1, totalCount = 1, armed = true },
    }
    s.staged = {
        m1 = { mode = "defend", armed = false },
        m2 = { mode = "attack", armed = true, preTickMode = "patrol" },
    }
    -- Select all: newly-ticked group uses current policy; already-checked keeps preTickMode.
    State.toggleGroup(s, "m2", true)  -- check m2 first
    eq(State.toggleAllGroups(s), true, "toggleAll: partial -> select all")
    eq(s.staged["m1"].mode, State.TICK_MODE, "toggleAll: new tick uses current policy")
    eq(s.staged["m2"].preTickMode, "patrol", "toggleAll: existing preTickMode preserved")
    -- Deselect all.
    eq(State.toggleAllGroups(s), false, "toggleAll: select all -> deselect all")
    assert(next(s.checkedGroupKeys) == nil, "toggleAll: all unchecked")
end

-- Explicit ordinary stageMode removes membership.
do
    local s = State.newSession(1, "g")
    s.staged = { k = { mode = State.TICK_MODE, armed = true } }
    s.checkedGroupKeys["k"] = true
    State.stageMode(s, "k", "defend", true)
    assert(s.checkedGroupKeys["k"] == nil, "stageMode ordinary: unchecked on ordinary mode")
    eq(s.staged["k"].mode, "defend",      "stageMode ordinary: stages explicit mode")
    assert(s.staged["k"].preTickMode == nil, "stageMode ordinary: clears preTickMode")
end

-- Choosing the OTHER Direct-control engine mode via stageMode is a no-op for
-- membership and staged mode.
do
    local s = State.newSession(1, "g")
    s.directMode = "attackenemies"
    s.staged = { k = { mode = State.TICK_MODE, armed = true } }
    s.checkedGroupKeys["k"] = true
    -- Try to switch to autoassist via stageMode.
    State.stageMode(s, "k", "autoassist", true)
    assert(s.checkedGroupKeys["k"] == true,  "other-direct stageMode: membership unchanged")
    eq(s.staged["k"].mode, State.TICK_MODE, "other-direct stageMode: staged mode unchanged")
    -- Unchecked group in ordinary mode: other-direct is also a no-op.
    s.checkedGroupKeys = {}
    s.staged = { k2 = { mode = "defend", armed = false } }
    State.stageMode(s, "k2", "autoassist", false)
    assert(s.checkedGroupKeys["k2"] == nil,  "other-direct stageMode unchecked: no check")
    eq(s.staged["k2"].mode, "defend",       "other-direct stageMode unchecked: mode unchanged")
end

-- checkpoint then untick -> defend (preTickMode cleared by commit).
do
    local s = State.newSession(1, "g")
    s.groups = { { key = "g1", operationalCount = 1, totalCount = 1 } }
    s.staged = { g1 = { mode = "defend", armed = true, preTickMode = "attack" } }
    s.checkedGroupKeys["g1"] = true
    State.commitStagedToBaseline(s)
    assert(s.staged["g1"].preTickMode == nil,
        "checkpoint: clears preTickMode on checked group")
    State.toggleGroup(s, "g1", true)
    eq(s.staged["g1"].mode, State.UNTICK_FALLBACK,
        "checkpoint then untick: falls back to defend")
end

-- save/load before checkpoint preserves a valid ordinary preTickMode.
do
    local saved = State.newSession("400", "gunnercontrol")
    saved.shipName = "Titan"
    saved.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    saved.checkedGroupKeys["group:OLD:p:g"] = true
    saved.staged = { ["group:OLD:p:g"] = { mode = State.TICK_MODE, armed = true, preTickMode = "attack" } }
    saved.committedBaseline = {
        { kind = "group", shipID = "400", contextID = "OLD", path = "p", group = "g",
          mode = "defend", armed = true },
    }
    local payload = State.encode(State.saveState(saved))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("400", "gunnercontrol")
    loaded.shipName = "Titan"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "save/load before checkpoint: restore succeeds")
    eq(loaded.directMode, "attackenemies", "save/load before cp: default policy restored")
    local loadKey = "group:NEW:p:g"
    assert(loaded.checkedGroupKeys[loadKey] == true,
        "save/load before checkpoint: checked group remains checked")
    eq(loaded.staged[loadKey].mode, State.TICK_MODE,
        "save/load before checkpoint: staged in policy mode")
    eq(loaded.staged[loadKey].preTickMode, "attack",
        "save/load before checkpoint: persisted ordinary preTickMode survives")
end

-- save/load after checkpoint does not restore old preTickMode.
do
    local saved = State.newSession("401", "gunnercontrol")
    saved.shipName = "Titan"
    saved.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = State.TICK_MODE, armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    saved.checkedGroupKeys["group:OLD:p:g"] = true
    saved.staged = { ["group:OLD:p:g"] = { mode = State.TICK_MODE, armed = true } }
    saved.committedBaseline = {
        { kind = "group", shipID = "401", contextID = "OLD", path = "p", group = "g",
          mode = State.TICK_MODE, armed = true },
    }
    local payload = State.encode(State.saveState(saved))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("401", "gunnercontrol")
    loaded.shipName = "Titan"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "save/load after checkpoint: restore succeeds")
    local loadKey = "group:NEW:p:g"
    assert(loaded.checkedGroupKeys[loadKey] == true,
        "save/load after checkpoint: checked group remains checked")
    eq(loaded.staged[loadKey].mode, State.TICK_MODE,
        "save/load after checkpoint: staged in policy mode")
    assert(loaded.staged[loadKey].preTickMode == nil,
        "save/load after checkpoint: preTickMode NOT restored (baseline was directed)")
end

-- active save/load restores autoassist policy.
do
    local saved = State.newSession("402", "gunnercontrol")
    saved.shipName = "Titan"
    saved.directMode = "autoassist"
    saved.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    saved.checkedGroupKeys["group:OLD:p:g"] = true
    saved.staged = { ["group:OLD:p:g"] = { mode = "autoassist", armed = true, preTickMode = "attack" } }
    saved.committedBaseline = {
        { kind = "group", shipID = "402", contextID = "OLD", path = "p", group = "g",
          mode = "defend", armed = true },
    }
    local payload = State.encode(State.saveState(saved))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("402", "gunnercontrol")
    loaded.shipName = "Titan"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "active save/load autoassist: restore succeeds")
    eq(loaded.directMode, "autoassist",
        "active save/load: autoassist policy restored")
    local loadKey = "group:NEW:p:g"
    eq(loaded.staged[loadKey].mode, "autoassist",
        "active save/load: checked group staged in restored policy")
    eq(loaded.staged[loadKey].preTickMode, "attack",
        "active save/load: persisted ordinary preTickMode survives autoassist policy")
end

-- legacy payload without directMode defaults to attackenemies.
do
    local legacyRecords = {
        { t = "session", phase = "engaged", controlMode = "direct",
          povAnchor = "turret", povMode = "manual",
          autoNextTarget = "1",
          shipID = "403", shipName = "Titan", aimTargetID = "", cameraMemberID = "" },
        { t = "baseline", kind = "group", shipID = "403", contextID = "OLD",
          path = "p", group = "g", mode = "defend", armed = "1" },
        { t = "checked", path = "p", group = "g" },
    }
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("403", "gunnercontrol")
    loaded.shipName = "Titan"
    assert(State.restoreState(loaded, legacyRecords, liveGroups),
        "legacy payload without policy: restore succeeds")
    eq(loaded.directMode, "attackenemies",
        "legacy payload: defaults to attackenemies")
end

-- setDirectMode rejects invalid values.
do
    local s = State.newSession(1, "g")
    assert(not State.setDirectMode(s, "defend"),   "setDirectMode: reject ordinary mode")
    assert(not State.setDirectMode(s, "attack"),  "setDirectMode: reject unknown mode")
    assert(not State.setDirectMode(s, ""),         "setDirectMode: reject empty string")
    assert(not State.setDirectMode(s, nil),        "setDirectMode: reject nil")
    eq(s.directMode, "attackenemies", "setDirectMode: policy unchanged on rejection")
end

-- setDirectMode is a no-op when the mode is already active.
do
    local s = State.newSession(1, "g")
    assert(not State.setDirectMode(s, "attackenemies"),
        "setDirectMode: no-op when already attackenemies")
end

-- Exact preTick round trip via normal stageMode/toggleGroup path.
-- baseline=defend, player stages ordinary mode=attack, then ticks the group,
-- then save/load must preserve that exact preTickMode so untick restores it.
do
    local rt = State.newSession("500", "gunnercontrol")
    rt.shipName = "Titan"
    rt.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    State.seedBaseline(rt, rt.groups)
    eq(rt.staged["group:OLD:p:g"].mode, "defend", "round-trip setup: baseline seeded")
    -- Stage an ordinary mode via the normal dropdown path; group stays unchecked.
    State.stageMode(rt, "group:OLD:p:g", "attack", true)
    eq(rt.staged["group:OLD:p:g"].mode, "attack", "round-trip setup: ordinary mode staged")
    assert(rt.checkedGroupKeys["group:OLD:p:g"] == nil,
        "round-trip setup: group is still unchecked after staging ordinary mode")
    -- Tick the group: applyTick records the current staged mode as preTickMode.
    State.toggleGroup(rt, "group:OLD:p:g", true)
    eq(rt.staged["group:OLD:p:g"].mode, State.TICK_MODE,
        "round-trip setup: ticked into policy mode")
    eq(rt.staged["group:OLD:p:g"].preTickMode, "attack",
        "round-trip setup: preTickMode records the displaced ordinary mode")
    assert(rt.checkedGroupKeys["group:OLD:p:g"] == true,
        "round-trip setup: group is now checked")
    -- Save and load.
    local payload = State.encode(State.saveState(rt))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("500", "gunnercontrol")
    loaded.shipName = "Titan"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "round-trip: restore succeeds")
    local loadKey = "group:NEW:p:g"
    assert(loaded.checkedGroupKeys[loadKey] == true,
        "round-trip: checked group remains checked after save/load")
    eq(loaded.staged[loadKey].mode, State.TICK_MODE,
        "round-trip: staged in policy mode after restore")
    eq(loaded.staged[loadKey].preTickMode, "attack",
        "round-trip: persisted preTickMode survives save/load")
    -- Untick restores the exact saved ordinary mode.
    State.toggleGroup(loaded, loadKey, true)
    eq(loaded.staged[loadKey].mode, "attack",
        "round-trip: untick restores the exact persisted preTickMode")
    assert(loaded.checkedGroupKeys[loadKey] == nil,
        "round-trip: checkbox cleared after untick")
end

-- After checkpoint: commit clears preTickMode; subsequent save/load must not
-- resurrect it. Untick falls back to defend.
do
    local postCp = State.newSession("501", "gunnercontrol")
    postCp.shipName = "Titan"
    postCp.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    State.seedBaseline(postCp, postCp.groups)
    State.stageMode(postCp, "group:OLD:p:g", "attack", true)
    State.toggleGroup(postCp, "group:OLD:p:g", true)
    eq(postCp.staged["group:OLD:p:g"].preTickMode, "attack",
        "post-checkpoint setup: preTickMode set before commit")
    -- Commit (checkpoint): this clears preTickMode on checked groups.
    State.commitStagedToBaseline(postCp)
    assert(postCp.staged["group:OLD:p:g"].preTickMode == nil,
        "post-checkpoint setup: commit cleared preTickMode")
    -- Save and load after checkpoint.
    local payload = State.encode(State.saveState(postCp))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("501", "gunnercontrol")
    loaded.shipName = "Titan"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "post-checkpoint: restore succeeds")
    local loadKey = "group:NEW:p:g"
    assert(loaded.checkedGroupKeys[loadKey] == true,
        "post-checkpoint: checked group remains checked after save/load")
    eq(loaded.staged[loadKey].mode, State.TICK_MODE,
        "post-checkpoint: staged in policy mode")
    assert(loaded.staged[loadKey].preTickMode == nil,
        "post-checkpoint: preTickMode NOT resurrected after commit+save/load")
    -- Untick falls back to defend (no persisted preTickMode to restore).
    State.toggleGroup(loaded, loadKey, true)
    eq(loaded.staged[loadKey].mode, State.UNTICK_FALLBACK,
        "post-checkpoint: untick falls back to defend, old attack history is not restored")
end

-- Legacy payload without preTick records still restores safely using the
-- existing baseline-derived fallback behaviour.
do
    local legacyPt = { t = "session", phase = "engaged", controlMode = "direct",
        povAnchor = "turret", povMode = "manual", autoNextTarget = "1",
        shipID = "502", shipName = "Titan", aimTargetID = "", cameraMemberID = "" }
    local legacyRecords = {
        legacyPt,
        { t = "baseline", kind = "group", shipID = "502", contextID = "OLD",
          path = "p", group = "g", mode = "defend", armed = "1" },
        { t = "checked", path = "p", group = "g" },
    }
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("502", "gunnercontrol")
    loaded.shipName = "Titan"
    assert(State.restoreState(loaded, legacyRecords, liveGroups),
        "legacy without preTick: restore succeeds")
    local loadKey = "group:NEW:p:g"
    assert(loaded.checkedGroupKeys[loadKey] == true,
        "legacy without preTick: checked group remains checked")
    eq(loaded.staged[loadKey].mode, State.TICK_MODE,
        "legacy without preTick: staged in default policy mode")
    -- With no persisted preTickMode the safe fallback is UNTICK_FALLBACK;
    -- untick falls back to defend rather than resurrecting a stale mode.
    assert(loaded.staged[loadKey].preTickMode == nil,
        "legacy without preTick: no preTickMode; untick falls back to defend")
end

-- Issue #48 Task 4: Direct-control persistence, checkpoint, teardown,
-- and legacy compatibility. The cases above prove the transport pieces;
-- these round trips each prove one whole required behaviour end to end,
-- asserting every element that must survive together.

-- Active Direct save/load under attackenemies restores checked membership,
-- the policy, the committed baseline (not the temporary Direct state), and a
-- valid ordinary preTickMode; a later untick returns the ordinary mode.
do
    local saved = State.newSession("600", "gunnercontrol")
    saved.shipName = "Behemoth"
    saved.phase, saved.controlMode = "engaged", "direct"
    saved.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    State.seedBaseline(saved, saved.groups)
    State.stageMode(saved, "group:OLD:p:g", "attack", true)
    State.toggleGroup(saved, "group:OLD:p:g", true)
    eq(saved.staged["group:OLD:p:g"].preTickMode, "attack", "task4 active setup: ordinary preTickMode recorded")
    local payload = State.encode(State.saveState(saved))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("600", "gunnercontrol")
    loaded.shipName = "Behemoth"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "task4 active attackenemies: restore succeeds")
    local loadKey = "group:NEW:p:g"
    assert(loaded.checkedGroupKeys[loadKey] == true,
        "task4 active attackenemies: checked membership restored")
    eq(loaded.directMode, "attackenemies", "task4 active attackenemies: policy restored")
    eq(#loaded.committedBaseline, 1, "task4 active attackenemies: committed baseline restored")
    eq(loaded.committedBaseline[1].mode, "defend",
        "task4 active attackenemies: committed baseline keeps the pre-engage mode, not the temporary Direct state")
    eq(loaded.committedBaseline[1].armed, true, "task4 active attackenemies: committed baseline armed restored")
    eq(loaded.staged[loadKey].mode, State.TICK_MODE, "task4 active attackenemies: checked group staged in the policy")
    eq(loaded.staged[loadKey].preTickMode, "attack", "task4 active attackenemies: valid ordinary preTickMode restored")
    State.toggleGroup(loaded, loadKey, true)
    eq(loaded.staged[loadKey].mode, "attack",
        "task4 active attackenemies: untick after restore returns the ordinary mode")
    assert(loaded.checkedGroupKeys[loadKey] == nil, "task4 active attackenemies: untick clears membership")
end

-- The same active save/load round trip under the autoassist policy: the
-- restored session must stage the checked group in autoassist, keep the
-- committed baseline intact, and let a later untick restore the ordinary mode.
do
    local saved = State.newSession("601", "gunnercontrol")
    saved.shipName = "Behemoth"
    saved.directMode = "autoassist"
    saved.phase, saved.controlMode = "engaged", "direct"
    saved.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    State.seedBaseline(saved, saved.groups)
    State.stageMode(saved, "group:OLD:p:g", "attack", true)
    State.toggleGroup(saved, "group:OLD:p:g", true)
    eq(saved.staged["group:OLD:p:g"].mode, "autoassist", "task4 active autoassist setup: tick stages the policy")
    eq(saved.staged["group:OLD:p:g"].preTickMode, "attack", "task4 active autoassist setup: ordinary preTickMode recorded")
    local payload = State.encode(State.saveState(saved))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("601", "gunnercontrol")
    loaded.shipName = "Behemoth"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "task4 active autoassist: restore succeeds")
    local loadKey = "group:NEW:p:g"
    assert(loaded.checkedGroupKeys[loadKey] == true,
        "task4 active autoassist: checked membership restored")
    eq(loaded.directMode, "autoassist", "task4 active autoassist: policy restored")
    eq(#loaded.committedBaseline, 1, "task4 active autoassist: committed baseline restored")
    eq(loaded.committedBaseline[1].mode, "defend",
        "task4 active autoassist: committed baseline keeps the pre-engage mode, not the temporary Direct state")
    eq(loaded.committedBaseline[1].armed, true, "task4 active autoassist: committed baseline armed restored")
    eq(loaded.staged[loadKey].mode, "autoassist", "task4 active autoassist: checked group staged in the restored policy")
    eq(loaded.staged[loadKey].preTickMode, "attack", "task4 active autoassist: valid ordinary preTickMode restored")
    State.toggleGroup(loaded, loadKey, true)
    eq(loaded.staged[loadKey].mode, "attack",
        "task4 active autoassist: untick after restore returns the ordinary mode")
    assert(loaded.checkedGroupKeys[loadKey] == nil, "task4 active autoassist: untick clears membership")
end

-- "Update turret behavior" is one action with two observable effects that a
-- single scenario must prove together: committedBaseline advances to the
-- staged Direct state AND the checked group's preTickMode is cleared, so a
-- later untick uses the Defend fallback instead of resurrecting the displaced
-- ordinary mode.
do
    local s = State.newSession("602", "gunnercontrol")
    s.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    State.seedBaseline(s, s.groups)
    State.stageMode(s, "group:OLD:p:g", "attack", true)
    State.toggleGroup(s, "group:OLD:p:g", true)
    eq(s.staged["group:OLD:p:g"].preTickMode, "attack", "task4 checkpoint setup: preTickMode before the commit")
    State.commitStagedToBaseline(s)
    eq(s.committedBaseline[1].mode, State.TICK_MODE,
        "task4 checkpoint: committedBaseline advances to the staged Direct mode")
    eq(s.committedBaseline[1].armed, true, "task4 checkpoint: committedBaseline advances armed with the staged state")
    assert(s.staged["group:OLD:p:g"].preTickMode == nil, "task4 checkpoint: preTickMode cleared on the checked group")
    assert(not State.isStagedDirty(s), "task4 checkpoint: session is clean after the commit")
    State.toggleGroup(s, "group:OLD:p:g", true)
    eq(s.staged["group:OLD:p:g"].mode, State.UNTICK_FALLBACK,
        "task4 checkpoint: untick after the commit uses the Defend fallback")
end

-- A save/load taken after the checkpoint must not resurrect the cleared
-- preTickMode, and a later untick uses Defend -- under the autoassist policy
-- as well, so the fallback is proven policy-independent.
do
    local saved = State.newSession("603", "gunnercontrol")
    saved.shipName = "Behemoth"
    saved.directMode = "autoassist"
    saved.phase, saved.controlMode = "engaged", "direct"
    saved.groups = {
        { key = "group:OLD:p:g", contextID = "OLD", path = "p", group = "g",
          kind = "group", componentID = "C1", mode = "defend", armed = true,
          operationalCount = 1, totalCount = 1 },
    }
    State.seedBaseline(saved, saved.groups)
    State.stageMode(saved, "group:OLD:p:g", "attack", true)
    State.toggleGroup(saved, "group:OLD:p:g", true)
    State.commitStagedToBaseline(saved)
    assert(saved.staged["group:OLD:p:g"].preTickMode == nil,
        "task4 post-cp autoassist setup: the commit cleared preTickMode")
    local payload = State.encode(State.saveState(saved))
    local liveGroups = { { key = "group:NEW:p:g", contextID = "NEW", path = "p", group = "g" } }
    local loaded = State.newSession("603", "gunnercontrol")
    loaded.shipName = "Behemoth"
    assert(State.restoreState(loaded, State.decode(payload), liveGroups),
        "task4 post-cp autoassist: restore succeeds")
    local loadKey = "group:NEW:p:g"
    eq(loaded.directMode, "autoassist", "task4 post-cp autoassist: policy restored")
    assert(loaded.checkedGroupKeys[loadKey] == true, "task4 post-cp autoassist: checked membership restored")
    eq(loaded.committedBaseline[1].mode, "autoassist",
        "task4 post-cp autoassist: the committed Direct mode is now the baseline")
    assert(loaded.staged[loadKey].preTickMode == nil,
        "task4 post-cp autoassist: the checkpointed preTickMode is not resurrected")
    State.toggleGroup(loaded, loadKey, true)
    eq(loaded.staged[loadKey].mode, State.UNTICK_FALLBACK,
        "task4 post-cp autoassist: untick after the checkpoint uses Defend")
end

-- Resolver seam: tick/restaging uses the resolver rather than blindly copying
-- session.directMode. A focused test substitutes a pure resolver to return
-- different effective modes for two checked group keys and proves membership
-- remains unchanged while each staged mode follows its resolved result.
do
    local rs = State.newSession(1, "g")
    rs.staged = {
        k1 = { mode = "defend", armed = true },
        k2 = { mode = "attack",  armed = false },
    }
    -- Save the original resolver.
    local origResolveDirectMode = State.resolveDirectMode
    -- Substitute a resolver that returns different effective modes per key.
    function State.resolveDirectMode(_, groupKey)
        if groupKey == "k1" then return "autoassist"
        elseif groupKey == "k2" then return "attackenemies"
        else return State.TICK_MODE end
    end
    -- Tick both groups via toggleGroup: applyTick must call the resolver.
    State.toggleGroup(rs, "k1", true)
    State.toggleGroup(rs, "k2", true)
    assert(rs.checkedGroupKeys["k1"] == true,  "resolver: k1 checked")
    assert(rs.checkedGroupKeys["k2"] == true,  "resolver: k2 checked")
    eq(rs.staged["k1"].mode, "autoassist", "resolver: k1 staged in its resolved mode")
    eq(rs.staged["k2"].mode, "attackenemies", "resolver: k2 staged in its resolved mode")
    -- setDirectMode must also resolve each group independently.
    State.setDirectMode(rs, "autoassist")
    assert(rs.checkedGroupKeys["k1"] == true,  "resolver: k1 still checked after policy change")
    assert(rs.checkedGroupKeys["k2"] == true,  "resolver: k2 still checked after policy change")
    eq(rs.staged["k1"].mode, "autoassist", "resolver: k1 re-staged to its resolved mode")
    eq(rs.staged["k2"].mode, "attackenemies", "resolver: k2 re-staged to its resolved mode")
    -- Restore original resolver.
    State.resolveDirectMode = origResolveDirectMode
end

-- Issue #45 Task 1: pure same-root surface-element fallback selection.
-- State.nextSameRootSurface(surfaces, lostTargetID, targetRootID, crossTypePolicy)
-- returns the componentID to fall back to when a single surface element is lost.
do
    local root = "800"

    -- Another operational same-root surface exists: it is chosen according to
    -- the existing size_first ordering, not merely input order. The type_first
    -- twin case proves the policy is forwarded to the comparator: with these
    -- sizes a turret-first ordering would pick the other surface.
    local ordered = {
        { componentID = "20ULL", kindKey = "turret", size = "M", distance = 100 },
        { componentID = "30ULL", kindKey = "shield", size = "XL", distance = 100 },
    }
    eq(State.nextSameRootSurface(ordered, "99ULL", root, "size_first"), "30ULL",
        "nextSameRootSurface: size_first picks the XL shield although it is second in input order")
    eq(State.nextSameRootSurface(ordered, "99ULL", root, "type_first"), "20ULL",
        "nextSameRootSurface: type_first picks the turret, so the policy reaches the comparator")

    -- The lost surface is excluded from candidacy even while still present in
    -- the supplied list and even when it would otherwise win the ordering.
    local withLost = {
        { componentID = "50ULL", kindKey = "turret", size = "XS", distance = 100 },
        { componentID = "51ULL", kindKey = "turret", size = "XL", distance = 100 },
    }
    eq(State.nextSameRootSurface(withLost, "51ULL", root, "size_first"), "50ULL",
        "nextSameRootSurface: the lost surface itself is never re-selected")

    -- Only non-operational surfaces remain: the existing runtime operational
    -- filter is represented as an empty supplied list -> nil.
    eq(State.nextSameRootSurface({}, "99ULL", root, "size_first"), nil,
        "nextSameRootSurface: an empty operational list returns nil")
    -- No same-root surfaces exist at all (a nil list is tolerated) -> nil.
    eq(State.nextSameRootSurface(nil, "99ULL", root, "size_first"), nil,
        "nextSameRootSurface: a nil surface list returns nil")

    -- Ordinary object-level loss: lost ID equals root ID, including the
    -- normalized ULL/plain forms -> nil even when candidate surfaces exist.
    local candidates = {
        { componentID = "40ULL", kindKey = "turret", size = "XL", distance = 100 },
        { componentID = "41ULL", kindKey = "shield", size = "M", distance = 100 },
    }
    eq(State.nextSameRootSurface(candidates, "800", "800", "size_first"), nil,
        "nextSameRootSurface: plain/plain same ID is ordinary object-level loss")
    eq(State.nextSameRootSurface(candidates, "800ULL", "800", "size_first"), nil,
        "nextSameRootSurface: ULL/plain same ID is ordinary object-level loss")
    eq(State.nextSameRootSurface(candidates, "800", "800ULL", "size_first"), nil,
        "nextSameRootSurface: plain/ULL same ID is ordinary object-level loss")
    eq(State.nextSameRootSurface(candidates, "800ULL", "800ULL", "size_first"), nil,
        "nextSameRootSurface: ULL/ULL same ID is ordinary object-level loss")

    -- Null or zero IDs on either side mean there is no selection context -> nil.
    eq(State.nextSameRootSurface(candidates, nil, root, "size_first"), nil,
        "nextSameRootSurface: nil lost ID returns nil")
    eq(State.nextSameRootSurface(candidates, "900", nil, "size_first"), nil,
        "nextSameRootSurface: nil root ID returns nil")
    eq(State.nextSameRootSurface(candidates, "0", root, "size_first"), nil,
        "nextSameRootSurface: zero lost ID returns nil")
    eq(State.nextSameRootSurface(candidates, "0ULL", root, "size_first"), nil,
        "nextSameRootSurface: zero ULL lost ID returns nil")

    -- The supplied surface list is never mutated by the call.
    local orderCheck = {
        { componentID = "60ULL", kindKey = "turret", size = "M", distance = 100 },
        { componentID = "61ULL", kindKey = "shield", size = "XL", distance = 100 },
    }
    eq(State.nextSameRootSurface(orderCheck, "99ULL", root, "size_first"), "61ULL",
        "nextSameRootSurface: XL candidate is returned first")
    eq(State.normID(orderCheck[1].componentID), "60",
        "nextSameRootSurface: supplied list order is not mutated (first entry)")
    eq(State.normID(orderCheck[2].componentID), "61",
        "nextSameRootSurface: supplied list order is not mutated (second entry)")
    eq(#orderCheck, 2, "nextSameRootSurface: supplied list length is not mutated")
end

-- Issue #45 Task 4: pure OFFLINE planner for the ENGAGEABLE-aware
-- surface -> hull -> object fallback sequence.
-- State.planEngageFallback(stage, orderedIDs, page, pageSize, results)
-- plans the next deterministic action; results holds runtime-accepted
-- ENGAGEABLE data keyed by normalized ID. A result that is missing, pending,
-- or lacking a numeric engageable count must yield wait -- never advance a
-- page, hand off a stage, or be read as a manufactured zero.
do
    local function zero() return { engageable = 0, known = 4, total = 4 } end
    local function pending() return { pending = true, total = 4 } end

    -- First ranked positive wins, never the largest engageable count.
    local ids = { "1", "2", "3" }
    local results = { ["1"] = { engageable = 0, known = 4, total = 4 },
                      ["2"] = { engageable = 1, total = 4 },
                      ["3"] = { engageable = 4, total = 4 } }
    local action = State.planEngageFallback("surfaces", ids, 1, 20, results)
    eq(action.action, "engage", "planner: a settled positive page engages")
    eq(action.targetID, "2", "planner: first ranked positive wins, not the largest count")

    -- Pending/missing/unevaluated current-page result => wait, never next
    -- page or hull, even when the other rows on the page are settled zeros.
    local two = { "1", "2" }
    local pair = { ["1"] = zero(), ["2"] = zero() }
    pair["2"] = pending()
    eq(State.planEngageFallback("surfaces", two, 1, 20, pair).action, "wait",
        "planner: pending current-page result waits, not hull")
    pair["2"] = nil
    eq(State.planEngageFallback("surfaces", two, 1, 20, pair).action, "wait",
        "planner: missing current-page result waits, not hull")
    pair["2"] = { total = 4 }
    eq(State.planEngageFallback("surfaces", two, 1, 20, pair).action, "wait",
        "planner: result without a numeric engageable count waits")
    pair["1"] = pending()
    pair["2"] = { engageable = 3, total = 4 }
    eq(State.planEngageFallback("surfaces", two, 1, 20, pair).action, "wait",
        "planner: pending first row waits although a later row is positive")
    eq(State.planEngageFallback("surfaces", two, 1, 20, nil).action, "wait",
        "planner: no accepted results at all waits")

    -- 21+ surfaces: the planner only ever evaluates the current page.
    local many, manyResults = {}, {}
    for i = 1, 21 do
        local id = tostring(i)
        many[i] = id
        manyResults[id] = { engageable = 0, known = 4, total = 4 }
    end
    eq(State.planEngageFallback("surfaces", many, 1, 20, manyResults).action, "next_page",
        "planner: all-zero first page with ranked entries remaining advances")
    eq(State.planEngageFallback("surfaces", many, 2, 20, manyResults).action, "hull",
        "planner: final all-zero surface page hands off to hull")
    manyResults["21"] = pending()
    eq(State.planEngageFallback("surfaces", many, 1, 20, manyResults).action, "next_page",
        "planner: only the current page's results gate the decision")
    manyResults["21"] = { engageable = 2, total = 4 }
    eq(State.planEngageFallback("surfaces", many, 1, 20, manyResults).action, "next_page",
        "planner: a page-two positive does not engage from page one")
    local page2 = State.planEngageFallback("surfaces", many, 2, 20, manyResults)
    eq(page2.action, "engage", "planner: positive on page two engages")
    eq(page2.targetID, "21", "planner: the page-two ID is the engage target")
    manyResults["7"] = pending()
    eq(State.planEngageFallback("surfaces", many, 1, 20, manyResults).action, "wait",
        "planner: pending on page one holds it, never next_page")

    -- Hull stage: one batch -- pending waits, positive engages, settled zero
    -- falls to objects.
    local hull = { "600" }
    local hullAction = State.planEngageFallback("hull", hull, 1, 20,
        { ["600"] = { engageable = 3, total = 4 } })
    eq(hullAction.action, "engage", "planner: settled positive hull engages")
    eq(hullAction.targetID, "600", "planner: hull ID is the engage target")
    eq(State.planEngageFallback("hull", hull, 1, 20,
        { ["600"] = { engageable = 0, known = 4, total = 4 } }).action, "objects",
        "planner: settled zero hull falls to objects")
    eq(State.planEngageFallback("hull", hull, 1, 20, { ["600"] = pending() }).action, "wait",
        "planner: pending hull waits")
    eq(State.planEngageFallback("hull", hull, 1, 20, {}).action, "wait",
        "planner: hull with no accepted result waits")

    -- Objects stage: same ranked/page behaviour; final all-zero batch => none.
    local objIDs = { "700", "701", "702" }
    local objAction = State.planEngageFallback("objects", objIDs, 1, 20, {
        ["700"] = { engageable = 0, known = 4, total = 4 },
        ["701"] = { engageable = 1, total = 4 },
        ["702"] = { engageable = 5, total = 4 },
    })
    eq(objAction.action, "engage", "planner: ranked object positive engages")
    eq(objAction.targetID, "701", "planner: first ranked object wins, not the largest count")
    local objZeros = { ["700"] = zero(), ["701"] = zero(), ["702"] = zero() }
    eq(State.planEngageFallback("objects", objIDs, 1, 20, objZeros).action, "none",
        "planner: exhausted all-zero objects end at none")
    local manyObjs, manyObjResults = {}, {}
    for i = 1, 21 do
        local id = "o" .. i
        manyObjs[i] = id
        manyObjResults[id] = { engageable = 0, known = 4, total = 4 }
    end
    eq(State.planEngageFallback("objects", manyObjs, 1, 20, manyObjResults).action, "next_page",
        "planner: all-zero objects page advances like surfaces")
    manyObjResults["o21"] = { engageable = 2, total = 4 }
    local objPage2 = State.planEngageFallback("objects", manyObjs, 2, 20, manyObjResults)
    eq(objPage2.action, "engage", "planner: page-two object positive engages")
    eq(objPage2.targetID, "o21", "planner: page-two object ID engaged")
    for i = 1, 21 do manyObjResults["o" .. i] = zero() end
    eq(State.planEngageFallback("objects", manyObjs, 2, 20, manyObjResults).action, "none",
        "planner: final all-zero objects batch ends at none")

    -- The expected page size of 20 comes from surfacePage, not duplicated
    -- here.
    local sizedIDs, sizedResults = {}, {}
    for i = 1, 21 do
        local id = tostring(i)
        sizedIDs[i] = id
        sizedResults[id] = zero()
    end
    eq(State.planEngageFallback("surfaces", sizedIDs, 1, nil, sizedResults).action, "next_page",
        "planner: nil page size defaults to 20")
    eq(State.planEngageFallback("surfaces", { "1", "2" }, 1, nil,
        { ["1"] = zero(), ["2"] = zero() }).action, "hull",
        "planner: single all-zero page at the default size hands off to hull")

    -- IDs match across the FFI/plain boundary; the planner returns the
    -- caller's own ID form.
    local u = State.planEngageFallback("hull", { "600ULL" }, nil, nil,
        { ["600"] = { engageable = 1, total = 2 } })
    eq(u.action, "engage", "planner: ULL-suffixed ID matches the normalized key")
    eq(u.targetID, "600ULL", "planner: returns the caller's own ID form")

    -- Issue #45 Task 4 correction: an incomplete-coverage zero is
    -- unresolved, never a proven zero. engageable == 0 settles only when
    -- total == 0 or known == total (both numeric); known < total, a missing
    -- known while total > 0, or any other incomplete coverage waits like a
    -- pending.
    local function incompleteZero() return { engageable = 0, known = 3, total = 4 } end

    -- surfaces: the incomplete zero holds the decision on the final page
    -- (never hull) and on an earlier page (never next_page).
    eq(State.planEngageFallback("surfaces", { "1", "2" }, 1, 20,
        { ["1"] = zero(), ["2"] = incompleteZero() }).action, "wait",
        "planner: incomplete zero on the final surface page waits, never hull")
    local incSurfaces, incSurfaceResults = {}, {}
    for i = 1, 21 do
        local id = tostring(i)
        incSurfaces[i] = id
        incSurfaceResults[id] = zero()
    end
    incSurfaceResults["7"] = incompleteZero()
    eq(State.planEngageFallback("surfaces", incSurfaces, 1, 20, incSurfaceResults).action,
        "wait",
        "planner: incomplete zero on an earlier surface page waits, never next_page")

    -- hull: the same incomplete zero waits, never objects.
    eq(State.planEngageFallback("hull", { "600" }, 1, 20,
        { ["600"] = incompleteZero() }).action, "wait",
        "planner: incomplete zero hull waits, never objects")

    -- objects: the same incomplete zero waits, never none (final batch) or
    -- next_page (earlier page).
    eq(State.planEngageFallback("objects", { "700", "701" }, 1, 20,
        { ["700"] = zero(), ["701"] = incompleteZero() }).action, "wait",
        "planner: incomplete zero in the final object batch waits, never none")
    local incObjects, incObjectResults = {}, {}
    for i = 1, 21 do
        local id = "o" .. i
        incObjects[i] = id
        incObjectResults[id] = zero()
    end
    incObjectResults["o7"] = incompleteZero()
    eq(State.planEngageFallback("objects", incObjects, 1, 20, incObjectResults).action,
        "wait",
        "planner: incomplete zero on an earlier object page waits, never next_page")

    -- A positive still qualifies under partial coverage: engageable > 0 has
    -- already proven at least one ENGAGEABLE. An unresolved row ahead of it
    -- still waits first (same priority as pending).
    local partialPositive = State.planEngageFallback("surfaces", { "1", "2" }, 1, 20,
        { ["1"] = zero(), ["2"] = { engageable = 1, known = 1, total = 4 } })
    eq(partialPositive.action, "engage",
        "planner: a partial-coverage positive still engages")
    eq(partialPositive.targetID, "2",
        "planner: the partial-coverage positive is the engage target")
    eq(State.planEngageFallback("surfaces", { "1", "2" }, 1, 20,
        { ["1"] = incompleteZero(),
          ["2"] = { engageable = 1, known = 1, total = 4 } }).action, "wait",
        "planner: an incomplete zero waits ahead of a later positive")

    -- engageable == 0 with total == 0 remains a settled zero: a group
    -- reporting no components cannot wait forever.
    eq(State.planEngageFallback("surfaces", { "1" }, 1, 20,
        { ["1"] = { engageable = 0, total = 0 } }).action, "hull",
        "planner: zero with total = 0 settles, so nothing waits forever")
    eq(State.planEngageFallback("hull", { "600" }, 1, 20,
        { ["600"] = { engageable = 0, total = 0 } }).action, "objects",
        "planner: a zero-total hull settles to objects")

    -- A zero with known == total (both numeric) is proven; a zero with
    -- missing known while total > 0 is not.
    eq(State.planEngageFallback("surfaces", { "1" }, 1, 20,
        { ["1"] = zero() }).action, "hull",
        "planner: a zero with known == total settles and hands off")
    eq(State.planEngageFallback("surfaces", { "1" }, 1, 20,
        { ["1"] = { engageable = 0, total = 4 } }).action, "wait",
        "planner: a zero with missing known and total > 0 waits")

    -- Inputs are never mutated.
    local inIDs = { "1", "2" }
    local inR1, inR2 = { engageable = 1, total = 4 }, { pending = true, total = 4 }
    local inResults = { ["1"] = inR1, ["2"] = inR2 }
    State.planEngageFallback("surfaces", inIDs, 1, 20, inResults)
    eq(#inIDs, 2, "planner: ordered IDs length untouched")
    eq(inIDs[1], "1", "planner: ordered IDs order untouched")
    eq(inResults["1"], inR1, "planner: result entries remain the same tables")
    eq(inR1.engageable, 1, "planner: settled result fields untouched")
    eq(inR2.pending, true, "planner: pending result untouched")

    -- Unknown stage is a contract violation, not an action.
    local ok, err = pcall(State.planEngageFallback, "shields", { "1" }, 1, 20, {})
    assert(not ok, "planner: unknown stage must raise")
    assert(tostring(err):find("unknown fallback stage"),
        "planner: unknown stage error names the contract")
end

print("gunnery_state tests passed")
