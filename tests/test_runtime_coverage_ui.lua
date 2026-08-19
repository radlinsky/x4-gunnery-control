local fix = dofile("tests/support/runtime_fixture.lua").load()
-- readGroups always builds group.key with State.groupKey, and seedBaseline keys
-- staged by that same derivation. Use the real form here so the fixture cannot
-- pass while the production key derivations disagree.
local groupKey = X4GunneryState.groupKey(5, "p", "g")
local group = fix.makeGroup{ displayName = "Group",
    members = { { componentID = 27, displayName = "Turret", operational = true, cameraSupported = true } } }
fix.gcMenu.onShowMenu()
local session = fix.API.getSession()
session.groups, session.checkedGroupKeys = { group }, { [groupKey] = true }
session.phase, session.controlMode, session.cameraMemberID = "engaged", "auto", 27
fix.C.GetExternalTargetViewComponent = function() return 27 end
fix.gcMenu.display()
for _, label in ipairs({ fix.LABEL.nextTurret, fix.LABEL.prevTurret }) do
    local entry = fix.buttonByText(label)
    assert(entry and entry.handlers and type(entry.handlers.onClick) == "function",
        "cycle turret button must expose its production handler")
    local checkpoint = fix.callbackCheckpoint()
    entry.handlers.onClick()
    assert(fix.callbackCheckpoint() > checkpoint,
        "cycle turret button " .. tostring(label) .. " must schedule its camera gate")
