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

-- Throwaway issue #205 feasibility probe: can the X4 graph widget show a
-- turret map? nil = probe off. See docs comment above menu.display() for the
-- probe-only body it triggers.
local turretMap = nil

-- MD may stringify a length with a unit suffix ("12.5m"); pull the leading
-- number out tolerantly rather than assume tonumber() handles it directly.
local function parseLength(s)
    local head = tostring(s or ""):match("^%s*([-+]?[%d%.]+[eE]?[-+]?%d*)")
    return tonumber(head)
end

local function turretMapPendingCount()
    if not turretMap then return 0 end
    local pending = 0
    for _, point in ipairs(turretMap.points) do
        if point.x == nil then pending = pending + 1 end
    end
    return pending
end

local function turretMapReceivedCount()
    if not turretMap then return 0 end
    return #turretMap.points - turretMapPendingCount()
end

local function onTurretMapPosition(_, param)
    if not turretMap then return end
    local raw = tostring(param or "")
    log("turretmap", { action = "position", raw = raw })
    local prefix, idxStr, rest = raw:match("^(x4gtm1):([%d%.]+):(.*)$")
    if not prefix then return end
    -- MD may echo the Lua integer back as "1.0".
    local idx = tonumber(idxStr) and math.floor(tonumber(idxStr))
    local point = idx and turretMap.points[idx]
    if not point then return end
    if rest == "fail" then
        point.x = false -- mark answered-but-failed so it stops counting as pending
        return
    end
    local xs, ys, zs = rest:match("^([^:]*):([^:]*):(.*)$")
    point.x, point.y, point.z = parseLength(xs), parseLength(ys), parseLength(zs)
    if turretMapPendingCount() == 0 then menu.display() end
end

local function turretMapPointName(point)
    return point.name .. " — " .. point.groupName .. " [" .. point.state .. "]"
end

