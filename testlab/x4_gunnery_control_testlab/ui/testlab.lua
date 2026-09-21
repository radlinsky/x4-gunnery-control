-- Developer-only current-ship turret sweep. The production extension owns all
-- turret discovery and mutations; this companion only drives its narrow API.
local State = X4GunneryTestLabState
local menu = { name = "X4GunneryTestLab", uixID = "x4_gunnery_control_testlab" }
local sweep, inspectStarted, nextPoll, stableSamples, unstableSamples, technical, targetBefore, targetPreserved, closing, suppressReopen = nil, nil, nil, 0, 0, nil, nil, nil, false, false
local scenarioActionStatus, scenarioRequestSerial, pendingScenario, remoteScenarioReady = nil, 0, nil, false
local finishGroups, emitSummary, returnToGunnery

local function text(id) return ReadText(20992, id) end
local function api() return X4GunneryControlAPI end
local function safe(value) return tostring(value or ""):gsub("[^%w_.%-]", "_") end
local function trim(value) return tostring(value or ""):match("^%s*(.-)%s*$") end
-- Engine real time is seconds since X4 boot and survives Reload UI. Capture it
-- for audit and again at each click for correlation; Lua globals do not survive
-- Reload UI and therefore cannot be used as a generation counter.
local scenarioLoadTime = GetCurRealTime()
local function clockToken(value)
    return tostring(math.floor((tonumber(value) or 0) * 1000000 + 0.5))
end

