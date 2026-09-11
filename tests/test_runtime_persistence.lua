-- test_runtime_persistence.lua
-- MD event ordering, save/restore, and payload handling.

local fix = dofile("tests/support/runtime_fixture.lua").load()
local gcMenu = fix.gcMenu
local API    = fix.API

-- Bring the module into a known state with a live session.
local ok_init, err_init = pcall(function() gcMenu.onShowMenu() end)
assert(ok_init, "onShowMenu() raised during persistence test setup: " .. tostring(err_init))

-- ── 49. Atomic restore rejects foreign/malformed payloads ──────────────────
assert(type(API.onRestoreEnvelope) == "function")
local live49, epoch49 = API.getSession(), API.getSessionEpoch()
local callbacks49, events49 = #fix.pendingCallbacks, #fix.uiTriggeredEvents
local cameraCalls49 = 0
local originalCamera49 = fix.C.SetPlayerCameraTargetView
fix.C.SetPlayerCameraTargetView = function(...) cameraCalls49 = cameraCalls49 + 1; return true end
local payload49 = X4GunneryState.encode(X4GunneryState.saveState({
    shipID = 42, shipName = "another ship", phase = "engaged", controlMode = "auto",
    povAnchor = "turret", povMode = "manual", checkedGroupKeys = {}, groups = {}, committedBaseline = {},
}))
API.onRestoreEnvelope({ generation = 1, target = 0, payload = payload49 })
assert(API.getSession() == live49 and API.getSessionEpoch() == epoch49,
    "foreign restore must preserve the exact live session and epoch")
assert(cameraCalls49 == 0, "foreign restore must not enter a camera")
assert(#fix.pendingCallbacks == callbacks49 and #fix.uiTriggeredEvents == events49,
    "foreign restore must not schedule callbacks or rewrite MD state")
for _, bad in ipairs({ "", "garbage" }) do
    assert(pcall(API.onRestoreEnvelope, { generation = 2, target = 0, payload = bad }),
        "malformed envelope must not throw")
    assert(API.getSession() == live49 and API.getSessionEpoch() == epoch49,
        "malformed restore must not replace the session")
end
assert(pcall(API.onRestoreEnvelope, { generation = 2, target = 0, payload = nil }),
    "nil restore payload must not throw")
assert(pcall(API.onRestoreEnvelope, { generation = 2, target = 0, payload = {} }),
    "table restore payload must not throw")
assert(API.getSession() == live49 and API.getSessionEpoch() == epoch49,
    "nil/table restore payloads must not replace the session")

-- A syntactically parseable but incomplete payload used to get fallback values
-- from restoreState, swap over this live Direct session, and lose the only
-- references capable of restoring the overridden turret. It must now be
-- rejected before candidate/session handover, camera work, persistence writes,
-- or any turret setting write.
local direct49 = API.getSession()
local baseline49 = { {
    shipID = direct49.shipID, kind = "group", contextID = 5, path = "p", group = "g",
    mode = "defend", armed = true,
} }
direct49.phase, direct49.controlMode = "engaged", "direct"
direct49.committedBaseline = baseline49
direct49.checkedGroupKeys = { ["group:5:p:g"] = true }
local modeWrites49, armedWrites49 = 0, 0
local originalMode49, originalArmed49 = fix.C.SetTurretGroupMode2, fix.C.SetTurretGroupArmed
fix.C.SetTurretGroupMode2 = function(...) modeWrites49 = modeWrites49 + 1 end
fix.C.SetTurretGroupArmed = function(...) armedWrites49 = armedWrites49 + 1 end
local function assertDirectRestoreRefused49(payload, label)
    local callbacks, events = #fix.pendingCallbacks, #fix.uiTriggeredEvents
    assert(pcall(API.onRestoreEnvelope, { generation = 49, target = 0, payload = payload }),
        label .. ": malformed restore must not throw")
    assert(API.getSession() == direct49 and API.getSessionEpoch() == epoch49,
        label .. ": malformed restore must retain the exact live Direct session and epoch")
    assert(direct49.committedBaseline == baseline49 and baseline49[1].mode == "defend"
        and baseline49[1].armed == true,
        label .. ": malformed restore must retain observable Direct committedBaseline")
    assert(modeWrites49 == 0 and armedWrites49 == 0 and cameraCalls49 == 0,
        label .. ": malformed restore must not write turrets or enter a camera")
    assert(#fix.pendingCallbacks == callbacks and #fix.uiTriggeredEvents == events,
        label .. ": malformed restore must not schedule callbacks or rewrite MD state")
