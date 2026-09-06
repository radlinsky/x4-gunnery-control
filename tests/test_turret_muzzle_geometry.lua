local function fail(message)
  error(message, 2)
end

local function add(left, right)
  return {
    left[1] + right[1],
    left[2] + right[2],
    left[3] + right[3],
  }
end

local function rotate(rotation, vector)
  local x, y, z, w = rotation[1], rotation[2], rotation[3], rotation[4]
  local vx, vy, vz = vector[1], vector[2], vector[3]
  local tx = 2 * (y * vz - z * vy)
  local ty = 2 * (z * vx - x * vz)
  local tz = 2 * (x * vy - y * vx)
  return {
    vx + w * tx + y * tz - z * ty,
    vy + w * ty + z * tx - x * tz,
    vz + w * tz + x * ty - y * tx,
  }
end

local function axis_rotation(axis, degrees)
  local radians = math.rad(degrees) / 2
  local sine = math.sin(radians)
  if axis == "x" then
    return { sine, 0, 0, math.cos(radians) }
  elseif axis == "y" then
    return { 0, sine, 0, math.cos(radians) }
  end
  fail("unsupported rotation axis " .. tostring(axis))
end

local function axis_rotation_radians(axis, radians)
  return axis_rotation(axis, math.deg(radians))
end

local function rotate_in_frame(rotations, vector)
  for index = #rotations, 1, -1 do
    vector = rotate(rotations[index], vector)
  end
  return vector
end

