-- test_runtime_persistence.lua
-- MD event ordering, save/restore, map-suspend/resume, payload handling.

local fix = dofile("tests/support/runtime_fixture.lua").load()
local gcMenu = fix.gcMenu
local API    = fix.API

-- Bring the module into a known state with a live session.
local ok_init, err_init = pcall(function() gcMenu.onShowMenu() end)
assert(ok_init, "onShowMenu() raised during persistence test setup: " .. tostring(err_init))

-- ── 11. map-suspended session resume (Change 1) ─────────────────────────────
-- Confirmed-live bug: closing the Map while seated resets the session to
-- console because DockedMenu re-opens ~70 ms after the MapMenu cleanup
-- callback, before the `reopening` lifecycle transition can complete.
-- The fix: a map-suspended session for the *same* ship must be treated as
-- resumable in onShowMenu(), keeping its phase and not recreating the session.

-- 11a: same ship — session must survive with its phase intact.
-- Reset to a known good state first.
local sess11 = API.getSession()
assert(sess11 ~= nil, "expected a live session for map-suspend resume test")
sess11.shipID    = 42                              -- matches playerShip() stub (id(42)=42)
sess11.phase     = "target_select"
sess11.lifecycle = X4GunneryState.lifecycle.suspendedMap
local preResumeSess = sess11

gcMenu.onShowMenu()

local postResumeSess = API.getSession()
assert(postResumeSess == preResumeSess,
    "BUG (same ship): map-suspended session was discarded and recreated; "
    .. "expected same session object after onShowMenu()")
assert(postResumeSess.phase == "target_select",
    "BUG (same ship): phase was reset to '"
    .. tostring(postResumeSess.phase)
    .. "' instead of 'target_select' after map-suspend resume")
assert(postResumeSess.lifecycle == X4GunneryState.lifecycle.owned,
    "BUG (same ship): lifecycle should be 'owned' after resume, got '"
    .. tostring(postResumeSess.lifecycle) .. "'")
-- 11b: different ship — session must still be discarded and recreated.
-- The ship-identity guard must not be weakened by the fix.
local sess11b = API.getSession()
assert(sess11b ~= nil, "expected a live session for different-ship guard test")
sess11b.shipID    = 99                             -- differs from playerShip()=42
sess11b.phase     = "target_select"
sess11b.lifecycle = X4GunneryState.lifecycle.suspendedMap
local preDiscardSess = sess11b

gcMenu.onShowMenu()

local postDiscardSess = API.getSession()
assert(postDiscardSess ~= preDiscardSess,
    "BUG (different ship): map-suspended session for wrong ship was NOT discarded; "
    .. "the ship-identity guard is broken")
assert(postDiscardSess.phase == "console",
    "BUG (different ship): recreated session should start at console, got '"
    .. tostring(postDiscardSess.phase) .. "'")
assert(postDiscardSess.lifecycle == X4GunneryState.lifecycle.owned,
    "BUG (different ship): recreated session lifecycle should be 'owned', got '"
    .. tostring(postDiscardSess.lifecycle) .. "'")

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
        source.groups = { {
            key = State.groupKey(5, "p", "g"), kind = "group", contextID = 5,
            path = "p", group = "g", componentID = 27, mode = "attack", armed = false,
            operationalCount = 1, totalCount = 1,
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
    local group = {
        key = "pov61", kind = "group", contextID = 5, path = "p", group = "g",
        componentID = 10, displayName = "Camera group", totalCount = 3,
        operationalCount = 3, mode = "attack", armed = false, members = {
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
    { button = 71, cameraMemberID = 12, label = "Next Turret" },
    { button = 72, cameraMemberID = 10, label = "Previous Turret" },
}) do
    local localFix, localSession, group = povFixture61()
    localSession.povAnchor, localSession.povMode = "target", "cinematic"
    localFix.gcMenu.display()
    local button = localFix.buttonByText("text:20991:" .. tostring(case.button))
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

print("runtime persistence tests passed")
