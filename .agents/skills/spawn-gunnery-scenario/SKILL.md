# spawn-gunnery-scenario

Spawns the ship fixture a live test needs, in the Test Lab extension, without a
game restart per scenario.

The flow is: **the agent edits one spec file; the owner clicks Reload UI once.**

## The flow

1. **Agent** edits `testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua` to
   describe the fixture the next checklist test needs. Give it a new `id` and
   set `enabled = true`.
2. **Agent** runs `./scripts/install-dev.sh "<X4 path>"` so the loose files on
   disk are the ones the game will re-read. Without this the reload re-runs the
   copy the game already has and nothing changes.
3. **Owner**, seated at a gunnery console, opens Test Lab and clicks
   **Reload UI**.
4. The ships appear. Test Lab shows `Scenario spec: <id> (enabled)` so the owner
   can confirm which fixture is live before touching anything.

Between tests, repeat with a new `id`. No game restart, no hardcoded presets.

## Reload requirement — verified, and it is NOT a restart

**Editing the CONTENTS of `scenario_spec.lua` needs only install + Reload UI.**

Evidence:

- `scenario_spec.lua` is registered as an ordinary `<file>` entry in
  `testlab/x4_gunnery_control_testlab/ui.xml`, ahead of `testlab.lua`. It is
  therefore a `ui/*.lua` file, which `docs/RELOADING.md` puts in the
  "install, then **Reload UI**" row.
- `ScheduleReloadUI` "re-reads loose files from disk" and was live-tested on
  2026-08-08 **with the `x4_gunnery_control_testlab` extension loaded**, with the
  reload triggered from a Test Lab button. Recorded in
  `.agents/skills/research-x4-modding/references/ui-lua-menu-camera.md`,
  section "ScheduleReloadUI exists in the menus environment and re-reads loose
  files from disk".
- `testlab.lua` reads the spec at load time (its `init()` calls
  `sendScenarioSpec(false)`), and a UI reload re-runs `init()` — the same
  mechanism the gunnery persistence handshake already depends on.

`docs/RELOADING.md` line 21 says testlab/ files need a restart, and the repo
hook (`.agents/hooks/reload-advice.sh`) prints "full restart" for any
`testlab/*` path. Both are deliberately conservative: a typical Test Lab change
touches `md/`, `t/` and `ui.xml` together, and the strictest category wins.

The argument above says a change confined to the body of `scenario_spec.lua`
does not need a restart, but that narrower claim has NOT been confirmed in game.
Until it has, follow the hook: when it says restart, tell the owner restart. If
a spec-only Reload UI is observed to work in a live session, raise it with the
owner and change `docs/RELOADING.md` and the hook together, so the repo's stated
rule and the advice agents act on stay identical. Do not carry a private
exception in this file.

**A full game restart is still required for:**

- Any change to `x4_gunnery_control_testlab_scenario.xml` (the MD).
- Any change to `ui.xml`, `content.xml`, or `t/0001.xml`.
- Adding a brand-new file the game must load.

Restart means: exit X4, then run `scripts/launch-x4-test-lab-dev.bat`, which
installs before it launches.

## The spec table

```lua
X4GunneryTestLabScenarioSpec = {
    id      = "unique-string",  -- change this to make it spawn again
    enabled = true,             -- false leaves the spec in place but inert
    groups  = {
        {
            label     = "hostile A",                      -- logged only
            macro     = "ship_xen_s_fighter_01_a_macro",  -- no "macro." prefix
            faction   = "xenon",                          -- faction id
            count     = 1,                                -- 1-12
            distance  = 5000,                             -- metres from player ship
            spread    = 0,                                -- optional extra scatter, metres
            behaviour = "wait",                           -- "wait" | "attack" | "none"
            hostile   = true,                             -- optional kill-relation boost
        },
    },
}

return X4GunneryTestLabScenarioSpec
```

The global assignment is what the game reads (X4 discards a `<file>`'s return
value); the `return` is what the offline tests read. Keep both.

`behaviour`:

- `"wait"` — holds position. A patient target. Use this for almost everything.
- `"attack"` — flies at the player ship and shoots. Use only when the test needs
  incoming fire.
- `"none"` — no order; default faction AI. Use for the player-owned platform.

