-- Shared #184 near-target aim-point map. Coordinates are target-local metres.
-- Search placement and stopping depend only on target geometry and X4 probes.
local AIM_TOTAL, AIM_PAD, AIM_PAD_Y = 40, 50, 8.86
local AIM_U = 2 ^ -24
local AIM_EPS, AIM_MISS = 2.2e-4, 5e-5
local AIM_MIN_ANGLE = 2 * (2 ^ -18 / math.sqrt(2) + 8 * AIM_U) / 0.01
local AIM_REL, AIM_FORWARD = 0.05, 31.5 * AIM_EPS
local AIM_SLACK = 2 * (AIM_EPS + 1e-6) / AIM_FORWARD
local AIM_ALPHA0, AIM_ALPHA_MIN = math.rad(2), math.rad(1 / 64)
local AIM_AXES = { { 2, 3 }, { 1, 3 }, { 1, 2 } }
local AIM_CAPPED = {}

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

local function aimRho(...)
    local m = 1
    for i = 1, select("#", ...) do
        local p = select(i, ...)
        for k = 1, 3 do m = math.max(m, math.abs(p[k])) end
    end
    return 2 * AIM_U * m + AIM_MISS
end

-- (depth along ray (u, d), depth error bound) where ray (v, e) crosses it, or nil.
local function aimCrossing(u, d, v, e)
    local c, k = vDot(d, e), vNorm(vCross(d, e))
    if k < AIM_MIN_ANGLE then return nil end
    local w = vSub(u, v)
    local ew, dw = vDot(e, w), vDot(d, w)
    local s, t = (c * ew - dw) / (k * k), (ew - c * dw) / (k * k)
    local x = vAdd(u, vMul(d, s))
    local miss = 2 * aimRho(u, v, x) + AIM_EPS * (math.abs(s) + math.abs(t))
    if s <= 0 or t <= 0 or vNorm(vSub(vSub(x, v), vMul(e, t))) > miss
            or miss / k > AIM_REL * math.max(s, t) then
        return nil
    end
    return s, miss / k
end

local function aimOnRay(u, d, c, r)
    local t = vDot(vSub(c, u), d)
    return t > 0 and vNorm(vSub(vSub(c, u), vMul(d, t))) <= r + AIM_EPS * (t + r) + aimRho(u, c)
end

local function aimBasis(d)
    local i = 1
    for k = 2, 3 do if math.abs(d[k]) < math.abs(d[i]) then i = k end end
    local e = { 0, 0, 0 }
    e[i] = 1
    local a = vCross(d, e)
    a = vUnit(a, vNorm(a))
    return a, vCross(d, a)
end

local function aimLinspace(a, b, count)
    local out, div = {}, count - 1
    local step = (b - a) / div
    for i = 0, count - 1 do
        out[i + 1] = step == 0 and (i / div) * (b - a) + a or i * step + a
    end
    out[count] = b
    return out
end

