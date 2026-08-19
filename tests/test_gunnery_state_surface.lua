local State = dofile("ui/gunnery_state.lua")
local function eq(a, b, label) assert(a == b, (label or "values differ") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

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


print("gunnery_state surface tests passed")