end
assertDirectRestoreRefused49("t=session", "truncated session")
local invalidPhase49 = X4GunneryState.saveState(direct49)
invalidPhase49[1].phase = "not-a-phase"
assertDirectRestoreRefused49(X4GunneryState.encode(invalidPhase49), "invalid phase")
local malformedBaseline49 = X4GunneryState.saveState(direct49)
malformedBaseline49[2].armed = nil
assertDirectRestoreRefused49(X4GunneryState.encode(malformedBaseline49), "truncated baseline")
fix.C.SetTurretGroupMode2, fix.C.SetTurretGroupArmed = originalMode49, originalArmed49

local oldControl49 = fix.C.GetPlayerCurrentControlGroup
fix.C.GetPlayerCurrentControlGroup = function() return "" end
local seatedSession49, seatedEpoch49 = API.getSession(), API.getSessionEpoch()
local seatedCallbacks49, seatedEvents49 = #fix.pendingCallbacks, #fix.uiTriggeredEvents
assert(pcall(API.onRestoreEnvelope, { generation = 3, target = 0, payload = payload49 }),
    "not-seated restore must not throw")
assert(API.getSession() == seatedSession49 and API.getSessionEpoch() == seatedEpoch49
    and cameraCalls49 == 0 and #fix.pendingCallbacks == seatedCallbacks49
    and #fix.uiTriggeredEvents == seatedEvents49,
    "not-seated restore must leave session, epoch, camera, callbacks, and MD events unchanged")
fix.C.GetPlayerCurrentControlGroup = oldControl49
fix.C.SetPlayerCameraTargetView = originalCamera49

