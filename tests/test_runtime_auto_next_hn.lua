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

-- Scenarios H-N of block 42.
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

print("runtime auto-next hn tests passed")
