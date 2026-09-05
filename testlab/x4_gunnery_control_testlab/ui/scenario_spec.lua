-- Test Lab scenario spec: the fixture the next live test needs.
--
-- THIS FILE IS AGENT-AUTHORED INPUT. Keep it plain: literal fields only, no
-- logic and no requires. Ordinary live fixtures should change this file only.
-- Keep the repository copy disabled; scripts/launch-x4-test-lab-dev.bat enables
-- the installed copy when launching the development Test Lab.
--
-- Fields
--   id        string   Change when fixture meaning changes.
--   enabled   boolean  false leaves the repository fixture inert.
--   location  table    Optional absolute remote-sector anchor.
--     sectorMacro string Exact sector macro name.
--     x/y/z       number Anchor position in sector coordinates, metres.
--   setup     table    Exact player ship/turret selection for Create.
--     remote          boolean Spawn the setup ship remotely, then arm it only
--                             after the owner teleports aboard.
--     shipMacro       string  Required player ship macro.
--     shipLabel       string  Exact visible ship name (trimmed).
--     turretGroup     string  Named-group selector: raw turret group id.
--                             Required for selectAll; when selectAll is false
--                             it is mutually exclusive with singleTurretMacro.
--     singleTurretMacro string Optional exact equipment macro of a production
--                             kind="single" turret entry. Selects that one
--                             turret; requires expectedTurrets = 1.
--     turretLabel     string  Human-readable group label.
--     expectedTurrets number  Exact operational-member count.
--     expectedMemberMacros list Optional exact sorted member-macro multiset.
--     selectAll       boolean Optional; select every mutable turret group and
--                             verify the aggregate member count.
--   groups    list     One entry per batch of identical ships.
--     label     string   Spawned name prefix and log label.
--     macro     string   Ship macro name, without the "macro." prefix.
--     faction   string   Faction id, e.g. "player", "xenon", "argon".
--     count     integer  1-12.
--     distance  number   Forward offset in metres; negative is astern.
--     spread    number   Optional local safepos scatter. Use 0 for exact work.
--     x/y       number   Optional right/up offsets in metres.
--     behaviour string   "wait", "attack", or "none".
--     hostile   boolean  Optional temporary kill-relation boost vs player.
--     holdFire  boolean  Repeatedly force all fixture weapons to HOLD FIRE;
--                        READY requires the live safety census to pass.
--     stripDefenceUnits boolean Remove carried defence drones before hostility.
--     repairGuard boolean Restore the ship and struck component after hits from
--                        the player shooter, without making them invulnerable.
--     yaw/pitch/roll number Optional spawn orientation in degrees.
--     preserveOrientation boolean Preserve authored orientation for Wait orders.
--     role      string   Optional "shooter" role. A shooter must have a named
--                        deterministic loadout and is kept dormant until armed.
--     loadout   string   Optional exact <loadout id> from libraries/loadouts.xml.
--                        Any group may use one; there is no Lua/MD whitelist.
--     expectedWeapons / expectedTurrets / expectedMissileTurrets
--                        Required non-negative exact operational totals whenever
--                        loadout is set. READY fails if any loaded ship differs.
--
-- Issue #75: live-regress the generated prospective-muzzle path for the exact
-- Paranid L Beam accepted in #74. This keeps only the two #69 Beam cases:
-- FAR is the known self-mask discriminator, and NEAR has the external blocker.
-- The old qualifier placed the FAR surface at 0.70 Beam range astern, NEAR at
-- 0.40 range right/astern, and the blocker halfway to NEAR. Beam range is about
-- 14 km, so these fixed root positions preserve that shape without restoring
-- the deleted issue-specific qualifier machinery. Keep this copy disabled.

X4GunneryTestLabScenarioSpec = {
    id      = "issue-75-par-l-beam-far-regression-r1",
    enabled = false,

    location = {
        sectorMacro = "Cluster_29_Sector001_macro",
        x = 500000,
        y = 0,
        z = 0,
    },

    setup = {
        remote          = true,
        shipMacro       = "ship_par_l_destroyer_01_a_macro",
        shipLabel       = "ISSUE75 PAR L BEAM SHOOTER 1",
        turretGroup     = "group_rear_down_mid",
        turretLabel     = "Rear Lower Mid Beam",
        expectedTurrets = 1,
        expectedMemberMacros = {
            "turret_par_l_beam_01_mk1_macro",
        },
        selectAll = false,
    },

    groups = {
        {
            label     = "ISSUE75 PAR L BEAM SHOOTER",
            macro     = "ship_par_l_destroyer_01_a_macro",
            faction   = "player",
            count     = 1,
            distance  = 0,
            x         = 0,
            y         = 0,
            spread    = 0,
            behaviour = "wait",

            role      = "shooter",
            loadout   = "x4gc_testlab_par_l_destroyer_01_beam_plasma",
            expectedWeapons        = 2,
            expectedTurrets        = 2,
            expectedMissileTurrets = 0,
        },

        {
            label     = "ISSUE75 FAR CLEAR",
            macro     = "ship_arg_l_destroyer_02_a_macro",
            faction   = "xenon",
            count     = 1,
            distance  = -9800,
            x         = 0,
            y         = 0,
            spread    = 0,
            behaviour = "wait",
            hostile   = true,
            holdFire  = true,
            stripDefenceUnits = true,
            repairGuard       = true,
            yaw = 90,
            pitch = 0,
            roll = 0,
            preserveOrientation = true,

            loadout   = "x4gc_testlab_arg_l_destroyer_02_beam",
            expectedWeapons        = 1,
            expectedTurrets        = 1,
            expectedMissileTurrets = 0,
        },

        {
            label     = "ISSUE75 NEAR BLOCKED",
            macro     = "ship_arg_l_destroyer_02_a_macro",
            faction   = "xenon",
            count     = 1,
            distance  = -5600,
            x         = 5600,
            y         = 0,
            spread    = 0,
            behaviour = "wait",
            hostile   = true,
            holdFire  = true,
            stripDefenceUnits = true,
            repairGuard       = true,
            yaw = 90,
            pitch = 0,
            roll = 0,
            preserveOrientation = true,

            loadout   = "x4gc_testlab_arg_l_destroyer_02_beam",
            expectedWeapons        = 1,
            expectedTurrets        = 1,
            expectedMissileTurrets = 0,
        },

        {
            label     = "ISSUE75 NEAR LOS BLOCKER",
            macro     = "ship_xen_l_terraformer_01_a_macro",
            faction   = "player",
            count     = 1,
            distance  = -2800,
            x         = 2800,
            y         = 0,
            spread    = 0,
            behaviour = "wait",
            holdFire  = true,
            stripDefenceUnits = true,
            repairGuard       = true,
            yaw = 90,
            pitch = 0,
            roll = 0,
            preserveOrientation = true,
        },
    },
}

return X4GunneryTestLabScenarioSpec
