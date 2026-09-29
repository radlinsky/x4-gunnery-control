-- Ship configuration hologram shared by the console and Direct-control view.
-- Public APIs only; the disposable native probe established the camera model.
X4GunneryHologram = {}
local H = X4GunneryHologram
local ffi = require("ffi")
local C = ffi.C
local State = X4GunneryState
-- Vanilla may already have declared these types.
for _, declaration in ipairs({
    "typedef uint64_t UniverseID;",
    "typedef struct { float x; float y; float z; float yaw; float pitch; float roll; } UIPosRot;",
    "typedef struct { UIPosRot offset; float cameradistance; } HoloMapState;",
    "typedef struct { const char* upgradetype; size_t slot; } UILoadoutSlot;",
}) do pcall(ffi.cdef, declaration) end
ffi.cdef[[
void GetMapState(UniverseID holomapid, HoloMapState* state);
void SetMapState(UniverseID holomapid, HoloMapState state);
UniverseID AddHoloMap(const char* texturename, float x0, float x1, float y0, float y1, float aspectx, float aspecty);
void RemoveHoloMap(void);
void SetMapPicking(UniverseID holomapid, bool enable);
void SetMapRelativeMousePosition(UniverseID holomapid, bool valid, float x, float y);
void StartRotateMap(UniverseID holomapid);
void StopRotateMap(UniverseID holomapid);
void ZoomMap(UniverseID holomapid, float zoomstep);
bool GetPickedMapMacroSlot(UniverseID holomapid, UniverseID defensibleid, UniverseID moduleid, const char* macroname, bool ismodule, UILoadoutSlot* result);
size_t GetNumUpgradeSlots(UniverseID destructibleid, const char* macroname, const char* upgradetypename);
UniverseID GetUpgradeSlotCurrentComponent(UniverseID destructibleid, const char* upgradetypename, size_t slot);
]]
pcall(ffi.cdef, "void ShowObjectConfigurationMap2(UniverseID holomapid, UniverseID defensibleid, UniverseID moduleid, const char* macroname, bool ismodule, UILoadout uiloadout, size_t cp_idx);")
local view, sequence = nil, 0
local cameras = {} -- Per runtime ship, survives menu/session teardown; UI reload starts a new lifetime.
local function uid(value) return State.normID(value) end
local function luaID(value) return ConvertStringToLuaID(tostring(value)) end
local function length(value)
    return tonumber(tostring(value or ""):match("^%s*([-+]?[%d%.]+[eE]?[-+]?%d*)"))
end

-- General orbit model from Test Lab projectTurret, validated on M and XL.
-- Far-side treatment is a keel-normal heuristic, not a hull occlusion query.
function H.project(entry, state, radius, aspect)
    if not radius or radius <= 0 or not aspect or aspect <= 0 then return nil end
    local yaw, pitch, d = state.offset.yaw, state.offset.pitch, state.cameradistance * radius
    if d <= 0 or not entry.x or not entry.y or not entry.z then return nil end
    local cp = math.cos(pitch)
    local cam = { -cp * math.sin(yaw) * d, -math.sin(pitch) * d, -cp * math.cos(yaw) * d }
    local f = { -cam[1] / d, -cam[2] / d, -cam[3] / d }
    local rl = math.sqrt(f[3] ^ 2 + f[1] ^ 2)
    if rl < 1e-6 then return nil end
    local r = { -f[3] / rl, 0, f[1] / rl }
    local u = { -r[3] * f[2], r[3] * f[1] - r[1] * f[3], r[1] * f[2] }
    local rel = { entry.x - cam[1], entry.y - cam[2], entry.z - cam[3] }
    local z = rel[1] * f[1] + rel[2] * f[2] + rel[3] * f[3]
    if z <= 1 then return nil end
    local x = -(rel[1] * r[1] + rel[3] * r[3]) / z / 0.75 / aspect
    local y = (rel[1] * u[1] + rel[2] * u[2] + rel[3] * u[3]) / z / 0.75
    return x, y, entry.x * (cam[1] - entry.x) + entry.y * (cam[2] - entry.y) < 0
