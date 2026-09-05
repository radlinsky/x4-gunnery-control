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
}
local macro_count = 0
for name in pairs(X4GunneryTurretMuzzleGeometry) do
  macro_count = macro_count + 1
  if not expected_macros[name] then
    fail("unexpected generated macro key " .. tostring(name))
  end
end
if macro_count ~= 2 then
  fail("expected exactly two generated macro records, got " .. macro_count)
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

print("turret muzzle geometry tests passed")
