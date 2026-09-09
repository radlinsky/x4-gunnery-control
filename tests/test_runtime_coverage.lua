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
    local fix = engaged()
    fix.gcMenu.display()
    overlayEntry(fix).callback({})
    assert(fix.logContains("engaged overlay descriptor could not be restored"),
        "a rebind without a recreated frame id must be reported, not crash")
end

do
    local fix = engaged()
    local registerMenu = fix.View.registerMenu
    fix.View.registerMenu = function(id, ...)
        if id ~= "Helper0" then return registerMenu(id, ...) end
    end
    fix.gcMenu.display()
    fix.View.registerMenu = registerMenu
    assert(fix.logContains("engaged overlay registration was not found after frame display"),
        "a missing Helper registration must be reported, not crash the retag")
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
