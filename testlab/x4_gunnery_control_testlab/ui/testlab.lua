-- Developer-only current-ship turret sweep. The production extension owns all
-- turret discovery and mutations; this companion only drives its narrow API.
local State = X4GunneryTestLabState
local menu = { name = "X4GunneryTestLab", uixID = "x4_gunnery_control_testlab" }
local sweep, inspectStarted, nextPoll, stableSamples, unstableSamples, technical, targetBefore, targetPreserved, closing, suppressReopen = nil, nil, nil, 0, 0, nil, nil, nil, false, false
local scenarioActionStatus, scenarioRequestSerial, pendingScenario = nil, 0, nil
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
local lastObservedAimTarget, observedAimSince, observedAimSettled

-- The engine SOFT target and the session's Prefer My Target flag are the whole
-- reason any Lua runs here: MD has player.target but no soft-target equivalent
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
    if soft and soft.id and soft.id ~= "0" then
        payload.softtgt = ConvertStringToLuaID(soft.id)
    end
    -- No session is the ordinary free-play case, not an error: MD then logs
    -- player.target and prefer stays false.
    local session = bridge.getSession and bridge.getSession()
    if session then
        payload.prefer = session.preferAllTurrets == true
        if session.aimTargetID then payload.aimtgt = ConvertStringToLuaID(tostring(session.aimTargetID)) end
    end
    AddUITriggeredEvent("X4GunneryTestLabObserve", "observe_state", payload)
    -- Geometry tests should not depend on the owner switching menus and
    -- clicking Mark at the right instant. Once MD has the new aim target,
    -- automatically request the same one-shot solution snapshot the button
    -- would have produced. String comparison normalises ffi cdata/number forms.
    local aimTarget = session and session.aimTargetID and tostring(session.aimTargetID) or nil
    local now = getElapsedTime()
    if aimTarget and aimTarget ~= lastObservedAimTarget then
        lastObservedAimTarget = aimTarget
        observedAimSince, observedAimSettled = now, false
        AddUITriggeredEvent("X4GunneryTestLabObserve", "observe_mark")
        log("observe", { action = "auto_mark_initial", target = aimTarget })
    elseif aimTarget and not observedAimSettled and observedAimSince and now - observedAimSince >= 20 then
        observedAimSettled = true
        AddUITriggeredEvent("X4GunneryTestLabObserve", "observe_mark")
        log("observe", { action = "auto_mark_settled", target = aimTarget, held_seconds = now - observedAimSince })
    end
    -- Self-rescheduling at the MD sample rate, the pattern the main mod's
    -- session watchdog uses (ui/gunnery_control.lua:2224) because it runs with
    -- no displayed frame. Whether it keeps firing with every menu closed is
    -- unverified; if it stops, MD still writes the full STATE and SOLUTION
    -- block and only softtgt/prefer go stale. Degrades, does not break.
    if Helper then Helper.addDelayedOneTimeCallbackOnUpdate(pushObserveState, false, getElapsedTime() + 1.0) end
end

