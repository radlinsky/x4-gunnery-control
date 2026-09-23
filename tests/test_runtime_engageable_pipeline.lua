local fix = dofile('tests/support/runtime_fixture.lua').load()
local C = fix.C
fix.gcMenu.onShowMenu()
local session = fix.API.getSession()
session.phase = 'console'
session.groups = {{key='selected', members={
    {componentID=101, macro='test', operational=true},
    {componentID=102, macro='test', operational=true},
    {componentID=103, macro='test', operational=false},
}}}
session.checkedGroupKeys = {selected=true}
GetComponentData = function(_, key)
    if key == 'isenemy' then return true end
end
local points = {{id=1,c={1,2,3},r=0.25}, {id=2,c={4,5,6},r=0.5}}
X4GunneryAimPointMap.search = function() return {points=points} end
X4GunneryTurretBearing.evaluate = function(_, point)
    return {aimPoint=point,state='CAN AIM',firingOrigins={{position={1,0,0}}}}
end
local cursor = 0
local function events()
    local out = {}
    for i=cursor+1,#fix.uiTriggeredEvents do out[#out+1]=fix.uiTriggeredEvents[i] end
    cursor=#fix.uiTriggeredEvents
    return out
end
local function one(control)
    local list=events()
    assert(#list==1 and list[1].control==control,
        'expected only '..control..', got '..(#list>0 and list[1].control or 'none'))
    return list[1].params
end
local function range(p,code)
    fix.fireEvent('X4GunneryControl.EngageabilityRange',
        'x4gcr:'..p.token..':'..p.weaponKey..':'..code)
end
local function box(p)
    fix.fireEvent('X4GunneryControl.AimPointBox',
        'x4gcapb:'..p.token..':1:0:0:0:10000:10000:10000')
end
local function start(target)
    cursor=#fix.uiTriggeredEvents
    local result=fix.API.requestEngageability(target)
    assert(result.total==2)
    return result
end

-- Invalid upstream replies and search failures complete as UNKNOWN.
local function started(target)
    local cached=start(target)
    local requests=events()
    range(requests[1].params,1); range(requests[2].params,2)
    return cached,one('aimpoint_box')
end
result,b=started(908)
fix.fireEvent('X4GunneryControl.AimPointBox','x4gcapb:'..b.token..':0:0:0:0:0:0:0')
assert(not result.pending and result.known==1 and result.aimMap.failed)
X4GunneryAimPointMap.search=function() error('failed search') end
result,b=started(909); box(b)
assert(not result.pending and result.known==1 and result.aimMap.failed)

local observed
X4GunneryAimPointMap.search=function(_,_,sample)
    observed=sample(1,{5,6,7})
    return {points={}}
end
result,b=started(910); box(b)
local probe=one('aimpoint_probe'); assert(probe.x==5)
fix.fireEvent('X4GunneryControl.AimPointProbe','x4gcapp:'..probe.token..':1:1000000000:0:0')
assert(observed[1]==1 and not result.pending and result.known==1)
result,b=started(911); box(b); probe=one('aimpoint_probe')
fix.fireEvent('X4GunneryControl.AimPointProbe','x4gcapp:'..probe.token..':0:0:0:0')
assert(not result.pending and result.known==1 and result.aimMap.failed)
result,b=started(912); box(b); probe=one('aimpoint_probe')
fix.fireEvent('X4GunneryControl.AimPointProbe','x4gcapp:'..probe.token..':1:0:0:0')
assert(not result.pending and result.known==1 and result.aimMap.failed)

X4GunneryAimPointMap.search=function() return {points=points} end
result,b=started(913); box(b)
local bad=one('aimpoint_bearing')
fix.fireEvent('X4GunneryControl.AimPointBearing',
    'x4gcapc:'..bad.token..':'..bad.weaponKey..':1:0:0:0:0:0:0:0')
assert(result.aimMap.rows[1].points[1].bearing.state=='UNKNOWN')
assert(result.aimMap.rows[1].points[1].lineOfFire=='NOT_EVALUATED')
assert(one('aimpoint_bearing').point==2)

-- A timed-out request replaces its token; an old range reply cannot finish it.
local clock=100
getElapsedTime=function() return clock end
local stale=start(914); e=events(); local old=e[1].params
clock=103
local refreshed=fix.API.requestEngageability(914)
assert(refreshed==stale and refreshed.aimMap.token~=old.token)
local mark=#fix.uiTriggeredEvents
range(old,1)
assert(refreshed.pending and #fix.uiTriggeredEvents==mark)
print('runtime engageable pipeline edge cases: ok')

-- Surface eligibility reads the owner, even when the selected component has
-- a different enemy flag.
local oldContext=C.GetContextByClass
C.GetContextByClass=function(component) return tonumber(component)==915 and 500 or oldContext(component) end
GetComponentData=function(component,key)
    if key=='isenemy' then return tonumber(component)==500 end
end
local surface=start(915)
assert(surface.pending and surface.aimMap.authorized and #events()==2)
GetComponentData=function(component,key)
    if key=='isenemy' then return tonumber(component)==915 end
end
surface=start(916)
assert(not surface.pending and surface.aimMap.authorized==false and #events()==0)
C.GetContextByClass=oldContext

-- A completed answer is cached; an expired answer re-enters pending state.
GetComponentData=function(_,key) if key=='isenemy' then return true end end
local cached=start(917)
e=events(); range(e[1].params,2); range(e[2].params,2)
assert(fix.API.requestEngageability(917)==cached and not cached.pending)
clock=105
assert(fix.API.requestEngageability(917)==cached and cached.pending
    and cached.engageable==nil and cached.total==2)
print('runtime engageable cache and owner gate: ok')
