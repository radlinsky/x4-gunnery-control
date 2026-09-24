local geometry = X4GunneryTurretBearingGeometry
local pi, sin, cos, atan2, sqrt, abs = math.pi, math.sin, math.cos, math.atan2, math.sqrt, math.abs
local tau, zeroing, zenith, snap = 2 * math.pi, 1e-3, 1e-4, 1e-4
local zero = {0, 0, 0}

local function add(a, b) return {a[1]+b[1], a[2]+b[2], a[3]+b[3]} end
local function sub(a, b) return {a[1]-b[1], a[2]-b[2], a[3]-b[3]} end
local function norm(a) return sqrt(a[1]^2+a[2]^2+a[3]^2) end
local function vmul(v, m)
    return {v[1]*m[1][1]+v[2]*m[2][1]+v[3]*m[3][1],
        v[1]*m[1][2]+v[2]*m[2][2]+v[3]*m[3][2],
        v[1]*m[1][3]+v[2]*m[2][3]+v[3]*m[3][3]}
end
local function mmul(a, b) return {vmul(a[1],b), vmul(a[2],b), vmul(a[3],b)} end
local function transpose(m) return {{m[1][1],m[2][1],m[3][1]}, {m[1][2],m[2][2],m[3][2]}, {m[1][3],m[2][3],m[3][3]}} end
local function compose(a, b) return {t=add(vmul(a.t,b.R),b.t), R=mmul(a.R,b.R)} end
local function rotation(axis, a)
    local c, s = cos(a), sin(a)
    if axis == 'x' then return {{1,0,0},{0,c,-s},{0,s,c}} end
    if axis == 'y' then return {{c,0,-s},{0,1,0},{s,0,c}} end
    return {{c,-s,0},{s,c,0},{0,0,1}}
end
local function joint(axis, a) return {t=zero,R=rotation(axis,a)} end
local function wrap(a) return (a+pi)%tau-pi end
local function inArc(a, limits)
    if not limits then return true end
    local deg = math.floor(math.deg(wrap(a))*10000+0.5)/10000
    return deg >= limits[1] and deg <= limits[2]
end
local function clamp(a, limits)
    if inArc(a,limits) then return a end
    local lo, hi = math.rad(limits[1]), math.rad(limits[2])
    if abs(wrap(a-lo)) <= abs(wrap(a-hi)) then return lo end
    return hi
end
local function muzzle(g, leaf, root) return compose(g.L,compose(joint(g.leaf.axis,leaf),compose(g.G,compose(joint(g.root.axis,root),g.H)))).t end

local function pmul(p,q)
    return {p[1]*q[1]+(p[2]*q[2]+p[3]*q[3])/2,
        p[1]*q[2]+p[2]*q[1],p[1]*q[3]+p[3]*q[1],
        (p[2]*q[2]-p[3]*q[3])/2,(p[2]*q[3]+p[3]*q[2])/2}
end
local function padd(...)
    local out={0,0,0,0,0}
    for _,p in ipairs({...}) do for i=1,5 do out[i]=out[i]+(p[i] or 0) end end
    return out
end
local function pscale(p,k) local out={} for i=1,5 do out[i]=(p[i] or 0)*k end return out end

local function ca(a,b) return {a[1]+b[1],a[2]+b[2]} end
local function cs(a,b) return {a[1]-b[1],a[2]-b[2]} end
local function cm(a,b) return {a[1]*b[1]-a[2]*b[2],a[1]*b[2]+a[2]*b[1]} end
local function cd(a,b) local d=b[1]^2+b[2]^2 return {(a[1]*b[1]+a[2]*b[2])/d,(a[2]*b[1]-a[1]*b[2])/d} end
local function cn(a) return sqrt(a[1]^2+a[2]^2) end
local function polyRoots(coeff)
    local big=0 for _,c in ipairs(coeff) do big=math.max(big,cn(c)) end
    if big==0 then return {} end
    while #coeff>1 and cn(coeff[1])<=1e-14*big do table.remove(coeff,1) end
    while #coeff>1 and cn(coeff[#coeff])<=1e-14*big do table.remove(coeff) end
    local n=#coeff-1
    if n==0 then return {} end
    local lead=coeff[1]
    for i=1,#coeff do coeff[i]=cd(coeff[i],lead) end
    local roots={}
    for k=0,n-1 do local a=0.4+2.1*k roots[k+1]={cos(a),sin(a)} end
    for _=1,500 do
        local worst=0
        for i,r in ipairs(roots) do
            local p,dp={0,0},{0,0}
            for _,c in ipairs(coeff) do dp=ca(cm(dp,r),p);p=ca(cm(p,r),c) end
            if cn(p)>0 then
                local ratio=cn(dp)>0 and cd(p,dp) or p
                local sum={0,0}
                for j,o in ipairs(roots) do if i~=j and cn(cs(r,o))>0 then sum=ca(sum,cd({1,0},cs(r,o))) end end
                local step=cd(ratio,cs({1,0},cm(ratio,sum)))
                roots[i]=cs(r,step)
                worst=math.max(worst,cn(step))
            end
        end
        if worst<1e-15 then break end
    end
    return roots
