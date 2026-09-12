-- Test Lab scenario spec: the fixture the next live test needs.
--
-- THIS FILE IS AGENT-AUTHORED INPUT. Keep it plain: literal fields only, no
-- logic and no requires. Ordinary live fixtures should change this file only.
-- Commit and push each PR-specific fixture with the work that used it so the
-- commit preserves the exact live-test setup.
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
-- Issue #151 C4: live-test the five newly supported rank-2 turret macros on
-- two sparse remote shooters. Shooter A is selected automatically by its
-- exact single-turret macro; FIRED records attribute shots to weapon macros.
--
-- Keep this repository copy disabled.

X4GunneryTestLabScenarioSpec = {
    id      = "issue-151-endpoint-count-rank2-gorgon-live-r2",
    enabled = false,

    location = {
        sectorMacro = "Cluster_29_Sector001_macro",
        x = 500000,
        y = 0,
        z = 0,
    },

    setup = {
        remote          = true,
        shipMacro       = "ship_par_m_frigate_01_a_macro",
        shipLabel       = "ISSUE151 C4 SHOOTER A 1",
        singleTurretMacro = "turret_par_m_gatling_01_mk1_macro",
        turretLabel     = "PAR M Gatling Single",
        expectedTurrets = 1,
        expectedMemberMacros = {
            "turret_par_m_gatling_01_mk1_macro",
        },
        selectAll = false,
    },

    groups = {
        {
            label     = "ISSUE151 C4 SHOOTER A",
            macro     = "ship_par_m_frigate_01_a_macro",
            faction   = "player",
            count     = 1,
            distance  = 0,
            x         = -200,
            y         = 0,
            spread    = 0,
            behaviour = "wait",
            yaw       = 0,
            pitch     = 0,
            roll      = 0,
            preserveOrientation = true,

            role      = "shooter",
            loadout   = "x4gc_testlab_par_m_frigate_01_rank2_gatling_c4",
            expectedWeapons        = 3,
            expectedTurrets        = 3,
            expectedMissileTurrets = 0,
        },

        {
            label     = "ISSUE151 C4 SHOOTER B",
            macro     = "ship_par_m_frigate_01_a_macro",
            faction   = "player",
            count     = 1,
            distance  = 0,
            x         = 200,
            y         = 0,
            spread    = 0,
            behaviour = "wait",
            yaw       = 0,
            pitch     = 0,
            roll      = 0,
            preserveOrientation = true,

            role      = "shooter",
            loadout   = "x4gc_testlab_par_m_frigate_01_rank2_shotgun_c4",
            expectedWeapons        = 2,
            expectedTurrets        = 2,
            expectedMissileTurrets = 0,
        },

        {
            label     = "ISSUE151 C4 TARGET",
            macro     = "ship_par_m_trans_container_01_a_macro",
            faction   = "xenon",
            count     = 1,
            distance  = 500,
            x         = 0,
            y         = 1000,
            spread    = 0,
            behaviour = "wait",
            hostile   = true,
            holdFire  = true,
            stripDefenceUnits = true,
            repairGuard       = true,
            yaw   = 0,
            pitch = 0,
            roll  = 0,
            preserveOrientation = true,

            loadout   = "timelines_scenario_assassination_target_trader",
            expectedWeapons        = 1,
            expectedTurrets        = 1,
            expectedMissileTurrets = 0,
        },
    },
}

return X4GunneryTestLabScenarioSpec
