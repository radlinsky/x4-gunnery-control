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

print("runtime coverage tests passed")
