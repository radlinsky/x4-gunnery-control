-- The production search shares one budget across fixed, confirmation and
-- adaptive probes, then returns a stable point identity and uncertainty.
dofile('ui/aimpoint_map.lua')
local map = X4GunneryAimPointMap
local probes = {}
local result = map.search({0, 0, 0}, {10, 10, 10}, function(_, p)
    probes[#probes + 1] = p
    local length = math.sqrt(p[1]^2 + p[2]^2 + p[3]^2)
    return {-p[1] / length, -p[2] / length, -p[3] / length}
end)
assert(#probes == result.samples and result.samples <= 40)
assert(#result.points == 1 and result.points[1].id == 1)
assert(result.points[1].r > 0)
-- The resumable path must request exactly the same probes and return the same map.
local resume = map.begin({0, 0, 0}, {10, 10, 10})
local answer
for i = 1, #probes do
    local completed, probe = resume(answer)
    assert(completed == nil and probe.n == i)
    for k = 1, 3 do assert(probe.p[k] == probes[i][k]) end
    local p = probe.p
    local length = math.sqrt(p[1]^2 + p[2]^2 + p[3]^2)
    answer = {-p[1] / length, -p[2] / length, -p[3] / length}
end
local resumed, extra = resume(answer)
assert(extra == nil and resumed.samples == result.samples and resumed.stop == result.stop)
assert(#resumed.points == #result.points)
for i, point in ipairs(result.points) do
    local other = resumed.points[i]
    assert(other.id == point.id and other.r == point.r)
    for k = 1, 3 do assert(other.c[k] == point.c[k]) end
end
local corners = {}
for _, x in ipairs({-60, 60}) do
    for _, y in ipairs({-60, 60}) do
        for _, z in ipairs({-60, 60}) do corners[#corners + 1] = {x, y, z} end
    end
end
for i = 1, 8 do
    for k = 1, 3 do assert(probes[i][k] == corners[i][k]) end
end
print('aimpoint map: ok')
