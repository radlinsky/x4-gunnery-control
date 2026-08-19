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
--   setup     table    Required for Create test scenario. Preflights the exact
--                      ship/loadout and selects the exact turret group.
--     shipMacro       string  Required player ship macro.
--     shipLabel       string  Exact visible required ship name (trimmed).
--     turretGroup     string  Raw group id, not the display label.
--     turretLabel     string  Human-readable group label.
--     expectedTurrets number  Exact operational-member count.
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
--
-- Issue #1 experiment: compare the same ticked upper turret group against a
-- candidate whose LINE OF FIRE is BLOCKED by a named, player-owned capital ship, a clear-sky control,
-- and an OUT OF RANGE control. Mark each target in Test Lab and compare
-- [X4GC TEST SOLUTION] against [X4GC TEST HIT].

-- Published as a global because X4 loads ui.xml <file> entries for their side
-- effects and discards their return value; the `return` at the end is what the
-- offline tests read.
X4GunneryTestLabScenarioSpec = {
    id      = "pr-2-solution-competing-osakas-r7",
    enabled = false,
    setup   = {
        shipMacro       = "ship_bor_l_destroyer_01_a_macro",
        shipLabel       = "Ray",
        turretGroup     = "group_front_up_left",
        turretLabel     = "All Turrets",
        expectedTurrets = 14,
        selectAll       = true,
    },
    groups = {
        -- Two separated, stationary capital targets distinguish shots aimed at
        -- the selected primary from ordinary autonomous fire at a distractor.
        -- Both remain attackable under exact-hit repair and cannot return fire.
        { label = "PR2 PRIMARY LEFT OSAKA - REPAIRED HOLD FIRE",
          macro = "ship_ter_l_destroyer_01_a_macro", faction = "xenon",
          count = 1, distance = 3500, x = -900, y = 0, spread = 0,
          behaviour = "wait", hostile = true, holdFire = true,
          stripDefenceUnits = true, repairGuard = true },
        { label = "PR2 DISTRACTOR RIGHT OSAKA - REPAIRED HOLD FIRE",
          macro = "ship_ter_l_destroyer_01_a_macro", faction = "xenon",
          count = 1, distance = 3500, x = 900, y = 0, spread = 0,
          behaviour = "wait", hostile = true, holdFire = true,
          stripDefenceUnits = true, repairGuard = true },
    },
    stations = {},
}
return X4GunneryTestLabScenarioSpec