-- ── 59. restored engagement without a usable camera tears down safely ──────
-- The saved Direct snapshot is still writable even though its only live turret
-- can no longer be used as a camera. Direct must restore it; Auto must
-- not issue any turret writes. Both paths clear the MD record and land at the
-- console instead of leaving an invisible engaged session behind.
do
    local C, State = fix.C, X4GunneryState
    local savedNumGroups, savedGroups2 = C.GetNumUpgradeGroups, C.GetUpgradeGroups2
    local savedInfo, savedSlots = C.GetUpgradeGroupInfo2, C.GetNumUpgradeSlots
    local savedSlotComponent, savedSlotGroup = C.GetUpgradeSlotCurrentComponent, C.GetUpgradeSlotGroup
    local savedOperational, savedCamera = C.IsComponentOperational, C.IsPlayerCameraTargetViewPossible
    local savedMode, savedArmed = C.SetTurretGroupMode2, C.SetTurretGroupArmed
    local savedNew = fix.ffiStub.new
    local groupBuffer = { [0] = { path = "p", group = "g", contextid = 5 } }
    C.GetNumUpgradeGroups, C.GetUpgradeGroups2 = function() return 1 end, function() return 1 end
    C.GetUpgradeGroupInfo2 = function()
        return { count = 1, currentcomponent = 27, currentmacro = "", slotsize = "",
            total = 1, operational = 1 }
    end
    C.GetNumUpgradeSlots = function() return 1 end
    C.GetUpgradeSlotCurrentComponent = function() return 27 end
    C.GetUpgradeSlotGroup = function() return { path = "p", group = "g" } end
    C.IsComponentOperational = function() return true end
    C.IsPlayerCameraTargetViewPossible = function() return false end
    fix.ffiStub.new = function() return groupBuffer end

    local function payload59(controlMode, phase, missingSavedCamera)
        local source = State.newSession(42, "gunnercontrol")
        source.shipName, source.phase, source.controlMode = "0", phase or "engaged", controlMode
        source.groups = { fix.makeGroup{
            members = { { componentID = 27, operational = true, cameraSupported = true } },
        } }
        if missingSavedCamera then
            source.groups[1].members[2] = {
                componentID = 28, operational = true, cameraSupported = true,
            }
            source.groups[1].totalCount = 2
            source.cameraMemberID = 28
        else
            source.cameraMemberID = 27
        end
        source.checkedGroupKeys = { [source.groups[1].key] = true }
        source.committedBaseline = controlMode == "direct" and { {
            shipID = 42, kind = "group", contextID = 5, path = "p", group = "g",
            mode = "attack", armed = false,
        } } or {}
        return State.encode(State.saveState(source))
    end

    local modeWrites59, armedWrites59 = 0, 0
    C.SetTurretGroupMode2 = function() modeWrites59 = modeWrites59 + 1 end
    C.SetTurretGroupArmed = function() armedWrites59 = armedWrites59 + 1 end
    fix.resetUITriggeredEvents()
    API.onRestoreEnvelope({ generation = 56, target = 0, payload = payload59("auto", nil, true) })
    local missingAutoCamera56 = API.getSession()
    assert(missingAutoCamera56.phase == "console" and missingAutoCamera56.controlMode == nil,
        "56 Auto missing camera: restored session must release to the console")
    assert(modeWrites59 == 0 and armedWrites59 == 0,
        "56 Auto missing camera: safe fallback must not write turret settings")
    assert(fix.uiTriggeredEvents[#fix.uiTriggeredEvents].control == "session_end",
        "56 Auto missing camera: safe fallback must clear MD persistence")

    fix.resetUITriggeredEvents()
    API.onRestoreEnvelope({ generation = 57, target = 0, payload = payload59("direct", nil, true) })
    local missingCamera57 = API.getSession()
    assert(missingCamera57.phase == "console" and missingCamera57.controlMode == nil,
        "57 Direct missing camera: restored session must release to the console")
    assert(modeWrites59 == 1 and armedWrites59 == 1,
        "57 Direct missing camera: saved snapshot must be restored exactly once")
    assert(fix.uiTriggeredEvents[#fix.uiTriggeredEvents].control == "session_end",
        "57 Direct missing camera: safe fallback must clear MD persistence")

    modeWrites59, armedWrites59 = 0, 0
    fix.resetUITriggeredEvents()
    API.onRestoreEnvelope({ generation = 58, target = 0, payload = payload59("direct", "target_select") })
    local targetSelect58 = API.getSession()
    assert(targetSelect58.phase == "console" and targetSelect58.controlMode == nil,
        "58 Direct target-select: restored session must release to the console")
    assert(modeWrites59 == 1 and armedWrites59 == 1,
        "58 Direct target-select: saved snapshot must be restored before console handoff")
    assert(fix.uiTriggeredEvents[#fix.uiTriggeredEvents].control == "session_end",
        "58 Direct target-select: release must clear MD persistence")

    modeWrites59, armedWrites59 = 0, 0
    fix.resetUITriggeredEvents()
    API.onRestoreEnvelope({ generation = 59, target = 0, payload = payload59("direct") })
    local direct59 = API.getSession()
    assert(direct59.phase == "console" and direct59.controlMode == nil,
        "59 Direct: no usable restored camera must return to the console")
    assert(modeWrites59 == 1 and armedWrites59 == 1,
        "59 Direct: saved snapshot must be restored exactly once")
    assert(fix.uiTriggeredEvents[#fix.uiTriggeredEvents].control == "session_end",
        "59 Direct: failed restored engagement must clear MD persistence")

    modeWrites59, armedWrites59 = 0, 0
    fix.resetUITriggeredEvents()
    API.onRestoreEnvelope({ generation = 60, target = 0, payload = payload59("auto") })
    local auto59 = API.getSession()
    assert(auto59.phase == "console" and auto59.controlMode == nil,
        "59 Auto: no usable restored camera must return to the console")
    assert(modeWrites59 == 0 and armedWrites59 == 0,
        "59 Auto: no-camera restore must not write a turret setting")
    assert(fix.uiTriggeredEvents[#fix.uiTriggeredEvents].control == "session_end",
        "59 Auto: failed restored engagement must clear MD persistence")

    C.GetNumUpgradeGroups, C.GetUpgradeGroups2 = savedNumGroups, savedGroups2
    C.GetUpgradeGroupInfo2, C.GetNumUpgradeSlots = savedInfo, savedSlots
    C.GetUpgradeSlotCurrentComponent, C.GetUpgradeSlotGroup = savedSlotComponent, savedSlotGroup
    C.IsComponentOperational, C.IsPlayerCameraTargetViewPossible = savedOperational, savedCamera
    C.SetTurretGroupMode2, C.SetTurretGroupArmed = savedMode, savedArmed
    fix.ffiStub.new = savedNew
end

-- ── 61. POV and camera buttons persist the selection immediately ───────────
-- X4 saves the MD-owned payload, not this Lua session table. A POV/turret
-- click therefore has to commit its new values itself; opening Test Lab later
-- must not be what makes the selection durable.
local function povFixture61()
    local localFix = dofile("tests/support/runtime_fixture.lua").load()
    localFix.gcMenu.onShowMenu()
    local localSession = localFix.API.getSession()
    local group = localFix.makeGroup{
        key = "pov61", componentID = 10, displayName = "Camera group",
        totalCount = 3, operationalCount = 3,
        members = {
            { componentID = 10, displayName = "T1", operational = true, cameraSupported = true },
            { componentID = 11, displayName = "T2", operational = true, cameraSupported = true },
            { componentID = 12, displayName = "T3", operational = true, cameraSupported = true },
        },
    }
    localSession.phase, localSession.controlMode = "engaged", "auto"
    localSession.groups, localSession.checkedGroupKeys = { group }, { pov61 = true }
    localSession.committedBaseline = {}
    localSession.cameraIndex, localSession.cameraMemberID = 2, 11
    localSession.aimTargetID, localSession.targetObjectID = 99, 99
    localFix.C.GetSofttarget2 = function()
        return { softtargetID = 99, softtargetConnectionName = "" }
    end
    return localFix, localSession, group
end

local function persistedSelection61(localFix, localSession, group, label)
    local payload
    for index = #localFix.uiTriggeredEvents, 1, -1 do
        local event = localFix.uiTriggeredEvents[index]
        if event.control == "session_commit" then
            payload = event.params and event.params.payload
            break
        end
    end
    assert(type(payload) == "string", label .. ": click must emit session_commit")
    local restored = X4GunneryState.newSession(localSession.shipID, "gunnercontrol")
    restored.shipName = localSession.shipName
    assert(X4GunneryState.restoreState(restored, X4GunneryState.decode(payload), { group }),
        label .. ": committed payload must decode and restore")
    return restored
end

for _, case in ipairs({
    { button = 63, anchor = "turret", mode = "manual", initialAnchor = "target", initialMode = "manual" },
    { button = 64, anchor = "target", mode = "manual", initialAnchor = "turret", initialMode = "manual" },
    { button = 65, anchor = "turret", mode = "cinematic", initialAnchor = "turret", initialMode = "manual" },
    { button = 66, anchor = "target", mode = "cinematic", initialAnchor = "turret", initialMode = "manual" },
}) do
    local localFix, localSession, group = povFixture61()
    localSession.povAnchor, localSession.povMode = case.initialAnchor, case.initialMode
    localFix.gcMenu.display()
    local button = localFix.buttonByText("text:20991:" .. tostring(case.button))
    assert(button and button.active and type(button.handlers.onClick) == "function",
        "POV " .. tostring(case.button) .. " must be a selectable real UI button")
    localFix.resetUITriggeredEvents()
    button.handlers.onClick()
    local restored = persistedSelection61(localFix, localSession, group,
        "POV " .. tostring(case.button))
    assert(restored.povAnchor == case.anchor and restored.povMode == case.mode,
        "POV " .. tostring(case.button) .. ": restored selection mismatch")
    assert(restored.cameraMemberID == 11,
        "POV " .. tostring(case.button) .. ": restore must retain the selected camera turret")
end

for _, case in ipairs({
    { button = 71, labelName = "nextTurret", cameraMemberID = 12, label = "Next Turret" },
    { button = 72, labelName = "prevTurret", cameraMemberID = 10, label = "Previous Turret" },
}) do
    local localFix, localSession, group = povFixture61()
    localSession.povAnchor, localSession.povMode = "target", "cinematic"
    localFix.gcMenu.display()
    local button = localFix.buttonByLabel(case.labelName)
    assert(button and button.active and type(button.handlers.onClick) == "function",
        case.label .. " must be a selectable real UI button")
    localFix.resetUITriggeredEvents()
    button.handlers.onClick()
    local restored = persistedSelection61(localFix, localSession, group, case.label)
    assert(restored.cameraMemberID == case.cameraMemberID,
        case.label .. ": committed payload must restore the newly selected turret")
    assert(restored.povAnchor == "target" and restored.povMode == "cinematic",
        case.label .. ": cycling the turret must retain the selected POV")
end

-- ── 62. Direct-control option buttons persist only settled state ────────
local function directOptionFixture62()
    local localFix, localSession, group = povFixture61()
    localSession.controlMode = "direct"
    localSession.committedBaseline = { {
        kind = "group", shipID = localSession.shipID, contextID = group.contextID,
        path = group.path, group = group.group, mode = "attack", armed = false,
    } }
    return localFix, localSession, group
end

local function eventCount62(localFix, control)
    local count = 0
    for _, event in ipairs(localFix.uiTriggeredEvents) do
        if event.control == control then count = count + 1 end
    end
    return count
end

-- Auto-next is a synchronous local option, so both sides of the checkbox
-- toggle must be in MD before the click handler returns.
do
    local localFix, localSession, group = directOptionFixture62()
    localFix.gcMenu.display()
    for _, expected in ipairs({ false, true }) do
        local checkbox = localFix.getCreatedCheckBoxes()[1]
        assert(checkbox and type(checkbox.handlers.onClick) == "function",
            "Auto-next Target must expose the actual checkbox click handler")
        localFix.resetUITriggeredEvents()
        checkbox.handlers.onClick()
        assert(localSession.autoNextTarget == expected,
            "Auto-next Target click must update the live session immediately")
        local restored = persistedSelection61(localFix, localSession, group, "Auto-next Target")
        assert(restored.autoNextTarget == expected,
            "Auto-next Target click must immediately persist " .. tostring(expected))
    end
end

-- ── 71. Stand-up after a restored Direct session reverts the committed baseline ──
-- A save/load during an active Direct engagement must rebuild the whole
-- session -- checked membership, policy, committed baseline, and the ordinary
-- preTickMode -- and the *normal* stand-up afterwards must write the ship
-- back to the committed baseline, never the temporary Direct state the
-- engagement was flying in nor the preTickMode that travelled with the
-- payload. Proven under both Direct-control policies.
local function eq71(a, b, label)
    assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
for _, policy in ipairs({ "attackenemies", "autoassist" }) do
    local localFix = dofile("tests/support/runtime_fixture.lua").load()
    local C, State = localFix.C, X4GunneryState
    -- The group must exist before onShowMenu's readGroups runs.
    local groupBuffer = { [0] = { path = "p", group = "g", contextid = 5 } }
    C.GetNumUpgradeGroups, C.GetUpgradeGroups2 = function() return 1 end, function() return 1 end
    C.GetUpgradeGroupInfo2 = function()
        return { count = 1, currentcomponent = 27, currentmacro = "", slotsize = "",
            total = 1, operational = 1 }
    end
    C.GetNumUpgradeSlots = function() return 1 end
    C.GetUpgradeSlotCurrentComponent = function() return 27 end
    C.GetUpgradeSlotGroup = function() return { path = "p", group = "g" } end
    C.IsComponentOperational = function() return true end
    C.IsPlayerCameraTargetViewPossible = function() return true end
    C.GetExternalTargetViewComponent = function() return 27 end
    C.GetTurretGroupMode2 = function() return "attack" end
    C.IsTurretGroupArmed = function() return false end
    localFix.ffiStub.new = function() return groupBuffer end
    localFix.gcMenu.onShowMenu()

    -- The live Direct session as the player saved it: the committed baseline
    -- still holds the pre-engage mode, the staged row holds the temporary
    -- Direct state with its displaced ordinary preTickMode.
    local sess = localFix.API.getSession()
    local group = sess.groups[1]
    local key = group.key
    sess.phase, sess.controlMode = "engaged", "direct"
    sess.directMode = policy
    sess.checkedGroupKeys = { [key] = true }
    sess.committedBaseline = { {
        shipID = sess.shipID, kind = "group", contextID = group.contextID,
        path = group.path, group = group.group, mode = "defend", armed = true,
    } }
    sess.staged = { [key] = { mode = policy, armed = true, preTickMode = "attack" } }
    sess.cameraMemberID = 27
    local payload = State.encode(State.saveState(sess))

    -- Restore it the way a save/load delivers it, into the open menu.
    localFix.gcMenu.shown = true
    localFix.API.onRestoreEnvelope({ generation = 71, target = 0, payload = payload })
    local restored = localFix.API.getSession()
    assert(restored ~= sess, "task4 restore " .. policy .. " must swap in the restored session")
    eq71(restored.phase, "engaged", "task4 restore " .. policy .. " phase")
    eq71(restored.controlMode, "direct", "task4 restore " .. policy .. " control mode")
    eq71(restored.directMode, policy, "task4 restore " .. policy .. " policy")
    assert(restored.checkedGroupKeys[key] == true,
        "task4 restore " .. policy .. ": checked membership restored")
    eq71(#restored.committedBaseline, 1, "task4 restore " .. policy .. " baseline count")
    eq71(restored.committedBaseline[1].mode, "defend",
        "task4 restore " .. policy .. ": committed baseline mode")
    eq71(restored.committedBaseline[1].armed, true,
        "task4 restore " .. policy .. ": committed baseline armed")
    eq71(restored.staged[key].mode, policy, "task4 restore " .. policy .. " staged in the policy")
    eq71(restored.staged[key].preTickMode, "attack",
        "task4 restore " .. policy .. ": ordinary preTickMode restored")

    -- Normal stand-up (the playerGetUp route): the ship must come back to the
    -- committed baseline, exactly once, in neither the staged policy mode nor
    -- the displaced ordinary mode.
    local modes, armeds = {}, {}
    C.SetTurretGroupMode2 = function(_, _, _, _, mode) modes[#modes + 1] = mode end
    C.SetTurretGroupArmed = function(_, _, _, _, armed) armeds[#armeds + 1] = armed end
    local eventsBefore = #localFix.uiTriggeredEvents
    localFix.API.endForMovement()
    assert(#modes == 1 and modes[1] == "defend",
        "task4 stand-up " .. policy .. ": writes the committed baseline mode, not the "
        .. "temporary Direct state or the preTickMode (got: " .. table.concat(modes, ",") .. ")")
    assert(#armeds == 1 and armeds[1] == true,
        "task4 stand-up " .. policy .. ": writes the committed baseline armed state")
    local sawEnd = false
    for i = eventsBefore + 1, #localFix.uiTriggeredEvents do
        if localFix.uiTriggeredEvents[i].control == "session_end" then sawEnd = true end
    end
    assert(sawEnd, "task4 stand-up " .. policy .. ": teardown clears the parked MD snapshot")
    assert(localFix.API.getSession() == nil, "task4 stand-up " .. policy .. ": session discarded")
end

-- ── 72. Direct target browser holds unchecked Direct-baseline groups in their
--    staged mode without touching the committed baseline ────────────────────
local function deepCopy72(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = deepCopy72(v) end
    return copy
end

local function deepEqual72(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not deepEqual72(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- Three groups (ga/gb/gc) on one ship, contextID 5, path "p", one turret each
-- (components 27/28/29). `engine` is the mutable table the C stubs read and
-- write, keyed by group name. Returns the write logs so the test can inspect
-- exactly what got sent to the engine.
local function installThreeGroupStubs72(localFix, engine)
    local C = localFix.C
    local groupBuffer = {
        [0] = { path = "p", group = "ga", contextid = 5 },
        [1] = { path = "p", group = "gb", contextid = 5 },
        [2] = { path = "p", group = "gc", contextid = 5 },
    }
    local componentByGroup = { ga = 27, gb = 28, gc = 29 }
    local groupBySlot = { "ga", "gb", "gc" }
    C.GetNumUpgradeGroups = function() return 3 end
    C.GetUpgradeGroups2 = function() return 3 end
    C.GetUpgradeGroupInfo2 = function(_, _, _, _, group)
        return { count = 1, currentcomponent = componentByGroup[group], currentmacro = "",
            slotsize = "", total = 1, operational = 1 }
    end
    C.GetNumUpgradeSlots = function() return 3 end
    C.GetUpgradeSlotCurrentComponent = function(_, _, slot) return componentByGroup[groupBySlot[slot]] end
    C.GetUpgradeSlotGroup = function(_, _, _, slot) return { path = "p", group = groupBySlot[slot] } end
    C.IsComponentOperational = function() return true end
    C.IsPlayerCameraTargetViewPossible = function() return true end
    C.GetExternalTargetViewComponent = function() return 27 end
    C.GetTurretGroupMode2 = function(_, _, _, group) return engine[group].mode end
    C.IsTurretGroupArmed = function(_, _, _, group) return engine[group].armed end
    local modeWrites, armedWrites = {}, {}
    C.SetTurretGroupMode2 = function(_, _, _, group, mode)
        engine[group].mode = mode
        modeWrites[#modeWrites + 1] = { group = group, mode = mode }
    end
    C.SetTurretGroupArmed = function(_, _, _, group, armed)
        engine[group].armed = armed
        armedWrites[#armedWrites + 1] = { group = group, armed = armed }
    end
    localFix.ffiStub.new = function() return groupBuffer end
    return modeWrites, armedWrites
end

local function byGroupName72(sess, name)
    for _, g in ipairs(sess.groups) do
        if g.group == name then return g end
    end
end

-- Values written to one group's field, in write order.
local function writesFor72(list, groupName, field)
    local result = {}
    for _, entry in ipairs(list) do
        if entry.group == groupName then result[#result + 1] = entry[field] end
    end
    return result
end

do
    local fix72 = dofile("tests/support/runtime_fixture.lua").load()
    local engine72 = {
        ga = { mode = "attackenemies", armed = true },
        gb = { mode = "attackenemies", armed = false },
        gc = { mode = "defend", armed = true },
    }
    local modeWrites72, armedWrites72 = installThreeGroupStubs72(fix72, engine72)
    fix72.gcMenu.onShowMenu()

    -- ── A. Browser safety ────────────────────────────────────────────────────
    local sess72 = fix72.API.getSession()
    local ga72, gb72, gc72 = byGroupName72(sess72, "ga"), byGroupName72(sess72, "gb"), byGroupName72(sess72, "gc")
    assert(sess72.checkedGroupKeys[ga72.key] == true and sess72.checkedGroupKeys[gb72.key] == true,
        "72: seeding must check both Direct-baseline groups (ga, gb)")
    assert(sess72.checkedGroupKeys[gc72.key] ~= true,
        "72: seeding must leave the ordinary-mode group (gc) unchecked")

    X4GunneryState.toggleGroup(sess72, gb72.key, sess72.staged[gb72.key].armed)
    assert(sess72.staged[gb72.key].mode == "defend",
        "72: unticking gb with no preTickMode must fall back to defend")
    assert(sess72.checkedGroupKeys[ga72.key] == true, "72: unticking gb must not affect ga")

    X4GunneryState.stageMode(sess72, gc72.key, "attack", true)
    assert(sess72.checkedGroupKeys[gc72.key] ~= true,
        "72: an ordinary staged edit on gc must not check it")

    local baselineCopy72 = deepCopy72(sess72.committedBaseline)
    local stagedCopy72 = deepCopy72(sess72.staged)
    local checkedCopy72 = deepCopy72(sess72.checkedGroupKeys)
    local directModeCopy72 = sess72.directMode

    for i = #modeWrites72, 1, -1 do modeWrites72[i] = nil end
    for i = #armedWrites72, 1, -1 do armedWrites72[i] = nil end
    fix72.resetUITriggeredEvents()
    local mark72 = fix72.callbackCheckpoint()
    assert(fix72.API.startTargetSelection(X4GunneryState.checkedGroups(sess72)) == true,
        "72: startTargetSelection must succeed for a checked mutable group")
    fix72.drainCallbacksSince(mark72)
    assert(sess72.phase == "target_select", "72: browser entry must land in target_select")

    assert(deepEqual72(writesFor72(modeWrites72, "gb", "mode"), { "attackenemies", "defend" }),
        "72: gb must be restored then held in its staged mode, in that order")
    assert(deepEqual72(writesFor72(modeWrites72, "ga", "mode"), { "attackenemies" }),
        "72: ga is checked, so browser entry must only restore it, never re-stage it")
    assert(deepEqual72(writesFor72(modeWrites72, "gc", "mode"), { "defend" }),
        "72: gc's committed baseline is not a Direct mode, so only the restore write reaches it "
        .. "(never its staged 'attack' edit)")

    assert(deepEqual72(writesFor72(armedWrites72, "ga", "armed"), { true }),
        "72: ga gets exactly one armed write, the restore")
    assert(deepEqual72(writesFor72(armedWrites72, "gb", "armed"), { false }),
        "72: gb gets exactly one armed write, the restore -- browser entry never arms/disarms")
    assert(deepEqual72(writesFor72(armedWrites72, "gc", "armed"), { true }),
        "72: gc gets exactly one armed write, the restore")

    assert(deepEqual72(sess72.committedBaseline, baselineCopy72),
        "72: browser entry must never mutate the committed baseline")
    assert(deepEqual72(sess72.staged, stagedCopy72), "72: browser entry must not touch staged")
    assert(deepEqual72(sess72.checkedGroupKeys, checkedCopy72),
        "72: browser entry must not change checked membership")
    assert(sess72.directMode == directModeCopy72, "72: browser entry must not change the policy")

    local payload72
    for i = #fix72.uiTriggeredEvents, 1, -1 do
        local event = fix72.uiTriggeredEvents[i]
        if event.control == "session_commit" then
            payload72 = event.params and event.params.payload
            break
        end
    end
    assert(type(payload72) == "string", "72: holding gb must persist a session_commit payload")

    -- ── B. Explicit exit ─────────────────────────────────────────────────────
    for i = #modeWrites72, 1, -1 do modeWrites72[i] = nil end
    for i = #armedWrites72, 1, -1 do armedWrites72[i] = nil end
    fix72.resetUITriggeredEvents()
    fix72.API.endForMovement()
    local gbModeWrites72 = writesFor72(modeWrites72, "gb", "mode")
    local gbArmedWrites72 = writesFor72(armedWrites72, "gb", "armed")
    assert(gbModeWrites72[#gbModeWrites72] == "attackenemies",
        "72: standing up must revert gb to its committed baseline mode")
    assert(gbArmedWrites72[#gbArmedWrites72] == false,
        "72: standing up must revert gb to its committed baseline armed state")
    assert(engine72.gb.mode == "attackenemies" and engine72.gb.armed == false,
        "72: the engine must actually be left in gb's committed baseline state")
    local sawSessionEnd72 = false
    for _, event in ipairs(fix72.uiTriggeredEvents) do
        if event.control == "session_end" then sawSessionEnd72 = true end
    end
    assert(sawSessionEnd72, "72: standing up must clear the parked MD snapshot")
    assert(fix72.API.getSession() == nil, "72: standing up must discard the session")

    -- ── C. Save/reload ───────────────────────────────────────────────────────
    local fix72b = dofile("tests/support/runtime_fixture.lua").load()
    -- Engine starts in the browser-time live state: gb was held in defend by
    -- part A, ga and gc were untouched.
    local engine72b = {
        ga = { mode = "attackenemies", armed = true },
        gb = { mode = "defend", armed = false },
        gc = { mode = "defend", armed = true },
    }
    local modeWrites72b, armedWrites72b = installThreeGroupStubs72(fix72b, engine72b)
    fix72b.gcMenu.onShowMenu()
    fix72b.gcMenu.shown = true
    local preRestore72b = fix72b.API.getSession()
    fix72b.API.onRestoreEnvelope({ generation = 149, target = 0, payload = payload72 })
    local restored72b = fix72b.API.getSession()
    assert(restored72b ~= preRestore72b, "72c: restoring the saved browser session must swap the session")

    local ga72b, gb72b, gc72b = byGroupName72(restored72b, "ga"), byGroupName72(restored72b, "gb"),
        byGroupName72(restored72b, "gc")
    local function baselineEntry72b(group)
        for _, entry in ipairs(restored72b.committedBaseline) do
            if entry.path == group.path and entry.group == group.group then return entry end
        end
    end
    local restoredGa72b, restoredGb72b, restoredGc72b =
        baselineEntry72b(ga72b), baselineEntry72b(gb72b), baselineEntry72b(gc72b)
    assert(restoredGb72b.mode == "attackenemies" and restoredGb72b.armed == false,
        "72c: gb's committed baseline must restore exactly as saved, never promoted to defend")
    assert(restoredGa72b.mode == "attackenemies" and restoredGa72b.armed == true,
        "72c: ga's committed baseline must restore as saved")
    assert(restoredGc72b.mode == "defend" and restoredGc72b.armed == true,
        "72c: gc's committed baseline must restore as saved")
    assert(restored72b.checkedGroupKeys[gb72b.key] ~= true,
        "72c: gb must not come back checked")
    assert(restored72b.staged[gb72b.key].mode == "defend",
        "72c: gb's staged mode must rebuild to the unticked fallback")
    assert(restored72b.checkedGroupKeys[ga72b.key] == true, "72c: ga must come back checked")

    for i = #modeWrites72b, 1, -1 do modeWrites72b[i] = nil end
    for i = #armedWrites72b, 1, -1 do armedWrites72b[i] = nil end
    fix72b.API.endForMovement()
    local gbModeWrites72b = writesFor72(modeWrites72b, "gb", "mode")
    local gbArmedWrites72b = writesFor72(armedWrites72b, "gb", "armed")
    assert(gbModeWrites72b[#gbModeWrites72b] == "attackenemies",
        "72c: standing up after a reload must restore gb to attackenemies")
    assert(gbArmedWrites72b[#gbArmedWrites72b] == false,
        "72c: standing up after a reload must restore gb's armed state")
    assert(engine72b.gb.mode == "attackenemies" and engine72b.gb.armed == false,
        "72c: the engine must actually land back on gb's committed baseline")
    local sawSessionEnd72b = false
    for _, event in ipairs(fix72b.uiTriggeredEvents) do
        if event.control == "session_end" then sawSessionEnd72b = true end
    end
    assert(sawSessionEnd72b, "72c: standing up after a reload must clear the parked MD snapshot")
    assert(fix72b.API.getSession() == nil, "72c: standing up after a reload must discard the session")
end

print("runtime persistence tests passed")
