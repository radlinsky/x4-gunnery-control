-- Test Lab scenario spec: the fixture the next live test needs.
--
-- THIS FILE IS AN AGENT-AUTHORED INPUT. The directing agent edits it between
-- tests; the owner then clicks Reload UI once in Test Lab and the fixture
-- spawns. Keep it plain: literal fields only, no logic, no requires.
--
-- Reload rule: docs/RELOADING.md puts all of testlab/ in the "restart" row, so
-- restart unless the owner relaxes that rule. This is a `ui/*.lua` entry in
-- ui.xml, so a spec-body edit arguably needs only install + Reload UI, but that
-- narrower claim is unconfirmed in game; see
-- .agents/skills/spawn-gunnery-scenario/SKILL.md before relying on it.
--
-- Fields
--   id        string   Change this whenever the fixture changes. The MD spawns
--                      a spec only once per id; leaving the id alone means a
--                      Reload UI during an unrelated test spawns nothing twice.
--   enabled   boolean  false leaves the spec in place but inert.
--   location  table    Optional absolute sector anchor. When present, Create
--                      can run from any safe gunnery console and every group is
--                      placed at anchor + its x/y/distance offsets.
--     sectorMacro string Exact sector macro name.
--     x/y/z       number Anchor position in sector coordinates, metres.
--   setup     table    Required for Create test scenario. Preflights the exact
--                      ship/loadout and selects the exact turret group.
--     remote          boolean The exact ship is spawned by the fixture; defer
--                             setup until the owner teleports to it.
--     shipMacro       string  Required player ship macro.
--     shipLabel       string  Exact visible required ship name (trimmed).
--     turretGroup     string  Raw group id, not the display label.
--     turretLabel     string  Human-readable group label.
--     expectedTurrets number  Exact operational-member count.
--     selectAll       boolean Select every mutable turret group and verify the
--                             aggregate member count instead of one raw group.
--   groups    list     One entry per batch of identical ships.
--     label     string   Spawned name prefix and log label.
--     macro     string   Ship macro name, without the "macro." prefix.
--     faction   string   Faction id, e.g. "player", "xenon", "argon".
--     count     integer  How many to create (1-12).
--     distance  number   Metres forward of the player ship (negative = astern).
--     spread    number   Optional. Metres of extra scatter beyond `distance`;
--                        omit or 0 puts them all at the same range.
--     x         number   Optional. Metres right of the player ship (positive =
--                        right, negative = left). Default 0.
--     y         number   Optional. Metres above the player ship (positive = up,
--                        negative = down). Default 0.
--                        Axes: positive x = right, positive y = up,
--                        positive z (distance) = forward.
--     behaviour string   "wait"  = hold position (a patient target)
--                        "attack"= fly at and shoot the player ship
--                        "none"  = no order at all (default faction AI)
--     hostile   boolean  Optional. true adds a kill-relation boost against the
--                        player so turret autoassist will engage it.
--     holdFire boolean   Keep every turret in HOLD FIRE and repeatedly cease
--                        fire; READY requires the live safety census to pass.
--     stripDefenceUnits boolean Remove all carried defence drones before the
--                        hostile relation is applied.
--     repairGuard boolean Restore the ship and struck component after each
--                        player-ship hit without making either indestructible.
--     yaw       number   Optional absolute yaw in degrees. Default 0.
--     role      string   Optional "shooter" role for strict loadout census.
--     loadout   string   Optional supported deterministic Test Lab loadout.
--     expectedMissileTurrets / expectedGuided / expectedDumbfire / expectedAmmo
--                        Exact shooter census required before READY.
--   stations  list     Deterministic equipped stations. Readiness is withheld
--                      until MD reports the required operational census.
--     label           string  Exact station name.
--     recipe          string  Supported recipe; currently "xen_defence".
--     faction         string  Owner faction id.
--     distance/x/y    number  Player-ship-local placement in metres.
--     spread          number  Optional safepos scatter; use 0 for fixtures.
--     hostile         boolean Add a temporary kill-relation boost.
--     expectedModules number  Exact operational module count required.
--     minSurfaces     number  Minimum modules + operational turrets, missile
--                            turrets, shields, and engines required.
--     holdFire       boolean Keep all station weapons in HOLD FIRE and refuse
--                            READY unless the live mode census proves it.
--
-- Issue #65 final obstruction control: one mixed-loadout Odysseus E and a
-- small Xenon P directly behind a named, player-owned capital blocker at the remote
-- Argon Prime range. R2's blocked Xenon K was too large: targetable parts were
-- exposed around the carrier, so every per-turret ray remained externally
-- clear. R3 exposed a transport/default edge case: a zero group distance was
-- read as missing and placed the shooter at the 5 km default, beyond both the
-- target and blocker. R4 uses a nonzero 1 m shooter offset and shifts the
-- other absolute offsets by the same metre, preserving exact relative lanes.
-- R4 then proved the Colossus's outer silhouette was large enough but its
-- physical mesh had openings through which four unguided muzzle rays could
-- see the P. R5 attempted to substitute a broadside Asgard but used the wrong
-- `ship_ter` macro prefix and failed closed. R6 uses the catalog-verified ATF
-- macro for the Asgard's solid central hull.

-- Published as a global because X4 loads ui.xml <file> entries for their side
-- effects and discards their return value; the `return` at the end is what the
-- offline tests read.
X4GunneryTestLabScenarioSpec = {
    id      = "issue-65-remote-odysseus-e-r6",
    enabled = false,
    location = {
        sectorMacro = "Cluster_14_Sector001_macro", -- Argon Prime, X4 9.00.
        x = 500000, y = 0, z = 0,
    },
    setup   = {
        remote          = true,
        shipMacro       = "ship_par_l_destroyer_02_a_macro",
        shipLabel       = "ISSUE65 ODYSSEUS E - 9 GUIDED 7 DUMBFIRE 1",
        turretGroup     = "all_missile_turrets",
        turretLabel     = "All Missile Turrets",
        expectedTurrets = 16,
        selectAll       = true,
    },
    groups = {
        { label = "ISSUE65 ODYSSEUS E - 9 GUIDED 7 DUMBFIRE",
          macro = "ship_par_l_destroyer_02_a_macro", faction = "player",
          count = 1, distance = 1, x = 0, y = 0, spread = 0, yaw = 0,
          behaviour = "wait", role = "shooter",
          loadout = "issue65_odysseus_mixed_missiles",
          stripDefenceUnits = true,
          expectedMissileTurrets = 16, expectedGuided = 9,
          expectedDumbfire = 7, expectedAmmo = 160 },
        { label = "ISSUE65 FULLY BLOCKED RIGHT IN-ARC XENON P - REPAIRED HOLD FIRE",
          macro = "ship_xen_m_fighter_01_a_macro", faction = "xenon",
          count = 1, distance = 4201, x = 1600, y = 0, spread = 0, yaw = 180,
          behaviour = "wait", hostile = true, holdFire = true,
          stripDefenceUnits = true, repairGuard = true },
        { label = "ISSUE65 RIGHT-LANE SOLID BLOCKER - PLAYER ASGARD HOLD FIRE",
          macro = "ship_atf_xl_battleship_01_a_macro", faction = "player",
          count = 1, distance = 2101, x = 800, y = 0, spread = 0, yaw = 90,
          behaviour = "wait", holdFire = true, stripDefenceUnits = true },
    },
    stations = {},
}
return X4GunneryTestLabScenarioSpec
