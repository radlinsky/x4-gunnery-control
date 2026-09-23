-- The production coordinator requests only the next required check.
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
local enemy = true
GetComponentData = function(_, key)
    if key == 'isenemy' then return enemy end
    return nil
end
local points = {{id=1,c={1,2,3},r=0.25}, {id=2,c={4,5,6},r=0.5}}
X4GunneryAimPointMap.search = function() return {points=points} end
local states = {}
X4GunneryTurretBearing.evaluate = function(_, point)
    local state = states[point.id] or 'CAN AIM'
    local origins = state == 'CAN AIM' and {{position={1,0,0}}, {position={2,0,0}}} or {}
    return {aimPoint=point,state=state,firingOrigins=origins}
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
local function bearing(p)
    fix.fireEvent('X4GunneryControl.AimPointBearing',
        'x4gcapc:'..p.token..':'..p.weaponKey..':'..p.point..':1:1000000000:2000000000:3000000000:0:0:0')
end
local function line(p,code)
    fix.fireEvent('X4GunneryControl.AimPointLineOfFire',
        'x4gcapl:'..p.token..':'..p.weaponKey..':'..p.point..':'..p.origin..':'..code..':1')
end
local function start(target)
    cursor=#fix.uiTriggeredEvents
    local result=fix.API.requestEngageability(target)
    assert(result.total==2)
    return result
end

enemy=false
local denied=start(900)
assert(not denied.pending and denied.engageable==0 and denied.known==2)
assert(#events()==0 and denied.aimMap.rows[1].range=='NOT_EVALUATED')
enemy=true
local out=start(901)
local e=events()
assert(#e==2 and e[1].control=='engageability_range' and e[2].control=='engageability_range')
range(e[1].params,2); range(e[2].params,2)
assert(not out.pending and out.engageable==0 and out.known==2 and #events()==0)

local result=start(902)
e=events(); range(e[1].params,1); range(e[2].params,2)
local request=result.aimMap
box(one('aimpoint_box'))
local b=one('aimpoint_bearing'); assert(b.weaponKey=='101' and b.point==1)
bearing(b)
local l=one('aimpoint_line_of_fire'); assert(l.origin==1 and l.px==1)
line(l,0)
l=one('aimpoint_line_of_fire'); assert(l.origin==2 and l.px==1)
line(l,1)
assert(not result.pending and result.engageable==1 and result.total==2 and result.known==2)
assert(request.rows[1].points[2].bearing=='NOT_EVALUATED')
assert(request.rows[1].points[1].lineOfFire=='clear')
assert(request.rows[2].range=='OUT OF RANGE')

states[1]='UNKNOWN'; states[2]='CANNOT BEAR'
result=start(903); e=events(); range(e[1].params,1); range(e[2].params,2)
box(one('aimpoint_box'))
b=one('aimpoint_bearing'); bearing(b)
b=one('aimpoint_bearing'); assert(b.point==2); bearing(b)
assert(#events()==0 and not result.pending and result.engageable==0 and result.known==1)
assert(result.aimMap.rows[1].points[1].bearing.state=='UNKNOWN')
assert(result.aimMap.rows[1].points[1].lineOfFire=='NOT_EVALUATED')

states[1]='CAN AIM'; states[2]='CANNOT BEAR'
result=start(904); e=events(); range(e[1].params,1); range(e[2].params,2)
box(one('aimpoint_box')); b=one('aimpoint_bearing'); bearing(b)
l=one('aimpoint_line_of_fire'); line(l,2)
l=one('aimpoint_line_of_fire'); line(l,2)
b=one('aimpoint_bearing'); assert(b.point==2); bearing(b)
assert(not result.pending and result.engageable==0 and result.known==2)

X4GunneryTurretBearing.evaluate=function(_,point)
    return {aimPoint=point,state='CAN AIM',firingOrigins={}}
end
result=start(905); e=events(); range(e[1].params,1); range(e[2].params,2)
box(one('aimpoint_box')); bearing(one('aimpoint_bearing')); bearing(one('aimpoint_bearing'))
assert(not result.pending and result.engageable==0 and result.known==2)
assert(result.aimMap.rows[1].points[1].bearing.state=='CAN AIM')
assert(result.aimMap.rows[1].points[1].lineOfFire=='NOT_EVALUATED')
print('runtime engageable pipeline: ok')

-- A clear first origin leaves the second origin and later aim point untouched.
X4GunneryTurretBearing.evaluate=function(_,point)
    return {aimPoint=point,state='CAN AIM',firingOrigins={{position={1,0,0}},{position={2,0,0}}}}
end
result=start(906); e=events(); range(e[1].params,1); range(e[2].params,2)
box(one('aimpoint_box')); bearing(one('aimpoint_bearing'))
l=one('aimpoint_line_of_fire'); line(l,1)
assert(not result.pending and result.engageable==1 and #events()==0)
assert(result.aimMap.rows[1].points[1].bearing.firingOrigins[2].lineOfFire.state=='NOT_EVALUATED')
assert(result.aimMap.rows[1].points[2].bearing=='NOT_EVALUATED')

-- An evaluated UNKNOWN remains distinct from both a blocked origin and skipped work.
result=start(907); e=events(); range(e[1].params,1); range(e[2].params,2)
box(one('aimpoint_box')); bearing(one('aimpoint_bearing'))
line(one('aimpoint_line_of_fire'),0); line(one('aimpoint_line_of_fire'),2)
bearing(one('aimpoint_bearing'))
line(one('aimpoint_line_of_fire'),2); line(one('aimpoint_line_of_fire'),2)
assert(not result.pending and result.engageable==0 and result.known==1)
assert(result.aimMap.rows[1].points[1].lineOfFire=='UNKNOWN')
assert(result.aimMap.rows[1].points[2].lineOfFire=='LINE OF FIRE BLOCKED')

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
