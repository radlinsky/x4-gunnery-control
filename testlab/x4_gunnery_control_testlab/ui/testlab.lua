-- Developer-only current-ship turret sweep. The production extension owns all
-- turret discovery and mutations; this companion only drives its narrow API.
local State = X4GunneryTestLabState
local menu = { name = "X4GunneryTestLab", uixID = "x4_gunnery_control_testlab" }
local sweep, inspectStarted, nextPoll, stableSamples, unstableSamples, technical, targetBefore, targetPreserved, closing, suppressReopen = nil, nil, nil, 0, 0, nil, nil, nil, false, false
local scenarioActionStatus, scenarioRequestSerial, pendingScenario, remoteScenarioReady = nil, 0, nil, false
-- Two-phase #67 station B geometry discriminator: after the OOS census the
-- fixture is only geometry-PENDING; the split is measured in system once the
-- owner teleports aboard the preserved Colossus. onGeometryQualified.
local pendingQualify, remoteGeometryPending = nil, false
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
        if type(group.count) ~= "number" or group.count < 1 then return nil, where .. ".count must be a positive number" end
        -- Signed, like x and y: MD passes this straight to safepos as z, so a
        -- negative value spawns the group astern. The old non-negative guard
        -- rejected the whole spec whenever a group used that.
        if type(group.distance) ~= "number" then return nil, where .. ".distance must be a number" end
        local behaviour = group.behaviour or "wait"
        if behaviour ~= "wait" and behaviour ~= "attack" and behaviour ~= "none" then
            return nil, where .. ".behaviour must be wait, attack or none"
        end
        local role = tostring(group.role or "")
        if role ~= "" and role ~= "shooter" then
            return nil, where .. ".role must be empty or shooter"
        end
        local geometryRole = tostring(group.geometryRole or "")
        if geometryRole ~= "" and geometryRole ~= "clear_arc" and geometryRole ~= "below_arc" then
            return nil, where .. ".geometryRole must be empty, clear_arc, or below_arc"
        end
        local expectedMissileTurrets = tonumber(group.expectedMissileTurrets) or 0
        local expectedGuided = tonumber(group.expectedGuided) or 0
        local expectedDumbfire = tonumber(group.expectedDumbfire) or 0
        local expectedAmmo = tonumber(group.expectedAmmo) or 0
        local expectedWeapons = tonumber(group.expectedWeapons) or 0
        local expectedTurrets = tonumber(group.expectedTurrets) or 0
        local expectedBeam = tonumber(group.expectedBeam) or 0
        local expectedPlasma = tonumber(group.expectedPlasma) or 0
        for field, value in pairs({ expectedWeapons = expectedWeapons,
                expectedTurrets = expectedTurrets, expectedBeam = expectedBeam,
                expectedPlasma = expectedPlasma,
                expectedMissileTurrets = expectedMissileTurrets,
                expectedGuided = expectedGuided, expectedDumbfire = expectedDumbfire,
                expectedAmmo = expectedAmmo }) do
            if value < 0 or value ~= math.floor(value) then
                return nil, where .. "." .. field .. " must be a non-negative integer"
            end
        end
        if role == "shooter" then
            if group.loadout ~= "issue65_odysseus_mixed_missiles"
                    and group.loadout ~= "issue67_colossus_arc_barrel" then
                return nil, where .. ".loadout is not a supported shooter loadout"
            end
            local missileCensus = expectedMissileTurrets > 0
                and expectedGuided + expectedDumbfire == expectedMissileTurrets
                and expectedAmmo > 0
            -- issue67 arms group_front_left_up (beam, 2 turrets) and
            -- group_front_right_up (plasma, 2 turrets) via per-group loadout
            -- entries. The census invariant (`.weapons` and `.turrets` both
            -- count turret-mounted weapons => 4) is live-tested on Behemoth E
            -- only (d7e3870); the Colossus mount/census is not yet live-verified
            -- (slots shipped-source, _02 compatibility inference).
            local conventionalCensus = expectedWeapons == 4 and expectedTurrets == 4
                and expectedBeam == 2 and expectedPlasma == 2
                and expectedMissileTurrets == 0 and expectedAmmo == 0
            if (group.loadout == "issue65_odysseus_mixed_missiles" and not missileCensus)
                    or (group.loadout == "issue67_colossus_arc_barrel" and not conventionalCensus) then
                return nil, where .. " has an inconsistent shooter census"
            end
        end
        groups[#groups + 1] = {
            label = tostring(group.label or ("group" .. index)),
            macro = group.macro,
            faction = group.faction,
            count = math.floor(group.count),
            distance = group.distance,
            spread = tonumber(group.spread) or 0,
            x = tonumber(group.x) or 0,
            y = tonumber(group.y) or 0,
            behaviour = behaviour,
            hostile = group.hostile == true,
            holdFire = group.holdFire == true,
            stripDefenceUnits = group.stripDefenceUnits == true,
            repairGuard = group.repairGuard == true,
            yaw = tonumber(group.yaw) or 0,
            role = role,
            loadout = tostring(group.loadout or ""),
            geometryRole = geometryRole,
            expectedWeapons = expectedWeapons,
            expectedTurrets = expectedTurrets,
            expectedBeam = expectedBeam,
            expectedPlasma = expectedPlasma,
            expectedMissileTurrets = expectedMissileTurrets,
            expectedGuided = expectedGuided,
            expectedDumbfire = expectedDumbfire,
            expectedAmmo = expectedAmmo,
        }
    end
    local stations = {}
    if raw.stations ~= nil and type(raw.stations) ~= "table" then
        return nil, "spec.stations must be a list"
    end
    for index, station in ipairs(raw.stations or {}) do
        local where = "stations[" .. index .. "]"
        if type(station) ~= "table" then return nil, where .. " is not a table" end
        if station.recipe ~= "xen_defence" then
            return nil, where .. ".recipe must be xen_defence"
        end
        if type(station.faction) ~= "string" or station.faction == "" then
            return nil, where .. ".faction must be a non-empty string"
        end
        if type(station.distance) ~= "number" then
            return nil, where .. ".distance must be a number"
        end
        if type(station.expectedModules) ~= "number" or station.expectedModules < 1 then
            return nil, where .. ".expectedModules must be a positive number"
        end
        if type(station.minSurfaces) ~= "number" or station.minSurfaces < 1 then
            return nil, where .. ".minSurfaces must be a positive number"
        end
        local geometryRole = tostring(station.geometryRole or "")
        if geometryRole ~= "" and geometryRole ~= "aim_split" then
            return nil, where .. ".geometryRole must be empty or aim_split"
        end
        local searchAttempts = tonumber(station.searchAttempts) or 1
        if searchAttempts < 1 or searchAttempts > 12 or searchAttempts ~= math.floor(searchAttempts) then
            return nil, where .. ".searchAttempts must be an integer from 1 to 12"
        end
        stations[#stations + 1] = {
            label = tostring(station.label or ("station" .. index)),
            recipe = station.recipe,
            faction = station.faction,
            distance = station.distance,
            spread = tonumber(station.spread) or 0,
            x = tonumber(station.x) or 0,
            y = tonumber(station.y) or 0,
            hostile = station.hostile == true,
            holdFire = station.holdFire == true,
            geometryRole = geometryRole,
            searchAttempts = searchAttempts,
            searchStepY = tonumber(station.searchStepY) or 0,
            expectedModules = math.floor(station.expectedModules),
            minSurfaces = math.floor(station.minSurfaces),
        }
    end
    if #groups == 0 and #stations == 0 then
        return nil, "spec.groups is empty"
    end
    local setup
    if raw.setup ~= nil then
        if type(raw.setup) ~= "table" then return nil, "spec.setup must be a table" end
        for _, field in ipairs({ "shipMacro", "shipLabel", "turretGroup", "turretLabel" }) do
            if type(raw.setup[field]) ~= "string" or raw.setup[field] == "" then
                return nil, "spec.setup." .. field .. " must be a non-empty string"
            end
        end
        if type(raw.setup.expectedTurrets) ~= "number" or raw.setup.expectedTurrets < 1 then
            return nil, "spec.setup.expectedTurrets must be a positive number"
        end
        local expectedMacros = {}
        if raw.setup.expectedMacros ~= nil then
            if type(raw.setup.expectedMacros) ~= "table" then
                return nil, "spec.setup.expectedMacros must be a list"
            end
            for index, macro in ipairs(raw.setup.expectedMacros) do
                if type(macro) ~= "string" or macro == "" then
                    return nil, "spec.setup.expectedMacros[" .. index .. "] must be a non-empty string"
                end
                expectedMacros[#expectedMacros + 1] = macro
            end
            if #expectedMacros ~= math.floor(raw.setup.expectedTurrets) then
                return nil, "spec.setup.expectedMacros must match expectedTurrets"
            end
            table.sort(expectedMacros)
        end
        setup = {
            remote = raw.setup.remote == true,
            shipMacro = raw.setup.shipMacro,
            shipLabel = raw.setup.shipLabel,
            turretGroup = raw.setup.turretGroup,
            turretLabel = raw.setup.turretLabel,
            expectedTurrets = math.floor(raw.setup.expectedTurrets),
            expectedMacros = expectedMacros,
            selectAll = raw.setup.selectAll == true,
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
        id = raw.id, enabled = raw.enabled, groups = groups, stations = stations,
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

-- A spec with an aim_split station cannot be qualified from the out-of-system
-- census: its root-vs-aim split only resolves in system, so the remote READY is
-- a PENDING state that a post-teleport in-system re-measurement must clear.
local function specHasAimSplit()
    for _, station in ipairs(scenarioSpec and scenarioSpec.stations or {}) do
        if station.geometryRole == "aim_split" then return true end
    end
    return false
end

-- A remote fixture's player ship is disposable only while the owner is not
-- aboard it.  Keep this identity check deliberately narrower than
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
            yaw = group.yaw, role = group.role, loadout = group.loadout,
            geometryRole = group.geometryRole,
            expectedWeapons = group.expectedWeapons,
            expectedTurrets = group.expectedTurrets,
            expectedBeam = group.expectedBeam,
            expectedPlasma = group.expectedPlasma,
            expectedMissileTurrets = group.expectedMissileTurrets,
            expectedGuided = group.expectedGuided,
            expectedDumbfire = group.expectedDumbfire,
            expectedAmmo = group.expectedAmmo,
        })
    end
    for _, station in ipairs(scenarioSpec.stations) do
        AddUITriggeredEvent("X4GunneryTestLabScenario", "scenario_station", {
            label = station.label, recipe = station.recipe, faction = station.faction,
            distance = station.distance, spread = station.spread,
            x = station.x, y = station.y, hostile = station.hostile,
            holdFire = station.holdFire, geometryRole = station.geometryRole,
            searchAttempts = station.searchAttempts, searchStepY = station.searchStepY,
            expectedModules = station.expectedModules, minSurfaces = station.minSurfaces,
        })
    end
    AddUITriggeredEvent("X4GunneryTestLabScenario", "scenario_commit")
    log("scenario_spec", { action = "sent", spec_id = scenarioSpec.id,
        groups = #scenarioSpec.groups, stations = #scenarioSpec.stations,
        forced = tostring(force == true) })
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
    if #setup.expectedMacros > 0
            and table.concat(memberMacros, ",") ~= table.concat(setup.expectedMacros, ",") then
        return nil, setup.turretLabel .. " needs macros " .. table.concat(setup.expectedMacros, ",")
            .. ", found " .. table.concat(memberMacros, ",")
    end
    table.sort(memberIDs)
    table.sort(groupKeys)
    return {
        label = setup.turretLabel,
        rawGroup = setup.turretGroup,
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
        selection = resolveExactGroup()
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
        selection = nil
    end
    if not remote then
        selection, reason = resolveExactGroup()
        if not selection then
            scenarioActionStatus = "FAILED: " .. reason
            log("scenario_create", { action = "rejected", reason = reason })
            menu.display()
            return
        end
    end
    local expectedShips, expectedHostiles, expectedRepairFixtures = 0, 0, 0
    local expectedShooters, expectedMissileTurrets, expectedGuided = 0, 0, 0
    local expectedDumbfire, expectedAmmo = 0, 0
    local expectedWeapons, expectedTurrets, expectedBeam, expectedPlasma = 0, 0, 0, 0
    local expectedGeometrySplits = 0
    for _, group in ipairs(scenarioSpec.groups) do
        expectedShips = expectedShips + group.count
        if group.hostile then expectedHostiles = expectedHostiles + group.count end
        if group.repairGuard then expectedRepairFixtures = expectedRepairFixtures + group.count end
        if group.role == "shooter" then expectedShooters = expectedShooters + group.count end
        expectedWeapons = expectedWeapons + group.expectedWeapons * group.count
        expectedTurrets = expectedTurrets + group.expectedTurrets * group.count
        expectedBeam = expectedBeam + group.expectedBeam * group.count
        expectedPlasma = expectedPlasma + group.expectedPlasma * group.count
        expectedMissileTurrets = expectedMissileTurrets + group.expectedMissileTurrets * group.count
        expectedGuided = expectedGuided + group.expectedGuided * group.count
        expectedDumbfire = expectedDumbfire + group.expectedDumbfire * group.count
        expectedAmmo = expectedAmmo + group.expectedAmmo * group.count
    end
    local expectedStations, expectedModules, minSurfaces, expectedSafeFixtures = #scenarioSpec.stations, 0, 0, 0
    for _, group in ipairs(scenarioSpec.groups) do
        if group.holdFire then expectedSafeFixtures = expectedSafeFixtures + group.count end
    end
    for _, station in ipairs(scenarioSpec.stations) do
        expectedModules = expectedModules + station.expectedModules
        minSurfaces = minSurfaces + station.minSurfaces
        if station.hostile then expectedHostiles = expectedHostiles + 1 end
        if station.holdFire then expectedSafeFixtures = expectedSafeFixtures + 1 end
        -- An aim_split station produces NO out-of-system split: it is preserved at
        -- attempt-0 and the split is re-measured in system by GeometryQualify, so
        -- the OOS acknowledgement must still expect zero splits.
    end
    scenarioRequestSerial = scenarioRequestSerial + 1
    local requestId = clockToken(GetCurRealTime()) .. "_" .. tostring(scenarioRequestSerial)
    pendingScenario = {
        requestId = requestId,
        specId = scenarioSpec.id,
        expectedShips = expectedShips,
        expectedStations = expectedStations,
        expectedModules = expectedModules,
        minSurfaces = minSurfaces,
        expectedSafeFixtures = expectedSafeFixtures,
        expectedRepairFixtures = expectedRepairFixtures,
        expectedDefenceUnits = 0,
        expectedHostiles = expectedHostiles,
        expectedShooters = expectedShooters,
        expectedWeapons = expectedWeapons,
        expectedTurrets = expectedTurrets,
        expectedBeam = expectedBeam,
        expectedPlasma = expectedPlasma,
        expectedMissileTurrets = expectedMissileTurrets,
        expectedGuided = expectedGuided,
        expectedDumbfire = expectedDumbfire,
        expectedAmmo = expectedAmmo,
        expectedLocationFailures = 0,
        expectedLoadoutFailures = 0,
        expectedPreflightFailures = 0,
        expectedGeometrySplits = expectedGeometrySplits,
        deadline = getElapsedTime() + (expectedStations > 0 and 60 or 10),
        selection = selection,
        remote = remote,
    }
    scenarioActionStatus = "CREATING: replacing the previous fixture and verifying "
        .. expectedShips .. " ships, " .. expectedStations .. " stations, and live surfaces..."
    sendScenarioSpec(true, requestId)
    log("scenario_create", {
        action = "requested", spec_id = scenarioSpec.id, expected_ships = expectedShips,
        expected_stations = expectedStations, expected_modules = expectedModules,
        min_surfaces = minSurfaces,
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
    local value = tostring(param or "")
    local requestId, specId, spawned, stations, modules, turrets, missileTurrets, shields, engines,
        safeFixtures, safeWeapons, unsafeWeapons, defenceUnits, hostiles, repairFixtures,
        shooters, shooterMissileTurrets, guided, dumbfire, ammo, loadoutFailures, locationFailures,
        shooterWeapons, shooterTurrets, shooterBeam, shooterPlasma,
        preflightFailures, geometrySplits =
        value:match("^x4gct8:([^:]+):([^:]+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
    if not requestId then
        requestId, specId, spawned, stations, modules, turrets, missileTurrets, shields, engines,
            safeFixtures, safeWeapons, unsafeWeapons, defenceUnits, hostiles, repairFixtures,
            shooters, shooterMissileTurrets, guided, dumbfire, ammo, loadoutFailures, locationFailures =
            value:match("^x4gct7:([^:]+):([^:]+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
        shooterWeapons, shooterTurrets, shooterBeam, shooterPlasma,
            preflightFailures, geometrySplits = "0", "0", "0", "0", "0", "0"
    end
    if not requestId then
        requestId, specId, spawned, stations, modules, turrets, missileTurrets, shields, engines,
            safeFixtures, safeWeapons, unsafeWeapons, defenceUnits, hostiles, repairFixtures =
            value:match("^x4gct6:([^:]+):([^:]+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
        shooters, shooterMissileTurrets, guided, dumbfire, ammo, loadoutFailures, locationFailures =
            "0", "0", "0", "0", "0", "0", "0"
        shooterWeapons, shooterTurrets, shooterBeam, shooterPlasma,
            preflightFailures, geometrySplits = "0", "0", "0", "0", "0", "0"
    end
    if not requestId then
        requestId, specId, spawned, stations, modules, turrets, missileTurrets, shields, engines,
            safeFixtures, safeWeapons, unsafeWeapons, defenceUnits, hostiles =
            value:match("^x4gct5:([^:]+):([^:]+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
        repairFixtures = tostring(pendingScenario and pendingScenario.expectedRepairFixtures or 0)
    end
    if not requestId then
        requestId, specId, spawned, stations, modules, turrets, missileTurrets, shields, engines,
            safeFixtures, safeWeapons, unsafeWeapons, defenceUnits =
        value:match("^x4gct4:([^:]+):([^:]+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
        hostiles = tostring(pendingScenario and pendingScenario.expectedHostiles or 0)
        repairFixtures = tostring(pendingScenario and pendingScenario.expectedRepairFixtures or 0)
    end
    if not requestId then
        requestId, specId, spawned, stations, modules, turrets, missileTurrets, shields, engines,
            safeFixtures, safeWeapons, unsafeWeapons =
        value:match("^x4gct3:([^:]+):([^:]+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
        defenceUnits, hostiles = "0", tostring(pendingScenario and pendingScenario.expectedHostiles or 0)
        repairFixtures = tostring(pendingScenario and pendingScenario.expectedRepairFixtures or 0)
    end
    if not requestId then
        requestId, specId, spawned, stations, modules, turrets, missileTurrets, shields, engines =
            value:match("^x4gct2:([^:]+):([^:]+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
        safeFixtures, safeWeapons, unsafeWeapons, defenceUnits, hostiles, repairFixtures = "0", "0", "0", "0", "0", "0"
    end
    if not requestId then
        requestId, specId, spawned = value:match("^x4gct1:([^:]+):([^:]+):(%d+)$")
        stations, modules, turrets, missileTurrets, shields, engines = "0", "0", "0", "0", "0", "0"
        safeFixtures, safeWeapons, unsafeWeapons, defenceUnits, hostiles, repairFixtures = "0", "0", "0", "0", "0", "0"
    end
    if not pendingScenario or requestId ~= pendingScenario.requestId
            or specId ~= pendingScenario.specId then return end
    spawned, stations, modules = tonumber(spawned), tonumber(stations), tonumber(modules)
    turrets, missileTurrets = tonumber(turrets), tonumber(missileTurrets)
    shields, engines = tonumber(shields), tonumber(engines)
    safeFixtures, safeWeapons, unsafeWeapons = tonumber(safeFixtures), tonumber(safeWeapons), tonumber(unsafeWeapons)
    defenceUnits = tonumber(defenceUnits)
    hostiles = tonumber(hostiles)
    repairFixtures = tonumber(repairFixtures)
    shooters, shooterMissileTurrets = tonumber(shooters), tonumber(shooterMissileTurrets)
    guided, dumbfire, ammo = tonumber(guided), tonumber(dumbfire), tonumber(ammo)
    loadoutFailures, locationFailures = tonumber(loadoutFailures), tonumber(locationFailures)
    shooterWeapons, shooterTurrets = tonumber(shooterWeapons), tonumber(shooterTurrets)
    shooterBeam, shooterPlasma = tonumber(shooterBeam), tonumber(shooterPlasma)
    preflightFailures, geometrySplits = tonumber(preflightFailures), tonumber(geometrySplits)
    local surfaces = modules + turrets + missileTurrets + shields + engines
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
    if stations ~= request.expectedStations or modules ~= request.expectedModules
            or surfaces < request.minSurfaces then
        scenarioActionStatus = "FAILED: station census was " .. stations .. " stations, "
            .. modules .. " modules, " .. surfaces .. " operational surfaces; expected "
            .. request.expectedStations .. "/" .. request.expectedModules .. "/at least "
            .. request.minSurfaces .. "; inspect debug.log"
        log("scenario_create", { action = "failed", request_id = request.requestId,
            expected_stations = request.expectedStations, spawned_stations = stations,
            expected_modules = request.expectedModules, spawned_modules = modules,
            min_surfaces = request.minSurfaces, operational_surfaces = surfaces,
            turrets = turrets, missile_turrets = missileTurrets, shields = shields,
            engines = engines })
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
            or shooterWeapons ~= request.expectedWeapons or shooterTurrets ~= request.expectedTurrets
            or shooterBeam ~= request.expectedBeam or shooterPlasma ~= request.expectedPlasma
            or shooterMissileTurrets ~= request.expectedMissileTurrets
            or guided ~= request.expectedGuided or dumbfire ~= request.expectedDumbfire
            or ammo ~= request.expectedAmmo or loadoutFailures ~= request.expectedLoadoutFailures then
        scenarioActionStatus = "FAILED: shooter census was " .. shooters .. " ships, "
            .. shooterWeapons .. " weapons/" .. shooterTurrets .. " ordinary turrets ("
            .. shooterBeam .. " beam/" .. shooterPlasma .. " plasma), "
            .. shooterMissileTurrets .. " missile turrets (" .. guided .. " guided/"
            .. dumbfire .. " dumbfire), " .. ammo .. " missiles, and "
            .. loadoutFailures .. " loadout failures; inspect debug.log"
        log("scenario_create", { action = "failed", request_id = request.requestId,
            expected_shooters = request.expectedShooters, shooters = shooters,
            expected_weapons = request.expectedWeapons, weapons = shooterWeapons,
            expected_turrets = request.expectedTurrets, ordinary_turrets = shooterTurrets,
            expected_beam = request.expectedBeam, beam = shooterBeam,
            expected_plasma = request.expectedPlasma, plasma = shooterPlasma,
            expected_missile_turrets = request.expectedMissileTurrets,
            shooter_missile_turrets = shooterMissileTurrets,
            expected_guided = request.expectedGuided, guided = guided,
            expected_dumbfire = request.expectedDumbfire, dumbfire = dumbfire,
            expected_ammo = request.expectedAmmo, ammo = ammo,
            loadout_failures = loadoutFailures })
        menu.display()
        return
    end
    if preflightFailures ~= request.expectedPreflightFailures
            or geometrySplits ~= request.expectedGeometrySplits then
        scenarioActionStatus = "FAILED: geometry preflight found " .. geometrySplits
            .. " discriminating station targets and " .. preflightFailures
            .. " failed controls; expected " .. request.expectedGeometrySplits
            .. "/0; inspect debug.log"
        log("scenario_create", { action = "failed", request_id = request.requestId,
            expected_geometry_splits = request.expectedGeometrySplits,
            geometry_splits = geometrySplits, preflight_failures = preflightFailures })
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
        remoteGeometryPending = specHasAimSplit()
        if remoteGeometryPending then
            -- The remote shell/module census is verified, but both station
            -- equipment and geometry remain experimental until the in-system
            -- qualifier reports them. Do not call the fixture READY here.
            scenarioActionStatus = "PENDING: remote station shell verified; equipment and geometry are NOT qualified; teleport to "
                .. scenarioSpec.setup.shipLabel .. " and open Test Lab once — it re-measures station B "
                .. "in system and qualifies only with the exact standard loadout plus a measured root or clear module aim-point candidate"
            log("scenario_create", { action = "remote_geometry_pending", request_id = request.requestId,
                spawned_ships = spawned, spawned_stations = stations, spawned_modules = modules,
                operational_surfaces = surfaces, turrets = turrets,
                missile_turrets = missileTurrets, shields = shields, engines = engines,
                shooters = shooters,
                weapons = shooterWeapons, ordinary_turrets = shooterTurrets,
                beam = shooterBeam, plasma = shooterPlasma,
                geometry_splits = geometrySplits, preflight_failures = preflightFailures,
                location_failures = locationFailures })
        else
            scenarioActionStatus = "READY: remote fixture verified; teleport to "
                .. scenarioSpec.setup.shipLabel .. " and open Test Lab once to arm "
                .. scenarioSpec.setup.turretLabel
            log("scenario_create", { action = "remote_ready", request_id = request.requestId,
                spawned_ships = spawned, shooters = shooters,
                weapons = shooterWeapons, ordinary_turrets = shooterTurrets,
                beam = shooterBeam, plasma = shooterPlasma,
                missile_turrets = shooterMissileTurrets, guided = guided,
                dumbfire = dumbfire, ammo = ammo, geometry_splits = geometrySplits,
                preflight_failures = preflightFailures, location_failures = locationFailures })
        end
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
    scenarioActionStatus = "READY: " .. spawned .. " named ships, " .. stations
        .. " named stations, and " .. surfaces .. " operational surfaces; only "
        .. selection.label .. " ticked"
    log("scenario_create", {
        action = "ready", request_id = request.requestId, spawned_ships = spawned, group = selection.rawGroup,
        spawned_stations = stations, spawned_modules = modules,
        operational_surfaces = surfaces, turrets = turrets,
        missile_turrets = missileTurrets, shields = shields, engines = engines,
        safe_fixtures = safeFixtures, safe_weapons = safeWeapons, unsafe_weapons = unsafeWeapons,
        defence_units = defenceUnits,
        hostiles = hostiles,
        repair_fixtures = repairFixtures,
        member_ids = selection.memberIDs,
    })
    -- An engaged session parked before scenario replacement still names the
    -- fixture MD just destroyed. Arm the listeners, but suppress that exact
    -- stale id until Gunnery selects a different live target; otherwise the
    -- synchronous first state push snapshots an invalid component.
    local currentSession = api() and api().getSession and api().getSession()
    setObserving(true, currentSession and currentSession.aimTargetID)
    returnToGunnery("scenario_ready")
end

-- Phase-two acknowledgement for the #67 station B discriminator. MD keeps the
-- preserved station root designated, but reports root-origin/root-aim geometry
-- and per-module origin/aim geometry independently. Qualify only when the exact
-- two-laser, four-shield module loadout is present AND either the root split is
-- real or a module aim-point candidate also has a clear external muzzle ray.
local function onGeometryQualified(_, param)
    local token, qualified, equipped, rootSplits, moduleOriginCandidates,
        moduleAimCandidates, moduleClearCandidates, measured, modulePairs,
        modules, turrets, standardLasers, missileTurrets, shields, engines =
        tostring(param or ""):match("^x4gcq4:([^:]+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
    if not token or not pendingQualify or token ~= pendingQualify.requestId then return end
    local request = pendingQualify
    pendingQualify = nil
    qualified, equipped = tonumber(qualified), tonumber(equipped)
    rootSplits = tonumber(rootSplits)
    moduleOriginCandidates = tonumber(moduleOriginCandidates)
    moduleAimCandidates = tonumber(moduleAimCandidates)
    moduleClearCandidates = tonumber(moduleClearCandidates)
    measured, modulePairs = tonumber(measured), tonumber(modulePairs)
    modules, turrets, standardLasers = tonumber(modules), tonumber(turrets), tonumber(standardLasers)
    missileTurrets, shields, engines = tonumber(missileTurrets), tonumber(shields), tonumber(engines)
    if qualified == 1 and equipped == 1
            and (rootSplits >= 1 or moduleClearCandidates >= 1)
            and modules == 5 and turrets == 2 and standardLasers == 2
            and missileTurrets == 0 and shields == 4 and engines == 0 then
        applyExactGroup(request.selection)
        remoteScenarioReady = false
        remoteGeometryPending = false
        scenarioActionStatus = "QUALIFIED: station B root remains designated (root splits="
            .. rootSplits .. ", module origin/aim/clear candidates="
            .. moduleOriginCandidates .. "/" .. moduleAimCandidates .. "/"
            .. moduleClearCandidates .. ", " .. modulePairs .. " module pairs); "
            .. request.selection.label
            .. " armed; returning to Gunnery Control"
        log("geometry_qualify", { action = "qualified", request_id = request.requestId,
            root_splits = rootSplits, module_origin_candidates = moduleOriginCandidates,
            module_aim_candidates = moduleAimCandidates,
            module_clear_candidates = moduleClearCandidates,
            measured = measured, module_pairs = modulePairs,
            designated_target = "station_root", ship_id = request.selection.shipID,
            station_modules = modules, station_turrets = turrets,
            station_standard_lasers = standardLasers, station_missile_turrets = missileTurrets,
            station_shields = shields, station_engines = engines,
            group = request.selection.rawGroup, member_ids = request.selection.memberIDs,
            member_macros = request.selection.memberMacros })
        setObserving(true)
        returnToGunnery("geometry_qualified")
    else
        -- Fail closed on either branch of the combined discriminator.
        if equipped ~= 1 then
            scenarioActionStatus = "FAILED: in-system station B loadout census was "
                .. modules .. " modules, " .. turrets .. " turrets (" .. standardLasers
                .. " standard lasers), " .. missileTurrets .. " missile turrets, "
                .. shields .. " shields, and " .. engines
                .. " engines; expected 5/2/2/0/4/0; diagnostic not started"
        else
            scenarioActionStatus = "FAILED: station B root stayed outside elevation and no qualifying aim point was found (root splits="
                .. rootSplits .. ", module origin/aim/clear candidates="
                .. moduleOriginCandidates .. "/" .. moduleAimCandidates .. "/"
                .. moduleClearCandidates .. ", " .. modulePairs
                .. " module pairs); diagnostic not started"
        end
        log("geometry_qualify", { action = "failed", request_id = request.requestId,
            equipped = equipped, root_splits = rootSplits,
            module_origin_candidates = moduleOriginCandidates,
            module_aim_candidates = moduleAimCandidates,
            module_clear_candidates = moduleClearCandidates,
            measured = measured, module_pairs = modulePairs,
            designated_target = "station_root",
            station_modules = modules, station_turrets = turrets,
            station_standard_lasers = standardLasers, station_missile_turrets = missileTurrets,
            station_shields = shields, station_engines = engines })
        menu.display()
    end
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
    if pendingQualify then
        -- The in-system station B discriminator is still running; keep the menu
        -- up and wait for GeometryQualify rather than re-issuing it.
        menu.display()
        return
    end
    if remoteScenarioReady then
        local selection, reason = resolveExactGroup()
        if selection then
            if remoteGeometryPending then
                -- Phase two: the exact turret set is verified, so fire the single
                -- in-system re-measurement of the preserved station B. Do NOT arm
                -- the group or return to Gunnery until a real split qualifies it.
                scenarioRequestSerial = scenarioRequestSerial + 1
                local token = clockToken(GetCurRealTime()) .. "_q" .. tostring(scenarioRequestSerial)
                pendingQualify = { requestId = token, selection = selection,
                    deadline = getElapsedTime() + 30 }
                AddUITriggeredEvent("X4GunneryTestLabScenario", "qualify_geometry",
                    { requestId = token })
                scenarioActionStatus = "QUALIFYING: re-measuring preserved station B in system with "
                    .. selection.label .. " (" .. selection.memberIDs .. ")"
                log("geometry_qualify", { action = "requested", request_id = token,
                    ship_id = selection.shipID, group = selection.rawGroup,
                    member_ids = selection.memberIDs, member_macros = selection.memberMacros })
                menu.display()
                return
            end
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
    if pendingQualify and now >= pendingQualify.deadline then
        local request = pendingQualify
        pendingQualify = nil
        scenarioActionStatus = "FAILED: no in-system geometry acknowledgement; inspect debug.log"
        log("geometry_qualify", { action = "timeout", request_id = request.requestId })
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
    RegisterEvent("X4GunneryTestLab.GeometryQualified", onGeometryQualified)
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
