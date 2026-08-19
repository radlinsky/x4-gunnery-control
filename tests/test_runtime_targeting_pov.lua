-- test_runtime_targeting_pov.lua
-- Auto/direct re-scan cadence, aim-target repaint, POV panel buttons,
-- element panel, target cycling, and Auto-next target scenarios.

local fix = dofile("tests/support/runtime_fixture.lua").load()
local gcMenu = fix.gcMenu
local API    = fix.API
local C      = fix.C

-- Shared clock for getElapsedTime; tests advance it explicitly.
local clock = 100
getElapsedTime = function() return clock end

-- A reusable group used across many rendering and targeting tests.
local grp27 = fix.makeGroup{
    key = "grp27", displayName = "G27",
    members = { { componentID = 27, displayName = "T1", operational = true,
                  cameraSupported = true, componentKey = "27" } },
}

-- Bring the module into a known state.
local ok_init, err_init = pcall(function() gcMenu.onShowMenu() end)
assert(ok_init, "onShowMenu() raised: " .. tostring(err_init))
local sess = API.getSession()
assert(sess ~= nil, "expected a live session after onShowMenu()")

-- Set up the sess23 / grp23 state that sections 25-26 mutate.
-- (Mirrors the setup from section 23 in the base file.)
gcMenu.onShowMenu()
local sess23 = API.getSession()
assert(sess23 ~= nil)
local grp23 = fix.makeGroup{
    key = "grp23", componentID = 20,
    members = { { componentID = 20, displayName = "T1", operational = true,
                  cameraSupported = true, componentKey = "20" } },
}
sess23.groups = { grp23 }
sess23.checkedGroupKeys = { ["grp23"] = true }
sess23.phase = "engaged"
sess23.controlMode = "auto"
sess23.committedBaseline = {}
sess23.cameraMemberID = 20
sess23.aimTargetID = nil
sess23.povMode = "cinematic"
sess23.povAnchor = "turret"
C.IsComponentOperational = function(id) return id == 99 end
GetComponentData = function(component, ...)
    local keys = {...}
    local vals = {}
    for _, k in ipairs(keys) do
        if k == "isenemy" then vals[#vals + 1] = (component == 99)
        elseif k == "ishostile" then vals[#vals + 1] = false
        elseif k == "isfriend" then vals[#vals + 1] = false
        elseif k == "isknown" then vals[#vals + 1] = true
        elseif k == "isradarvisible" then vals[#vals + 1] = true
        elseif k == "maxradarrange" then vals[#vals + 1] = 40000
        elseif k == "isplayerowned" then vals[#vals + 1] = false
        else vals[#vals + 1] = nil
        end
    end
    return unpack(vals)
end
C.GetContextByClass = function(comp, cls, self_) return comp end
GetContainedShips = function() return { 99 } end
GetContainedStations = function() return {} end
C.GetDistanceBetween = function() return 1000 end
GetPlayerContextByClass = function() return 1 end
X4GunneryControlAPI.updateAimTarget()
-- (sess23.aimTargetID is now set; section 25 resets it before its checks)

-- ── 25. auto re-scans on a 5 s cadence; direct holds its target ───────────────
-- Two live candidates. In auto mode the better one (98, nearer) must not be
-- adopted within 5 s of the last scan, and must be adopted once 5 s have
-- passed. In direct mode the ordered target is held however much time passes,
-- but a dead one is replaced at once.
GetContainedShips = function() return { 98, 99 } end
C.IsComponentOperational = function(id) return id == 98 or id == 99 end
GetComponentData = function(component, ...)
    local keys, vals = {...}, {}
    for _, k in ipairs(keys) do
        if k == "isenemy" then vals[#vals + 1] = true
        elseif k == "ishostile" then vals[#vals + 1] = false
        elseif k == "isfriend" then vals[#vals + 1] = false
        elseif k == "isknown" then vals[#vals + 1] = true
        elseif k == "isradarvisible" then vals[#vals + 1] = true
        elseif k == "maxradarrange" then vals[#vals + 1] = 40000
        elseif k == "isplayerowned" then vals[#vals + 1] = false  -- enemies, not player-owned
        else vals[#vals + 1] = nil
        end
    end
    return unpack(vals)
end
C.GetDistanceBetween = function(_, b) return (tostring(b) == "98") and 100 or 5000 end

sess23.povMode = "manual"
sess23.povAnchor = "turret"

sess23.controlMode = "auto"
sess23.aimTargetID = 99
X4GunneryControlAPI.updateAimTarget()   -- arms the 5 s window
sess23.aimTargetID = 99
clock = clock + 1
X4GunneryControlAPI.updateAimTarget()
assert(tostring(sess23.aimTargetID) == "99",
    "auto must not re-scan within 5 s; aimTargetID became " .. tostring(sess23.aimTargetID))
clock = clock + 10
X4GunneryControlAPI.updateAimTarget()
assert(tostring(sess23.aimTargetID) == "98",
    "auto must adopt the better target after 5 s; got " .. tostring(sess23.aimTargetID))

sess23.controlMode = "direct"
sess23.aimTargetID = 99
clock = clock + 600
X4GunneryControlAPI.updateAimTarget()
assert(tostring(sess23.aimTargetID) == "99",
    "direct must hold its target regardless of elapsed time; got " .. tostring(sess23.aimTargetID))
-- What direct does when its target *dies* is the Auto-next Target contract;
-- tests 39 and 41 own it.

-- ── 26. a changed aim target repaints the manual panel ───────────────────────
-- Button `active` states are fixed when the frame is built, so acquiring the
-- first target must rebuild the frame or "Target POV" stays greyed forever.
sess23.controlMode = "auto"
sess23.povMode, sess23.povAnchor = "manual", "turret"
sess23.aimTargetID = nil
C.IsComponentOperational = function(id) return id == 98 or id == 99 end
fix.resetLastFrameProps()
clock = clock + 60
X4GunneryControlAPI.updateAimTarget()
assert(sess23.aimTargetID ~= nil, "precondition: updateAimTarget must pick a target")
assert(fix.getLastFrameProps() ~= nil,
    "acquiring an aim target in manual mode must rebuild the panel frame")

-- ── 27. engaged/direct with targetObjectID creates TWO frames ────────────────
-- The left element panel is only shown when controlMode=="direct" AND
-- session.targetObjectID is set.
gcMenu.onShowMenu()
local sess27 = API.getSession()
assert(sess27 ~= nil, "expected session for two-frame test")
sess27.groups = { grp27 }
sess27.checkedGroupKeys = { ["grp27"] = true }
sess27.phase = "engaged"
sess27.controlMode = "direct"
sess27.committedBaseline = { { kind = "group", contextID = 5, path = "p", group = "g",
    shipID = sess27.shipID, mode = "attack", armed = false } }
sess27.cameraMemberID = 27
sess27.targetObjectID = 500
sess27.aimTargetID = 500
local ok27, err27 = pcall(function() gcMenu.display() end)
assert(ok27, "display() raised in engaged/direct+targetObjectID: " .. tostring(err27))
assert(fix.getFrameCount() == 2,
    "engaged/direct with targetObjectID must create TWO frames; got " .. tostring(fix.getFrameCount()))
-- frame:display() registers a view keyed by layer (helper.lua onFrameHandleView
-- Created / View.registerMenu("Helper" .. layer)). Two frames sharing the
-- default layer 4 means the second silently replaces the first on screen.
local fp = fix.getFrameProps()
assert(fp[1].layer ~= fp[2].layer,
    "the two engaged/direct frames must sit on different layers; both had "
    .. tostring(fp[1].layer))

-- ── 28. engaged/auto creates ONE frame ───────────────────────────────────────
gcMenu.onShowMenu()
local sess28 = API.getSession()
assert(sess28 ~= nil, "expected session for one-frame test")
sess28.groups = { grp27 }
sess28.checkedGroupKeys = { ["grp27"] = true }
sess28.phase = "engaged"
sess28.controlMode = "auto"
sess28.committedBaseline = {}
sess28.cameraMemberID = 27
sess28.aimTargetID = nil
local ok28, err28 = pcall(function() gcMenu.display() end)
assert(ok28, "display() raised in engaged/auto: " .. tostring(err28))
assert(fix.getFrameCount() == 1,
    "engaged/auto must create ONE frame; got " .. tostring(fix.getFrameCount()))

-- ── 29. cycleTarget exposed via TestAPI and changes targetObjectID ────────────
-- Restore the camera stub that test 14 replaced with an error-thrower.
C.SetPlayerCameraTargetView = function() return true end
gcMenu.onShowMenu()
local sess29 = API.getSession()
assert(sess29 ~= nil, "expected session for cycleTarget test")
assert(type(X4GunneryControlAPI.cycleTarget) == "function",
    "X4GunneryControlAPI.cycleTarget must be exposed")
-- Set up a direct session with two candidates accessible via GetContainedShips.
-- GetContainedShips returns 98 and 99, both operational (restored from test 25).
C.IsComponentOperational = function(id) return id == 98 or id == 99 end
GetContainedShips = function() return { 98, 99 } end
GetContainedStations = function() return {} end
GetPlayerContextByClass = function() return 1 end
C.GetContextByClass = function(comp, cls, self_) return comp end
C.GetDistanceBetween = function(_, b) return (tostring(b) == "98") and 100 or 5000 end
GetComponentData = function(component, ...)
    local keys, vals = {...}, {}
    for _, k in ipairs(keys) do
        if k == "isenemy" then vals[#vals + 1] = true
        elseif k == "ishostile" then vals[#vals + 1] = false
        elseif k == "isfriend" then vals[#vals + 1] = false
        elseif k == "isknown" then vals[#vals + 1] = true
        elseif k == "isradarvisible" then vals[#vals + 1] = true
        elseif k == "maxradarrange" then vals[#vals + 1] = 40000
        elseif k == "isplayerowned" then vals[#vals + 1] = false  -- enemy ships, not player-owned
        else vals[#vals + 1] = nil
        end
    end
    return unpack(vals)
end
local grp29 = fix.makeGroup{
    key = "grp29", displayName = "G29",
    members = { { componentID = 27, displayName = "T1", operational = true,
                  cameraSupported = true, componentKey = "27" } },
}
sess29.groups = { grp29 }
sess29.checkedGroupKeys = { ["grp29"] = true }
sess29.phase = "engaged"
sess29.controlMode = "direct"
sess29.committedBaseline = { { kind = "group", contextID = 5, path = "p", group = "g",
    shipID = sess29.shipID, mode = "attack", armed = false } }
sess29.cameraMemberID = 27
-- Candidate 98 is nearer (100m) so it will be first sorted; start at 98.
sess29.targetObjectID = 98
sess29.aimTargetID = 98
-- cycleTarget(1) should move to the second candidate (99).
X4GunneryControlAPI.cycleTarget(1)
local newTarget = API.getSession().targetObjectID
assert(newTarget ~= nil,
    "cycleTarget(1) must set targetObjectID; got nil")
assert(tostring(newTarget) ~= tostring(98),
    "cycleTarget(1) from 98 must change targetObjectID; still " .. tostring(newTarget))

-- ── 30. the panel greys the button for the view already on screen ────────────
-- Regression: entering engaged with a stale povAnchor greyed "Target POV
-- manual" while the camera was actually on the turret.
local function povButton(id) return fix.buttonByText("text:20991:" .. id) end
gcMenu.onShowMenu()
local sess30 = API.getSession()
sess30.groups = { grp27 }
sess30.checkedGroupKeys = { ["grp27"] = true }
sess30.phase = "engaged"
sess30.cameraMemberID = 27
sess30.committedBaseline = { { kind = "group", contextID = 5, path = "p", group = "g",
    shipID = sess30.shipID, mode = "attack", armed = false } }
sess30.controlMode = "auto"
sess30.povAnchor, sess30.povMode = "turret", "manual"
sess30.aimTargetID = 500
gcMenu.display()
assert(povButton(63) and povButton(63).active == false,
    "Turret POV manual must be greyed while it is the current view")
assert(povButton(65) and povButton(65).active == true,
    "Turret POV cinematic must be clickable while the view is manual")
assert(povButton(64) and povButton(64).active == true,
    "Target POV manual must be clickable when an aim target exists")

sess30.povAnchor, sess30.povMode = "target", "cinematic"
gcMenu.display()
assert(povButton(66) and povButton(66).active == false,
    "Target POV cinematic must be greyed while it is the current view")
assert(povButton(63) and povButton(63).active == true,
    "Turret POV manual must be clickable while the view is target cinematic")

-- ── 31. the element panel pins whichever element is being attacked ───────────
sess30.controlMode = "direct"
sess30.povAnchor, sess30.povMode = "turret", "manual"
sess30.targetObjectID = 500
sess30.aimTargetID = 500          -- hull is the engaged element
gcMenu.display()
local function hasPinnedRow()
    for _, entry in ipairs(fix.getCreatedTexts()) do
        if entry.row == "surface_pinned" then return true end
    end
    return false
end
assert(hasPinnedRow(), "engaged hull must render in the fixed pinned section")
sess30.aimTargetID = 501          -- a surface element, not the hull
sess30.surfaceBrowser.pendingReason = "open"
gcMenu.display()
assert(hasPinnedRow(), "engaged surface must render in the fixed pinned section")

-- ── 32. Next/Previous Target grey out with nothing to cycle to ───────────────
-- Cycling is pointless with a single candidate, and there is no candidate list
-- at all outside direct mode. The stubs from test 29 still supply 98 and 99.
-- Advance the clock so the hasMultipleTargets() 1 s TTL memo expires between
-- this display() and the one above.
clock = clock + 2
GetContainedShips = function() return { 98 } end
gcMenu.display()
assert(povButton(75) and povButton(75).active == false,
    "Next Target must be greyed with only one candidate")
assert(povButton(76) and povButton(76).active == false,
    "Previous Target must be greyed with only one candidate")

clock = clock + 2
GetContainedShips = function() return { 98, 99 } end
gcMenu.display()
assert(povButton(75) and povButton(75).active == true,
    "Next Target must be clickable with two candidates")
assert(povButton(76) and povButton(76).active == true,
    "Previous Target must be clickable with two candidates")

sess30.controlMode = "auto"
gcMenu.display()
assert(povButton(75) == nil and povButton(76) == nil,
    "Auto-engage must not offer the target cycling buttons at all")

-- ── 33. leaving direct mode unregisters the element panel's frame ────────────
-- clearDataForRefresh() does not touch menu.frames, so a frame left over from a
-- previous display() stays registered as its own view ("Helper" .. layer) and
-- keeps rendering. Only Helper.clearFrame() unregisters it.
sess30.controlMode = "direct"
sess30.targetObjectID = 500
fix.resetClearedFrames()
gcMenu.display()
assert(#fix.getClearedFrames() == 0, "nothing to clear while the element panel is shown")
sess30.phase = "target_select"
gcMenu.display()
assert(fix.getClearedFrames()[1] == 3,
    "leaving the element panel must clearFrame its layer; cleared "
    .. tostring(fix.getClearedFrames()[1]))

-- ── 39. Auto-next Target on: a dead target takes the turrets along ───────────
-- The old behaviour moved only session.aimTargetID, so the camera followed the
-- next ship while the groups stayed armed against a wreck: the soft target and
-- session.targetObjectID both still named the dead one. Re-engaging is what
-- moves all three together, so assert on targetObjectID, not just the aim.
gcMenu.onShowMenu()
local sess39 = API.getSession()
assert(sess39 ~= nil, "expected session for auto-next test")
assert(sess39.autoNextTarget == true, "Auto-next Target must default to on")
sess39.groups = { grp27 }
sess39.checkedGroupKeys = { ["grp27"] = true }
sess39.phase = "engaged"
sess39.controlMode = "direct"
sess39.committedBaseline = { { kind = "group", contextID = 5, path = "p", group = "g",
    shipID = sess39.shipID, mode = "attack", armed = false } }
sess39.cameraMemberID = 27
sess39.targetObjectID = 500
sess39.aimTargetID = 500
sess39.povAnchor, sess39.povMode = "turret", "manual"

GetPlayerContextByClass = function() return 1 end
GetContainedShips = function() return { 98 } end
GetContainedStations = function() return {} end
C.GetContextByClass = function(comp) return comp end
C.GetDistanceBetween = function() return 1000 end
C.SetSofttarget = function() return true end
C.SetPlayerCameraTargetView = function() return true end
GetComponentData = function(component, ...)
    local keys, vals = {...}, {}
    for _, k in ipairs(keys) do
        if k == "isenemy" then vals[#vals + 1] = true
        elseif k == "isknown" then vals[#vals + 1] = true
        elseif k == "isradarvisible" then vals[#vals + 1] = true
        elseif k == "maxradarrange" then vals[#vals + 1] = 40000
        elseif k == "isplayerowned" then vals[#vals + 1] = false  -- enemy ship, not player-owned
        else vals[#vals + 1] = false
        end
    end
    return unpack(vals)
end
-- The engaged target 500 is destroyed; 98 is the only survivor.
C.IsComponentOperational = function(cid) return tostring(cid) == "98" end
X4GunneryControlAPI.updateAimTarget()
assert(tostring(sess39.aimTargetID) == "98",
    "auto-next must move the aim to the survivor; got " .. tostring(sess39.aimTargetID))
assert(tostring(sess39.targetObjectID) == "98",
    "auto-next must re-engage rather than only move the camera; targetObjectID stayed "
    .. tostring(sess39.targetObjectID))
assert(sess39.phase == "engaged",
    "auto-next must stay engaged; phase became " .. tostring(sess39.phase))

-- ── 40. engaged/direct session toggles have independent defaults ────────────
gcMenu.display()
assert(#fix.getCreatedCheckBoxes() == 2,
    "the engaged/direct panel must offer Auto-next and surface auto-refresh; got "
    .. tostring(#fix.getCreatedCheckBoxes()))
assert(fix.getCreatedCheckBoxes()[1].checked == true,
    "the Auto-next Target checkbox must be checked while session.autoNextTarget is on")
assert(fix.getCreatedCheckBoxes()[2].checked == false,
    "surface auto-refresh must default unchecked")

-- ── 41. Auto-next Target off: a dead target returns to the picker ────────────
-- Reset the view first: one Esc's worth of state, so whatever cinematic was on
-- screen is gone and the player lands back on the manual Turret POV before the
-- target browser reopens.
sess39.autoNextTarget = false
sess39.phase = "engaged"
sess39.aimTargetID = 500
sess39.targetObjectID = 500
sess39.povAnchor, sess39.povMode = "target", "cinematic"
X4GunneryControlAPI.updateAimTarget()
assert(sess39.phase == "target_select",
    "with auto-next off a dead target must reopen the target browser; phase is "
    .. tostring(sess39.phase))
assert(sess39.povAnchor == "turret" and sess39.povMode == "manual",
    "with auto-next off the view must reset to manual Turret POV; got "
    .. tostring(sess39.povAnchor) .. "/" .. tostring(sess39.povMode))


print("runtime targeting pov tests passed")
