local fix = dofile('tests/support/runtime_fixture.lua').load()
fix.gcMenu.onShowMenu()
local session = fix.API.getSession()
session.phase = 'console'

local BLOCKED, NE = 'LINE OF FIRE BLOCKED', 'NOT_EVALUATED'
local function point(aim, origins)
    return {aim=aim, origins=origins or {}}
end
local function turret(range, p1, p2, expected)
    return {range=range, points={p1, p2}, expected=expected}
end
local B, U, C = {code=2, checks=3}, {code=0, checks=3}, {code=1, checks=3}
local cannot, unknown, zero = point('CANNOT BEAR'), point('UNKNOWN'), point('CAN AIM')
local blocked = point('CAN AIM', {B, B})
local mixed = point('CAN AIM', {B, U})
local clearFirst = point('CAN AIM', {C, B})
local clearLater = point('CAN AIM', {B, C})
local cases = {
    {name='FIRE NOT AUTHORIZED', authorized=false,
        turrets={turret(1, clearFirst, clearLater, {'N','N'})}, answer=0, known=1, work={0,0,0,0,0}},
    {name='all OUT OF RANGE', turrets={
        turret(2, clearFirst, clearLater, {'N','N'}),
        turret(2, blocked, mixed, {'N','N'})}, answer=0, known=2, work={2,0,0,0,0}},
    {name='exact range boundary', turrets={turret(1, clearFirst, cannot, {'C','N'})},
        answer=1, known=1, work={1,1,1,1,3}},
    {name='first origin clear', turrets={turret(1, clearFirst, blocked, {'C','N'})},
        answer=1, known=1, work={1,1,1,1,3}},
    {name='later origin clear', turrets={turret(1, clearLater, cannot, {'L','N'})},
        answer=1, known=1, work={1,1,1,2,6}},
    {name='all origins blocked', turrets={turret(1, blocked, cannot, {'D','B'})},
        answer=0, known=1, work={1,1,2,2,6}},
    {name='blocked plus UNKNOWN', turrets={turret(1, mixed, cannot, {'U','B'})},
        answer=0, known=0, work={1,1,2,2,6}},
    {name='early aim point ENGAGEABLE', turrets={turret(1, clearFirst, clearLater, {'C','N'})},
        answer=1, known=1, work={1,1,1,1,3}},
    {name='failed aim point before success', turrets={turret(1, unknown, clearLater, {'A','L'})},
        answer=1, known=1, work={1,1,2,2,6}},
    {name='UNKNOWN line before success', turrets={turret(1, mixed, clearFirst, {'U','C'})},
        answer=1, known=1, work={1,1,2,3,9}},
    {name='aim-point consistency trap', turrets={turret(1, point('CAN AIM',{B}), cannot, {'S','B'})},
        answer=0, known=1, work={1,1,2,1,3}},
    {name='CAN AIM without origin', turrets={turret(1, zero, cannot, {'Z','B'})},
        answer=0, known=1, work={1,1,2,0,0}},
    {name='two surviving turrets worst case', turrets={
        turret(1, mixed, point('CAN AIM',{U,B}), {'U','V'}),
        turret(1, mixed, point('CAN AIM',{U,B}), {'U','V'})},
        answer=0, known=0, work={2,1,4,8,24}},
}

