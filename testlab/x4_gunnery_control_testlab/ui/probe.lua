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
--   - A = PR3 TARGET A LEFT OSAKA (first hostile group in spec)
--   - B = PR3 TARGET B RIGHT OSAKA (second hostile group in spec)
-- Actual component IDs resolved from live fixture; never hard-coded.
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

-- Resolve the player ship and the two PR3 fixture targets (A and B) from the
-- live scenario. Returns {ship=component, a=component, b=component} or nil.
local function resolveProbeTargets()
    local setup = X4GunneryTestLabScenarioSpec and X4GunneryTestLabScenarioSpec.setup
    if not setup then return nil end

    -- Get player ship.
    local bridge = X4GunneryControlAPI
    if not bridge or not bridge.getCurrentShipSweepReadOnly then
        return nil
    end
    local ship, reason = bridge.getCurrentShipSweepReadOnly()
    if not ship then return nil end

    -- Find A and B from the scenario spec groups. The spec defines exactly two
    -- hostile OSAKA ships: A (left, x=-900) and B (right, x=+900).
    local groups = X4GunneryTestLabScenarioSpec.groups or {}
    local targetA, targetB = nil, nil
    for _, group in ipairs(groups) do
        if group.hostile == true and group.macro and group.macro:find("osaka", 1, true) then
            if not targetA then
                targetA = { label = group.label, x = tonumber(group.x) or 0 }
            else
                targetB = { label = group.label, x = tonumber(group.x) or 0 }
            end
        end
    end

    -- Resolve actual component IDs from live sector.
    local shipComp = ConvertStringToLuaID(tostring(ship.id))
    local aComp, bComp = nil, nil

    -- Search for ships matching the spec labels in the player sector.
    local searchResult = find_object("player.sector", "objecttype.ship", "multiple")
    if searchResult then
        for _, obj in ipairs(searchResult) do
            if obj.exists and obj.knownname then
                local name = trim(obj.knownname)
                if targetA and name:find(trim(targetA.label), 1, true) and not aComp then
                    aComp = ConvertStringToLuaID(tostring(obj.id))
                end
                if targetB and name:find(trim(targetB.label), 1, true) and not bComp then
                    bComp = ConvertStringToLuaID(tostring(obj.id))
                end
            end
        end
    end

    if not aComp or not bComp then
        return nil
    end

    return { ship = shipComp, a = aComp, b = bComp }
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
        infoRow[1]:setColSpan(4):createText("Targets: unresolved (open Gunnery menu on PR3 fixture ship)")
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
    menu.display()
end

function menu.onCloseElement(dueToClose)
    Helper.closeMenuAndOpenNewMenu(menu, "X4GunneryTestLab", { 0, 0 }, true)
end

local function init()
    Menus = Menus or {}; table.insert(Menus, menu)
    log("loaded")
    if Helper then Helper.registerMenu(menu) end
end
init()
