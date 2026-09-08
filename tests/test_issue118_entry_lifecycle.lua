-- Issue #118 Task 3: only the regression gaps not already covered by
-- test_runtime_lifecycle.lua and test_runtime_onboard_ingress.lua.

local function countRelease(fix)
    local count, event = 0, nil
    for _, item in ipairs(fix.uiTriggeredEvents) do
        if item.screen == "X4GunneryControl" and item.control == "chair_release" then
            count, event = count + 1, item
        end
    end
    return count, event
end

local function installOneGroup(fix)
    fix.C.GetNumUpgradeGroups = function() return 1 end
    fix.C.GetUpgradeGroups2 = function() return 1 end
    fix.C.GetUpgradeGroupInfo2 = function()
        return { count = 1, currentcomponent = 27, currentmacro = "", slotsize = "", total = 1, operational = 1 }
    end
    fix.C.IsComponentOperational = function() return true end
    fix.ffiStub.new = function()
        return { [0] = { path = "p", group = "g", contextid = 5 } }
    end
end

-- Duplicate physical ingress in the same redirect window emits one request.
do
    local fix = dofile("tests/support/runtime_fixture.lua").load()
    fix.gcMenu.shown = false
    local mark = fix.callbackCheckpoint()
    fix.fireUIEvent("gameplanchange", "cockpit")
    fix.fireUIEvent("gameplanchange", "cockpit")
    fix.drainCallbacksSince(mark)
    local count, event = countRelease(fix)
    assert(count == 1, "duplicate chair ingress must emit exactly one chair_release")
    assert(event.params.ship == 42, "chair_release must keep the observed ship")
    assert(fix.API.getSession() == nil, "chair ingress must not create a pre-release session")
end

-- After a normal onboard exit, both launchers can start a fresh onboard session.
do
    local fix = dofile("tests/support/runtime_fixture.lua").load()
    local State = X4GunneryState
    local control = "cockpit"
    fix.C.GetPlayerCurrentControlGroup = function() return control end
    GetComponentData = function(_, key)
        if key == "isplayerowned" then return true end
    end
    installOneGroup(fix)
    Helper.getMenu = function() return nil end

    -- Existing Map/right-click ingress, then normal onboard exit.
    fix.fireEvent("X4GunneryControl.OpenOnboard", 42)
    local session = fix.API.getSession()
    assert(session and session.origin == "onboard", "precondition: onboard session")
    session.lifecycle = State.lifecycle.owned
    session.phase = "console"
    fix.gcMenu.onCloseElement("close")
    assert(fix.API.getSession() == nil, "onboard exit must clear the session")

    -- Physical-console re-entry may request release again after that exit.
    control = "gunnercontrol"
    fix.resetUITriggeredEvents()
    fix.gcMenu.shown = false
    local mark = fix.callbackCheckpoint()
    fix.fireUIEvent("gameplanchange", "cockpit")
    fix.drainCallbacksSince(mark)
    local count, event = countRelease(fix)
    assert(count == 1, "physical re-entry after exit must emit one chair_release")

    -- Model the MD stopped-control completion by raising the existing onboard event.
    control = "cockpit"
    fix.fireEvent("X4GunneryControl.OpenOnboard", event.params.ship)
    session = fix.API.getSession()
    assert(session and session.origin == "onboard", "physical re-entry must converge to onboard origin")
    session.lifecycle = State.lifecycle.owned
    session.phase = "console"
    fix.gcMenu.onCloseElement("close")
    assert(fix.API.getSession() == nil, "physical-origin onboard exit must clear the session")

    -- Map entry remains reusable after the same lifecycle has exited again.
    fix.fireEvent("X4GunneryControl.OpenOnboard", 42)
    session = fix.API.getSession()
    assert(session and session.origin == "onboard", "Map re-entry after exit must create onboard origin")
end

print("Issue #118 entry lifecycle regression tests passed")
