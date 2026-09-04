-- Task 2 (#68): explicit session origin + central validity policy.
--
-- Proves State.newSession records an origin ("chair" default, "onboard"
-- explicit) and that the single sessionContextValid() gate behaves per origin:
--   chair   -> valid only while seated (gunnercontrol) on the same ship;
--   onboard -> valid while physically aboard the same player-owned ship, no
--              seat required.
--
-- The fixture stubs playerShip() through C.GetPlayerOccupiedShipID (0) falling
-- back to C.GetContextByClass(...) == 42, validated as a ship by
-- C.IsComponentClass. So the baseline occupant ship id is 42, and the chair
-- baseline control group is "gunnercontrol".

local fix = dofile("tests/support/runtime_fixture.lua").load()

-- Ownership is part of onboard-session validity but not chair-session validity.
-- Keep it mutable so the same-ship ownership-loss case is exercised directly.
local playerOwned = true
GetComponentData = function(_, key)
    if key == "isplayerowned" then return playerOwned end
    return nil
end

-- ── No session yet: the gate short-circuits to invalid ───────────────────────
assert(fix.API.sessionContextValid() == false,
    "sessionContextValid must be false when there is no session")

-- ── State.newSession origin field (2a) ───────────────────────────────────────
assert(X4GunneryState.newSession(1, "gunnercontrol").origin == "chair",
    "newSession origin must default to chair")
assert(X4GunneryState.newSession(1, "gunnercontrol", "onboard").origin == "onboard",
    "newSession must record an explicit onboard origin")

-- ── Chair session via the normal chair ingress ───────────────────────────────
fix.gcMenu.onShowMenu()
local session = fix.API.getSession()
assert(session and session.origin == "chair",
    "chair ingress (onShowMenu) must default the session origin to chair")
assert(fix.API.sessionContextValid() == true,
    "chair session valid when seated (gunnercontrol) on the same ship (42)")

-- Chair invalid off the gunner seat.
fix.C.GetPlayerCurrentControlGroup = function() return "cockpit" end
assert(fix.API.sessionContextValid() == false,
    "chair session invalid when control group is not gunnercontrol")
fix.C.GetPlayerCurrentControlGroup = function() return "gunnercontrol" end

-- Chair invalid on a different ship.
fix.C.GetPlayerOccupiedShipID = function() return 99 end
assert(fix.API.sessionContextValid() == false,
    "chair session invalid when the player is in a different ship")
fix.C.GetPlayerOccupiedShipID = function() return 0 end

-- ── Same session switched to onboard origin ──────────────────────────────────
session.origin = "onboard"

-- Onboard valid regardless of control group (no seat required).
fix.C.GetPlayerCurrentControlGroup = function() return "cockpit" end
assert(fix.API.sessionContextValid() == true,
    "onboard session valid while aboard, even with a non-gunner control group")
fix.C.GetPlayerCurrentControlGroup = function() return "" end
assert(fix.API.sessionContextValid() == true,
    "onboard session valid while aboard, even with an empty control group")
fix.C.GetPlayerCurrentControlGroup = function() return "gunnercontrol" end

-- Onboard invalid if the exact same occupied ship stops being player-owned.
playerOwned = false
assert(fix.API.sessionContextValid() == false,
    "onboard session invalid when the occupied ship is no longer player-owned")
playerOwned = true

-- Onboard invalid on a different ship.
fix.C.GetPlayerOccupiedShipID = function() return 99 end
assert(fix.API.sessionContextValid() == false,
    "onboard session invalid when the player is in a different ship")
fix.C.GetPlayerOccupiedShipID = function() return 0 end

-- Onboard invalid when the enclosing container is not a ship (e.g. a station):
-- playerShip() resolves to 0 and cannot match the cached ship.
fix.C.IsComponentClass = function() return false end
assert(fix.API.sessionContextValid() == false,
    "onboard session invalid when the enclosing container is not a ship")
fix.C.IsComponentClass = function() return true end

-- Onboard invalid with no container at all (player left the ship).
fix.C.GetContextByClass = function() return 0 end
assert(fix.API.sessionContextValid() == false,
    "onboard session invalid when there is no enclosing container")
fix.C.GetContextByClass = function() return 42 end

-- ── Stale/zero cached ship id can never match a real occupant ────────────────
session.shipID = 0
assert(fix.API.sessionContextValid() == false,
    "session with a zero cached ship id is invalid")

print("session origin + context validity tests passed")