-- Random shuffle of FAKE per-turret states; missile turrets can never show
-- "hit" because X4 does not attribute missile impacts per turret (see the
-- observe MD script's HIT-line comment for the same limitation).
local function turretMapShuffleStates()
    for _, point in ipairs(turretMap.points) do
        local roll = math.random()
        if turretMap.preview then
            -- Preview: show all four states regardless of real selection.
            local states = point.isMissile and { "unselected", "idle", "fired" } or { "unselected", "idle", "fired", "hit" }
            point.state = states[math.random(#states)]
        elseif not point.selected then
            point.state = "unselected"
        elseif point.isMissile then
            point.state = (roll < 0.6) and "idle" or "fired"
        else
            if roll < 0.5 then point.state = "idle"
            elseif roll < 0.8 then point.state = "fired"
            else point.state = "hit" end
        end
    end
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
    setObserving(true, currentSession and currentSession.aimTargetID)
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
    turretMap = nil
end

local startTurretMapTicker, turretMapDraw3D
local function startTurretMapProbe()
    -- Read the live session, not getCurrentShipSweep(): that one requires the
    -- gunner chair, and Gunnery Control is also opened onboard (docked menu).
    local session = api() and api().getSession and api().getSession()
    if not session or not session.shipID then
        local reason = api() and "no Gunnery session" or "no API"
        turretMap = { failReason = reason, points = {} }
        log("turretmap", { action = "on", ok = "false", reason = reason })
        menu.display()
        return
    end
    local ship = { id = tostring(session.shipID) }
    local points = {}
    for _, group in ipairs(session.groups or {}) do
        local selected = session.checkedGroupKeys and session.checkedGroupKeys[group.key] and true or false
        for _, member in ipairs(group.members or {}) do
            if member.operational then
                local macro = tostring(GetComponentData(ConvertStringTo64Bit(tostring(member.componentID)), "macro") or "")
                points[#points + 1] = {
                    id = tostring(member.componentID), componentID = member.componentID,
                    name = member.displayName or "?", groupName = group.displayName or "?",
                    macro = macro, isMissile = macro:find("missile") ~= nil,
                    selected = selected, state = selected and "idle" or "unselected", sourceIndex = #points + 1,
                }
            end
        end
    end
    turretMap = {
        ship = ship, points = points, typeIcons = true, synthetic = false, preview = true, cycle = {}, yaw = 0, pitch = 25,
        nextShuffle = getElapsedTime() + 1, renderCount = 0, shuffleCount = 0, lastRenderKey = nil,
    }
    log("turretmap", { action = "on", ok = "true", points = #points })
    startTurretMapTicker()
    for i, point in ipairs(points) do
        AddUITriggeredEvent("X4GunneryTestLabObserve", "turretmap_position", {
            ship = ConvertStringToLuaID(ship.id), turret = ConvertStringToLuaID(point.id), idx = i,
        })
    end
    menu.display()
end

-- Pads the real point list up to exactly 101 by repeating real points with
-- small deterministic jitter, keeping sourceIndex so a click on a synthetic
-- point still focuses the real turret it was copied from.
local function turretMapDrawPoints(range)
    if not turretMap.synthetic then return turretMap.points end
    local drawn, real = {}, turretMap.points
    for _, point in ipairs(real) do drawn[#drawn + 1] = point end
    local jitter = range * 0.02
    local k = 0
    -- Bounded: if every real position failed, base.x is never set.
    while #drawn < 101 and k < 101 * math.max(#real, 1) do
        k = k + 1
        local base = real[((k - 1) % #real) + 1]
        if base.x then
            -- Deterministic pseudo-jitter from k, no math.random so repeated
            -- renders of the same padded set stay visually stable.
            local dx = jitter * (((k * 37) % 7) - 3) / 3
            local dz = jitter * (((k * 53) % 7) - 3) / 3
            local dy = jitter * (((k * 61) % 7) - 3) / 3
            drawn[#drawn + 1] = {
                id = base.id, name = base.name .. " #" .. k .. " (synthetic)",
                groupName = base.groupName, macro = base.macro, isMissile = base.isMissile,
                x = base.x + dx, y = base.y + dy, z = base.z + dz,
                selected = base.selected, state = base.state, sourceIndex = base.sourceIndex,
            }
        end
    end
    return drawn
end

-- Equal-scale symmetric axis range so the ship silhouette is not stretched.
local function turretMapAxisRange(values, minExtent)
    local extent = minExtent
    for _, v in ipairs(values) do extent = math.max(extent, math.abs(v)) end
    return extent * 1.15
end

-- The X4 graph widget failed live (one graph per UI, 5-icon cap, smeared
-- circle markers). Two replacements are probed side by side:
--   * a compact table-icon grid: function-valued icon colour and hover text
--     that frame:update() re-evaluates without a rebuild; clickable;
--   * a 3D view drawn with the widget system's shapes (Helper.drawCircle /
--     drawLine, as menu_encyclopedia/menu_timeline use): exact positions, any
--     colour, no hover or click. Shape pools: 100 circles, 1000 rectangles.
-- Tables cap at 13 columns (helper.lua maxTableCols).
local TURRETMAP_COLS, TURRETMAP_ROWS, TURRETMAP_CELL = 13, 3, 20
local TURRETMAP_MAX_CIRCLES = 95
local TURRETMAP_RANK = { unselected = 1, idle = 2, fired = 3, hit = 4 }

local function turretMapColors()
    return { unselected = Color["text_inactive"], idle = Color["icon_normal"],
        fired = Color["text_warning"], hit = Color["text_positive"] }
end

local function turretMapIcon(macro)
    local m = tostring(macro or "")
    for _, rule in ipairs({ { "_beam_", "weapon_beam_mk1" }, { "_plasma_", "weapon_plasma_mk1" },
            { "_ion_", "weapon_ion_mk1" }, { "_gatling_", "weapon_gatling_mk1" },
            { "_shotgun_", "weapon_shotgun_mk1" }, { "_flak_", "weapon_shotgun_mk1" },
            { "_disruptor_", "weapon_bor_disruptor_mk1" }, { "_railgun_", "weapon_railgun_mk1" },
            { "_cannon_", "weapon_cannon_mk1" }, { "_laser_", "weapon_laser_mk1" },
            { "_arc_", "weapon_bor_arc_mk1" } }) do
        if m:find(rule[1], 1, true) then return rule[2] end
    end
    return "ency_timeline_dot_01"
end

-- Normalise each axis to [-1, 1] over the turrets' bounding box (schematic).
local function turretMapNormaliser(points)
    local lo, hi = { x = math.huge, y = math.huge, z = math.huge }, { x = -math.huge, y = -math.huge, z = -math.huge }
    for _, p in ipairs(points) do
        if p.x then
            for _, k in ipairs({ "x", "y", "z" }) do lo[k], hi[k] = math.min(lo[k], p[k]), math.max(hi[k], p[k]) end
        end
    end
    return function(p, k)
        if hi[k] - lo[k] < 1 then return 0 end
        return (p[k] - lo[k]) / (hi[k] - lo[k]) * 2 - 1
    end
end

local function turretMapCellState(list)
    local best = "unselected"
    for _, p in ipairs(list) do
        if TURRETMAP_RANK[p.state] > TURRETMAP_RANK[best] then best = p.state end
    end
    return best
end

-- Compact grid: columns stern -> bow, rows by the second axis.
local function turretMapAddGrid(tableView, title, points, norm, axisB, flipB)
    local titleRow = tableView:addRow(false, {})
    titleRow[1]:setColSpan(TURRETMAP_COLS):createText(title, { fontsize = Helper.scaleFont(Helper.standardFont, 9) })
    local cells = {}
    for _, p in ipairs(points) do
        if p.x then
            local col = math.floor((norm(p, "z") + 1) / 2 * (TURRETMAP_COLS - 1) + 0.5) + 1
            local b = norm(p, axisB) * (flipB and -1 or 1)
            local row = TURRETMAP_ROWS - math.floor((b + 1) / 2 * (TURRETMAP_ROWS - 1) + 0.5)
            local key = row * 100 + col
            cells[key] = cells[key] or {}
            table.insert(cells[key], p)
        end
    end
    local colors, shared = turretMapColors(), 0
    for r = 1, TURRETMAP_ROWS do
        local row = tableView:addRow(true, { bgColor = Color["row_background_blue"] })
        for c = 1, TURRETMAP_COLS do
            local list = cells[r * 100 + c]
            if list then
                if #list > 1 then shared = shared + 1 end
                local key = title .. ":" .. r .. ":" .. c
                local button = row[c]:createButton({ height = TURRETMAP_CELL,
                    bgColor = Color["button_background_hidden"], highlightColor = Color["button_highlight_default"],
                    borderColor = Color["button_border_hidden"],
                    mouseOverText = function()
                        local lines = {}
                        for _, p in ipairs(list) do lines[#lines + 1] = p.name .. " — " .. p.groupName .. " [" .. p.state .. "]" end
                        return table.concat(lines, "\n")
                    end })
                button:setIcon(turretMap.typeIcons and turretMapIcon(list[1].macro) or "ency_timeline_dot_01",
                    { color = function() return colors[turretMapCellState(list)] end })
                if #list > 1 then button:setText(tostring(#list), { halign = "right", fontsize = Helper.scaleFont(Helper.standardFont, 8) }) end
                row[c].handlers.onClick = function()
                    -- Repeated clicks cycle through every turret in the cell.
                    local nextIndex = ((turretMap.cycle[key] or 0) % #list) + 1
                    turretMap.cycle[key] = nextIndex
                    local real = turretMap.points[list[nextIndex].sourceIndex]
                    if not real then return end
                    local ok, reason = api().enterCamera({ componentID = real.componentID, cameraSupported = true })
                    log("turretmap", { action = "click", view = title, turret = real.id, cycle = nextIndex .. "/" .. #list, ok = tostring(ok), reason = tostring(reason or "") })
                end
            else
                row[c]:createText("", { minRowHeight = TURRETMAP_CELL })
            end
        end
    end
    local ends = tableView:addRow(false, {})
    ends[1]:setColSpan(3):createText("STERN", { fontsize = Helper.scaleFont(Helper.standardFont, 8) })
    ends[11]:setColSpan(3):createText("BOW", { halign = "right", fontsize = Helper.scaleFont(Helper.standardFont, 8) })
    return shared
end

-- Orthographic 3D view with yaw/pitch from the sliders, true proportions,
-- scaled to fit. X4 ship-local axes: x starboard, y dorsal, z bow. At yaw 0 the
-- bow points right and pitch tilts the camera down onto the deck, so port is
-- the near side. A generic grey hull outline on the y = 0 plane rotates with
-- the view: pointed bow, thick port edge.
turretMapDraw3D = function()
    HideAllCircles(); HideAllRects()
    local area = turretMap and turretMap.area3d
    if not area then return end
    local yaw, pitch = math.rad(turretMap.yaw or 0), math.rad(turretMap.pitch or 25)
    local cy_, sy_, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    local function view(x, y, z)
        local h = z * cy_ - x * sy_
        local d = z * sy_ + x * cy_          -- + = away from the viewer at yaw 0
        return h, y * cp + d * sp, d * cp - y * sp
    end
    local turrets = {}
    local zlo, zhi, wmax = math.huge, -math.huge, 10
    for _, p in ipairs(area.points) do
        if p.x then
            turrets[#turrets + 1] = p
            zlo, zhi, wmax = math.min(zlo, p.z), math.max(zhi, p.z), math.max(wmax, math.abs(p.x) * 1.1)
        end
    end
    if #turrets == 0 then return end
    local len = math.max(zhi - zlo, 20)
    local sternZ, shoulderZ, bowZ = zlo - 0.05 * len, zlo + 0.75 * len, zhi + 0.12 * len
    local hull = { { -wmax, sternZ }, { wmax, sternZ }, { wmax, shoulderZ }, { 0, bowZ }, { -wmax, shoulderZ } }
    -- Fit: project everything once, then scale the bounding box into the area.
    local hlo, hhi, vlo, vhi = math.huge, -math.huge, math.huge, -math.huge
    local function extend(h, v) hlo, hhi, vlo, vhi = math.min(hlo, h), math.max(hhi, h), math.min(vlo, v), math.max(vhi, v) end
    for _, c in ipairs(hull) do extend(view(c[1], 0, c[2])) end
    for _, p in ipairs(turrets) do extend(view(p.x, p.y, p.z)) end
    local pad = 14
    local scale = math.min((area.w - 2 * pad) / math.max(hhi - hlo, 1), (area.h - 2 * pad) / math.max(vhi - vlo, 1))
    local ox = area.x + area.w / 2 - (hlo + hhi) / 2 * scale
    local oy = area.y + area.h / 2 + (vlo + vhi) / 2 * scale
    local function screen(x, y, z)
        local h, v, d = view(x, y, z)
        return ox + h * scale, oy - v * scale, d
    end
    local function line(ax, ay, bx, by, color, thickness)
        Helper.drawLine({ x = ax, y = ay }, { x = bx, y = by }, thickness or 1, nil, color, true)
    end
    local outline, faint = Color["text_inactive"], Color["row_background_blue"]
    for i, c in ipairs(hull) do
        local n = hull[i % #hull + 1]
        local ax, ay = screen(c[1], 0, c[2])
        local bx, by = screen(n[1], 0, n[2])
        -- Edges 5->1 and 4->5 lie on the port (-x) side.
        local port = (i == 4) or (i == 5)
        line(ax, ay, bx, by, outline, port and 3 or 1)
    end
    local kx, ky = screen(0, 0, sternZ)
    local bx, by = screen(0, 0, bowZ)
    line(kx, ky, bx, by, faint, 1)

    local colors = turretMapColors()
    local radius = (#turrets > 40) and 4 or 7
    local projected = {}
    for _, p in ipairs(turrets) do
        local sx, sy, depth = screen(p.x, p.y, p.z)
        local fx, fy = screen(p.x, 0, p.z)
        projected[#projected + 1] = { p = p, sx = sx, sy = sy, fx = fx, fy = fy, depth = depth }
    end
    table.sort(projected, function(a, b) return a.depth > b.depth end) -- far first
    for index, q in ipairs(projected) do
        line(q.sx, q.sy, q.fx, q.fy, faint, 1)
        if index <= TURRETMAP_MAX_CIRCLES then
            Helper.drawCircle(radius, q.sx, q.sy, nil, colors[q.p.state], true)
        else
            -- Circle pool exhausted: fall back to squares from the rectangle pool.
            Helper.drawRectangle(radius * 2, radius * 2, q.sx - radius, q.sy - radius, 0, nil, colors[q.p.state], true)
        end
    end
end

local function turretMapBody(tableView, frameX, frameY)
    local cols = TURRETMAP_COLS
    local small = { fontsize = Helper.scaleFont(Helper.standardFont, 9) }
    local title = tableView:addRow(false, { bgColor = Color["row_title_background"] })
    title[1]:setColSpan(cols):createText("Turret map probe (issue #205)", Helper.headerRowCenteredProperties)

    if not turretMap.ship then
        local row = tableView:addRow(false, {})
        row[1]:setColSpan(cols):createText("Turret map probe failed: " .. tostring(turretMap.failReason))
        local off = tableView:addRow("tm_off", {})
        off[1]:setColSpan(cols):createButton({}):setText("Probe: OFF")
        off[1].handlers.onClick = function() turretMap = nil; HideAllCircles(); HideAllRects(); menu.display() end
        return
    end

    local controls = tableView:addRow("tm_controls", {})
    controls[1]:setColSpan(3):createButton({}):setText("Probe: OFF")
    controls[1].handlers.onClick = function() turretMap = nil; HideAllCircles(); HideAllRects(); menu.display() end
    controls[4]:setColSpan(3):createButton({}):setText("Icons: " .. (turretMap.typeIcons and "weapon" or "dot"))
    controls[4].handlers.onClick = function() turretMap.typeIcons = not turretMap.typeIcons; turretMap.lastRenderKey = nil; menu.display() end
    controls[7]:setColSpan(3):createButton({}):setText("States: " .. (turretMap.preview and "preview all 4" or "real selection"))
    controls[7].handlers.onClick = function() turretMap.preview = not turretMap.preview; turretMap.lastRenderKey = nil; menu.display() end
    controls[10]:setColSpan(4):createButton({}):setText("Synthetic 101: " .. (turretMap.synthetic and "ON" or "OFF"))
    controls[10].handlers.onClick = function() turretMap.synthetic = not turretMap.synthetic; turretMap.lastRenderKey = nil; menu.display() end

    local colors = turretMapColors()
    local legend = tableView:addRow(false, {})
    for index, spec in ipairs({ { "unselected", "not selected" }, { "idle", "selected, idle" }, { "fired", "firing" }, { "hit", "hitting" } }) do
        legend[(index - 1) * 3 + 1]:setColSpan(3):createText(spec[2], { color = colors[spec[1]], fontsize = small.fontsize })
    end

    local received, total = turretMapReceivedCount(), #turretMap.points
    if received < total then
        local statusRow = tableView:addRow(false, {})
        statusRow[1]:setColSpan(cols):createText("positions received " .. received .. " / " .. total)
        return
    end

    local rangeSeed = {}
    for _, point in ipairs(turretMap.points) do
        if point.x then rangeSeed[#rangeSeed + 1] = point.x; rangeSeed[#rangeSeed + 1] = point.y; rangeSeed[#rangeSeed + 1] = point.z end
    end
    local drawPoints = turretMapDrawPoints(turretMapAxisRange(rangeSeed, 10))
    local norm = turretMapNormaliser(drawPoints)

    -- 3D view: reserve an empty block; shapes are drawn over it after display.
    local label3d = tableView:addRow(false, {})
    label3d[1]:setColSpan(cols):createText("3D (shapes; no hover/click). Pointed end = BOW, thick edge = PORT. Drag sliders to rotate.", small)
    local rotate = tableView:addRow("tm_rotate", {})
    rotate[1]:setColSpan(2):createText("Yaw", small)
    rotate[3]:setColSpan(4):createSliderCell({ min = -180, max = 180, start = turretMap.yaw or 0, step = 5, height = Helper.standardTextHeight })
    rotate[3].handlers.onSliderCellChanged = function(_, value) turretMap.yaw = value; turretMapDraw3D() end
    -- One slider cell per row: X4 rejects a second one ("Slidercell defined
    -- although excluded by other row content") and reloads the whole UI.
    local tilt = tableView:addRow("tm_tilt", {})
    tilt[1]:setColSpan(2):createText("Pitch", small)
    tilt[3]:setColSpan(4):createSliderCell({ min = -90, max = 90, start = turretMap.pitch or 25, step = 5, height = Helper.standardTextHeight })
    tilt[3].handlers.onSliderCellChanged = function(_, value) turretMap.pitch = value; turretMapDraw3D() end
    -- Preset quarter views from 30 degrees above. Viewer sits at ship-local
    -- (z, x) = (-sin yaw, -cos yaw), so yaw 0 looks from port, bow right.
    local presets = tableView:addRow("tm_presets", {})
    for index, preset in ipairs({ { "Port-bow", -45 }, { "Stbd-bow", -135 }, { "Port-stern", 45 }, { "Stbd-stern", 135 } }) do
        local cell = presets[(index - 1) * 3 + 1]
        cell:setColSpan(index == 4 and 4 or 3):createButton({}):setText(preset[1])
        cell.handlers.onClick = function()
            turretMap.yaw, turretMap.pitch = preset[2], 30
            log("turretmap", { action = "view", preset = preset[1] })
            menu.display()
        end
    end
    local areaTop = tableView:getFullHeight()
    local areaH = Helper.scaleY(170)
    tableView:addEmptyRow(areaH, false)
    turretMap.area3d = { x = frameX + tableView.properties.x, y = frameY + tableView.properties.y + areaTop,
        w = tableView.properties.width, h = areaH, points = drawPoints }

    local sharedTop = turretMapAddGrid(tableView, "Grid top view (hover/click; upper row = PORT)", drawPoints, norm, "x", true)
    local sharedSide = turretMapAddGrid(tableView, "Grid side view (upper row = DORSAL)", drawPoints, norm, "y", false)

    local renderKey = tostring(turretMap.typeIcons) .. ":" .. tostring(turretMap.synthetic) .. ":" .. tostring(turretMap.preview)
    if renderKey ~= turretMap.lastRenderKey then
        turretMap.lastRenderKey = renderKey
        log("turretmap", { action = "render", renderer = "grid+shapes", icons = tostring(turretMap.typeIcons),
            synthetic = tostring(turretMap.synthetic), preview = tostring(turretMap.preview), points = #drawPoints,
            shared_cells_top = sharedTop, shared_cells_side = sharedSide,
            area = string.format("%d,%d,%dx%d", turretMap.area3d.x, turretMap.area3d.y, turretMap.area3d.w, turretMap.area3d.h) })
    end
end

-- Own 1 Hz ticker: Test Lab's menu.onUpdate never runs, because onShowMenu
-- redraws via Helper.clearMenu, which clears the handler Helper installed
-- just before calling onShowMenu (helper.lua ~1408 vs ~1436).
local turretMapTickGeneration = 0
local function turretMapTick(generation)
    if generation ~= turretMapTickGeneration or not turretMap or not turretMap.ship then return end
    if turretMapPendingCount() == 0 then
        turretMapShuffleStates()
        turretMap.shuffleCount = turretMap.shuffleCount + 1
        if turretMap.shuffleCount % 10 == 0 then
            log("turretmap", { action = "update", updates = turretMap.shuffleCount })
        end
        if menu.turretMapFrame then menu.turretMapFrame:update() end
        turretMapDraw3D()
    end
    Helper.addDelayedOneTimeCallbackOnUpdate(function() turretMapTick(generation) end, false, getElapsedTime() + 1)
end

startTurretMapTicker = function()
    turretMapTickGeneration = turretMapTickGeneration + 1
    local generation = turretMapTickGeneration
    Helper.addDelayedOneTimeCallbackOnUpdate(function() turretMapTick(generation) end, false, getElapsedTime() + 1)
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
    if turretMap then
        -- Not Helper.clearMenu: it also drops the menu's onUpdate ticker
        -- (onUpdateHandler = nil), which stopped the probe's 1 Hz refresh.
        Helper.clearDataForRefresh(menu)
        local width = Helper.scaleX(700)
        local frameX, frameY = math.floor((Helper.viewWidth - width) / 2), Helper.scaleY(60)
        local frame = Helper.createFrameHandle(menu, { x = frameX, y = frameY, width = width, standardButtons = { close = true } })
        local tableView = frame:addTable(TURRETMAP_COLS, { tabOrder = 1, x = Helper.borderSize, y = Helper.borderSize, width = width - 2 * Helper.borderSize })
        turretMapBody(tableView, frameX, frameY)
        frame.properties.height = tableView.properties.y + tableView:getFullHeight() + 2 * Helper.borderSize
        frame:display()
        menu.turretMapFrame = frame
        turretMapDraw3D()
        return
    end
    Helper.clearMenu(menu)
    -- Leave the camera unobscured during the mandatory five-second visual check.
    -- The menu remains registered, so onUpdate continues to poll its stability.
    if sweep and sweep.phase == "inspecting" then return end
    local frame = Helper.createFrameHandle(menu, { width = Helper.scaleX(900), height = Helper.scaleY(520), standardButtons = { close = true } })
    local tableView = frame:addTable(4, { tabOrder = 1, width = Helper.scaleX(880) })
    local title = tableView:addRow(false, { bgColor = Color["row_title_background"] })
    title[1]:setColSpan(4):createText(text(1), Helper.headerRowCenteredProperties)
    local tmRow = tableView:addRow("tm_open", {})
    tmRow[1]:setColSpan(4):createButton({}):setText("Turret map probe")
    tmRow[1].handlers.onClick = function() startTurretMapProbe() end
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
    RegisterEvent("X4GunneryTestLab.TurretMapPosition", onTurretMapPosition)
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
