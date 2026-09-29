-- Exercise production projection, transport, picking, lifecycle and shape ownership.
local fix = dofile("tests/support/runtime_fixture.lua").load()
local H, C = X4GunneryHologram, fix.C
local ffi = require("ffi")
ffi.new = function() return { offset = {} } end
local now, mx, my, picked, clicks = 0, 0, 0, 1, 0
GetCurRealTime = function() return now end
GetLocalMousePosition = function() return mx, my end
GetRenderTargetMousePosition = function() return 0, 0 end
GetRenderTargetTexture = function() return "test" end
GetSize = function() return 400, 200 end
IsType = function(_, kind) return kind == "rendertarget" end
Helper.getRelativeRenderTargetSize = function() return -1, -0.5, 0, 1 end
Helper.callLoadoutFunction = function(_, _, fn) fn({}) end
Helper.viewWidth, Helper.viewHeight = 1600, 400
local camera = { yaw = 0, pitch = 0, distance = 1 }
local removed, shapeID, draws = 0, 0, {}
local live = { [9999] = true } -- A foreign rectangle must survive every refresh.
local function color(r,g,b) return { r=r, g=g, b=b, a=100 } end
Color.text_inactive, Color.icon_normal = color(100,100,100), color(255,255,255)
Color.text_warning, Color.text_positive = color(255,150,0), color(0,255,0)
Helper.drawLine = function(a,b,thickness,_,c)
    shapeID = shapeID + 1
    live[shapeID] = true
    draws[#draws+1] = { color=c, a=a, b=b }
    return shapeID
end
HideRect = function(id) assert(live[id], "hide only a live owned shape"); live[id] = nil end
C.AddHoloMap = function(_,_,_,_,_,aspect) assert(aspect == 2); return 7 end
C.RemoveHoloMap = function() removed = removed + 1 end
C.GetMapState = function(_, state)
    state.offset.yaw, state.offset.pitch = camera.yaw, camera.pitch
    state.cameradistance = camera.distance
end
C.SetMapState = function(_, state)
    camera.yaw, camera.pitch, camera.distance = state.offset.yaw, state.offset.pitch, state.cameradistance
end
C.GetPickedMapMacroSlot = function(_,_,_,_,_,out) out.upgradetype, out.slot = "turret", picked; return true end
C.GetNumUpgradeSlots = function() return 2 end
C.GetUpgradeSlotCurrentComponent = function(_,_,slot) return 100 + slot end
C.IsComponentClass = function(component,kind) return component == 102 and kind == "missileturret" end
local group = { key="a", positionLabel="Front", members={
    {componentID=101,displayName="Beam",operational=true,cameraSupported=true},
    {componentID=102,displayName="Missile",operational=true,cameraSupported=true},
} }
local session = { shipID=5, aimTargetID=20, groups={group}, checkedGroupKeys={a=true} }
local frame = Helper.createFrameHandle(fix.gcMenu,{layer=3})
local function mount(combat)
    H.mount(fix.gcMenu,frame,session,{x=0,y=0,w=400,h=200},combat,function(member, g)
        assert(member == group.members[picked] and g == group); clicks=clicks+1
    end)
    H.viewCreated(3, "widget")
end
local function latestOpen()
    for i=#fix.uiTriggeredEvents,1,-1 do
        local e=fix.uiTriggeredEvents[i]
        if e.screen == "X4GunneryHologram" and e.control == "open" then return e.params.nonce end
    end
end
local function reply(nonce,data) H.receive(nil,"x4gh1:"..nonce..":"..data) end
local function tick() now=now+0.1; H.update() end
local function countOwned()
    local n=0; for id in pairs(live) do if id~=9999 then n=n+1 end end; return n
end
local state = {offset={yaw=0,pitch=0},cameradistance=1}
local x,y = H.project({x=75,y=75,z=0},state,1000,2)
assert(math.abs(x-0.05)<1e-12 and math.abs(y-0.1)<1e-12, "projection uses vertical FOV and actual aspect")
assert(H.project({x=0,y=0,z=-1100},state,1000,2)==nil, "reject points behind camera")
assert(H.project({x=0,y=0,z=0},state,0,2)==nil, "missing geometry must not divide by zero")
mount(true)
local nonce=latestOpen()
reply(nonce,"size:2000m")
reply(nonce,"position:1.0:75.125m:0m:0m")
reply(nonce,"position:2.0:-75.125m:0m:0m")
reply(nonce,"activity:21")
tick()
assert(countOwned()==12, "ordinary hit reticle and missile firing burst are distinct")
assert(draws[1].color.g==255 and draws[#draws].color.r==255, "hit green and firing orange")
local drawCount=#draws
tick()
assert(#draws==drawCount, "unchanged view does not redraw static shapes")
local oldRemoved=removed
H.viewCreated(3,"replacement-widget"); tick()
assert(removed==oldRemoved+1 and countOwned()==12, "recreated widget rebinds its map without losing activity")
H.mouseDown(); now=now+0.05; H.select()
assert(clicks==1, "short stationary click dispatches the exact turret and group")
H.mouseDown(); mx=10; H.select()
assert(clicks==1, "rotation drag must not toggle or change camera")
mx=0
H.refresh(); mount(true)
assert(latestOpen()==nonce, "cosmetic rebuild retains geometry and activity subscription")
tick()
assert(countOwned()==12 and live[9999], "rebuild retains activity and foreign shapes")
reply(nonce,"activity:22"); tick()
assert(countOwned()==14, "missile hit code falls back to idle, never a hit reticle")
reply(nonce,"activity:2"); tick()
assert(countOwned()==14, "reject incomplete snapshots atomically")
camera.yaw,camera.pitch,camera.distance=0.7,0.3,0.85
H.close()
assert(countOwned()==0 and live[9999] and removed>=1, "teardown releases only owned resources")
camera.yaw,camera.pitch,camera.distance=0,0,1
mount(false); tick()
assert(camera.yaw==0.7 and camera.distance==0.85, "ship camera persists across sessions/views")
reply(nonce,"size:2m"); reply(nonce,"position:1:0:0:0"); tick()
assert(countOwned()==0, "late geometry from the previous subscription cannot render")
H.close()
-- Crowded unselected roster: every turret receives a coarse marker within budget.
local many={}
for i=1,101 do many[i]={componentID=100+i,displayName="Turret"} end
group.members=many
session.checkedGroupKeys={}
C.GetNumUpgradeSlots=function() return 101 end
camera.yaw,camera.pitch,camera.distance=0,0,1
session.shipID=6
mount(false)
nonce=latestOpen()
reply(nonce,"size:2000")
for i=1,101 do reply(nonce,"position:"..i..":0:0:0") end
tick()
assert(countOwned()==707 and live[9999], "all 101 turrets get a marker inside the shared pool")
local current=latestOpen()
session.checkedGroupKeys={a=true}; mount(true)
assert(latestOpen()~=current, "selection/combat changes replace the MD subscription")
H.close()
print("gunnery hologram tests passed")