end
-- #18: Previous on the left, Next on the right.
local cycleTurretBtns = {}
for _, b in ipairs(fix.getCreatedButtons()) do
    if b.text == fix.LABEL.nextTurret or b.text == fix.LABEL.prevTurret then cycleTurretBtns[#cycleTurretBtns + 1] = b end end
assert(#cycleTurretBtns == 2, "engaged/auto must render exactly two cycle_turret buttons")
local prevBtn, nextBtn
for _, b in ipairs(cycleTurretBtns) do
    if b.text == fix.LABEL.prevTurret then prevBtn = b elseif b.text == fix.LABEL.nextTurret then nextBtn = b end
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
    local grpE = fixE.makeGroup()
    fixE.gcMenu.onShowMenu()
    local sessE = fixE.API.getSession()
    sessE.groups, sessE.checkedGroupKeys, sessE.cameraMemberID = { grpE }, { [key] = true }, 27
    sessE.phase, sessE.controlMode = "engaged", controlMode
    X4GunneryState.seedBaseline(sessE, { grpE })

    fixE.gcMenu.display()
    -- Task 1: engaged panels (auto and direct) must NOT render Update turret
    -- behavior; the button lives on the main console only.
    local engagedUpdateBtn = latestButton(fixE, fixE.LABEL.updateBehavior)
    assert(engagedUpdateBtn == nil,
        "engaged/" .. controlMode .. " panel must NOT render the Update turret behavior button")
    -- #18: Previous on the left, Next on the right (cycle_turret is shared).
    local dirCycleBtns = {}
    for _, b in ipairs(fixE.getCreatedButtons()) do
        if b.text == fixE.LABEL.nextTurret or b.text == fixE.LABEL.prevTurret then dirCycleBtns[#dirCycleBtns + 1] = b end end
    assert(#dirCycleBtns == 2, "engaged/" .. controlMode .. " must render exactly two cycle_turret buttons")
    local dPrev, dNext
    for _, b in ipairs(dirCycleBtns) do
        if b.text == fixE.LABEL.prevTurret then dPrev = b elseif b.text == fixE.LABEL.nextTurret then dNext = b end
    end
    assert(dPrev and dPrev.column == 1, "engaged/" .. controlMode .. ": Previous Turret (72) must be col 1")
    assert(dNext and dNext.column == 2, "engaged/" .. controlMode .. ": Next Turret (71) must be col 2")
end
-- #18: engaged/direct cycle_target row.
do
    local fixCT = dofile("tests/support/runtime_fixture.lua").load()
    local key = X4GunneryState.groupKey(5, "p", "g")
    local grp = fixCT.makeGroup()
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
        if b.text == fixCT.LABEL.nextTarget or b.text == fixCT.LABEL.prevTarget then cycleTargetBtns[#cycleTargetBtns + 1] = b end end
    assert(#cycleTargetBtns == 2, "engaged/direct must render exactly two cycle_target buttons")
    local cPrev, cNext
    for _, b in ipairs(cycleTargetBtns) do
        if b.text == fixCT.LABEL.prevTarget then cPrev = b elseif b.text == fixCT.LABEL.nextTarget then cNext = b end
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
    local grpC = fixC.makeGroup()
    fixC.gcMenu.onShowMenu()
    local sessC = fixC.API.getSession()
    sessC.groups, sessC.checkedGroupKeys, sessC.cameraMemberID = { grpC }, { [key] = true }, 27
    sessC.phase, sessC.controlMode = "engaged", "direct"
    X4GunneryState.seedBaseline(sessC, { grpC })
    fixC.gcMenu.display()

    local ceaseBtn = latestButton(fixC, fixC.LABEL.getUp)
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
    local grpR = fixR.makeGroup()
    fixR.gcMenu.onShowMenu()
    local sessR = fixR.API.getSession()
    sessR.groups, sessR.checkedGroupKeys, sessR.cameraMemberID = { grpR }, { [key] = true }, 27
    X4GunneryState.seedBaseline(sessR, { grpR })
    -- refresh() inside the callback re-reads groups off the stubbed engine, which
    -- reports none, so every baseline entry comes back unresolved and the
    -- mismatch branch runs. That is the branch worth covering: a silent failure
    -- to restore is exactly what leaves the player with a silently altered ship.
    local markR = fixR.callbackCheckpoint()
    local autoBtn = latestButton(fixR, fixR.LABEL.autoEngage)
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
local updateBtnClean = latestButton(fix2, fix2.LABEL.updateBehavior)
assert(updateBtnClean ~= nil,
    "Update turret behavior button must be rendered in clean console display")
assert(updateBtnClean.active == false,
    "Update button must be inactive while clean (staged equals baseline)")

-- Stage a divergent mode and re-display; Update must become active.
X4GunneryState.stageMode(sess2, groupKey, "defend", group.armed)
fix2.gcMenu.display()
local updateBtnDirty = latestButton(fix2, fix2.LABEL.updateBehavior)
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
local armedLabels = { [fix2.LABEL.armed] = true, [fix2.LABEL.disarmed] = true }
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
-- Issue #48 Task 2: the console Direct-control turret mode selector and the
-- constrained per-row mode dropdowns. Shipped 9.00 Helper dropdowns carry no
-- per-option disable (options only hold id/icon/text), so the conflicting
-- Direct-control mode is omitted from every row rather than greyed out.
do
    local fixD = dofile("tests/support/runtime_fixture.lua").load()
    local keyA = X4GunneryState.groupKey(5, "pA", "gA")
    local keyB = X4GunneryState.groupKey(5, "pB", "gB")
    local groupA = {
        key = keyA, kind = "group", contextID = 5, path = "pA", group = "gA",
        componentID = 27, displayName = "GA", operationalCount = 1, totalCount = 1,
        mode = "attack", armed = false,
        members = { { componentID = 27, displayName = "TA", operational = true, cameraSupported = true } },
    }
    local groupB = {
        key = keyB, kind = "group", contextID = 5, path = "pB", group = "gB",
        componentID = 28, displayName = "GB", operationalCount = 1, totalCount = 1,
        mode = "attack", armed = false,
        members = { { componentID = 28, displayName = "TB", operational = true, cameraSupported = true } },
    }
    fixD.gcMenu.onShowMenu()
    local sessD = fixD.API.getSession()
    sessD.groups = { groupA, groupB }
    X4GunneryState.seedBaseline(sessD, { groupA, groupB })
    -- Real tick of group A through the accepted API: staged follows the
    -- session's Direct-control policy, exactly as a real sit-down+tick would.
    X4GunneryState.toggleGroup(sessD, keyA, groupA.armed)
    GetComponentData = function(_, key) if key == "isplayerowned" then return true end return nil end

    local function latestRowDropDown(fixture, rowID)
        local found
        for _, dd in ipairs(fixture.getCreatedDropDowns()) do
            if dd.row == rowID then found = dd end
        end
        return found
    end
    local function optionIDs(dd)
        local ids = {}
        for _, option in ipairs(dd.options or {}) do ids[#ids + 1] = option.id end
        return ids
    end
    local function hasID(ids, wanted)
        for _, id in ipairs(ids) do if id == wanted then return true end end
        return false
    end
    local function startValue(dd)
        local start = dd.startOption
        return type(start) == "function" and start() or start
    end

    fixD.gcMenu.display()

    -- Selector: rendered on the console with exactly the two Direct-control
    -- ids, the vanilla Helper option texts, and the localized label/help.
    local selDD = latestRowDropDown(fixD, "direct_mode")
    assert(selDD, "console must render the direct_mode selector dropdown")
    local selIDs = optionIDs(selDD)
    assert(#selIDs == 2 and selIDs[1] == "attackenemies" and selIDs[2] == "autoassist",
        "selector must offer exactly the two Direct-control modes in vanilla order")
    local vanillaText = {}
    for _, entry in ipairs(Helper.turretModes) do vanillaText[entry.id] = entry.text end
    assert(selDD.options[1].text == vanillaText.attackenemies
        and selDD.options[2].text == vanillaText.autoassist,
        "selector options must reuse the vanilla Helper option texts, not hardcoded labels")
    assert(selDD.startOption == "attackenemies" and sessD.directMode == "attackenemies",
        "selector must start at session.directMode (attackenemies)")
    -- X4's createDropDown aborts the whole frame on an option without a
    -- boolean displayremoveoption (live 9.00: "Invalid dropdown descriptor.
    -- Given displayremoveoption is missing or not a bool."), so every selector
    -- option must carry the descriptor field, not just id/text/icon.
    for i, option in ipairs(selDD.options) do
        assert(type(option.displayremoveoption) == "boolean",
            "console selector option " .. i .. " (" .. tostring(option.id) .. ") must carry a "
            .. "boolean displayremoveoption for X4's createDropDown")
    end
    local selLabel
    for _, entry in ipairs(fixD.getCreatedTexts()) do
        if entry.row == "direct_mode" and entry.column == 1 then selLabel = entry.text end
    end
    assert(selLabel == ReadText(20991, 101),
        "selector label must come from localization id 101, not hardcoded English")
    assert(selDD.mouseOverText == ReadText(20991, 102),
        "selector help text must come from localization id 102, not hardcoded English")

    -- Rows under attackenemies (checked and unchecked): the current Direct
    -- mode is offered, the other one is not, ordinary modes stay available.
    for _, rowKey in ipairs({ keyA, keyB }) do
        local ids = optionIDs(latestRowDropDown(fixD, rowKey))
        assert(hasID(ids, "attackenemies"), "row must offer the current Direct mode (" .. rowKey .. ")")
        assert(not hasID(ids, "autoassist"),
            "under attackenemies the row must not offer autoassist (" .. rowKey .. ")")
        assert(hasID(ids, "defend") and hasID(ids, "mining") and hasID(ids, "towing"),
            "ordinary vanilla modes must stay available (" .. rowKey .. ")")
    end
    assert(startValue(latestRowDropDown(fixD, keyA)) == "attackenemies",
        "checked row displays the staged Direct-control mode")

    -- Selector change: policy + checked staging update, repaint follows, and
    -- no live turret state is written (Task 2 is staged/UI-only).
    local liveC = require("ffi").C
    local liveWrites = {}
    local liveSaves = {}
    for _, name in ipairs({ "SetTurretGroupMode2", "SetTurretGroupArmed", "SetWeaponMode", "SetWeaponArmed" }) do
        liveSaves[name] = rawget(liveC, name)
        liveC[name] = function(...) liveWrites[#liveWrites + 1] = name end
    end
    selDD.handlers.onDropDownConfirmed(nil, "autoassist")
    for _, name in ipairs({ "SetTurretGroupMode2", "SetTurretGroupArmed", "SetWeaponMode", "SetWeaponArmed" }) do
        liveC[name] = liveSaves[name]
    end
    assert(#liveWrites == 0,
        "selector change must not write live turret state: " .. table.concat(liveWrites, ","))
    assert(sessD.directMode == "autoassist", "selector change must set session.directMode")
    assert(sessD.staged[keyA].mode == "autoassist",
        "setDirectMode must re-stage the checked row in the new mode")

    fixD.gcMenu.display()
    assert(startValue(latestRowDropDown(fixD, keyA)) == "autoassist",
        "checked row must repaint in the new Direct-control mode")

    -- Rows under autoassist (checked and unchecked): attackenemies is now the
    -- omitted mode; ordinary modes remain.
    for _, rowKey in ipairs({ keyA, keyB }) do
        local ids = optionIDs(latestRowDropDown(fixD, rowKey))
        assert(hasID(ids, "autoassist"), "row must offer the current Direct mode (" .. rowKey .. ")")
        assert(not hasID(ids, "attackenemies"),
            "under autoassist the row must not offer attackenemies (" .. rowKey .. ")")
        assert(hasID(ids, "defend") and hasID(ids, "mining"),
            "ordinary vanilla modes must stay available (" .. rowKey .. ")")
    end

    -- The engine-compatibility filter can drop the current Direct mode from a
    -- row's vanilla list; the row must still offer it, or a checked row could
    -- display a mode its dropdown cannot select.
    fixD.C.IsWeaponModeCompatible = function(_, _, modeID) return modeID ~= "autoassist" end
    fixD.gcMenu.display()
    local compatIDs = optionIDs(latestRowDropDown(fixD, keyA))
    assert(hasID(compatIDs, "autoassist"),
        "row must still offer the current Direct mode when compatibility filtered it out")
    assert(not hasID(compatIDs, "attackenemies"), "the conflicting Direct mode stays excluded")
    -- The surviving autoassist option was force-added by vanillaModeOption,
    -- the exact path a checked row takes when the compatibility filter drops
    -- the current Direct mode. It must be a valid X4 dropdown descriptor too,
    -- or the same live abort hits the row instead of the selector.
    for _, rowKey in ipairs({ keyA, keyB }) do
        local foundForced = false
        for _, option in ipairs(latestRowDropDown(fixD, rowKey).options) do
            if option.id == "autoassist" then
                foundForced = true
                assert(type(option.displayremoveoption) == "boolean",
                    "force-added Direct mode option on row " .. rowKey
                    .. " must carry a boolean displayremoveoption for X4's createDropDown")
            end
        end
        assert(foundForced, "row " .. rowKey .. " must offer the force-added Direct mode")
    end
    fixD.C.IsWeaponModeCompatible = nil

    -- Checked row -> explicit ordinary mode: unticks the row and keeps the
    -- chosen ordinary mode (State.stageMode membership contract).
    latestRowDropDown(fixD, keyA).handlers.onDropDownConfirmed(nil, "defend")
    assert(sessD.checkedGroupKeys[keyA] == nil,
        "choosing an ordinary mode on a checked row must untick it")
    assert(sessD.staged[keyA].mode == "defend",
        "the unticked row must keep the explicitly chosen ordinary mode")
    assert(sessD.directMode == "autoassist",
        "an ordinary row selection must not move the session policy")

    -- Unchecked row -> another ordinary mode: stays unchecked, mode applied.
    latestRowDropDown(fixD, keyB).handlers.onDropDownConfirmed(nil, "mining")
    assert(sessD.checkedGroupKeys[keyB] == nil,
        "changing an unchecked row to another ordinary mode must keep it unchecked")
    assert(sessD.staged[keyB].mode == "mining",
        "the unchecked row must keep the selected ordinary mode")

    -- Degraded Helper table: the selector degrades to what vanilla ships and
    -- the ensure-present fallback resolves to nil without raising.
    local savedModes = Helper.turretModes
    Helper.turretModes = {}
    fixD.gcMenu.display()
    assert(#optionIDs(latestRowDropDown(fixD, "direct_mode")) == 0,
        "with no vanilla entries the selector offers no options")
    assert(#optionIDs(latestRowDropDown(fixD, keyA)) == 0,
        "with no vanilla entries the row offers no options")
    Helper.turretModes = savedModes
    GetComponentData = function() return nil end
end

print("runtime coverage ui tests passed")
