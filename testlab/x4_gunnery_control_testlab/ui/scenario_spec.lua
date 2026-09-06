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
-- Issue #99 r2: live-regress the generated prospective-muzzle path for the
-- exact Paranid M Laser accepted in #98.
--
-- r1 was a bad fixture: it reused a #83 ship-root firing pose and assumed the
-- Behemoth's child Beam-turret surface would also be reachable there. Live X4
-- disproved that assumption: the exact surface itself stayed 0/1 and never
-- fired.
--
-- The r2 intended-pass target instead reuses the exact Behemoth transform from
-- Issue #67 A100. That exact ARG L Beam surface was live-proven 1/1 ENGAGEABLE
-- and received correlated FIRED/HIT evidence. Its root is translated so the
-- same P*-relative transform is measured from the live/source-proven M-Laser
-- mount origin on the Demeter shooter. The blocked control uses the already
-- proven #75 external-blocker shape, scaled to 40% so it stays inside the
-- M-Laser's 3.5 km range. Keep this repository copy disabled.

X4GunneryTestLabScenarioSpec = {
    id      = "issue-99-par-m-laser-far-regression-r2",
    enabled = false,

    location = {
        sectorMacro = "Cluster_29_Sector001_macro",
        x = 500000,
        y = 0,
        z = 0,
    },

    setup = {
        remote            = true,
        shipMacro         = "ship_par_m_trans_container_01_a_macro",
        shipLabel         = "ISSUE99 PAR M LASER SHOOTER 1",
        singleTurretMacro = "turret_par_m_laser_01_mk1_macro",
        turretLabel       = "Integrated PAR M Laser",
        expectedTurrets   = 1,
        expectedMemberMacros = {
            "turret_par_m_laser_01_mk1_macro",
        },
        selectAll = false,
    },

    groups = {
        {
            label     = "ISSUE99 PAR M LASER SHOOTER",
            macro     = "ship_par_m_trans_container_01_a_macro",
            faction   = "player",
            count     = 1,
            distance  = 1,
            x         = 0,
            y         = 0,
            spread    = 0,
            behaviour = "wait",

            role      = "shooter",
            loadout   = "timelines_scenario_assassination_target_trader",
            expectedWeapons        = 1,
            expectedTurrets        = 1,
            expectedMissileTurrets = 0,
        },

        {
            label     = "ISSUE99 FAR CLEAR SURFACE",
            macro     = "ship_arg_l_destroyer_02_a_macro",
            faction   = "xenon",
            count     = 1,
            -- #67 A100 final root was P* + (-223.612, +1788.313, -163.698).
            -- M-Laser P* is source/live-proven at approximately
            -- (0, +14.3573, -44.2423) from this zero-oriented shooter root.
            distance  = -206.940,
            x         = -223.612,
            y         = 1802.670,
            spread    = 0,
            behaviour = "wait",
            hostile   = true,
            holdFire  = true,
            stripDefenceUnits = true,
            repairGuard       = true,
            yaw   = 214.0265,
            pitch = 68.9246,
            roll  = -166.8782,
            preserveOrientation = true,

            loadout   = "x4gc_testlab_arg_l_destroyer_02_beam",
            expectedWeapons        = 1,
            expectedTurrets        = 1,
            expectedMissileTurrets = 0,
        },

        {
            label     = "ISSUE99 BLOCKED SURFACE",
            macro     = "ship_arg_l_destroyer_02_a_macro",
            faction   = "xenon",
            count     = 1,
            -- #75 NEAR geometry scaled from (x=5600,z=-5600) to 40%.
            distance  = -2240,
            x         = 2240,
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
            label     = "ISSUE99 LOS BLOCKER",
            macro     = "ship_xen_l_terraformer_01_a_macro",
            faction   = "player",
            count     = 1,
            -- Halfway along the blocked-control root ray, matching #75.
            distance  = -1120,
            x         = 1120,
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
