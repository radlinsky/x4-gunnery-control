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
-- Issue #99 r3: live-regress the generated prospective-muzzle path for the
-- exact Paranid M Laser accepted in #98.
--
-- r1 was a bad fixture: it reused a #83 ship-root firing pose and assumed the
-- Behemoth's child Beam-turret surface would also be reachable there. Live X4
-- disproved that assumption: the exact surface itself stayed 0/1 and never
-- fired.
--
-- r3 starts from Issue #67 A100's exact Behemoth/ARG-L-Beam surface geometry,
-- which was live-proven 1/1 ENGAGEABLE with exact FIRED/HIT evidence. #67's
-- shooter weapon frame is tilted, so the A100 root/orientation are first moved
-- into weapon-local coordinates, then rigidly rotated onto exact M-Laser bore
-- directions already live-proven by #83. This preserves the known-good target
-- surface/hull relationship instead of copying #67 world coordinates.
--
-- FAR CLEAR SURFACE is aligned to #83 PITCH HIGH (yaw 0, pitch 1.12376 rad),
-- at about 1.5 km. BLOCKED SURFACE is aligned to #83 RIGHT HIGH
-- (yaw 0.636900, pitch 1.10904 rad), then moved outward to about 3.0 km; a
-- separate player-owned M freighter sits halfway down that exact surface-aim
-- ray. Keep this repository copy disabled.

X4GunneryTestLabScenarioSpec = {
    id      = "issue-99-par-m-laser-far-regression-r3",
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
            -- Rigid transplant of #67 A100 into the identity M-Laser mount
            -- frame, rotated so this exact ARG L Beam surface's hittable aim
            -- point lies on #83 PITCH HIGH. Relative to the live/source-proven
            -- M-Laser origin, surface aim ~= (0, 1349.715, 647.060) m.
            distance  = 724.211593,
            x         = -7.209009,
            y         = 1653.206073,
            spread    = 0,
            behaviour = "wait",
            hostile   = true,
            holdFire  = true,
            stripDefenceUnits = true,
            repairGuard       = true,
            yaw   = -23.106996,
            pitch = 75.831285,
            roll  = -45.918598,
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
            -- Same proven target-surface construction, rigidly aligned to the
            -- #83 RIGHT HIGH bore and shifted 1.5 km farther along that ray.
            -- Surface aim is about 2.997 km from the M-Laser origin, within the
            -- exact weapon's 3.5 km live range.
            distance  = 1126.815327,
            x         = 871.653208,
            y         = 2985.006447,
            spread    = 0,
            behaviour = "wait",
            hostile   = true,
            holdFire  = true,
            stripDefenceUnits = true,
            repairGuard       = true,
            yaw   = 52.055513,
            pitch = 76.249477,
            roll  = 30.272988,
            preserveOrientation = true,

            loadout   = "x4gc_testlab_arg_l_destroyer_02_beam",
            expectedWeapons        = 1,
            expectedTurrets        = 1,
            expectedMissileTurrets = 0,
        },

        {
            label     = "ISSUE99 LOS BLOCKER",
            macro     = "ship_par_m_trans_container_01_a_macro",
            faction   = "player",
            count     = 1,
            -- Centered halfway along BLOCKED SURFACE's exact hittable-aim ray.
            distance  = 493.445716,
            x         = 397.007680,
            y         = 1355.833218,
            spread    = 0,
            behaviour = "wait",
            holdFire  = true,
            stripDefenceUnits = true,
            repairGuard       = true,
            yaw = 0,
            pitch = 0,
            roll = 0,
            preserveOrientation = true,
        },
    },
}

return X4GunneryTestLabScenarioSpec
