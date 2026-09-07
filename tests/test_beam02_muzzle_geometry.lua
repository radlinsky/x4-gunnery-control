-- Focused source-oracle regression for Issue #128 rank-1 beam_02 geometry.
-- Expected muzzle positions are rebuilt from the accepted shipped-source
-- constants below, never from the generated record under test.
local eval = dofile("tests/support/muzzle_geometry_eval.lua")
dofile("ui/turret_muzzle_geometry.lua")

-- ARG/PAR/TEL share one downstream muzzle chain (bit-identical ANI).
local macros = {
    "turret_arg_m_beam_02_mk1_macro",
    "turret_par_m_beam_02_mk1_macro",
    "turret_tel_m_beam_02_mk1_macro",
}

local ROTATOR_CONNECTION_Y = 3.464102
local ROTATOR_SETTLED_Y = 2.3680334091186523
local GUN_CONNECTION = { -1.754811e-06, -0.09415483, -5.053287e-04 }
local BARREL_CONNECTION = { -2.474098e-08, -0.7722228, 1.42531 }
-- Stored channel-0 translation; the ANI-to-native boundary flips X.
local BARREL_SETTLED = {
    4.470348358154297e-07,
    1.1920928955078125e-07,
    3.4313702583312988,
}

local endpoints = {
    con_beam_01 = { 2.413219, 2.198219e-04, 1.274742 },
    con_beam_02 = { -2.397867, 2.193451e-04, 1.274741 },
}

local function sourceExpected(endpoint, yaw, pitch)
    local yawOrigin = { 0, ROTATOR_CONNECTION_Y + ROTATOR_SETTLED_Y, 0 }
    local barrelAndEndpoint = eval.add(
        eval.add(BARREL_CONNECTION, BARREL_SETTLED), endpoint)
    local pitched = eval.rotate(eval.axis_rotation("x", -pitch), barrelAndEndpoint)
    local yawLocal = eval.add(GUN_CONNECTION, pitched)
    return eval.add(yawOrigin, eval.rotate(eval.axis_rotation("y", yaw), yawLocal))
end

for _, macro in ipairs(macros) do
    local record = X4GunneryTurretMuzzleGeometry[macro]
    assert(record ~= nil, "missing generated beam_02 record for " .. macro)
    assert(record.semantic_case == "depth4_one_key_barrel_translation",
        macro .. " must reuse depth4_one_key_barrel_translation")
    assert(#record.layers == 4, macro .. " must keep the accepted depth-4 path")
    local expectedConnections = { "Connection01", "Connection03", "Connection04", "Connection05" }
    for index, connection in ipairs(expectedConnections) do
        assert(record.layers[index].owning_connection == connection,
            macro .. " unexpected owning connection at layer " .. index)
    end
    assert(record.layers[2].settled_position[2] == ROTATOR_SETTLED_Y,
        macro .. " lost the accepted rotator settled translation")
    local barrelSettled = record.layers[4].settled_position
    assert(barrelSettled ~= nil, macro .. " lost the barrel settled translation")
    for axis = 1, 3 do
        assert(math.abs(barrelSettled[axis] - BARREL_SETTLED[axis]) <= 1e-9,
            macro .. " barrel settled translation axis " .. axis
            .. " does not match the X-flipped source channel-0 key")
    end

    for _, layer in ipairs(record.layers) do
        assert(layer.settled_rotation_x_radians == nil,
            macro .. " must not emit a settled rotation")
        assert(layer.settled_scale == nil, macro .. " must not emit a settled scale")
    end

    for endpointName, endpoint in pairs(endpoints) do
        for _, yaw in ipairs({ -90, 0, 90 }) do
            for _, pitch in ipairs({ -10, 0, 45, 90 }) do
                local got = eval.evaluate_geometry(record, endpointName, { yaw = yaw, pitch = pitch })
                local want = sourceExpected(endpoint, yaw, pitch)
                for axis = 1, 3 do
                    assert(math.abs(got[axis] - want[axis]) <= 1e-9, string.format(
                        "%s %s source oracle mismatch at yaw=%g pitch=%g axis=%d "
                        .. "(got %.17g want %.17g)",
                        macro, endpointName, yaw, pitch, axis, got[axis], want[axis]))
                end
            end
        end
    end
end

print("beam_02 muzzle geometry tests passed")
