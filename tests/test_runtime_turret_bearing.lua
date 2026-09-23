dofile('ui/turret_bearing_geometry.lua')
dofile('ui/turret_bearing.lua')
local bearing = X4GunneryTurretBearing

local point = {id=1, c={18.814417367671947,28.22162605150792,94.07208683835974}, r=0.25, samples=12}
local aim = bearing.evaluate('turret_arg_l_beam_01_mk1_macro',point,point.c,{9,8,7})
assert(aim.aimPoint == point and aim.state == 'CAN AIM' and #aim.firingOrigins == 1)
assert(aim.firingOrigins[1].source == 'geometry-predicted')
assert(math.abs(aim.firingOrigins[1].position[1] - -1.7329971944018276) < 1e-6)
assert(point.r == 0.25 and point.samples == 12)

local cannot = bearing.evaluate('turret_arg_l_beam_01_mk1_macro',point,{-0.03939104,8.86484451335585,93.93046434107696},{9,8,7})
assert(cannot.aimPoint == point and cannot.state == 'CANNOT BEAR' and #cannot.firingOrigins == 0)

local unknown = bearing.evaluate('turret_l_imp_exe_quad_ball_blue_macro',point,{0,0,0},{9,8,7})
assert(unknown.aimPoint == point and unknown.state == 'UNKNOWN' and #unknown.firingOrigins == 0)

local two = bearing.evaluate('turret_bor_l_disruptor_01_mk1_macro',point,{7.1e-09,105.55757485984815,-3.025561160031036},{9,8,7})
assert(two.aimPoint == point and two.state == 'CAN AIM' and #two.firingOrigins == 2)
assert(two.firingOrigins[1].source == 'geometry-predicted' and two.firingOrigins[2].source == 'geometry-predicted')
assert(math.abs(two.firingOrigins[1].position[1] - 0.3369279929) < 1e-6)
assert(math.abs(two.firingOrigins[2].position[1] - -0.3369279929) < 1e-6)

local fallback = bearing.evaluate('future_turret_macro',point,point.c,{9,8,7})
assert(fallback.aimPoint == point and fallback.state == 'CAN AIM' and #fallback.firingOrigins == 1)
assert(fallback.firingOrigins[1].source == 'current-barrelposition-fallback')
assert(fallback.firingOrigins[1].position[1] == 9 and fallback.firingOrigins[1].position[2] == 8 and fallback.firingOrigins[1].position[3] == 7)

local fix = dofile('tests/support/runtime_fixture.lua').load()
fix.gcMenu.onShowMenu()
local session = fix.API.getSession()
session.groups = {{key='selected', members={
    {componentID=101, macro='turret_arg_l_beam_01_mk1_macro', operational=true},
    {componentID=102, macro='future_turret_macro', operational=true},
}}}
session.checkedGroupKeys = {selected=true}
local returned = {points={point}, samples=12, stop='nothing definite'}
X4GunneryAimPointMap.search = function() return returned end
local cached = fix.API.requestEngageability(900)
local box
for _,event in ipairs(fix.uiTriggeredEvents) do
    if event.control == 'aimpoint_box' then box = event.params end
end
assert(box and cached.aimMap)
fix.fireEvent('X4GunneryControl.AimPointBox','x4gcapb:'..box.token..':1:0:0:0:10000:10000:10000')
local sent = {}
for _,event in ipairs(fix.uiTriggeredEvents) do
    if event.control == 'aimpoint_bearing' then sent[event.params.weaponKey] = event.params end
end
assert(sent['101'] and sent['102'] and sent['101'].x == point.c[1])
local function packed(weapon, localPoint)
    local values={}
    for _,v in ipairs(localPoint) do values[#values+1]=string.format('%.0f',v*1e9) end
    return 'x4gcapc:'..box.token..':'..weapon..':1:1:'..table.concat(values,':')..':9000000000:8000000000:7000000000'
end
fix.fireEvent('X4GunneryControl.AimPointBearing',packed('101',point.c))
fix.fireEvent('X4GunneryControl.AimPointBearing',packed('102',point.c))
local known = cached.aimMap.bearingResults['101'][1]
local future = cached.aimMap.bearingResults['102'][1]
assert(known.aimPoint == point and known.state == 'CAN AIM' and known.firingOrigins[1].source == 'geometry-predicted')
assert(future.aimPoint == point and future.state == 'CAN AIM' and future.firingOrigins[1].source == 'current-barrelposition-fallback')
assert(cached.aimMap.bearingPending == 0)

-- Exercise the asynchronous #184 probe handoff and its genuine failure paths.
local function startMap(target)
    local request = fix.API.requestEngageability(target).aimMap
    local token = request.token
    fix.fireEvent('X4GunneryControl.AimPointBox',
        'x4gcapb:'..token..':1:0:0:0:10000:10000:10000')
    return request, token
end
local observed
X4GunneryAimPointMap.search = function(_, _, sample)
    observed = sample(1, {5,6,7})
    return {points={},samples=1}
end
local replay, replayToken = startMap(901)
assert(replay.pending and fix.uiTriggeredEvents[#fix.uiTriggeredEvents].control == 'aimpoint_probe')
assert(fix.uiTriggeredEvents[#fix.uiTriggeredEvents].params.x == 5)
fix.fireEvent('X4GunneryControl.AimPointProbe',
    'x4gcapp:'..replayToken..':1:1000000000:0:0')
assert(replay.result and replay.bearingPending == 0 and replay.lineOfFirePending == 0)
assert(observed[1] == 1 and observed[2] == 0 and observed[3] == 0)

X4GunneryAimPointMap.search = function() error('bad search') end
local failed = startMap(902)
assert(failed.failed and failed.pending == nil)

X4GunneryAimPointMap.search = function(_, _, sample)
    sample(1, {5,6,7})
end
local badReply, badToken = startMap(903)
fix.fireEvent('X4GunneryControl.AimPointProbe', 'x4gcapp:'..badToken..':0:0:0:0')
assert(badReply.failed and badReply.pending == nil)

local badVector, badVectorToken = startMap(904)
fix.fireEvent('X4GunneryControl.AimPointProbe', 'x4gcapp:'..badVectorToken..':1:0:0:0')
assert(badVector.failed and badVector.pending == nil)

print('turret bearing: ok')
