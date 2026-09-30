# A5 runtime aim-query survey: can X4 tell us whether a turret can bear? — 2026-09-18

Scope: [Issue #176](https://github.com/radlinsky/x4-gunnery-control/issues/176)
A5, universal CANNOT BEAR baseline. Starting SHA `68555c9`. X4 9.00 build
611726, `X4.exe` SHA-256 verified. Research only: no production change, no live
run, and no new benchmark rows. Durable X4 facts are in
[`turret-aim-feasibility-surface.md`](../../.agents/skills/research-x4-modding/references/turret-aim-feasibility-surface.md).
This file holds the issue-specific analysis. Static native scratch lives under
the ignored `.x4-research-cache/issue176-a5-native/`.

## Headline

1. **X4 has no script-visible CANNOT BEAR query.** No MD property, action,
   event, declared FFI function or undeclared export answers "can turret T
   reach point P?". The engine never computes that answer as a stored result:
   the joint solver clamps out-of-limit requests without recording anything.
2. **The engine does know each macro's limits, but keeps them internal.**
   `Weapon::Defaults` holds one yaw pair and one pitch pair for every loaded
   weapon macro, including DLC and mod macros. Its only reader is the
   no-argument player-HUD export `IsPointingWithinAimingRange`. Reading the
   limits for an arbitrary turret would need native code, which is excluded
   for production.
3. **Every ray method locates the aim point, not reachability.** Same-ray,
   three-ray and direction all answer "where is P?". Turning P into PASS or
   FAIL needs the turret's limits and pivot geometry. A4x supplies those from
   the corpus record. For a truly unknown turret, no shipped runtime source
   supplies them. This is the largest gap in the universal baseline, and it is
   separate from ray quality.
4. **No generic prior rescues FAIL.** Across all 288 supported turrets, the
   union of authored limits covers the whole sphere. Pitch ranges from −90° to
   180°, and yaw is unlimited on 279 turrets. A "no known turret could reach
   this" rule therefore never fires. A "typical turret" rule would guess
   wrong: 179 of 288 turrets use a −10° pitch minimum, and the rest differ.

## 1. Promising — worth testing or building

### 1a. Adaptive aim-point localisation with arbitrary-origin queries

- **Information X4 provides:** the direction from any chosen origin to the
  aim point that the selector picks from that origin (`create_orientation
  useaimtarget="true"` with a `<position value=… object=… space=…>` origin).
- **How Gunnery Control gets it:** MD `create_orientation` calls from probe
  origins it chooses in weapon space.
- **Per turret:** yes. The origin is that turret's muzzle or origin.
- **Unknown or mod turrets:** yes, for locating P. It still needs limits and
  geometry to score P (headline 3).
- **Passive:** yes. It is a query and changes no game state.
- **Cost:** about 3–20 cheap MD actions per turret–target pair, depending on
  the variant below.
- **Evidence:** the schema documents the origin (`shipped-source`). Vanilla
  uses offset origins with `object`/`space` (`shipped-source`). The selector
  picks the aim point nearest the query origin (`inference`, native trace in
  `macro-box-aimtargets.md`). The A4/A5 offline surrogate models exactly this.
  The combination of an offset origin with `useaimtarget` has not been run
  live.
- **Why it improves on the fixed ladder:** the same-ray audit showed that a
  bracket cannot be scored by its ends. The fix is to measure λ, then score
  one point. Two ways to measure it:
  - **Triangulation with a certificate.** Query from O and from two lateral
    probes `O + δ·e1` and `O + δ·e2`, with `e1` and `e2` perpendicular to
    `d0`. If all three select P, the rays meet at P and λ follows. The error
    grows roughly as `λ²·σθ/δ`. If a lateral probe switched to another point
    Q, its ray misses the O ray except when Q lies in that probe's plane
    through the O ray. Two independent planes leave only the exactly
    collinear case, the same hazard every method shares. A nonzero
    closest-approach residual detects the switch. Then shrink δ and retry.
    The baseline δ comes from the residual test, not from a rough distance,
    which removes bucket 4's rough-distance dependence.
  - **Exponential search then bisection on the anchor ray.** On `[O, P)` a
    probe always returns `d0`, because the cell is convex. The first
    non-forward probe gives an upper bound, so there is no open bracket.
    Bisection narrows the bracket. Precision stops at the float-noise band
    near P, which the audit put at up to about 6.4% short of P at the 1e-4
    forward tolerance. Robust, but coarse.
- **Mechanical failure versus switching:** once P is located, the two separate
  cleanly. Switching is a query-phase event: an inconsistent reading, a
  residual, or a non-forward probe short of the predicted P. CANNOT BEAR is
  then the scorer's verdict on one located point. They are entangled today
  only because a bracket may span a limit crossing.
- **Smallest next step:** offline first. Add a `triangulate` method, with
  residual certificate and δ shrink, to the A4x harness. Run it as a focused
  pilot on the bucket 2/3/4 rows and the known172 rows, with the two bucket 3
  rows (10719 and 1815) as named regressions. Live second: one Test Lab
  capture comparing offset-origin `useaimtarget` directions with the
  offline selector for a fixture with known aim points.

### 1b. Passive bore-witness learning

- **Information X4 provides:** on every shot, `event_weapon_fired` names the
  exact weapon, and its `param` is the fired projectile. The projectile's
  rotation, or its rotation relative to the turret, is the bore direction at
  the moment of fire.
- **How Gunnery Control gets it:** an MD `event_weapon_fired` listener over
  the ship's turrets. Record mount-frame yaw and pitch per turret instance,
  throttled.
- **Per turret:** yes. **Unknown or mod turrets:** yes. **Passive:** yes.
- **Cost:** one handler per shot, which is high volume, so it needs
  throttling or binning. Storage is a small per-turret envelope.
- **Evidence:** `live-tested` as a bore-direction proxy in the rank-1 and
  rank-2 settled-transform records, with models instantiated from projectile
  bore directions. The event and `bullet.launcher` are `shipped-source`.
- **What it can prove:** a direction the turret actually fired along was
  reachable then. That supports PASS for targets whose required direction is
  within tolerance of a witnessed bore, after pivot parallax.
- **What it cannot prove:** that an unwitnessed direction is unreachable. The
  witnessed set is an inner envelope that grows with play time. Using its
  edge as a FAIL boundary is extrapolation and biases toward false CANNOT
  BEAR near real limits. Turrets that never fire, such as those holding
  fire, blocked or idle, contribute nothing.
- **Smallest next step:** a Test Lab log of mount-relative projectile
  rotation for one turret swept across its known pitch stop. Measure how
  close the witnessed envelope gets to the authored stop, and how fast.

## 2. Possible, but one specific fact is missing

### 2a. Clamp detection from muzzle stall

- **Information:** `weapon.barrelposition` is the live selected-connection
  translation and moves with the joints. The KB records a live observation
  (experimental) and a native trace.
- **Idea:** while a turret is solving for a target the mod itself
  designated, a turret parked on a clamp holds its muzzle still while the
  required direction keeps moving.
- **Missing fact:** a turret's current target is unreadable in general. It is
  known only when Gunnery Control designated it. Also, the MD sampling rate
  of `barrelposition` versus the mover step is not measured. Passive, per
  turret, generic, but weak: a stall is also what an on-target turret does
  against a static target.

### 2b. Hidden Lua data-getter keys

- **Missing fact:** the name behind any of the 31 unnamed `GetMacroData`
  keys or the 111 unnamed `GetComponentData` keys.
- **Why it is only possible:** keys are FNV-hashed, so they can only be named
  by guessing and matching. The limit fields are provably not read by either
  getter, so this route cannot expose `Weapon::Defaults` limits. It is kept
  only because an unnamed key could expose something else, such as a
  connection restriction read directly. The probability is low. A live call
  with an unknown key is safe, but it is not recommended before a static
  handler check.

## 3. Dead ends

| Route | Why | Evidence |
|---|---|---|
| `IsPointingWithinAimingRange` | `bool(void)`. Tests the player's pointing direction against the player ship's active-group weapon limits | inference (native trace) |
| `GetWeaponDetails2` | `(size_t weaponnum, bool issecondary)`, player-slot HUD details | inference; successor declared in vanilla |
| `IsTargetInPlayerWeaponRange`, `GetRelativeAimOffset`, `GetTargetAngle`, `GetPlayerTargetOffset` | Player-ship or HUD scope, with no turret argument | shipped-source declarations |
| Other undeclared keyword exports | Launched-macro selection, turret group mode, soft target, VR/Tobii/radar | inference (name sweep over 2378 exports) |
| `weapon` script properties | No aim, angle, limit or joint property. `isreadytofire` means active and deployed only | shipped-source |
| Lua data getters for limits | No handler reads `Weapon::Defaults +0x9F0..+0x9FC` | inference (full-image scan) |
| Solver or aim-entry result | Silent clamp. The "settled" flag is also true on a clamp. Return values are discarded | inference |
| Started/Stopped Aiming and ShootTarget events | Native-only. Absent from the MD/AI schema and Lua | inference |
| `GetDistanceBetween` as λ | Component origin to component origin, approximate square root. Not the aim point | inference (native trace) |
| `distanceto` / `bboxdistanceto` as λ | Origin or box distances, not aim-point distance. `bboxdistanceto` is biased short, which opens brackets | shipped-source |
| `componentslot.rotation` on turret joints | No script route yields a turret joint slot | shipped-source (property census) |
| Corpus-union reach prior | The union covers the full sphere, so it never fails | offline corpus computation (this file) |
| `$turret.rotation`, `barrelposition` as direction | Already known dead | existing KB |

## 4. Unsafe or inappropriate for production

- **`aim_turret`, `fire_turret`, `reset_turret` as probes.** None returns a
  result. `aim_turret` drives the same aim entry as normal control and moves
  the joints, so probing would interfere with the player's turrets.
- **Native helpers (X4Native or any DLL).** These could read
  `Weapon::Defaults`, subscribe to the internal aiming and shoot-target
  events, or call the solver. The issue excludes them for production, and so
  does the owner: users would need a native toolchain and Protected UI off.
- **Hijacking player weapon groups to reach `IsPointingWithinAimingRange`.**
  This mutates player state, still measures the player's pointing direction
  rather than a target, and covers only one weapon per group.

## Explicit answers

- **Direct generic CANNOT BEAR engine query?** No.
- **Engine field or function that a small wrapper could expose?** Yes,
  internally: the `Weapon::Defaults` yaw/pitch pair per macro, generic and
  present for mods but lossy (one pair per axis, no Z, no pivots), and the
  solver's clamp. Any wrapper would be native, so there is no production
  route.
- **Is a ray or probe method still necessary?** Yes, to locate P. It is not
  sufficient: an unknown turret also needs runtime limits and geometry, and no
  shipped surface provides them. The universal baseline can gain sound PASS
  evidence from bore witnesses. It has no sound FAIL source from any exposed
  X4 surface.
- **What would most improve rays:** measure λ instead of bracketing it.
  Triangulate with lateral probes, use the closest-approach residual as the
  switch certificate, and shrink δ adaptively. Bisection is the robust
  fallback. Then score only the located point. This removes the open-bracket
  flip-back hole and the rough-distance dependence. Do not use
  `GetDistanceBetween` or `bboxdistanceto` as λ.
- **Single most valuable unanswered question:** can the universal baseline
  get any sound runtime FAIL evidence for an unknown turret without
  prebuilt data? The static answer for the shipped surface is no. The only
  generic information left is observed behaviour, so the question becomes how
  quickly and how closely passive bore witnesses (1b) approach an unknown
  turret's real limits in live play. If they do not, the universal baseline
  should return PASS-with-evidence or UNKNOWN, never FAIL. Aim-point
  localisation (1a) then matters only for the specialized methods.

## Recommended next task

Run the 1b live measurement in Test Lab: log mount-relative projectile bore
directions for one known turret swept across its authored pitch stop and
across yaw. Report how close the witnessed envelope gets to the authored
limits and how fast. It decides whether the universal baseline can ever issue
FAIL, which is the question the remaining ray work cannot answer.
