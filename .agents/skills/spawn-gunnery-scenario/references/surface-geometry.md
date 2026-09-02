# Surface and geometry fixtures

Read this only when the live test depends on turret arc, line of fire, a specific
surface element, manual root-to-surface designation, or a geometry search.

## Use one exact object for each claim

Qualify the same exact component the owner will interact with. Do not combine a
root-level predicate with a different module or surface and call the result one
fixture state.

For each role, keep these independent where they matter to the experiment:

- exact component identity;
- range;
- firing arc;
- attackability;
- line of fire or other experiment-specific geometry predicate;
- operator designation and observation correlation.

A no-fire interval does not identify which predicate failed. `ON SOLUTION` or a
geometry-qualified state proves only that a geometry solution was found; it does
not prove that the turret actually targeted or fired at that object.

## Weapon-relative placement

For tight remote geometry, resolve the exact selected weapon position after
teleport and place or reposition preserved targets relative to that point.
Preserve the authored target rotation and fail closed if the post-warp transform
or identity does not match the requested fixture.

Do not rely on absolute remote coordinates for a narrow arc split when weapon
position is the quantity that matters.

## Bounded search

Use a bounded search only when a deterministic authored coordinate cannot express
the required discriminator and the relevant predicates can be measured in the
current state.

- search a fixed finite candidate set;
- move the same preserved object rather than respawning candidates;
- wait a nonzero interval before measuring each moved candidate;
- log each candidate and every predicate used to accept it;
- accept only when all required predicates pass together;
- stop closed if none pass;
- never ask the owner to retry guessed coordinates manually.

A generated coordinate is not deterministic evidence until it reproduces on a
fresh fixture.

Treat immediate post-warp line-of-sight readings as telemetry unless the
experiment specifically establishes that the settled-state gate is valid.

## Manual surface interaction

Test Lab may prepare the exact turret group and visible aids, but it must not
perform a Direct-control root/surface click when that interaction is itself
under test. Arm timed observation only after Gunnery accepts the owner's exact
manual designation.

Every surface the owner must select needs an unambiguous visible identity: use a
sparse unique loadout or a proven marker. Duplicate visible rows invalidate a
fixture if the owner would have to infer the correct surface from an internal id,
list position, or hull location.

## Controls and evidence

Keep control roles independent. A blocked-line-of-fire control should not also
be the out-of-range control unless the test explicitly needs both predicates on
the same object.

For a solid blocker, visible hull overlap is not enough; meshes can contain
openings. Require the experiment's exact muzzle-line predicate to show blocked
for every weapon whose line of fire is claimed blocked.

Prefer correlated per-weapon FIRED/projectile/HIT evidence and exact-component
HIT attribution where available. If a visual assertion cannot be logged, record
it only as the owner's observation and do not promote it beyond what it proves.
