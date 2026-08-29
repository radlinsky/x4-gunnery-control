-- Focused offline regression for Issue #69 request 337878448_q2.
--
-- Candidate constants come only from shipped X4 9.00 (611726) assets:
-- turret_par_l_beam_01_mk1.xml
--   14-23   component root offset and animation frame ranges
--   137-140 yaw rotator
--   185-197 elevation pivot and base quaternion
--   233-237 barrel connection and cancelling quaternion
--   273-280 authored laser offsets
--   305-307 zero-offset equipment socket
-- turret_par_l_beam_01_mk1_macro.xml
--   4-10    component binding and 20 deg/s, 30 deg/s^2 articulation
-- TURRET_PAR_L_BEAM_01_MK1_DATA.ANI (v1 descriptor/key records)
--   part_rotator/turret_active: position [0, 6.145042419433594, 0]
--   anim_barrel/turret_active: position [0, -0.23982000350952148,
--                                      27.710205078125]
-- No metre value below is fitted from the live trajectory. Live vectors are
-- observations used only as expected results.

local function vec(x, y, z)
    return { x = x, y = y, z = z }
end

local function add(a, b)
    return vec(a.x + b.x, a.y + b.y, a.z + b.z)
end

local function sub(a, b)
    return vec(a.x - b.x, a.y - b.y, a.z - b.z)
end

