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
-- #18: Previous on the left, Next on the right.
local cycleTurretBtns = {}
for _, b in ipairs(fix.getCreatedButtons()) do
    if string.find(b.text, "text:20991:7[12]") then cycleTurretBtns[#cycleTurretBtns + 1] = b end end
assert(#cycleTurretBtns == 2, "engaged/auto must render exactly two cycle_turret buttons")
local prevBtn, nextBtn
for _, b in ipairs(cycleTurretBtns) do
    if b.text == "text:20991:72" then prevBtn = b elseif b.text == "text:20991:71" then nextBtn = b end
end
assert(prevBtn and prevBtn.column == 1, "engaged/auto: Previous Turret (72) must be col 1")
assert(nextBtn and nextBtn.column == 2, "engaged/auto: Next Turret (71) must be col 2")

-- Regression: Update turret behavior is console-only and must not appear on
-- either engaged panel. menu.display returns early for the engaged phase, so
-- these fixtures specifically exercise the compact Auto and Direct views.
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
    -- Task 1: engaged panels (auto and direct) must NOT render Update turret
    -- behavior; the button lives on the main console only.
    local engagedUpdateBtn = latestButton(fixE, "text:20991:83")
    assert(engagedUpdateBtn == nil,
        "engaged/" .. controlMode .. " panel must NOT render the Update turret behavior button")
    -- #18: Previous on the left, Next on the right (cycle_turret is shared).
    local dirCycleBtns = {}
    for _, b in ipairs(fixE.getCreatedButtons()) do
        if string.find(b.text, "text:20991:7[12]") then dirCycleBtns[#dirCycleBtns + 1] = b end end
    assert(#dirCycleBtns == 2, "engaged/" .. controlMode .. " must render exactly two cycle_turret buttons")
    local dPrev, dNext
    for _, b in ipairs(dirCycleBtns) do
        if b.text == "text:20991:72" then dPrev = b elseif b.text == "text:20991:71" then dNext = b end
    end
    assert(dPrev and dPrev.column == 1, "engaged/" .. controlMode .. ": Previous Turret (72) must be col 1")
    assert(dNext and dNext.column == 2, "engaged/" .. controlMode .. ": Next Turret (71) must be col 2")
end
-- #18: engaged/direct cycle_target row.
do
    local fixCT = dofile("tests/support/runtime_fixture.lua").load()
    local key = X4GunneryState.groupKey(5, "p", "g")
    local grp = {
        key = key, kind = "group", contextID = 5, path = "p", group = "g",
        componentID = 27, displayName = "G", operationalCount = 1, totalCount = 1,
        mode = "attack", armed = false,
        members = { { componentID = 27, displayName = "T", operational = true, cameraSupported = true } },
    }
    fixCT.gcMenu.onShowMenu()
    local sess = fixCT.API.getSession()
    sess.groups, sess.checkedGroupKeys, sess.cameraMemberID = { grp }, { [key] = true }, 27
    sess.phase, sess.controlMode = "engaged", "direct"
    X4GunneryState.seedBaseline(sess, { grp })
    -- hasMultipleTargets returns false by default; fake it so cycle_target renders.
    fixCT.C.hasMultipleTargets = function() return true end
    fixCT.gcMenu.display()
    local cycleTargetBtns = {}
    for _, b in ipairs(fixCT.getCreatedButtons()) do
        if string.find(b.text, "text:20991:7[56]") then cycleTargetBtns[#cycleTargetBtns + 1] = b end end
    assert(#cycleTargetBtns == 2, "engaged/direct must render exactly two cycle_target buttons")
    local cPrev, cNext
    for _, b in ipairs(cycleTargetBtns) do
        if b.text == "text:20991:76" then cPrev = b elseif b.text == "text:20991:75" then cNext = b end
    end
    assert(cPrev and cPrev.column == 1, "engaged/direct: Previous Target (76) must be col 1")
    assert(cNext and cNext.column == 2, "engaged/direct: Next Target (75) must be col 2")
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
-- Make the ship appear player-owned so the console group loop runs.
GetComponentData = function(_, key) if key == "isplayerowned" then return true end return nil end
fix2.gcMenu.display()
-- Task 1: Update must exist while clean and be inactive (active == false).
local State = X4GunneryState
assert(not State.isStagedDirty(sess2), "seeded session must start clean")
local updateBtnClean = latestButton(fix2, "text:20991:83")
assert(updateBtnClean ~= nil,
    "Update turret behavior button must be rendered in clean console display")
assert(updateBtnClean.active == false,
    "Update button must be inactive while clean (staged equals baseline)")

-- Stage a divergent mode and re-display; Update must become active.
X4GunneryState.stageMode(sess2, groupKey, "defend", group.armed)
fix2.gcMenu.display()
local updateBtnDirty = latestButton(fix2, "text:20991:83")
assert(updateBtnDirty ~= nil,
    "Update button must still render while dirty")
assert(updateBtnDirty.active == true,
    "Update button must be active after staged divergence")

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
assert(State.isStagedDirty(sess2),
    "console row handlers must leave the session dirty (staged diverges from the baseline)")

-- Clicking the Update button writes staged to the ship and advances committedBaseline.
-- Intercept the live C table the loaded module actually bound at load time, so
-- SetTurretGroupMode2 and SetTurretGroupArmed calls are captured rather than
-- silently dispatched to stubs. Each fixture.load() builds a fresh C and
-- gunnery_control captures ffi.C once; fix2.C is only the fixture's copy.
local liveC = require("ffi").C
local stagedMode = sess2.staged[groupKey] and sess2.staged[groupKey].mode or "attack"
local stagedArmed = sess2.staged[groupKey] and sess2.staged[groupKey].armed or false
local modeWrites = {}
local armedWrites = {}
local origSetMode = rawget(liveC, "SetTurretGroupMode2")
local origSetArmed = rawget(liveC, "SetTurretGroupArmed")
liveC.SetTurretGroupMode2 = function(_, _, _, _, mode) modeWrites[#modeWrites + 1] = tostring(mode) end
liveC.SetTurretGroupArmed = function(_, _, _, _, armed) armedWrites[#armedWrites + 1] = armed end
local commitMark = fix2.callbackCheckpoint()
updateBtnDirty.handlers.onClick()
fix2.drainCallbacksSince(commitMark)
liveC.SetTurretGroupMode2 = origSetMode
liveC.SetTurretGroupArmed = origSetArmed
assert(#modeWrites == 1 and modeWrites[1] == stagedMode,
    "Update must push exactly one SetTurretGroupMode2 for the staged mode; got "
    .. table.concat(modeWrites, ","))
assert(#armedWrites == 1 and armedWrites[1] == stagedArmed,
    "Update must push exactly one SetTurretGroupArmed for the staged armed value; got "
    .. tostring(armedWrites[1]))
-- Read the final staged values (armed may have been toggled by the armed button).
local finalStaged = sess2.staged[groupKey]
assert(sess2.committedBaseline[1] and sess2.committedBaseline[1].mode == finalStaged.mode,
    "committedBaseline must advance to the staged mode after clicking Update")
assert(sess2.committedBaseline[1] and sess2.committedBaseline[1].armed == finalStaged.armed,
    "committedBaseline armed must match after clicking Update")
assert(not State.isStagedDirty(sess2),
    "session must be clean after committing staged to baseline")
GetComponentData = function() return nil end

print("runtime coverage ui tests passed")
