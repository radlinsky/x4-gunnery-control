-- Drive the asynchronous production checks with small synthetic MD replies.
local M = {}
function M.install()
    X4GunneryAimPointMap.begin = function()
        return function() return {points={{id=1,c={1,2,3},r=0.25}}} end
    end
    X4GunneryTurretBearing.evaluate = function(_, point)
        return {aimPoint=point,state='CAN AIM',firingOrigins={{position={0,0,0}}}}
    end
end
function M.finish(fix, request, engageable)
    local desired = type(engageable)=="number" and engageable or (engageable and #request.aimMap.rows or 0)
    local map = request.aimMap
    if not map or not request.pending then return end
    for index, row in ipairs(map.rows) do
        if row.range == 'NOT_EVALUATED' then
            fix.fireEvent('X4GunneryControl.EngageabilityRange',
                'x4gcr:'..map.token..':'..row.weapon..':'..(index<=desired and '1' or '2'))
        end
    end
    if desired==0 or not request.pending then return end
    fix.fireEvent('X4GunneryControl.AimPointBox',
        'x4gcapb:'..map.token..':1:0:0:0:10000:10000:10000')
    local entries = {}
    for _, row in ipairs(map.rows) do
        if row.range == 'IN RANGE' then
            entries[#entries+1] = row.weapon..':1:1000000000:2000000000:3000000000:0:0:0'
        end
    end
    fix.fireEvent('X4GunneryControl.AimPointBearing',
        'x4gcapc:'..map.token..':1|'..table.concat(entries,'|'))
    for _, row in ipairs(map.rows) do
        if row.range == 'IN RANGE' then
            fix.fireEvent('X4GunneryControl.AimPointLineOfFire',
                'x4gcapl:'..map.token..':'..row.weapon..':1:1:1:1')
        end
    end
end
return M
