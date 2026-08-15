-- Developer-only PR3 diagnostic probe harness.
--
-- Adds six separately invokable probes to the Test Lab menu so the human
-- tester can causally bisect which engine-facing operation first changes a
-- working Direct-B controller back toward A while hard/soft/session target
-- remains B.
--
-- PROBE INVENTORY
--   1. NOOP                              - log boundary only; no targeting action.
--   2. RELEASE_A                         - exact production previous-target/capital-
--                                          hierarchy stop_firing_at_target for A/root(A).
--                                          No set_turret_targets.
--   3. NARROW_ANY_B                      - set_turret_targets object=ship target=[B]
--                                          preferredtarget=B (no weaponmode).
--   4. WIDE_ANY_B                        - set_turret_targets object=ship target=$hostiles
--                                          preferredtarget=B (no weaponmode). Builds hostiles
--                                          using same semantics as production.
--   5. NARROW_ATTACKENEMIES_B            - set_turret_targets object=ship target=[B]
--                                          preferredtarget=B weaponmode=weaponmode.attackenemies
--   6. WIDE_ATTACKENEMIES_B              - set_turret_targets object=ship target=$hostiles
--                                          preferredtarget=B weaponmode=weaponmode.attackenemies
--
-- PROBE INPUTS
-- Uses existing PR3 fixture identities resolved from the live scenario:
--   - player ship (from getCurrentShipSweepReadOnly)
--   - A and B resolved asynchronously by the scenario MD via exact-label lookup
--     against ScenarioRoot.$ProbeLabels, returned as two raw-component events
--     (X4GunneryTestLab.ProbeTargetResolvedA.<requestId>,
--      X4GunneryTestLab.ProbeTargetResolvedB.<requestId>)
--
-- TARGET RESOLUTION
-- probe.lua requests resolution by sending flat scalar keys (Lua→MD proven
-- transport contract):
--   AddUITriggeredEvent("X4GunneryTestLabScenario", "probe_target_resolve",
--     {specId = ..., requestId = ..., labelA = ..., labelB = ...})
-- The scenario MD resolves labels via its spawn-label registry and returns two
-- raw-component events keyed by requestId:
--   X4GunneryTestLab.ProbeTargetResolvedA.<requestId> param=<component>
--   X4GunneryTestLab.ProbeTargetResolvedB.<requestId> param=<component>
-- Lua receives the component as a number (MD→Lua component transport, proven in
-- research KB and ui/gunnery_persistence.lua:52). ConvertStringToLuaID(tostring(n))
-- reverses it back to a live component. A request token guards against stale
-- responses from prior fixture generations.
--
-- LOGGING
-- Immediately before executing each probe, emits one clear boundary:
--   [X4GC TEST PROBE] op=<name> ship=<id> a=<id> b=<id> hostiles=<count if applicable> t=<time>
--
-- DO NOT MODIFY:
--   ui/gunnery_control.lua
--   md/x4_gunnery_control.xml
--   production Prefer/Direct behavior
--   production persistence/state logic

local State = X4GunneryTestLabState
local menu = { name = "X4GunneryTestLabProbe", uixID = "x4_gunnery_control_testlab" }
local scenarioActionStatus, pendingScenario = nil, nil
local scenarioLoadTime = GetCurRealTime()
local probeResolvedTargets, probePendingRequestId = nil, nil
local probeReceivedA, probeReceivedB = false, false
local probeResolvedA, probeResolvedB = nil, nil
local probeRequestSerial = 0

local function text(id) return ReadText(20992, id) end
local function safe(value) return tostring(value or ""):gsub("[^%w_.%-]", "_") end
local function trim(value) return tostring(value or ""):match("^%s*(.-)%s*$") end