local function log(event, fields)
    local parts = { "[X4GC TEST]", "event=" .. event }
    for key, value in pairs(fields or {}) do parts[#parts + 1] = key .. "=" .. safe(value) end
    table.sort(parts, function(a, b) return a < b end)
    DebugError(table.concat(parts, " "))
end

-- Fire-control observability. MD owns the sample loop and emits every log line
-- (md/x4_gunnery_control_testlab_observe.xml); this side is only the master
-- switch, the marker, and the two facts MD cannot see for itself. Off by
-- default, so installing the Test Lab does not flood debug.log on its own.
local observing = false
local lastObservedAimTarget, observedAimActiveSeconds, observedAimLastTick, observedAimSettled
local suppressedObservedAimTarget

-- The engine SOFT target and the session's aimTargetID are the whole reason
-- any Lua runs here: MD has player.target but no soft-target equivalent
-- (scriptproperties.xml has no player.softtarget at all), and the mod session is
-- Lua-side state. Both come from the main mod's already-public test API
-- (ui/gunnery_control.lua:1121 getSession, :1169 getTestSofttarget), so the
-- shipped mod is untouched and nothing here needs ffi -- this file deliberately
-- contains no require("ffi") and no C. calls, and that stays true.
local function pushObserveState()
    if not observing then return end
    local bridge = api()
    if not bridge then return end
    local payload = {}
    local soft = bridge.getTestSofttarget and bridge.getTestSofttarget()
    -- getTestSofttarget reports "0" for "nothing selected". Sending that would
    -- make MD prefer a dead id over player.target, so it is simply omitted.
    if soft and soft.id and soft.id ~= "0"
            and tostring(soft.id) ~= suppressedObservedAimTarget then
        payload.softtgt = ConvertStringToLuaID(soft.id)
    end
    -- No session is the ordinary free-play case, not an error: MD then logs
    -- player.target and prefer stays false.
    local session = bridge.getSession and bridge.getSession()
    local aimTarget = session and session.aimTargetID and tostring(session.aimTargetID) or nil
    if suppressedObservedAimTarget and aimTarget
            and aimTarget ~= suppressedObservedAimTarget then
        suppressedObservedAimTarget = nil
    end
    if session then
        if aimTarget and aimTarget ~= suppressedObservedAimTarget then
            payload.aimtgt = ConvertStringToLuaID(aimTarget)
        end
    end
    AddUITriggeredEvent("X4GunneryTestLabObserve", "observe_state", payload)
    -- Geometry tests should not depend on the owner switching menus and
    -- clicking Mark at the right instant. Once MD has the new aim target,
    -- automatically request the same one-shot engageability snapshot the button
    -- would have produced. String comparison normalises ffi cdata/number forms.
    local now = getElapsedTime()
    if aimTarget and aimTarget ~= suppressedObservedAimTarget
            and aimTarget ~= lastObservedAimTarget then
        lastObservedAimTarget = aimTarget
        observedAimActiveSeconds, observedAimLastTick, observedAimSettled = 0, now, false
        AddUITriggeredEvent("X4GunneryTestLabObserve", "observe_mark")
        log("observe", { action = "auto_mark_initial", target = aimTarget })
    elseif aimTarget and not observedAimSettled and observedAimLastTick then
        if not (bridge.isGamePaused and bridge.isGamePaused()) then
            observedAimActiveSeconds = observedAimActiveSeconds + (now - observedAimLastTick)
        end
        observedAimLastTick = now
        if observedAimActiveSeconds >= 20 then
            observedAimSettled = true
            AddUITriggeredEvent("X4GunneryTestLabObserve", "observe_mark")
            log("observe", { action = "auto_mark_settled", target = aimTarget, active_seconds = observedAimActiveSeconds })
        end
    end
    -- Self-rescheduling at the MD sample rate, the pattern the main mod's
    -- session watchdog uses (ui/gunnery_control.lua:2224) because it runs with
    -- no displayed frame. Whether it keeps firing with every menu closed is
    -- unverified; if it stops, MD still writes the full STATE and historical [X4GC TEST SOLUTION] block and only softtgt/prefer go stale. Degrades, does not break.
    if Helper then Helper.addDelayedOneTimeCallbackOnUpdate(pushObserveState, false, getElapsedTime() + 1.0) end
end

local function setObserving(enabled, suppressAimTarget)
    observing = enabled
    lastObservedAimTarget, observedAimActiveSeconds, observedAimLastTick, observedAimSettled = nil, nil, nil, nil
    suppressedObservedAimTarget = enabled and suppressAimTarget and tostring(suppressAimTarget) or nil
    AddUITriggeredEvent("X4GunneryTestLabObserve", "observe_toggle", { enabled = enabled })
    log("observe", { action = enabled and "on" or "off" })
    if enabled then pushObserveState() end
end

-- Scenario spec: the fixture for the next live test, authored on disk in
-- ui/scenario_spec.lua and replayed into MD on every UI load. Every field is
-- validated here rather than in MD, because a bad value in Lua is a log line
-- while a bad value in MD is a silently dead cue.
local function validateSpec(raw)
    if type(raw) ~= "table" then return nil, "spec is not a table" end
    if type(raw.id) ~= "string" or raw.id == "" then return nil, "spec.id must be a non-empty string" end
    if raw.id:find(":", 1, true) then return nil, "spec.id must not contain ':'" end
    if raw.enabled ~= true and raw.enabled ~= false then return nil, "spec.enabled must be true or false" end
    if type(raw.groups) ~= "table" then return nil, "spec.groups must be a list" end
    local groups = {}
    for index, group in ipairs(raw.groups) do
        local where = "groups[" .. index .. "]"
        if type(group) ~= "table" then return nil, where .. " is not a table" end
        if type(group.macro) ~= "string" or group.macro == "" then return nil, where .. ".macro must be a non-empty string" end
        if type(group.faction) ~= "string" or group.faction == "" then return nil, where .. ".faction must be a non-empty string" end
        if type(group.count) ~= "number" or group.count < 1 or group.count > 12
                or group.count ~= math.floor(group.count) then
            return nil, where .. ".count must be an integer from 1 to 12"
        end
        if type(group.distance) ~= "number" or group.distance ~= group.distance
                or group.distance == math.huge or group.distance == -math.huge then
            return nil, where .. ".distance must be a finite number"
        end
        local behaviour = group.behaviour or "wait"
        if behaviour ~= "wait" and behaviour ~= "attack" and behaviour ~= "none" then
            return nil, where .. ".behaviour must be wait, attack or none"
        end
        local role = tostring(group.role or "")
        if role ~= "" and role ~= "shooter" then
            return nil, where .. ".role must be empty or shooter"
        end
        if group.preserveOrientation ~= nil and type(group.preserveOrientation) ~= "boolean" then
            return nil, where .. ".preserveOrientation must be a boolean"
        end
        local numbers = {}
        for _, field in ipairs({ "spread", "x", "y", "yaw", "pitch", "roll" }) do
            local value = group[field]
            if value == nil then value = 0 end
            if type(value) ~= "number" or value ~= value
                    or value == math.huge or value == -math.huge then
                return nil, where .. "." .. field .. " must be a finite number"
            end
            numbers[field] = value
        end
        local loadout = tostring(group.loadout or "")
        local expected = { expectedWeapons = -1, expectedTurrets = -1, expectedMissileTurrets = -1 }
        for field in pairs(expected) do
            local value = group[field]
            if loadout ~= "" then
                if type(value) ~= "number" or value < 0 or value ~= math.floor(value) then
                    return nil, where .. "." .. field .. " must be a non-negative integer when loadout is set"
                end
                expected[field] = value
            elseif value ~= nil then
                return nil, where .. "." .. field .. " requires loadout"
            end
        end
        if loadout ~= "" and expected.expectedWeapons < expected.expectedTurrets then
            return nil, where .. ".expectedWeapons must be greater than or equal to expectedTurrets"
        end
        if role == "shooter" and loadout == "" then
            return nil, where .. ".loadout must be set for role=shooter"
        end
        groups[#groups + 1] = {
            label = tostring(group.label or ("group" .. index)),
            macro = group.macro,
            faction = group.faction,
            count = group.count,
            distance = group.distance,
            spread = numbers.spread,
            x = numbers.x,
            y = numbers.y,
            behaviour = behaviour,
            hostile = group.hostile == true,
            holdFire = group.holdFire == true,
            stripDefenceUnits = group.stripDefenceUnits == true,
            repairGuard = group.repairGuard == true,
            yaw = numbers.yaw,
            pitch = numbers.pitch,
            roll = numbers.roll,
            preserveOrientation = group.preserveOrientation == true,
            role = role,
            loadout = loadout,
            expectedWeapons = expected.expectedWeapons,
            expectedTurrets = expected.expectedTurrets,
            expectedMissileTurrets = expected.expectedMissileTurrets,
        }
    end
    if #groups == 0 then return nil, "spec.groups is empty" end
    local setup
    if raw.setup ~= nil then
        if type(raw.setup) ~= "table" then return nil, "spec.setup must be a table" end
        for _, field in ipairs({ "shipMacro", "shipLabel", "turretLabel" }) do
            if type(raw.setup[field]) ~= "string" or raw.setup[field] == "" then
                return nil, "spec.setup." .. field .. " must be a non-empty string"
            end
        end
        local singleTurretMacro
        if raw.setup.singleTurretMacro ~= nil then
            if type(raw.setup.singleTurretMacro) ~= "string" or raw.setup.singleTurretMacro == "" then
                return nil, "spec.setup.singleTurretMacro must be a non-empty string"
            end
            singleTurretMacro = raw.setup.singleTurretMacro
        end
        local selectAll = raw.setup.selectAll == true
        local turretGroup
        if selectAll then
            if type(raw.setup.turretGroup) ~= "string" or raw.setup.turretGroup == "" then
                return nil, "spec.setup.turretGroup must be a non-empty string"
            end
            turretGroup = raw.setup.turretGroup
        else
            local namedGroup
            if raw.setup.turretGroup ~= nil then
                if type(raw.setup.turretGroup) ~= "string" or raw.setup.turretGroup == "" then
                    return nil, "spec.setup.turretGroup must be a non-empty string"
                end
                namedGroup = raw.setup.turretGroup
            end
            if namedGroup and singleTurretMacro then
                return nil, "spec.setup.turretGroup and spec.setup.singleTurretMacro are mutually exclusive"
            end
            if namedGroup then
                turretGroup = namedGroup
            elseif not singleTurretMacro then
                return nil, "spec.setup needs either turretGroup or singleTurretMacro"
            end
        end
        if type(raw.setup.expectedTurrets) ~= "number" or raw.setup.expectedTurrets < 1 then
            return nil, "spec.setup.expectedTurrets must be a positive number"
        end
        if singleTurretMacro and not selectAll and raw.setup.expectedTurrets ~= 1 then
            return nil, "spec.setup.singleTurretMacro requires expectedTurrets = 1"
        end
        local expectedMemberMacros = {}
        local rawExpectedMemberMacros = raw.setup.expectedMemberMacros
        if rawExpectedMemberMacros ~= nil then
            if type(rawExpectedMemberMacros) ~= "table" then
                return nil, "spec.setup.expectedMemberMacros must be a list"
            end
            for index, macro in ipairs(rawExpectedMemberMacros) do
                if type(macro) ~= "string" or macro == "" then
                    return nil, "spec.setup.expectedMemberMacros[" .. index .. "] must be a non-empty string"
                end
                expectedMemberMacros[#expectedMemberMacros + 1] = macro
            end
            if #expectedMemberMacros ~= math.floor(raw.setup.expectedTurrets) then
                return nil, "spec.setup.expectedMemberMacros must match expectedTurrets"
            end
            table.sort(expectedMemberMacros)
        end
        setup = {
            remote = raw.setup.remote == true,
            shipMacro = raw.setup.shipMacro,
            shipLabel = raw.setup.shipLabel,
            turretGroup = turretGroup,
            turretLabel = raw.setup.turretLabel,
            expectedTurrets = math.floor(raw.setup.expectedTurrets),
            expectedMemberMacros = expectedMemberMacros,
            selectAll = selectAll,
            singleTurretMacro = singleTurretMacro,
        }
    end
    local location
    if raw.location ~= nil then
        if type(raw.location) ~= "table" then return nil, "spec.location must be a table" end
        if type(raw.location.sectorMacro) ~= "string" or raw.location.sectorMacro == "" then
            return nil, "spec.location.sectorMacro must be a non-empty string"
        end
        for _, field in ipairs({ "x", "y", "z" }) do
            if type(raw.location[field]) ~= "number" then
                return nil, "spec.location." .. field .. " must be a number"
            end
        end
        location = {
            sectorMacro = raw.location.sectorMacro,
            x = raw.location.x, y = raw.location.y, z = raw.location.z,
        }
    end
    if setup and setup.remote and not location then
        return nil, "remote setup requires spec.location"
    end
    return {
        id = raw.id, enabled = raw.enabled, groups = groups,
        setup = setup, location = location,
    }
end

-- The spec file is a plain data literal, but it is hand-edited by an agent, so
-- a syntax error or a typo must degrade to a log line rather than take the
-- whole Test Lab menu down with it.
local function loadSpec()
    if X4GunneryTestLabScenarioSpec == nil then return nil, nil end
    local ok, spec, reason = pcall(validateSpec, X4GunneryTestLabScenarioSpec)
    if not ok then return nil, "spec load raised: " .. tostring(spec) end
    if not spec then return nil, tostring(reason or "spec rejected") end
    return spec, nil
end

local scenarioSpec, scenarioSpecError = loadSpec()

local function scenarioSpecLabel()
    if scenarioSpecError then return "invalid (" .. scenarioSpecError .. ")" end
    if not scenarioSpec then return "none" end
    return scenarioSpec.id .. (scenarioSpec.enabled and " (enabled)" or " (disabled)")
end

-- A remote fixture's player ship is disposable only while the owner is not
-- aboard it. Keep this identity check deliberately narrower than
-- resolveExactGroup(): damaged/missing turrets must not make an occupied
-- spawned ship suddenly safe to destroy.
local function occupiedRemoteShooter()
    local setup, bridge = scenarioSpec and scenarioSpec.setup, api()
    if not setup or not setup.remote or not bridge or not bridge.getCurrentShipSweepReadOnly then
        return nil
    end
    local ship = bridge.getCurrentShipSweepReadOnly()
    if not ship or ship.macro ~= setup.shipMacro
            or trim(ship.name) ~= trim(setup.shipLabel) then
        return nil
    end
    return tostring(ship.id)
end

-- MD cannot be handed a nested table: the only live-tested Lua->MD payload is a
-- flat table of scalars. The spec is therefore streamed as begin / one event per
-- group / commit. See the transport note in the MD script.
local function sendScenarioSpec(force, requestId)
    if scenarioSpecError then
        log("scenario_spec", { action = "rejected", reason = scenarioSpecError })
        return false
    end
    if not scenarioSpec then
        log("scenario_spec", { action = "absent" })
        return false
    end
    if not scenarioSpec.enabled and not force then
        log("scenario_spec", { action = "inert", spec_id = scenarioSpec.id })
        return false
    end
    local location = scenarioSpec.location or {}
    AddUITriggeredEvent("X4GunneryTestLabScenario", "scenario_begin", {
        specId = scenarioSpec.id, force = force == true, requestId = requestId or "",
        sectorMacro = location.sectorMacro or "",
        anchorX = location.x or 0, anchorY = location.y or 0, anchorZ = location.z or 0,
    })
    for _, group in ipairs(scenarioSpec.groups) do
        AddUITriggeredEvent("X4GunneryTestLabScenario", "scenario_group", {
            label = group.label, macro = group.macro, faction = group.faction,
            count = group.count, distance = group.distance, spread = group.spread,
            x = group.x, y = group.y,
            behaviour = group.behaviour, hostile = group.hostile,
            holdFire = group.holdFire, stripDefenceUnits = group.stripDefenceUnits,
            repairGuard = group.repairGuard,
            yaw = group.yaw, pitch = group.pitch, roll = group.roll,
            preserveOrientation = group.preserveOrientation,
            role = group.role, loadout = group.loadout,
            expectedWeapons = group.expectedWeapons,
            expectedTurrets = group.expectedTurrets,
            expectedMissileTurrets = group.expectedMissileTurrets,
        })
    end
    AddUITriggeredEvent("X4GunneryTestLabScenario", "scenario_commit")
    log("scenario_spec", { action = "sent", spec_id = scenarioSpec.id,
        groups = #scenarioSpec.groups, forced = tostring(force == true) })
    return true
end

-- Resolve the exact named ship, raw group, and operational members without
-- mutating the parked Gunnery session.
local function resolveExactGroup()
    local setup, bridge = scenarioSpec and scenarioSpec.setup, api()
    if not setup then return nil, "spec has no exact setup block" end
    if not bridge or not bridge.getCurrentShipSweepReadOnly or not bridge.getSession then
        return nil, "scenario setup API unavailable"
    end
    local ship, reason = bridge.getCurrentShipSweepReadOnly()
    if not ship then return nil, tostring(reason or "no occupied gunnery ship") end
    if ship.macro ~= setup.shipMacro or trim(ship.name) ~= trim(setup.shipLabel) then
        return nil, "need " .. setup.shipLabel .. " [" .. setup.shipMacro .. "], got "
            .. tostring(ship.name) .. " [" .. tostring(ship.macro) .. "]"
    end
    local selected, selectedGroups = nil, {}
    if setup.selectAll then
        for _, group in ipairs(ship.groups or {}) do
            if group.kind == "group" and group.mutable == true then
                selectedGroups[#selectedGroups + 1] = group
            end
        end
        if #selectedGroups == 0 then return nil, "no mutable turret groups" end
    elseif setup.singleTurretMacro then
        local matches = {}
        for _, group in ipairs(ship.groups or {}) do
            if group.kind == "single" and group.mutable == true
                    and group.macro == setup.singleTurretMacro then
                matches[#matches + 1] = group
            end
        end
        if #matches == 0 then
            return nil, "no mutable single turret with macro " .. setup.singleTurretMacro
        end
        if #matches > 1 then
            return nil, #matches .. " mutable single turrets with macro " .. setup.singleTurretMacro
                .. "; expected exactly one"
        end
        selected = matches[1]
        selectedGroups[1] = selected
    else
        for _, group in ipairs(ship.groups or {}) do
            if trim(group.group) == setup.turretGroup then selected = group; break end
        end
        if not selected then return nil, "missing raw group " .. setup.turretGroup end
        if selected.kind ~= "group" or selected.mutable ~= true then
            return nil, setup.turretLabel .. " is not a mutable turret group"
        end
        selectedGroups[1] = selected
    end
    local session = bridge.getSession()
    if not session then return nil, "no Gunnery session" end

    local memberIDs, memberMacros, groupKeys = {}, {}, {}
    for _, group in ipairs(selectedGroups) do
        groupKeys[#groupKeys + 1] = tostring(group.key)
        for _, member in ipairs(group.members or {}) do
            memberIDs[#memberIDs + 1] = tostring(member.id)
            memberMacros[#memberMacros + 1] = tostring(member.macro or "")
        end
    end
    if #memberIDs ~= setup.expectedTurrets then
        return nil, setup.turretLabel .. " needs " .. setup.expectedTurrets
            .. " operational turrets, found " .. #memberIDs
    end
    table.sort(memberMacros)
    if #setup.expectedMemberMacros > 0
            and table.concat(memberMacros, ",") ~= table.concat(setup.expectedMemberMacros, ",") then
        return nil, setup.turretLabel .. " needs macros " .. table.concat(setup.expectedMemberMacros, ",")
            .. ", found " .. table.concat(memberMacros, ",")
    end
    table.sort(memberIDs)
    table.sort(groupKeys)
    return {
        label = setup.turretLabel,
        rawGroup = setup.turretGroup or "",
        memberIDs = table.concat(memberIDs, ","),
        memberMacros = table.concat(memberMacros, ","),
        shipID = tostring(ship.id),
        groupKey = table.concat(groupKeys, ","),
        exactGroupKey = selected and selected.key or nil,
        armed = selected ~= nil and selected.armed == true,
        selectAll = setup.selectAll,
        session = session,
    }
end

local function applyExactGroup(selection)
    local session = selection.session
    local checked = {}
    for key in pairs(session.checkedGroupKeys or {}) do checked[#checked + 1] = key end
    for _, key in ipairs(checked) do X4GunneryState.toggleGroup(session, key, true) end
    if selection.selectAll then
        X4GunneryState.toggleAllGroups(session)
        session.selectedGroupKey = nil
    else
        X4GunneryState.toggleGroup(session, selection.exactGroupKey, selection.armed)
        session.selectedGroupKey = selection.exactGroupKey
    end
end

local function createTestScenario()
    if scenarioSpecError then
        scenarioActionStatus = "FAILED: " .. scenarioSpecError
        menu.display()
        return
    end
    if not scenarioSpec then
        scenarioActionStatus = "FAILED: no scenario spec loaded"
        menu.display()
        return
    end
    local remote = scenarioSpec.setup and scenarioSpec.setup.remote == true
    local selection, reason
    if remote then
        local occupiedShooterID = occupiedRemoteShooter()
        if remoteScenarioReady or occupiedShooterID then
            scenarioActionStatus = "BLOCKED: remote fixture already exists; do not Create again. "
                .. (remoteScenarioReady and ("teleport to " .. scenarioSpec.setup.shipLabel
                    .. " and open Test Lab once to arm it")
                    or "this is the spawned shooter; continue from Gunnery Control")
            log("scenario_create", { action = "rejected", reason = "remote_fixture_already_active",
                ship_id = occupiedShooterID or "pending_teleport" })
            menu.display()
            return
        end
    else
        selection, reason = resolveExactGroup()
        if not selection then
            scenarioActionStatus = "FAILED: " .. reason
            log("scenario_create", { action = "rejected", reason = reason })
            menu.display()
            return
        end
    end

    local expectedShips, expectedHostiles, expectedRepairFixtures = 0, 0, 0
    local expectedSafeFixtures, expectedShooters = 0, 0
    local expectedWeapons, expectedTurrets, expectedMissileTurrets = 0, 0, 0
    for _, group in ipairs(scenarioSpec.groups) do
        expectedShips = expectedShips + group.count
        if group.hostile then expectedHostiles = expectedHostiles + group.count end
        if group.repairGuard then expectedRepairFixtures = expectedRepairFixtures + group.count end
        if group.holdFire then expectedSafeFixtures = expectedSafeFixtures + group.count end
        if group.role == "shooter" then
            expectedShooters = expectedShooters + group.count
            expectedWeapons = expectedWeapons + group.expectedWeapons * group.count
            expectedTurrets = expectedTurrets + group.expectedTurrets * group.count
            expectedMissileTurrets = expectedMissileTurrets + group.expectedMissileTurrets * group.count
        end
    end

    scenarioRequestSerial = scenarioRequestSerial + 1
    local requestId = clockToken(GetCurRealTime()) .. "_" .. tostring(scenarioRequestSerial)
    pendingScenario = {
        requestId = requestId,
        specId = scenarioSpec.id,
        expectedShips = expectedShips,
        expectedSafeFixtures = expectedSafeFixtures,
        expectedRepairFixtures = expectedRepairFixtures,
        expectedDefenceUnits = 0,
        expectedHostiles = expectedHostiles,
        expectedShooters = expectedShooters,
        expectedWeapons = expectedWeapons,
        expectedTurrets = expectedTurrets,
        expectedMissileTurrets = expectedMissileTurrets,
        expectedLoadoutFailures = 0,
        expectedLocationFailures = 0,
        deadline = getElapsedTime() + 10,
        selection = selection,
        remote = remote,
    }
    scenarioActionStatus = "CREATING: replacing the previous fixture and verifying "
        .. expectedShips .. " ships..."
    sendScenarioSpec(true, requestId)
    log("scenario_create", {
        action = "requested", spec_id = scenarioSpec.id, expected_ships = expectedShips,
        request_id = requestId, load_time = scenarioLoadTime,
        group = selection and selection.rawGroup or "deferred_remote",
        member_ids = selection and selection.memberIDs or "deferred_remote",
        member_macros = selection and selection.memberMacros or "deferred_remote",
    })
    menu.display()
end

local function despawnTestScenario()
    if pendingScenario then
        scenarioActionStatus = "BLOCKED: scenario creation is still pending"
        log("scenario", { action = "despawn_rejected", reason = "creation_pending" })
        menu.display()
        return
    end
    local occupiedShooterID = occupiedRemoteShooter()
    if occupiedShooterID then
        scenarioActionStatus = "BLOCKED: leave the spawned shooter before despawning the test scenario"
        log("scenario", { action = "despawn_rejected", reason = "occupied_remote_shooter",
            ship_id = occupiedShooterID })
        menu.display()
        return
    end
    remoteScenarioReady = false
    AddUITriggeredEvent("X4GunneryTestLabScenario", "despawn_scenario")
    log("scenario", { action = "despawn" })
    menu.display()
end

-- TEMPORARY issue #184 A8 live diagnostic; delete during A9 cleanup.
--
-- a8Search is the frozen A7.3/A7.4 near-target aim-point search, ported line for
-- line from research/issue184/aimpoint_map.py: near_only_run(total=40, pad=50,
-- geom="C8") followed by refine_points, with the target frame as the identity.
-- ask(n, p, kind) returns X4's unit direction from target-local position p
-- toward the aim point X4 selects there, or nil. Every sample, starting,
-- confirmation, moved or adaptive, goes through one counter capped at 40.
local A8_TOTAL, A8_PAD, A8_PAD_Y = 40, 50, 8.86
local A8_U = 2 ^ -24
local A8_EPS = 2 ^ -18 / math.sqrt(2) + 8 * A8_U
local A8_REL, A8_FORWARD = 0.01, 1e-4
local A8_SLACK = 2 * (A8_EPS + 1e-6) / A8_FORWARD
local A8_ALPHA0, A8_ALPHA_MIN = math.rad(2), math.rad(1 / 64)
local A8_AXES = { { 2, 3 }, { 1, 3 }, { 1, 2 } }
local A8_CAPPED, A8_DIVERGED = {}, {}

local function vAdd(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function vSub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function vMul(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
local function vDot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function vCross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
local function vNorm(a) return math.sqrt(vDot(a, a)) end
local function vUnit(a, len) return { a[1] / len, a[2] / len, a[3] / len } end
-- Python keys positions by float tuple, where -0.0 == 0.0.
local function vKey(a) return string.format("%.17g,%.17g,%.17g", a[1] + 0, a[2] + 0, a[3] + 0) end
local function vLess(a, b)
    for k = 1, 3 do if a[k] ~= b[k] then return a[k] < b[k] end end
    return false
end
local function vInside(lo, hi, x, r)
    for k = 1, 3 do if not (lo[k] - r <= x[k] and x[k] <= hi[k] + r) then return false end end
    return true
end

local function a8Rho(...)
    local m = 1
    for i = 1, select("#", ...) do
        local p = select(i, ...)
        for k = 1, 3 do m = math.max(m, math.abs(p[k])) end
    end
    return 2 * A8_U * m
end

-- (depth along ray (u, d), depth error bound) where ray (v, e) crosses it, or nil.
local function a8Crossing(u, d, v, e)
    local c, k = vDot(d, e), vNorm(vCross(d, e))
    if k < 2 * A8_EPS / A8_REL then return nil end
    local w = vSub(u, v)
    local ew, dw = vDot(e, w), vDot(d, w)
    local s, t = (c * ew - dw) / (k * k), (ew - c * dw) / (k * k)
    local x = vAdd(u, vMul(d, s))
    local miss = 2 * a8Rho(u, v, x) + A8_EPS * (math.abs(s) + math.abs(t))
    if s <= 0 or t <= 0 or vNorm(vSub(vSub(x, v), vMul(e, t))) > miss
            or miss / k > A8_REL * math.max(s, t) then
        return nil
    end
    return s, miss / k
end

local function a8OnRay(u, d, c, r)
    local t = vDot(vSub(c, u), d)
    return t > 0 and vNorm(vSub(vSub(c, u), vMul(d, t))) <= r + A8_EPS * (t + r) + a8Rho(u, c)
end

local function a8Basis(d)
    local i = 1
    for k = 2, 3 do if math.abs(d[k]) < math.abs(d[i]) then i = k end end
    local e = { 0, 0, 0 }
    e[i] = 1
    local a = vCross(d, e)
    a = vUnit(a, vNorm(a))
    return a, vCross(d, a)
end

local function a8Linspace(a, b, count)
    local out, div = {}, count - 1
    local step = (b - a) / div
    for i = 0, count - 1 do
        out[i + 1] = step == 0 and (i / div) * (b - a) + a or i * step + a
    end
    out[count] = b
    return out
end

local function a8Search(C, H, askX4)
    local n, stop = 0, nil
    local points, found, tried, hits = {}, {}, {}, {}
    local rays = { order = {}, map = {} }
    local seen = { n = 0 }
    local tlo, thi = vSub(C, H), vAdd(vAdd(C, H), { 0, A8_PAD_Y, 0 })
    local plo = { C[1] - H[1] - A8_PAD, C[2] - H[2] - A8_PAD, C[3] - H[3] - A8_PAD }
    local phi = { C[1] + H[1] + A8_PAD, C[2] + H[2] + A8_PAD, C[3] + H[3] + A8_PAD }

    local function ask(p, kind)
        if n >= A8_TOTAL then error(A8_CAPPED, 0) end
        n = n + 1
        return askX4(n, p, kind)
    end
    local function spend(k) return n + k <= A8_TOTAL end
    local function addRay(p, d)
        local key = vKey(p)
        if not rays.map[key] then rays.order[#rays.order + 1] = key end
        rays.map[key] = { u = p, d = d }
        return key
    end
    local function byPosition(a, b) return vLess(rays.map[a].u, rays.map[b].u) end
    local function owner(u, d)
        if not d then return nil end
        local only
        for i, point in ipairs(points) do
            if a8OnRay(u, d, point.c, point.r) then
                if only then return nil end
                only = i
            end
        end
        return only
    end
    local function rayOwner(key) return owner(rays.map[key].u, rays.map[key].d) end

    local function confirm(u, d, s, err)
        local near = s / (1 + 1.5 * A8_SLACK) - 2 * err
        if near <= 0 then return false end
        local a = ask(vAdd(u, vMul(d, near)), "confirmation")
        local b = ask(vAdd(u, vMul(d, s + 2 * err)), "confirmation")
        return a ~= nil and vDot(a, d) > 0 and vNorm(vCross(a, d)) <= A8_FORWARD
            and (b == nil or vDot(b, d) <= 0 or vNorm(vCross(b, d)) > A8_FORWARD)
    end

    local function locate()
        local freeOrder, free = {}, {}
        for _, key in ipairs(rays.order) do
            if rays.map[key].d and rayOwner(key) == nil then
                freeOrder[#freeOrder + 1] = key
                free[key] = rays.map[key]
            end
        end
        local sorted = {}
        for i, key in ipairs(freeOrder) do sorted[i] = key end
        table.sort(sorted, byPosition)
        for i, ka in ipairs(sorted) do
            hits[ka] = hits[ka] or { order = {}, map = {} }
            local row = hits[ka]
            for j, kb in ipairs(sorted) do
                if i ~= j and row.map[kb] == nil then
                    local s, err = a8Crossing(free[ka].u, free[ka].d, free[kb].u, free[kb].d)
                    row.map[kb] = s and { s - err, s + err } or false
                    row.order[#row.order + 1] = kb
                end
            end
        end
        local candidates = {}
        for _, ka in ipairs(freeOrder) do
            local spans = {}
            for _, kb in ipairs(hits[ka] and hits[ka].order or {}) do
                if hits[ka].map[kb] and free[kb] then spans[#spans + 1] = { h = hits[ka].map[kb], key = kb } end
            end
            for a = 1, #spans - 1 do
                for b = a + 1, #spans do
                    local lo = math.max(spans[a].h[1], spans[b].h[1])
                    local hi = math.min(spans[a].h[2], spans[b].h[2])
                    local id = ka .. "|" .. spans[a].key .. "|" .. spans[b].key
                    if lo <= hi and not tried[id] then
                        candidates[#candidates + 1] = { width = hi - lo, ka = ka, kb = spans[a].key,
                            kc = spans[b].key, s = (lo + hi) / 2, id = id }
                    end
                end
            end
        end
        table.sort(candidates, function(a, b)
            if a.width ~= b.width then return a.width < b.width end
            for _, field in ipairs({ "ka", "kb", "kc" }) do
                if byPosition(a[field], b[field]) then return true end
                if byPosition(b[field], a[field]) then return false end
            end
            return a.s < b.s
        end)
        for _, f in ipairs(candidates) do
            local ray = rays.map[f.ka]
            if rayOwner(f.ka) == nil and rayOwner(f.kb) == nil and rayOwner(f.kc) == nil then
                tried[f.id] = true
                local x = vAdd(ray.u, vMul(ray.d, f.s))
                local r = f.width / 2 + A8_EPS * f.s + a8Rho(ray.u, x)
                local apart = true
                for _, point in ipairs(points) do
                    if not (vNorm(vSub(point.c, x)) > point.r + r) then apart = false; break end
                end
                if vInside(tlo, thi, x, r) and apart and confirm(ray.u, ray.d, f.s, f.width / 2) then
                    points[#points + 1] = { c = x, r = r }
                end
            end
        end
        if #points > (found[#found] and found[#found][2] or 0) then found[#found + 1] = { n, #points } end
    end

    local function boxDepth(u, d)
        local near, far = 0, math.huge
        for k = 1, 3 do
            if math.abs(d[k]) >= 1e-12 then
                local a, b = (tlo[k] - u[k]) / d[k], (thi[k] - u[k]) / d[k]
                if b < a then a, b = b, a end
                near, far = math.max(near, a), math.min(far, b)
            end
        end
        if near <= far and far < math.huge then return 0.5 * (near + far) end
        return math.max(vDot(vSub(vMul(vAdd(tlo, thi), 0.5), u), d), 1)
    end

    -- Moved samples sideways of each unassigned ray until it is assigned or too narrow.
    local function pursue(anchors)
        local state = {}
        while #anchors > 0 do
            locate()
            local kept = {}
            for _, key in ipairs(anchors) do if rayOwner(key) == nil then kept[#kept + 1] = key end end
            anchors = kept
            if #points > seen.n then
                seen.n = #points
            elseif #anchors == 0 or not spend(3) then
                break
            else
                local ray = rays.map[anchors[1]]
                local st = state[anchors[1]] or { A8_ALPHA0, 0 }
                local alpha, turn = st[1], st[2]
                if alpha < A8_ALPHA_MIN then
                    table.remove(anchors, 1)
                else
                    local a, b = a8Basis(ray.d)
                    local side = vAdd(vMul(a, math.cos(turn * math.pi / 3)), vMul(b, math.sin(turn * math.pi / 3)))
                    local v = vAdd(ray.u, vMul(side, boxDepth(ray.u, ray.d) * math.tan(alpha)))
                    local d = ask(v, "moved")
                    addRay(v, d)
                    local s = d and a8Crossing(ray.u, ray.d, v, d)
                    local supported = s and vInside(tlo, thi, vAdd(ray.u, vMul(ray.d, s)), 0)
                    state[anchors[1]] = { supported and alpha or alpha / 2, turn + 1 }
                end
            end
        end
        locate()
    end

    -- The position on the padded box seen from the largest missing viewing
    -- direction of whichever confirmed point is definitely selected there.
    local function angularPick()
        local dirs = {}
        for i = 1, #points do dirs[i] = {} end
        for _, key in ipairs(rays.order) do
            local i = rayOwner(key)
            if i then
                local v = vSub(rays.map[key].u, points[i].c)
                local len = vNorm(v)
                if len > 0 then dirs[i][#dirs[i] + 1] = vUnit(v, len) end
            end
        end
        local function gapAt(w)
            local dist, b = {}, 1
            for i, point in ipairs(points) do
                dist[i] = vNorm(vSub(w, point.c))
                if dist[i] < dist[b] then b = i end
            end
            local far = dist[b] + points[b].r
            for i, point in ipairs(points) do
                if i ~= b and not (dist[i] - point.r > far) then return -1 end
            end
            if #dirs[b] == 0 then return math.pi end
            local v = vSub(w, points[b].c)
            local len = vNorm(v)
            v = vUnit(v, len > 0 and len or 1)
            local gap = math.huge
            for _, dir in ipairs(dirs[b]) do
                gap = math.min(gap, math.acos(math.max(-1, math.min(1, vDot(v, dir)))))
            end
            return gap
        end
        local function scan(k, side, win)
            local ax, best = A8_AXES[k], nil
            local ss, ts = a8Linspace(win[1][1], win[1][2], 9), a8Linspace(win[2][1], win[2][2], 9)
            for i = 1, 9 do
                for j = 1, 9 do
                    local w = {}
                    w[k], w[ax[1]], w[ax[2]] = side, ss[i], ts[j]
                    local gap = gapAt(w)
                    if not best or gap > best.gap then best = { gap = gap, k = k, side = side, s = ss[i], t = ts[j] } end
                end
            end
            return best
        end
        local best
        for k = 1, 3 do
            local ax = A8_AXES[k]
            for _, side in ipairs({ plo[k], phi[k] }) do
                local face = scan(k, side, { { plo[ax[1]], phi[ax[1]] }, { plo[ax[2]], phi[ax[2]] } })
                if face.gap >= 0 and (not best or face.gap > best.gap) then best = face end
            end
        end
        if not best then return nil end
        local ax = A8_AXES[best.k]
        local half = { (phi[ax[1]] - plo[ax[1]]) / 2, (phi[ax[2]] - plo[ax[2]]) / 2 }
        for _ = 1, 3 do
            half = { half[1] * 0.25, half[2] * 0.25 }
            local face = scan(best.k, best.side, {
                { math.max(plo[ax[1]], best.s - half[1]), math.min(phi[ax[1]], best.s + half[1]) },
                { math.max(plo[ax[2]], best.t - half[2]), math.min(phi[ax[2]], best.t + half[2]) },
            })
            if face.gap >= 0 and face.gap > best.gap then best = face end
        end
        local pos = {}
        pos[best.k], pos[ax[1]], pos[ax[2]] = best.side, best.s, best.t
        return pos
    end

    local ok, err = pcall(function()
        local starts = {}
        for _, x in ipairs({ plo[1], phi[1] }) do
            for _, y in ipairs({ plo[2], phi[2] }) do
                for _, z in ipairs({ plo[3], phi[3] }) do starts[#starts + 1] = { x, y, z } end
            end
        end
        addRay(starts[1], ask(starts[1], "start"))
        locate()
        for i = 2, #starts do
            if n + 1 > A8_TOTAL then break end
            addRay(starts[i], ask(starts[i], "start"))
        end
        locate()
        seen.n = #points
        if #points == 0 then
            local anchors = {}
            for _, key in ipairs(rays.order) do
                if rays.map[key].d and rayOwner(key) == nil then anchors[#anchors + 1] = key end
            end
            table.sort(anchors, byPosition)
            pursue(anchors)
        end
        while true do
            locate()
            if #points == 0 then stop = "no confirmed point"; break end
            if not spend(3) then stop = "budget"; break end
            local pos = angularPick()
            if not pos then stop = "nothing definite"; break end
            if rays.map[vKey(pos)] then stop = "position already asked"; break end
            local d = ask(pos, "adaptive")
            local key = addRay(pos, d)
            locate()
            if d and rayOwner(key) == nil then pursue({ key }) end
        end
    end)
    if not ok then
        if err ~= A8_CAPPED then error(err, 0) end
        stop = "hard cap"
    end

    -- Refinement: tighten each point from rays already collected; no samples.
    local refined = {}
    for i, point in ipairs(points) do
        local own, best = {}, nil
        for _, key in ipairs(rays.order) do
            local ray, count = rays.map[key], 0
            if ray.d and a8OnRay(ray.u, ray.d, point.c, point.r) then
                for _, other in ipairs(points) do
                    if a8OnRay(ray.u, ray.d, other.c, other.r) then count = count + 1 end
                end
                if count == 1 then own[#own + 1] = ray end
            end
        end
        for a = 1, #own do
            for b = 1, #own do
                local s, err2 = nil, nil
                if a ~= b then s, err2 = a8Crossing(own[a].u, own[a].d, own[b].u, own[b].d) end
                if s then
                    local x = vAdd(own[a].u, vMul(own[a].d, s))
                    local r = err2 + A8_EPS * s + a8Rho(own[a].u, x)
                    if not best or r < best.r then best = { c = x, r = r } end
                end
            end
        end
        local accept = #own >= 2 and best ~= nil and best.r < point.r
            and vNorm(vSub(best.c, point.c)) + best.r <= point.r
        for _, ray in ipairs(accept and own or {}) do
            if not a8OnRay(ray.u, ray.d, best.c, best.r) then accept = false; break end
        end
        refined[i] = accept and { c = best.c, r = best.r, refined = true }
            or { c = point.c, r = point.r, refined = false }
    end
    return { samples = n, stop = stop, points = points, refined = refined, found = found }
end
menu.a8Search = a8Search

-- The live driver. One Create of the A8 fixture runs A8_RUNS complete searches
-- on its single spawned target. X4 answers asynchronously, so after every
-- answer the pure search is replayed from the answers collected so far until
-- it either needs the next sample or finishes. Exactly one request is
-- outstanding at a time, and every answer must echo its request's token.
local A8_SPEC_ID, A8_MARKER = "issue-184-a8-near-target-live-r1", "issue184-a8-live-r1"
local A8_RUNS, A8_TIMEOUT = 10, 10
local a8

local function a8Fmt(x) return string.format("%.17g", x) end

local function a8Fail(reason)
    local session = a8
    a8 = nil
    log("a8_run", { result = "FAIL", reason = reason, run = session.run, samples = #session.answers })
    log("a8_overall", { result = "FAIL", marker = A8_MARKER, reason = reason,
        runs_complete = session.run - 1, runs = A8_RUNS })
    scenarioActionStatus = "A8 FAIL in run " .. session.run .. " of " .. A8_RUNS .. " (" .. reason
        .. "); exit X4 and upload debug.log"
end

local function a8Request(control, sample, fields)
    local session = a8
    local token = session.requestId .. "_" .. session.run .. "_" .. sample
    session.outstanding, fields.token = token, token
    AddUITriggeredEvent("X4GunneryTestLabScenario", control, fields)
    if Helper then
        Helper.addDelayedOneTimeCallbackOnUpdate(function()
            if a8 == session and session.outstanding == token then a8Fail("timeout_" .. control) end
        end, false, getElapsedTime() + A8_TIMEOUT)
    end
end

local function a8NextRun()
    a8.run, a8.answers, a8.compute, a8.t0 = a8.run + 1, {}, 0, nil
    log("a8_run", { phase = "start", run = a8.run, runs = A8_RUNS })
    a8.targetSent = GetCurRealTime()
    a8Request("a8_target", 0, { specId = A8_SPEC_ID })
end

local function a8Step()
    local session = a8
    local started = GetCurRealTime()
    local ok, result = pcall(a8Search, session.C, session.H, function(n, p, kind)
        local known = session.answers[n]
        if not known then error({ n = n, p = p, kind = kind }, 0) end
        if vKey(known.p) ~= vKey(p) or known.kind ~= kind then error(A8_DIVERGED, 0) end
        return known.d
    end)
    local finished = GetCurRealTime()
    session.compute = session.compute + (finished - started)
    if not ok and type(result) == "table" and result.n then
        session.pending = result
        log("a8_sample", { phase = "request", run = session.run, sample = result.n, kind = result.kind,
            x = a8Fmt(result.p[1]), y = a8Fmt(result.p[2]), z = a8Fmt(result.p[3]) })
        if result.n == 1 then session.t0 = GetCurRealTime() end
        a8Request("a8_probe", result.n, { x = result.p[1], y = result.p[2], z = result.p[3] })
        return
    end
    if not ok then
        return a8Fail(result == A8_DIVERGED and "replay_diverged" or ("lua_error " .. tostring(result)))
    end
    local counts = { start = 0, confirmation = 0, moved = 0, adaptive = 0 }
    for _, answer in ipairs(session.answers) do counts[answer.kind] = counts[answer.kind] + 1 end
    if #result.points == 0 then return a8Fail("no_recovered_point " .. tostring(result.stop)) end
    log("a8_run", { result = "COMPLETE", run = session.run, samples = result.samples,
        points = #result.points, stop = result.stop,
        elapsed_ms = a8Fmt((finished - session.t0) * 1000),
        final_compute_ms = a8Fmt((finished - started) * 1000),
        replay_compute_ms = a8Fmt(session.compute * 1000),
        start = counts.start, confirmation = counts.confirmation,
        moved = counts.moved, adaptive = counts.adaptive })
    for i, point in ipairs(result.refined) do
        local confirmedAt
        for _, entry in ipairs(result.found) do
            if not confirmedAt and entry[2] >= i then confirmedAt = entry[1] end
        end
        local raw = result.points[i]
        log("a8_point", { run = session.run, index = i, confirmed_at_sample = confirmedAt,
            x = a8Fmt(point.c[1]), y = a8Fmt(point.c[2]), z = a8Fmt(point.c[3]), r = a8Fmt(point.r),
            refined = tostring(point.refined), raw_x = a8Fmt(raw.c[1]), raw_y = a8Fmt(raw.c[2]),
            raw_z = a8Fmt(raw.c[3]), raw_r = a8Fmt(raw.r) })
    end
    session.complete = session.complete + 1
    if session.run < A8_RUNS then return a8NextRun() end
    a8 = nil
    log("a8_overall", { result = "COMPLETE", marker = A8_MARKER, runs = A8_RUNS,
        runs_complete = session.complete })
    scenarioActionStatus = "A8 COMPLETE: " .. session.complete .. " of " .. A8_RUNS
        .. " searches finished; exit X4 and upload debug.log"
end

local function a8Start(requestId)
    a8 = { requestId = requestId, run = 0, complete = 0 }
    log("a8_begin", { marker = A8_MARKER, spec_id = A8_SPEC_ID, request_id = requestId,
        runs = A8_RUNS, total = A8_TOTAL })
    scenarioActionStatus = "A8 RUNNING: " .. A8_RUNS .. " aim-point searches; stay seated"
    a8NextRun()
end

local function onA8Target(_, param)
    local token, found, target, macro, cx, cy, cz, hx, hy, hz = tostring(param or ""):match(
        "^x4gca8t:([^:]+):([01]):([^:]+):([^:]+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+)$")
    if not a8 or not token or token ~= a8.outstanding then
        log("a8_ignored", { kind = "target", param = param })
        return
    end
    a8.outstanding = nil
    if found ~= "1" then return a8Fail("target_unresolved") end
    a8.C = { tonumber(cx) / 1000, tonumber(cy) / 1000, tonumber(cz) / 1000 }
    a8.H = { tonumber(hx) / 1000, tonumber(hy) / 1000, tonumber(hz) / 1000 }
    log("a8_target", { run = a8.run, target = target, macro = macro,
        c_x = a8Fmt(a8.C[1]), c_y = a8Fmt(a8.C[2]), c_z = a8Fmt(a8.C[3]),
        h_x = a8Fmt(a8.H[1]), h_y = a8Fmt(a8.H[2]), h_z = a8Fmt(a8.H[3]),
        query_ms = a8Fmt((GetCurRealTime() - a8.targetSent) * 1000) })
    a8Step()
end

local function onA8Probe(_, param)
    local token, answered, x, y, z = tostring(param or ""):match(
        "^x4gca8p:([^:]+):([01]):(%-?%d+):(%-?%d+):(%-?%d+)$")
    if not a8 or not token or token ~= a8.outstanding then
        log("a8_ignored", { kind = "probe", param = param })
        return
    end
    a8.outstanding = nil
    if answered ~= "1" then return a8Fail("target_lost") end
    local pending = a8.pending
    local d = { tonumber(x) / 1e9, tonumber(y) / 1e9, tonumber(z) / 1e9 }
    if math.abs(vNorm(d) - 1) > 1e-3 then return a8Fail("bad_direction") end
    a8.answers[pending.n] = { p = pending.p, kind = pending.kind, d = d }
    log("a8_sample", { phase = "answer", run = a8.run, sample = pending.n, kind = pending.kind,
        ix = x, iy = y, iz = z })
    a8Step()
end

local function onScenarioReady(_, param)
    local requestId, specId, spawned, safeFixtures, safeWeapons, unsafeWeapons,
        defenceUnits, hostiles, repairFixtures, shooters, shooterWeapons,
        shooterTurrets, shooterMissileTurrets, loadoutFailures, locationFailures =
        tostring(param or ""):match(
            "^x4gct9:([^:]+):([^:]+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
    if not requestId or not pendingScenario or requestId ~= pendingScenario.requestId
            or specId ~= pendingScenario.specId then return end
    spawned = tonumber(spawned)
    safeFixtures, safeWeapons, unsafeWeapons = tonumber(safeFixtures), tonumber(safeWeapons), tonumber(unsafeWeapons)
    defenceUnits, hostiles, repairFixtures = tonumber(defenceUnits), tonumber(hostiles), tonumber(repairFixtures)
    shooters, shooterWeapons, shooterTurrets = tonumber(shooters), tonumber(shooterWeapons), tonumber(shooterTurrets)
    shooterMissileTurrets = tonumber(shooterMissileTurrets)
    loadoutFailures, locationFailures = tonumber(loadoutFailures), tonumber(locationFailures)
    local request = pendingScenario
    pendingScenario = nil

    if spawned ~= request.expectedShips then
        scenarioActionStatus = "FAILED: created " .. tostring(spawned) .. " of "
            .. tostring(request.expectedShips) .. " ships; inspect debug.log"
        log("scenario_create", { action = "failed", request_id = request.requestId,
            expected_ships = request.expectedShips, spawned_ships = spawned })
        menu.display()
        return
    end
    if safeFixtures ~= request.expectedSafeFixtures
            or (request.expectedSafeFixtures > 0 and (safeWeapons < 1 or unsafeWeapons ~= 0))
            or defenceUnits ~= request.expectedDefenceUnits then
        scenarioActionStatus = "FAILED: safety census was " .. safeFixtures
            .. " fixtures, " .. safeWeapons .. " safe weapons, " .. unsafeWeapons
            .. " unsafe weapons, and " .. defenceUnits .. " defence units; inspect debug.log"
        log("scenario_create", { action = "failed", request_id = request.requestId,
            expected_safe_fixtures = request.expectedSafeFixtures, safe_fixtures = safeFixtures,
            safe_weapons = safeWeapons, unsafe_weapons = unsafeWeapons,
            expected_defence_units = request.expectedDefenceUnits, defence_units = defenceUnits })
        menu.display()
        return
    end
    if hostiles ~= request.expectedHostiles then
        scenarioActionStatus = "FAILED: hostility census was " .. hostiles
            .. " attackable targets; expected " .. request.expectedHostiles .. "; inspect debug.log"
        log("scenario_create", { action = "failed", request_id = request.requestId,
            expected_hostiles = request.expectedHostiles, hostiles = hostiles })
        menu.display()
        return
    end
    if repairFixtures ~= request.expectedRepairFixtures then
        scenarioActionStatus = "FAILED: repair census was " .. repairFixtures
            .. " guarded fixtures; expected " .. request.expectedRepairFixtures .. "; inspect debug.log"
        log("scenario_create", { action = "failed", request_id = request.requestId,
            expected_repair_fixtures = request.expectedRepairFixtures,
            repair_fixtures = repairFixtures })
        menu.display()
        return
    end
    if shooters ~= request.expectedShooters
            or shooterWeapons ~= request.expectedWeapons
            or shooterTurrets ~= request.expectedTurrets
            or shooterMissileTurrets ~= request.expectedMissileTurrets
            or loadoutFailures ~= request.expectedLoadoutFailures then
        scenarioActionStatus = "FAILED: shooter/loadout census was " .. shooters .. " shooters, "
            .. shooterWeapons .. " weapons, " .. shooterTurrets .. " ordinary turrets, "
            .. shooterMissileTurrets .. " missile turrets, and " .. loadoutFailures
            .. " loadout failures; inspect debug.log"
        log("scenario_create", { action = "failed", request_id = request.requestId,
            expected_shooters = request.expectedShooters, shooters = shooters,
            expected_weapons = request.expectedWeapons, weapons = shooterWeapons,
            expected_turrets = request.expectedTurrets, ordinary_turrets = shooterTurrets,
            expected_missile_turrets = request.expectedMissileTurrets,
            shooter_missile_turrets = shooterMissileTurrets,
            loadout_failures = loadoutFailures })
        menu.display()
        return
    end
    if locationFailures ~= request.expectedLocationFailures then
        scenarioActionStatus = "FAILED: " .. locationFailures
            .. " objects missed the exact remote placement; inspect debug.log"
        log("scenario_create", { action = "failed", request_id = request.requestId,
            expected_location_failures = request.expectedLocationFailures,
            location_failures = locationFailures })
        menu.display()
        return
    end

    if request.remote then
        remoteScenarioReady = true
        scenarioActionStatus = "READY: remote fixture verified; teleport to "
            .. scenarioSpec.setup.shipLabel .. " and open Test Lab once to arm "
            .. scenarioSpec.setup.turretLabel
        log("scenario_create", { action = "remote_ready", request_id = request.requestId,
            spawned_ships = spawned, shooters = shooters,
            weapons = shooterWeapons, ordinary_turrets = shooterTurrets,
            missile_turrets = shooterMissileTurrets,
            location_failures = locationFailures })
        returnToGunnery("remote_scenario_ready")
        return
    end

    local selection, reason = resolveExactGroup()
    if not selection or selection.shipID ~= request.selection.shipID
            or selection.groupKey ~= request.selection.groupKey
            or selection.memberIDs ~= request.selection.memberIDs then
        reason = reason or "ship or exact turret membership changed while spawning"
        scenarioActionStatus = "FAILED: " .. reason
        log("scenario_create", { action = "failed", request_id = request.requestId, reason = reason })
        menu.display()
        return
    end
    applyExactGroup(selection)
    scenarioActionStatus = "READY: " .. spawned .. " named ships; only "
        .. selection.label .. " ticked"
    log("scenario_create", {
        action = "ready", request_id = request.requestId, spawned_ships = spawned,
        group = selection.rawGroup, safe_fixtures = safeFixtures,
        safe_weapons = safeWeapons, unsafe_weapons = unsafeWeapons,
        defence_units = defenceUnits, hostiles = hostiles,
        repair_fixtures = repairFixtures, member_ids = selection.memberIDs,
    })
    local currentSession = api() and api().getSession and api().getSession()
    -- A8 times its own search, so it leaves the general observer off.
    if request.specId == A8_SPEC_ID then
        a8Start(request.requestId)
    else
        setObserving(true, currentSession and currentSession.aimTargetID)
    end
    returnToGunnery("scenario_ready")
end

local function shipFields(item)
    local ship = sweep and sweep.ship or {}
    local group, member = item and item.group or {}, item and item.member or {}
    return { ship_macro = ship.macro, ship_name = ship.name, ship_id = ship.id, group_key = group.key, group_path = group.path, group_name = group.group, turret_macro = member.macro, turret_name = member.name, turret_id = member.id }
end

local function fieldsFor(item, extra)
    local fields = shipFields(item)
    for key, value in pairs(extra or {}) do fields[key] = value end
    return fields
end

local function cleanup(reason, clearSweep)
    local activeSweep = sweep
    if api() then api().returnTestCamera() end
    inspectStarted, nextPoll, stableSamples, unstableSamples, technical, targetBefore, targetPreserved = nil, nil, 0, 0, nil, nil, nil
    if reason and activeSweep and activeSweep.phase ~= "complete" then log("abort", { reason = reason, ship_id = activeSweep.ship.id, ship_name = activeSweep.ship.name, ship_macro = activeSweep.ship.macro }) end
    if clearSweep then sweep = nil end
end

-- Gunnery parks its live session before opening this companion. Every
-- operator-driven exit must therefore hand ownership explicitly back to the
-- main menu; a plain close leaves resumePending armed with no menu to consume
-- it. Keep the latch set until the Test Lab is shown again so a Helper-induced
-- re-entrant/late onCloseElement cannot request the handoff twice.
returnToGunnery = function(reason)
    if closing then return end
    closing = true
    cleanup(reason, true)
    Helper.closeMenuAndOpenNewMenu(menu, "X4GunneryMenu", { 0, 0 }, true)
end

local function startSweep()
    if not api() then return end
    if api().isDirectControlActive() then log("start_rejected", { reason = "direct_active" }); return end
    local ship, reason = api().getCurrentShipSweep()
    if not ship then log("start_rejected", { reason = reason }); return end
    sweep = State.newSweep(ship)
    log("sweep_start", { ship_macro = ship.macro, ship_name = ship.name, ship_id = ship.id, queued = #sweep.queue, groups = #sweep.groupQueue })
    if sweep.phase == "groups" then finishGroups() end
    if sweep.phase == "complete" then emitSummary() end
end

emitSummary = function()
    if not sweep or sweep.summaryLogged then return end
    sweep.summaryLogged = true
    local summary = State.summary(sweep)
    log("summary", { ship_macro = sweep.ship.macro, ship_name = sweep.ship.name, ship_id = sweep.ship.id, queued = summary.queued, inspected = summary.inspected, technical_pass = summary.technicalPass, visual_pass = summary.visualPass, visual_fail = summary.visualFail, skipped = summary.skipped, retries = summary.retries, group_pass = summary.groupPass, group_fail = summary.groupFail })
end

finishGroups = function()
    while sweep and sweep.phase == "groups" do
        local group = sweep.groupQueue[sweep.groupIndex]
        if not group then sweep.phase = "complete"; break end
        local result = api().verifyTestGroup(group.key)
        State.recordGroup(sweep, group, result)
        log("group_verify", { ship_macro = sweep.ship.macro, ship_name = sweep.ship.name, ship_id = sweep.ship.id, group_key = group.key, group_path = group.path, group_name = group.group, technical = result.pass and "pass" or "fail", applied = result.applied, restored = result.restored, reason = result.reason })
    end
    if sweep and sweep.phase == "complete" then emitSummary() end
end

local function inspectCurrent()
    local item = State.current(sweep)
    if not item or sweep.phase ~= "ready" then return end
    targetBefore, targetPreserved = api().getTestSofttarget(), nil
    if not item.member.cameraSupported then
        technical = "fail"; sweep.phase = "verdict"
        targetPreserved = "not_checked"
        log("inspect", shipFields(item)); log("technical", fieldsFor(item, { technical = "fail", reason = "camera_unsupported", target_id = targetBefore.id, target_connection = targetBefore.connection, target_name = targetBefore.name, target_macro = targetBefore.macro, target_preserved = targetPreserved }))
        return
    end
    local ok, reason = api().focusTestTurret(item.member.id)
    if not ok then
        technical = "fail"; sweep.phase = "verdict"
        targetPreserved = "not_checked"
        log("technical", fieldsFor(item, { technical = "fail", reason = reason, target_id = targetBefore.id, target_connection = targetBefore.connection, target_name = targetBefore.name, target_macro = targetBefore.macro, target_preserved = targetPreserved }))
        return
    end
    inspectStarted, nextPoll, stableSamples, unstableSamples, technical = getElapsedTime(), getElapsedTime() + 0.5, 0, 0, nil
    sweep.phase = "inspecting"
    log("inspect", shipFields(item))
end

local function verdict(value)
    if not sweep or sweep.phase ~= "verdict" then return end
    local item = State.current(sweep)
    local reason = value == "skip" and "operator_skip" or ""
    State.recordVerdict(sweep, value, reason, technical)
    log("verdict", fieldsFor(item, { technical = technical, visual = value, reason = reason, target_id = targetBefore and targetBefore.id or "0", target_connection = targetBefore and targetBefore.connection or "", target_name = targetBefore and targetBefore.name or "", target_macro = targetBefore and targetBefore.macro or "", target_preserved = targetPreserved or "not_checked" }))
    technical = nil
    if sweep.phase == "groups" then finishGroups() end
end

function menu.onShowMenu()
    closing, suppressReopen = false, false
    if remoteScenarioReady then
        local selection, reason = resolveExactGroup()
        if selection then
            applyExactGroup(selection)
            remoteScenarioReady = false
            scenarioActionStatus = "ARMED: " .. selection.label
                .. " verified and selected; returning to Gunnery Control"
            log("scenario_activate", { action = "ready", ship_id = selection.shipID,
                group = selection.rawGroup, member_ids = selection.memberIDs,
                member_macros = selection.memberMacros })
            setObserving(true)
            returnToGunnery("remote_scenario_armed")
            return
        end
        scenarioActionStatus = "READY: teleport to " .. scenarioSpec.setup.shipLabel
            .. ", then open Test Lab again (" .. tostring(reason) .. ")"
    end
    menu.display()
end

function menu.display()
    Helper.clearMenu(menu)
    -- Leave the camera unobscured during the mandatory five-second visual check.
    -- The menu remains registered, so onUpdate continues to poll its stability.
    if sweep and sweep.phase == "inspecting" then return end
    local frame = Helper.createFrameHandle(menu, { width = Helper.scaleX(900), height = Helper.scaleY(520), standardButtons = { close = true } })
    local tableView = frame:addTable(4, { tabOrder = 1, width = Helper.scaleX(880) })
    local title = tableView:addRow(false, { bgColor = Color["row_title_background"] })
    title[1]:setColSpan(4):createText(text(1), Helper.headerRowCenteredProperties)
    local reloadRow = tableView:addRow("reload", {})
    for index, spec in ipairs({ { text(22), "ui" }, { text(23), "md" }, { text(24), "ai" } }) do
        local label, kind = spec[1], spec[2]
        reloadRow[index]:createButton({}):setText(label)
        reloadRow[index].handlers.onClick = function()
            if kind == "ui" then
                -- Both functions were present and worked when this was live-tested
                -- on 2026-08-08; fn_present is still logged because a future patch
                -- removing one would otherwise look like a button that does nothing.
                log("reload", { kind = kind, fn_present = tostring(ScheduleReloadUI ~= nil) })
                if ScheduleReloadUI then ScheduleReloadUI() end
            else
                -- Second arg MUST be 0, not nil: nil segfaults the game.
                -- refreshmd is live-tested; refreshai is not, and the AI button is
                -- here only because it costs one table entry to offer it.
                log("reload", { kind = kind, fn_present = tostring(ExecuteDebugCommand ~= nil) })
                if ExecuteDebugCommand then ExecuteDebugCommand("refresh" .. kind, 0) end
            end
        end
    end
    local specRow = tableView:addRow(false, {})
    specRow[1]:setColSpan(4):createText(text(27) .. ": " .. scenarioSpecLabel())
    if scenarioSpec and scenarioSpec.setup then
        local setup = scenarioSpec.setup
        local setupRow = tableView:addRow(false, {})
        setupRow[1]:setColSpan(4):createText((setup.remote and "Remote setup: " or "One-click setup: ")
            .. setup.shipLabel .. " | only " .. setup.turretLabel .. " | "
            .. setup.expectedTurrets .. " operational turrets")
    end
    local scenarioRow = tableView:addRow("scenario", {})
    local remoteCreateBlocked, remoteDespawnBlocked = false, false
    if scenarioSpec and scenarioSpec.setup and scenarioSpec.setup.remote then
        local occupiedShooterID = occupiedRemoteShooter()
        remoteCreateBlocked = remoteScenarioReady or occupiedShooterID ~= nil
        remoteDespawnBlocked = occupiedShooterID ~= nil
    end
    scenarioRow[1]:setColSpan(2):createButton({
        active = scenarioSpec ~= nil and scenarioSpec.setup ~= nil and pendingScenario == nil
            and not remoteCreateBlocked,
    }):setText(text(25))
    scenarioRow[1].handlers.onClick = createTestScenario
    scenarioRow[3]:setColSpan(2):createButton({
        active = pendingScenario == nil and not remoteDespawnBlocked,
    }):setText(text(26))
    scenarioRow[3].handlers.onClick = despawnTestScenario
    if scenarioActionStatus then
        local statusRow = tableView:addRow(false, {})
        statusRow[1]:setColSpan(4):createText(scenarioActionStatus)
    end
    -- Arms the ownership-change test. The Test Lab cannot be opened while
    -- engaged, so this cannot flip an owner on the spot; it arms MD to do it on
    -- the NEXT Direct-control engage instead. See ArmCapture in the MD script.
    local captureRow = tableView:addRow("capture", {})
    captureRow[1]:setColSpan(4):createButton({}):setText(text(28)); captureRow[1].handlers.onClick = function()
        AddUITriggeredEvent("X4GunneryTestLabScenario", "arm_capture")
        log("scenario", { action = "arm_capture" })
    end
    -- Fire-control logging. Arm it here, then close the menu and play normally:
    -- the sampler lives in MD, so it keeps running with every menu shut. Mark
    -- stamps the interesting instant; MD numbers the marks, because mid-combat
    -- the point is one click and not typing a label.
    local observeRow = tableView:addRow("observe", {})
    observeRow[1]:setColSpan(2):createButton({}):setText(text(29) .. ": " .. (observing and "ON" or "OFF"))
    observeRow[1].handlers.onClick = function() setObserving(not observing); menu.display() end
    observeRow[3]:setColSpan(2):createButton({}):setText(text(30))
    observeRow[3].handlers.onClick = function()
        AddUITriggeredEvent("X4GunneryTestLabObserve", "observe_mark")
        log("observe", { action = "mark" })
    end
    if not sweep then
        local row = tableView:addRow(false, {}); row[1]:setColSpan(4):createText(text(12))
        local start = tableView:addRow("start", {}); start[1]:setColSpan(4):createButton({}):setText(text(2)); start[1].handlers.onClick = function() startSweep(); menu.display() end
    else
        local summary = State.summary(sweep)
        local info = tableView:addRow(false, {})
        info[1]:setColSpan(4):createText(text(14) .. ": " .. sweep.ship.name .. " [" .. sweep.ship.macro .. "]")
        local progress = tableView:addRow(false, {})
        progress[1]:setColSpan(4):createText(text(15) .. ": " .. tostring(summary.inspected) .. " / " .. tostring(summary.queued) .. " | visual " .. tostring(summary.visualPass) .. "/" .. tostring(summary.visualFail) .. " | groups " .. tostring(summary.groupPass) .. "/" .. tostring(summary.groupFail))
        local item = State.current(sweep)
        if sweep.phase == "ready" and item then
            local row = tableView:addRow(false, {}); row[1]:setColSpan(4):createText(item.member.name .. " — " .. item.group.name)
            local action = tableView:addRow("inspect", {}); action[1]:setColSpan(4):createButton({}):setText(text(4)); action[1].handlers.onClick = function() inspectCurrent(); menu.display() end
        elseif sweep.phase == "inspecting" then
            local row = tableView:addRow(false, {}); row[1]:setColSpan(4):createText(text(4) .. " (5 seconds)")
        elseif sweep.phase == "verdict" and item then
            local row = tableView:addRow(false, {}); row[1]:setColSpan(4):createText((technical == "pass") and text(20) or text(19))
            local targetRow = tableView:addRow(false, {}); targetRow[1]:setColSpan(4):createText("Target preservation: " .. tostring(targetPreserved or "not_checked"))
            local buttons = tableView:addRow("verdict", {})
            for index, spec in ipairs({ { text(5), "pass" }, { text(6), "fail" }, { text(7), "retry" }, { text(8), "skip" } }) do
                local choice = spec[2]
                buttons[index]:createButton({}):setText(spec[1]); buttons[index].handlers.onClick = function() verdict(choice); menu.display() end
            end
        elseif sweep.phase == "complete" then
            local row = tableView:addRow(false, {}); row[1]:setColSpan(4):createText(text(13))
            local final = tableView:addRow(false, {})
            final[1]:setColSpan(4):createText("Technical " .. tostring(summary.technicalPass) .. "/" .. tostring(summary.inspected) .. " | Visual pass/fail " .. tostring(summary.visualPass) .. "/" .. tostring(summary.visualFail) .. " | Skip/retry " .. tostring(summary.skipped) .. "/" .. tostring(summary.retries))
            local groups = tableView:addRow(false, {})
            groups[1]:setColSpan(4):createText(text(16) .. ": pass/fail " .. tostring(summary.groupPass) .. "/" .. tostring(summary.groupFail))
            local reset = tableView:addRow("reset", {}); reset[1]:setColSpan(4):createButton({}):setText(text(2)); reset[1].handlers.onClick = function() sweep = nil; startSweep(); menu.display() end
        end
        local abort = tableView:addRow("abort", {}); abort[1]:setColSpan(4):createButton({}):setText(text(9)); abort[1].handlers.onClick = function() returnToGunnery("operator_abort") end
    end
    frame:display()
end

function menu.onUpdate()
    local now = getElapsedTime()
    if pendingScenario and now >= pendingScenario.deadline then
        local request = pendingScenario
        pendingScenario = nil
        scenarioActionStatus = "FAILED: no spawn acknowledgement; inspect debug.log"
        log("scenario_create", { action = "timeout", request_id = request.requestId,
            expected_ships = request.expectedShips })
        menu.display()
        return
    end
    if not sweep or sweep.phase ~= "inspecting" then return end
    local item = State.current(sweep)
    if not item then return end
    if now >= nextPoll then
        if api().getCameraFocus() == item.member.id then stableSamples = stableSamples + 1 else unstableSamples = unstableSamples + 1 end
        nextPoll = now + 0.25
    end
    if now - inspectStarted >= 5 then
        api().returnTestCamera()
        local acquisitionFailed = api().testCameraFailed(item.member.id)
        local targetAfter = api().getTestSofttarget()
        targetPreserved = State.targetsEqual(targetBefore, targetAfter) and "pass" or "fail"
        technical = stableSamples >= 3 and unstableSamples == 0 and not acquisitionFailed and targetPreserved == "pass" and "pass" or "fail"
        sweep.phase = "verdict"
        local reason = technical == "pass" and "" or (acquisitionFailed and "camera_acquisition_failed" or (targetPreserved == "fail" and "target_not_preserved" or "camera_focus_mismatch"))
        log("technical", fieldsFor(item, { technical = technical, stable_samples = stableSamples, unstable_samples = unstableSamples, reason = reason, target_id = targetBefore and targetBefore.id or "0", target_connection = targetBefore and targetBefore.connection or "", target_name = targetBefore and targetBefore.name or "", target_macro = targetBefore and targetBefore.macro or "", target_preserved = targetPreserved }))
        menu.display()
    end
end

function menu.onCloseElement(dueToClose)
    if closing then return end
    if suppressReopen then
        closing = true
        cleanup("menu_closed", true)
        Helper.closeMenu(menu, dueToClose, nil, false)
        return
    end
    closing = true
    cleanup("menu_closed", true)
    Helper.closeMenuAndOpenNewMenu(menu, "X4GunneryMenu", { 0, 0 }, true)
end

local function init()
    Menus = Menus or {}; table.insert(Menus, menu)
    log("scenario_runtime", { action = "loaded", load_time = scenarioLoadTime,
        spec_id = scenarioSpec and scenarioSpec.id or "none" })
    -- A UI reload destroys this file-local state but leaves MD cue variables
    -- alive. The new Lua instance starts OFF, so explicitly converge MD on
    -- that state before rendering the menu; otherwise ObserveArm keeps
    -- logging while the button says OFF.
    if AddUITriggeredEvent then setObserving(false) end
    -- Exact-setup specs are deliberately inert until the owner presses Create
    -- test scenario. That button performs the ship/loadout preflight before MD
    -- is allowed to replace anything. Preserve load-time replay only for old
    -- specs without setup metadata so existing ad-hoc fixtures keep working.
    if AddUITriggeredEvent and (not scenarioSpec or not scenarioSpec.setup) then
        sendScenarioSpec(false)
    end
    if Helper then Helper.registerMenu(menu) end
    RegisterEvent("X4GunneryTestLab.ScenarioReady", onScenarioReady)
    RegisterEvent("X4GunneryTestLab.A8Target", onA8Target)
    RegisterEvent("X4GunneryTestLab.A8Probe", onA8Probe)
    if api() then
        api().registerTestLab({ open = function()
            local main = Helper.getMenu("X4GunneryMenu")
            if main then Helper.closeMenuAndOpenNewMenu(main, "X4GunneryTestLab", { 0, 0 }, true) end
        end })
    end
    local abort = function()
        -- The player has left the chair (or a load is replacing the world), so
        -- the automatic menu close must not resurrect Gunnery Control. This is
        -- reset only when a later, deliberate Test Lab opening is shown.
        suppressReopen = true
        pendingScenario = nil
        if sweep then cleanup("player_context_changed", true) end
    end
    RegisterEvent("playerGetUp", abort)
    RegisterEvent("playerUndock", abort)
    registerForEvent("gameplanchange", getElement("Scene.UIContract"), function(_, mode) if mode ~= "cockpit" and mode ~= "external" and mode ~= "externalfirstperson" then abort() end end)
    registerForEvent("gameLoadingDone", getElement("Scene.UIContract"), abort)
end
init()
