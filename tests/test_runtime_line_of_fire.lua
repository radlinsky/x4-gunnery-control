local fix = dofile('tests/support/runtime_fixture.lua').load()
fix.gcMenu.onShowMenu()
local session=fix.API.getSession()
session.groups={{key='selected',members={{componentID=101,macro='known',operational=true}}}}
session.checkedGroupKeys={selected=true}
GetComponentData=function(_,key) if key=='isenemy' then return true end end
local point={id=1,c={10,20,30},r=0.25}
X4GunneryAimPointMap.begin=function() return function() return {points={point},samples=12} end end
X4GunneryTurretBearing.evaluate=function(_,aim)
    return {aimPoint=aim,state='CAN AIM',firingOrigins={
        {position={1,2,3},source='geometry-predicted'},
        {position={4,5,6},source='geometry-predicted'}}}
end
local cached=fix.API.requestEngageability(900)
local token=cached.aimMap.token
fix.fireEvent('X4GunneryControl.EngageabilityRange','x4gcr:'..token..':101:1')
fix.fireEvent('X4GunneryControl.AimPointBox','x4gcapb:'..token..':1:0:0:0:10000:10000:10000')
fix.fireEvent('X4GunneryControl.AimPointBearing',
    'x4gcapc:'..token..':1|101:1:10000000000:20000000000:30000000000:0:0:0')
local first=fix.uiTriggeredEvents[#fix.uiTriggeredEvents]
assert(first.control=='aimpoint_line_of_fire' and first.params.point==1
    and first.params.origin==1 and first.params.ox==1 and first.params.px==10)
fix.fireEvent('X4GunneryControl.AimPointLineOfFire','x4gcapl:'..token..':101:1:2:1:0')
assert(cached.pending and cached.aimMap.rows[1].points[1].bearing.firingOrigins[2].lineOfFire.state=='NOT_EVALUATED')
fix.fireEvent('X4GunneryControl.AimPointLineOfFire','x4gcapl:'..token..':101:1:1:2:3')
local second=fix.uiTriggeredEvents[#fix.uiTriggeredEvents]
assert(second.control=='aimpoint_line_of_fire' and second.params.origin==2
    and second.params.ox==4 and second.params.px==10)
fix.fireEvent('X4GunneryControl.AimPointLineOfFire','x4gcapl:'..token..':101:1:2:1:2')
local result=cached.aimMap.rows[1].points[1]
assert(result.aimPoint==point and result.bearing.aimPoint==point and result.lineOfFire=='clear')
assert(result.bearing.firingOrigins[1].lineOfFire.state=='LINE OF FIRE BLOCKED')
assert(result.bearing.firingOrigins[2].lineOfFire.state=='clear')
assert(not cached.pending and cached.engageable==1)
print('runtime line of fire: ok')
