# CLEAR LINE OF FIRE susceptibility, vanilla X4 9.00 and SWI 0.9.1 HF (#202) — INTERIM

Status: **interim, offline inference**. Production evaluated: `d95e607` (guarded full). SWI: Star Wars
Interworlds 0.9.1 HF (`content.xml` version 091, 2025-12-24), read in place from the owner's local copy
(`Documents/temp_swi_location/starwarsmod_m1_091hf`, not beside the X4 install). Code: `susceptibility.py`
(`census`, `sample`, `report`). Raw outputs stay in `.x4-research-cache/issue202-susceptibility/`.

## Inventory (static census)

Ships: the #184 census rows (one component = one model; macros are variants).

| | vanilla | SWI |
|---|---:|---:|
| ship components (macros) | 203 (285) | 226 (257) |
| large target, no aim point (probe only in production) | 36 (18 %): 29 of 31 XL, 7 L | 1 (`mandator`) |
| single aim point exactly at the origin (production aims at the box centre instead) | 0 | 47 (21 %): 27 S, 20 M |
| several aim points (selection-mismatch guard) | 14 (7 %) | 128 (57 %) |
| aim point outside its own box (extension bound may be short) | 0 | 5 (2 %) |

Surface-element component types (turret incl. missile turret, shield, engine):

| | vanilla | SWI (MESH only) |
|---|---:|---:|
| types: turret / shield / engine | 142 / 67 / 71 | 119 / 31 / 111 |
| no collision body (X4 can never hit it; permits only a genuine miss) | 38 / 18 / 21 | 21 / 5 / 55 |
| aim point off its own collision | 16 / 1 / 1 | 57 / 10 / 45 |
| single aim point at origin | 0 / 0 / 2 | 0 / 0 / 0 |
| several aim points | 0 / 0 / 1 | 0 / 0 / 2 |
| beam turret macros (bullet `attach="1"`; inference) | 35 of 115 (18 are mining) | 6 of 162 |
| mount slots over all ship components: turret / shield / engine | 1,134 / 1,282 / 463 | 4,714 / 1,732 / 694 |

- SWI's `-hull.jcs` files (built for X4 8.00) do not parse as 9.00 hulls, so SWI is MESH-only; its
  off-mesh counts use mesh parity and may be inflated by open meshes. Whether X4 9.00 loads those hulls
  or falls back to `-collision.xmf` is a runtime question.
- Shipped loadouts are scripted only (NPC equipment is procedural), so installed-instance frequency is not
  determinable from source; mount slots are the exposure measure.
- The large-target offset region of all 36 vanilla ships is partly inside and partly outside the hull
  (15–96 % inside on a 5×5×9 sample): one per-ship bit cannot resolve it.

## Frequency, saved vanilla benchmark rows (production, MESH)

- False UNKNOWN on shots X4 permits: whole ship 40 (all the large-target ambiguity, ordinary 1.5 km
  views), station surface 30 (off-mesh Xenon shield points; extended line meets the parent module), ship
  surface 6.
- False CLEAR: 2 (a beam barrel grazing the parent hull, 300 m view).
- UNKNOWN on refused shots: nearly all surface elements whose own parent is hit first (X4 refuses via its
  second ray) — the correct not-counted outcome.

## Not yet done

- The targeted sample (13 hosts: 4 vanilla large-target ships, 9 SWI ships covering each flag; 4 vanilla
  attackers M1/L1/L2/X1 at 1.5 km and 300 m) was running when work stopped; results, per-method tables
  (origin metadata, large-target metadata, large-target dual check), ray costs, recommendation and the
  LIVE test are pending.
