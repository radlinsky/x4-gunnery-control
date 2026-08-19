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

-- ── helpers for the watchdog-driven retry scenarios ────────────────────────
-- Fresh fixture with the shared group stubs applied (readGroups must find a
-- camera-capable member for the resume camera route).
local function freshFix()
    local f = dofile("tests/support/runtime_fixture.lua").load()
    f.ffiStub.new = function() return groupBuffer end
    f.C.GetNumUpgradeGroups = function() return 1 end
    f.C.GetUpgradeGroups2 = function() return 1 end
    f.C.GetUpgradeGroupInfo2 = function()
        return { count = 1, currentcomponent = 27, currentmacro = "", slotsize = "",
                 total = 1, operational = 1 }
    end
    f.C.GetNumUpgradeSlots = function() return 1 end
    f.C.GetUpgradeSlotCurrentComponent = function() return 27 end
    f.C.GetUpgradeSlotGroup = function() return { path = "p", group = "g" } end
    f.C.IsComponentOperational = function() return true end
    f.C.IsPlayerCameraTargetViewPossible = function() return true end
    f.C.GetExternalTargetViewComponent = function() return 27 end
    return f
end

-- Drives a Direct engaged Test Lab resume (park + reopen) through the real
-- button route and returns the session exactly as onShowMenu left it.
local function directTestLabResume(f, aimTarget)
    f.gcMenu.onShowMenu()
    local s = f.API.getSession()
    s.phase, s.controlMode = "engaged", "direct"
    s.aimTargetID = aimTarget
    s.cameraMemberID = 27
    s.directSnapshots = {}
    f.API.registerTestLab({ open = function() end })
    f.gcMenu.display()
    local button = f.buttonByText(ReadText(20991, 32))
    assert(button and button.handlers.onClick, "expected Test Lab button")
    button.handlers.onClick()
    assert(s.lifecycle == State.lifecycle.reopening,
        "Test Lab open must park session in reopening lifecycle")
    s.repointTargetID = nil
    f.gcMenu.onShowMenu()
    assert(f.API.getSession() == s, "resume must keep the same session object")
    assert(s.repointTargetID == aimTarget, "resume must queue the aim target for re-point")
    return s
end

-- ── 3. Direct resume: first refusal leaves exactly one bounded retry ───────
-- The engine refuses SetSofttarget once while it settles after the Test Lab
-- menu transition, then accepts the identical write. The first watchdog must
-- not abandon (the Task 6 failure) but leave a single bounded retry; the
-- second watchdog retries, succeeds, and clears every re-point field.
do
    local f = freshFix()
    local s = directTestLabResume(f, 77)
    local calls = {}
    f.C.SetSofttarget = function(target, connection)
        calls[#calls + 1] = target
        return #calls >= 2  -- refuse the first write, accept the retry
    end
    f.API.runSessionWatchdog()
    assert(#calls == 1, "first watchdog must make exactly one SetSofttarget call")
    assert(calls[1] == 77, "first watchdog must attempt the resumed aim target")
    assert(s.repointTargetID == 77,
        "first refusal must re-arm the re-point instead of abandoning; got "
        .. tostring(s.repointTargetID))
    assert(s.repointRetryArmed == true,
        "first refusal must leave a bounded one-retry allowance pending")
    assert(s.repointResumeRetry == 77,
        "pending retry must stay bound to the aim target it was granted for")
    assert(s.aimTargetID == 77, "aim target must remain 77 after the first refusal")
    f.API.runSessionWatchdog()
    assert(#calls == 2, "second watchdog must make exactly one retry call")
    assert(calls[2] == 77, "retry must re-write the same soft target")
    assert(s.repointTargetID == nil, "successful retry must clear the re-point")
    assert(s.repointRetryArmed == nil, "successful retry must clear the armed retry")
    assert(s.repointResumeRetry == nil, "successful retry must clear the resume grant")
    assert(s.aimTargetID == 77, "aim target must remain 77 after the successful retry")
    f.API.runSessionWatchdog()
    assert(#calls == 2, "cleared re-point state must not schedule further writes")
end

-- ── 4. Direct resume: a second refusal abandons (retry at most once) ───────
do
    local f = freshFix()
    local s = directTestLabResume(f, 77)
    local calls = 0
    f.C.SetSofttarget = function()
        calls = calls + 1
        return false
    end
    f.API.runSessionWatchdog()
    assert(calls == 1 and s.repointTargetID == 77,
        "first refusal must re-arm the single bounded retry")
    f.API.runSessionWatchdog()
    assert(calls == 2, "second watchdog must make exactly one retry call")
    assert(s.repointTargetID == nil,
        "second refusal must abandon normally (no re-point left pending)")
    assert(s.repointRetryArmed == nil, "second refusal must clear the armed retry")
    assert(s.repointResumeRetry == nil, "second refusal must clear the resume grant")
    f.API.runSessionWatchdog()
    assert(calls == 2, "an abandoned re-point must never be retried again")
end

-- ── 5. An aim-target change while the retry is pending cancels it ──────────
do
    local f = freshFix()
    local s = directTestLabResume(f, 77)
    local calls = 0
    f.C.SetSofttarget = function()
        calls = calls + 1
        return false
    end
    f.API.runSessionWatchdog()
    assert(s.repointTargetID == 77, "first refusal must re-arm the retry")
    s.aimTargetID = 88  -- the player re-targeted while the retry is pending
    f.API.runSessionWatchdog()
    assert(calls == 1, "aim-target drift must cancel the pending retry (no write)")
    assert(s.repointTargetID == nil, "drift must drop the queued re-point")
    assert(s.repointResumeRetry == nil, "drift must clear the resume grant")
    assert(s.repointRetryArmed == nil, "drift must clear the armed retry")
end

-- ── 6. A control-mode change while the retry is pending cancels it ─────────
do
    local f = freshFix()
    local s = directTestLabResume(f, 77)
    local calls = 0
    f.C.SetSofttarget = function()
        calls = calls + 1
        return false
    end
    f.API.runSessionWatchdog()
    assert(s.repointTargetID == 77, "first refusal must re-arm the retry")
    s.controlMode = "auto"  -- e.g. handed to Auto-engage while the retry is pending
    f.API.runSessionWatchdog()
    assert(calls == 1, "control-mode drift must cancel the pending retry (no write)")
    assert(s.repointTargetID == nil, "drift must drop the queued re-point")
    assert(s.repointResumeRetry == nil, "drift must clear the resume grant")
    assert(s.repointRetryArmed == nil, "drift must clear the armed retry")
end

print("runtime coverage resume repoint tests passed")
