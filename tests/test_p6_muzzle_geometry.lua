-- Focused source-oracle regression for Issue #132 rank-1 P6 geometry.
-- Expected positions are rebuilt from A1's accepted shipped-source constants.
local eval = dofile("tests/support/muzzle_geometry_eval.lua")
dofile("ui/turret_muzzle_geometry.lua")

local macros = {
    "turret_pir_l_battleship_01_laser_01_mk1_macro",
    "turret_tel_l_laser_01_mk1_macro",
}

local ROTATOR_CONNECTION = { -0.0244168, 17.52643, -0.1001702 }
local GUN_CONNECTION = { 2.980232e-8, -0.02269363, -5.565336 }
local BARREL_CONNECTION = { -4.023314e-6, 0.1448975, 11.62085 }
local BARREL_SETTLED = { 0, -1.9072999748459551e-6, 0 }
local endpoints = {
    con_laser_01 = { 4.560871, -0.1317711, 23.71955 },
    con_laser_02 = { -4.823473, -0.001207352, 23.71955 },
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

for _, macro in ipairs(macros) do
    local record = X4GunneryTurretMuzzleGeometry[macro]
    assert(record ~= nil, "missing generated P6 record for " .. macro)
    assert(record.semantic_case == "depth4_p6_translation",
        macro .. " must use the bounded P6 semantic case")
    assert(#record.layers == 4, macro .. " must keep the accepted depth-4 path")
    assert(record.layers[3].settled_position[1] == 0
        and record.layers[3].settled_position[2] == 0
        and record.layers[3].settled_position[3] == 0,
        macro .. " must retain the exact zero gun translation")
    for axis = 1, 3 do
        assert(record.layers[4].settled_position[axis] == BARREL_SETTLED[axis],
            macro .. " barrel settled translation does not match A1")
    end
    for _, layer in ipairs(record.layers) do
        assert(layer.settled_rotation_x_radians == nil,
            macro .. " must not emit a settled rotation")
        assert(layer.settled_scale == nil,
            macro .. " must not emit a settled scale")
    end

    for endpointName, endpoint in pairs(endpoints) do
        for _, yaw in ipairs({ -90, 0, 90 }) do
            for _, pitch in ipairs({ -5, 0, 45, 90 }) do
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
end

print("P6 muzzle geometry tests passed")
