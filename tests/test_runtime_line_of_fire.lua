local fix = dofile("tests/support/runtime_fixture.lua").load()
fix.gcMenu.onShowMenu()
local session = fix.API.getSession()
session.groups = {{key="selected", members={
    {componentID=101, macro="known", operational=true},
    {componentID=102, macro="future", operational=true},
    {componentID=103, macro="cannot", operational=true},
}}}
session.checkedGroupKeys = {selected=true}

local point = {id=1, c={10,20,30}, r=0.25}
X4GunneryAimPointMap.search = function() return {points={point}, samples=12} end
X4GunneryTurretBearing.evaluate = function(macro, aim, _, barrel)
    local origins = {}
    local state = "CANNOT BEAR"
    if macro == "known" then
        state = "CAN AIM"
        origins = {
            {position={1,2,3}, source="geometry-predicted"},
            {position={4,5,6}, source="geometry-predicted"},
        }
    elseif macro == "future" then
        state = "CAN AIM"
        origins = {{position=barrel, source="current-barrelposition-fallback"}}
    end
    return {aimPoint=aim, state=state, firingOrigins=origins}
end

local cached = fix.API.requestEngageability(900)
local token
for _, event in ipairs(fix.uiTriggeredEvents) do
    if event.control == "aimpoint_box" then token = event.params.token end
end
assert(token and cached.aimMap)
fix.fireEvent("X4GunneryControl.AimPointBox", "x4gcapb:"..token..":1:0:0:0:10000:10000:10000")

local function bearing(weapon)
    fix.fireEvent("X4GunneryControl.AimPointBearing",
        "x4gcapc:"..token..":"..weapon..":1:1:10000000000:20000000000:30000000000:9000000000:8000000000:7000000000")
end
bearing(101)
bearing(102)
bearing(103)

local sent = {}
for _, event in ipairs(fix.uiTriggeredEvents) do
    if event.control == "aimpoint_line_of_fire" then sent[#sent+1] = event.params end
end
assert(#sent == 3 and cached.aimMap.bearingPending == 0 and cached.aimMap.lineOfFirePending == 3)
assert(sent[1].weaponKey == "101" and sent[1].point == 1 and sent[1].origin == 1)
assert(sent[2].weaponKey == "101" and sent[2].point == 1 and sent[2].origin == 2)
assert(sent[3].weaponKey == "102" and sent[3].origin == 1)
for _, e in ipairs(sent) do
    assert(e.px == 10 and e.py == 20 and e.pz == 30 and e.target == 900)
end
assert(sent[1].ox == 1 and sent[2].ox == 4 and sent[3].ox == 9)

local function reply(weapon, origin, result, checks)
    fix.fireEvent("X4GunneryControl.AimPointLineOfFire",
        "x4gcapl:"..token..":"..weapon..":1:"..origin..":"..result..":"..checks)
end
reply(101, 2, 2, 3)
reply(101, 2, 1, 0)
reply(102, 1, 0, 0)
assert(cached.aimMap.lineOfFirePending == 1)
reply(101, 1, 1, 2)

local known = cached.aimMap.bearingResults["101"][1]
local future = cached.aimMap.bearingResults["102"][1]
local cannot = cached.aimMap.bearingResults["103"][1]
assert(known.aimPoint == point and known.aimPoint.r == 0.25)
assert(known.firingOrigins[1].lineOfFire.state == "clear" and known.firingOrigins[1].lineOfFire.checks == 2)
assert(known.firingOrigins[2].lineOfFire.state == "LINE OF FIRE BLOCKED" and known.firingOrigins[2].lineOfFire.checks == 3)
assert(future.firingOrigins[1].source == "current-barrelposition-fallback")
assert(future.firingOrigins[1].lineOfFire.state == "UNKNOWN" and future.firingOrigins[1].lineOfFire.checks == 0)
assert(cannot.state == "CANNOT BEAR" and #cannot.firingOrigins == 0)
assert(cached.aimMap.lineOfFirePending == 0)
reply(101, 1, 2, 3)
assert(known.firingOrigins[1].lineOfFire.state == "clear")
print("runtime line of fire: ok")