Anything else — per-ship loadouts, named ships, formations, spawn sectors — is
deliberately absent. Add a field only when a checklist test cannot be run
without it.

## Worked example — M6, lone disposable hostile

M6 needs one qualifying hostile and, ideally, nothing else eligible in radar
range, so destroying it produces a genuinely candidate-free scan. Note the
player-faction target filter excludes only player-owned objects, not all
friendlies, so the owner may still need an isolated position; this fixture gives
the hostile, not the isolation.

```lua
X4GunneryTestLabScenarioSpec = {
    id      = "m6-lone-hostile",
    enabled = true,
    groups  = {
        {
            label     = "gunnery platform",
            macro     = "ship_arg_l_destroyer_01_a_macro",
            faction   = "player",
            count     = 1,
            distance  = 2000,
            behaviour = "none",
        },
        {
            label     = "disposable hostile",
            macro     = "ship_xen_s_fighter_01_a_macro",
            faction   = "xenon",
            count     = 1,
            distance  = 5000,
            behaviour = "wait",
            hostile   = true,
        },
    },
}

return X4GunneryTestLabScenarioSpec
```

## Worked example — M7A, two hostiles A and B

M7A destroys A while B must stay eligible, so auto-next has somewhere to go.
Two separate one-ship groups, at different ranges so the owner can tell them
apart by distance in the target browser.

```lua
X4GunneryTestLabScenarioSpec = {
    id      = "m7a-two-hostiles",
    enabled = true,
    groups  = {
        {
            label     = "gunnery platform",
            macro     = "ship_arg_l_destroyer_01_a_macro",
            faction   = "player",
            count     = 1,
            distance  = 2000,
            behaviour = "none",
        },
        {
            label     = "hostile A",
            macro     = "ship_xen_s_fighter_01_a_macro",
            faction   = "xenon",
            count     = 1,
            distance  = 5000,
            behaviour = "wait",
            hostile   = true,
        },
        {
            label     = "hostile B",
            macro     = "ship_xen_s_fighter_01_a_macro",
            faction   = "xenon",
            count     = 1,
            distance  = 6000,
            behaviour = "wait",
            hostile   = true,
        },
    },
}

return X4GunneryTestLabScenarioSpec
```

M7B uses the same fixture with a new `id`; only the operator procedure differs.

## Idempotency

Every Reload UI re-runs `testlab.lua`, so the spec is re-sent every time. MD
records the id of the fixture currently on the field in
`ScenarioRoot.$SpawnedSpecId` and refuses a `scenario_begin` carrying the same
id. A Reload UI during an unrelated test therefore spawns nothing.

Three ways to make it spawn again:

- Change `id` in the spec — the normal path between tests.
- Press **Re-run current spec** in Test Lab — sends `force = true`, and works
  even on a disabled spec.
- Press **Despawn test scenario** — clears the recorded id, so the next Reload
  UI re-spawns the same spec.

An accepted spawn always despawns the previous fixture first, so even a forced
re-run replaces rather than stacks.

