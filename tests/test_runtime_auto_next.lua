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
