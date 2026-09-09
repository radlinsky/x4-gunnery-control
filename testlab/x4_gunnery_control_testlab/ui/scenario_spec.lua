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
-- Issue #116 Task 3: verify Direct-mode target sync after a world left-click.
-- This deliberately reuses the accepted Issue #110/#118 three-capital layout:
-- two separated hostile click targets and one player-owned ineligible control
-- ahead of the Ray. The geometry already proved suitable for world left-click
-- work, so this fixture changes only the scenario identity/labels needed to
-- attribute the new live run.
--
-- Keep this repository copy disabled.

X4GunneryTestLabScenarioSpec = {
    id      = "issue-116-world-target-sync-r1",
    enabled = false,

    setup = {
        shipMacro       = "ship_bor_l_destroyer_01_a_macro",
        shipLabel       = "Ray",
        turretGroup     = "group_front_up_left",
        turretLabel     = "Front Upper Left",
        expectedTurrets = 2,
        selectAll       = false,
    },

    groups = {
        {
            label     = "ISSUE116 HOSTILE LEFT",
            macro     = "ship_ter_l_destroyer_01_a_macro",
            faction   = "xenon",
            count     = 1,
            distance  = 4500,
            x         = -1200,
            y         = 0,
            spread    = 0,
            behaviour = "wait",
            hostile   = true,
            holdFire  = true,
            stripDefenceUnits = true,
            repairGuard       = true,
        },

        {
            label     = "ISSUE116 HOSTILE RIGHT",
            macro     = "ship_ter_l_destroyer_01_a_macro",
            faction   = "xenon",
            count     = 1,
            distance  = 4500,
            x         = 1200,
            y         = 0,
            spread    = 0,
            behaviour = "wait",
            hostile   = true,
            holdFire  = true,
            stripDefenceUnits = true,
            repairGuard       = true,
        },

        -- Player-owned: the ineligible-click control. Never designate it.
        {
            label     = "ISSUE116 FRIENDLY CENTRE - DO NOT TARGET",
            macro     = "ship_ter_l_destroyer_01_a_macro",
            faction   = "player",
            count     = 1,
            distance  = 4500,
            x         = 0,
            y         = 0,
            spread    = 0,
            behaviour = "wait",
            hostile   = false,
            holdFire  = true,
            stripDefenceUnits = true,
        },
    },
}

return X4GunneryTestLabScenarioSpec
