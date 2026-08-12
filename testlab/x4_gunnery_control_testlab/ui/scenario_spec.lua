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
--
-- Issue #1 experiment: compare the same ticked upper turret group against a
-- candidate MASKED by a named, player-owned capital ship, a clear-sky control,
-- and an OUT OF RANGE control. Mark each target in Test Lab and compare
-- [X4GC TEST SOLUTION] against [X4GC TEST HIT].

-- Published as a global because X4 loads ui.xml <file> entries for their side
-- effects and discards their return value; the `return` at the end is what the
-- offline tests read.
X4GunneryTestLabScenarioSpec = {
    id      = "issue-1-on-solution-blocker-r3",
    enabled = false,
    setup   = {
        shipMacro       = "ship_bor_l_destroyer_01_a_macro",
        shipLabel       = "Ray",
        turretGroup     = "group_front_up_left",
        turretLabel     = "Front Upper Left",
        expectedTurrets = 2,
    },
    groups  = {
        -- This player-owned XL ship is deliberately centred between the Ray
        -- and A. It is a physical occluder, not a candidate: the hostile target
        -- browser excludes player-owned ships. Do not designate it.
        { label = "MASKING BLOCKER - DO NOT TARGET", macro = "ship_arg_xl_carrier_01_a_macro",
          faction = "player", count = 1, distance = 2000, x = 0, y = 0,
          spread = 0, behaviour = "wait", hostile = false },
        -- A is directly behind the carrier's centre. The selected Ray turrets
        -- sit only about 84m off-centre, so their rays converge through the
        -- carrier rather than relying on uncertain Ray self-masking geometry.
        { label = "A BLOCKED BY CARRIER - HOLD 25s", macro = "ship_xen_m_fighter_01_a_macro",
          faction = "xenon", count = 1, distance = 4000, x = 0, y = 0,
          spread = 0, behaviour = "wait", hostile = true },
        -- Same range but well above the blocker: the clear line-of-fire control.
        { label = "B CLEAR - HOLD 25s", macro = "ship_xen_m_fighter_01_a_macro",
          faction = "xenon", count = 1, distance = 4000, x = 0, y = 1200,
          spread = 0, behaviour = "wait", hostile = true },
        -- Inside the console's target-browser radius but beyond ordinary
        -- capital-turret range. It verifies the range half of the predicate.
        { label = "C OUT OF RANGE - HOLD 25s", macro = "ship_xen_m_fighter_01_a_macro",
          faction = "xenon", count = 1, distance = 15000, x = 0, y = 1200,
          spread = 0, behaviour = "wait", hostile = true },
    },
}
return X4GunneryTestLabScenarioSpec
