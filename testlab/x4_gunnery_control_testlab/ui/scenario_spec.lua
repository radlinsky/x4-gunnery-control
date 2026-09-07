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
-- Issue #132: discriminate the only unresolved P6 settled transform question:
-- do the part_gun channel-1/channel-2 companions add no material transform, as
-- the converter-backed additive-Euler/multiplicative-scale model predicts?
--
-- The sparse shooter has exactly one turret_tel_l_laser_01_mk1_macro in the
-- one-slot group_front_up_mid2. Its two P6 component endpoints and active ANI
-- records are source-identical to the scoped Pirate component for every
-- transform input used by this discriminator.
--
-- The intended source model retains authored connection/endpoint transforms,
-- applies the exact channel-0 translations, treats gun channel 1 (0,0,0) as an
-- additive Euler no-op and channel 2 (1,1,1) as multiplicative unit scale, then
-- composes live yaw at part_rotator before live pitch at part_gun.
--
-- The control instead treats channel 2 as additive scale, yielding local scale
-- (2,2,2) at part_gun. It adds one extra copy of the gun-to-endpoint vector:
-- 35.633489 m for con_laser_01 or 35.668340 m for con_laser_02. One absolute
-- runtime barrelposition at a settled attributed shot therefore discriminates
-- the models; the existing FIRED/HIT observer already logs every required
-- value, so this fixture needs no new diagnostics.
--
-- The target is 2 km high-forward (nominal hull yaw 0, pitch +30 degrees),
-- inside the exact bullet's 5 km speed*lifetime range and conservatively clear
-- of the destroyer hull from the front-upper mount. Its known one-turret
-- loadout supplies a fail-closed hold-fire safety census.
-- Keep this repository copy disabled.

X4GunneryTestLabScenarioSpec = {
    id      = "issue-132-p6-tel-l-laser-transform-r1",
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
        shipLabel       = "ISSUE132 P6 SHOOTER 1",
        turretGroup     = "group_front_up_mid2",
        turretLabel     = "Front Upper TEL L Pulse",
        expectedTurrets = 1,
        expectedMemberMacros = {
            "turret_tel_l_laser_01_mk1_macro",
        },
        selectAll = false,
    },

    groups = {
        {
            label     = "ISSUE132 P6 SHOOTER",
            macro     = "ship_par_l_destroyer_01_a_macro",
            faction   = "player",
            count     = 1,
            distance  = 1,
            x         = 0,
            y         = 0,
            spread    = 0,
            behaviour = "wait",

            role      = "shooter",
            loadout   = "x4gc_testlab_par_l_destroyer_01_tel_l_laser",
            expectedWeapons        = 1,
            expectedTurrets        = 1,
            expectedMissileTurrets = 0,
        },

        {
            label     = "ISSUE132 P6 TARGET HIGH FORWARD",
            macro     = "ship_par_m_trans_container_01_a_macro",
            faction   = "xenon",
            count     = 1,
            -- Nominal hull yaw 0, pitch +30 degrees, 2000 m slant range.
            distance  = 1732.050808,
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