local function setObserving(enabled)
    observing = enabled
    lastObservedAimTarget, observedAimSince, observedAimSettled = nil, nil, nil
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
        }
    end
    if #groups == 0 then return nil, "spec.groups is empty" end
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
        setup = {
            shipMacro = raw.setup.shipMacro,
            shipLabel = raw.setup.shipLabel,
            turretGroup = raw.setup.turretGroup,
            turretLabel = raw.setup.turretLabel,
            expectedTurrets = math.floor(raw.setup.expectedTurrets),
        }
    end
    return { id = raw.id, enabled = raw.enabled, groups = groups, setup = setup }
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
    AddUITriggeredEvent("X4GunneryTestLabScenario", "scenario_begin",
        { specId = scenarioSpec.id, force = force == true, requestId = requestId or "" })
    for _, group in ipairs(scenarioSpec.groups) do
        AddUITriggeredEvent("X4GunneryTestLabScenario", "scenario_group", {
            label = group.label, macro = group.macro, faction = group.faction,
            count = group.count, distance = group.distance, spread = group.spread,
            x = group.x, y = group.y,
            behaviour = group.behaviour, hostile = group.hostile,
        })
    end
    AddUITriggeredEvent("X4GunneryTestLabScenario", "scenario_commit")
    log("scenario_spec", { action = "sent", spec_id = scenarioSpec.id, groups = #scenarioSpec.groups, forced = tostring(force == true) })
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
    local selected
    for _, group in ipairs(ship.groups or {}) do
        if trim(group.group) == setup.turretGroup then selected = group; break end
    end
    if not selected then return nil, "missing raw group " .. setup.turretGroup end
    if selected.kind ~= "group" or selected.mutable ~= true then
        return nil, setup.turretLabel .. " is not a mutable turret group"
    end
    if #(selected.members or {}) ~= setup.expectedTurrets then
        return nil, setup.turretLabel .. " needs " .. setup.expectedTurrets
            .. " operational turrets, found " .. #(selected.members or {})
    end
    local session = bridge.getSession()
    if not session then return nil, "no Gunnery session" end

    local memberIDs = {}
    for _, member in ipairs(selected.members) do memberIDs[#memberIDs + 1] = tostring(member.id) end
    table.sort(memberIDs)
    return {
        label = setup.turretLabel,
        rawGroup = setup.turretGroup,
        memberIDs = table.concat(memberIDs, ","),
        shipID = tostring(ship.id),
        groupKey = selected.key,
        armed = selected.armed == true,
        session = session,
    }
end

local function applyExactGroup(selection)
    local session = selection.session
    local checked = {}
    for key in pairs(session.checkedGroupKeys or {}) do checked[#checked + 1] = key end
    for _, key in ipairs(checked) do X4GunneryState.toggleGroup(session, key, true) end
    X4GunneryState.toggleGroup(session, selection.groupKey, selection.armed)
    session.selectedGroupKey = selection.groupKey
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
    local selection, reason = resolveExactGroup()
    if not selection then
        scenarioActionStatus = "FAILED: " .. reason
        log("scenario_create", { action = "rejected", reason = reason })
        menu.display()
        return
    end
    local expectedShips = 0
    for _, group in ipairs(scenarioSpec.groups) do expectedShips = expectedShips + group.count end
    scenarioRequestSerial = scenarioRequestSerial + 1
    local requestId = clockToken(GetCurRealTime()) .. "_" .. tostring(scenarioRequestSerial)
    pendingScenario = {
        requestId = requestId,
        specId = scenarioSpec.id,
        expectedShips = expectedShips,
        deadline = getElapsedTime() + 10,
        selection = selection,
    }
    scenarioActionStatus = "CREATING: replacing the previous fixture and verifying "
        .. expectedShips .. " ships..."
    sendScenarioSpec(true, requestId)
    log("scenario_create", {
        action = "requested", spec_id = scenarioSpec.id, expected_ships = expectedShips,
        request_id = requestId, load_time = scenarioLoadTime,
        group = selection.rawGroup, member_ids = selection.memberIDs,
    })
    menu.display()
end

local function onScenarioReady(_, param)
    local requestId, specId, spawned = tostring(param or ""):match("^x4gct1:([^:]+):([^:]+):(%d+)$")
    if not pendingScenario or requestId ~= pendingScenario.requestId
            or specId ~= pendingScenario.specId then return end
    spawned = tonumber(spawned)
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
    scenarioActionStatus = "READY: " .. spawned .. " named ships created; only "
        .. selection.label .. " ticked"
    log("scenario_create", {
        action = "ready", request_id = request.requestId, spawned_ships = spawned, group = selection.rawGroup,
        member_ids = selection.memberIDs,
    })
    setObserving(true)
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
        setupRow[1]:setColSpan(4):createText("One-click setup: " .. setup.shipLabel
            .. " | only " .. setup.turretLabel .. " | " .. setup.expectedTurrets .. " operational turrets")
    end
    local scenarioRow = tableView:addRow("scenario", {})
    scenarioRow[1]:setColSpan(2):createButton({
        active = scenarioSpec ~= nil and scenarioSpec.setup ~= nil and pendingScenario == nil,
    }):setText(text(25))
    scenarioRow[1].handlers.onClick = createTestScenario
    scenarioRow[3]:setColSpan(2):createButton({ active = pendingScenario == nil }):setText(text(26)); scenarioRow[3].handlers.onClick = function()
        if pendingScenario then
            pendingScenario = nil
            scenarioActionStatus = "CANCELLED: pending creation was invalidated"
        end
        AddUITriggeredEvent("X4GunneryTestLabScenario", "despawn_scenario")
        log("scenario", { action = "despawn" })
        menu.display()
    end
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
