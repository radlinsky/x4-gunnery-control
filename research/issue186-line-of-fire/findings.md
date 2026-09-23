# LINE OF FIRE benchmark findings (#186 L6)

Status: **inference** — offline decision-logic evidence over constructed scenes. Simplified box/sphere bodies do not reproduce X4 collision meshes; no LIVE evidence is added.

**66 scenes, 65 firing-origin + aim-point pairs, 2 no-origin inputs.** Result: **FAIL**.

| measure | value |
|---|---:|
| confirmed correct pairs/inputs (every concrete world) | 64 of 67 |
| failing pairs | 3 |
| wrong clear | 0 |
| wrong LINE OF FIRE BLOCKED | 0 |
| correct UNKNOWN | 4 |
| missing UNKNOWN (definite where truth is UNKNOWN) | 3 |
| excessive UNKNOWN | 0 |
| max LOS queries, non-guided pair (limit 4) | 3 |
| max LOS queries, guided / UNKNOWN-weapon pair (limit 0) | 0 |
| total simulated LOS queries | 145 |
| centre result differing from the hidden authored-point result | 2 |
| #184 frozen searches (one per target view) / max samples | 14 / 38 |
| offline Python run time (not X4 cost) | 4.0 s |

## Failures

- blocker-wreck state not established#M origin 0: expected UNKNOWN (ambiguous/unestablished wreck/presence state), got varies by concrete world (varies: selected target, unrelated)
- off-box-uncertainty#offbox origin 0: expected UNKNOWN (ambiguous/aim-point uncertainty), got clear (genuine miss)
- coincident#M origin 0: expected UNKNOWN (ambiguous/near-coincident hits), got varies by concrete world (varies: selected target, unrelated)

## Notes

- Simulated `check_line_of_sight` returns only a boolean. Where the offline scene leaves presence (unestablished wreck) or near-coincident first-hit order open, each pair runs in every concrete world (unknown body present/absent x tie order either way); `varies by concrete world` means the candidate's definite answer depends on a state it cannot observe.
- Aim-point uncertainty: the accepted centre-only candidate cannot return the L5 UNKNOWN when the #184 uncertainty ball straddles a blocker edge; `check_line_of_sight` exposes no hit distance. The `off-box-uncertainty` scene is that case (its hidden authored point happens to agree). L7 question.
- Observed maximum is 3 queries: the tree issues either the zone query or the second ray, never both. The accepted L4 bound of 4 is still enforced.
- XS comes from #184 `targets()` (the A4.4 census omits XS); `ship_arg_l_destroyer_01` is a real no-aim-point L ship from the vanilla A4.4 census (box-centre fallback); `arrestor_cruiser` comes from the SWI-applied census with a SWI turret. Rows keep `source` official/swi separate.
- Ammunition switch: `turret_arg_m_dumbfire_01_mk1` loads both ordinary unguided and cluster ammunition. No official missile turret's ammunition tags accept both guided and dumbfire macros, so a guided/unguided switch on one turret does not exist in source.
- The multi-origin scene uses 100 m: #185's only known multi-stable case (bor disruptor, leaf limit) is at that distance; the recovered #184 point is reached along that exact turret-local bearing.
- The whole station is two real module macros at explicit offsets; its runtime box is their union and its aim point the #184 box-centre fallback. Surface hosts use real attachment frames; host hull sections are explicit spheres, not runtime boxes.
- Pair-specific collision filters have no runtime-visible input, so no scene models them; they stay an L8 condition.

| group | clear | LINE OF FIRE BLOCKED | UNKNOWN | varies by concrete world | no pair |
|---|---:|---:|---:|---:|---:|
| CONVENTIONAL_STRAIGHT_PATH | 27 | 25 | 1 | 2 | 2 |
| DISTRIBUTING_CLUSTER_MISSILE | 0 | 2 | 0 | 0 | 0 |
| GUIDED_MISSILE | 2 | 0 | 0 | 0 | 0 |
| UNGUIDED_DIRECT_MISSILE | 0 | 3 | 0 | 0 | 0 |
| UNKNOWN | 0 | 0 | 3 | 0 | 0 |

