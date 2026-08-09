-- Coverage for the resume-route soft-target re-point fix.
--
-- Both the Test Lab reopen route (resuming) and the Map suspend route
-- (mapSuspendResume) re-enter the engaged view without re-applying the engine
-- soft target. The fix hands session.aimTargetID to session.repointTargetID so
-- the watchdog's attemptRepoint() picks it up. Auto mode must not set it because
-- Auto never shows a soft target.

local fix = dofile("tests/support/runtime_fixture.lua").load()
local State = X4GunneryState

-- Shared group setup so readGroups() returns a camera-capable member.
local groupBuffer = { [0] = { path = "p", group = "g", contextid = 5 } }
fix.ffiStub.new = function() return groupBuffer end
fix.C.GetNumUpgradeGroups = function() return 1 end
fix.C.GetUpgradeGroups2 = function() return 1 end
fix.C.GetUpgradeGroupInfo2 = function()
    return { count = 1, currentcomponent = 27, currentmacro = "", slotsize = "",
             total = 1, operational = 1 }
end
fix.C.GetNumUpgradeSlots = function() return 1 end
fix.C.GetUpgradeSlotCurrentComponent = function() return 27 end
fix.C.GetUpgradeSlotGroup = function() return { path = "p", group = "g" } end
fix.C.IsComponentOperational = function() return true end
fix.C.IsPlayerCameraTargetViewPossible = function() return true end
fix.C.GetExternalTargetViewComponent = function() return 27 end

-- ── helper: build a Direct-engaged session via the Test Lab button route ─────
local function directEngagedResume(aimTarget)
    fix.gcMenu.onShowMenu()
    local session = fix.API.getSession()
    assert(session, "expected a session")
    session.phase, session.controlMode = "engaged", "direct"
    session.aimTargetID = aimTarget
    session.cameraMemberID = 27
    session.directSnapshots = {}
    -- Register a no-op Test Lab and click the button so openTestLab() sets
    -- resumePending=true and lifecycle=reopening — the same state a real
    -- Test Lab close hands back to onShowMenu.
    fix.API.registerTestLab({ open = function() end })
    fix.gcMenu.display()
    local button = fix.buttonByText(ReadText(20991, 32))
    assert(button and button.handlers.onClick, "expected Test Lab button")
    button.handlers.onClick()
    assert(session.lifecycle == State.lifecycle.reopening,
        "Test Lab open must park session in reopening lifecycle")
    -- Clear any repointTargetID the button click might have left so we only
    -- observe the one set by onShowMenu.
    session.repointTargetID = nil
    return session
end

-- ── 1. Direct + resuming: repointTargetID must be set ────────────────────────
do
    local fix2 = dofile("tests/support/runtime_fixture.lua").load()
    -- Copy group stubs into the fresh fixture.
    fix2.ffiStub.new = function() return groupBuffer end
    fix2.C.GetNumUpgradeGroups = function() return 1 end
    fix2.C.GetUpgradeGroups2 = function() return 1 end
    fix2.C.GetUpgradeGroupInfo2 = function()
        return { count = 1, currentcomponent = 27, currentmacro = "", slotsize = "",
                 total = 1, operational = 1 }
    end
    fix2.C.GetNumUpgradeSlots = function() return 1 end
    fix2.C.GetUpgradeSlotCurrentComponent = function() return 27 end
    fix2.C.GetUpgradeSlotGroup = function() return { path = "p", group = "g" } end
    fix2.C.IsComponentOperational = function() return true end
    fix2.C.IsPlayerCameraTargetViewPossible = function() return true end
    fix2.C.GetExternalTargetViewComponent = function() return 27 end
    fix2.gcMenu.onShowMenu()
    local session = fix2.API.getSession()
    session.phase, session.controlMode = "engaged", "direct"
    session.aimTargetID = 77
    session.cameraMemberID = 27
    session.directSnapshots = {}
    fix2.API.registerTestLab({ open = function() end })
    fix2.gcMenu.display()
    local btn = fix2.buttonByText(ReadText(20991, 32))
    assert(btn and btn.handlers.onClick, "expected Test Lab button (direct resume case)")
    btn.handlers.onClick()
    assert(session.lifecycle == State.lifecycle.reopening,
        "Test Lab must park session in reopening for direct resume case")
    session.repointTargetID = nil
    -- This is the resume: onShowMenu sees resumePending=true + reopening lifecycle.
    fix2.gcMenu.onShowMenu()
    assert(fix2.API.getSession() == session,
        "resume must keep the same session object")
    assert(session.repointTargetID == session.aimTargetID,
        "Direct resume must set repointTargetID so the watchdog re-applies the soft target; got "
        .. tostring(session.repointTargetID))
end

-- ── 2. Auto + resuming: repointTargetID must NOT be set ──────────────────────
do
    local fix3 = dofile("tests/support/runtime_fixture.lua").load()
    fix3.ffiStub.new = function() return groupBuffer end
    fix3.C.GetNumUpgradeGroups = function() return 1 end
    fix3.C.GetUpgradeGroups2 = function() return 1 end
    fix3.C.GetUpgradeGroupInfo2 = function()
        return { count = 1, currentcomponent = 27, currentmacro = "", slotsize = "",
                 total = 1, operational = 1 }
    end
    fix3.C.GetNumUpgradeSlots = function() return 1 end
    fix3.C.GetUpgradeSlotCurrentComponent = function() return 27 end
    fix3.C.GetUpgradeSlotGroup = function() return { path = "p", group = "g" } end
    fix3.C.IsComponentOperational = function() return true end
    fix3.C.IsPlayerCameraTargetViewPossible = function() return true end
    fix3.C.GetExternalTargetViewComponent = function() return 27 end
    fix3.gcMenu.onShowMenu()
    local session = fix3.API.getSession()
    session.phase, session.controlMode = "engaged", "auto"
    session.aimTargetID = 77
    session.cameraMemberID = 27
    fix3.API.registerTestLab({ open = function() end })
    fix3.gcMenu.display()
    local btn = fix3.buttonByText(ReadText(20991, 32))
    assert(btn and btn.handlers.onClick, "expected Test Lab button (auto resume case)")
    btn.handlers.onClick()
    assert(session.lifecycle == State.lifecycle.reopening,
        "Test Lab must park session in reopening for auto resume case")
    session.repointTargetID = nil
    fix3.gcMenu.onShowMenu()
    assert(fix3.API.getSession() == session, "auto resume must keep session object")
    assert(session.repointTargetID == nil,
        "Auto resume must NOT set repointTargetID; Auto never shows a soft target")
end

print("runtime coverage resume repoint tests passed")
