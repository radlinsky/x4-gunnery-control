local function readFile(path)
    local handle = assert(io.open(path, "r"))
    local content = handle:read("*a")
    handle:close()
    return content
end

local scenario = readFile("testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_scenario.xml")
local loadouts = readFile("testlab/x4_gunnery_control_testlab/libraries/loadouts.xml")
local ui = readFile("testlab/x4_gunnery_control_testlab/ui/testlab.lua")

assert(not loadouts:find("x4gc_testlab_issue", 1, true),
    "reusable deterministic loadout ids must not be issue-numbered")
assert(loadouts:find('id="x4gc_testlab_par_l_destroyer_01_beam_plasma"', 1, true),
    "the current dual-family fixture must use a descriptive library id")
assert(loadouts:find('id="x4gc_testlab_par_l_destroyer_01_mixed_missiles"', 1, true),
    "the former code-authored missile loadout must live in the data library")
assert(scenario:find('<get_loadout result="$RequestedLoadout" loadout="$Def.$loadout" macro="macro.{$Def.$macro}"/>', 1, true),
    "MD must resolve the authored loadout id generically")
assert(scenario:find('<apply_loadout object="$Ship" loadout="$RequestedLoadout"/>', 1, true),
    "MD must apply the resolved named loadout generically")
assert(not scenario:find("$Def.$loadout ==", 1, true),
    "MD must not branch on fixture-specific loadout names")
assert(not ui:find("supported shooter loadout", 1, true),
    "Lua must not maintain a deterministic-loadout whitelist")
assert(not ui:find("inconsistent shooter census", 1, true),
    "Lua must not hard-code census shapes for named fixtures")
assert(not scenario:find("scenario_station", 1, true) and not ui:find("scenarioSpec.stations", 1, true),
    "the ordinary declarative path must not retain the historical station experiment")
assert(not scenario:find("GeometryQualify", 1, true) and not ui:find("pendingQualify", 1, true),
    "historical geometry qualification must not remain in the ordinary fixture path")

print("test_testlab_declarative_scenario.lua: ok")