| target_type | clear | LINE OF FIRE BLOCKED | UNKNOWN | varies by concrete world | no pair |
|---|---:|---:|---:|---:|---:|
| ship engine | 2 | 1 | 0 | 0 | 0 |
| ship shield | 2 | 1 | 0 | 0 | 0 |
| ship turret | 6 | 1 | 0 | 0 | 0 |
| station-module shield | 1 | 0 | 0 | 0 | 0 |
| station-module turret | 2 | 2 | 0 | 0 | 0 |
| whole ship ship_l | 2 | 0 | 0 | 0 | 0 |
| whole ship ship_m | 7 | 25 | 4 | 2 | 2 |
| whole ship ship_s | 1 | 0 | 0 | 0 | 0 |
| whole ship ship_xl | 3 | 0 | 0 | 0 | 0 |
| whole ship ship_xs | 1 | 0 | 0 | 0 | 0 |
| whole station | 2 | 0 | 0 | 0 | 0 |

| target_size | clear | LINE OF FIRE BLOCKED | UNKNOWN | varies by concrete world | no pair |
|---|---:|---:|---:|---:|---:|
| large | 6 | 0 | 0 | 0 | 0 |
| small | 23 | 30 | 4 | 2 | 2 |

| blocker | clear | LINE OF FIRE BLOCKED | UNKNOWN | varies by concrete world | no pair |
|---|---:|---:|---:|---:|---:|
| None | 13 | 0 | 1 | 0 | 2 |
| absent wreck+enemy ship | 0 | 1 | 0 | 0 | 0 |
| asteroid | 0 | 1 | 0 | 0 | 0 |
| asteroid+enemy ship | 0 | 1 | 0 | 0 | 0 |
| destroyed without wreck | 1 | 0 | 0 | 0 | 0 |
| enemy ship | 3 | 4 | 3 | 1 | 0 |
| enemy station | 0 | 1 | 0 | 0 | 0 |
| fresh ship wreck | 0 | 1 | 0 | 0 | 0 |
| gate | 0 | 1 | 0 | 0 | 0 |
| host part | 5 | 4 | 0 | 0 | 0 |
| host part+enemy ship | 1 | 0 | 0 | 0 | 0 |
| mine (representative small object) | 3 | 2 | 0 | 0 | 0 |
| missile+own hull | 0 | 1 | 0 | 0 | 0 |
| missile/explosive | 0 | 1 | 0 | 0 | 0 |
| own hull | 1 | 3 | 0 | 0 | 0 |
| own hull+enemy ship | 0 | 1 | 0 | 0 | 0 |
| persistent wreck | 0 | 1 | 0 | 0 | 0 |
| player ship | 0 | 1 | 0 | 0 | 0 |
| player station | 0 | 1 | 0 | 0 | 0 |
| restored wreck | 0 | 1 | 0 | 0 | 0 |
| station module | 0 | 2 | 0 | 0 | 0 |
| station-module wreck | 0 | 1 | 0 | 0 | 0 |
| wreck killed again | 1 | 0 | 0 | 0 | 0 |
| wreck state not established | 0 | 0 | 0 | 1 | 0 |
| wreck timed out | 1 | 0 | 0 | 0 | 0 |
| wrecked station | 0 | 1 | 0 | 0 | 0 |