end

-- X4 hides a rectangle at once but shows a new one only at its next shape
-- update, which runs before this module's update each frame. Draw the
-- replacement first and hide the old markers one update later; otherwise every
-- redraw renders a frame without markers.
local function clearShapes(v)
    for _, shape in ipairs(v.shapes) do HideRect(shape) end
    for _, shape in ipairs(v.stale) do HideRect(shape) end
    v.shapes, v.stale, v.staleIDs = {}, {}, {}
end

local function retireShapes(v)
    for _, shape in ipairs(v.shapes) do v.stale[#v.stale + 1] = shape; v.staleIDs[shape] = true end
    v.shapes = {}
end

local function hideStale(v)
    for _, shape in ipairs(v.stale) do HideRect(shape) end
    v.stale, v.staleIDs = {}, {}
end

local function releaseRender(v, keepShapes)
    if v.map and v.map ~= 0 then
        local state = ffi.new("HoloMapState")
        C.GetMapState(v.map, state)
        cameras[uid(v.session.shipID)] = { yaw = tonumber(state.offset.yaw), pitch = tonumber(state.offset.pitch), distance = tonumber(state.cameradistance) }
        C.StopRotateMap(v.map)
        C.RemoveHoloMap()
    end
    if keepShapes then hideStale(v) else clearShapes(v) end
    v.map, v.widget, v.press, v.picked = nil, nil, nil, nil
    v.drawKey = nil
end

-- A menu rebuild keeps the markers on screen; the following mount reuses them
-- until its first draw, or close hides them.
function H.refresh()
    if view then releaseRender(view, true) end
end

function H.close()
    local v = view
    if not v then return end
    view = nil -- Late MD replies cannot attach to a replacement view.
    releaseRender(v)
    AddUITriggeredEvent("X4GunneryHologram", "close", { nonce = v.nonce })
end

function H.mount(menu, frame, session, rect, combat, onClick)
    local previous = view
    H.refresh()
    sequence = sequence + 1
    local v = { menu = menu, session = session, layer = frame.properties.layer or 4,
        rect = rect, combat = combat, onClick = onClick, shapes = {}, stale = {}, staleIDs = {}, entries = {}, bySlot = {},
        nonce = tostring(GetCurRealTime()) .. "-" .. tostring(sequence), hover = "", nextDraw = 0 }
    v.ship = ConvertStringTo64Bit(tostring(session.shipID))
    v.macro = GetComponentData(v.ship, "macro") or ""
    local members = {}
    for _, group in ipairs(session.groups or {}) do
        for _, member in ipairs(group.members or {}) do
            members[uid(member.componentID)] = { group = group, member = member }
        end
    end
    local turrets, selected, signature = {}, {}, { uid(session.shipID), combat and uid(session.aimTargetID or session.targetObjectID) or "console" }
    for slot = 1, tonumber(C.GetNumUpgradeSlots(v.ship, "", "turret")) do
        local component = C.GetUpgradeSlotCurrentComponent(v.ship, "turret", slot)
        local match = members[uid(component)]
        if component ~= 0 and match then
            local entry = { slot = slot, component = component, group = match.group, member = match.member,
                selected = session.checkedGroupKeys[match.group.key] == true,
                missile = C.IsComponentClass(component, "missileturret"), activity = "idle" }
            v.entries[#v.entries + 1], v.bySlot[slot] = entry, entry
            turrets[#turrets + 1] = luaID(component)
            selected[#selected + 1] = entry.selected
            signature[#signature + 1] = uid(component) .. "/" .. tostring(entry.selected)
        end
    end
    v.signature = table.concat(signature, ":")
    local reuse = previous and previous.session == session and previous.signature == v.signature
    if reuse then
        v.nonce, v.radius = previous.nonce, previous.radius
        for index, entry in ipairs(v.entries) do
            local old = previous.entries[index]
            entry.x, entry.y, entry.z, entry.activity = old.x, old.y, old.z, old.activity
        end
        v.shapes, previous.shapes = previous.shapes, {}
        v.carriedUntil = GetCurRealTime() + 1
    else
        H.close()
    end
    view = v
    frame:addRenderTarget({ x = rect.x, y = rect.y, width = rect.w, height = rect.h, scaling = false, alpha = 100 })
    local hover = frame:addTable(1, { tabOrder = 0, x = rect.x, y = rect.y + rect.h, width = rect.w })
    hover:addRow(false, {})[1]:createText(function() return v.hover end)
    if not combat then
        hover:addRow(false, {})[1]:createText("Click a turret to toggle its group for Direct-control. Left-drag rotates; wheel zooms.",
            { wordwrap = true, color = Color["text_inactive"] })
    end
    if not reuse then
        AddUITriggeredEvent("X4GunneryHologram", "open", { nonce = v.nonce, ship = luaID(v.ship),
            target = combat and luaID(session.aimTargetID or session.targetObjectID) or nil,
            count = #turrets, combat = combat })
        for index, turret in ipairs(turrets) do
            AddUITriggeredEvent("X4GunneryHologram", "member", { nonce = v.nonce,
                index = index, turret = turret, selected = selected[index] })
        end
        AddUITriggeredEvent("X4GunneryHologram", "commit", { nonce = v.nonce })
    end
end

function H.viewCreated(layer, ...)
    if not view or layer ~= view.layer then return end
    for _, child in ipairs({ ... }) do
        if IsType(child, "rendertarget") then
            if view.widget and view.widget ~= child then releaseRender(view) end
            view.widget = child
        end
    end
end

-- Full snapshot commits atomically; geometry replies carry a view nonce and
-- roster ordinal, never a rounded numeric position or a guessed component id.
function H.receive(_, payload)
    local v = view
    if not v or type(payload) ~= "string" then return end
    local nonce, kind, data = payload:match("^x4gh1:([^:]+):([^:]+):(.*)$")
    if nonce ~= v.nonce then return end
    if kind == "size" then
        local size = length(data)
        if size and size > 0 then v.radius = size / 2 end
    elseif kind == "position" then
        local index, x, y, z = data:match("^([%d%.]+):([^:]+):([^:]+):([^:]+)$")
        local entry = index and v.entries[tonumber(index)]
        x, y, z = length(x), length(y), length(z)
        if entry and x and y and z then entry.x, entry.y, entry.z = x, y, z end
    elseif kind == "activity" and #data == #v.entries and not data:find("[^012]") then
        for index, entry in ipairs(v.entries) do
            local code = data:sub(index, index)
            entry.activity = code == "2" and not entry.missile and "hit" or (code == "1" and "fired" or "idle")
        end
    end
    v.drawKey = nil
end

-- Each marker set fits a 450-rectangle budget, so the old and new sets together
-- stay inside 900 of the shared 1000-slot pool during the one-update overlap.
-- Every shape scales with the per-marker allowance; at 101 visible turrets each
-- marker gets four rectangles. Stop on pool exhaustion.
-- ponytail: past 112 visible markers the 4-line hit square exceeds the allowance
-- and the budget check drops the remainder.
local function draw(v, state)
    retireShapes(v)
    v.carriedUntil = nil
    local visible = {}
    for _, entry in ipairs(v.entries) do
        if not v.combat or entry.selected then
            local x, y, far = H.project(entry, state, v.radius, v.aspect)
            if x and math.abs(x) < 1 and math.abs(y) < 1 then
                visible[#visible + 1] = { entry = entry, x = x, y = y, far = far }
            end
        end
    end
    local budget, failed = 450, false
    local limit = math.min(12, math.floor(budget / math.max(#visible, 1)))
    local cost = math.min(#visible > 60 and 8 or 12, limit)
    local function line(ax, ay, bx, by, color, thickness)
        if failed or #v.shapes >= budget then return end
        local shape = Helper.drawLine({ x = ax, y = ay }, { x = bx, y = by }, thickness or 2, nil, color, true)
        if shape == nil then failed = true; return end
        -- A reissued id means the engine already freed every tracked rectangle
        -- (HideAllShapes on view close); hiding the stale ids now would hide
        -- these new markers.
        if v.staleIDs[shape] then v.stale, v.staleIDs = {}, {} end
        v.shapes[#v.shapes + 1] = shape
    end
    for _, point in ipairs(visible) do
        if #v.shapes + limit > budget or failed then break end
        local entry, rt = point.entry, v.bounds
        local status = entry.selected and entry.activity or "unselected"
        local color = Color[status == "hit" and "text_positive" or status == "fired" and "text_warning" or status == "idle" and "icon_normal" or "text_inactive"]
        if point.far then color = { r = color.r, g = color.g, b = color.b, a = (color.a or 100) * 0.2, glow = color.glow } end
        local size = math.max(5, math.min(12, 7 / math.sqrt(math.max(tonumber(state.cameradistance), 0.05))))
        if point.far then size = size * 0.7 end
        local cx, cy = rt.x + (point.x + 1) * rt.w / 2, rt.y + (1 - point.y) * rt.h / 2
        -- Keep the entire marker inside its render target.
        if cx - size >= rt.x and cx + size <= rt.x + rt.w and cy - size >= rt.y and cy + size <= rt.y + rt.h then
            if status == "fired" then -- burst, distinguishable without color
                local spokes = math.min(4, limit)
                for i = 0, spokes - 1 do
                    local a = i * math.pi / spokes
                    local dx, dy = math.cos(a) * size, math.sin(a) * size
                    line(cx - dx, cy - dy, cx + dx, cy + dy, color)
                end
            elseif status == "hit" then -- square reticle, with four inward ticks when the budget allows
                for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
                    local x, y = d[1] * size, d[2] * size
                    line(cx + x - y, cy + y + x, cx + x + y, cy + y - x, color)
                    if limit >= 8 then line(cx + x, cy + y, cx + x * 0.5, cy + y * 0.5, color) end
                end
            elseif status == "idle" then -- filled disc from horizontal strips
                local strips = math.min(6, limit)
                for i = 0, strips - 1 do
                    local y = -size + (i + 0.5) * 2 * size / strips
                    local w = math.sqrt(size * size - y * y)
                    line(cx - w, cy + y, cx + w, cy + y, color, 2 * size / strips + 1)
                end
            else -- hollow ring
                for i = 0, cost - 1 do
                    local a, b = i * 2 * math.pi / cost, (i + 1) * 2 * math.pi / cost
                    line(cx + size * math.cos(a), cy + size * math.sin(a), cx + size * math.cos(b), cy + size * math.sin(b), color)
                end
            end
        end
    end
    local counts = tostring(#visible) .. ":" .. tostring(#v.shapes) .. ":" .. tostring(failed)
    if counts ~= v.lastCounts then
        v.lastCounts = counts
        DebugError("[X4GC HOLO] markers nonce=" .. v.nonce .. " visible=" .. tostring(#visible)
            .. " rectangles=" .. tostring(#v.shapes) .. " coarse=" .. tostring(cost < 12)
            .. " exhausted=" .. tostring(failed))
    end
end

function H.update()
    local v = view
    if not v then return end
    hideStale(v)
    local now = GetCurRealTime()
    -- Markers carried across a rebuild must not outlive a view that never draws.
    if v.carriedUntil and now >= v.carriedUntil then retireShapes(v); v.carriedUntil = nil end
    if not v.nextHeartbeat or now >= v.nextHeartbeat then
        v.nextHeartbeat = now + 1
        AddUITriggeredEvent("X4GunneryHologram", "heartbeat", { nonce = v.nonce })
    end
    if not v.widget then return end
    if not v.map then
        local texture = GetRenderTargetTexture(v.widget)
        if not texture then return end
        local x0, x1, y0, y1 = Helper.getRelativeRenderTargetSize(v.menu, v.layer, v.widget)
        -- Helper returns normalized screen bounds; use actual widget dimensions
        -- rather than requested layout dimensions (scaling can round them).
        local w, h = GetSize(v.widget)
        if w <= 0 or h <= 0 then return end
        v.aspect = w / h
        v.bounds = { x = (x0 + 1) * Helper.viewWidth / 2, y = (1 - y1) * Helper.viewHeight / 2, w = w, h = h }
        v.map = C.AddHoloMap(texture, x0, x1, y0, y1, v.aspect, 1)
        if v.map == 0 then v.map = nil; return end
        local ok, reason = pcall(Helper.callLoadoutFunction, {}, nil, function(loadout)
            C.ShowObjectConfigurationMap2(v.map, v.ship, 0, v.macro, false, loadout, 0)
        end)
        if not ok then
            DebugError("[X4GC HOLO] configuration map failed: " .. tostring(reason))
            H.close()
            return
        end
        C.SetMapPicking(v.map, true)
        local remembered = cameras[uid(v.session.shipID)]
        if remembered then
            local state = ffi.new("HoloMapState")
            C.GetMapState(v.map, state)
            state.offset.yaw, state.offset.pitch, state.cameradistance = remembered.yaw, remembered.pitch, remembered.distance
            C.SetMapState(v.map, state)
        end
    end
    local x, y = GetRenderTargetMousePosition(v.widget)
    C.SetMapRelativeMousePosition(v.map, x ~= nil and y ~= nil, x or 0, y or 0)
    if now < v.nextDraw then return end
    v.nextDraw = now + 0.05
    local picked = ffi.new("UILoadoutSlot")
    local entry
    if x and y and C.GetPickedMapMacroSlot(v.map, v.ship, 0, v.macro, false, picked) and ffi.string(picked.upgradetype) == "turret" then
        entry = v.bySlot[tonumber(picked.slot)]
        if entry and v.combat and not entry.selected then entry = nil end
    end
    v.picked = entry
    v.hover = entry and State.turretLabel(entry.group, entry.member) or ""
    local state = ffi.new("HoloMapState")
    C.GetMapState(v.map, state)
    local key = table.concat({ tostring(state.offset.yaw), tostring(state.offset.pitch), tostring(state.cameradistance) }, ":")
    if key ~= v.drawKey then draw(v, state); v.drawKey = key end
end

function H.mouseDown()
    if not view or not view.map then return end
    local x, y = GetLocalMousePosition()
    if not x or not y then return end
    view.press = { x = x, y = y, time = GetCurRealTime() }
    C.StartRotateMap(view.map)
end
function H.mouseUp() if view and view.map then C.StopRotateMap(view.map) end end
function H.zoom(step)
    local v = view
    if not v or not v.map then return end
    local state = ffi.new("HoloMapState")
    C.GetMapState(v.map, state)
    local before = tonumber(state.cameradistance)
    C.ZoomMap(v.map, step)
    if step >= 0 then return end
    -- The wheel stops at vanilla's limit; push closer ourselves (Test Lab probe c126407).
    C.GetMapState(v.map, state)
    if math.abs(state.cameradistance - before) < 0.01 then
        state.cameradistance = math.max(0.1, before * 0.85)
        C.SetMapState(v.map, state)
    end
end
function H.select()
    local v = view
    if not v or not v.press or not v.picked then return end
    local x, y = GetLocalMousePosition()
    local press = v.press
    v.press = nil
    if x and y and GetCurRealTime() - press.time < 0.2 and math.abs(x - press.x) <= 2 and math.abs(y - press.y) <= 2 then
        v.onClick(v.picked.member, v.picked.group)
    end
end
RegisterEvent("X4GunneryHologram.Data", H.receive)
return H
