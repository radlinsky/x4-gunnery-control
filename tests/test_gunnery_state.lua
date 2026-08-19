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

print("gunnery_state tests passed")
