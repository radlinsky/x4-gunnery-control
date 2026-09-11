-- Focused runtime edges for the executable-line coverage contract. These use
-- the same public test hooks and captured Helper button handlers as the other
-- runtime suites; no production-only behavior is simulated here.
local function fresh()
    local fix = dofile("tests/support/runtime_fixture.lua").load()
    local group = fix.makeGroup{ key = "g" }
    fix.gcMenu.onShowMenu()
    local session = fix.API.getSession()
    session.groups, session.checkedGroupKeys = { group }, { g = true }
    session.cameraMemberID = 27
    return fix, group, session
end

local function button(fix, id)
    local entry = fix.buttonByText("text:20991:" .. tostring(id))
    assert(entry and entry.handlers and type(entry.handlers.onClick) == "function",
        "expected clickable button " .. tostring(id))
    return entry.handlers.onClick
end

-- Test Lab is reachable from the console, engaged panel, and target browser.
-- Capturing the actual UI handler verifies each row calls the shared suspend
-- route, parks the session, and opens the registered Test Lab exactly once.
do
    for _, phase in ipairs({ "console", "engaged", "target_select" }) do
        local fix, _, session = fresh()
        local opened = 0
        fix.API.registerTestLab({ open = function() opened = opened + 1 end })
        session.phase = phase
        session.controlMode = phase == "engaged" and "auto" or nil
        session.selectedGroupKey, session.selectedMemberID = "g", 27
        fix.gcMenu.display()
        button(fix, 32)()
        assert(opened == 1, "Test Lab handler must open once from " .. phase)
        assert(session.lifecycle == X4GunneryState.lifecycle.reopening,
            "Test Lab handler must park " .. phase .. " session for reload")
        assert(fix.uiTriggeredEvents[#fix.uiTriggeredEvents].control == "session_commit",
            "Test Lab handler must persist " .. phase .. " session")
    end
end

-- The ordinary console update stays on Helper's updater: only an engaged frame
-- earns the independent addon callback.
do
    local fix, _, session = fresh()
    fix.gcMenu.onUpdate()
    assert(fix.API.getSession() == session, "console onUpdate must keep the session")
    assert(fix.getOnUpdateCallback() == nil,
        "console onUpdate must not install the engaged independent updater")
end

-- Once the session is legitimately parked, the independent updater has no owner
-- left to serve and must relinquish its slot.
do
    local fix, _, session = fresh()
    session.phase, session.controlMode = "engaged", "auto"
    session.selectedGroupKey, session.selectedMemberID = "g", 27
    fix.gcMenu.display()
    assert(fix.getOnUpdateCallback() ~= nil, "engaged display must install the updater")
    session.lifecycle = X4GunneryState.lifecycle.reopening
    fix.invokeOnUpdate()
    assert(fix.getOnUpdateCallback() == nil,
        "the engaged updater must remove itself once the session is not owned")
end

-- Helper can auto-hide the menu without onCloseElement. Cleanup only arms the
-- watchdog; the watchdog confirms the loss and discards the orphan.
do
    local fix, _, session = fresh()
    local now = 0
    GetCurRealTime = function() return now end
    session.phase, session.controlMode = "engaged", "auto"
    session.selectedGroupKey, session.selectedMemberID = "g", 27
    fix.gcMenu.display()
    local function overlay()
        for _, entry in ipairs(fix.View.menus) do
            if entry.id == "X4GunneryOverlay" then return entry end
        end
    end
    assert(overlay(), "engaged display must register the overlay")
    fix.gcMenu.shown = false
    fix.gcMenu.cleanup()
    assert(fix.API.getSession() == session and session.autoHideAt == now,
        "unexpected menu loss must arm the watchdog, not destroy the session")
    now = now + 1
    fix.API.runSessionWatchdog()
    assert(fix.API.getSession() == nil, "the watchdog must discard the orphaned session")
    assert(overlay() == nil, "the watchdog must remove the engaged overlay registration")
end

-- Defensive engaged-overlay edges: a rebind with no recreated frame, a display
-- whose Helper registration vanished before the retag, and a retained
-- fullscreen descriptor caught by a real teardown.
local function engaged()
    local fix, group, session = fresh()
    session.phase, session.controlMode = "engaged", "auto"
    session.selectedGroupKey, session.selectedMemberID = "g", 27
    return fix, group, session
end

local function overlayEntry(fix)
    for _, entry in ipairs(fix.View.menus) do
        if entry.id == "X4GunneryOverlay" then return entry end
    end
end

do
    local fix, _, session = engaged()
    fix.gcMenu.display()
    local entry = overlayEntry(fix)
    assert(pcall(entry.callback, {}),
        "a rebind without recreated frame ids must return safely")
    assert(fix.API.getSession() == session and session.phase == "engaged"
            and session.controlMode == "auto" and overlayEntry(fix) == entry
            and fix.getOnUpdateCallback() ~= nil,
        "a failed rebind must leave the engaged session and overlay usable")
end

do
    local fix, group, session = engaged()
    session.controlMode = "direct"
    session.engagePending, session.engagePendingSince = true, 1
    session.committedBaseline = { { kind = "group", contextID = group.contextID,
        path = group.path, group = group.group, shipID = session.shipID,
        mode = "attack", armed = false } }
    group.mode, group.armed = "attackenemies", true
    local modeWrites, armedWrites = {}, {}
    fix.C.SetTurretGroupMode2 = function(_, _, _, _, mode)
        modeWrites[#modeWrites + 1] = tostring(mode)
    end
    fix.C.SetTurretGroupArmed = function(_, _, _, _, armed)
        armedWrites[#armedWrites + 1] = armed
    end
    local registerMenu = fix.View.registerMenu
    fix.View.registerMenu = function(id, ...)
        if id ~= "Helper0" then return registerMenu(id, ...) end
    end
    fix.gcMenu.display()
    fix.View.registerMenu = registerMenu
    assert(fix.API.getSession() == session and session.phase == "console"
            and fix.getOnUpdateCallback() == nil,
        "a missing Helper registration must safely abandon engaged mode and its updater")
    assert(session.controlMode == nil and not session.engagePending and not session.engagePendingSince,
        "a missing Helper registration must clear Direct and its pending transition")
    assert(modeWrites[#modeWrites] == "attack" and armedWrites[#armedWrites] == false,
        "a missing Helper registration must restore the pre-Direct turret state")
    assert(overlayEntry(fix) == nil,
        "a missing Helper registration must not leak the custom Gunnery overlay")
end

do
    local fix, group, session = fresh()
    group.members = { { componentID = 27, displayName = "T", operational = true,
        cameraSupported = true, componentKey = "27" } }
    session.phase = "target_select"
    session.staged = { g = { mode = "defend", armed = true } }
    session.committedBaseline = { { kind = "group", contextID = group.contextID,
        path = group.path, group = group.group, shipID = session.shipID,
        mode = group.mode, armed = group.armed } }
    fix.C.SetSofttarget = function() return true end
    fix.C.SetPlayerCameraTargetView = function() return true end
    fix.C.GetContextByClass = function(component, class, force)
        if class == "container" and force == true then return 500 end
        return 42
    end
    local modeWrites, armedWrites = {}, {}
    fix.C.SetTurretGroupMode2 = function(_, _, _, _, mode)
        modeWrites[#modeWrites + 1] = tostring(mode)
    end
    fix.C.SetTurretGroupArmed = function(_, _, _, _, armed)
        armedWrites[#armedWrites + 1] = armed
    end
    assert(fix.API.engageTarget(501),
        "partial-registration precondition: real Direct engagement must succeed")
    assert(session.engagePending and group.mode ~= "attack" and group.armed == true,
        "partial-registration precondition: Direct temporary state must be live")
    fix.View.maxFrames = 1
    fix.gcMenu.display()
    assert(fix.API.getSession() == session and session.phase == "console"
            and fix.getOnUpdateCallback() == nil,
        "a partial initial overlay registration must leave engaged mode and its updater")
    assert(session.controlMode == nil and not session.engagePending and not session.engagePendingSince,
        "a partial initial overlay registration must clear Direct and its pending transition")
    assert(modeWrites[#modeWrites] == "attack" and armedWrites[#armedWrites] == false,
        "a partial initial overlay registration must restore the real pre-Direct turret state")
    assert(overlayEntry(fix) == nil,
        "a partial initial overlay registration must not leak the custom Gunnery overlay")
    assert(fix.gcMenu.frame and button(fix, 15),
        "a partial initial overlay registration must leave the normal console usable")
end

do
    local fix = engaged()
    local now = 0
    GetCurRealTime = function() return now end
    fix.gcMenu.display()
    fix.setFullscreenMenuDisplayed(true)
    fix.invokeOnUpdate()
    fix.View.maxFrames = 0
    local restoreCalls = 0
    local registerMenu = fix.View.registerMenu
    fix.View.registerMenu = function(id, ...)
        if id == "X4GunneryOverlay" then restoreCalls = restoreCalls + 1 end
        return registerMenu(id, ...)
    end
    fix.setFullscreenMenuDisplayed(false)
    fix.invokeOnUpdate()
    fix.invokeOnUpdate()
    fix.invokeOnUpdate()
    local restoreFailureLogs = 0
    for _, line in ipairs(fix.getCapturedLog()) do
        if string.find(line, "engaged overlay registration could not be restored", 1, true) then
            restoreFailureLogs = restoreFailureLogs + 1
        end
    end
    assert(overlayEntry(fix) == nil
            and not fix.logContains("engaged overlay restored after fullscreen takeover")
            and restoreCalls == 1 and restoreFailureLogs == 1,
        "a sustained capacity shortage must throttle fullscreen restoration retries")
    fix.View.maxFrames = 5
    now = now + 0.5
    fix.invokeOnUpdate()
    assert(overlayEntry(fix) ~= nil
            and fix.logContains("engaged overlay restored after fullscreen takeover"),
        "a refused fullscreen restoration must retain its descriptor and retry")
end

do
    local fix, _, session = engaged()
    local now = 0
    GetCurRealTime = function() return now end
    fix.gcMenu.display()
    fix.setFullscreenMenuDisplayed(true)
    fix.invokeOnUpdate()
    assert(overlayEntry(fix) == nil and fix.gcMenu.frame,
        "fullscreen takeover must unregister the overlay while retaining its descriptor")
    local released = 0
    ReleaseDescriptor = function() released = released + 1 end
    -- Teardown wins the race: the takeover ends without anyone restoring first.
    fix.setFullscreenMenuDisplayed(false)
    fix.gcMenu.shown = false
    fix.gcMenu.cleanup()
    now = now + 1
    fix.API.runSessionWatchdog()
    assert(released > 0, "a real teardown must release the retained overlay descriptor")
    fix.invokeOnUpdate()
    assert(overlayEntry(fix) == nil,
        "a released overlay descriptor must not be restored after the takeover ends")
end

-- Live race: Test Lab's closeMenuAndOpenNewMenu leaves a real gap with Gunnery
-- hidden and no external menu reported. The generic watchdog must not read that
-- as a finished external-menu cleanup and reopen Gunnery over the Test Lab.
do
    local fix, _, session = fresh()
    local opened = 0
    fix.API.registerTestLab({ open = function()
        opened = opened + 1
        fix.gcMenu.shown = false
    end })
    fix.gcMenu.display()
    local reopens = 0
    local realOpenMenu = OpenMenu
    OpenMenu = function(name, ...)
        if name == "X4GunneryMenu" then reopens = reopens + 1 end
        return realOpenMenu and realOpenMenu(name, ...)
    end
    button(fix, 32)()
    assert(opened == 1, "Test Lab handoff must open the Test Lab once")
    assert(session.lifecycle == X4GunneryState.lifecycle.reopening
        and fix.API.getSession() == session, "handoff must park this exact session")
    fix.API.runSessionWatchdog()
    OpenMenu = realOpenMenu
    assert(reopens == 0, "watchdog must not reopen Gunnery during the Test Lab handoff gap")
    assert(fix.API.getSession() == session, "the parked session must survive the gap")
    fix.gcMenu.shown = true
    fix.gcMenu.onShowMenu()
    assert(fix.API.getSession() == session
        and session.lifecycle == X4GunneryState.lifecycle.owned,
        "Test Lab's explicit return must restore the same session to owned")
end

print("runtime coverage tests passed")
