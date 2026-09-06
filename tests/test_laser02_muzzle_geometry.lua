-- Focused source-oracle regression for Issue #125 rank-1 laser_02 geometry.
local eval = dofile("tests/support/muzzle_geometry_eval.lua")
dofile("ui/turret_muzzle_geometry.lua")

local cases = {
    {
        macro = "turret_arg_m_laser_02_mk1_macro",
        barrel_connection_z = -0.3393459,
        barrel_settled_z = 3.5189666748046875,
    },
    {
        macro = "turret_par_m_laser_02_mk1_macro",
        barrel_connection_z = -0.3415632,
        barrel_settled_z = 3.521183967590332,
    },
    {
        macro = "turret_tel_m_laser_02_mk1_macro",
        barrel_connection_z = -0.3415632,
        barrel_settled_z = 3.521183967590332,
    },
}

local endpoints = {
    con_laser_01 = { 2.22173, 0.3119164, 4.094663 },
    con_laser_02 = { -2.279301, 0.3119164, 4.094663 },
}

local function sourceExpected(case, endpoint, yaw, pitch)
    local yawOrigin = {
        0,
        2.803713 + 2.962090492248535,
        -7.008049e-08,
    }
    local gunConnection = { 0, 0.2833061, -1.238369e-08 }
    local barrelAndEndpoint = eval.add(
        { 0, -1.025152, case.barrel_connection_z + case.barrel_settled_z },
        endpoint)
    local pitched = eval.rotate(eval.axis_rotation("x", -pitch), barrelAndEndpoint)
    local yawLocal = eval.add(gunConnection, pitched)
    return eval.add(yawOrigin, eval.rotate(eval.axis_rotation("y", yaw), yawLocal))
end

for _, case in ipairs(cases) do
    local record = X4GunneryTurretMuzzleGeometry[case.macro]
    assert(record ~= nil, "missing generated laser_02 record for " .. case.macro)
    assert(record.semantic_case == "depth4_one_key_barrel_translation",
        case.macro .. " must reuse depth4_one_key_barrel_translation")
    assert(#record.layers == 4, case.macro .. " must keep the accepted depth-4 path")
    local expectedConnections = { "Connection01", "Connection02", "Connection03", "Connection04" }
    for index, connection in ipairs(expectedConnections) do
        assert(record.layers[index].owning_connection == connection,
            case.macro .. " unexpected owning connection at layer " .. index)
    end
    assert(record.layers[2].settled_position[2] == 2.962090492248535,
        case.macro .. " lost the accepted rotator settled translation")
    assert(record.layers[4].settled_position[3] == case.barrel_settled_z,
        case.macro .. " lost the source-derived barrel settled translation")

    for endpointName, endpoint in pairs(endpoints) do
        for _, yaw in ipairs({ -90, 0, 90 }) do
            for _, pitch in ipairs({ -10, 0, 45, 90 }) do
                local got = eval.evaluate_geometry(record, endpointName, { yaw = yaw, pitch = pitch })
                local want = sourceExpected(case, endpoint, yaw, pitch)
                for axis = 1, 3 do
                    assert(math.abs(got[axis] - want[axis]) <= 1e-9, string.format(
                        "%s %s source oracle mismatch at yaw=%g pitch=%g axis=%d "
                        .. "(got %.17g want %.17g)",
                        case.macro, endpointName, yaw, pitch, axis, got[axis], want[axis]))
                end
            end
        end
    end
end

print("laser_02 muzzle geometry tests passed")
