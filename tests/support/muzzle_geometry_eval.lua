-- Shared evaluation of the generated turret muzzle records
-- (ui/turret_muzzle_geometry.lua). Used by tests/test_turret_muzzle_geometry.lua
-- and tests/test_runtime_targeting_engageability.lua so neither test carries a
-- second copy of the accepted composition rules.
-- Usage: local eval = dofile("tests/support/muzzle_geometry_eval.lua")

local M = {}

function M.add(left, right)
  return {
    left[1] + right[1],
    left[2] + right[2],
    left[3] + right[3],
  }
end

function M.rotate(rotation, vector)
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

function M.axis_rotation(axis, degrees)
  local radians = math.rad(degrees) / 2
  local sine = math.sin(radians)
  if axis == "x" then
    return { sine, 0, 0, math.cos(radians) }
  elseif axis == "y" then
    return { 0, sine, 0, math.cos(radians) }
  end
  error("unsupported rotation axis " .. tostring(axis))
end

function M.axis_rotation_radians(axis, radians)
  return M.axis_rotation(axis, math.deg(radians))
end

function M.rotate_in_frame(rotations, vector)
  for index = #rotations, 1, -1 do
    vector = M.rotate(rotations[index], vector)
  end
  return vector
end

function M.apply_transform(position, rotations, transform)
  position = M.add(position, M.rotate_in_frame(rotations, transform.position))
  rotations[#rotations + 1] = transform.quaternion
  return position
end

-- depth4_dual_translation composition (issue #74 accepted rule).
-- Pose yaw/pitch are degrees.
function M.evaluate_geometry(geometry, endpoint_connection, pose)
  local position = { 0, 0, 0 }
  local rotations = {}

  for _, layer in ipairs(geometry.layers) do
    position = M.add(position,
      M.rotate_in_frame(rotations, layer.connection_transform.position))
    if layer.settled_position then
      position = M.add(position,
        M.rotate_in_frame(rotations, layer.settled_position))
    end
    if layer.runtime_rotation then
      local axis = layer.runtime_rotation.axis
      local degrees = axis == "x" and -pose.pitch or pose.yaw
      rotations[#rotations + 1] = M.axis_rotation(axis, degrees)
    end
    rotations[#rotations + 1] = layer.connection_transform.quaternion
    position = M.apply_transform(position, rotations, layer.part_transform)
  end

  for _, endpoint in ipairs(geometry.endpoints) do
    if endpoint.connection == endpoint_connection then
      return M.apply_transform(position, rotations, endpoint.transform)
    end
  end
  error("missing endpoint " .. endpoint_connection)
end

-- depth5_additive_x_rotation composition (issue #83 accepted rule):
-- C_i, then P_i, then the additive settled local-X rotation, then the
-- layer's live rotation. Yaw/pitch are radians.
function M.evaluate_depth5(geometry, endpoint_connection, yaw, pitch)
  local position = { 0, 0, 0 }
  local rotations = {}
  for _, layer in ipairs(geometry.layers) do
    position = M.apply_transform(position, rotations, layer.connection_transform)
    position = M.apply_transform(position, rotations, layer.part_transform)
    if layer.settled_position then
      position = M.add(position,
        M.rotate_in_frame(rotations, layer.settled_position))
    end
    if layer.settled_rotation_x_radians then
      rotations[#rotations + 1] =
        M.axis_rotation_radians("x", layer.settled_rotation_x_radians)
    end
    if layer.runtime_rotation then
      local axis = layer.runtime_rotation.axis
      rotations[#rotations + 1] =
        M.axis_rotation_radians(axis, axis == "x" and -pitch or yaw)
    end
  end
  for _, endpoint in ipairs(geometry.endpoints) do
    if endpoint.connection == endpoint_connection then
      return M.add(position, M.rotate_in_frame(rotations, endpoint.transform.position))
    end
  end
  error("missing endpoint " .. endpoint_connection)
end

-- Evaluate a generated record at its production endpoint (the ordered pair's
-- second entry) for the semantic case it declares. Yaw/pitch are degrees.
function M.evaluate_record(geometry, yaw, pitch)
  local connection = geometry.endpoints[2].connection
  if geometry.semantic_case == "depth5_additive_x_rotation" then
    return M.evaluate_depth5(geometry, connection, math.rad(yaw), math.rad(pitch))
  end
  return M.evaluate_geometry(geometry, connection, { yaw = yaw, pitch = pitch })
end

return M