| order | clear | LINE OF FIRE BLOCKED | UNKNOWN | varies by concrete world | no pair |
|---|---:|---:|---:|---:|---:|
| blocker before target | 5 | 20 | 3 | 1 | 0 |
| cross-zone | 0 | 0 | 1 | 0 | 0 |
| descendant module hit | 1 | 0 | 0 | 0 | 0 |
| external before own hull | 0 | 1 | 0 | 0 | 0 |
| genuine miss | 2 | 0 | 0 | 0 | 0 |
| multi-origin | 1 | 1 | 0 | 0 | 0 |
| near-coincident unrelated/target | 0 | 0 | 0 | 1 | 0 |
| no origin (#185 UNKNOWN) | 0 | 0 | 0 | 0 | 1 |
| no origin (CANNOT BEAR) | 0 | 0 | 0 | 0 | 1 |
| off-box beyond-endpoint | 1 | 0 | 0 | 0 | 0 |
| off-box uncertainty | 1 | 0 | 0 | 0 | 0 |
| own hull before external | 0 | 1 | 0 | 0 | 0 |
| removed body, later body blocks | 0 | 1 | 0 | 0 | 0 |
| same object before external | 1 | 0 | 0 | 0 | 0 |
| same object, second ray blocks | 0 | 4 | 0 | 0 | 0 |
| same object, second ray clears | 4 | 0 | 0 | 0 | 0 |
| selected target before same object | 1 | 0 | 0 | 0 | 0 |
| selected target before unrelated | 1 | 0 | 0 | 0 | 0 |
| sibling module (unrelated to surface module) | 0 | 1 | 0 | 0 | 0 |
| target only | 10 | 0 | 0 | 0 | 0 |
| two unrelated, closest decides | 0 | 1 | 0 | 0 | 0 |
| unrelated behind selected target | 1 | 0 | 0 | 0 | 0 |

| expected_class | clear | LINE OF FIRE BLOCKED | UNKNOWN | varies by concrete world | no pair |
|---|---:|---:|---:|---:|---:|
| ambiguous | 1 | 0 | 0 | 2 | 0 |
| cross-zone | 0 | 0 | 1 | 0 | 0 |
| genuine miss | 5 | 0 | 0 | 0 | 0 |
| guided bypass | 2 | 0 | 0 | 0 | 0 |
| no origin | 0 | 0 | 0 | 0 | 2 |
| same object, second ray blocks | 0 | 4 | 0 | 0 | 0 |
| same object, second ray clears | 5 | 0 | 0 | 0 | 0 |
| selected target | 16 | 0 | 0 | 0 | 0 |
| unrelated | 0 | 26 | 0 | 0 | 0 |
| weapon | 0 | 0 | 3 | 0 | 0 |

| result_reason | clear | LINE OF FIRE BLOCKED | UNKNOWN | varies by concrete world | no pair |
|---|---:|---:|---:|---:|---:|
| None | 29 | 30 | 0 | 2 | 2 |
| cross-zone target physics world | 0 | 0 | 1 | 0 | 0 |
| missing guidance | 0 | 0 | 1 | 0 | 0 |
| no loaded ammunition | 0 | 0 | 1 | 0 | 0 |
| unaudited modded ammunition | 0 | 0 | 1 | 0 | 0 |

| origin_source | clear | LINE OF FIRE BLOCKED | UNKNOWN | varies by concrete world | no pair |
|---|---:|---:|---:|---:|---:|
| None | 0 | 0 | 0 | 0 | 2 |
| current weapon.barrelposition fallback | 0 | 1 | 1 | 0 | 0 |
| geometry-predicted aimed muzzle | 29 | 29 | 3 | 2 | 0 |

| source | clear | LINE OF FIRE BLOCKED | UNKNOWN | varies by concrete world | no pair |
|---|---:|---:|---:|---:|---:|
| official | 28 | 30 | 4 | 2 | 2 |
| swi | 1 | 0 | 0 | 0 | 0 |

## Per-origin results

- `group-unaudited mod#M` (#185 CAN AIM): [(0, 'current weapon.barrelposition fallback', 'UNKNOWN')]
- `multi-origin#M` (#185 CAN AIM): [(0, 'geometry-predicted aimed muzzle', 'LINE OF FIRE BLOCKED'), (1, 'geometry-predicted aimed muzzle', 'clear')]
- `fallback-origin#M` (#185 CAN AIM): [(0, 'current weapon.barrelposition fallback', 'LINE OF FIRE BLOCKED')]
- `cannot-bear#M` (#185 CANNOT BEAR): [(None, None, 'no pair')]
- `c185-unknown#M` (#185 UNKNOWN): [(None, None, 'no pair')]

## Weapon behavior source check

Compatible official turret ammunition by group: {'DISTRIBUTING_CLUSTER_MISSILE': 2, 'GUIDED_MISSILE': 15, 'UNGUIDED_DIRECT_MISSILE': 8} (accepted L2: {'GUIDED_MISSILE': 15, 'UNGUIDED_DIRECT_MISSILE': 8, 'DISTRIBUTING_CLUSTER_MISSILE': 2}). Compatible macros without a usable guidance value: [('missile_story_dumbfire_light_mk2_macro', 'missing guidance')]. Missile-turret ammunition tag sets spanning guided and dumbfire: 0.