local function length(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function distance(a, b)
    return length(sub(a, b))
end

local function rotate_x(v, angle)
    local c, s = math.cos(angle), math.sin(angle)
    return vec(v.x, c * v.y - s * v.z, s * v.y + c * v.z)
end

local function rotate_y(v, angle)
    local c, s = math.cos(angle), math.sin(angle)
    return vec(c * v.x + s * v.z, v.y, -s * v.x + c * v.z)
end

local function quaternion(x, y, z, w)
    return { x = x, y = y, z = z, w = w }
end

local function multiply_quaternion(a, b)
    return quaternion(
        a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
end

local function rotate_quaternion(q, v)
    local tx = 2 * (q.y * v.z - q.z * v.y)
    local ty = 2 * (q.z * v.x - q.x * v.z)
    local tz = 2 * (q.x * v.y - q.y * v.x)
    return vec(
        v.x + q.w * tx + q.y * tz - q.z * ty,
        v.y + q.w * ty + q.z * tx - q.x * tz,
        v.z + q.w * tz + q.x * ty - q.y * tx)
end

local component_root = vec(1.877547e-6, 2.018104, -1.043081e-5)
local elevation_pivot = vec(-1.730653e-6, 2.926126, -16.11956)
local barrel_connection = vec(-1.113896e-6, 0.06259775, 17.45395)
local gun_base_rotation = quaternion(-4.327158e-3, 3.273904e-12,
                                     -7.565876e-10, 0.9999906)
local barrel_base_rotation = quaternion(4.327045e-3, -6.547686e-12,
                                        2.825544e-14, 0.9999906)
-- barrelposition at rest identifies con_laser_02, not the midpoint: composing
-- this authored offset reproduces the observed rest vector to micrometres.
local laser_02 = vec(-0.361773, 0.2692866, 10.70685)
local rotator_active_translation = vec(0, 6.145042419433594, 0)
local barrel_active_translation = vec(0, -0.23982000350952148,
                                      27.710205078125)
local zero_animation = vec(0, 0, 0)

local gun_barrel_rotation = multiply_quaternion(gun_base_rotation,
                                                barrel_base_rotation)

local function compose_muzzle(rotator_translation, barrel_translation)
    local rotator_origin = add(component_root, rotator_translation)
    local downstream = add(
        rotate_quaternion(gun_base_rotation,
                          add(barrel_connection, barrel_translation)),
        rotate_quaternion(gun_barrel_rotation, laser_02))
    return add(add(rotator_origin, elevation_pivot), downstream),
           rotator_origin, downstream
end

local rest_muzzle = compose_muzzle(zero_animation, zero_animation)
local observed_rest = vec(-0.361774, 5.427165, 12.040031)
assert(distance(rest_muzzle, observed_rest) < 0.00001,
       "authored inactive hierarchy no longer reproduces barrelposition")

local deployed_neutral, yaw_origin, deployed_from_elevation_pivot =
    compose_muzzle(rotator_active_translation, barrel_active_translation)

-- Minimal prospective construction. The authored active muzzle and its authored
-- elevation pivot are retained. The downstream vector is reprojected by the
-- weapon-local look-at pitch (X4 pitch uses the opposite mathematical X sign),
-- then the pivot plus muzzle is turned around the authored Y rotator to the
-- target yaw. No controller state or fitted distance is used.
local target_yaw = math.pi
local target_pitch = -0.00135549
local virtual_muzzle = add(
    yaw_origin,
    rotate_y(add(elevation_pivot,
                 rotate_x(deployed_from_elevation_pivot, -target_pitch)),
             target_yaw))

-- A pure rotation of the current/rest vector preserves its 13.2116 m norm.
-- Every settled muzzle is about 41.2983 m from the weapon origin, so the reverse
-- triangle inequality is already a decisive lower bound on every such model.
local settled = {
    { value = vec(0.361772, 11.193660, -39.750687), count = 17 },
    { value = vec(0.361762, 11.193673, -39.750683), count = 17 },
    { value = vec(0.361791, 11.193634, -39.750687), count = 20 },
    { value = vec(0.361781, 11.193646, -39.750679), count = 19 },
}

local pure_rotation_lower_bound = math.huge
local max_settled_error = 0
local settled_squared_error = 0
local settled_count = 0
for _, sample in ipairs(settled) do
    local lower_bound = math.abs(length(sample.value) - length(observed_rest))
    if lower_bound < pure_rotation_lower_bound then
        pure_rotation_lower_bound = lower_bound
    end
    local candidate_error = distance(virtual_muzzle, sample.value)
    if candidate_error > max_settled_error then
        max_settled_error = candidate_error
    end
    settled_squared_error = settled_squared_error
        + sample.count * candidate_error * candidate_error
    settled_count = settled_count + sample.count
end
local settled_rmse = math.sqrt(settled_squared_error / settled_count)

assert(pure_rotation_lower_bound > 28.0,
       "current-vector pure rotation is no longer decisively rejected")
assert(max_settled_error <= 0.5,
       "source-backed deployed virtual muzzle exceeds 0.5 m settled tolerance")
assert(settled_count == 73, "settled non-recoil sample census changed")

-- Ready ticks 5-13 trace yaw around the source-backed deployed radial length.
local ready_circle = {
    vec(-4.492211, 11.193221, 39.497673),
    vec(-17.767292, 11.193207, 35.560791),
    vec(-28.882421, 11.193261, 27.313961),
    vec(-36.501034, 11.193314, 15.745507),
    vec(-39.691616, 11.193407, 2.196001),
    vec(-38.028008, 11.193474, -11.580927),
    vec(-31.734879, 11.193594, -23.940453),
    vec(-21.625963, 11.193606, -33.355141),
    vec(-8.888703, 11.193646, -38.745819),
}
local authored_radius = math.sqrt(
    (virtual_muzzle.x - yaw_origin.x) ^ 2
    + (virtual_muzzle.z - yaw_origin.z) ^ 2)
local max_circle_radius_error = 0
for _, sample in ipairs(ready_circle) do
    local radius = math.sqrt(
        (sample.x - yaw_origin.x) ^ 2 + (sample.z - yaw_origin.z) ^ 2)
    max_circle_radius_error = math.max(max_circle_radius_error,
                                       math.abs(radius - authored_radius))
end
assert(max_circle_radius_error < 0.002,
       "authored deployed radius no longer explains ready-state yaw circle")

-- Endpoint errors for the observed tick-3-to-settled trajectory. Large early
-- errors are expected: this is a prospective endpoint, not a controller-motion
-- model. Tick 14 is a recoil sample; tick 15 is the first settled sample.
local trajectory = {
    { 3, vec(-0.361774, 7.266187, 20.669619) },
    { 4, vec(-0.361774, 10.221849, 34.539024) },
    { 5, ready_circle[1] }, { 6, ready_circle[2] },
    { 7, ready_circle[3] }, { 8, ready_circle[4] },
    { 9, ready_circle[5] }, { 10, ready_circle[6] },
    { 11, ready_circle[7] }, { 12, ready_circle[8] },
    { 13, ready_circle[9] },
    { 14, vec(0.336448, 11.231123, -36.388474) },
    { 15, settled[1].value },
}

io.write(string.format(
    "issue69 virtual muzzle: rest_norm=%.6f deployed_neutral=[%.6f,%.6f,%.6f] "
    .. "candidate=[%.6f,%.6f,%.6f]\n",
    length(observed_rest), deployed_neutral.x, deployed_neutral.y,
    deployed_neutral.z, virtual_muzzle.x, virtual_muzzle.y, virtual_muzzle.z))
io.write(string.format(
    "pure_rotation_lower_bound=%.6f settled_n=%d settled_max_error=%.6f "
    .. "settled_rmse=%.6f authored_radius=%.6f circle_max_radius_error=%.6f\n",
    pure_rotation_lower_bound, settled_count, max_settled_error, settled_rmse,
    authored_radius, max_circle_radius_error))
for _, sample in ipairs(trajectory) do
    io.write(string.format("tick=%d endpoint_error=%.6f\n", sample[1],
                           distance(virtual_muzzle, sample[2])))
end
io.write("issue69 virtual muzzle geometry passed\n")
