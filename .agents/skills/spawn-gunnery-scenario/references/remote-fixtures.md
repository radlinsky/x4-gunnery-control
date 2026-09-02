# Remote fixtures

Read this only when `setup.remote = true` or the player must teleport into a
spawned shooter.

## Operator flow

1. Start from a safe launcher ship and open its gunnery console.
2. Open **Gunnery Control → Test Lab** and click **Create test scenario** exactly
   once.
3. Wait for the correlated acknowledgement before teleporting.
4. Teleport to the exact named spawned player ship.
5. Open that ship's gunnery console and open **Test Lab** exactly once.
6. Continue only after the fixture reports READY or a required in-system
   qualification reports QUALIFIED. Never press Create again after teleport.

A remote fixture may report PENDING when exact geometry cannot be qualified from
the launcher's system. PENDING is not READY. The single post-teleport Test Lab
open may run the required qualification, but it must stop closed on failure or
timeout. Preserve the fixture and evidence; do not retry guessed coordinates.

## Destructive-action safety

Create replaces the existing Test Lab fixture, and Despawn destroys it. Test Lab
must therefore enforce these guards in code rather than relying on operator
wording:

- reject or disable Create while a remote teleport/setup is pending;
- reject or disable Create and Despawn while the current player ship belongs to
  the spawned fixture;
- re-check occupancy in the destructive click handler, not only when the button
  was rendered;
- have Mission Director cleanup/replacement independently refuse to destroy an
  occupied spawned fixture.

Do not ask the owner to use Create, Despawn, Reload UI, or manual cleanup as a
routine recovery step after teleport.

## Placement and qualification

Create the fixture in the resolved remote sector. `player.zone` still describes
the safe launcher until teleport, so do not use it as the remote fixture's
location.

If the experiment needs an absolute remote anchor, avoid scalar `distance = 0`
for transported groups: the current Lua-to-MD transport treats zero as a missing
optional value and may substitute its default. Use a shared small nonzero base
offset while preserving the intended relative geometry.

Use a bounded search only when the predicates being measured are available in
the current attention/system state. Preserve the same object while searching,
wait a nonzero interval after each move before measuring, log every candidate,
and accept only a reproducible candidate that satisfies the stated predicates.
If those predicates require the player to be in-system, keep the authored
candidate and defer qualification until after teleport.

## Evidence

Normal remote READY must be tied to the same request token/spec id used for
Create. A geometry-deferred fixture should record the remote pending state and a
separate post-teleport qualification request followed by exactly one terminal
QUALIFIED, FAILED, or timeout result.

Do not treat a geometry qualification as proof of actual turret targeting or
firing. The gameplay test still needs its own correlated shot/projectile/hit or
other experiment-specific evidence.
