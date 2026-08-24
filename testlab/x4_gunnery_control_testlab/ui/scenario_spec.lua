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
--     expectedMacros  list    Optional exact sorted member-macro multiset.
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
--     geometryRole string Optional "clear_arc" or "below_arc" preflight role.
--     expectedWeapons / expectedTurrets / expectedBeam / expectedPlasma
--                        Exact ordinary-emitter census required before READY.
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
--     geometryRole   string  Optional "aim_split" role. Test Lab keeps only a
--                            station where root and hittable-aim arc results
--                            differ for an exact #67 turret.
--     searchAttempts/searchStepY
--                        Bounded deterministic vertical position search.
--
-- Issue #67 combines the origin-vs-hittable-aim arc question with the
-- zero-barrel conventional-ray question. The station height is searched
-- automatically and READY fails closed unless a real classification split is
-- found; the owner never retries guessed coordinates.

-- Published as a global because X4 loads ui.xml <file> entries for their side
-- effects and discards their return value; the `return` at the end is what the
-- offline tests read.
X4GunneryTestLabScenarioSpec = {
    id      = "issue-67-arc-barrel-diagnostic-r2",
    enabled = false,
    location = {
        sectorMacro = "Cluster_29_Sector001_macro", -- Hatikvah's Choice I (Argon-friendly), one gate from Xenon Tharka's Cascade XV. X4 9.00.
        x = 500000, y = 0, z = 0,
    },
    setup   = {
        remote          = true,
        shipMacro       = "ship_arg_xl_carrier_02_a_macro",
        shipLabel       = "ISSUE ARC-BARREL COLOSSUS E 1",
        turretGroup     = "group_front_left_up",
        turretLabel     = "Front Upper Left",
        selectAll       = true,
        expectedTurrets = 4,
        expectedMacros  = {
            "turret_arg_m_beam_02_mk1_macro",
            "turret_arg_m_beam_02_mk1_macro",
            "turret_arg_m_plasma_02_mk1_macro",
            "turret_arg_m_plasma_02_mk1_macro",
        },
    },
    groups = {
        { label = "ISSUE ARC-BARREL COLOSSUS E",
          macro = "ship_arg_xl_carrier_02_a_macro", faction = "player",
          count = 1, distance = 1, x = 0, y = 0, spread = 0, yaw = 0,
          behaviour = "wait", role = "shooter",
          loadout = "issue67_colossus_arc_barrel",
          stripDefenceUnits = true,
          -- Live-proven (issue-67 run, X4 9.00): `.weapons.operational.count`
          -- reports 4 here, matching `.turrets` — turret-mounted weapons are
          -- counted in both. Colossus E arms group_front_left_up (beam) and
          -- group_front_right_up (plasma), 2 turrets each. 4 turrets => weapons=4.
          expectedWeapons = 4, expectedTurrets = 4,
          expectedBeam = 2, expectedPlasma = 2,
          expectedMissileTurrets = 0, expectedGuided = 0,
          expectedDumbfire = 0, expectedAmmo = 0 },
        { label = "A CLEAR IN-ARC BARREL CONTROL P",
          macro = "ship_xen_m_fighter_01_a_macro", faction = "xenon",
          count = 1, distance = 2201, x = -1200, y = 400, spread = 0, yaw = 180,
          behaviour = "wait", hostile = true, holdFire = true,
          stripDefenceUnits = true, repairGuard = true,
          geometryRole = "clear_arc" },
        { label = "C TRUE CANNOT BEAR CONTROL P",
          macro = "ship_xen_m_fighter_01_a_macro", faction = "xenon",
          count = 1, distance = 1801, x = 1600, y = -1200, spread = 0, yaw = 180,
          behaviour = "wait", hostile = true, holdFire = true,
          stripDefenceUnits = true, repairGuard = true,
          geometryRole = "below_arc" },
    },
}
return X4GunneryTestLabScenarioSpec
