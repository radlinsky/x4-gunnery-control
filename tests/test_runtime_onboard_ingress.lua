-- Tasks 3/4/5 (#68): onboard Map ingress, origin-aware exit/restore, and
-- Reload-UI origin persistence. Drives onOpenOnboard (the MD->Lua handler),
-- the leaveSession/leaveOnboard exit dispatch, and onRestoreEnvelope's
-- onboard/backstop paths through the shared runtime fixture.

local State = X4GunneryState  -- populated by the fixture load below

-- Install FFI stubs so readGroups() returns exactly one usable turret group.
-- Mirrors tests/test_runtime_coverage_restore.lua.
local function installOneGroup(fix)
    local groupBuffer = { [0] = { path = "p", group = "g", contextid = 5 } }
    fix.C.GetNumUpgradeGroups   = function() return 1 end
    fix.C.GetUpgradeGroups2     = function() return 1 end
    fix.C.GetUpgradeGroupInfo2  = function()
        return { count = 1, currentcomponent = 27, currentmacro = "", slotsize = "", total = 1, operational = 1 }
    end
    fix.C.IsComponentOperational = function() return true end
    fix.ffiStub.new = function() return groupBuffer end
end

local function ownPlayerShip()
    -- componentData() reads the global GetComponentData; make ship 42 player-owned.
    GetComponentData = function(_, key)
        if key == "isplayerowned" then return true end
        return nil
    end
end

-- ── onOpenOnboard: refusals (no session created) ─────────────────────────────
do
    local fix = dofile("tests/support/runtime_fixture.lua").load()
    State = X4GunneryState
    -- No onShowMenu: session stays nil, so each call exercises a refusal branch.
    fix.fireEvent("X4GunneryControl.OpenOnboard", 0)      -- id() -> 0
    assert(fix.API.getSession() == nil, "onboard ingress ignores a zero ship id")

    fix.fireEvent("X4GunneryControl.OpenOnboard", 99)     -- playerShip()==42, mismatch
    assert(fix.API.getSession() == nil, "onboard ingress ignores a ship the player is not inside")

    -- ship 42 matches playerShip() but is not player-owned (default GetComponentData).
    fix.fireEvent("X4GunneryControl.OpenOnboard", 42)
    assert(fix.API.getSession() == nil, "onboard ingress ignores a non-player-owned ship")

    -- owned, but readGroups() defaults to no usable turret group.
    ownPlayerShip()
    fix.fireEvent("X4GunneryControl.OpenOnboard", 42)
    assert(fix.API.getSession() == nil, "onboard ingress ignores a ship with no usable turret group")
end

-- ── onOpenOnboard: success + Map handoff + already-active guard ───────────────
do
    local fix = dofile("tests/support/runtime_fixture.lua").load()
    State = X4GunneryState
    ownPlayerShip()
    installOneGroup(fix)
    -- Capture the Map->console handoff: the deferred callback should close the
    -- MapMenu and open X4GunneryMenu (mirrors redirectDockedMenu).
    local handoff
    Helper.getMenu = function(name) return name == "MapMenu" and { name = "MapMenu" } or nil end
    Helper.closeMenuAndOpenNewMenu = function(src, newName) handoff = { src = src, newName = newName } end

    local mark = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.OpenOnboard", 42)
    local s = fix.API.getSession()
    assert(s ~= nil, "onboard ingress must create a session")
    assert(s.origin == "onboard", "ingress session origin must be onboard")
    assert(s.lifecycle == State.lifecycle.suspendedMap,
        "onboard ingress must park the session as suspendedMap")
    assert(#s.groups >= 1, "onboard ingress must capture the usable turret group(s)")
    assert(next(s.committedBaseline or {}) ~= nil, "onboard ingress must seed the baseline")

    fix.drainCallbacksSince(mark)
    assert(handoff and handoff.newName == "X4GunneryMenu" and handoff.src.name == "MapMenu",
        "onboard ingress must close the Map and open X4GunneryMenu")

    -- A second OpenOnboard while a session exists is a no-op (guard at entry).
    fix.fireEvent("X4GunneryControl.OpenOnboard", 42)
    assert(fix.API.getSession() == s, "a second OpenOnboard must not replace the live session")
end

-- ── onOpenOnboard: Map handoff fallback when MapMenu is unavailable ───────────
do
    local fix = dofile("tests/support/runtime_fixture.lua").load()
    State = X4GunneryState
    ownPlayerShip()
    installOneGroup(fix)
    Helper.getMenu = function() return nil end  -- no Map to close
    local mark = fix.callbackCheckpoint()
    fix.fireEvent("X4GunneryControl.OpenOnboard", 42)
    fix.drainCallbacksSince(mark)
    -- Session stays parked; the watchdog/gameplanchange reopen path still applies.
    assert(fix.API.getSession() ~= nil and fix.API.getSession().lifecycle == State.lifecycle.suspendedMap,
        "with no MapMenu the onboard session stays parked for the watchdog reopen")
    assert(fix.logContains("MapMenu unavailable"), "must log the missing-Map fallback")
end

-- ── Onboard exit: leaveSession -> leaveOnboard (no GetUp), origin restore ─────
do
    local fix = dofile("tests/support/runtime_fixture.lua").load()
    State = X4GunneryState
    ownPlayerShip()
    installOneGroup(fix)
    fix.fireEvent("X4GunneryControl.OpenOnboard", 42)
    local s = fix.API.getSession()
    assert(s and s.origin == "onboard", "precondition: onboard session")
    -- Bring the parked session to an owned console so onCloseElement reaches the exit.
    s.lifecycle = State.lifecycle.owned
    s.phase = "console"

    local getUpCalled, camRestores = false, 0
    fix.C.GetUp = function() getUpCalled = true; return true end
    fix.C.SetPlayerCameraCockpitView = function() camRestores = camRestores + 1; return true end

    local mark = fix.callbackCheckpoint()
    fix.gcMenu.onCloseElement("close")
    assert(fix.API.getSession() == nil, "onboard exit must discard the session")
    assert(not getUpCalled, "onboard exit must NOT call GetUp()")
    assert(camRestores >= 1, "onboard exit must restore the standing camera")
    fix.drainCallbacksSince(mark)
    assert(fix.getCloseMenuCalls() >= 1, "onboard exit must close the menu on a later tick")
end

-- ── Reload-UI restore: onboard payload returns to console, keeps origin ──────
do
    local fix = dofile("tests/support/runtime_fixture.lua").load()
    State = X4GunneryState
    fix.gcMenu.onShowMenu()
    local seed = fix.API.getSession()
    local payload = State.encode(State.saveState({
        shipID = seed.shipID, shipName = seed.shipName, phase = "target_select",
        origin = "onboard", groups = {}, checkedGroupKeys = {}, directSnapshots = {},
    }))
    local camRestores = 0
    fix.C.SetPlayerCameraCockpitView = function() camRestores = camRestores + 1; return true end
    fix.API.onRestoreEnvelope({ generation = 1, target = 0, payload = payload })
    local r = fix.API.getSession()
    assert(r ~= nil and r.origin == "onboard", "restore must preserve the onboard origin")
    assert(r.phase == "console", "non-engaged onboard restore returns to console")
    assert(camRestores >= 1, "onboard returnToConsole must restore the standing camera")
end

-- ── Reload-UI restore: context backstop refuses a chair payload off the seat ─
do
    local fix = dofile("tests/support/runtime_fixture.lua").load()
    State = X4GunneryState
    fix.gcMenu.onShowMenu()
    local seed = fix.API.getSession()
    local payload = State.encode(State.saveState({
        shipID = seed.shipID, shipName = seed.shipName, phase = "console",
        origin = "chair", groups = {}, checkedGroupKeys = {}, directSnapshots = {},
    }))
    -- Chair origin off the gunner seat: sessionContextValid() must reject it.
    fix.C.GetPlayerCurrentControlGroup = function() return "cockpit" end
    fix.API.onRestoreEnvelope({ generation = 1, target = 0, payload = payload })
    assert(fix.API.getSession() == nil,
        "a chair payload restored off the seat must be refused by the context gate")
    assert(fix.logContains("context invalid"), "backstop must log the refusal")
end

-- ── Reload-UI restore: deferred while the player is not aboard a ship ────────
do
    local fix = dofile("tests/support/runtime_fixture.lua").load()
    State = X4GunneryState
    fix.gcMenu.onShowMenu()
    local seed = fix.API.getSession()
    local payload = State.encode(State.saveState({
        shipID = seed.shipID, shipName = seed.shipName, phase = "console",
        groups = {}, checkedGroupKeys = {}, directSnapshots = {},
    }))
    fix.C.GetPlayerOccupiedShipID = function() return 0 end
    fix.C.GetContextByClass = function() return 0 end   -- playerShip() -> 0
    fix.API.onRestoreEnvelope({ generation = 1, target = 0, payload = payload })
    assert(fix.logContains("not aboard a ship"), "restore must defer when the player is not aboard")
end

print("onboard ingress + exit + restore tests passed")
