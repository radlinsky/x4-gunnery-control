-- Throwaway issue #205 probe: can X4's own ship-configuration hologram
-- (AddHoloMap + ShowObjectConfigurationMap2 in a render target, as
-- menu_ship_configuration.lua uses it) show the player's ship in a small
-- panel, rotate by mouse drag, report the turret slot under the mouse, and
-- highlight chosen turret slots? Everything is logged as [X4GC TEST] holo.
-- Kept out of testlab.lua, which deliberately contains no ffi.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
typedef uint64_t UniverseID;
typedef struct { const char* upgradetype; size_t slot; } UILoadoutSlot;
typedef struct { const char* path; const char* group; } UpgradeGroup;
typedef struct { float x; float y; float z; float yaw; float pitch; float roll; } UIPosRot;
typedef struct { UIPosRot offset; float cameradistance; } HoloMapState;
void GetMapState(UniverseID holomapid, HoloMapState* state);
void SetMapState(UniverseID holomapid, HoloMapState state);
UniverseID AddHoloMap(const char* texturename, float x0, float x1, float y0, float y1, float aspectx, float aspecty);
void RemoveHoloMap(void);
void SetMapPicking(UniverseID holomapid, bool enable);
void SetMapRelativeMousePosition(UniverseID holomapid, bool valid, float x, float y);
void StartRotateMap(UniverseID holomapid);
void StopRotateMap(UniverseID holomapid);
void StartPanMap(UniverseID holomapid);
void StopPanMap(UniverseID holomapid);
void ZoomMap(UniverseID holomapid, float zoomstep);
void ClearSelectedMapMacroSlots(UniverseID holomapid);
void SetSelectedMapMacroSlots(UniverseID holomapid, UniverseID defensibleid, UniverseID moduleid, const char* macroname, bool ismodule, const char* upgradetypename, size_t* slots, uint32_t numslots);
bool GetPickedMapMacroSlot(UniverseID holomapid, UniverseID defensibleid, UniverseID moduleid, const char* macroname, bool ismodule, UILoadoutSlot* result);
size_t GetNumUpgradeSlots(UniverseID destructibleid, const char* macroname, const char* upgradetypename);
UniverseID GetUpgradeSlotCurrentComponent(UniverseID destructibleid, const char* upgradetypename, size_t slot);
]]
-- UILoadout is declared by vanilla (helper/ship configuration); only the
-- function that takes it by value is declared here, and tolerated if vanilla
-- already did.
pcall(ffi.cdef, "void ShowObjectConfigurationMap2(UniverseID holomapid, UniverseID defensibleid, UniverseID moduleid, const char* macroname, bool ismodule, UILoadout uiloadout, size_t cp_idx);")

local menu = { name = "X4GunneryTurretHolo" }
local LAYER = 3
local holo = { map = nil, holomap = 0, activate = false, hover = "", nextPick = 0, closing = false }

