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
    holo.slotCount = count
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

-- Temporary Task 5 equipment. No native code is required unless explicitly armed.
local anchorSequence = 0
local projectTurret, HOLO_TANHALF  -- defined with the marker code below
local function uid(value) return tostring(ffi.cast("uint64_t", value)):gsub("ULL$", "") end
local function exactState()
    local state = ffi.new("HoloMapState")
    C.GetMapState(holo.holomap, state)
    local o = state.offset
    return { tonumber(o.x), tonumber(o.y), tonumber(o.z), tonumber(o.yaw), tonumber(o.pitch), tonumber(o.roll), tonumber(state.cameradistance) }
end
local function quote(value)
    return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(c)
        if c == '"' or c == '\\' then return '\\' .. c end
        return string.format("\\u%04x", c:byte())
    end) .. '"'
end
local function json(value)
    if type(value) == "string" then return quote(value) end
    if type(value) == "boolean" then return tostring(value) end
    if type(value) == "number" then
        if value ~= value or math.abs(value) == math.huge then error("nonfinite measurement") end
        return string.format("%.17g", value)
    end
    if type(value) ~= "table" then error("unsupported measurement value") end
    local fields = {}
    if #value > 0 then
        for _, v in ipairs(value) do fields[#fields + 1] = json(v) end
        return "[" .. table.concat(fields, ",") .. "]"
    end
    local keys = {}; for key in pairs(value) do keys[#keys + 1] = key end; table.sort(keys)
    for _, key in ipairs(keys) do fields[#fields + 1] = quote(key) .. ":" .. json(value[key]) end
    return "{" .. table.concat(fields, ",") .. "}"
end
local function widget()
    if not holo.map or not menu.frameData or not menu.frameData[LAYER] then return nil end
    local w, h = GetSize(holo.map)
    local x, y = GetOffset(holo.map)
    local frame = menu.frameData[LAYER]
    local x0, x1, y0, y1 = Helper.getRelativeRenderTargetSize(menu, LAYER, holo.map)
    return { widget = tostring(holo.map), width = w, height = h, measured_aspect = h > 0 and w / h or 0, offset = { x, y },
        frame_origin = { frame.x, frame.y }, bounds = { x + frame.x, y + frame.y, x + frame.x + w, y + frame.y + h },
        normalized = { x0, x1, y0, y1 }, view = { Helper.viewWidth, Helper.viewHeight }, ui_scale = Helper.uiScale }
end
local function nativeCommand(text) CallEventScripts("X4GunneryAnchor.Request", text) end
local function sameLoadout()
    if tonumber(C.GetNumUpgradeSlots(holo.ship, "", "turret")) ~= holo.slotCount then return false end
    for slot = 1, holo.slotCount do
        local expected = holo.bySlot[slot] and holo.bySlot[slot].component or 0
        if uid(C.GetUpgradeSlotCurrentComponent(holo.ship, "turret", slot)) ~= uid(expected) then return false end
    end
    return true
end
local function finishAnchor(reason, native)
    local a = holo.anchor
    if not a then return end
    local after, bounds = exactState(), widget()
    if a.before and json(a.before) ~= json(after) then reason = reason or "lua_camera_changed" end
    if a.widget and (not bounds or json(a.widget) ~= json(bounds)) then reason = reason or "widget_changed" end
    if not sameLoadout() then reason = reason or "loadout_changed" end
    local probe = {}
    local entry = a.slot and holo.bySlot and holo.bySlot[a.slot]
    if entry and entry.x then
        local _, state = stateKey()
        local mx, my, far = projectTurret(entry, state)
        if mx then probe = { ndc = { mx, my }, far_side = far and true or false, position = { entry.x, entry.y, entry.z },
            scale = holo.scale, aspect = holo.aspect, tanhalf = HOLO_TANHALF } end
    end
    local record = { request = a.id, sequence = a.sequence, valid = reason == nil, live_verified = false,
        reason = reason or "structural_checks_passed_live_validation_required", ship = uid(holo.ship), macro = holo.macro,
        holomap = uid(holo.holomap), fixture_sha = "2cd5bab427a79790431dc7347ca6a6abc77d3414",
        fixture_sha_role = "unchanged_accepted_fixture_source", fixture_spec = a.spec or "none",
        slot = a.slot or 0, component = a.component or "none", positions = a.positions or {},
        public_turret_slots = holo.slotCount,
        probe_projection = probe,
        ship_radius = a.radius or 0,
        before = a.before or after, after = after, widget_before = a.widget or bounds or {}, widget_after = bounds or {},
        add_holomap = holo.addInputs or {}, requested_state = holo.requestedState or {},
        started = a.started, finished = getElapsedTime(), ui_update = holo.anchorUpdate or 0 }
    DebugError("[X4GC TEST] ANCHOR_RECORD " .. json(record):sub(1, -2) .. ',"native":' .. (native or "null") .. "}")
    holo.anchor, holo.anchorStatus = nil, reason and ("INVALID: " .. reason) or "Captured; LIVE validation still required"
    menu.frame:update()
end
local function cancelAnchor(reason)
    local a = holo.anchor
    if not a then return end
    -- Clear locally first: a synchronous cancellation reply cannot complete it twice.
    finishAnchor(reason or "cancelled")
    nativeCommand("C|" .. a.id)
end
local function startAnchor()
    if holo.anchor then cancelAnchor(); return end
    if holo.holomap == 0 or holo.scan then holo.anchorStatus = "Finish the scan / wait for the map"; menu.frame:update(); return end
    if holo.geometryRequest then holo.anchorStatus = "Waiting for the previous MD reply before rearming"; menu.frame:update(); return end
    anchorSequence = anchorSequence + 1
    holo.anchor = { id = string.format("%.9f_%d", GetCurRealTime(), anchorSequence), sequence = anchorSequence,
        phase = "hello", started = getElapsedTime(), deadline = getElapsedTime() + 5, positions = {} }
    holo.anchorStatus = "Checking disposable native probe..."
    nativeCommand("H|" .. holo.anchor.id)
    menu.frame:update()
end
local function distancePreset(distance)
    if holo.anchor then cancelAnchor("camera_control_during_capture") end
    local state = ffi.new("HoloMapState")
    C.GetMapState(holo.holomap, state)
    state.cameradistance = distance
    C.SetMapState(holo.holomap, state)
    holo.requestedState = exactState()
    holo.requestedState[7] = distance  -- Requested decimal and actual readback remain distinct.
end
local function nativeStateMatches(payload, name, expected)
    local raw = payload:match('"' .. name .. '":%[([^%]]*)%]')
    if not raw then return false end
    local values = {}; for number in raw:gmatch("[^,]+") do values[#values + 1] = tonumber(number) end
    if #values ~= 7 then return false end
    for i, value in ipairs(values) do if tonumber(ffi.new("float[1]", value)[0]) ~= expected[i] then return false end end
    return true
end
local function onAnchorReply(_, param)
    local id, status, payload = tostring(param or ""):match("^([^|]+)|([^|]+)|(.+)$")
    local a = holo.anchor
    if not a or id ~= a.id then return end
    if status == "ready" and a.phase == "hello" then
        a.phase, a.deadline = "hover", getElapsedTime() + 30
        holo.anchorStatus = "Hover one green turret slot; hold camera still"
    elseif status == "armed" and a.phase == "native" then
        holo.anchorStatus = "Capturing hovered slot " .. a.slot .. "..."
    elseif status == "ok" and a.phase == "native" then
        local reason
        if not nativeStateMatches(payload, "before", a.before) or not nativeStateMatches(payload, "after", a.before) then
            reason = "native_lua_state_mismatch"
        end
        if tonumber(payload:match('"public_slot":(%d+)')) ~= a.slot then reason = "native_public_slot_mismatch" end
        finishAnchor(reason, payload)
    elseif status == "invalid" then finishAnchor("native_rejected", payload)
    else cancelAnchor("unexpected_native_reply") end
    if menu.frame then menu.frame:update() end
end
local function onGeometryHeader(_, param)
    local id, slot, spec = tostring(param or ""):match("^([^:]+):([^:]+):(.+)$")
    local a = holo.anchor
    if not a or a.phase ~= "md" or id ~= a.id then return end
    if tonumber(slot) ~= a.pending.slot or (a.spec and a.spec ~= spec) or a.header then cancelAnchor("geometry_header_identity"); return end
    a.spec, a.header, a.numbers = spec, true, {}
end
local function geometryComponent(which, param)
    local a = holo.anchor
    if not a or a.phase ~= "md" or not a.header then return end
    local expected = which == "ship" and holo.ship or a.pending.component
    if not sameID(param, expected) or a[which .. "Reply"] then cancelAnchor("geometry_component_identity"); return end
    a[which .. "Reply"] = true
end
local function onGeometryNumber(_, param)
    local a = holo.anchor
    if not a or a.phase ~= "md" or not a.header then return end
    if type(param) ~= "number" or param ~= param or math.abs(param) == math.huge or #a.numbers >= 4 then
        cancelAnchor("geometry_numeric_transport"); return
    end
    a.numbers[#a.numbers + 1] = param
end
local function onGeometryEnd(_, param)
    local id = tostring(param):gsub(":fail$", "")
    if id == holo.geometryRequest then holo.geometryRequest = nil end
    local a = holo.anchor
    if not a or a.phase ~= "md" then return end
    if tostring(param) ~= a.id or not a.header or not a.shipReply or not a.turretReply or #a.numbers ~= 4 or a.numbers[1] <= 0 then
        cancelAnchor("geometry_incomplete"); return
    end
    if a.radius and a.radius ~= a.numbers[1] then cancelAnchor("geometry_radius_changed"); return end
    a.radius = a.numbers[1]
    a.positions[#a.positions + 1] = { slot = a.pending.slot, component = uid(a.pending.component),
        radius = a.radius, position = { a.numbers[2], a.numbers[3], a.numbers[4] } }
    a.phase = "md_next"  -- Next request on the next UI update; no nested MD request.
end
local function stepAnchor()
    local a = holo.anchor
    if not a then return end
    if getElapsedTime() > a.deadline then cancelAnchor("timeout_" .. a.phase); return end
    if a.before and json(a.before) ~= json(exactState()) then cancelAnchor("camera_changed_before_capture"); return end
    if a.phase == "hover" then
        local kind, slot = pickedSlot()
        local entry = kind == "turret" and holo.bySlot[slot]
        local state = exactState()
        local key = entry and (tostring(slot) .. json(state)) or ""
        a.stable = key ~= "" and key == a.last and (a.stable or 0) + 1 or 0
        a.last = key
        if a.stable >= 3 then
            a.before, a.widget, a.slot, a.component = state, widget(), slot, uid(entry.component)
            if not sameLoadout() then cancelAnchor("loadout_changed"); return end
            if not a.widget or a.widget.width <= 0 or a.widget.height <= 0 or not holo.addInputs
                or GetRenderTargetTexture(holo.map) ~= holo.addInputs.texture
                or json(a.widget.normalized) ~= json(holo.addInputs.bounds) then
                cancelAnchor("missing_or_stale_viewport"); return
            end
            a.phase, a.deadline = "md_next", getElapsedTime() + 10
            holo.anchorStatus = "Reading exact ship/turret geometry..."
        end
    elseif a.phase == "md_next" then
        local entry = holo.slots[#a.positions + 1]
        if entry then
            a.pending, a.header, a.shipReply, a.turretReply = entry, false, false, false
            a.phase = "md"
            holo.geometryRequest = a.id
            AddUITriggeredEvent("X4GunneryTestLabObserve", "holo_anchor_geometry", { request = a.id, slot = entry.slot,
                ship = ConvertStringToLuaID(tostring(holo.ship)), turret = ConvertStringToLuaID(tostring(entry.component)) })
        else
            a.phase, a.deadline = "native", getElapsedTime() + 5
            nativeCommand(table.concat({ "A", a.id, uid(holo.holomap), uid(holo.ship), a.component, tostring(a.slot), holo.macro }, "|"))
        end
    elseif a.phase == "native" then
        pickedSlot()  -- The temporary public-picker hook joins this exact public slot to its native pair.
        nativeCommand("P|" .. a.id)
    end
end

local function highlight(slots, why)
    if holo.holomap == 0 then return end
    if why then log("highlight", { why = why, slots = #slots }) end
    if #slots == 0 then C.ClearSelectedMapMacroSlots(holo.holomap); return end
    local buffer = ffi.new("size_t[?]", #slots)
    for i, slot in ipairs(slots) do buffer[i - 1] = slot end
    C.SetSelectedMapMacroSlots(holo.holomap, holo.ship, 0, holo.macro, false, "turret", buffer, #slots)
end

-- Our own turret markers over the hologram. Camera orbits the ship origin at
-- yaw/pitch from GetMapState; one cameradistance unit = half the MD
-- bounding-box diagonal ($ship.size / 2); vertical tan(FOV/2) = 0.75 and x is
-- divided by the render-target aspect. Confirmed against engine view-projection
-- matrices captured 2026-09-29 on XL and M ships (issue 205), error below
-- 1e-5 NDC with the MD string-route positions.
HOLO_TANHALF = 0.75
local STATE_COLORS = function()
    return { unselected = Color["text_inactive"], idle = Color["icon_normal"],
        fired = Color["text_warning"], hit = Color["text_positive"] }
end

function projectTurret(entry, state)
    if not holo.scale then return nil end
    local yaw, pitch, d = state.offset.yaw, state.offset.pitch, state.cameradistance * holo.scale
    local cp = math.cos(pitch)
    local cam = { -cp * math.sin(yaw) * d, -math.sin(pitch) * d, -cp * math.cos(yaw) * d }
    local fl = math.sqrt(cam[1] ^ 2 + cam[2] ^ 2 + cam[3] ^ 2)
    local f = { -cam[1] / fl, -cam[2] / fl, -cam[3] / fl }
    local r = { -f[3], 0, f[1] }                      -- f x (0,1,0)
    local rl = math.sqrt(r[1] ^ 2 + r[3] ^ 2)
    if rl < 1e-6 then return nil end
    r = { r[1] / rl, 0, r[3] / rl }
    local u = { r[2] * f[3] - r[3] * f[2], r[3] * f[1] - r[1] * f[3], r[1] * f[2] - r[2] * f[1] }
    local rel = { entry.x - cam[1], entry.y - cam[2], entry.z - cam[3] }
    local z = rel[1] * f[1] + rel[2] * f[2] + rel[3] * f[3]
    if z <= 1 then return nil end
    local mx = -(rel[1] * r[1] + rel[3] * r[3]) / z / HOLO_TANHALF / holo.aspect
    local my = (rel[1] * u[1] + rel[2] * u[2] + rel[3] * u[3]) / z / HOLO_TANHALF
    -- Far side = back-facing: the turret's outward direction, taken as away
    -- from the keel line (x, y, 0), points away from the camera. The
    -- hologram's slot picking sees through the hull, so true occlusion is not
    -- available. ponytail: keel-line normal; read each mount's
    -- relativerotation once if odd hulls misjudge.
    local farSide = (entry.x * (cam[1] - entry.x) + entry.y * (cam[2] - entry.y)) < 0
    return mx, my, farSide
end

local function line(ax, ay, bx, by, color, thickness)
    Helper.drawLine({ x = ax, y = ay }, { x = bx, y = by }, thickness, nil, color, true)
end

-- Shapes from rectangles only: X4's circle/triangle shapes are 3D meshes
-- that smear in the widget scene. Selected states build on the white disc.
local function ring(cx, cy, r, color, segs, thickness)
    for i = 0, segs - 1 do
        local a0, a1 = i * 2 * math.pi / segs, (i + 1) * 2 * math.pi / segs
        line(cx + r * math.cos(a0), cy + r * math.sin(a0), cx + r * math.cos(a1), cy + r * math.sin(a1), color, thickness)
    end
end

local function disc(cx, cy, r, color, segs)
    local strips = math.max(4, math.floor(segs * 0.6))
    local h = 2 * r / strips
    for j = 0, strips - 1 do
        local y = -r + (j + 0.5) * h
        local hw = math.sqrt(math.max(r * r - y * y, 0))
        Helper.drawRectangle(2 * hw, h + 1, cx - hw, cy + y - h / 2, 0, nil, color, true)
    end
end

local MARKERS = {
    unselected = function(cx, cy, s, c, segs) ring(cx, cy, s * 0.42, c.unselected, segs, 2) end,
    idle = function(cx, cy, s, c, segs) disc(cx, cy, s * 0.42, c.idle, segs) end,
    fired = function(cx, cy, s, c, segs)                     -- disc + orange burst
        disc(cx, cy, s * 0.42, c.idle, segs)
        for _, a in ipairs({ 0, 45, 90, 135 }) do
            local dx, dy = math.cos(math.rad(a)) * s * 0.75, math.sin(math.rad(a)) * s * 0.75
            line(cx - dx, cy - dy, cx + dx, cy + dy, c.fired, 2)
        end
    end,
    hit = function(cx, cy, s, c, segs)                       -- disc + green lock reticle
        disc(cx, cy, s * 0.42, c.idle, segs)
        -- Rectangle pool is 1000: crowded ships keep only the ticks.
        if segs > 6 then ring(cx, cy, s * 0.62, c.hit, segs, 2) end
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            line(cx + d[1] * s * 0.5, cy + d[2] * s * 0.5, cx + d[1] * s * 0.85, cy + d[2] * s * 0.85, c.hit, 2)
        end
    end,
}

local function dimmed(colors)
    local out = {}
    for k, c in pairs(colors) do out[k] = { r = c.r, g = c.g, b = c.b, a = math.floor((c.a or 100) * 0.10), glow = c.glow } end
    return out
end

local function drawMarkers(force)
    if holo.holomap == 0 or not holo.rt or not holo.markers then return end
    local key, state = stateKey()
    local stateSig = {}
    for _, entry in ipairs(holo.slots or {}) do stateSig[#stateSig + 1] = entry.state or "" end
    key = key .. table.concat(stateSig, ",")
    if key == holo.lastMarkerKey and not force then return end
    holo.lastMarkerKey = key
    HideAllRects()
    local colors, rt = STATE_COLORS(), holo.rt
    -- Bigger when zoomed in; bounded so markers stay markers.
    local size = math.max(16, math.min(36, 18 / math.sqrt(math.max(state.cameradistance, 0.05))))
    -- Rectangle pool is 1000 and a hit marker costs ~2.6 segs rects.
    -- ponytail: fixed budget; crowded ships (~100 turrets) get coarse circles.
    local segs = math.max(6, math.min(20, math.floor(850 / (3 * math.max(#(holo.slots or {}), 1)))))
    local faded = dimmed(colors)
    for _, entry in ipairs(holo.slots or {}) do
        if entry.x and entry.state then
            local mx, my, far = projectTurret(entry, state)
            if mx and math.abs(mx) <= 1 and math.abs(my) <= 1 then
                local cx = rt.x + (mx + 1) / 2 * rt.w
                local cy = rt.y + (1 - my) / 2 * rt.h
                -- Issue 205 alignment gate only: hollow ring + gapped cross so the
                -- green slot icon stays visible underneath. Restore MARKERS[entry.state] after the gate.
                local c, s = (far and faded or colors).fired, size * 0.6
                ring(cx, cy, s, c, segs, 1)
                for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                    line(cx + d[1] * s * 0.4, cy + d[2] * s * 0.4, cx + d[1] * s * 1.3, cy + d[2] * s * 1.3, c, 1)
                end
            end
        end
    end
end

local function shuffleStates()
    for _, entry in ipairs(holo.slots or {}) do
        if holo.preview then
            local states = { "unselected", "idle", "fired", "hit" }
            entry.state = states[math.random(#states)]
        else
            entry.state = entry.ticked and "idle" or "unselected"
        end
    end
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
    holo.lastMarkerKey = nil
end

local function onSize(_, param)
    local size = tonumber(tostring(param or ""):match("^x4ghs1:%s*([-+]?[%d%.]+)"))
    if size and size > 0 then holo.scale = size / 2; holo.lastMarkerKey = nil end
    log("size", { raw = tostring(param), scale = tostring(holo.scale) })
end

-- Scan: walk a virtual mouse over a grid, one point per frame, and ask the
-- holomap which slot is under it. Per-slot centroids plus the camera state
-- are the calibration data for drawing our own markers.
local SCAN_COLS, SCAN_ROWS = 48, 32
local function startScan()
    if holo.anchor then cancelAnchor("scan_during_capture") end
    if holo.holomap == 0 then return end
    holo.scan = { index = 0, pending = nil, hits = {}, state = stateKey() }
    log("scan_start", { state = holo.scan.state, grid = SCAN_COLS .. "x" .. SCAN_ROWS })
end

-- Refine: 9x9 samples, 3 px apart, around each turret's predicted screen
-- position; centroids are ~10x more precise than the coarse grid.
local function startRefine()
    if holo.anchor then cancelAnchor("scan_during_capture") end
    if holo.holomap == 0 or not holo.rt then return end
    local key, state = stateKey()
    local points = {}
    for _, entry in ipairs(holo.slots or {}) do
        if entry.x then
            local mx, my = projectTurret(entry, state)
            if mx and math.abs(mx) < 1 and math.abs(my) < 1 then
                for i = -4, 4 do
                    for j = -4, 4 do
                        points[#points + 1] = { mx + i * 6 / holo.rt.w, my + j * 6 / holo.rt.h, entry.slot, mx, my }
                    end
                end
            end
        end
    end
    holo.scan = { index = 0, pending = nil, hits = {}, state = key, points = points, predicted = {} }
    for _, p in ipairs(points) do holo.scan.predicted[p[3]] = { p[4], p[5] } end
    log("refine_start", { state = key, samples = #points })
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
    local total = scan.points and #scan.points or SCAN_COLS * SCAN_ROWS
    if scan.index >= total then
        local found = 0
        for slot, hit in pairs(scan.hits) do
            found = found + 1
            local entry = holo.bySlot[slot]
            local pred = scan.predicted and scan.predicted[slot]
            log("scan_hit", { slot = slot, component = entry and tostring(entry.component) or "",
                predicted = pred and string.format("%.4f,%.4f", pred[1], pred[2]) or "",
                mouse = string.format("%.4f,%.4f", hit.sx / hit.n, hit.sy / hit.n), samples = hit.n,
                pos = entry and entry.x and string.format("%.3f,%.3f,%.3f", entry.x, entry.y, entry.z) or "", state = scan.state })
        end
        log("scan_done", { turrets_found = found, state = scan.state, state_after = stateKey() })
        holo.scan = nil
        holo.hover = "scan done: " .. found .. " turrets found"
        menu.frame:update()
        return
    end
    local x, y
    if scan.points then
        x, y = scan.points[scan.index + 1][1], scan.points[scan.index + 1][2]
    else
        local col, row = scan.index % SCAN_COLS, math.floor(scan.index / SCAN_COLS)
        x = -1 + (col + 0.5) * 2 / SCAN_COLS
        y = -1 + (row + 0.5) * 2 / SCAN_ROWS
    end
    C.SetMapRelativeMousePosition(holo.holomap, true, x, y)
    scan.pending = { x, y }
    scan.index = scan.index + 1
end

function menu.onShowMenu()
    holo.closing, holo.flash, holo.scan = false, false, nil
    holo.markers, holo.preview, holo.scale = true, true, nil
    holo.anchor, holo.anchorStatus, holo.addInputs, holo.requestedState = nil, "Native capture idle", nil, nil
    if not readSlots() then log("no_session") else
        requestPositions()
        AddUITriggeredEvent("X4GunneryTestLabObserve", "holo_size", { ship = ConvertStringToLuaID(tostring(holo.ship)) })
        shuffleStates()
    end
    menu.display()
end

function menu.display()
    -- clearDataForRefresh, not clearMenu: clearMenu also drops onUpdate.
    Helper.clearDataForRefresh(menu)
    local width = Helper.scaleX(700)
    local rtHeight = Helper.scaleY(460)
    local frame = Helper.createFrameHandle(menu, { layer = LAYER, x = math.floor((Helper.viewWidth - width) / 2),
        y = Helper.scaleY(60), width = width, standardButtons = { close = true } })
    -- ponytail: frame x/y repeated in holo.rt below; keep them in step.
    menu.frame = frame
    local t = frame:addTable(4, { tabOrder = 1, x = Helper.borderSize, y = Helper.borderSize, width = width - 2 * Helper.borderSize })
    local title = t:addRow(false, { bgColor = Color["row_title_background"] })
    title[1]:setColSpan(4):createText("Turret hologram probe (issue #205)", Helper.headerRowCenteredProperties)
    local buttons = t:addRow("holo_buttons", {})
    buttons[1]:createButton({}):setText("Markers: " .. (holo.markers and "ON" or "OFF"))
    buttons[1].handlers.onClick = function()
        if holo.anchor then cancelAnchor("menu_rebuild_during_capture") end
        holo.markers = not holo.markers
        if not holo.markers then HideAllRects() end
        holo.lastMarkerKey = nil
        menu.display()
    end
    buttons[2]:createButton({}):setText("States: " .. (holo.preview and "preview all 4" or "real selection"))
    buttons[2].handlers.onClick = function()
        if holo.anchor then cancelAnchor("menu_rebuild_during_capture") end
        holo.preview = not holo.preview
        shuffleStates()
        menu.display()
    end
    buttons[3]:createButton({}):setText("Highlight ticked")
    buttons[3].handlers.onClick = function()
        if holo.anchor then cancelAnchor("selection_during_capture") end
        local slots = {}
        for _, entry in ipairs(holo.slots or {}) do if entry.ticked then slots[#slots + 1] = entry.slot end end
        highlight(slots, "ticked")
    end
    buttons[4]:createButton({}):setText("Back to Test Lab")
    buttons[4].handlers.onClick = function() menu.onCloseElement("back") end
    local legend = t:addRow(false, {})
    local colors = STATE_COLORS()
    for index, spec in ipairs({ { "unselected", "open circle: not selected" }, { "idle", "filled circle: selected" },
            { "fired", "+ orange burst: firing" }, { "hit", "+ green lock: hitting" } }) do
        legend[index]:createText(spec[2], { color = colors[spec[1]], fontsize = Helper.scaleFont(Helper.standardFont, 9) })
    end
    local scanRow = t:addRow("holo_scan", {})
    scanRow[1]:setColSpan(2):createButton({}):setText("Scan turret positions (hold still ~25 s)")
    scanRow[1].handlers.onClick = function()
        startScan(); holo.hover = "scanning..."; menu.frame:update()
    end
    scanRow[3]:setColSpan(2):createButton({}):setText("Refine scan (hold still ~20 s)")
    scanRow[3].handlers.onClick = function()
        startRefine(); holo.hover = "refining..."; menu.frame:update()
    end
    local exact = t:addRow("holo_anchor", {})
    exact[1]:createButton({}):setText(function() return holo.anchor and "Cancel exact capture" or "Arm exact anchor" end)
    exact[1].handlers.onClick = startAnchor
    for index, distance in ipairs({ 1.0, 0.85, 0.2724905312 }) do
        exact[index + 1]:createButton({}):setText("d=" .. tostring(distance))
        exact[index + 1].handlers.onClick = function() distancePreset(distance) end
    end
    local status = t:addRow(false, {})
    status[1]:setColSpan(4):createText(function() return holo.anchorStatus end)
    local help = t:addRow(false, {})
    help[1]:setColSpan(4):createText("Left-drag rotate, right- or middle-drag pan, wheel zoom, click a turret for its camera.",
        { fontsize = Helper.scaleFont(Helper.standardFont, 9) })
    local hover = t:addRow(false, {})
    hover[1]:setColSpan(4):createText(function() return "Hover: " .. holo.hover end)
    local rtY = t.properties.y + t:getFullHeight() + Helper.borderSize
    frame:addRenderTarget({ width = width - 2 * Helper.borderSize, height = rtHeight, x = Helper.borderSize, y = rtY, scaling = false, alpha = 100 })
    frame.properties.height = rtY + rtHeight + Helper.borderSize
    holo.aspect = (width - 2 * Helper.borderSize) / rtHeight
    -- Absolute pixel rectangle of the render target, for the marker overlay.
    local frameX = math.floor((Helper.viewWidth - width) / 2)
    holo.rt = { x = frameX + Helper.borderSize, y = Helper.scaleY(60) + rtY, w = width - 2 * Helper.borderSize, h = rtHeight }
    holo.lastMarkerKey = nil
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
            local float = function(v) return tonumber(ffi.new("float[1]", v)[0]) end
            holo.addInputs = { texture = texture, bounds = { x0, x1, y0, y1 },
                bounds_float = { float(x0), float(x1), float(y0), float(y1) },
                aspect = { holo.aspect or 1, 1 }, aspect_float = { float(holo.aspect or 1), 1 } }
            holo.holomap = C.AddHoloMap(texture, x0, x1, y0, y1, holo.aspect or 1, 1)
            local ok, err = pcall(Helper.callLoadoutFunction, {}, nil, function(loadout)
                return C.ShowObjectConfigurationMap2(holo.holomap, holo.ship, 0, holo.macro, false, loadout, 0)
            end)
            C.SetMapPicking(holo.holomap, true)
            log("holomap", { id = tostring(holo.holomap), show_ok = tostring(ok), err = tostring(err or "") })
        end
    end
    holo.anchorUpdate = (holo.anchorUpdate or 0) + 1
    stepAnchor()
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
        if holo.preview and now >= (holo.nextShuffle or 0) then
            holo.nextShuffle = now + 1
            shuffleStates()
        end
        drawMarkers()
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
    if holo.anchor and holo.anchor.before then cancelAnchor("camera_drag_during_capture") end
    if holo.holomap ~= 0 then C.StartRotateMap(holo.holomap) end
    holo.leftdown = { time = GetCurRealTime(), position = table.pack(GetLocalMousePosition()) }
end

function menu.onRenderTargetMouseUp()
    if holo.holomap ~= 0 then C.StopRotateMap(holo.holomap) end
end

function menu.onRenderTargetMiddleMouseDown() if holo.anchor then cancelAnchor("camera_pan_during_capture") end; if holo.holomap ~= 0 then C.StartPanMap(holo.holomap) end end
function menu.onRenderTargetMiddleMouseUp() if holo.holomap ~= 0 then C.StopPanMap(holo.holomap) end end
function menu.onRenderTargetRightMouseDown() if holo.anchor then cancelAnchor("camera_pan_during_capture") end; if holo.holomap ~= 0 then C.StartPanMap(holo.holomap) end end
function menu.onRenderTargetRightMouseUp() if holo.holomap ~= 0 then C.StopPanMap(holo.holomap) end end
function menu.onRenderTargetCombinedScrollDown(step) if holo.anchor then cancelAnchor("camera_zoom_during_capture") end; if holo.holomap ~= 0 then C.ZoomMap(holo.holomap, step) end end
function menu.onRenderTargetCombinedScrollUp(step)
    if holo.anchor then cancelAnchor("camera_zoom_during_capture") end
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
    if holo.anchor then cancelAnchor("turret_click_during_capture"); return end
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
    if holo.anchor then cancelAnchor("menu_closed") end
    HideAllRects()
    if holo.holomap ~= 0 then C.RemoveHoloMap(); holo.holomap = 0 end
    holo.map, holo.activate, holo.flash = nil, false, false
    log("close", { reason = tostring(dueToClose) })
    Helper.closeMenuAndOpenNewMenu(menu, "X4GunneryTestLab", { 0, 0 }, true)
end

local function init()
    Menus = Menus or {}; table.insert(Menus, menu)
    if Helper then Helper.registerMenu(menu) end
    RegisterEvent("X4GunneryTestLab.TurretMapPosition", onPosition)
    RegisterEvent("X4GunneryTestLab.HoloSize", onSize)
    RegisterEvent("X4GunneryAnchor.Reply", onAnchorReply)
    RegisterEvent("X4GunneryAnchor.GeometryHeader", onGeometryHeader)
    RegisterEvent("X4GunneryAnchor.GeometryShip", function(_, param) geometryComponent("ship", param) end)
    RegisterEvent("X4GunneryAnchor.GeometryTurret", function(_, param) geometryComponent("turret", param) end)
    RegisterEvent("X4GunneryAnchor.GeometryNumber", onGeometryNumber)
    RegisterEvent("X4GunneryAnchor.GeometryEnd", onGeometryEnd)
end

init()