end
local function trigRoots(p)
    local a0,a1,b1,a2,b2=p[1],p[2],p[3],p[4],p[5]
    local roots=polyRoots({{a2/2,-b2/2},{a1/2,-b1/2},{a0,0},{a1/2,b1/2},{a2/2,b2/2}})
    local out={}
    for _,z in ipairs(roots) do if abs(cn(z)-1)<1e-6 then out[#out+1]=atan2(z[2],z[1]) end end
    return out
end
local function extend(a,b) for _,v in ipairs(b) do a[#a+1]=v end end

local function resting(g,pt,swap)
    local G,H,L=g.G,g.H,g.L
    local aim=vmul(L.R[3],G.R)
    local beta=swap and atan2(aim[1],aim[2]) or atan2(aim[1],aim[3])
    local tg,th,rh,target=G.t,H.t,H.R,pt
    if swap then
        local function sv(v) return {v[1],v[3],v[2]} end
        tg,th,target=sv(tg),sv(th),sv(target)
        rh={sv(H.R[1]),sv(H.R[3]),sv(H.R[2])}
    end
    local rht=transpose(rh)
    local q=sub(target,th)
    local e0=vmul({0,tg[2],0},rh)
    local ec=vmul({tg[1],0,tg[3]},rh)
    local es=vmul({tg[3],0,-tg[1]},rh)
    local e={}
    for i=1,3 do e[i]={q[i]-e0[i],-ec[i],-es[i]} end
    local sq={pmul(e[1],e[1]),pmul(e[2],e[2]),pmul(e[3],e[3])}
    local norm2=padd(sq[1],sq[2],sq[3])
    local cosA,sinA={0,cos(beta),-sin(beta)},{0,sin(beta),cos(beta)}
    local events={0,-pi}
    for i=1,3 do extend(events,trigRoots(padd(sq[i],pscale(norm2,-zeroing^2)))) end
    for mask=0,7 do
        local z={}
        for i=1,3 do z[i]=math.floor(mask/2^(i-1))%2==1 and {0,0,0} or e[i] end
        local w={}
        for _,j in ipairs({1,3}) do
            w[#w+1]=padd(pscale(z[1],rht[1][j]),pscale(z[2],rht[2][j]),pscale(z[3],rht[3][j]))
        end
        local zn2={0,0,0,0,0}
        for i=1,3 do if math.floor(mask/2^(i-1))%2==0 then zn2=padd(zn2,sq[i]) end end
        extend(events,trigRoots(padd(pmul(w[1],cosA),pscale(pmul(w[2],sinA),-1))))
        for _,wj in ipairs(w) do extend(events,trigRoots(padd(pmul(wj,wj),pscale(zn2,-zenith^2)))) end
    end
    for i,y in ipairs(events) do events[i]=wrap(y) end
    table.sort(events)
    local points={events[1]}
    for i=2,#events do if events[i]-points[#points]>1e-9 then points[#points+1]=events[i] end end
    if #points>1 and points[1]+tau-points[#points]<=1e-9 then table.remove(points) end
    local function state(y)
        local c,s=cos(y),sin(y)
        local d,mask={},{}
        for i=1,3 do d[i]=e[i][1]+e[i][2]*c+e[i][3]*s end
        local n=norm(d)
        for i=1,3 do mask[i]=abs(d[i])<zeroing*n end
        return mask,d
    end
    local function dhFor(mask,d)
        local z={}
        for i=1,3 do z[i]=mask[i] and 0 or d[i] end
        return vmul(z,rht),norm(z)
    end
    local function gsign(y,mask,d)
        local dh,n=dhFor(mask,d)
        if abs(dh[1])<zenith*n and abs(dh[3])<zenith*n then return true,-sin(y) end
        local a=y+beta
        return false,dh[1]*cos(a)-dh[3]*sin(a)
    end
    local function slope(y,mask,zen)
        if zen then return wrap(-y),0 end
        local c,s=cos(y),sin(y)
        local z,dz={},{}
        for i=1,3 do
            z[i]=mask[i] and 0 or e[i][1]+e[i][2]*c+e[i][3]*s
            dz[i]=mask[i] and 0 or e[i][3]*c-e[i][2]*s
        end
        local dh,ddh=vmul(z,rht),vmul(dz,rht)
        local horizontal=dh[1]^2+dh[3]^2
        if horizontal==0 then return wrap(atan2(dh[1],dh[3])-beta-y),math.huge end
        return wrap(atan2(dh[1],dh[3])-beta-y),(dh[3]*ddh[1]-dh[1]*ddh[3])/horizontal
    end
    local arcs={}
    for k,y in ipairs(points) do
        local nextY=points[k+1] or points[1]+tau
        local mid=(y+nextY)/2
        local mask,d=state(mid)
        local zen,h=gsign(mid,mask,d)
        arcs[k]={mask=mask,zen=zen,sign=h>0 and 1 or h<0 and -1 or 0}
    end
    local out={}
    for k,y in ipairs(points) do
        local left,right=arcs[k-1] or arcs[#arcs],arcs[k]
        if left.sign>0 and right.sign<0 then
            local gl,sl=slope(y,left.mask,left.zen)
            local gr,sr=slope(y,right.mask,right.zen)
            if abs(gl)<snap and abs(gr)<snap and abs(sl)<1 and abs(sr)<1 then out[#out+1]=y end
        end
    end
    return out
end

local function request(axis,u,aim)
    local i,j=axis=='x' and 2 or 1,axis=='x' and 3 or axis=='y' and 3 or 2
    if abs(u[i])<zenith and abs(u[j])<zenith then return 0 end
    return atan2(u[i],u[j])-atan2(aim[i],aim[j])
end
local function fixed(g,pt)
    local pivot=compose(g.G,g.H).t
    local d=sub(pt,pivot)
    local n=norm(d)
    if n==0 then return nil,{} end
    for i=1,3 do d[i]=abs(d[i])<zeroing*n and 0 or d[i]/n end
    n=norm(d)
    for i=1,3 do d[i]=d[i]/n end
    local rootReq=request(g.root.axis,vmul(d,transpose(g.H.R)),mmul(g.L.R,g.G.R)[3])
    local root=clamp(rootReq,g.root.limits)
    local frame=mmul(g.G.R,mmul(rotation(g.root.axis,root),g.H.R))
    local leafReq=request(g.leaf.axis,vmul(d,transpose(frame)),g.L.R[3])
    local leaf=clamp(leafReq,g.leaf.limits)
    if root==rootReq and leaf==leafReq then return true,{muzzle(g,leaf,root)} end
    return false,{}
end
local function rotating(g,pt)
    local clocks=resting(g,pt,g.root.axis=='z')
    if #clocks==0 then return false,{} end
    local origins,scored={},0
    for _,clock in ipairs(clocks) do
        local frame=compose(g.G,compose(joint(g.root.axis,clock),g.H))
        local d=sub(pt,frame.t)
        local n=norm(d)
        if n>0 then
            scored=scored+1
            for i=1,3 do if abs(d[i])<zeroing*n then d[i]=0 end end
            local x=wrap(request('x',vmul(d,transpose(frame.R)),g.L.R[3]))
            if inArc(x,g.leaf.limits) then origins[#origins+1]=muzzle(g,x,clock) end
        end
    end
    if scored==0 then return nil,{} end
    return #origins>0,origins
end

local function evaluate(macro,aimPoint,turretPoint,currentBarrel)
    local g=geometry[macro]
    local result={aimPoint=aimPoint, firingOrigins={}}
    if not g then
        result.state='CAN AIM'
        result.firingOrigins[1]={position=currentBarrel,source='current-barrelposition-fallback'}
        return result
    end
    local can,origins
    if g.class=='ordinary_xy' or g.class=='rotation_z' then can,origins=rotating(g,turretPoint)
    else can,origins=fixed(g,turretPoint) end
    result.state=can==nil and 'UNKNOWN' or can and 'CAN AIM' or 'CANNOT BEAR'
    for _,position in ipairs(origins) do
        result.firingOrigins[#result.firingOrigins+1]={position=position,source='geometry-predicted'}
    end
    return result
end

X4GunneryTurretBearing={evaluate=evaluate}
