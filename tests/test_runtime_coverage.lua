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

print("runtime coverage tests passed")
