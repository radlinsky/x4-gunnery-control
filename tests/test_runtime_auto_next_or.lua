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

-- Scenarios O-R of block 42.
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

print("runtime auto-next or tests passed")