MD cue variables survive a UI reload (`docs/RELOADING.md`, "Two consequences
worth knowing"), which is what makes the id comparison hold across the very
reload that triggers it.

## Buttons in Test Lab

| Button | Text id | Effect |
|---|---|---|
| Re-run current spec | 25 | Re-sends the loaded spec with `force = true` |
| Despawn test scenario | 26 | Destroys everything spawned; clears the recorded id |

A `Scenario spec: <id> (enabled\|disabled\|invalid …)` line sits above them.

## Failure handling

The spec is validated in Lua, not in MD, because a bad value in Lua is a log
line while a bad value in MD is a silently dead cue. A malformed spec is caught,
logged as `[X4GC TEST] event=scenario_spec action=rejected reason=…`, and Test
Lab still opens with the despawn button available. It never spawns a partial
fixture.

Log lines to watch, all prefixed `[X4GC TEST SCENARIO]` on the MD side:

- `accepting spec id=… force=…` — the spec was admitted.
- `skipped; spec already spawned id=…` — idempotency guard fired; expected on an
  unrelated Reload UI.
- `group … macro=… faction=… count=…` — one per group actually created.
- `spawned spec id=… ships=N` — the total.
- `skipping group …; unknown macro=…` — a typo in the spec.

## Transport, and why it looks the way it does

Lua cannot hand MD a nested table. The only live-tested Lua→MD payload shape is
a **flat table of scalar keys**, with the engine prepending `$` to every Lua
string key (research KB, "Lua→MD `AddUITriggeredEvent` transport contract",
live-tested 2026-08-04). A multi-group spec is therefore streamed:

```
scenario_begin  {specId, force}
scenario_group  {label, macro, faction, count, distance, spread, behaviour, hostile}   (repeated)
scenario_commit {}
```

MD queues the group events into a list of tables and creates them all on commit.
Group and commit events are ignored unless `scenario_begin` opened the window, so
a refused spec cannot half-apply.

## Evidence basis

Validated with `xmllint --noout --schema` against the extracted X4 9.00
`schemas-9.00/md/md.xsd`. Element-level grounding, all under
`.x4-research-cache/extracted/`:

| Element | Source file:line |
|---|---|
| `create_ship` with `owner`, `loadout` level | `scripts-9.00/md/rml_deliver_fleet.xml:251-259`; `scripts-9.00/md/lib_generic.xml:741-742` |
| `safepos` with a `z` distance plus `max` scatter | `scripts-9.00/md/tutorial_map_missions.xml:523` |
| `macro.{<string>}` resolving a UI-supplied macro name | `scripts-9.00/md/x4ep1_mentor_subscription.xml:9235-9236,9564` |
| `do_for_each` over a list of tables, `$Def.$key?` access | `scripts-9.00/md/rml_deliver_fleet.xml:461-483` |
| `append_to_list` of a `table[...]` literal | `scripts-9.00/md/factiongoal_plunder.xml:19` |
| `<continue/>` inside `do_for_each` | `scripts-9.00/md/rml_deliver_fleet.xml:475` |
| `set_value exact="[]"` for an empty list | `scripts-9.00/md/rml_rescueship.xml:97-99` |
| `check_value` on an optional `?` variable | `scripts-9.00/md/factiongoal_plunder.xml:241` |
| `add_relation_boost` to kill | `scripts-9.00/md/encounters.xml:300` |
| `create_order id="'Wait'"` | `scripts-9.00/md/rml_repairobject.xml:290` |
| `create_order id="'Attack'"` with `primarytarget` | `scripts-9.00/md/encounters.xml:301-306` |
| `do_for_each` + `destroy_object` cleanup | `scripts-9.00/md/cpu_ship_manager.xml:879-894` |

## What is not verified

- **`faction.{<string>}`.** `macro.{<string>}` is directly attested; the
  equivalent faction lookup is not. `faction` is declared as a lookup keyword
  exactly like `macro`
  (`props-9.00/libraries/scriptproperties.xml:2862-2864` and `:2903-2907`), and
  `lookup.faction.{$i}` indexing is attested at
  `scripts-9.00/md/gm_find_object.xml:1106-1108`, so the inference is strong but
  it is an inference. The MD falls back to `faction.xenon` and logs when the
  lookup returns nothing, so a wrong faction string is visible rather than fatal.
- Nothing here has been run in game. The whole spawner is offline-validated
  only: XSD-clean MD, green unit tests on the Lua side.
- Whether `add_relation_boost` alone is enough for turret `autoassist` to fire
  without a global `set_faction_relation`. Xenon-vs-player is already `kill` in
  every vanilla save, so this should be redundant.
- Whether `wait` ships stay truly stationary in low-attention mode. Keep
  `distance` well under 30 km.
- Whether `destroy_object` on a ship already destroyed in combat is safe. The
  `.exists` guard is present but untested against that case.

## Guardrails

- The shipped mod (`md/x4_gunnery_control.xml`) must never be modified. This
  spawner belongs exclusively to the Test Lab extension.
- The spec committed to the repository must be left `enabled = false`. A unit
  test enforces this, so a live fixture cannot be committed by accident.

## validate.sh

`./scripts/validate.sh` lints the MD via `xmllint`, byte-compiles the Test Lab
Lua, and runs `tests/test_testlab_lifecycle.lua`, which covers the enabled,
disabled and malformed spec paths. Run it before and after any edit.
