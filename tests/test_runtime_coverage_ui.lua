local fix = dofile("tests/support/runtime_fixture.lua").load()
-- readGroups always builds group.key with State.groupKey, and seedBaseline keys
-- staged by that same derivation. Use the real form here so the fixture cannot
-- pass while the production key derivations disagree.
local groupKey = X4GunneryState.groupKey(5, "p", "g")
local group = {
    key = groupKey, kind = "group", contextID = 5, path = "p", group = "g",
    componentID = 27, displayName = "Group", operationalCount = 1, totalCount = 1, mode = "attack", armed = false,
    members = { { componentID = 27, displayName = "Turret", operational = true, cameraSupported = true } },
}
fix.gcMenu.onShowMenu()
local session = fix.API.getSession()
session.groups, session.checkedGroupKeys = { group }, { [groupKey] = true }
session.phase, session.controlMode, session.cameraMemberID = "engaged", "auto", 27
fix.C.GetExternalTargetViewComponent = function() return 27 end
fix.gcMenu.display()
for _, id in ipairs({ 71, 72 }) do
    local entry = fix.buttonByText("text:20991:" .. id)
    assert(entry and entry.handlers and type(entry.handlers.onClick) == "function",
        "cycle turret button must expose its production handler")
    local checkpoint = fix.callbackCheckpoint()
    entry.handlers.onClick()
    assert(fix.callbackCheckpoint() > checkpoint,
        "cycle turret button " .. tostring(id) .. " must schedule its camera gate")
end

-- Deliverable D: the same commit point is available on the engaged panel, in
-- both Auto and Direct. menu.display returns early for the engaged phase, so a
-- console-only row would never render here.
--
-- buttonByText returns the FIRST match. A repaint can leave more than one entry
-- with the same label in the fixture's list, and only the newest one's handlers
-- belong to the live frame, so always take the latest match before clicking.
local function latestButton(fixture, label)
    local found
    for _, entry in ipairs(fixture.getCreatedButtons()) do
        if entry.text == label then found = entry end
    end
    return found
