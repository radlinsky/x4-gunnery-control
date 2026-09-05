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
-- Issue #110 Task 1: establish the mouse world-click target contract. The
-- fixture supplies three simultaneously visible, uniquely named click targets
-- ahead of the Ray so every Task 1 left-click question has an unambiguous
-- subject: two separated hostile capitals (LEFT is the "current" target, RIGHT
-- is the "different hostile"), and one player-owned capital that must never be
-- an eligible Direct target. Capitals are used deliberately - their turrets
-- give X4 its own clickable surface markers for the surface-element click.
-- Placement is fixed and lateral so the owner can tell the three apart on
-- screen without flying.
--
-- A fourth hostile sits astern as a setup-only capture sink. Test Lab has a
-- separate one-shot ownership-change experiment whose armed flag can survive
-- scenario replacement (tracked by issue #32). Before the real mouse-click
-- sequence, Direct-engage this sink once and leave it engaged for 11 seconds.
-- If that old one-shot is armed, it is consumed on the disposable sink instead
-- of corrupting LEFT or RIGHT. Do not use the sink again during the contract
-- run. Keep this copy disabled.

X4GunneryTestLabScenarioSpec = {
    id      = "issue-110-mouse-target-contract-r2",
    enabled = false,

    setup = {
        shipMacro       = "ship_bor_l_destroyer_01_a_macro",
        shipLabel       = "Ray",
        turretGroup     = "group_front_up_left",
        turretLabel     = "Front Upper Left",
        expectedTurrets = 2,
    },

    groups = {
        {
            label     = "ISSUE110 HOSTILE LEFT",
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
            label     = "ISSUE110 HOSTILE RIGHT",
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
            label     = "ISSUE110 FRIENDLY CENTRE - DO NOT TARGET",
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

        -- Setup-only stale-capture sink. It is deliberately astern so it does
        -- not overlap the three world-click subjects ahead of the player.
        {
            label     = "ISSUE110 CAPTURE SINK - SETUP ONLY",
            macro     = "ship_ter_l_destroyer_01_a_macro",
            faction   = "xenon",
            count     = 1,
            distance  = -4500,
            x         = 0,
            y         = 0,
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
