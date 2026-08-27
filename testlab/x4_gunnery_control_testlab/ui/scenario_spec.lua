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
--     expectedMemberMacros list Optional exact sorted member-macro multiset (expectedMacros is accepted for legacy specs).
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
--     ox / oy / oz number Optional. Finite P*-relative target-root offsets.
--                        All three are required when geometryRole is
--                        "surface_mask"; ordinary groups transport numeric 0 defaults.
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
--     yaw       number   Optional absolute spawn-orientation yaw, degrees.
--     pitch     number   Optional absolute spawn-orientation pitch, degrees.
--     roll      number   Optional absolute spawn-orientation roll, degrees.
--                        Spawn orientation is how the spawned ship faces when
--                        it is created; it is not a weapon aim angle or a
--                        turret traverse/elevation limit. Default 0.
--     preserveOrientation boolean Optional. For Wait targets, set the shipped
--                        order's internal skipalignment parameter so it does
--                        not replace authored pitch/roll with ecliptic zeroes.
--                        Default false.
--     role      string   Optional "shooter" role for strict loadout census.
--     loadout   string   Optional supported deterministic Test Lab loadout.
--     geometryRole string Optional "clear_arc", "below_arc", or
--                         "surface_mask" post-teleport qualifier role.
--                         "surface_mask" is the sky-survey pending
--                         exact-ship-surface transport role used to qualify one
--                         authored arc-split component for manual designation.
--     geometryWeaponMacro string Exact qualifier weapon macro for the shooter.
--     expectedGeometryWeapons number Exact operational members of that macro.
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
--     geometryRole   string  Optional "aim_split" transport role.
--     searchAttempts/searchStepY
--                        Bounded deterministic vertical position search.
--
-- Issue #69 r1 reproduces the aim-point multiplicity symptom on an ENGINE:
-- one Argon L destroyer placed so exactly ONE of its all-round engines
-- (con_engine_01) straddles the Paranid plasma +80° arc limit — useaimtarget
-- pitch ≈83° (old predicate: non-engageable) while look_at_bbox pitch ≈55°
-- (new predicate: engageable). The straddle engine is the single marked
-- Direct-control objective. Geometry solved and validated offline; placement
-- values must not be re-derived.

-- Published as a global because X4 loads ui.xml <file> entries for their side
-- effects and discards their return value; the `return` at the end is what the
-- offline tests read.
X4GunneryTestLabScenarioSpec = {
    id      = "issue-69-engine-straddle-r1",
    enabled = false,
    location = {
        sectorMacro = "Cluster_29_Sector001_macro",
        x = 500000, y = 0, z = 0,
    },
    setup   = {
        remote          = true,
        shipMacro       = "ship_par_l_destroyer_01_a_macro",
        shipLabel       = "ISSUE SKY-SURVEY PARANID DESTROYER 1",
        turretGroup     = "group_front_up_mid2",
        turretLabel     = "Front Upper Mid Plasma",
        selectAll       = false,
        expectedTurrets = 1,
        expectedMemberMacros = { "turret_par_l_plasma_01_mk1_macro" },
    },
    groups = {
        { label = "ISSUE SKY-SURVEY PARANID DESTROYER",
          macro = "ship_par_l_destroyer_01_a_macro", faction = "player",
          count = 1, distance = 1, x = 0, y = 0, spread = 0, behaviour = "wait",
          role = "shooter", loadout = "issue67_paranid_sky_survey",
          geometryWeaponMacro = "turret_par_l_plasma_01_mk1_macro",
          expectedGeometryWeapons = 1,
          expectedWeapons = 1, expectedTurrets = 1, expectedPlasma = 1, expectedBeam = 0,
          expectedMissileTurrets = 0, expectedGuided = 0, expectedDumbfire = 0, expectedAmmo = 0 },
        { label = "ISSUE ENGINE STRADDLE ARGON",
          macro = "ship_arg_l_destroyer_02_a_macro", faction = "xenon",
          count = 1, distance = 260, x = -40, y = 670, spread = 0,
          ox = -40.345, oy = 670.435, oz = -45.015,
          yaw = 213, pitch = 81, roll = 132,
          preserveOrientation = true,
          behaviour = "wait", hostile = true, holdFire = true,
          stripDefenceUnits = true, repairGuard = true, geometryRole = "surface_mask",
          loadout = "issue67_argon_sky_target",
          geometryCase = "engine_straddle" },
    },
    stations = {},
}
return X4GunneryTestLabScenarioSpec
