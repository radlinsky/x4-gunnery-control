-- Resume-route soft-target re-point regressions.
--
-- Both the Test Lab reopen route (resuming) and the Map suspend route
-- (mapSuspendResume) re-enter the engaged view without re-applying the engine
-- soft target. The fix hands session.aimTargetID to session.repointTargetID so
-- the watchdog's attemptRepoint() picks it up. Auto mode must not set it because
-- Auto never shows a soft target.

dofile("tests/support/runtime_fixture.lua").load()
local State = X4GunneryState

-- A single synthetic group is returned by each independent resume fixture.
local groupBuffer = { [0] = { path = "p", group = "g", contextid = 5 } }

-- Each resume check uses an independent fixture with one camera-capable turret.
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

-- Auto resume must not re-point its target ──────────────────────
do
    local fix3 = freshFix()
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
    -- Generic parked session from here on; the Test Lab handoff gap has its own
    -- coverage and deliberately suspends watchdog reopening while it is set.
    s.testLabHandoffPending = nil
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

-- ── 7. A parked session whose chair context went invalid is discarded ──────
do
    local f = freshFix()
    f.gcMenu.onShowMenu()
    local s = f.API.getSession()
    s.phase, s.controlMode = "engaged", "direct"
    s.aimTargetID = 77
    s.cameraMemberID = 27
    s.directSnapshots = {}
    f.API.registerTestLab({ open = function() end })
    f.gcMenu.display()
    local button = f.buttonByText(ReadText(20991, 32))
    assert(button and button.handlers.onClick, "expected Test Lab button")
    button.handlers.onClick()
    assert(s.lifecycle == State.lifecycle.reopening,
        "Test Lab open must park session in reopening lifecycle")
    -- Generic parked session from here on; the Test Lab handoff gap has its own
    -- coverage and deliberately suspends watchdog reopening while it is set.
    s.testLabHandoffPending = nil
    s.repointTargetID = nil
    -- The player left the gunner chair while the Test Lab was up.
    f.C.GetPlayerCurrentControlGroup = function() return "cockpit" end
    assert(f.API.sessionContextValid() == false,
        "leaving the gunner chair must invalidate the parked session context")
    f.API.runSessionWatchdog()
    assert(f.API.getSession() == nil,
        "a parked session with an invalid chair context must be discarded, not reopened")
end

print("runtime coverage resume repoint tests passed")
