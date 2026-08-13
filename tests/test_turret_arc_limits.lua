-- Generated turret firing-arc metadata contract.

X4GunneryTurretArcLimits = nil
dofile("ui/turret_arc_limits.lua")

assert(type(X4GunneryTurretArcLimits) == "table",
    "turret arc metadata must publish X4GunneryTurretArcLimits")

local count = 0
local distribution = {}
for macro, limits in pairs(X4GunneryTurretArcLimits) do
    count = count + 1
    assert(type(macro) == "string" and macro:match("_macro$"),
        "turret arc key must be a macro identifier: " .. tostring(macro))
    assert(type(limits) == "table" and type(limits[1]) == "number"
            and type(limits[2]) == "number" and limits[1] <= limits[2],
        "invalid pitch interval for " .. macro)
    local interval = tostring(limits[1]) .. "," .. tostring(limits[2])
    distribution[interval] = (distribution[interval] or 0) + 1
end

assert(count == 147, "official X4 9.00 arc table must contain 147 macros, got " .. tostring(count))
local expectedDistribution = {
    ["-45,40"] = 1,
    ["-10,89"] = 41,
    ["-10,90"] = 56,
    ["-9,89"] = 1,
    ["-7,89"] = 9,
    ["-5,80"] = 18,
    ["-5,89"] = 3,
    ["-5,90"] = 15,
    ["-2,89"] = 2,
    ["18,89"] = 1,
}
for interval, expected in pairs(expectedDistribution) do
    assert(distribution[interval] == expected,
        "official X4 9.00 interval " .. interval .. " expected " .. expected
        .. ", got " .. tostring(distribution[interval]))
    distribution[interval] = nil
end
assert(next(distribution) == nil, "official X4 9.00 arc table contains an unexpected interval")
assert(X4GunneryTurretArcLimits.turret_bor_m_railgun_02_mk1_macro[1] == -10,
    "Ray M railgun must preserve its shipped -10 degree depression limit")
assert(X4GunneryTurretArcLimits.turret_bor_l_disruptor_01_mk1_macro[1] == -5,
    "Ray L disruptor must preserve its shipped -5 degree depression limit")

print("turret arc limit tests passed")
