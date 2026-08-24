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
-- conventional-ray question. The station B geometry cannot be measured
-- out of system, so it is a two-phase probe: the OOS create preserves one
-- station and reports geometry PENDING, then a single post-teleport in-system
-- open moves that same station through a bounded deterministic search. Every
-- position is measured on a later MD update; the timed test still designates
-- station B's root. The owner never retries guessed coordinates.

-- Published as a global because X4 loads ui.xml <file> entries for their side
-- effects and discards their return value; the `return` at the end is what the
-- offline tests read.
X4GunneryTestLabScenarioSpec = {
    id      = "issue-67-arc-barrel-two-phase-r9",
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
          -- Census invariant: turret-mounted weapons are counted in both
          -- `.weapons.operational.count` and `.turrets`, so 4 turrets =>
          -- weapons=4. That invariant is live-tested on Behemoth E only
          -- (X4 9.00, d7e3870). Colossus E arms group_front_left_up (beam) and
          -- group_front_right_up (plasma), 2 turrets each: those slot/group
          -- facts are shipped-source and the _02 beam/plasma compatibility is
          -- inference — the Colossus mount and census are not yet live-verified.
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
    stations = {
        -- B: the LARGE ROOT AIM-POINT target. A Xenon xen_defence station (five
        -- modules) placed forward of the shooter and below it, so its root origin
        -- can drop below the front-upper turrets' generated -10 degree elevation
        -- stop while a hittable upper-module surface stays inside the arc.
        -- Equipment discriminator: apply one deterministic SAFE loadout to one
        -- actual xenon_small_station_01_base module, never to the station root:
        -- two standard medium lasers in group01, four medium shields in groups01-04,
        -- and no large/graviton equipment. The MD records the station census
        -- immediately, after a 1 ms delayed cue, and in system. Only the in-system
        -- census is a qualification gate; the earlier two are observations that
        -- will tell us whether remote equipment is synchronous. Two-phase: OOS the
        -- aim target does not resolve to a real hull surface, so root and
        -- hittable-aim pitch are near-identical and no split can be measured at
        -- spawn. Test Lab PRESERVES exactly one station at this attempt-0 position
        -- (searchAttempts = 1; no OOS repositioning), verifies its census, and
        -- reports geometry PENDING. After the owner teleports to the Colossus,
        -- opening Test Lab once moves this same station through eight bounded,
        -- safely separated in-system positions. r8 disproved its close/low band;
        -- r9 applies a deterministic 180-degree station roll so the construction
        -- plan's negative-Y module offsets sit above the root, and samples the
        -- measured elevation boundary. Each warp is followed by a 1 ms delayed
        -- measurement against the same four turrets.
        -- It records root origin/aim plus every operational module's origin/aim
        -- independently. Qualification accepts either a
        -- root-OUTSIDE/root-aim-INSIDE/in-range turret or a root-OUTSIDE/
        -- module-aim-INSIDE/in-range turret with clear external muzzle LOS; if
        -- neither exists it fails closed. The timed test still designates B's
        -- station root, so these measurements do not pre-judge engine behavior.
        -- The search coordinates are experimental fixture inputs, not verified
        -- X4 behavior or a knowledge-base conclusion.
        -- At Create,
        -- minSurfaces intentionally requires only the five-module shell so a
        -- deferred loadout can reach the in-system discriminator. The exact
        -- turret-and-shield census is enforced only by that in-system check.
        -- searchStepY is retained only as a downward-search marker.
        { label = "B LARGE ROOT AIM-POINT STATION",
          recipe = "xen_defence", faction = "xenon",
          distance = 6000, x = 0, y = -800, spread = 0,
          hostile = true, holdFire = true,
          geometryRole = "aim_split",
          expectedModules = 5, minSurfaces = 5,
          searchAttempts = 1, searchStepY = -400 },
    },
}
return X4GunneryTestLabScenarioSpec
