# NO_FORWARD_BOX_ENTRY evidence audit

Issue [#170](https://github.com/radlinsky/x4-gunnery-control/issues/170),
2026-09-16. Frozen study `11bd0ffa05f6f519485cfc365600e7b2a0c2d9dc`; starting
from accepted #169 SHA `6a3e52375ae45ac8abef68c974474c2b8cb91dad`. Offline
only: no full-study rerun, no production or frozen-study change. Throwaway
scripts and outputs: `.x4-research-cache/issue170/` (`scan.py`,
`classify.py`, `deep.py`, `counterfactual.py`).

## Population

All 2,585,916 cached trial records were scanned. Exactly **161,463** have
`reason=NO_FORWARD_BOX_ENTRY`: ordinary 161,463, official-adversarial 0,
synthetic 0. Every one reproduces through the frozen `approximate()` path and
its first logged query selects the same point as the native selector.

They come from **76 macro records / 72 components**, the same 76 nonzero-box
outside-point records audited in #169. In **161,463/161,463** the selected
authored aim point is outside the collision-filtered `macro.boundingbox`
(0.348–8.854 m from it).

| Ray relationship (direct ray origin→selected point) | Trials |
|---|---:|
| Unquantized direct ray misses the box entirely | 161,334 |
| Unquantized ray grazes the box; quantized query ray misses by 0.26–36 mm | 129 |
| Selected point inside box | 0 |

The 129 grazes are all at radius ≥1,000 m (76 at 20 km). 88 graze before
reaching the point, 41 would enter only beyond it. The miss is caused by the
2^-18 rad direction quantization, but it is only possible because the point is
outside the box: a ray aimed at an interior point cannot miss. **Unexplained
remainder after #169: 0.**

## Frame and slab checks

Origin, points, C and H are in the same macro frame used by the accepted #169
audit. An independent exact-rational slab test, using the frozen float values,
agrees with the frozen `slab()` on all 161,463 trials for both the quantized and
unquantized directions. The `enter > 0` / `exit >= enter` logic has no defect in
this population; the origin is never inside the box, so rejected rays are
genuine misses. The corrected tally is therefore unchanged.

## Production scope

The #169/#79 population rules were reused unchanged.

| Scope | Records / components | Trials |
|---|---:|---:|
| Production-eligible L/XL/station surface targets | 71 / 68 | 140,985 |
| No compatible L/XL/station mount | 3 | 16,077 |
| Integrated hull | 2 | 4,401 |

## Box-entry probe step

The step supplies a **range estimate**, and the triangulation needs one. With
no advancement (probe at the origin), the diagnostic rerun of these trials
reconstructs the point within E in only 55,288/161,463 trials. It fails with
`ILL_CONDITIONED` from 500 m outward.

Requiring the ray to **enter** the box is an **unnecessary restriction**.
Diagnostic rerun of only these 161,463 trials, changing just the missing-entry
case to use the query ray's nearest approach to the box: 161,463/161,463 then
reconstruct the selected point within E, and all still end at the separate
#169 containment rejection.

The step is also **not a safe "before the target" guarantee** once points may
lie outside the box. Across the 556,737 frozen trials of these 76 macros that
did place a probe, 240,721 put probe A at or beyond the selected point along
the original direction, by up to 37.9 m. All of them still reconstructed the
point within E (#169). Rays are lines, so this was harmless here because each
record has one aim point. For multi-point targets it could let the probe select
a different point. This is a risk, not an observed failure.

Generic rule suggested by the evidence, **not implemented or validated**:
- Derive the probe range from the query ray's nearest approach to the box,
  which equals box entry when the ray hits.
- Accept rays that pass near the box.
- Do not assume the probe precedes the aim point.
- Drop the inside-box acceptance check per #169.

These are diagnostic outcomes only. ENGAGEABLE rates stay diagnostic until
#173.

## Classification

- The whole bucket is a consequence of #169's outside-box aim points, which
  expose a wrong box-entry requirement in Route A.
- 129 of those trials also depend on direction quantization near a grazing
  edge.
- No slab, frame, or reconstruction defect was found. No stress-only family
  contributes.
- The original 161,463 remains the correct frozen broad-corpus count. Its
  meaning changes from an unexplained model failure to a coverage loss
  caused by that restriction.

No LIVE X4 test is needed. The box geometry is already LIVE-backed in #169,
and the rest is offline algebra over the frozen inputs.
