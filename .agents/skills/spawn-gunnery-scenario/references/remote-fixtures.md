# Remote fixtures

Read this only when `setup.remote = true` or the player must teleport into a
spawned shooter.

## Operator flow

1. Start from a safe launcher ship and open its gunnery console.
2. Open **Gunnery Control → Test Lab** and click **Create test scenario** exactly once.
3. Continue only after the correlated READY acknowledgement.
4. Teleport to the exact named spawned player ship.
5. Open that ship's gunnery console and open **Test Lab** exactly once.
6. Continue only after Test Lab verifies and arms the exact configured group.
   Never press Create again after teleport.

## Destructive-action safety

Create replaces the existing Test Lab fixture, and Despawn destroys it. Test Lab
must enforce these guards in code rather than relying on operator wording:

- reject or disable Create while a remote teleport/setup is pending;
- reject or disable Create and Despawn while the current player ship belongs to
  the spawned fixture;
- re-check occupancy in the destructive click handler, not only when the button
  was rendered;
- have Mission Director cleanup/replacement independently refuse to destroy an
  occupied spawned fixture.

Do not ask the owner to use Create, Despawn, Reload UI, or manual cleanup as a
routine recovery step after teleport.

## Placement

Create the fixture in the resolved remote sector. `player.zone` still describes
the safe launcher until teleport, so do not use it as the remote fixture's
location. Author exact sector-relative offsets in `scenario_spec.lua`; do not ask
the owner to fly or nudge a fixture into place.

## Evidence

Remote READY must be tied to the same request token/spec id used for Create. The
post-teleport Test Lab open must independently resolve the exact configured ship,
raw turret group, operational member count, and optional member-macro multiset
before arming the group.