local expected = {
    N={NE,NE,{}}, B={'CANNOT BEAR',NE,{}}, A={'UNKNOWN',NE,{}},
    Z={'CAN AIM',NE,{}}, C={'CAN AIM','clear',{'clear',NE}},
    L={'CAN AIM','clear',{BLOCKED,'clear'}},
    D={'CAN AIM',BLOCKED,{BLOCKED,BLOCKED}},
    S={'CAN AIM',BLOCKED,{BLOCKED}},
    U={'CAN AIM','UNKNOWN',{BLOCKED,'UNKNOWN'}},
    V={'CAN AIM','UNKNOWN',{'UNKNOWN',BLOCKED}},
}
local eventNames = {
    engageability_range='X4GunneryControl.EngageabilityRange',
    aimpoint_box='X4GunneryControl.AimPointBox',
    aimpoint_bearing='X4GunneryControl.AimPointBearing',
    aimpoint_line_of_fire='X4GunneryControl.AimPointLineOfFire',
}
local function run(case, number)
    session.groups = {{key='selected', members={}}}
    session.checkedGroupKeys = {selected=true}
    for i=1,#case.turrets do
        session.groups[1].members[i] = {componentID=100+i, macro='test', operational=true}
    end
    GetComponentData = function(_, key)
        if key == 'isenemy' then return case.authorized ~= false end
    end
    local points = {
        {id=1,c={11,12,13},r=0.25},
        {id=2,c={21,22,23},r=0.5},
    }
    local searches = 0
    X4GunneryAimPointMap.search = function()
        searches = searches + 1
        return {points=points}
    end
    local activeTurret
    X4GunneryTurretBearing.evaluate = function(_, aim, center, barrel)
        assert(aim == points[aim.id] and center[1] == aim.c[1] and barrel[1] == 0)
        local spec = case.turrets[activeTurret].points[aim.id]
        local origins = {}
        for i=1,#spec.origins do
            origins[i] = {position={aim.c[1] + i, 0, 0}}
        end
        return {aimPoint=aim, state=spec.aim, firingOrigins=origins}
    end
    local cursor = #fix.uiTriggeredEvents
    local result = fix.API.requestEngageability(900+number)
    local work = {0,0,0,0,0}
    while result.pending do
        cursor = cursor + 1
        local event = fix.uiTriggeredEvents[cursor]
        assert(event, case.name..': pending without emitted control')
        local p, payload = event.params
        local turretIndex = tonumber(p.weaponKey)
        if turretIndex then turretIndex = turretIndex - 100 end
        local spec = turretIndex and case.turrets[turretIndex]
        if event.control == 'engageability_range' then
            work[1] = work[1] + 1
            assert(spec and p.target == 900+number)
            payload = 'x4gcr:'..p.token..':'..p.weaponKey..':'..spec.range
        elseif event.control == 'aimpoint_box' then
            work[2] = work[2] + 1
            assert(work[1] == #case.turrets)
            payload = 'x4gcapb:'..p.token..':1:0:0:0:10000:10000:10000'
        elseif event.control == 'aimpoint_bearing' then
            work[3] = work[3] + 1
            assert(spec and p.x == points[p.point].c[1])
            activeTurret = turretIndex
            payload = 'x4gcapc:'..p.token..':'..p.weaponKey..':'..p.point..':1:'
                ..(p.x*1000000000)..':'..(p.y*1000000000)..':'..(p.z*1000000000)..':0:0:0'
        elseif event.control == 'aimpoint_line_of_fire' then
            work[4] = work[4] + 1
            local origin = spec.points[p.point].origins[p.origin]
            assert(origin and p.px == points[p.point].c[1]
                and p.ox == points[p.point].c[1] + p.origin)
            work[5] = work[5] + origin.checks
            payload = 'x4gcapl:'..p.token..':'..p.weaponKey..':'..p.point..':'..p.origin
                ..':'..origin.code..':'..origin.checks
        else
            error(case.name..': unexpected control '..event.control)
        end
        fix.fireEvent(eventNames[event.control], payload)
    end
    assert(cursor == #fix.uiTriggeredEvents, case.name..': extra work after completion')
    assert(result.engageable == case.answer and result.known == case.known, case.name..': answer')
    assert(searches == work[2] and work[2] <= 1, case.name..': shared search')
    for i=1,5 do
        assert(work[i] == case.work[i], case.name..': work '..i..' got '..work[i])
    end
    local reference = {case.authorized == false and 0 or #case.turrets, 0, 0, 0, 0}
    for _, turretSpec in ipairs(case.turrets) do
        if case.authorized ~= false and turretSpec.range == 1 then
            reference[2] = 1
            reference[3] = reference[3] + #turretSpec.points
            for _, aim in ipairs(turretSpec.points) do
                if aim.aim == 'CAN AIM' then
                    reference[4] = reference[4] + #aim.origins
                    for _, origin in ipairs(aim.origins) do reference[5] = reference[5] + origin.checks end
                end
            end
        end
    end
    for i=1,5 do assert(work[i] <= reference[i], case.name..': exceeds reference work '..i) end
    for i, turretSpec in ipairs(case.turrets) do
        local row = result.aimMap.rows[i]
        assert(row.range == (case.authorized == false and NE
            or turretSpec.range == 1 and 'IN RANGE' or 'OUT OF RANGE'), case.name..': range')
        if reference[2] == 1 then
            for j, key in ipairs(turretSpec.expected) do
                local actual, want = row.points[j], expected[key]
                assert(actual.aimPoint == points[j], case.name..': point identity')
                local bearing = type(actual.bearing) == 'table' and actual.bearing.state or actual.bearing
                assert(bearing == want[1] and actual.lineOfFire == want[2], case.name..': point '..j)
                if type(actual.bearing) == 'table' then
                    assert(actual.bearing.aimPoint == points[j], case.name..': bearing identity')
                    for k, state in ipairs(want[3]) do
                        local origin = actual.bearing.firingOrigins[k]
                        assert(origin.lineOfFire.state == state, case.name..': origin '..k)
                        if state ~= NE then assert(origin.lineOfFire.checks == turretSpec.points[j].origins[k].checks) end
                    end
                end
            end
        else
            assert(#row.points == 0, case.name..': skipped search')
        end
    end
    print(case.name..': range='..work[1]..' search='..work[2]..' aim='..work[3]
        ..' origins='..work[4]..' queries='..work[5])
end
for i, case in ipairs(cases) do run(case, i) end
print('production ENGAGEABLE benchmark: ok')
