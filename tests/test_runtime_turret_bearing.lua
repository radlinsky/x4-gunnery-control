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
session.groups = {{key='selected', members={{componentID=101,macro='future_turret_macro',operational=true}}}}
session.checkedGroupKeys = {selected=true}
GetComponentData = function(_,key) if key=='isenemy' then return true end end
X4GunneryAimPointMap.search = function() return {points={point},samples=12} end
local cached=fix.API.requestEngageability(900)
local request=cached.aimMap
assert(request and request.result==nil and fix.uiTriggeredEvents[#fix.uiTriggeredEvents].control=='engageability_range')
fix.fireEvent('X4GunneryControl.EngageabilityRange','x4gcr:'..request.token..':101:1')
assert(fix.uiTriggeredEvents[#fix.uiTriggeredEvents].control=='aimpoint_box')
fix.fireEvent('X4GunneryControl.AimPointBox','x4gcapb:'..request.token..':1:0:0:0:10000:10000:10000')
local sent=fix.uiTriggeredEvents[#fix.uiTriggeredEvents]
assert(sent.control=='aimpoint_bearing' and sent.params.x==point.c[1])
local values={}
for _,v in ipairs(point.c) do values[#values+1]=string.format('%.0f',v*1e9) end
fix.fireEvent('X4GunneryControl.AimPointBearing',
    'x4gcapc:'..request.token..':101:1:1:'..table.concat(values,':')..':9000000000:8000000000:7000000000')
local bearingResult=request.rows[1].points[1].bearing
assert(bearingResult.aimPoint==point and bearingResult.state=='CAN AIM')
assert(bearingResult.firingOrigins[1].source=='current-barrelposition-fallback')
assert(fix.uiTriggeredEvents[#fix.uiTriggeredEvents].control=='aimpoint_line_of_fire')
print('turret bearing: ok')