local function apply_transform(position, rotations, transform)
  position = add(position, rotate_in_frame(rotations, transform.position))
  rotations[#rotations + 1] = transform.quaternion
  return position
end

local function evaluate_geometry(geometry, endpoint_connection, pose)
  local position = { 0, 0, 0 }
  local rotations = {}

  for _, layer in ipairs(geometry.layers) do
    position = add(position,
      rotate_in_frame(rotations, layer.connection_transform.position))
    if layer.settled_position then
      position = add(position,
        rotate_in_frame(rotations, layer.settled_position))
    end
    if layer.runtime_rotation then
      local axis = layer.runtime_rotation.axis
      local degrees = axis == "x" and -pose.pitch or pose.yaw
      rotations[#rotations + 1] = axis_rotation(axis, degrees)
    end
    rotations[#rotations + 1] = layer.connection_transform.quaternion
    position = apply_transform(position, rotations, layer.part_transform)
  end

  for _, endpoint in ipairs(geometry.endpoints) do
    if endpoint.connection == endpoint_connection then
      return apply_transform(position, rotations, endpoint.transform)
    end
  end
  fail("missing endpoint " .. endpoint_connection)
end

-- Independent oracle: the accepted production O + Ry(yaw) *
-- (P + Rx(-pitch) * D) construction recorded in census_anchor_evidence.py.
local function evaluate_production_oracle(yaw, pitch)
  local yaw_origin = add(
    { 1.877547e-6, 2.018104, -1.043081e-5 },
    { 0, 6.145042419433594, 0 }
  )
  local pivot = { -1.730653e-6, 2.926126, -16.11956 }
  local downstream = {
    -0.36177411330546533,
    0.4829345992763463,
    55.87084740617998,
  }
  local pitched = rotate(axis_rotation("x", -pitch), downstream)
  return add(yaw_origin, rotate(axis_rotation("y", yaw), add(pivot, pitched)))
end

X4GunneryTurretMuzzleGeometry = nil
assert(loadfile("ui/turret_muzzle_geometry.lua"))()

local expected_macros = {
  turret_par_l_beam_01_mk1_macro = true,
  turret_par_m_laser_01_mk1_macro = true,
  turret_par_l_laser_01_mk1_macro = true,
  turret_par_l_plasma_01_mk1_macro = true,
  turret_par_m_beam_01_mk1_macro = true,
  turret_par_m_plasma_01_mk1_macro = true,
  turret_tel_m_beam_01_mk1_macro = true,
  turret_tel_m_laser_01_mk1_macro = true,
  turret_tel_m_plasma_01_mk1_macro = true,
  turret_ter_m_laser_01_mk1_macro = true,
}
local macro_count = 0
for name in pairs(X4GunneryTurretMuzzleGeometry) do
  macro_count = macro_count + 1
  if not expected_macros[name] then
    fail("unexpected generated macro key " .. tostring(name))
  end
end
if macro_count ~= 10 then
  fail("expected exactly ten generated macro records, got " .. macro_count)
end
local expected_macro = "turret_par_l_beam_01_mk1_macro"

local geometry = X4GunneryTurretMuzzleGeometry[expected_macro]
local tolerance = 1e-9
for _, yaw in ipairs({ -90, 0, 90 }) do
  for _, pitch in ipairs({ -5, 30, 80 }) do
    local actual = evaluate_geometry(geometry, "con_laser_02", {
      yaw = yaw,
      pitch = pitch,
    })
    local expected = evaluate_production_oracle(yaw, pitch)
    for axis = 1, 3 do
      local difference = math.abs(actual[axis] - expected[axis])
      if difference > tolerance then
        fail(string.format(
          "yaw=%g pitch=%g axis=%d differs by %.17g (actual %.17g, expected %.17g)",
          yaw, pitch, axis, difference, actual[axis], expected[axis]
        ))
      end
    end
  end
end

-- depth5_additive_x_rotation composition (issue #83 accepted rule):
-- C_i, then P_i, then the additive settled local-X rotation, then the
-- layer's live rotation. Yaw/pitch come from the projectile bore.
local function evaluate_depth5(geometry, endpoint_connection, yaw, pitch)
  local position = { 0, 0, 0 }
  local rotations = {}
  for _, layer in ipairs(geometry.layers) do
    position = apply_transform(position, rotations, layer.connection_transform)
    position = apply_transform(position, rotations, layer.part_transform)
    if layer.settled_position then
      position = add(position,
        rotate_in_frame(rotations, layer.settled_position))
    end
    if layer.settled_rotation_x_radians then
      rotations[#rotations + 1] =
        axis_rotation_radians("x", layer.settled_rotation_x_radians)
    end
    if layer.runtime_rotation then
      local axis = layer.runtime_rotation.axis
      rotations[#rotations + 1] =
        axis_rotation_radians(axis, axis == "x" and -pitch or yaw)
    end
  end
  for _, endpoint in ipairs(geometry.endpoints) do
    if endpoint.connection == endpoint_connection then
      return add(position, rotate_in_frame(rotations, endpoint.transform.position))
    end
  end
  fail("missing endpoint " .. endpoint_connection)
end

-- Accepted issue #83 nine-pose live witnesses; never fitted, never derived.
local laser_poses = {
  { "center", 0, 0.747567, -0.313826, 5.19057, 2.90662 },
  { "yaw right", 0.592892, 0.736931, 1.66678, 5.14855, 2.53582 },
  { "yaw left", -0.592892, 0.736930, -2.1873, 5.14855, 2.18511 },
  { "pitch low", 0, 0.363425, -0.313826, 3.42557, 4.12367 },
  { "pitch high", 0, 1.12376, -0.313826, 6.35365, 1.15801 },
  { "right low", 0.578989, 0.357808, 2.27399, 3.39663, 3.55235 },
  { "right high", 0.636900, 1.10904, 0.778724, 6.32098, 1.08071 },
  { "left low", -0.578989, 0.357808, -2.79934, 3.39663, 3.20892 },
  { "left high", -0.636900, 1.10904, -1.28332, 6.32098, 0.707438 },
}

local laser = X4GunneryTurretMuzzleGeometry["turret_par_m_laser_01_mk1_macro"]
if laser.semantic_case ~= "depth5_additive_x_rotation" then
  fail("unexpected M Laser semantic case " .. tostring(laser.semantic_case))
end
for _, pose in ipairs(laser_poses) do
  local name, yaw, pitch = pose[1], pose[2], pose[3]
  local actual = evaluate_depth5(laser, "con_laser_02", yaw, pitch)
  local error_squared = 0
  for axis = 1, 3 do
    local difference = actual[axis] - pose[axis + 3]
    error_squared = error_squared + difference * difference
  end
  local distance = math.sqrt(error_squared)
  if distance > 2e-5 then
    fail(string.format(
      "M Laser pose %s off by %.9g m (%.9g, %.9g, %.9g)",
      name, distance, actual[1], actual[2], actual[3]
    ))
  end
end

-- Determinism: identical inputs must give bit-identical output.
for _, pose in ipairs(laser_poses) do
  local first = evaluate_depth5(laser, "con_laser_02", pose[2], pose[3])
  local second = evaluate_depth5(laser, "con_laser_02", pose[2], pose[3])
  for axis = 1, 3 do
    if first[axis] ~= second[axis] then
      fail("M Laser evaluation is not deterministic at pose " .. pose[1])
    end
  end
end

-- The remaining Paranid L records use the same accepted depth-4 composition
-- as the Beam. Build the expected result directly from the accepted source
-- transforms and each authored endpoint, rather than from generated fields.
local function evaluate_depth4_source_oracle(endpoint_position, yaw, pitch)
  local yaw_origin = add(
    { 1.877547e-6, 2.018104, -1.043081e-5 },
    { 0, 6.145042419433594, 0 }
  )
  local pivot = { -1.730653e-6, 2.926126, -16.11956 }
  local gun_rotation = {
    -0.004327158, 3.273904e-12, -7.565876e-10, 0.9999906,
  }
  local barrel_connection = { -1.113896e-6, 0.06259775, 17.45395 }
  local barrel_settled = { 0, -0.23982000350952148, 27.710205078125 }
  local barrel_rotation = {
    0.004327045, -6.547686e-12, 2.825544e-14, 0.9999906,
  }
  local downstream = rotate(gun_rotation, add(
    barrel_connection,
    add(barrel_settled, rotate(barrel_rotation, endpoint_position))
  ))
  local pitched = rotate(axis_rotation("x", -pitch), downstream)
  return add(yaw_origin, rotate(axis_rotation("y", yaw), add(pivot, pitched)))
end

local depth4_cases = {
  {
    macro = "turret_par_l_laser_01_mk1_macro",
    endpoints = {
      { "con_laser_01", { 2.039967, 0.2692852, 16.88073 } },
      { "con_laser_02", { -2.063906, 0.3998489, 16.88074 } },
    },
  },
  {
    macro = "turret_par_l_plasma_01_mk1_macro",
    endpoints = {
      { "con_laser_01", { 0.5374919, 0.2692828, 28.04837 } },
      { "con_laser_02", { -0.5369991, 0.2692828, 28.04837 } },
    },
  },
}

for _, depth4_case in ipairs(depth4_cases) do
  local depth4_geometry = X4GunneryTurretMuzzleGeometry[depth4_case.macro]
  if depth4_geometry.semantic_case ~= "depth4_dual_translation" then
    fail("unexpected depth-4 semantic case for " .. depth4_case.macro)
  end
  for _, endpoint in ipairs(depth4_case.endpoints) do
    for _, yaw in ipairs({ -90, 0, 90 }) do
      for _, pitch in ipairs({ -5, 30, 80 }) do
        local actual = evaluate_geometry(depth4_geometry, endpoint[1], {
          yaw = yaw,
          pitch = pitch,
        })
        local expected = evaluate_depth4_source_oracle(endpoint[2], yaw, pitch)
        for axis = 1, 3 do
          local difference = math.abs(actual[axis] - expected[axis])
          if difference > tolerance then
            fail(string.format(
              "%s %s yaw=%g pitch=%g axis=%d differs by %.17g",
              depth4_case.macro, endpoint[1], yaw, pitch, axis, difference
            ))
          end
        end
      end
    end
  end
end

-- The remaining six rank-2 records reconstructed from the accepted source
-- transforms in turret-rank2-settled-active-transform.md and the Teladi
-- channel-0 vector in turret-rank2-teladi-channel0-resolution.md. Nothing here
-- is read from ui/turret_muzzle_geometry.lua.
local alpha = 0.6108652353286743
local teladi_channel0 = {
  -4.6193599700927734e-7,
  8.195638656616211e-8,
  -2.7567148208618164e-7,
}
local identity_quaternion = { 0, 0, 0, 1 }

-- Shared upstream authored transforms, per family.
local rank2_upstream = {
  paranid = {
    { position = { 0, -1.991911, 2.638335 }, quaternion = identity_quaternion },
    {
      position = { 0, -0.008089185, 0 },
      quaternion = identity_quaternion,
      settled_rotation_x = alpha,
    },
    {
      position = { 0, 0.003018975, -3.745065 },
      quaternion = { 0.3007058, 0, 0, -0.953717 },
      offset = { 0, 5.96e-8, -1.192e-7 },
      settled_rotation_x = -alpha,
    },
  },
  teladi = {
    { position = { 0, -1.999982, -0.0001986027 }, quaternion = identity_quaternion },
    {
      position = { 0, -1.80006e-5, 2.669387 },
      quaternion = { 5.96e-8, 0, 0, -1 },
      settled_rotation_x = alpha,
    },
    {
      position = { 0, 0.003018746, -3.745065 },
      quaternion = { -5.96e-8, 0, 0, -1 },
      offset = { 0, 1.192e-7, 0 },
      settled_position = teladi_channel0,
      settled_rotation_x = -alpha,
    },
  },
  terran = {
    { position = { 0, -1.991911, -0.2152019 }, quaternion = identity_quaternion },
    {
      position = { 0, -0.008089185, 2.853536 },
      quaternion = identity_quaternion,
      settled_rotation_x = alpha,
    },
    {
      position = { 0, 0.003018975, -3.745065 },
      quaternion = { 0.3007058, 0, 0, -0.953717 },
      offset = { 0, 5.96e-8, -1.192e-7 },
      settled_rotation_x = -alpha,
    },
  },
}

local function evaluate_rank2_source_oracle(record, endpoint_position, yaw, pitch)
  local position = { 0, 0, 0 }
  local rotations = {}
  local layers = {}
  for _, upstream in ipairs(rank2_upstream[record.family]) do
    layers[#layers + 1] = upstream
  end
  layers[#layers + 1] = record.rotator
  layers[#layers + 1] = record.gun
  for index, layer in ipairs(layers) do
    position = add(position, rotate_in_frame(rotations, layer.position))
    rotations[#rotations + 1] = layer.quaternion
    if layer.offset then
      position = add(position, rotate_in_frame(rotations, layer.offset))
    end
    if layer.settled_position then
      position = add(position, rotate_in_frame(rotations, layer.settled_position))
    end
    if layer.settled_rotation_x then
      rotations[#rotations + 1] =
        axis_rotation_radians("x", layer.settled_rotation_x)
    end
    if index == 4 then
      rotations[#rotations + 1] = axis_rotation_radians("y", yaw)
    elseif index == 5 then
      rotations[#rotations + 1] = axis_rotation_radians("x", -pitch)
    end
  end
  return add(position, rotate_in_frame(rotations, endpoint_position))
end

local rank2_cases = {
  {
    macro = "turret_par_m_beam_01_mk1_macro",
    family = "paranid",
    rotator = {
      position = { 5.48e-8, 2.384e-7, -4.172e-7 },
      quaternion = { -0.3007058, 0, 0, -0.953717 },
    },
    gun = {
      position = { -2.32e-8, 1.028346, -0.4325762 },
      quaternion = identity_quaternion,
    },
    endpoints = {
      { "con_beam_01", { 0.2306155, -0.1077832, 2.274507 } },
      { "con_beam_02", { -0.2306155, -0.1077832, 2.274507 } },
    },
  },
  {
    macro = "turret_par_m_plasma_01_mk1_macro",
    family = "paranid",
    rotator = {
      position = { 0, 0.8191521, 0.5735763 },
      quaternion = { -0.3007058, 0, 0, -0.953717 },
    },
    gun = {
      position = { -8.42e-8, 0.05871224, -0.8014987 },
      quaternion = { 1.808e-7, -2.3e-9, 0, -1 },
      offset = { 0, -2.54e-8, 0 },
    },
    endpoints = {
      { "con_standard_01", { -0.413957, -0.05976738, 2.289655 } },
      { "con_standard_02", { 0.4139574, -0.05976691, 2.289655 } },
    },
  },
  {
    macro = "turret_tel_m_beam_01_mk1_macro",
    family = "teladi",
    rotator = {
      position = { 5.066e-7, 1.113813, -0.4385716 },
      quaternion = identity_quaternion,
    },
    gun = {
      position = { -9.537e-7, 0.3985944, -0.0718013 },
      quaternion = identity_quaternion,
      offset = { 0, 2.98e-8, 2.384e-7 },
    },
    endpoints = {
      { "con_beam_01", { 0.7378538, 0.05214825, 2.724045 } },
      { "con_beam_02", { -0.7411804, 0.05214825, 2.724045 } },
    },
  },
  {
    macro = "turret_tel_m_laser_01_mk1_macro",
    family = "teladi",
    rotator = {
      position = { -4.619e-7, 0.504442, -0.03085339 },
      quaternion = identity_quaternion,
      offset = { 0, 1.192e-7, 1.192e-7 },
    },
    gun = {
      position = { -0.2250015, 0.9301549, -0.001182318 },
      quaternion = identity_quaternion,
      offset = { 0, 0, -1.192e-7 },
    },
    endpoints = {
      { "con_laser_01", { 0.8107684, 0.01269937, 5.323081 } },
      { "con_laser_02", { -0.360766, 0.01269937, 5.323081 } },
    },
  },
  {
    macro = "turret_tel_m_plasma_01_mk1_macro",
    family = "teladi",
    rotator = {
      position = { -4.619e-7, 0.5087894, -0.03085339 },
      quaternion = identity_quaternion,
      offset = { 0, 2.384e-7, 2.384e-7 },
    },
    gun = {
      position = { 0, 0.6530152, -0.4986504 },
      quaternion = identity_quaternion,
      offset = { 0, -1.788e-7, 1.192e-7 },
    },
    endpoints = {
      { "con_standard_01", { -0.5150182, 0.314377, 2.313589 } },
      { "con_standard_02", { 0.5162557, 0.314377, 2.313589 } },
    },
  },
  {
    macro = "turret_ter_m_laser_01_mk1_macro",
    family = "terran",
    rotator = {
      position = { 0, 1.039598, 0.6400551 },
      quaternion = { -0.3007058, 0, 0, -0.953717 },
      offset = { 0, -5.96e-8, -1.192e-7 },
    },
    gun = {
      position = { -0.2250015, -0.1942234, -1.192e-7 },
      quaternion = identity_quaternion,
      offset = { -1.49e-8, 5.96e-8, 3.576e-7 },
    },
    endpoints = {
      { "con_laser_01", { 0.7535628, 0.1360996, 6.793119 } },
      { "con_laser_02", { -0.3611313, 0.1360996, 6.793119 } },
    },
  },
}

-- Loose enough to absorb the sub-micrometre authored part offsets the
-- reference tables record as "none"; far tighter than any real difference.
local rank2_tolerance = 1e-7
for _, rank2_case in ipairs(rank2_cases) do
  local record = X4GunneryTurretMuzzleGeometry[rank2_case.macro]
  if record.semantic_case ~= "depth5_additive_x_rotation" then
    fail("unexpected rank-2 semantic case for " .. rank2_case.macro)
  end
  for _, endpoint in ipairs(rank2_case.endpoints) do
    for _, yaw in ipairs({ -90, 0, 90 }) do
      for _, pitch in ipairs({ -5, 30, 80 }) do
        local yaw_radians, pitch_radians = math.rad(yaw), math.rad(pitch)
        local actual =
          evaluate_depth5(record, endpoint[1], yaw_radians, pitch_radians)
        local expected = evaluate_rank2_source_oracle(
          rank2_case, endpoint[2], yaw_radians, pitch_radians)
        for axis = 1, 3 do
          local difference = math.abs(actual[axis] - expected[axis])
          if difference > rank2_tolerance then
            fail(string.format(
              "%s %s yaw=%g pitch=%g axis=%d differs by %.17g",
              rank2_case.macro, endpoint[1], yaw, pitch, axis, difference
            ))
          end
        end
      end
    end
  end
end

-- Generator determinism is covered by test_turret_muzzle_geometry_generation.py,
-- which iterates every entry in the generator's MACROS table.
print("turret muzzle geometry tests passed")