local function log(event, fields)
    local parts = { "[X4GC TEST PROBE]", "event=" .. event }
    for key, value in pairs(fields or {}) do parts[#parts + 1] = key .. "=" .. safe(value) end
    table.sort(parts, function(a, b) return a < b end)
    DebugError(table.concat(parts, " "))
end

-- Probe operations: each name maps to the exact MD control string.
local PROBE_OPS = {
    "noop",
    "release_a",
    "narrow_any_b",
    "wide_any_b",
    "narrow_attackenemies_b",
    "wide_attackenemies_b",
}

-- Resolve the player ship (synchronous) and request A/B from scenario MD.
-- Returns {ship=component, a=component, b=component} or nil if not yet resolved.
local function resolveProbeTargets()
    -- Get player ship.
    local bridge = X4GunneryControlAPI
    if not bridge or not bridge.getCurrentShipSweepReadOnly then
        return nil
    end
    local ship, reason = bridge.getCurrentShipSweepReadOnly()
    if not ship then return nil end

    -- A/B must have been resolved asynchronously by the scenario MD.
    if not probeResolvedTargets then return nil end

    return { ship = ConvertStringToLuaID(tostring(ship.id)),
             a = probeResolvedTargets.a, b = probeResolvedTargets.b }
end

-- Clock token for unique request IDs.
local function clockToken(value)
    return tostring(math.floor((tonumber(value) or 0) * 1000000 + 0.5))
end

-- Request the scenario MD to resolve A/B labels to live component IDs.
local function requestProbeTargetResolution()
    if not X4GunneryTestLabScenarioSpec or not X4GunneryTestLabScenarioSpec.groups then
        log("probe_resolve", { action = "skipped", reason = "no spec groups" })
        return
    end
    -- Collect exact labels from hostile groups in spec order.
    local labelA, labelB = nil, nil
    for _, group in ipairs(X4GunneryTestLabScenarioSpec.groups) do
        if group.hostile == true and group.label and not labelA then
            labelA = trim(group.label)
        elseif group.hostile == true and group.label and labelA and not labelB then
            labelB = trim(group.label)
        end
    end
    if not labelA or not labelB then
        log("probe_resolve", { action = "skipped", reason = "need at least 2 hostile labels", count = (labelA and 1 or 0) + (labelB and 1 or 0) })
        return
    end
    probeRequestSerial = probeRequestSerial + 1
    local requestId = clockToken(GetCurRealTime()) .. "_" .. tostring(probeRequestSerial)
    probePendingRequestId = requestId
    probeResolvedTargets = nil
    -- Reset per-request state so an incomplete older pair cannot contribute a half.
    probeReceivedA, probeReceivedB = false, false
    probeResolvedA, probeResolvedB = nil, nil
    log("probe_resolve", { action = "requested", request_id = requestId, label_a = labelA, label_b = labelB })
    -- Register exact full dynamic event names (per-request correlation).
    RegisterEvent(
        "X4GunneryTestLab.ProbeTargetResolvedA." .. requestId,
        function(_, value)
            onProbeTargetResolved(requestId, "A", value)
        end)
    RegisterEvent(
        "X4GunneryTestLab.ProbeTargetResolvedB." .. requestId,
        function(_, value)
            onProbeTargetResolved(requestId, "B", value)
        end)
    AddUITriggeredEvent("X4GunneryTestLabScenario", "probe_target_resolve",
        { specId = X4GunneryTestLabScenarioSpec.id, requestId = requestId,
          labelA = labelA, labelB = labelB })
end

-- Handle one raw-component response (A or B). Both must arrive before the
-- pending requestId expires.  MD raises components as Lua numbers; reverse
-- with ConvertStringToLuaID(tostring(n)).  param=0 signals "not found".
-- The requestId and side are captured from the per-registration closure, not
-- parsed from a third callback argument.
local function onProbeTargetResolved(requestId, side, value)
    if not probePendingRequestId or requestId ~= probePendingRequestId then
        log("probe_resolve", { action = "stale_response", received = requestId, pending = probePendingRequestId })
        return
    end
    -- MD sends 0 for unresolved; nonzero is a live component identity.
    local comp = ConvertStringToLuaID(tostring(value or 0))
    if side == "A" then
        probeReceivedA = true
        probeResolvedA = comp
    else
        probeReceivedB = true
        probeResolvedB = comp
    end
    log("probe_resolve", { action = "received_" .. side, request_id = requestId, value = tostring(comp) })
    if not (probeReceivedA and probeReceivedB) then return end
    -- Both halves arrived for this requestId — finalize.
    probePendingRequestId = nil
    -- Zero ID means unresolved; nonzero is accepted as resolved (MD owns existence).
    local aValid = probeResolvedA and probeResolvedA ~= 0
    local bValid = probeResolvedB and probeResolvedB ~= 0
    if aValid and bValid and probeResolvedA ~= probeResolvedB then
        probeResolvedTargets = { a = probeResolvedA, b = probeResolvedB }
        log("probe_resolve", { action = "resolved", a = tostring(probeResolvedA), b = tostring(probeResolvedB) })
        menu.display()
    else
        local count = (aValid and 1 or 0) + (bValid and 1 or 0)
        log("probe_resolve", { action = "failed", count = count, a_valid = aValid, b_valid = bValid })
        scenarioActionStatus = "FAILED: could not resolve probe targets A/B from scenario"
        menu.display()
    end
    probeReceivedA, probeReceivedB = false, false
    probeResolvedA, probeResolvedB = nil, nil
end

-- Invoke exactly one probe operation. Logs boundary, then sends the MD event.
local function invokeProbe(op)
    local targets = resolveProbeTargets()
    if not targets then
        scenarioActionStatus = "FAILED: cannot resolve probe targets (ship/A/B)"
        log("invoke", { op = op, reason = "targets_unresolved" })
        menu.display()
        return
    end

    -- Log boundary immediately before executing.
    log("invoke", { op = op, ship = tostring(targets.ship), a = tostring(targets.a), b = tostring(targets.b) })

    -- Send exactly one event to MD; no other targeting/mode operation.
    AddUITriggeredEvent("X4GunneryTestLabProbe", "probe_invoke", {
        op = op,
        ship = targets.ship,
        a = targets.a,
        b = targets.b,
    })

    scenarioActionStatus = "PROBE: " .. op .. " invoked at t=" .. getElapsedTime()
    menu.display()
end

-- Menu display: probe buttons + status.
function menu.display()
    Helper.clearMenu(menu)
    local frame = Helper.createFrameHandle(menu, { width = Helper.scaleX(900), height = Helper.scaleY(520), standardButtons = { close = true } })
    local tableView = frame:addTable(4, { tabOrder = 1, width = Helper.scaleX(880) })
    local title = tableView:addRow(false, { bgColor = Color["row_title_background"] })
    title[1]:setColSpan(4):createText(text(1) .. " - PR3 Diagnostic Probes", Helper.headerRowCenteredProperties)

    -- Show current probe targets if resolvable.
    local targets = resolveProbeTargets()
    local infoRow = tableView:addRow(false, {})
    if targets then
        infoRow[1]:setColSpan(4):createText("ship=" .. tostring(targets.ship) .. " a=" .. tostring(targets.a) .. " b=" .. tostring(targets.b))
    else
        if probePendingRequestId then
            infoRow[1]:setColSpan(4):createText("Targets: resolving...")
        else
            infoRow[1]:setColSpan(4):createText("Targets: unresolved (create PR3 scenario first)")
        end
    end

    -- Six probe buttons, each invoking exactly one isolated operation.
    local probeLabels = {
        { op = "noop", label = "1. NOOP" },
        { op = "release_a", label = "2. RELEASE_A" },
        { op = "narrow_any_b", label = "3. NARROW_ANY_B" },
        { op = "wide_any_b", label = "4. WIDE_ANY_B" },
        { op = "narrow_attackenemies_b", label = "5. NARROW_ATTACKENEMIES_B" },
        { op = "wide_attackenemies_b", label = "6. WIDE_ATTACKENEMIES_B" },
    }

    for _, probe in ipairs(probeLabels) do
        local row = tableView:addRow(false, {})
        row[1]:setColSpan(4):createButton({}):setText(probe.label)
        row[1].handlers.onClick = function() invokeProbe(probe.op) end
    end

    -- Status line.
    if scenarioActionStatus then
        local statusRow = tableView:addRow(false, {})
        statusRow[1]:setColSpan(4):createText(scenarioActionStatus)
    end

    -- Return to Test Lab button.
    local backRow = tableView:addRow("back", {})
    backRow[1]:setColSpan(4):createButton({}):setText(text(9) .. " (return to Test Lab)")
    backRow[1].handlers.onClick = function()
        Helper.closeMenuAndOpenNewMenu(menu, "X4GunneryTestLab", { 0, 0 }, true)
    end

    frame:display()
end

function menu.onShowMenu()
    requestProbeTargetResolution()
    menu.display()
end

function menu.onCloseElement(dueToClose)
    Helper.closeMenuAndOpenNewMenu(menu, "X4GunneryTestLab", { 0, 0 }, true)
end

local function init():
    Menus = Menus or {}; table.insert(Menus, menu)
    log("loaded")
    if Helper then Helper.registerMenu(menu) end
end
init()
