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
assert(map.choose(result, {100, 0, 0}) == result.points[1])
assert(map.choose({points = {}}, {100, 0, 0}) == nil)
local corners = {}
for _, x in ipairs({-60, 60}) do
    for _, y in ipairs({-60, 60}) do
        for _, z in ipairs({-60, 60}) do corners[#corners + 1] = {x, y, z} end
    end
end
for i = 1, 8 do
    for k = 1, 3 do assert(probes[i][k] == corners[i][k]) end
end
local ambiguous = { points = {
    {id = 1, c = {-1, 0, 0}, r = 0.1},
    {id = 2, c = {1, 0, 0}, r = 0.1},
} }
assert(map.choose(ambiguous, {0, 0, 0}) == nil)
assert(map.choose(ambiguous, {-5, 0, 0}) == ambiguous.points[1])
print('aimpoint map: ok')
