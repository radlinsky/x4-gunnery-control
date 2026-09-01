local function readFile(path)
    local handle = assert(io.open(path, "r"))
    local content = handle:read("*a")
    handle:close()
    return content
end

local function countPlain(haystack, needle)
    local count, start = 0, 1
    while true do
        local first = haystack:find(needle, start, true)
        if not first then return count end
        count = count + 1
        start = first + #needle
    end
end

local scenario = readFile("testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_scenario.xml")
local loadouts = readFile("testlab/x4_gunnery_control_testlab/libraries/loadouts.xml")

-- This is a reusable Test Lab safety contract, not a historical scenario
-- snapshot: when a supported deterministic shooter declares one Beam, the MD
-- readiness census must recognize the exact Beam macro that the loadout mounts.
local mountedBeam = '<turrets macro="turret_par_l_beam_01_mk1_macro" group="group_rear_down_mid" exact="1"/>'
assert(countPlain(loadouts, mountedBeam) == 1,
    "dual-family loadout must mount exactly one Paranid L Beam")

local censusCondition = '$Weapon.macro == macro.turret_arg_m_beam_02_mk1_macro or $Weapon.macro == macro.turret_par_l_beam_01_mk1_macro'
assert(countPlain(scenario, censusCondition) == 2,
    "both shooter census paths must count the Paranid L Beam as Beam")

print("test_testlab_dual_family_census.lua: ok")
