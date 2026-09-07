-- Focused source-oracle regression for Issue #130 Xenon rank-1 geometry.
-- Expected muzzle positions are rebuilt from the accepted shipped-source
-- constants below, never from the generated record under test.
local eval = dofile("tests/support/muzzle_geometry_eval.lua")
dofile("ui/turret_muzzle_geometry.lua")

-- Both aliases are backed by the one component turret_xen_m_laser_02_mk1, so
-- they must carry bit-identical geometry.
local macros = {
    "turret_xen_m_beam_02_mk1_macro",
    "turret_xen_m_laser_02_mk1_macro",
}

local ROTATOR_CONNECTION = { 0, 2.803713, -7.008049e-08 }
local ROTATOR_SETTLED = { 0, 2.962090492248535, 0 }
local GUN_CONNECTION = { 0, 0.2833061, -1.238369e-08 }
local BARREL_CONNECTION = { 0, -1.025152, -4.286385e-02 }
local BARREL_SETTLED = { 0, 0, 3.222484588623047 }

local endpoints = {
    con_laser_01 = { 2.22173, 0.3119164, 4.094663 },
    con_laser_02 = { -2.279301, 0.3119164, 4.094663 },
}

local function sourceExpected(endpoint, yaw, pitch)
    local yawOrigin = eval.add(ROTATOR_CONNECTION, ROTATOR_SETTLED)
    local barrelAndEndpoint = eval.add(
        eval.add(BARREL_CONNECTION, BARREL_SETTLED), endpoint)
    local pitched = eval.rotate(eval.axis_rotation("x", -pitch), barrelAndEndpoint)
    local yawLocal = eval.add(GUN_CONNECTION, pitched)
    return eval.add(yawOrigin, eval.rotate(eval.axis_rotation("y", yaw), yawLocal))
end

for _, macro in ipairs(macros) do
    local record = X4GunneryTurretMuzzleGeometry[macro]
    assert(record ~= nil, "missing generated Xenon record for " .. macro)
    assert(record.semantic_case == "depth4_one_key_barrel_translation",
        macro .. " must reuse depth4_one_key_barrel_translation")
    assert(#record.layers == 4, macro .. " must keep the accepted depth-4 path")
    local expectedConnections = { "Connection01", "Connection03", "Connection04", "Connection05" }
    for index, connection in ipairs(expectedConnections) do
        assert(record.layers[index].owning_connection == connection,
            macro .. " unexpected owning connection at layer " .. index)
    end
    -- Stored source values: exact match, no tolerance.
    for axis = 1, 3 do
        assert(record.layers[2].settled_position[axis] == ROTATOR_SETTLED[axis],
            macro .. " rotator settled translation axis " .. axis
            .. " does not match the source channel-0 key")
        assert(record.layers[4].settled_position[axis] == BARREL_SETTLED[axis],
            macro .. " barrel settled translation axis " .. axis
            .. " does not match the source one-key channel-0 key")
    end
    assert(record.layers[3].runtime_rotation.minimum_degrees == -10,
        macro .. " lost the authored pitch minimum")
    assert(record.layers[3].runtime_rotation.maximum_degrees == 90,
        macro .. " lost the authored pitch maximum")

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

print("Xenon laser_02 muzzle geometry tests passed")
