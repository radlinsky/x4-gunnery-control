-- Focused source-oracle regression for Issue #135 rank-1 P8 geometry.
-- Expected positions are rebuilt from A1's accepted shipped-source constants.
local eval = dofile("tests/support/muzzle_geometry_eval.lua")
dofile("ui/turret_muzzle_geometry.lua")

local macro = "turret_ter_l_beam_01_mk1_macro"

local ROTATOR_CONNECTION = { 0, 8.5, 0 }
local GUN_CONNECTION = { 0, 2.064657, -6.057116 }
local BARREL_CONNECTION = { 0, 0.6179247, 45.60182 }
local BARREL_SETTLED = { 0, 0, 3.8145999496919103e-06 }
local endpoints = {
    con_laser_01 = { 2.003361, 0.00462532, 17.78848 },
    con_laser_02 = { -2.000694, 0.135191, 17.78848 },
}

local function sourceExpected(endpoint, yaw, pitch)
    local downstream = eval.add(
        BARREL_CONNECTION, eval.add(BARREL_SETTLED, endpoint))
    local pitched = eval.rotate(eval.axis_rotation("x", -pitch), downstream)
    local yawLocal = eval.add(GUN_CONNECTION, pitched)
    return eval.add(
        ROTATOR_CONNECTION,
        eval.rotate(eval.axis_rotation("y", yaw), yawLocal))
end

local record = X4GunneryTurretMuzzleGeometry[macro]
assert(record ~= nil, "missing generated P8 record for " .. macro)
assert(record.semantic_case == "depth4_p8_translation",
    macro .. " must use the bounded P8 semantic case")
assert(#record.layers == 4, macro .. " must keep the accepted depth-4 path")
for axis = 1, 3 do
    assert(record.layers[2].settled_position[axis] == 0,
        macro .. " must retain the exact zero rotator translation")
    assert(record.layers[4].settled_position[axis] == BARREL_SETTLED[axis],
        macro .. " barrel settled translation does not match A1")
end
assert(record.layers[3].settled_position == nil,
    macro .. " must not emit a gun translation")
for _, layer in ipairs(record.layers) do
    assert(layer.settled_rotation_x_radians == nil,
        macro .. " must not emit a settled rotation")
    assert(layer.settled_scale == nil,
        macro .. " must not emit a settled scale")
end

for endpointName, endpoint in pairs(endpoints) do
    for _, yaw in ipairs({ -90, 0, 90 }) do
        for _, pitch in ipairs({ -5, 0, 45, 80 }) do
            local got = eval.evaluate_geometry(
                record, endpointName, { yaw = yaw, pitch = pitch })
            local want = sourceExpected(endpoint, yaw, pitch)
            for axis = 1, 3 do
                assert(math.abs(got[axis] - want[axis]) <= 1e-9,
                    string.format(
                        "%s %s mismatch yaw=%g pitch=%g axis=%d",
                        macro, endpointName, yaw, pitch, axis))
            end
        end
    end
end

print("P8 muzzle geometry tests passed")