local function search(C, H, askX4)
    local n, stop = 0, nil
    local points, tried, hits = {}, {}, {}
    local rays = { order = {}, map = {} }
    local seen = { n = 0 }
    local tlo, thi = vSub(C, H), vAdd(vAdd(C, H), { 0, AIM_PAD_Y, 0 })
    local plo = { C[1] - H[1] - AIM_PAD, C[2] - H[2] - AIM_PAD, C[3] - H[3] - AIM_PAD }
    local phi = { C[1] + H[1] + AIM_PAD, C[2] + H[2] + AIM_PAD, C[3] + H[3] + AIM_PAD }

    local function ask(p, kind)
        if n >= AIM_TOTAL then error(AIM_CAPPED, 0) end
        n = n + 1
        return askX4(n, p, kind)
    end
    local function spend(k) return n + k <= AIM_TOTAL end
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
            if aimOnRay(u, d, point.c, point.r) then
                if only then return nil end
                only = i
            end
        end
        return only
    end
    local function rayOwner(key) return owner(rays.map[key].u, rays.map[key].d) end

    local function confirm(u, d, s, err)
        local near = s / (1 + 1.5 * AIM_SLACK) - 2 * err
        if near <= 0 then return false end
        local a = ask(vAdd(u, vMul(d, near)), "confirmation")
        local b = ask(vAdd(u, vMul(d, s + 2 * err)), "confirmation")
        return a ~= nil and vDot(a, d) > 0 and vNorm(vCross(a, d)) <= AIM_FORWARD
            and (b == nil or vDot(b, d) <= 0 or vNorm(vCross(b, d)) > AIM_FORWARD)
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
                    local s, err = aimCrossing(free[ka].u, free[ka].d, free[kb].u, free[kb].d)
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
                local r = f.width / 2 + AIM_EPS * f.s + aimRho(ray.u, x)
                local apart = true
                for _, point in ipairs(points) do
                    if not (vNorm(vSub(point.c, x)) > point.r + r) then apart = false; break end
                end
                if vInside(tlo, thi, x, r) and apart and confirm(ray.u, ray.d, f.s, f.width / 2) then
                    points[#points + 1] = { c = x, r = r }
                end
            end
        end
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
                local st = state[anchors[1]] or { AIM_ALPHA0, 0 }
                local alpha, turn = st[1], st[2]
                if alpha < AIM_ALPHA_MIN then
                    table.remove(anchors, 1)
                else
                    local a, b = aimBasis(ray.d)
                    local side = vAdd(vMul(a, math.cos(turn * math.pi / 3)), vMul(b, math.sin(turn * math.pi / 3)))
                    local v = vAdd(ray.u, vMul(side, boxDepth(ray.u, ray.d) * math.tan(alpha)))
                    local d = ask(v, "moved")
                    addRay(v, d)
                    local s = d and aimCrossing(ray.u, ray.d, v, d)
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
            local ax, best = AIM_AXES[k], nil
            local ss, ts = aimLinspace(win[1][1], win[1][2], 9), aimLinspace(win[2][1], win[2][2], 9)
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
            local ax = AIM_AXES[k]
            for _, side in ipairs({ plo[k], phi[k] }) do
                local face = scan(k, side, { { plo[ax[1]], phi[ax[1]] }, { plo[ax[2]], phi[ax[2]] } })
                if face.gap >= 0 and (not best or face.gap > best.gap) then best = face end
            end
        end
        if not best then return nil end
        local ax = AIM_AXES[best.k]
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
            if n + 1 > AIM_TOTAL then break end
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
        if err ~= AIM_CAPPED then error(err, 0) end
        stop = "hard cap"
    end

    -- Refinement: tighten each point from rays already collected; no samples.
    local refined = {}
    for i, point in ipairs(points) do
        local own, best = {}, nil
        for _, key in ipairs(rays.order) do
            local ray, count = rays.map[key], 0
            if ray.d and aimOnRay(ray.u, ray.d, point.c, point.r) then
                for _, other in ipairs(points) do
                    if aimOnRay(ray.u, ray.d, other.c, other.r) then count = count + 1 end
                end
                if count == 1 then own[#own + 1] = ray end
            end
        end
        for a = 1, #own do
            for b = 1, #own do
                local s, err2 = nil, nil
                if a ~= b then s, err2 = aimCrossing(own[a].u, own[a].d, own[b].u, own[b].d) end
                if s then
                    local x = vAdd(own[a].u, vMul(own[a].d, s))
                    local r = err2 + AIM_EPS * s + aimRho(own[a].u, x)
                    if not best or r < best.r then best = { c = x, r = r } end
                end
            end
        end
        local accept = #own >= 2 and best ~= nil and best.r < point.r
            and vNorm(vSub(best.c, point.c)) + best.r <= point.r
        for _, ray in ipairs(accept and own or {}) do
            if not aimOnRay(ray.u, ray.d, best.c, best.r) then accept = false; break end
        end
        refined[i] = accept and { id = i, c = best.c, r = best.r }
            or { id = i, c = point.c, r = point.r }
    end
    return { samples = n, stop = stop, points = refined }
end

-- A later position is definite only when one recovered uncertainty ball is
-- strictly closer than every other ball. A missing map is UNKNOWN.
local function choose(result, position)
    if not result or #result.points == 0 then return nil end
    local winner, nearest = nil, math.huge
    for i, point in ipairs(result.points) do
        local distance = vNorm(vSub(position, point.c))
        if distance - point.r < nearest then
            winner, nearest = i, distance - point.r
        end
    end
    local chosen = result.points[winner]
    local far = vNorm(vSub(position, chosen.c)) + chosen.r
    for i, point in ipairs(result.points) do
        if i ~= winner and vNorm(vSub(position, point.c)) - point.r <= far then return nil end
    end
    return chosen
end

X4GunneryAimPointMap = { search = search, choose = choose }
