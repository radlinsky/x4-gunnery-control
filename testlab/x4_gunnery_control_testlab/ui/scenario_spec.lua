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
--     turretGroup     string  Raw turret group id.
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
-- The disabled fixture below is retained only as the current work-in-progress
-- input. Its A/B coordinates are known-bad for the channel discriminator; do
-- not treat them as a reusable geometry fixture.

X4GunneryTestLabScenarioSpec = {
    id      = "issue-72-a3-channel0-discriminator-r1",
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
        shipLabel       = "ISSUE72 PAR L BEAM SHOOTER 1",
        turretGroup     = "group_rear_down_mid",
        turretLabel     = "Rear Lower Mid Beam",
        selectAll       = false,
        expectedTurrets = 1,
        expectedMemberMacros = {
            "turret_par_l_beam_01_mk1_macro",
        },
    },

    groups = {
        {
            label     = "ISSUE72 PAR L BEAM SHOOTER",
            macro     = "ship_par_l_destroyer_01_a_macro",
            faction   = "player",
            count     = 1,
            distance  = 1,
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
            label     = "ISSUE72 CHANNEL0 TARGET A",
            macro     = "ship_arg_l_destroyer_02_a_macro",
            faction   = "xenon",
            count     = 1,
            distance  = 7000,
            x         = 0,
            y         = 0,
            spread    = 0,
            behaviour = "wait",
            hostile   = true,
            holdFire  = true,
            stripDefenceUnits = true,
            repairGuard       = true,
        },

        {
            label     = "ISSUE72 CHANNEL0 TARGET B",
            macro     = "ship_arg_l_destroyer_02_a_macro",
            faction   = "xenon",
            count     = 1,
            distance  = 7000,
            x         = 2000,
            y         = 1500,
            spread    = 0,
            behaviour = "wait",
            hostile   = true,
            holdFire  = true,
            stripDefenceUnits = true,
            repairGuard       = true,
        },
    },
}

return X4GunneryTestLabScenarioSpec