end
for _, controlMode in ipairs({ "auto", "direct" }) do
    local fixE = dofile("tests/support/runtime_fixture.lua").load()
    local key = X4GunneryState.groupKey(5, "p", "g")
    local grpE = {
        key = key, kind = "group", contextID = 5, path = "p", group = "g",
        componentID = 27, displayName = "G", operationalCount = 1, totalCount = 1,
        mode = "attack", armed = false,
        members = { { componentID = 27, displayName = "T", operational = true, cameraSupported = true } },
    }
    fixE.gcMenu.onShowMenu()
    local sessE = fixE.API.getSession()
    sessE.groups, sessE.checkedGroupKeys, sessE.cameraMemberID = { grpE }, { [key] = true }, 27
    sessE.phase, sessE.controlMode = "engaged", controlMode
    X4GunneryState.seedBaseline(sessE, { grpE })

    fixE.gcMenu.display()
    local cleanBtn = latestButton(fixE, "text:20991:83")
    assert(cleanBtn ~= nil,
        "engaged/" .. controlMode .. " panel must render the Update turret behavior button")
    assert(cleanBtn.active == false,
        "engaged/" .. controlMode .. ": Update must be greyed while staged matches the baseline")

    X4GunneryState.stageMode(sessE, key, "defend", grpE.armed)
    fixE.gcMenu.display()
    local dirtyBtn = latestButton(fixE, "text:20991:83")
    assert(dirtyBtn.active == true,
        "engaged/" .. controlMode .. ": Update must be active once staged diverges")

    -- Capture the turret write on the C table the loaded module actually holds.
    -- Each fixture load() builds a fresh C, and gunnery_control binds ffi.C once
    -- at load, so a later fixture's .C is not the one production calls through.
    local liveC = require("ffi").C
    local writesE = {}
    local origMode = rawget(liveC, "SetTurretGroupMode2")
    liveC.SetTurretGroupMode2 = function(_, _, _, _, mode) writesE[#writesE + 1] = tostring(mode) end
    dirtyBtn.handlers.onClick()
    liveC.SetTurretGroupMode2 = origMode
    assert(#writesE == 1 and writesE[1] == "defend",
        "engaged/" .. controlMode .. ": Update must push the staged mode immediately; wrote "
        .. table.concat(writesE, ","))
    assert(sessE.committedBaseline[1].mode == "defend",
        "engaged/" .. controlMode .. ": Update must advance the committed baseline")
    assert(not X4GunneryState.isStagedDirty(sessE),
        "engaged/" .. controlMode .. ": Update must leave the session clean")
end

-- The engaged panel's stand-up button. It used to read "Cease Engagement" and
-- drop back to the console via restoreDirect + returnToConsole; revert is now
-- bound to leaving the chair, so it routes to leaveChair and carries the same
-- label as the console's own Get Up button (id 14) because it is the same action.
do
    local fixC = dofile("tests/support/runtime_fixture.lua").load()
    local key = X4GunneryState.groupKey(5, "p", "g")
    local grpC = {
        key = key, kind = "group", contextID = 5, path = "p", group = "g",
        componentID = 27, displayName = "G", operationalCount = 1, totalCount = 1,
        mode = "attack", armed = false,
        members = { { componentID = 27, displayName = "T", operational = true, cameraSupported = true } },
    }
    fixC.gcMenu.onShowMenu()
    local sessC = fixC.API.getSession()
    sessC.groups, sessC.checkedGroupKeys, sessC.cameraMemberID = { grpC }, { [key] = true }, 27
    sessC.phase, sessC.controlMode = "engaged", "direct"
    X4GunneryState.seedBaseline(sessC, { grpC })
    fixC.gcMenu.display()

    local ceaseBtn = latestButton(fixC, "text:20991:14")
    assert(ceaseBtn and ceaseBtn.handlers and ceaseBtn.handlers.onClick,
        "engaged/direct panel must render a clickable Get Up button")
    ceaseBtn.handlers.onClick()
    assert(fixC.API.getSession() == nil,
        "the engaged panel's Get Up must stand the player up, not return to the console")
end

-- restoreDirect's deferred read-back loop. The engine's mode read-back lags the
-- write, so the check is deferred half a second and logs whatever still fails to
-- match. Auto-engage is the reachable route that runs restoreDirect and keeps
-- the session alive; every stand-up route discards it, and the epoch guard then
-- makes the callback bail before this loop.
do
    local fixR = dofile("tests/support/runtime_fixture.lua").load()
    local key = X4GunneryState.groupKey(5, "p", "g")
    local grpR = {
        key = key, kind = "group", contextID = 5, path = "p", group = "g",
        componentID = 27, displayName = "G", operationalCount = 1, totalCount = 1,
        mode = "attack", armed = false,
        members = { { componentID = 27, displayName = "T", operational = true, cameraSupported = true } },
    }
    fixR.gcMenu.onShowMenu()
    local sessR = fixR.API.getSession()
    sessR.groups, sessR.checkedGroupKeys, sessR.cameraMemberID = { grpR }, { [key] = true }, 27
    X4GunneryState.seedBaseline(sessR, { grpR })
    -- refresh() inside the callback re-reads groups off the stubbed engine, which
    -- reports none, so every baseline entry comes back unresolved and the
    -- mismatch branch runs. That is the branch worth covering: a silent failure
    -- to restore is exactly what leaves the player with a silently altered ship.
    local markR = fixR.callbackCheckpoint()
    local autoBtn = latestButton(fixR, "text:20991:68")
    assert(autoBtn and autoBtn.handlers and autoBtn.handlers.onClick,
        "console must render a clickable Auto-engage button")
    autoBtn.handlers.onClick()
    fixR.drainCallbacksSince(markR)
    local sawMismatch = false
    for _, line in ipairs(fixR.getCapturedLog()) do
        if string.find(line, "post-restore readback mismatch", 1, true) then sawMismatch = true end
    end
    assert(sawMismatch,
        "an unresolvable group must be reported after the deferred read-back, "
        .. "not swallowed")
end

-- TestAPI.isDirectControlActive covers lines 1078-1079.
fix.gcMenu.onShowMenu()
local sess3 = fix.API.getSession()
assert(not fix.API.isDirectControlActive(), "isDirectControlActive: false for console session")
sess3.phase = "engaged"
sess3.controlMode = "direct"
assert(fix.API.isDirectControlActive(), "isDirectControlActive: true for engaged/direct")
sess3.phase = "target_select"
assert(fix.API.isDirectControlActive(), "isDirectControlActive: true for target_select/direct")
sess3.phase = "console"
assert(not fix.API.isDirectControlActive(), "isDirectControlActive: false for console/direct")

-- restoreDirect deferred callback (lines 462-463, 468, 471-472): trigger via
-- a target_select close (session stays alive, epoch unchanged, callback proceeds).
-- Set up a baseline entry that refresh() cannot find to hit the mismatch branch.
do
    local fix4 = dofile("tests/support/runtime_fixture.lua").load()
    fix4.gcMenu.onShowMenu()
    local sess4 = fix4.API.getSession()
    local grp4key = X4GunneryState.groupKey(5, "p4", "g4")
    local grp4 = { key = grp4key, kind = "group", contextID = 5, path = "p4", group = "g4",
        componentID = 28, displayName = "G4", operationalCount = 1, totalCount = 1,
        mode = "attack", armed = false,
        members = { { componentID = 28, displayName = "T4", operational = true, cameraSupported = true } } }
    sess4.groups = { grp4 }
    sess4.checkedGroupKeys = { [grp4key] = true }
    sess4.phase = "target_select"
    sess4.controlMode = "direct"
    -- Set committedBaseline with a group entry. After onCloseElement, restoreDirect
    -- is called, and the deferred callback fires while the session is still alive.
    -- refresh() reads 0 groups (fixture default), so findSnapshotGroup returns nil -> mismatch.
    sess4.committedBaseline = { {
        kind = "group", shipID = sess4.shipID, contextID = 5,
        path = "p4", group = "g4", mode = "attack", armed = false,
    } }
    local mark4 = fix4.callbackCheckpoint()
    -- target_select onCloseElement calls restoreDirect then returnToConsole; session stays alive.
    fix4.gcMenu.onCloseElement("close")
    -- Drain the deferred callback to hit the mismatch loop (lines 462-463, 468, 471-472).
    fix4.drainCallbacksSince(mark4)
end

-- Console display with staged values covers isDirectedGroup (342-344) and the
-- staged-row rendering (1756-1775). Use direct controlMode to exercise the
-- isDirectedGroup "directed" branch. Must fake isplayerowned so the group list renders.
local fix2 = dofile("tests/support/runtime_fixture.lua").load()
fix2.gcMenu.onShowMenu()
local sess2 = fix2.API.getSession()
sess2.groups = { group }
sess2.checkedGroupKeys = { [groupKey] = true }
sess2.phase = "console"
sess2.controlMode = "direct"
-- onShowMenu seeded against the fixture's empty group list, so seed again over
-- the group this test installs. That gives committedBaseline something to
-- compare against and starts the session clean, as a real sit-down would.
X4GunneryState.seedBaseline(sess2, { group })
X4GunneryState.stageMode(sess2, groupKey, "defend", group.armed)
-- Make the ship appear player-owned so the console group loop runs.
GetComponentData = function(_, key) if key == "isplayerowned" then return true end return nil end
fix2.gcMenu.display()
-- The Update turret behavior button (id 83) must be rendered.
local updateBtn = fix2.buttonByText("text:20991:83")
assert(updateBtn ~= nil, "Update turret behavior button must be rendered in console display")
-- Exercise the dropdown onDropDownConfirmed handler (line 1769): covers stageMode closure.
local dropDowns = fix2.getCreatedDropDowns()
for _, dd in ipairs(dropDowns) do
    if dd.handlers and dd.handlers.onDropDownConfirmed then
        dd.handlers.onDropDownConfirmed(nil, "defend")  -- covers line 1769
        break
    end
end
-- Exercise the armed button onClick (line 1774): covers the stageArmed closure.
-- Match on the armed labels (ids 6/7) rather than "any button that is not the
-- Update one": identity comparison against a stale handle silently selected the
-- Update button instead and consumed the dirty state this block sets up.
local armedLabels = { ["text:20991:6"] = true, ["text:20991:7"] = true }
local armedClicked = false
for _, btn in ipairs(fix2.getCreatedButtons()) do
    if armedLabels[btn.text] and btn.handlers and btn.handlers.onClick then
        btn.handlers.onClick()  -- covers line 1774
        armedClicked = true
        break
    end
end
assert(armedClicked, "console group row must expose a clickable armed toggle")

-- The console row handlers above edit staged only; nothing reaches the turrets
-- until a commit point. The dirty flag is what greys the Update button.
local State = X4GunneryState
assert(State.isStagedDirty(sess2),
    "console row handlers must leave the session dirty (staged diverges from the baseline)")
fix2.gcMenu.display()
assert(fix2.buttonByText("text:20991:83") ~= nil,
    "Update turret behavior button must still render while dirty")
GetComponentData = function() return nil end

print("runtime coverage ui tests passed")
