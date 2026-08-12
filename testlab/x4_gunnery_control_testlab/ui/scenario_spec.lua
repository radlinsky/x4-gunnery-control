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
-- .claude/skills/spawn-gunnery-scenario/SKILL.md before relying on it.
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
-- Worked example below: M10, hostiles A and B placed at deliberate opposite
-- bearings so an unchecked turret visibly swings its aim from one to the other.
-- Random `spread` cannot produce that reliably, which is why x/y exist.

-- Published as a global because X4 loads ui.xml <file> entries for their side
-- effects and discards their return value; the `return` at the end is what the
-- offline tests read.
X4GunneryTestLabScenarioSpec = {
    id      = "m10-fallback-abcde",
    enabled = false,
    groups  = {
        -- A: 1.2 km LEFT, 1.2 km UP, 3 km ahead.
        --
        -- Each placement here fixed the one before it:
        --   2.5 km out, 80 deg apart, level -- too wide. The unchecked turrets
        --     sat on the right of the hull with no shot at A, fell back to B,
        --     and the override looked broken when it was behaving as
        --     documented.
        --   3 km out, 44 deg apart, level -- correct bearing, wrong elevation.
        --     Turrets bore on A and then never fired. The console's turrets are
        --     on the ship's upper surface, and a target at hull level sits in
        --     their arc but behind their own hull, so they track it and hold
        --     fire. Nothing falls back, because X4's preferred-target fallback
        --     asks "can I aim at this", not "can I hit it" -- see the overclaim
        --     at ui/gunnery_control.lua:344-348, which only ever covered the
        --     out-of-arc case.
        --   Current: same range and bearing, raised 1.2 km. Clear sky above the
        --     hull, so "did not fire" can only mean the override, never the
        --     geometry. Range is deliberately unchanged; it was never the
        --     variable under test.
        --
        -- M fighters, not S: with every turret preferring the same target an
        -- S fighter died before the swing could be observed. What the test
        -- needs is observation time, and hull is the only lever the spawner
        -- has. Three per bearing keeps the bearing occupied as they die.
        { label = "A left", macro = "ship_xen_m_fighter_01_a_macro",
          faction = "xenon", count = 3, distance = 3000, x = -1200, y = 1200,
          spread = 400, behaviour = "wait", hostile = true },
        -- B: mirrored to the RIGHT at the same height, so an unchecked turret
        -- aiming at B is unmistakably not aiming at A.
        { label = "B right", macro = "ship_xen_m_fighter_01_a_macro",
          faction = "xenon", count = 3, distance = 3000, x = 1200, y = 1200,
          spread = 400, behaviour = "wait", hostile = true },
        -- C: 1.2 km LOW and RIGHT. Added 2026-08-09 because A and B alone
        -- cannot test the autoassist fallback at all.
        --
        -- With both groups high, the two lower-right turrets (515155, 515157)
        -- read los=0 against every hostile in the sector -- the cost sweep's
        -- 78 pairs came back with 66 solutions, and the missing 12 are exactly
        -- those 2 turrets times the 6 hostiles. A fallback test whose canary
        -- turrets cannot reach any fallback target returns "no fallback"
        -- whether the feature works or not.
        --
        -- C sits where those turrets can actually shoot. Target A (high left)
        -- and the pair has no solution on it but a clear one on C, so
        -- fallback_hits separates a working fallback from a broken one.
        { label = "C low right", macro = "ship_xen_m_fighter_01_a_macro",
          faction = "xenon", count = 3, distance = 3000, x = 1200, y = -1200,
          spread = 400, behaviour = "wait", hostile = true },
        -- D: OUT OF RANGE preferred target for the fallback test. MASKED was
        -- tested live on 2026-08-09 and the engine holds fire indefinitely
        -- rather than falling back, and OUT OF ARC could not be staged because
        -- the NPC pilot will not hold an attitude. 15 km is inside the
        -- console's 40 km maxradarrange so the group is still selectable in
        -- the target list, but far outside any capital turret's reach, so
        -- "did not fall back" cannot be blamed on geometry. Raised 1.2 km for
        -- the same clear-sky reason as A and B.
        { label = "D far", macro = "ship_xen_m_fighter_01_a_macro",
          faction = "xenon", count = 2, distance = 15000, x = 0, y = 1200,
          spread = 500, behaviour = "wait", hostile = true },
        -- E: OUT OF ARC instrument. CONFIRMED LIVE 2026-08-10: a Front group
        -- directed at E, which it cannot bear on, rolled to another hostile
        -- instead of tracking in silence. That closes the last fire-control
        -- condition the fallback claim rested on inference for; OUT OF RANGE was
        -- confirmed on 2026-08-09 and MASKED is accepted as unfixable.
        --
        -- Pick a Front group when using this instrument. A Rear group has E in
        -- arc and the test degenerates into an ordinary engagement.
        --
        -- Negative distance places the group 3 km astern; the spawner passes
        -- distance straight to safepos as z, and positive z is forward. That
        -- negative value was rejected outright by the spec validator until
        -- 2026-08-10, which is why this group had never once spawned. Raised
        -- 1.2 km so the target is astern with clear sky above the hull: that
        -- elevation is what separates OUT OF ARC from MASKED, since a target
        -- astern at hull level would be both at once and the observation could
        -- not distinguish them. Posing the ship instead of the target was tried
        -- first and failed -- the NPC pilot will not hold an attitude on command.
        { label = "E astern", macro = "ship_xen_m_fighter_01_a_macro",
          faction = "xenon", count = 3, distance = -3000, x = 0, y = 1200,
          spread = 400, behaviour = "wait", hostile = true },
    },
}
return X4GunneryTestLabScenarioSpec
