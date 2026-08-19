-- test_runtime_auto_next.lua
-- Issue #45 Task 5 (block 42, scenarios A-P): Direct target loss —
-- asynchronous same-root fallback, extracted from test_runtime_targeting.lua.

local fix = dofile("tests/support/runtime_fixture.lua").load()
local gcMenu = fix.gcMenu
local API    = fix.API
local C      = fix.C

-- Shared clock for getElapsedTime; tests advance it explicitly.
local clock = 100
getElapsedTime = function() return clock end

-- ── 42. Direct target loss: asynchronous same-root fallback (Issue #45 Task 5) ─
-- The production path is updateAimTarget() on the 0.25 s tick. A dead surface
-- element with Auto-next on must NOT be answered with an immediate choice:
-- onDirectTargetLost() refreshes the root's surface snapshot, records the
-- ranked unfiltered same-root surfaces in session.targetFallback (page 1),
-- and issues the page-1 ENGAGEABLE query immediately. Each later tick consumes
-- the pending/accepted readings through one State.planEngageFallback decision:
-- ranked same-root surfaces in pages, then the target's hull, then ranked
-- other objects. The assertions below fail on a synchronous pick at the loss
-- tick, a deferred page-1 query, a browser fallback before the planner has
-- exhausted every stage, re-implemented enumeration/ordering logic, or a
-- request that bypasses the checked operational turret membership.
-- Distinct stub IDs keep every assertion discriminating: 600 root, 701+
-- surfaces, 98/99 hostile objects, 500 ordinary object.
do
    -- Save the stubs this block replaces; nil restores the fixture's C
    -- metatable fallbacks.
    local savedClass42 = C.IsComponentClass
    local savedNumSlots42 = C.GetNumUpgradeSlots
    local savedSlotComp42 = C.GetUpgradeSlotCurrentComponent
    local savedSlotMacro42 = C.GetUpgradeSlotCurrentMacro
    local savedSetName42 = C.GetComponentName
    local savedDist42 = C.GetDistanceBetween
    local savedCtxClass42 = C.GetContextByClass
    local savedOperational42 = C.IsComponentOperational
    local savedSoft42 = C.SetSofttarget
    local savedMacroData42 = GetMacroData
    local savedCompData42 = GetComponentData
    local savedShips42 = GetContainedShips
    local savedStations42 = GetContainedStations
    local savedSector42 = GetPlayerContextByClass
    local savedAdd42 = AddUITriggeredEvent
    -- Earlier blocks left their own AddUITriggeredEvent stubs installed; this
    -- block captures into the fixture list so the batch helpers can read it.
    AddUITriggeredEvent = function(screen, control, params)
        fix.uiTriggeredEvents[#fix.uiTriggeredEvents + 1] = {
            screen = screen, control = control, params = params,
        }
    end

    C.IsComponentClass = function(component, class)
        if class == "ship" then return true end
        return false
    end
    -- Surfaces 70x resolve to their root 600; every other component (the
    -- ship, hostile objects 98/99, ordinary object 500) resolves to itself.
    C.GetContextByClass = function(component)
        local n = tonumber(tostring(component))
        if n and n >= 700 and n <= 799 then return 600 end
        return component
    end
    C.GetDistanceBetween = function() return 1000 end
    C.GetComponentName = function(component) return "Target " .. tostring(component) end
    C.GetUpgradeSlotCurrentMacro = function() return "" end
    GetMacroData = function() return "" end
    GetPlayerContextByClass = function() return 1 end
    -- Root 600 is a plain (non-station) object carrying turret slots 701..N.
    local slotCount42 = 0
    -- Only surface scans of root 600 count: readGroups() also queries
    -- GetNumUpgradeSlots for the ship's own turret groups, which is not a
    -- surface enumeration.
    local surfaceScanCalls42 = 0
    C.GetNumUpgradeSlots = function(destructible, _, upgrade)
        if tonumber(tostring(destructible)) ~= 600 then return 0 end
        if upgrade ~= "turret" then return 0 end
        surfaceScanCalls42 = surfaceScanCalls42 + 1
        return slotCount42
    end
    C.GetUpgradeSlotCurrentComponent = function(destructible, _, slot)
        return tonumber(tostring(destructible)) == 600 and (700 + slot) or 0
    end
    local operational42 = {}
    C.IsComponentOperational = function(cid)
        return operational42[tostring(cid)] == true
    end
    -- The sector sweep that chooseAimTarget()/readTargetCandidates() run:
    -- counting these proves (or disproves) that the object sweep was
    -- consulted, and when.
    local objectSweepCalls42 = 0
    local sectorShips42 = {}
    GetContainedShips = function()
        objectSweepCalls42 = objectSweepCalls42 + 1
        return sectorShips42
    end
    GetContainedStations = function()
        objectSweepCalls42 = objectSweepCalls42 + 1
        return {}
    end
    local softtargetCalls42 = {}
    C.SetSofttarget = function(target, conn)
        softtargetCalls42[#softtargetCalls42 + 1] = target
        return true
    end
    GetComponentData = function(component, ...)
        local keys, vals = {...}, {}
        for _, k in ipairs(keys) do
            if k == "isenemy" then vals[#vals + 1] = true
            elseif k == "isknown" then vals[#vals + 1] = true
            elseif k == "isradarvisible" then vals[#vals + 1] = true
            elseif k == "maxradarrange" then vals[#vals + 1] = 40000
            elseif k == "isplayerowned" then vals[#vals + 1] = false
            else vals[#vals + 1] = false
            end
        end
        return unpack(vals)
    end

    -- ── shared helpers ────────────────────────────────────────────────────
    local function group42(key, memberID, operational)
        return { key = key, kind = "group", contextID = 5, path = "p", group = "g",
            componentID = memberID, displayName = "G" .. key, totalCount = 1,
            operationalCount = operational and 1 or 0, mode = "attack", armed = false,
            members = { { componentID = memberID, displayName = "T",
                           operational = operational, cameraSupported = true,
                           componentKey = tostring(memberID) } } }
    end
    local grp42 = group42("grp42", 27, true)

    -- A fresh engaged/direct session; the given groups are the checked ones.
    local function freshDirectSession42(groups)
        gcMenu.onShowMenu()
        local sess = API.getSession()
        assert(sess ~= nil, "expected a fresh session")
        local keys = {}
        for _, g in ipairs(groups) do keys[g.key] = true end
        sess.groups, sess.checkedGroupKeys = groups, keys
        sess.phase, sess.controlMode = "engaged", "direct"
        sess.committedBaseline = { { kind = "group", contextID = 5, path = "p",
            group = "g", shipID = sess.shipID, mode = "attack", armed = false } }
        sess.cameraMemberID = 27
        sess.povAnchor, sess.povMode = "turret", "manual"
        return sess
    end

    -- ENGAGEABLE batches emitted after uiTriggeredEvents index `mark`.
    local function batchesSince42(mark)
        local batches, current = {}, nil
        for i = mark + 1, #fix.uiTriggeredEvents do
            local e = fix.uiTriggeredEvents[i]
            if e.control == "engageability_begin" then
                current = { nonce = e.params.nonce, members = e.params.members,
                             memberIDs = {}, targets = {} }
                batches[#batches + 1] = current
            elseif current ~= nil and e.params and e.params.nonce == current.nonce then
                if e.control == "engageability_member" then
                    current.memberIDs[#current.memberIDs + 1] = e.params.weapon
                elseif e.control == "engageability_target" then
                    current.targets[#current.targets + 1] = X4GunneryState.normID(e.params.target)
                elseif e.control == "engageability_commit" then
                    current = nil
                end
            end
        end
        return batches
    end

    -- Deliver MD's reply for one batch: an EngageabilityResult per target it
    -- has a reading for ("engageable:known:total"), then the batch complete.
    local function deliver42(batch, resultsByKey)
        for _, key in ipairs(batch.targets) do
            local counts = resultsByKey[key]
            if counts then
                fix.fireEvent("X4GunneryControl.EngageabilityResult",
                    "x4gce3:" .. batch.nonce .. ":" .. key .. ":" .. counts)
            end
        end
        fix.fireEvent("X4GunneryControl.EngageabilityBatchComplete",
            "x4gce2c:" .. batch.nonce .. ":" .. tostring(#batch.targets) .. ":"
                .. tostring(#batch.targets))
    end

    local function resetCounts42()
        slotCount42 = 0
        sectorShips42 = {}
        operational42 = {}
        surfaceScanCalls42 = 0
        objectSweepCalls42 = 0
        softtargetCalls42 = {}
    end

    local function tick42()
        clock = clock + 0.25
        API.updateAimTarget()
    end

    -- The common scenario preamble: reset the counters, install the fixture
    -- values, create the fresh direct session on the checked groups
    -- (default { grp42 }), aim target/root at 600/701, move the clock to
    -- 500, and return the session. Behavioral steps stay in each scenario.
    local function scenario42(opts)
        resetCounts42()
        slotCount42 = opts.slotCount42
        operational42 = opts.operational42
        sectorShips42 = opts.sectorShips42
        local sess = freshDirectSession42(opts.groups or { grp42 })
        sess.targetObjectID, sess.aimTargetID =
            opts.targetObjectID or 600, opts.aimTargetID or 701
        clock = opts.clock or 500
        return sess
    end

    -- E/F/N/O/P preamble: from a fresh session aimed at the dead surface
    -- 701 of root 600 with no other root surface alive, drive the existing
    -- production path to the objects stage: the loss tick, the empty-
    -- surfaces escalation to the hull stage, the hull ENGAGEABLE query
    -- (exactly root 600), the proven-zero "0:1:1" reading, and the
    -- escalation to objects. Returns the UI-event mark of the moment the
    -- objects stage is entered; object-stage batches, results, and actions
    -- stay in the calling scenario.
    local function reachObjects42(sess)
        API.updateAimTarget()
        tick42()
        assert(sess.targetFallback ~= nil
            and sess.targetFallback.stage == "hull",
            "an empty surface stage must escalate to the hull stage; stage is "
            .. tostring(sess.targetFallback and sess.targetFallback.stage))
        local mark = #fix.uiTriggeredEvents
        tick42()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 1
            and batches[1].targets[1] == "600",
            "the hull stage must issue one ENGAGEABLE query for exactly the "
            .. "root 600; targets="
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        deliver42(batches[1], { ["600"] = "0:1:1" })
        tick42()
        assert(sess.targetFallback ~= nil
            and sess.targetFallback.stage == "objects",
            "a proven-zero hull must escalate to the objects stage; stage is "
            .. tostring(sess.targetFallback and sess.targetFallback.stage))
        return #fix.uiTriggeredEvents
    end

    -- Count only engageability transport events since `mark`: an engage also
    -- emits its direct_fallback cue, which is expected, not a violation.
    local function engageabilityEventsSince42(mark)
        local n = 0
        for i = mark + 1, #fix.uiTriggeredEvents do
            if tostring(fix.uiTriggeredEvents[i].control):match("^engageability_") then
                n = n + 1
            end
        end
        return n
    end

    -- A. Task 5A: the loss tick supersedes a REAL pre-existing surface
    -- snapshot of the same root (one generation later), ranks the unfiltered
    -- alternatives of its refreshed allSurfaces, and immediately issues
    -- exactly one page-1 ENGAGEABLE batch for the checked operational
    -- turrets. It still makes no choice and runs no object sweep; the next
    -- tick consumes the pending readings without re-requesting.
    do
        local sess = scenario42({
            slotCount42 = 3,                  -- 701/702/703 all alive at first
            operational42 = { ["600"] = true, ["701"] = true, ["702"] = true,
                ["703"] = true, ["98"] = true },
            sectorShips42 = { 98 } })
        sess.surfaceTypeFilter = "engine"     -- browser filter: must not narrow the fallback
        -- 1. Establish a REAL pre-existing snapshot: render the element panel
        -- the way an engaged direct-control player sees it, aiming at the
        -- live surface 701. The loss tick below must then supersede this
        -- live browser snapshot rather than create one from scratch.
        local okA, errA = pcall(function() gcMenu.display() end)
        assert(okA, "setup display raised: " .. tostring(errA))
        assert(sess.surfaceBrowser ~= nil
            and X4GunneryState.normID(sess.surfaceBrowser.rootID) == "600"
            and (sess.surfaceBrowser.generation or 0) >= 1,
            "setup: the element panel render must create a real snapshot for "
            .. "root 600; generation="
            .. tostring(sess.surfaceBrowser and sess.surfaceBrowser.generation))
        local genBefore = sess.surfaceBrowser.generation
        local oldAllSurfaces = {}
        for _, surface in ipairs(sess.surfaceBrowser.allSurfaces or {}) do
            oldAllSurfaces[#oldAllSurfaces + 1] = X4GunneryState.normID(surface.componentID)
        end
        assert(table.concat(oldAllSurfaces, ",") == "701,702,703",
            "setup: the pre-existing snapshot must hold all three operational "
            .. "surfaces; got " .. table.concat(oldAllSurfaces, ","))
        -- The user's engine filter narrows the browser's FILTERED list to
        -- nothing (all three surfaces are turrets) while its unfiltered
        -- allSurfaces keeps the turret surfaces: the fallback below must rank
        -- the allSurfaces that the filter hides from the browser.
        assert(#sess.surfaceBrowser.orderedIDs == 0,
            "setup: under the engine filter the browser's filtered orderedIDs "
            .. "must be empty while allSurfaces holds the turret surfaces; got "
            .. tostring(#sess.surfaceBrowser.orderedIDs))
        -- ENGAGEABLE traffic from that setup render (the pinned row's batch)
        -- must not satisfy the loss-tick assertions: mark only now.
        local mark = #fix.uiTriggeredEvents
        local sweepsAtMark = objectSweepCalls42
        softtargetCalls42 = {}
        -- The browser object the loss tick must refresh in place.
        local browserBefore = sess.surfaceBrowser
        -- 2. 701 dies while the browser still lists it: the pre-existing
        -- snapshot is now stale.
        operational42["701"] = false
        local lossLogStart = #fix.getCapturedLog()
        API.updateAimTarget()
        assert(sess.targetFallback ~= nil,
            "surface loss with auto-next on must start a session-scoped resolution")
        assert(tostring(sess.aimTargetID) == "701",
            "no immediate choice: the aim must stay on the lost surface; aim is "
            .. tostring(sess.aimTargetID))
        assert(tostring(sess.targetObjectID) == "600" and sess.phase == "engaged",
            "the resolution must preserve the root and stay engaged; root="
            .. tostring(sess.targetObjectID) .. " phase=" .. tostring(sess.phase))
        assert(#softtargetCalls42 == 0,
            "no re-engage may happen on the loss tick itself")
        assert(objectSweepCalls42 == sweepsAtMark,
            "the object sweep belongs to the planner's objects stage, not the loss tick; "
            .. (objectSweepCalls42 - sweepsAtMark) .. " extra call(s)")
        -- The surface snapshot for the root is the SAME browser object,
        -- advanced by exactly one generation on the loss tick...
        assert(sess.surfaceBrowser == browserBefore,
            "the loss tick must refresh the pre-existing browser object "
            .. "itself, not replace it")
        assert(sess.surfaceBrowser.generation == genBefore + 1,
            "the loss tick must advance the pre-existing snapshot by exactly "
            .. "one generation; before=" .. tostring(genBefore)
            .. " after=" .. tostring(sess.surfaceBrowser.generation))
        local sawSnapshotLog, sawFallbackStartLog = false, false
        for i = lossLogStart + 1, #fix.getCapturedLog() do
            local line = fix.getCapturedLog()[i]
            if string.find(line,
                "event=surface_snapshot action=create reason=auto_next", 1, true) then
                sawSnapshotLog = true
            end
            if string.find(line,
                "event=auto_next_fallback action=start", 1, true) then
                sawFallbackStartLog = true
            end
        end
        assert(sawSnapshotLog,
            "the loss-tick snapshot refresh must be logged with the auto_next reason")
        -- ...and its allSurfaces now reflect the changed population instead
        -- of the stale setup snapshot.
        local newAllSurfaces = {}
        for _, surface in ipairs(sess.surfaceBrowser.allSurfaces or {}) do
            newAllSurfaces[#newAllSurfaces + 1] = X4GunneryState.normID(surface.componentID)
        end
        assert(table.concat(newAllSurfaces, ",") == "702,703",
            "the refreshed snapshot must hold the unfiltered operational surfaces "
            .. "after 701 died; got " .. table.concat(newAllSurfaces, ","))
        assert(table.concat(newAllSurfaces, ",") ~= table.concat(oldAllSurfaces, ","),
            "the refreshed allSurfaces must differ from the stale setup snapshot; old="
            .. table.concat(oldAllSurfaces, ",")
            .. " new=" .. table.concat(newAllSurfaces, ","))
        -- and the fallback ranks the unfiltered same-root alternatives of
        -- exactly that snapshot (the user's engine filter would leave the
        -- browser none of them).
        local expected = X4GunneryState.surfaceAlternatives(
            sess.surfaceBrowser.allSurfaces, sess.aimTargetID, "any", "any")
        table.sort(expected, function(a, b)
            return X4GunneryState.surfaceMetadataLess(a, b, "size_first")
        end)
        local expectedIDs = {}
        for _, surface in ipairs(expected) do
            expectedIDs[#expectedIDs + 1] = X4GunneryState.normID(surface.componentID)
        end
        assert(sess.targetFallback.stage == "surfaces" and sess.targetFallback.page == 1
            and #sess.targetFallback.orderedIDs == #expectedIDs
            and table.concat(sess.targetFallback.orderedIDs, ",")
                == table.concat(expectedIDs, ","),
            "the fallback must start at surfaces page 1 ranked from the refreshed "
            .. "unfiltered allSurfaces; stage="
            .. tostring(sess.targetFallback.stage)
            .. " page=" .. tostring(sess.targetFallback.page)
            .. " ids=" .. table.concat(sess.targetFallback.orderedIDs, ",")
            .. " expected=" .. table.concat(expectedIDs, ","))
        assert(surfaceScanCalls42 >= 1,
            "the resolution must rank root 600 through the surface reader")
        assert(sawFallbackStartLog,
            "the fallback start must be logged on this loss tick")
        -- ...and page 1 is queried immediately through the checked turrets.
        local batches = batchesSince42(mark)
        assert(#batches == 1,
            "the loss tick must issue exactly one page-1 ENGAGEABLE batch; got "
            .. tostring(#batches))
        assert(#batches[1].targets <= 20,
            "a page-1 batch must hold at most 20 ranked targets; got "
            .. tostring(#batches[1].targets))
        assert(batches[1].members == 1 and #batches[1].memberIDs == 1
            and batches[1].memberIDs[1] == 27,
            "the batch must carry exactly the checked operational turret; members="
            .. tostring(batches[1].members)
            .. " members_list=" .. table.concat(batches[1].memberIDs, ","))
        assert(#batches[1].targets == 2 and batches[1].targets[1] == "702"
            and batches[1].targets[2] == "703",
            "page 1 must query the ranked same-root surfaces; targets="
            .. table.concat(batches[1].targets, ","))
        assert(#softtargetCalls42 == 0,
            "no choice may be made before a result is accepted")

        -- Next tick: the batch is still pending inside the cache window, so
        -- the planner waits without re-requesting, and still makes no choice.
        mark = #fix.uiTriggeredEvents
        tick42()
        assert(#batchesSince42(mark) == 0,
            "a still-pending page-1 batch must not be re-requested on the next tick")
        assert(#softtargetCalls42 == 0,
            "no choice may be made before a result is accepted")
    end

    -- B. An accepted positive result engages the surviving surface and ends
    -- the resolution; the root is preserved.
    do
        local sess = scenario42({
            slotCount42 = 2,
            operational42 = { ["600"] = true, ["702"] = true, ["98"] = true },
            sectorShips42 = { 98 } })
        sess.povAnchor, sess.povMode = "turret", "cinematic"
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        local batches = batchesSince42(mark)
        assert(#batches == 1, "the loss tick must issue the page-1 batch")
        deliver42(batches[1], { ["702"] = "1:1:1" })
        softtargetCalls42 = {}
        tick42()
        assert(tostring(sess.aimTargetID) == "702",
            "the accepted positive surface must be engaged; aim is "
            .. tostring(sess.aimTargetID))
        assert(tostring(sess.targetObjectID) == "600",
            "same-root fallback must preserve the root object; targetObjectID is "
            .. tostring(sess.targetObjectID))
        assert(sess.phase == "engaged",
            "the resolution must stay engaged; phase is " .. tostring(sess.phase))
        assert(sess.targetFallback == nil,
            "an engaged resolution must clear the fallback state")
        assert(#softtargetCalls42 >= 1 and softtargetCalls42[#softtargetCalls42] == 702,
            "the engaged surface must become the soft target; got "
            .. tostring(softtargetCalls42[#softtargetCalls42]))
        local stops, starts = 0, 0
        for i = mark + 1, #fix.uiTriggeredEvents do
            local e = fix.uiTriggeredEvents[i]
            if e.control == "cutscene_aim_stop" then stops = stops + 1 end
            if e.control == "cutscene_aim_start" then starts = starts + 1 end
        end
        assert(stops == 1 and starts == 1,
            "a cinematic POV must be stopped and restarted around the engage; "
            .. "stops=" .. stops .. " starts=" .. starts)
        assert(fix.logContains("auto-next engaged"),
            "the auto-next engage must keep its session log line")
    end

    -- C. Pages advance only when every reading on the page is a proven zero;
    -- the next page is queried as a fresh batch and the first ranked positive
    -- on it wins. Cached page-1 readings must not be re-requested within the
    -- cache window.
    do
        local operationalC = { ["600"] = true, ["98"] = true }
        for n = 702, 724 do operationalC[tostring(n)] = true end
        local sess = scenario42({
            slotCount42 = 24,                 -- 701 dead, 702..724 alive
            operational42 = operationalC,
            sectorShips42 = { 98 } })
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 20
            and batches[1].targets[1] == "702" and batches[1].targets[20] == "721",
            "page 1 must be the first 20 ranked surfaces; got "
            .. tostring(#batches) .. " batch(es), "
            .. tostring(#(batches[1] and batches[1].targets or {})) .. " target(s)")
        local zeros = {}
        for _, key in ipairs(batches[1].targets) do zeros[key] = "0:1:1" end
        deliver42(batches[1], zeros)
        mark = #fix.uiTriggeredEvents
        tick42()
        assert(sess.targetFallback ~= nil and sess.targetFallback.page == 2,
            "an all-zero page must advance to page 2; page is "
            .. tostring(sess.targetFallback and sess.targetFallback.page))
        assert(#batchesSince42(mark) == 0,
            "page 2 must not be requested on the same tick as the page advance")
        tick42()
        batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 3
            and batches[1].targets[1] == "722" and batches[1].targets[3] == "724",
            "page 2 must be a fresh batch for the remaining ranked surfaces; got "
            .. tostring(#batches) .. " batch(es), targets="
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        local seen702 = 0
        for i = mark, #fix.uiTriggeredEvents do
            local e = fix.uiTriggeredEvents[i]
            if e.control == "engageability_target"
                and X4GunneryState.normID(e.params.target) == "702" then
                seen702 = seen702 + 1
            end
        end
        assert(seen702 == 0,
            "page-1 targets must be served from the cache, not re-requested")
        deliver42(batches[1], { ["722"] = "0:1:1", ["723"] = "0:1:1", ["724"] = "1:1:1" })
        softtargetCalls42 = {}
        tick42()
        assert(tostring(sess.aimTargetID) == "724" and tostring(sess.targetObjectID) == "600",
            "the first ranked positive on page 2 must be engaged; aim="
            .. tostring(sess.aimTargetID) .. " root=" .. tostring(sess.targetObjectID))
        assert(sess.phase == "engaged" and sess.targetFallback == nil,
            "page-2 engage must stay engaged and clear the fallback")
        assert(softtargetCalls42[#softtargetCalls42] == 724,
            "the engaged page-2 surface must become the soft target")
    end

    -- D. With no surviving same-root surface, the planner escalates to the
    -- target's hull, and a positive hull reading engages the hull itself.
    do
        local sess = scenario42({
            slotCount42 = 1,                  -- only the dead 701 remains
            operational42 = { ["600"] = true, ["98"] = true },
            sectorShips42 = { 98 } })
        API.updateAimTarget()
        tick42()
        assert(sess.targetFallback.stage == "hull",
            "an empty surface stage must escalate to the hull stage; stage is "
            .. tostring(sess.targetFallback.stage))
        assert(X4GunneryState.normID(sess.targetFallback.orderedIDs[1]) == "600"
            and #sess.targetFallback.orderedIDs == 1,
            "the hull stage must query exactly the root object")
        local mark = #fix.uiTriggeredEvents
        tick42()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 1
            and batches[1].targets[1] == "600",
            "the hull stage must issue one ENGAGEABLE query for the root")
        deliver42(batches[1], { ["600"] = "1:1:1" })
        softtargetCalls42 = {}
        tick42()
        assert(tostring(sess.aimTargetID) == "600" and tostring(sess.targetObjectID) == "600",
            "a positive hull reading must engage the root hull; aim="
            .. tostring(sess.aimTargetID))
        assert(sess.phase == "engaged" and sess.targetFallback == nil,
            "the hull engage must stay engaged and clear the fallback")
        assert(softtargetCalls42[#softtargetCalls42] == 600,
            "the hull must become the soft target")
    end

    -- E. A proven-zero hull escalates to ranked other objects; the planner
    -- walks the ranking and engages the first positive, skipping proven zeros.
    do
        local sess = scenario42({
            slotCount42 = 1,
            operational42 = { ["600"] = true, ["98"] = true, ["99"] = true },
            sectorShips42 = { 98, 99 } })
        local mark = reachObjects42(sess)
        assert(objectSweepCalls42 >= 1,
            "the objects stage must rank through the sector sweep")
        tick42()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 2
            and batches[1].targets[1] == "98" and batches[1].targets[2] == "99",
            "the objects stage must query the ranked candidates without the lost root; "
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        deliver42(batches[1], { ["98"] = "0:1:1", ["99"] = "1:1:1" })
        softtargetCalls42 = {}
        tick42()
        assert(tostring(sess.aimTargetID) == "99" and tostring(sess.targetObjectID) == "99",
            "the first ranked positive object must be engaged, skipping the "
            .. "proven-zero 98; aim=" .. tostring(sess.aimTargetID))
        assert(sess.phase == "engaged" and sess.targetFallback == nil,
            "the object engage must stay engaged and clear the fallback")
        assert(softtargetCalls42[#softtargetCalls42] == 99,
            "the engaged object must become the soft target")
    end

    -- F. Surfaces, hull and every other object proven zero: the resolution
    -- exhausts and hands the choice back at the target browser.
    do
        local sess = scenario42({
            slotCount42 = 1,
            operational42 = { ["600"] = true },
            sectorShips42 = {} })
        sess.povAnchor, sess.povMode = "target", "cinematic"
        reachObjects42(sess)
        assert(#sess.targetFallback.orderedIDs == 0,
            "with no other objects the objects stage must be empty")
        tick42()
        assert(sess.phase == "target_select",
            "an exhausted resolution must reopen the target browser; phase is "
            .. tostring(sess.phase))
        assert(sess.aimTargetID == nil and sess.targetObjectID == nil,
            "the browser fallback must clear the lost aim and root")
        assert(sess.povAnchor == "turret" and sess.povMode == "manual",
            "the browser fallback must reset the view to manual Turret POV; got "
            .. tostring(sess.povAnchor) .. "/" .. tostring(sess.povMode))
        assert(sess.targetFallback == nil,
            "the exhausted resolution must clear the fallback state")
        assert(#softtargetCalls42 == 0,
            "an exhausted resolution must not re-engage anything")
        assert(fix.logContains("event=auto_next_fallback action=exhausted"),
            "the exhausted resolution must be logged")
    end

    -- G. Ordinary object-level loss (aimTargetID == targetObjectID) keeps the
    -- existing synchronous object sweep: no fallback state, no surface
    -- enumeration, no ENGAGEABLE request.
    do
        local sess = scenario42({
            slotCount42 = 2,
            operational42 = { ["98"] = true },
            sectorShips42 = { 98 },
            targetObjectID = 500, aimTargetID = 500 })
        sess.povAnchor, sess.povMode = "turret", "cinematic"
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        assert(sess.targetFallback == nil,
            "ordinary object loss must not start the surface fallback")
        assert(tostring(sess.aimTargetID) == "98" and tostring(sess.targetObjectID) == "98",
            "an ordinary dead object must fall back to the next object; aim="
            .. tostring(sess.aimTargetID))
        assert(sess.phase == "engaged",
            "the object fallback must stay engaged; phase is " .. tostring(sess.phase))
        assert(surfaceScanCalls42 == 0,
            "ordinary object-level loss must not enumerate surfaces; the surface "
            .. "reader ran " .. surfaceScanCalls42 .. " time(s)")
        assert(objectSweepCalls42 >= 1,
            "the object fallback must run the sweep to find 98")
        assert(engageabilityEventsSince42(mark) == 0,
            "ordinary object loss must not issue ENGAGEABLE requests")
        assert(softtargetCalls42[#softtargetCalls42] == 98,
            "the sweep's survivor must become the soft target")
        local stopsG, startsG = 0, 0
        for i = mark + 1, #fix.uiTriggeredEvents do
            local e = fix.uiTriggeredEvents[i]
            if e.control == "cutscene_aim_stop" then stopsG = stopsG + 1 end
            if e.control == "cutscene_aim_start" then startsG = startsG + 1 end
        end
        assert(stopsG == 1 and startsG == 1,
            "the object-loss engage must stop/restart a running cinematic; "
            .. "stops=" .. stopsG .. " starts=" .. startsG)
    end

    -- H. Auto-next off during a surface loss: straight to the browser, with
    -- neither a fallback state nor any enumeration.
    do
        local sess = scenario42({
            slotCount42 = 2,
            operational42 = { ["702"] = true, ["98"] = true },
            sectorShips42 = { 98 } })
        sess.autoNextTarget = false
        sess.povAnchor, sess.povMode = "target", "cinematic"
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        assert(sess.phase == "target_select",
            "with auto-next off a dead surface must reopen the target browser; phase is "
            .. tostring(sess.phase))
        assert(sess.aimTargetID == nil and sess.targetObjectID == nil,
            "the browser fallback must clear the lost aim and root")
        assert(sess.povAnchor == "turret" and sess.povMode == "manual",
            "the browser fallback must reset the view to manual Turret POV; got "
            .. tostring(sess.povAnchor) .. "/" .. tostring(sess.povMode))
        assert(sess.targetFallback == nil,
            "auto-next off must not start the fallback resolution")
        assert(#softtargetCalls42 == 0,
            "auto-next off must not re-engage any surface or object")
        assert(surfaceScanCalls42 == 0,
            "auto-next off must not enumerate surfaces; the reader ran "
            .. surfaceScanCalls42 .. " time(s)")
        local seen702H = 0
        for i = mark + 1, #fix.uiTriggeredEvents do
            local e = fix.uiTriggeredEvents[i]
            if e.control == "engageability_target"
                and X4GunneryState.normID(e.params.target) == "702" then
                seen702H = seen702H + 1
            end
        end
        assert(seen702H == 0,
            "auto-next off must not run the surface fallback (702 was queried "
            .. seen702H .. " time(s)); browser-row queries for other objects are "
            .. "legitimate")
    end

    -- I. The resolution's ENGAGEABLE requests carry exactly the checked
    -- operational turrets: a checked group whose member is not operational
    -- contributes nothing to the batch.
    do
        local groups = {
            group42("grpI_A", 27, true),
            group42("grpI_B", 28, false),
        }
        local sess = scenario42({
            slotCount42 = 2,
            operational42 = { ["600"] = true, ["702"] = true, ["98"] = true },
            sectorShips42 = { 98 }, groups = groups })
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and batches[1].members == 1
            and #batches[1].memberIDs == 1 and batches[1].memberIDs[1] == 27,
            "the batch must list only the checked operational turret; members="
            .. tostring(batches[1] and batches[1].members)
            .. " members_list=" .. table.concat(
                (batches[1] and batches[1].memberIDs) or {}, ","))
        deliver42(batches[1], { ["702"] = "1:1:1" })
        tick42()
        assert(tostring(sess.aimTargetID) == "702",
            "membership filtering must not block the resolve; aim is "
            .. tostring(sess.aimTargetID))
    end

    -- J. The root dying mid-resolution aborts the fallback to the ordinary
    -- object loss: the sweep runs and the survivor is engaged.
    do
        local sess = scenario42({
            slotCount42 = 3,                  -- 701 dead, 702/703 alive
            operational42 = { ["600"] = true, ["702"] = true, ["703"] = true,
                ["98"] = true },
            sectorShips42 = { 98 } })
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 2,
            "the loss tick must query both surviving surfaces")
        -- The whole root goes down before any result arrives.
        operational42 = { ["98"] = true }
        objectSweepCalls42 = 0
        softtargetCalls42 = {}
        tick42()
        assert(sess.targetFallback == nil,
            "a dead root must abort the fallback resolution")
        assert(objectSweepCalls42 >= 1,
            "the abort must fall through to the ordinary object sweep")
        assert(tostring(sess.aimTargetID) == "98" and tostring(sess.targetObjectID) == "98",
            "the sweep's survivor must be engaged; aim=" .. tostring(sess.aimTargetID))
        assert(sess.phase == "engaged",
            "the abort must stay engaged; phase is " .. tostring(sess.phase))
        assert(softtargetCalls42[#softtargetCalls42] == 98,
            "the survivor must become the soft target")
        assert(fix.logContains("event=auto_next_fallback action=root_lost_abort"),
            "the root-loss abort must be logged")
    end

    -- K. The planner picks a positive surface but engageTarget refuses it
    -- (the soft-target write fails): the resolution hands the choice back at
    -- the browser instead of retrying the refused engage forever.
    do
        local sess = scenario42({
            slotCount42 = 2,
            operational42 = { ["600"] = true, ["702"] = true, ["98"] = true },
            sectorShips42 = { 98 } })
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        assert(sess.targetFallback ~= nil, "setup: the fallback must be running")
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 1,
            "the loss tick must issue the single-surface batch")
        deliver42(batches[1], { ["702"] = "1:1:1" })
        local savedRefuseSoft = C.SetSofttarget
        C.SetSofttarget = function(target)
            softtargetCalls42[#softtargetCalls42 + 1] = target
            return false
        end
        softtargetCalls42 = {}
        tick42()
        C.SetSofttarget = savedRefuseSoft
        assert(softtargetCalls42[#softtargetCalls42] == 702,
            "the planner's positive pick must be attempted as an engage")
        assert(sess.phase == "target_select",
            "a refused engage must fall back to the target browser; phase is "
            .. tostring(sess.phase))
        assert(sess.aimTargetID == nil and sess.targetObjectID == nil,
            "the browser fallback must clear the lost aim and root")
        assert(sess.targetFallback == nil,
            "a refused engage must clear the fallback state")
        assert(sess.povAnchor == "turret" and sess.povMode == "manual",
            "the browser fallback must reset the view to manual Turret POV")
        assert(fix.logContains("back to target selection"),
            "the browser fallback must keep its session log line")
    end

    -- L. A control-mode switch away from direct mid-resolution drops the
    -- fallback state quietly: no ENGAGEABLE query, no engage, no browser --
    -- even with Auto-next off on the same tick, which must lose the
    -- precedence to the control-mode cancellation.
    do
        local sess = scenario42({
            slotCount42 = 2,
            operational42 = { ["600"] = true, ["702"] = true, ["98"] = true },
            sectorShips42 = { 98 } })
        API.updateAimTarget()
        assert(sess.targetFallback ~= nil, "setup: the fallback must be running")
        sess.controlMode = nil               -- e.g. a restoreDirect transition
        sess.autoNextTarget = false          -- off on the same tick; the mode
                                              -- switch must win over the
                                              -- browser fallback
        local mark = #fix.uiTriggeredEvents
        tick42()
        assert(sess.targetFallback == nil,
            "a non-direct control mode must drop the pending fallback state")
        assert(tostring(sess.aimTargetID) == "701",
            "the mode switch must not choose a replacement; aim is "
            .. tostring(sess.aimTargetID))
        assert(sess.phase ~= "target_select",
            "a mode switch must not open the target browser; phase is "
            .. tostring(sess.phase))
        assert(engageabilityEventsSince42(mark) == 0,
            "a mode switch must not issue ENGAGEABLE requests")
    end

    -- M. A surface that dies after its positive ENGAGEABLE result was
    -- accepted must never be engaged: the consume tick must skip engageTarget
    -- entirely (no hull/browser fallthrough) and restart the same-root
    -- surface stage from a fresh snapshot. 703 starts NON-OPERATIONAL, so
    -- the loss snapshot holds 702 as the only surviving alternative, the
    -- loss-tick batch targets only 702, and 703 has no cached ENGAGEABLE
    -- reading when it is made operational just before the consume tick. The
    -- consume tick's stale restart must therefore issue the new page-1 batch
    -- for 703 itself, immediately (startTargetFallback's immediate page-1
    -- query): the UI-event mark recorded right before the consume tick fails
    -- if that query were deferred to a later tick.
    do
        local mLogStart = #fix.getCapturedLog()
        local sess = scenario42({
            slotCount42 = 3,                  -- 701 (dead), 702 alive, 703 not yet operational
            operational42 = { ["600"] = true, ["702"] = true, ["98"] = true },
            sectorShips42 = { 98 } })
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        -- 1. The loss snapshot holds 702 as the only surviving alternative;
        -- 703 is not operational yet and cannot leak in.
        assert(#sess.surfaceBrowser.allSurfaces == 1
            and sess.surfaceBrowser.allSurfaces[1].componentID == 702,
            "the loss snapshot must hold 702 as the only surviving "
            .. "alternative; got " .. tostring(#sess.surfaceBrowser.allSurfaces))
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 1
            and batches[1].targets[1] == "702",
            "the loss tick must query only 702; targets="
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        -- Record this snapshot's generation before the consume tick: the
        -- stale restart must advance exactly this snapshot by one generation.
        local genBeforeRestart = sess.surfaceBrowser.generation
        -- 2. The page result proves 702 positive.
        deliver42(batches[1], { ["702"] = "1:1:1" })
        -- 3. Before the consume tick, 702 dies and 703 comes back
        -- operational; the root stays alive.
        operational42["702"] = false
        operational42["703"] = true
        softtargetCalls42 = {}
        -- 4. Mark immediately before the consume tick: the restarted page-1
        -- batch for 703 must appear between this mark and the end of the
        -- consume tick itself.
        local restartMark = #fix.uiTriggeredEvents
        tick42()
        -- 5. The consume tick must NOT engage the dead surface.
        local engaged702 = false
        for _, target in ipairs(softtargetCalls42) do
            if tostring(target) == "702" then engaged702 = true end
        end
        assert(not engaged702,
            "a surface that died after its positive result must not be engaged")
        -- 6. The fallback stays active on the surfaces stage, restarted from
        -- the fresh snapshot: the snapshot advanced by exactly one
        -- generation, the refreshed allSurfaces and the fallback's
        -- orderedIDs hold exactly the newly operational 703, and the
        -- immediate page-1 query asked for it on this same tick.
        assert(sess.surfaceBrowser.generation == genBeforeRestart + 1,
            "the stale restart must advance the snapshot by exactly one "
            .. "generation; before=" .. tostring(genBeforeRestart)
            .. " after=" .. tostring(sess.surfaceBrowser.generation))
        local restartedAllSurfaces = {}
        for _, surface in ipairs(sess.surfaceBrowser.allSurfaces or {}) do
            restartedAllSurfaces[#restartedAllSurfaces + 1] = X4GunneryState.normID(surface.componentID)
        end
        assert(table.concat(restartedAllSurfaces, ",") == "703",
            "the restarted snapshot must hold exactly the newly operational "
            .. "703; got " .. table.concat(restartedAllSurfaces, ","))
        assert(sess.targetFallback ~= nil
            and sess.targetFallback.stage == "surfaces"
            and sess.targetFallback.page == 1,
            "the stale restart must keep the resolution active on surfaces "
            .. "page 1; stage="
            .. tostring(sess.targetFallback and sess.targetFallback.stage))
        assert(#sess.targetFallback.orderedIDs == 1
            and X4GunneryState.normID(sess.targetFallback.orderedIDs[1]) == "703",
            "the restarted candidates must hold exactly 703; ids="
            .. table.concat(sess.targetFallback.orderedIDs, ","))
        local restartBatches = batchesSince42(restartMark)
        assert(#restartBatches == 1 and #restartBatches[1].targets == 1
            and restartBatches[1].targets[1] == "703",
            "the consume tick itself must issue the fresh page-1 batch for "
            .. "703, which has no cached reading; batches="
            .. tostring(#restartBatches))
        assert(#softtargetCalls42 == 0,
            "the stale restart must make no target choice; soft-target calls="
            .. tostring(#softtargetCalls42))
        assert(sess.phase == "engaged" and tostring(sess.aimTargetID) == "701"
            and tostring(sess.targetObjectID) == "600",
            "the stale restart must choose nothing; aim="
            .. tostring(sess.aimTargetID) .. " root=" .. tostring(sess.targetObjectID))
        assert(objectSweepCalls42 == 0,
            "a dead surface must not escalate to the object sweep or browser; "
            .. objectSweepCalls42 .. " sweep call(s)")
        local restarts = 0
        for i = mLogStart + 1, #fix.getCapturedLog() do
            if string.find(fix.getCapturedLog()[i],
                "event=auto_next_fallback action=stale_surface_restart", 1, true)
            then restarts = restarts + 1 end
        end
        assert(restarts == 1,
            "the stale/dead surface restart must be logged exactly once")
        -- 7. The new batch's positive result makes 703 engageable.
        deliver42(restartBatches[1], { ["703"] = "1:1:1" })
        -- 8. The next consume tick engages 703.
        softtargetCalls42 = {}
        tick42()
        assert(tostring(sess.aimTargetID) == "703"
            and tostring(sess.targetObjectID) == "600",
            "the next consume tick must engage the surviving 703; aim="
            .. tostring(sess.aimTargetID))
        assert(sess.phase == "engaged" and sess.targetFallback == nil,
            "the 703 engage must stay engaged and clear the fallback")
        assert(softtargetCalls42[#softtargetCalls42] == 703,
            "the engaged 703 must become the soft target")
    end

    -- N. Issue #45 Task 5B2a: when surfaces and the hull prove zero, the
    -- objects stage keeps readTargetCandidates() ranking but must drop
    -- non-operational candidates up front. The fixture is deliberately
    -- discriminating: 98 (NON-operational), 99 and 100 (operational) each
    -- get a distinct distance, so the raw ranking 98, 99, 100 is decided by
    -- distance alone -- never by an accidental priority/name tie (the
    -- constant-distance stub would tie them and the name tiebreak alone
    -- yields 100, 98, 99). Dropping dead 98 must leave orderedIDs exactly
    -- 99, 100 in that relative order; the ENGAGEABLE batch must ride exactly
    -- 99, 100 and never 98; and with 99 positive and 100 proven zero the
    -- ranked-first positive 99 is what gets engaged.
    do
        -- The block-level distance stub returns one constant for every
        -- object, so override it here: distinct distances make 98, 99, 100
        -- the only possible ranking order of the sector sweep.
        local savedDistN = C.GetDistanceBetween
        C.GetDistanceBetween = function(_, component)
            local n = tonumber(tostring(component))
            if n == 98 then return 1000 end
            if n == 99 then return 2000 end
            if n == 100 then return 3000 end
            return 1000
        end
        local sess = scenario42({
            slotCount42 = 1,                  -- only the dead 701 remains
            operational42 = { ["600"] = true, ["99"] = true, ["100"] = true },
            sectorShips42 = { 98, 99, 100 } })   -- 98 is NON-operational
        local mark = reachObjects42(sess)
        local objectIDs = {}
        for _, v in ipairs(sess.targetFallback.orderedIDs) do
            objectIDs[#objectIDs + 1] = X4GunneryState.normID(v)
        end
        assert(table.concat(objectIDs, ",") == "99,100",
            "the objects stage must keep the readTargetCandidates() ranking "
            .. "98, 99, 100 with only the non-operational 98 dropped, so "
            .. "exactly 99, 100 survive in that relative order; ids="
            .. table.concat(objectIDs, ","))
        tick42()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 2
            and batches[1].targets[1] == "99" and batches[1].targets[2] == "100",
            "the objects ENGAGEABLE batch must query exactly 99, 100 and "
            .. "never the non-operational 98; targets="
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        -- Settle the WHOLE batch: 99 proven positive, 100 proven zero.
        deliver42(batches[1], { ["99"] = "1:1:1", ["100"] = "0:1:1" })
        softtargetCalls42 = {}
        tick42()
        assert(tostring(sess.aimTargetID) == "99"
            and tostring(sess.targetObjectID) == "99",
            "the ranked-first positive 99 must be engaged; aim="
            .. tostring(sess.aimTargetID) .. " root="
            .. tostring(sess.targetObjectID))
        assert(sess.phase == "engaged" and sess.targetFallback == nil,
            "the object engage must stay engaged and clear the fallback")
        assert(softtargetCalls42[#softtargetCalls42] == 99,
            "the engaged object 99 must become the soft target")
        C.GetDistanceBetween = savedDistN
    end

    -- O. Issue #45 Task 5B2b: an objects-stage target that dies after its
    -- positive ENGAGEABLE result was accepted must never be engaged. The
    -- consume tick must skip engageTarget entirely (no soft target, no
    -- browser fallthrough), rebuild the ranked objects list from a fresh
    -- sweep -- where the dead object has dropped out -- and resume the
    -- ordinary next-tick evaluation from page 1.
    do
        local oLogStart = #fix.getCapturedLog()
        -- Distinct distances make the sector ranking 98, 99 distance-decided,
        -- never a priority/name tie (as in 42N).
        local savedDistO = C.GetDistanceBetween
        C.GetDistanceBetween = function(_, component)
            local n = tonumber(tostring(component))
            if n == 98 then return 1000 end
            if n == 99 then return 2000 end
            return 1000
        end
        local sess = scenario42({
            slotCount42 = 1,                  -- only the dead 701 remains
            operational42 = { ["600"] = true, ["98"] = true },  -- 99 is NON-operational
            sectorShips42 = { 98, 99 } })
        local mark = reachObjects42(sess)
        local entryIDs = {}
        for _, v in ipairs(sess.targetFallback.orderedIDs) do
            entryIDs[#entryIDs + 1] = X4GunneryState.normID(v)
        end
        assert(table.concat(entryIDs, ",") == "98",
            "the objects stage must hold 98 as the only operational ordinary "
            .. "candidate; ids=" .. table.concat(entryIDs, ","))
        tick42()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 1
            and batches[1].targets[1] == "98",
            "the objects ENGAGEABLE batch must query exactly the operational "
            .. "98; targets="
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        -- 98 proves positive ... then dies before the consume tick, while
        -- 99 comes back operational.
        deliver42(batches[1], { ["98"] = "1:1:1" })
        operational42["98"] = false
        operational42["99"] = true
        softtargetCalls42 = {}
        tick42()
        -- 1. The dead 98 must NOT be engaged.
        local engaged98 = false
        for _, target in ipairs(softtargetCalls42) do
            if tostring(target) == "98" then engaged98 = true end
        end
        assert(not engaged98,
            "an object that died after its positive result must not be engaged")
        -- 2. The fallback stays active on the objects stage page 1, rebuilt
        -- from the fresh sweep: 98 has dropped out and exactly 99 remains.
        assert(sess.targetFallback ~= nil
            and sess.targetFallback.stage == "objects"
            and sess.targetFallback.page == 1,
            "the stale-object restart must keep the resolution active on "
            .. "objects page 1; stage="
            .. tostring(sess.targetFallback and sess.targetFallback.stage)
            .. " page=" .. tostring(sess.targetFallback and sess.targetFallback.page))
        local objectIDs = {}
        for _, v in ipairs(sess.targetFallback.orderedIDs) do
            objectIDs[#objectIDs + 1] = X4GunneryState.normID(v)
        end
        assert(table.concat(objectIDs, ",") == "99",
            "the rebuilt objects list must hold exactly the surviving "
            .. "operational 99; ids=" .. table.concat(objectIDs, ","))
        -- 3. No browser fallback and no target choice on that tick.
        assert(sess.phase == "engaged" and tostring(sess.aimTargetID) == "701"
            and tostring(sess.targetObjectID) == "600",
            "the stale-object restart must choose nothing and stay engaged; "
            .. "phase=" .. tostring(sess.phase) .. " aim="
            .. tostring(sess.aimTargetID) .. " root="
            .. tostring(sess.targetObjectID))
        assert(#softtargetCalls42 == 0,
            "the stale-object restart must make no target choice; soft-target "
            .. "calls=" .. tostring(#softtargetCalls42))
        -- 4. The next tick evaluates the surviving 99 ...
        mark = #fix.uiTriggeredEvents
        tick42()
        batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 1
            and batches[1].targets[1] == "99",
            "the tick after the restart must evaluate the surviving 99; "
            .. "targets="
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        deliver42(batches[1], { ["99"] = "1:1:1" })
        softtargetCalls42 = {}
        tick42()
        -- 5. ... and the following consume tick engages it.
        assert(tostring(sess.aimTargetID) == "99"
            and tostring(sess.targetObjectID) == "99",
            "the surviving operational 99 must be engaged; aim="
            .. tostring(sess.aimTargetID) .. " root="
            .. tostring(sess.targetObjectID))
        assert(sess.phase == "engaged" and sess.targetFallback == nil,
            "the object engage must stay engaged and clear the fallback")
        assert(softtargetCalls42[#softtargetCalls42] == 99,
            "the engaged object 99 must become the soft target")
        local restarts = 0
        for i = oLogStart + 1, #fix.getCapturedLog() do
            if string.find(fix.getCapturedLog()[i],
                "event=auto_next_fallback action=stale_object_restart", 1, true)
            then restarts = restarts + 1 end
        end
        assert(restarts == 1,
            "the stale-object restart must be logged exactly once")
        C.GetDistanceBetween = savedDistO
    end

    -- P. Issue #45 Task 5B2c: an objects-stage candidate that dies AFTER the
    -- stage was built, while its ENGAGEABLE result is still pending, must not
    -- hold its batch slot open forever. The consume tick would otherwise keep
    -- handing the planner a page whose dead member can never settle: the
    -- planner yields "wait" on the pending reading and never reaches the
    -- surviving sibling's positive proof. The fix detects the death before
    -- paging/querying/planning, rebuilds the ranked objects list exactly as
    -- the stage entry does (the dead object drops out), resets page 1, logs
    -- one restart event, and lets ordinary evaluation resume next tick --
    -- where the sibling's cached positive reading may be reused without a
    -- new transport batch.
    do
        local pLogStart = #fix.getCapturedLog()
        -- Distinct distances make the sector ranking 98, 99 distance-decided,
        -- never a priority/name tie (as in 42N/42O).
        local savedDistP = C.GetDistanceBetween
        C.GetDistanceBetween = function(_, component)
            local n = tonumber(tostring(component))
            if n == 98 then return 1000 end
            if n == 99 then return 2000 end
            return 1000
        end
        local sess = scenario42({
            slotCount42 = 1,                  -- only the dead 701 remains
            operational42 = { ["600"] = true, ["98"] = true, ["99"] = true },
            sectorShips42 = { 98, 99 } })
        local mark = reachObjects42(sess)
        local objectIDs = {}
        for _, v in ipairs(sess.targetFallback.orderedIDs) do
            objectIDs[#objectIDs + 1] = X4GunneryState.normID(v)
        end
        assert(table.concat(objectIDs, ",") == "98,99",
            "the objects stage must rank the operational candidates 98, 99; "
            .. "ids=" .. table.concat(objectIDs, ","))
        -- 1. Issue the one objects ENGAGEABLE batch for 98, 99.
        tick42()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 2
            and batches[1].targets[1] == "98" and batches[1].targets[2] == "99",
            "the objects ENGAGEABLE batch must query exactly 98, 99; targets="
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        -- 2. After the batch is issued, 98 dies; its reading will never settle.
        operational42["98"] = false
        -- 3. 99 proves positive, 98 is left unresolved; complete the batch the
        -- standard fixture way (per-target results, then batch complete).
        deliver42(batches[1], { ["99"] = "1:1:1" })
        softtargetCalls42 = {}
        local restartMark = #fix.uiTriggeredEvents
        tick42()
        -- 4. The consume tick must detect the dead 98 BEFORE planner
        -- evaluation: the list rebuilds to exactly the surviving 99, the
        -- stage holds on objects page 1, nothing is chosen, no browser
        -- fallback, and no new ENGAGEABLE batch rides this tick.
        assert(sess.targetFallback ~= nil
            and sess.targetFallback.stage == "objects"
            and sess.targetFallback.page == 1,
            "the stale-object restart must keep the resolution active on "
            .. "objects page 1; stage="
            .. tostring(sess.targetFallback and sess.targetFallback.stage)
            .. " page=" .. tostring(sess.targetFallback and sess.targetFallback.page))
        objectIDs = {}
        for _, v in ipairs(sess.targetFallback.orderedIDs) do
            objectIDs[#objectIDs + 1] = X4GunneryState.normID(v)
        end
        assert(table.concat(objectIDs, ",") == "99",
            "the dead 98 must be dropped from the objects list before planner "
            .. "evaluation; ids=" .. table.concat(objectIDs, ","))
        assert(#softtargetCalls42 == 0,
            "the stale-object restart must make no target choice; soft-target "
            .. "calls=" .. tostring(#softtargetCalls42))
        assert(sess.phase == "engaged" and tostring(sess.aimTargetID) == "701"
            and tostring(sess.targetObjectID) == "600",
            "the stale-object restart must choose nothing and stay engaged; "
            .. "phase=" .. tostring(sess.phase) .. " aim="
            .. tostring(sess.aimTargetID) .. " root="
            .. tostring(sess.targetObjectID))
        assert(#batchesSince42(restartMark) == 0,
            "the restart tick must return before querying; batches="
            .. tostring(#batchesSince42(restartMark)))
        local restarts = 0
        for i = pLogStart + 1, #fix.getCapturedLog() do
            if string.find(fix.getCapturedLog()[i],
                "event=auto_next_fallback action=stale_object_list_restart", 1, true)
            then restarts = restarts + 1 end
        end
        assert(restarts == 1,
            "the stale-object-list restart must be logged exactly once; saw "
            .. restarts)
        -- 5. On the following tick the cached positive reading for 99 is
        -- reused without a new transport batch, and 99 is engaged.
        mark = #fix.uiTriggeredEvents
        softtargetCalls42 = {}
        tick42()
        assert(#batchesSince42(mark) == 0,
            "the cached positive reading for 99 must be reused; no new "
            .. "ENGAGEABLE batch may be issued")
        assert(tostring(sess.aimTargetID) == "99"
            and tostring(sess.targetObjectID) == "99",
            "the surviving 99 must be engaged from its cached positive "
            .. "reading; aim=" .. tostring(sess.aimTargetID)
            .. " root=" .. tostring(sess.targetObjectID))
        assert(sess.phase == "engaged" and sess.targetFallback == nil,
            "the cached engage must stay engaged and clear the fallback")
        assert(softtargetCalls42[#softtargetCalls42] == 99,
            "the engaged object 99 must become the soft target")
        C.GetDistanceBetween = savedDistP
    end

    -- Q. Issue #45 Task 5B2c (settled-zero half): a dead objects-stage
    -- candidate whose cached result settled to ZERO must not exhaust the
    -- fallback to the browser (the pre-fix planner reads its stale zero,
    -- concludes "none", and falls back even though a newly operational
    -- object exists). The consume tick must keep the fallback active on
    -- objects page 1 with a refreshed list, and the next tick must query
    -- and engage the survivor.
    do
        local sess = scenario42({
            slotCount42 = 1,                  -- only the dead 701 remains
            operational42 = { ["600"] = true, ["98"] = true },  -- 99 NON-operational
            sectorShips42 = { 98, 99 } })
        local mark = reachObjects42(sess)
        tick42()
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 1
            and batches[1].targets[1] == "98",
            "the objects ENGAGEABLE batch must query only the operational "
            .. "98; targets="
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        -- 98 settles as a proven zero, then dies while 99 comes operational.
        deliver42(batches[1], { ["98"] = "0:1:1" })
        operational42["98"] = false
        operational42["99"] = true
        softtargetCalls42 = {}
        tick42()
        assert(sess.targetFallback ~= nil
            and sess.targetFallback.stage == "objects"
            and sess.targetFallback.page == 1,
            "a dead settled-zero candidate must not exhaust to the browser; "
            .. "stage=" .. tostring(sess.targetFallback and sess.targetFallback.stage)
            .. " page=" .. tostring(sess.targetFallback and sess.targetFallback.page))
        local objectIDs = {}
        for _, v in ipairs(sess.targetFallback.orderedIDs) do
            objectIDs[#objectIDs + 1] = X4GunneryState.normID(v)
        end
        assert(table.concat(objectIDs, ",") == "99",
            "the refreshed objects list must hold exactly the newly "
            .. "operational 99; ids=" .. table.concat(objectIDs, ","))
        assert(#softtargetCalls42 == 0,
            "the refresh tick must not engage anything; soft-target calls="
            .. tostring(#softtargetCalls42))
        mark = #fix.uiTriggeredEvents
        tick42()
        batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 1
            and batches[1].targets[1] == "99",
            "the tick after the refresh must query the surviving 99; targets="
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        deliver42(batches[1], { ["99"] = "1:1:1" })
        softtargetCalls42 = {}
        tick42()
        assert(tostring(sess.aimTargetID) == "99" and sess.targetFallback == nil,
            "the surviving 99 must be engaged and clear the fallback; aim="
            .. tostring(sess.aimTargetID))
        assert(softtargetCalls42[#softtargetCalls42] == 99,
            "the engaged object 99 must become the soft target")
    end

    -- R. Issue #45 Task 5C: turning Auto-next off while a resolution is in
    -- flight cancels the asynchronous fallback: the next tick clears
    -- targetFallback, hands the choice back at the target browser through the
    -- existing browser-fallback path, and makes no soft-target engage call --
    -- even though a positive ENGAGEABLE reading is sitting in the cache, ready
    -- for a fallback that the player has just switched off.
    do
        local sess = scenario42({
            slotCount42 = 2,
            operational42 = { ["600"] = true, ["702"] = true, ["98"] = true },
            sectorShips42 = { 98 } })
        sess.povAnchor, sess.povMode = "target", "cinematic"
        -- 1. Start the surface-loss fallback with Auto-next enabled and prove
        -- it is active on surfaces page 1 with the page-1 batch out the door.
        local mark = #fix.uiTriggeredEvents
        API.updateAimTarget()
        assert(sess.targetFallback ~= nil,
            "setup: a surface loss with auto-next on must start the resolution")
        assert(sess.targetFallback.stage == "surfaces"
            and sess.targetFallback.page == 1,
            "setup: the resolution must sit on surfaces page 1; stage="
            .. tostring(sess.targetFallback.stage)
            .. " page=" .. tostring(sess.targetFallback.page))
        local batches = batchesSince42(mark)
        assert(#batches == 1 and #batches[1].targets == 1
            and batches[1].targets[1] == "702",
            "the loss tick must issue the single-surface batch; targets="
            .. table.concat(batches[1] and batches[1].targets or {}, ","))
        -- 2. The positive reading settles in the cache ... and the player
        -- disables Auto-next before the consume tick.
        deliver42(batches[1], { ["702"] = "1:1:1" })
        sess.autoNextTarget = false
        softtargetCalls42 = {}
        tick42()
        -- 3. The cancelled resolution must clear the fallback, hand the
        -- choice back at the browser, and engage nothing.
        assert(sess.targetFallback == nil,
            "turning auto-next off mid-resolution must clear the fallback; "
            .. "stage=" .. tostring(sess.targetFallback and sess.targetFallback.stage))
        assert(sess.phase == "target_select",
            "the cancelled resolution must hand the choice back at the target "
            .. "browser; phase is " .. tostring(sess.phase))
        assert(sess.aimTargetID == nil and sess.targetObjectID == nil,
            "the browser fallback must clear the lost aim and root; aim="
            .. tostring(sess.aimTargetID) .. " root=" .. tostring(sess.targetObjectID))
        assert(sess.povAnchor == "turret" and sess.povMode == "manual",
            "the browser fallback must reset the view to manual Turret POV; got "
            .. tostring(sess.povAnchor) .. "/" .. tostring(sess.povMode))
        assert(#softtargetCalls42 == 0,
            "the cancellation must make no soft-target engage call, even with "
            .. "a positive reading cached; soft-target calls="
            .. tostring(#softtargetCalls42))
        assert(fix.logContains("event=auto_next_fallback action=auto_next_off_cancel"),
            "the auto-next-off cancellation must be logged")
    end

    -- Restore the pre-block stubs (nil hands C back to its fallbacks).
    C.IsComponentClass = savedClass42
    C.GetNumUpgradeSlots = savedNumSlots42
    C.GetUpgradeSlotCurrentComponent = savedSlotComp42
    C.GetUpgradeSlotCurrentMacro = savedSlotMacro42
    C.GetComponentName = savedSetName42
    C.GetDistanceBetween = savedDist42
    C.GetContextByClass = savedCtxClass42
    C.IsComponentOperational = savedOperational42
    C.SetSofttarget = savedSoft42
    GetMacroData = savedMacroData42
    GetComponentData = savedCompData42
    GetContainedShips = savedShips42
    GetContainedStations = savedStations42
    GetPlayerContextByClass = savedSector42
    AddUITriggeredEvent = savedAdd42
end

print("runtime auto-next tests passed")