local function log(event, fields)
    local parts = { "[X4GC TEST]", "event=holo", "action=" .. event }
    for key, value in pairs(fields or {}) do parts[#parts + 1] = key .. "=" .. tostring(value):gsub("[^%w_.%-]", "_") end
    DebugError(table.concat(parts, " "))
end

local function api() return X4GunneryControlAPI end
local function sameID(a, b) return tostring(ConvertStringTo64Bit(tostring(a))) == tostring(ConvertStringTo64Bit(tostring(b))) end

-- slot -> { component, name, groupLabel, ticked } from the live Gunnery session.
local function readSlots()
    holo.slots, holo.bySlot = {}, {}
    local session = api() and api().getSession and api().getSession()
    if not session or not session.shipID then return false end
    holo.ship = ConvertStringTo64Bit(tostring(session.shipID))
    holo.macro = GetComponentData(holo.ship, "macro") or ""
    local count = tonumber(C.GetNumUpgradeSlots(holo.ship, "", "turret"))
    for slot = 1, count do
        local component = C.GetUpgradeSlotCurrentComponent(holo.ship, "turret", slot)
        if component ~= 0 then
            local entry = { slot = slot, component = component, name = "?", groupLabel = "?", ticked = false }
            for _, group in ipairs(session.groups or {}) do
                for _, member in ipairs(group.members or {}) do
                    if sameID(member.componentID, component) then
                        entry.name = member.displayName or "?"
                        -- "Front Lower Left: Ion Pulse Turret" -> "Front Lower Left"
                        entry.groupLabel = tostring(group.displayName or "?"):match("^([^:]+)") or "?"
                        entry.ticked = session.checkedGroupKeys and session.checkedGroupKeys[group.key] and true or false
                        entry.componentID = member.componentID
                    end
                end
            end
            holo.slots[#holo.slots + 1] = entry
            holo.bySlot[slot] = entry
        end
    end
    log("slots", { ship = tostring(holo.ship), macro = holo.macro, turret_slots = count, equipped = #holo.slots })
    return true
end

local function pickedSlot()
    if holo.holomap == 0 then return nil end
    local picked = ffi.new("UILoadoutSlot")
    if C.GetPickedMapMacroSlot(holo.holomap, holo.ship, 0, holo.macro, false, picked) then
        return ffi.string(picked.upgradetype), tonumber(picked.slot)
    end
end

local function stateKey()
    local state = ffi.new("HoloMapState")
    C.GetMapState(holo.holomap, state)
    local o = state.offset
    return string.format("%.1f,%.1f,%.1f,%.4f,%.4f,%.4f,%.1f", o.x, o.y, o.z, o.yaw, o.pitch, o.roll, state.cameradistance), state
end

local function highlight(slots, why)
    if holo.holomap == 0 then return end
    if why then log("highlight", { why = why, slots = #slots }) end
    if #slots == 0 then C.ClearSelectedMapMacroSlots(holo.holomap); return end
    local buffer = ffi.new("size_t[?]", #slots)
    for i, slot in ipairs(slots) do buffer[i - 1] = slot end
    C.SetSelectedMapMacroSlots(holo.holomap, holo.ship, 0, holo.macro, false, "turret", buffer, #slots)
end

local function requestPositions()
    for index, entry in ipairs(holo.slots or {}) do
        AddUITriggeredEvent("X4GunneryTestLabObserve", "turretmap_position", {
            ship = ConvertStringToLuaID(tostring(holo.ship)), turret = ConvertStringToLuaID(tostring(entry.component)), idx = index })
    end
end

-- Same reply the turret-map probe parses; testlab.lua ignores it while its
-- own probe is off.
local function onPosition(_, param)
    local idx, x, y, z = tostring(param or ""):match("^x4gtm1:([%d%.]+):([^:]+):([^:]+):([^:]+)$")
    local entry = idx and holo.slots and holo.slots[math.floor(tonumber(idx))]
    if not entry then return end
    local function num(v) return tonumber(tostring(v):match("^%s*([-+]?[%d%.]+[eE]?[-+]?%d*)")) end
    entry.x, entry.y, entry.z = num(x), num(y), num(z)
    log("position", { slot = entry.slot, component = tostring(entry.component), x = entry.x, y = entry.y, z = entry.z })
end

-- Scan: walk a virtual mouse over a grid, one point per frame, and ask the
-- holomap which slot is under it. Per-slot centroids plus the camera state
-- are the calibration data for drawing our own markers.
local SCAN_COLS, SCAN_ROWS = 48, 32
local function startScan()
    if holo.holomap == 0 then return end
    holo.scan = { index = 0, pending = nil, hits = {}, state = stateKey() }
    log("scan_start", { state = holo.scan.state, grid = SCAN_COLS .. "x" .. SCAN_ROWS })
end

local function stepScan()
    local scan = holo.scan
    if scan.pending then
        local kind, slot = pickedSlot()
        if kind == "turret" and slot then
            local hit = scan.hits[slot] or { sx = 0, sy = 0, n = 0 }
            hit.sx, hit.sy, hit.n = hit.sx + scan.pending[1], hit.sy + scan.pending[2], hit.n + 1
            scan.hits[slot] = hit
        end
    end
    if scan.index >= SCAN_COLS * SCAN_ROWS then
        local found = 0
        for slot, hit in pairs(scan.hits) do
            found = found + 1
            local entry = holo.bySlot[slot]
            log("scan_hit", { slot = slot, component = entry and tostring(entry.component) or "",
                mouse = string.format("%.4f,%.4f", hit.sx / hit.n, hit.sy / hit.n), samples = hit.n,
                pos = entry and entry.x and string.format("%.3f,%.3f,%.3f", entry.x, entry.y, entry.z) or "", state = scan.state })
        end
        log("scan_done", { turrets_found = found, state = scan.state, state_after = stateKey() })
        holo.scan = nil
        holo.hover = "scan done: " .. found .. " turrets found"
        menu.frame:update()
        return
    end
    local col, row = scan.index % SCAN_COLS, math.floor(scan.index / SCAN_COLS)
    local x = -1 + (col + 0.5) * 2 / SCAN_COLS
    local y = -1 + (row + 0.5) * 2 / SCAN_ROWS
    C.SetMapRelativeMousePosition(holo.holomap, true, x, y)
    scan.pending = { x, y }
    scan.index = scan.index + 1
end

function menu.onShowMenu()
    holo.closing, holo.flash, holo.scan = false, false, nil
    if not readSlots() then log("no_session") else requestPositions() end
    menu.display()
end

function menu.display()
    -- clearDataForRefresh, not clearMenu: clearMenu also drops onUpdate.
    Helper.clearDataForRefresh(menu)
    local width = Helper.scaleX(700)
    local rtHeight = Helper.scaleY(460)
    local frame = Helper.createFrameHandle(menu, { layer = LAYER, x = math.floor((Helper.viewWidth - width) / 2),
        y = Helper.scaleY(60), width = width, standardButtons = { close = true } })
    menu.frame = frame
    local t = frame:addTable(4, { tabOrder = 1, x = Helper.borderSize, y = Helper.borderSize, width = width - 2 * Helper.borderSize })
    local title = t:addRow(false, { bgColor = Color["row_title_background"] })
    title[1]:setColSpan(4):createText("Turret hologram probe (issue #205)", Helper.headerRowCenteredProperties)
    local buttons = t:addRow("holo_buttons", {})
    buttons[1]:createButton({}):setText("Highlight ticked")
    buttons[1].handlers.onClick = function()
        holo.flash = false
        local slots = {}
        for _, entry in ipairs(holo.slots or {}) do if entry.ticked then slots[#slots + 1] = entry.slot end end
        highlight(slots, "ticked")
    end
    buttons[2]:createButton({}):setText("Flash random (1 Hz)")
    buttons[2].handlers.onClick = function() holo.flash = true; log("flash", { on = true }) end
    buttons[3]:createButton({}):setText("Clear highlight")
    buttons[3].handlers.onClick = function() holo.flash = false; highlight({}, "clear") end
    buttons[4]:createButton({}):setText("Back to Test Lab")
    buttons[4].handlers.onClick = function() menu.onCloseElement("back") end
    local scanRow = t:addRow("holo_scan", {})
    scanRow[1]:setColSpan(2):createButton({}):setText("Scan turret positions (hold still ~25 s)")
    scanRow[1].handlers.onClick = function()
        startScan(); holo.hover = "scanning..."; menu.frame:update()
    end
    local help = t:addRow(false, {})
    help[1]:setColSpan(4):createText("Left-drag rotate, right- or middle-drag pan, wheel zoom, click a turret for its camera.",
        { fontsize = Helper.scaleFont(Helper.standardFont, 9) })
    local hover = t:addRow(false, {})
    hover[1]:setColSpan(4):createText(function() return "Hover: " .. holo.hover end)
    local rtY = t.properties.y + t:getFullHeight() + Helper.borderSize
    frame:addRenderTarget({ width = width - 2 * Helper.borderSize, height = rtHeight, x = Helper.borderSize, y = rtY, scaling = false, alpha = 100 })
    frame.properties.height = rtY + rtHeight + Helper.borderSize
    holo.aspect = (width - 2 * Helper.borderSize) / rtHeight
    frame:display()
end

function menu.viewCreated(layer, ...)
    if layer ~= LAYER then return end
    for _, child in ipairs({ ... }) do
        if IsType(child, "rendertarget") then
            holo.map = child
            if holo.holomap == 0 then holo.activate = true end
        end
    end
    log("view_created", { rendertarget = tostring(holo.map) })
end

menu.updateInterval = 0.01

function menu.onUpdate()
    local now = getElapsedTime()
    if holo.activate and holo.map then
        local x0, x1, y0, y1 = Helper.getRelativeRenderTargetSize(menu, LAYER, holo.map)
        local texture = GetRenderTargetTexture(holo.map)
        if texture then
            holo.activate = false
            holo.holomap = C.AddHoloMap(texture, x0, x1, y0, y1, holo.aspect or 1, 1)
            local ok, err = pcall(Helper.callLoadoutFunction, {}, nil, function(loadout)
                return C.ShowObjectConfigurationMap2(holo.holomap, holo.ship, 0, holo.macro, false, loadout, 0)
            end)
            C.SetMapPicking(holo.holomap, true)
            log("holomap", { id = tostring(holo.holomap), show_ok = tostring(ok), err = tostring(err or "") })
        end
    end
    if holo.holomap ~= 0 and holo.scan then
        stepScan()
        return
    end
    if holo.holomap ~= 0 and holo.map then
        local x, y = GetRenderTargetMousePosition(holo.map)
        C.SetMapRelativeMousePosition(holo.holomap, (x and y) ~= nil, x or 0, y or 0)
        if now >= holo.nextPick then
            holo.nextPick = now + 0.1
            local kind, slot = pickedSlot()
            local entry = kind == "turret" and holo.bySlot[slot]
            local text = entry and (entry.groupLabel .. "; " .. entry.name) or (kind and (kind .. " " .. tostring(slot)) or "")
            if text ~= holo.hover then
                holo.hover = text
                if text ~= "" then
                    -- Calibration pair for drawing our own markers: which slot
                    -- is under the mouse, where the mouse is (-1..1), and the
                    -- camera state at that moment.
                    local mx, my = GetRenderTargetMousePosition(holo.map)
                    log("hover", { kind = kind, slot = slot, text = text,
                        component = entry and tostring(entry.component) or "",
                        mouse = string.format("%.4f,%.4f", mx or 0, my or 0), state = stateKey() })
                end
                menu.frame:update()
            end
        end
        if now >= (holo.nextState or 0) then
            holo.nextState = now + 0.5
            local key = stateKey()
            if key ~= holo.lastState then
                holo.lastState = key
                log("state", { offset_and_distance = key })
            end
        end
        if holo.flash and now >= (holo.nextFlash or 0) then
            holo.nextFlash = now + 1
            local slots = {}
            for _, entry in ipairs(holo.slots or {}) do if math.random() < 0.5 then slots[#slots + 1] = entry.slot end end
            highlight(slots)
        end
    end
end

-- Helper dispatches render-target mouse events to these names.
function menu.onRenderTargetMouseDown()
    if holo.holomap ~= 0 then C.StartRotateMap(holo.holomap) end
    holo.leftdown = { time = GetCurRealTime(), position = table.pack(GetLocalMousePosition()) }
end

function menu.onRenderTargetMouseUp()
    if holo.holomap ~= 0 then C.StopRotateMap(holo.holomap) end
end

function menu.onRenderTargetMiddleMouseDown() if holo.holomap ~= 0 then C.StartPanMap(holo.holomap) end end
function menu.onRenderTargetMiddleMouseUp() if holo.holomap ~= 0 then C.StopPanMap(holo.holomap) end end
function menu.onRenderTargetRightMouseDown() if holo.holomap ~= 0 then C.StartPanMap(holo.holomap) end end
function menu.onRenderTargetRightMouseUp() if holo.holomap ~= 0 then C.StopPanMap(holo.holomap) end end
function menu.onRenderTargetCombinedScrollDown(step) if holo.holomap ~= 0 then C.ZoomMap(holo.holomap, step) end end
function menu.onRenderTargetCombinedScrollUp(step)
    if holo.holomap == 0 then return end
    local before = select(2, stateKey()).cameradistance
    C.ZoomMap(holo.holomap, -step)
    local _, state = stateKey()
    -- ZoomMap may apply over later frames; only intervene when it did nothing.
    if math.abs(state.cameradistance - before) < 0.01 then
        state.cameradistance = before * 0.85
        C.SetMapState(holo.holomap, state)
        local _, after = stateKey()
        log("zoom_past_limit", { before = before, requested = before * 0.85, after = after.cameradistance })
    end
end

-- A click is a short press without movement (vanilla's 0.2 s / 2 px rule).
function menu.onRenderTargetSelect()
    local offset = table.pack(GetLocalMousePosition())
    if not (holo.leftdown and holo.leftdown.time + 0.2 > GetCurRealTime()
            and not Helper.comparePositions(holo.leftdown.position, offset, 2)) then return end
    local kind, slot = pickedSlot()
    local entry = kind == "turret" and holo.bySlot[slot]
    log("click", { kind = tostring(kind), slot = tostring(slot), turret = entry and tostring(entry.component) or "none" })
    if entry and entry.componentID then
        local ok, reason = api().enterCamera({ componentID = entry.componentID, cameraSupported = true })
        log("camera", { ok = tostring(ok), reason = tostring(reason or "") })
    end
end

function menu.onCloseElement(dueToClose)
    if holo.closing then return end
    holo.closing = true
    if holo.holomap ~= 0 then C.RemoveHoloMap(); holo.holomap = 0 end
    holo.map, holo.activate, holo.flash = nil, false, false
    log("close", { reason = tostring(dueToClose) })
    Helper.closeMenuAndOpenNewMenu(menu, "X4GunneryTestLab", { 0, 0 }, true)
end

local function init()
    Menus = Menus or {}; table.insert(Menus, menu)
    if Helper then Helper.registerMenu(menu) end
    RegisterEvent("X4GunneryTestLab.TurretMapPosition", onPosition)
end

init()
