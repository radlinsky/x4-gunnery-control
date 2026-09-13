# Offline prospective-muzzle verification for X4 turrets

**Recommendation: HYBRID OFFLINE/LIVE. Replace the per-geometry discovery process with verification of a source interpreter. Do not implement another turret batch first.**

The strongest new result is a deterministic explanation of the Split Plasma exception. Static analysis of the installed X4 executable traces `weapon.barrelposition` to the **first laser-tagged connection in unsigned connection-name-hash order**. The hash sorts `con_beam_02` and `con_laser_02` first, but `con_standard_01` first. This predicts all three #155 endpoint choices without a negative-X rule, a macro exception, or another launch. **[inference: traced shipped executable, corroborated by existing live-tested evidence]**

Across all 92 combat candidates, that rule selects lexical endpoint 2 for **46**, endpoint 1 for **35**, and endpoint 4 for **11**. No hash collision occurs among any individual turret's firing endpoints. All 92 have deterministically identifiable endpoint candidates and ancestry. The complete animation/aiming interpreter is not yet proved for all 92, so this report does **not** claim a finished full-offline oracle. It also finds no evidence that distinct geometry values inherently require distinct LIVE tests.

The audit produces **83 conservative geometry-input graph fingerprints**, not a dramatic collapse to eleven identical geometries. That is not the important efficiency limit. A verified matrix/animation operation can evaluate thousands of different vectors without a fresh experiment for each vector. Conversely, a transform-family label alone does not establish endpoint identity or complete geometry equivalence.

The research artifacts include a [92-row census](corpus.csv), [source verification manifest and graph groups](summary.json), [audit program](x4-offline-audit.py), and [retrospective calculation](x4-retrospective.py). These are research artifacts, not production changes. The full intermediate graph/ANI audit was intentionally omitted as reproducible generated data; proprietary extracted inputs remain outside tracked repository files.

## Evidence and scope

Repository inspected: branch `issue-155`, SHA `ce416fd702970b3f2305e38932b017aeb596a845`; clean at the start; only two research-KB reference files changed at handoff. GitHub #79 is open; #155 and draft PR #156 remain unaccepted/unmerged. The GitHub PR metadata inspected also identifies current `develop` as `503dc288b7d623c46e16eb5f4a2073bafb0554e2`; this report evaluates the explicit local SHA, not an assumed develop checkout. No game was launched, installation changed, issue edited, or production behavior implemented.

Official inputs: installed X4 `version.dat = 900`; executable file/product version `9.0.0.0`; base plus Split, Terran, Pirate, Boron, Timelines, mini_01 and mini_02 official source sets. Catalog indexing covered 30 non-signature catalogs and 513,274 catalog entries; current XML/XSD/Lua extraction covered 1,099 script/library files. The combat audit compares **274 distinct macro/component/ANI files byte-for-byte against current official catalogs**, checking catalog MD5 on reads and recording SHA-256. All 274 comparisons pass. This guards against silently interpreting stale cached assets. It is not a claim that every game file was semantically reverse-engineered.

Executable: `X4.exe`, 55,412,768 bytes, SHA-256 `19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`. Addresses below are preferred-base virtual addresses, image base `0x140000000`; subtract that base for RVA. No private engine C++ source or usable PDB was available. An embedded build path names `P:\exe_p1\Master\X4.pdb`; it is not a locally available symbol file. Historical correlated LIVE records identify X4 9.00 build 611726. The executable hash was not recorded in those historical issues, so exact historical binary equality is not asserted.

Evidence labels:

- **shipped-source:** directly inspected official XML, scripts, schemas, or data bytes. Data layout interpretation is separately qualified where necessary.
- **documented-public:** official public documentation; no public documentation found that specifies barrel hash ordering.
- **live-tested:** an identified historical runtime observation, with original-log reanalysis distinguished from a published evidence record.
- **inference:** deductions, including reverse-engineered function meanings, candidate generalizations, and completeness claims.
- **design-choice:** proposed support contract, representation, acceptance method, or implementation.

The existing ANI parser's detailed layout originated partly in a third-party converter. Official bytes establish stored values; they do not, by themselves, make every field name or interpolation interpretation authoritative. This report retains that limitation rather than silently upgrading it.

## 1. What ENGAGEABLE actually needs

The current mod implements a geometric engagement-availability predicate. It is not an exact reproduction of X4's complete firing decision, and it does not currently require readiness in the production counting loop. Range and arc precede own-hull-aware visibility probes. A prospective muzzle is used only after current-origin probes fail, for the relevant conventional surface-target path. Successful firing and `ENGAGEABLE` can therefore occur without ever exercising the prospective calculation. **[shipped-source: repository `md/x4_gunnery_control.xml`, EngageabilityService, approximately lines 230–390]**

For the prospective subproblem, define the required quantity as:

`p*(macro, desired joint pose) = weapon-local position of the barrelposition anchor in the chosen deployed, non-recoiling reference state`.

That definition must be made explicit. The instantaneous runtime quantity is instead `p(macro, actual joints, animation state, phase, scene state)`. Testing these as though they were identical creates false failures during deployment/recoil and false confidence when an unobserved axis of error is projected away. **[design-choice / inference]**

| Fact | Required role | Offline versus runtime |
|---|---|---|
| Equipment macro → runtime component | Select exact geometry definition, not a name-derived faction/family | Explicit macro/component references, offline |
| Turret-side mating connection and hull mount transform | Define component/mount coordinate relationship | Authored transform offline; actual mount instance and ship pose runtime |
| Connection and part ancestry | Ordered coordinate frames from component root to selected anchor | Offline XML graph |
| Authored connection and direct-part transforms | Fixed translations/rotations, including meaningful nonzero part offsets | Offline values; general application semantics require an engine rule |
| Articulation ownership, axes, limits | Identify where yaw/elevation enter the chain | Authored restrictions offline; current angles runtime; aiming convention requires semantic verification |
| Animation bindings and state | Choose active transforms and separate deployment/recoil | Bindings/state graph offline; current phase/state runtime |
| Barrel connection identity | Reproduce the particular anchor returned by `barrelposition` | Offline given the traced hash/filter/accessor rule |
| Endpoint ordering | Relevant to the engine's collection ordering, not the generator's array convention | Engine hash order; lexical order is not authoritative |
| Endpoint position and orientation | Point location and bore reference frame | Offline; leaf orientation does not move its own origin but can affect direction/aim interpretation |
| Desired aim direction → joint pose | Put the muzzle at its prospective pointing pose | Dynamic target direction; general kinematic inversion may be computed offline-defined/runtime-evaluated |
| Range | Current `$weapon.maxfirerange` versus target bbox distance | Runtime values; do not replace with a static turret constant |
| Firing arc | Current aim point relative to mount and authored stops | Mixed source/runtime; not a muzzle validation question |
| Target geometry | Native aim point, bounding box witnesses, root/module policy | Static geometry plus runtime target identity/transform |
| Own-hull line of sight | Ray queries from current/prospective point | Runtime collision query; a static muzzle oracle cannot determine a changing scene |
| Readiness, deployment, firing cycle, scene/collision availability | Determines whether actual instantaneous geometry equals the reference state | Runtime state; isolate or parameterize it |

Production currently compresses geometry into `O + Ry(yaw) * (P + Rx(-pitch) * D)` in `ui/gunnery_control.lua`. This form is sufficient only when the actual joint frames and desired-angle convention permit that factorization. A general hierarchy has fixed rotations between joints. Unless those commute or are explicitly folded into transformed axes, arbitrarily placing two rotations into this nine-scalar formula is not valid. Source-equivalent composition and compatibility with this particular production representation are separate proof obligations. **[inference from the implementation and rigid-body algebra]**

## 2. What the current workflow is really testing

Four different obligations have been bundled together:

1. **Engine semantics:** which connection `barrelposition` returns; how ANI coordinates, rotations, defaults and animation state affect it.
2. **Source interpretation:** resolving the exact macro, ancestry, offsets, channel values and endpoint without parser errors.
3. **Implementation equivalence:** whether generated data, Lua factorization and MD reconstruction evaluate the intended model.
4. **Integration and measurement:** whether the intended runtime turret and prospective branch were exercised and whether logged pose and position describe the same instant/state.

The first can need an engine discriminator. The second and third are principally offline verification. The fourth requires some runtime integration evidence, but not automatically one new fixture and launch per geometry. **[design-choice]**

#83 genuinely discovered additive-versus-replacement composition and the ANI-X convention. Its right-minus-left comparison was blind to a fixed translation error; absolute observations exposed that error. #128 distinguished radian versus degree interpretation. #132 rejected doubled/additive scale but could not distinguish ignored unit scale from multiplicative unit scale. #155 discovered a wrong endpoint assumption. These were semantic experiments hidden inside per-turret tasks. **[live-tested: cited issue records]**

Once a parameterized operation is independently established, repeating it for a different literal translation or X-angle adds parser/integration coverage, not a new mathematical rule. #137 repeatedly rejected source records because their values, counts or topology lay outside existing literal guards. That is valid evidence of a narrow implementation boundary; it is not evidence that X4 has a special engine rule for each such value. **[inference]**

Two concrete current defects underline the distinction:

- Of the 37 generated records, **nine** have an endpoint-2 selection inconsistent with the traced engine rule: ARG M Plasma 02; PAR M Plasma 01/02 and Gatling 01; TEL M Plasma 01/02 and Gatling 01; TER M Gatling 01; SPL M Plasma 02. Only the last has the explicit #155 runtime discriminator; the other eight are engine-trace predictions, not newly live-tested bugs.
- PAR and TEL M Shotgun 01 each have one endpoint. Executing the actual production derivation preamble with the generated file returns no prospective entry for those two: **37 generated, 35 streamable**. This is an offline reproduction, not an inference from ENGAGEABLE counts. `geometry.endpoints[2]` is the immediate cause.

Thus only **26/37** current generated records both produce a prospective entry and choose the traced anchor. This says nothing by itself about their remaining transform accuracy. **[shipped-source / inference: endpoint meaning from executable trace]**

## 3. How X4 determines the runtime muzzle

### Source and executable data flow

Macro XML explicitly names a component. Component XML contains connections, tags, parent-part references, direct-owned parts and transforms. The census already reconstructs these relationships. `laser` tags identify the ordinary weapon emitter connections in this corpus. ANI data attaches named state descriptors to source parts; XML selectors and `libraries/animation_sequences.xml` supply state bindings/transitions. **[shipped-source]**

Ordinary shipped MD/AI/Lua does not contain the full barrel transform implementation. `libraries/scriptproperties.xml`, weapon datatype, documents `barrelposition` and warns that weapons without collision can return zero. Static tracing continues into the executable:

| Stage | Installed executable evidence | Interpretation |
|---|---|---|
| Script property | `barrelposition` string at `0x142a1e0f0`; metadata maps it to ID `0x4e`; evaluator switch entry reaches `0x140d04598` | Links the script property to native code |
| Getter | Case calls `0x1407c6e80`; this clears `edx` before calling `0x1405bebc0` | Requests endpoint index **zero**, not a cycling shot index |
| Endpoint collection | `0x1405bebc0` indexes pointers in defaults offsets `+0x7a0..+0x7a8` | The selected pointer comes from the weapon definition |
| Collection construction | `0x14081e2d0`, at `0x14081f097`, loads the `laser` tag ID and calls `0x14081f7f0` | Ordinary firing connections are tag-filtered |
| Tag provenance | Global `0x14395ccd8` initialized using string `laser` at `0x142b8aba4`, through initialization around `0x1408d81eb..0x1408d8236` | This is a tag identity, not a name-prefix heuristic |
| Enumeration | Macro vtable `0x142ba5430`, slot `+0xa8`, reaches `0x140973ba0` → `0x14088cc80` | Iterates template connection storage in order; appends passing connections without reordering |
| Storage order | Loader `0x140886940..0x140889193`; name hash construction at `0x140888483`; lower-bound ordinal lookup `0x140947e90`; writes slot at `ordinal * 0x160` | Connection entries are addressed in unsigned numeric hash order |
| Independent lookup corroboration | `0x14088cb60` binary-searches the same stride-`0x160` array using its `+8` hash | Supports the ordering interpretation |
| Hash implementation | `0x14034c220`, especially `0x14034c23e..0x14034c25f` | Initial 64-bit value `0x811c9dc5`; multiply then XOR, with 64-bit wrap |
| Spatial evaluation | Getter invokes vtable `+0x1ec8`; Weapon/Turret implementations point to `0x14081c960` | Evaluate selected connection at current runtime state |
| Scene transform | `0x14081c960` calls `0x140e22b70` when the relevant scene/physics state exists; otherwise follows a static fallback | Scene-backed and fallback paths must not be conflated |

All function-purpose labels in this table are **inference from disassembly**, not public symbols or published source names. The actual instructions, constants, strings and control-flow links are observations of shipped executable bytes. This is substantially stronger than fitting a rule to three endpoint samples, but remains pinned to the executable hash.

The hash for the ASCII names in this corpus is:

```python
h = 0x811c9dc5
for byte in connection_name.encode("ascii"):
    h = ((h * 0x1000193) & 0xffffffffffffffff) ^ byte
```

This is **not** ordinary FNV-1a, and it is not standard FNV-64 with its usual constants. The native loop sign-extends bytes; ASCII avoids that distinction. A production implementation should reject unsupported encodings and collisions until their semantics are intentionally covered. Select the minimum unsigned hash among eligible `laser` connections. Do not sort by decimal/hex spelling or signed integer order. **[inference]**

A separate accessor at `0x1405bec50` uses weapon state at `+0x2f0`; `0x1407c6ed0` advances that state modulo the endpoint count. `barrelposition` instead passes fixed index zero. Consequently, the anchor returned by this property need not be the barrel that emitted the particular correlated projectile. This explains why projectile direction is only a pose proxy and why “emitter connection” and “barrelposition anchor” need distinct vocabulary. **[inference]**

### Transform tracing and its remaining boundary

`0x140e22b70` composes the leaf connection matrix and its parent part. It can use a scene-provided transform, or call `0x14074c2d0`; that function obtains an animated part transform through `0x141165440`, otherwise a stored part transform, and combines it with its owning connection via `0x14074be30`. The recursion exposes explicit matrix composition, scaling-related paths and runtime scene inputs. **[inference]**

The animation path continues `0x141165440` → `0x1411608b0` → key evaluator `0x14115fdc0`. The inspected position/rotation routine uses channel arrays at `+0x28` and `+0x40` and trigonometric rotation construction. Nearby `0x141160c80` processes additional scale/pre/post channels. This is a concrete route for recovering general semantics offline. It is **not yet a fully verified mapping from every ANI byte through scene articulation to the returned point**. In particular, defaults, scale stripping/application, selector inheritance and joint application need completed linkage before those routines justify a universal interpreter. No unexplained result is labeled “engine-only and unrecoverable” merely because that linkage is unfinished.

One previously missing rule is directly in ordinary shipped source: `libraries/animation_sequences.xml` defines `turretloop_activating → turretloop_active`, the active self-loop, firing and deactivation. #137's Xenon L Plasma state-family gap need not be answered by discovering the state name LIVE. The transform and phase behavior still need interpretation. **[shipped-source]**

## 4. Why #155 Split Plasma differs

| Macro | Connection 01 hash | Connection 02 hash | Minimum unsigned hash | Existing LIVE result |
|---|---:|---:|---|---|
| `turret_spl_m_beam_02_mk1_macro` | `5836806a11999f07` | `5836806a11999f04` | `con_beam_02` | endpoint 2 |
| `turret_spl_m_laser_02_mk1_macro` | `0c9442e72bbe5383` | `0c9442e72bbe5380` | `con_laser_02` | endpoint 2 |
| `turret_spl_m_plasma_02_mk1_macro` | `679c43e529f14519` | `679c43e529f1451a` | `con_standard_01` | endpoint 1 |

**[inference: hash calculation and engine trace; live-tested: #155]**

The generator's lexical array indices are incidental. Negative local X is also incidental: none of the traced selection code tests endpoint X. Shared transform composition remains possible; shared complete geometry identity does not follow. The same engine selection rule yields different lexical indices because the names hash differently.

The recovered #155 log independently reproduces the decisive published values. Window `t >= 249104`, exact Split emitters and the original Plasma aim-error filter yield 190 Laser, 6 Beam and 20 Plasma FIRED samples. This window was selected retrospectively to reproduce the published settled corpus; it is not a new predeclared acceptance experiment. Log SHA-256: `eb651fd8e82d6b303c28ebb448326c2d915ddc6913dc68e2b9663611defc703a`.

| Macro | Selected-anchor residual, metres | Alternative | What this establishes |
|---|---:|---:|---|
| Split Laser 02 | perpendicular min `0.000001893`, median `0.000016794`, max `0.000026825` | ~`4.50103` | Strong anchor and transverse geometry agreement |
| Split Beam 02 | perpendicular min `0.0119953`, median `0.0155294`, max `0.0216822` | `4.79716..4.82453` | Correct endpoint discriminator; original 0.020 m all-samples gate still fails |
| Split Plasma 02 | target-bearing-perpendicular min `0.00637605`, median `0.00825239`, max `0.01141186` | `4.937934..4.937991` | Decisive endpoint-1 selection; not full absolute recoil-state agreement |

There is a provenance correction: the fresh window's FIRED records say `mode=attackenemies`, whereas the issue text describes the runs as `autoassist`. The numerical endpoint results reproduce despite that mismatch. Preserve the log's actual mode rather than silently rewriting it to match the issue. The earlier historical window includes autoassist. **[live-tested: archived log reanalysis]**

## 5. Proposed offline oracle

The smallest trustworthy oracle has two outputs: **which anchor**, and **the reference-state transform function**. It should report unresolved semantics explicitly instead of equating “not recognized by today's allowlist” with an ambiguous game asset. **[design-choice]**

Algorithm:

1. Resolve official macro/component references against the actual installed source-set/load order; verify source hashes. Extensions that patch these definitions require a rebuilt oracle or fail-closed scope restriction.
2. Enumerate eligible connections using the traced tag rule; compute unsigned name hashes; reject collisions or unsupported names; select index zero in that order. Preserve the selected connection's spelling and hash as provenance.
3. Walk its complete component/connection/part ancestry. Retain both connection transforms and direct-part transforms, articulation restrictions/owners, relevant flags, and all state bindings. Resolve references by identity, never name resemblance.
4. Resolve the explicitly chosen reference animation state through the shipped state graph and selectors. Interpret the ANI channels using a verified, versioned engine semantic. Do not discard identity-valued channels merely because their values look harmless before that semantic is known.
5. Produce the ordered transform expression with joint variables left symbolic. Include the leaf direction basis when mapping a desired pointing direction to the required pose. Reduce to the existing O/P/D formula only after proving equivalence; otherwise report representation incompatibility.
6. Emit either an evaluable reference-state function with its proof dependencies, or a specific unresolved operation/state. No manually selected endpoint index and no family-specific copied vectors.
7. Validate parser/output determinism and compare the resulting function against the historical numerical corpus. Validate the production consumer against this independently specified function, not against a second copy of the same production algorithm.

For a general two-joint rigid chain, a compact form is `T0 · R(axis1, q1) · T1 · R(axis2, q2) · T2 · endpoint`. Static matrices can be precomposed. This is a proposed representation, not a claim that all 92 already reduce to that form or that scale/state can always be discarded. No full per-frame animation framework is warranted if the product only needs a verified deployed reference state. **[design-choice]**

### Complete equivalence versus a useful audit key

The complete equivalence relation is equality of the required function over its supported domain, with the same state/default/scene assumptions and desired-direction convention. A sufficient structural fingerprint would include:

- versioned engine semantics and reference-state contract;
- selected anchor semantics, connection identity/order evidence and relevant eligibility flags;
- ordered owning frames, numeric transforms and articulation placement/axes;
- animation-selector ownership/spans, relevant state transitions, defaults and complete interpreted channel functions;
- direction basis and any flags that change scene/part transform evaluation;
- all runtime arguments that remain variable, rather than hiding them in a macro label.

Alpha-renaming is safe only after proving that the renamed identifier is not used for hashing, state selection or engine role assignment. Exact source-file identity is a conservative sufficient link for sharing source interpretation, but different macro properties must still be checked for effects on the chosen state/function. **[design-choice / inference]**

The implemented research key retains hashed-order endpoint identities, all endpoint ancestry transforms, relevant connection attributes/tags/restrictions, state-selector owner positions and frame spans, descriptor durations/counts, and full raw key records. It normalizes connection/part graph labels and excludes macro names. It deliberately retains all captured states rather than claiming unused states can already be removed. It finds **83 keys**. This is a **candidate sufficient-input graph key**, not a certified complete runtime fingerprint: untraced scene flags, descriptor semantics and macro-driven state effects still limit that claim.

Adding selector spans changed 82 provisional keys to 83. Therefore the report does not disguise a partial key as proof of complete equivalence. Exact complete runtime-function class count remains **unknown**; 91 component identities are the conservative source-identity baseline. Once the general interpreter is proved, equivalent functions could be merged further, but that optimization is optional.

## 6. Retrospective validation

Existing LIVE results are an oracle with different strengths. A published residual is not equivalent to having its complete raw log and pose. The following table separates those cases.

| Exact macro(s) | Source prediction/control | Runtime result and residual | Semantic question; reanalysis status |
|---|---|---|---|
| `turret_par_m_laser_01_mk1_macro`, #83 B2 | additive X rotation versus replacement; endpoint 2 | published displacement error ~`7.4e-6 m`; replacement ~`0.693 m` vector error | Additive composition; fixed-offset sign remains invisible to displacement-only test |
| Same, #83 B4, nine poses | complete authored chain, ANI X negated, hash-selected `con_laser_02` | independently recomputed from published pose/position pairs: `3.387e-6..1.57158e-5 m` | Absolute sign/composition; no fitted constants. Original raw B4 log unavailable here |
| `turret_arg_m_beam_02_mk1_macro`; source-equivalent PAR/TEL M Beam 02, #128 | radian companion versus degree control, endpoint 2 | LEFT 6: median `.0083`, max `.013`; RIGHT 10: median `.0035`, max `.018`; degree ~`.53`; clean absolute `6.8e-6 m` | Radian interpretation in this signature. Correct hash-selected endpoint. Published source/runtime vectors checked; raw pose/log unavailable for independent complete replay |
| `turret_tel_l_laser_01_mk1_macro`; source-equivalent `turret_pir_l_battleship_01_laser_01_mk1_macro`, #132 | endpoint 2; additive/doubled scale control | recomputed source prediction `(-4.84789379,42.73788185,19.07721840)` versus `(-4.84789,42.7379,19.0772)`: `2.61248e-5 m`; doubled-scale `35.66834 m`; endpoint 1 ~`9.38525 m` | Reject doubled scale; does not distinguish unit scaling from ignoring scale. Uses published bore/mount data and forward-yaw fixture interpretation |
| `turret_spl_m_laser_02_mk1_macro`, #155 | hash-selected endpoint 2 versus endpoint 1 | 190 samples, `1.893e-6..2.6825e-5 m` transverse | Independently reproduced from archived raw log |
| `turret_spl_m_plasma_02_mk1_macro`, #155 | hash-selected endpoint 1 versus endpoint 2 | 20 samples, `.006376.. .011412 m` transverse versus ~`4.938 m` | Independently reproduced; adversarial endpoint test passes |
| `turret_spl_m_beam_02_mk1_macro`, #155 | hash-selected endpoint 2 versus endpoint 1 | 6 samples, `.011995.. .021682 m` transverse | Independently reproduced; endpoint discrimination passes, strict geometry gate remains failed |
| `turret_par_l_beam_01_mk1_macro`, #83/#75 | endpoint 2, target-bearing/bore and alternate-endpoint controls | historical nine-pose `.1324.. .3614 m`; #75 ~`.303 m` | Useful historical observations; strict acceptance revoked, not restored by this report |
| `turret_ter_l_beam_01_mk1_macro`, #135 | endpoint 2 versus endpoint 1 | historical ~`.0328 m` versus ~`3.98 m` | Endpoint-leading evidence, not strict geometry acceptance under the reopened contract |
| `turret_ter_m_beam_02_mk1_macro`, `turret_ter_m_laser_02_mk1_macro`, #155 | generated shortened composition | FIRED/HIT and ENGAGEABLE only | No strong quantitative geometry result to replay |
| Remaining #99/#102/#105/#125/#130/#151/#163 scope | generated/model parity, engagement/attribution or inherited rule | No additional independent strict exact-geometry measurement established by the inspected records | Do not manufacture a geometry PASS from behavior or CI |

The B4 calculation is recorded in [x4-b4-retrospective.json](x4-b4-retrospective.json); the #155 per-sample calculations are in [x4-retrospective.json](x4-retrospective.json). The evaluator uses source-resolved authored geometry and the existing bounded composition rules, with hash-selected endpoints. It is **not** a newly proved universal interpreter. It reproduces the strongest available numerical observations in their supported scope and explains the endpoint counterexample. It cannot honestly be described as retrospectively validating unknown general ANI semantics on all 92.

Perpendicular residuals remove recoil contamination along the chosen direction but also remove sensitivity to any model error along that direction. A fixed 20 mm transverse gate cannot certify a full point to 20 mm. Future evidence must state precisely which quantity was measured and which error directions remain unobserved. **[inference / design-choice]**

## 7. The complete 92-turret analysis

The [CSV](corpus.csv) supplies every exact macro, component, selected connection, hash, lexical index, endpoint count, graph fingerprint and existing composition status. The analysis is performed over the actual `COMBAT_CANDIDATE` classification, not a manually reconstructed macro list.

| Quantity | Measured result | Meaning |
|---|---:|---|
| Combat macros / component identities | 92 / 91 | Exact census scope |
| Official source files checked against catalogs | 274; 0 mismatches | Current cached macro/component/ANI inputs verified |
| Resolved endpoint ancestry and hash choice | 92 | Offline anchor selection under the traced rule |
| Endpoint hash collisions within a turret | 0 | No collision policy needed for this corpus |
| One / two / three / four / five / eight endpoints | 25 / 52 / 1 / 2 / 11 / 1 macros | Endpoint pairs are not a general invariant |
| Lexical selected endpoint 1 / 2 / 4 | 35 / 46 / 11 macros | Generator order differs from engine order |
| Existing bounded composition recognized | 37 | Does not mean 37 strict runtime geometry proofs |
| Outside existing bounded composition | 55 | Interpreter gaps, not missing source geometry |
| Conservative graph keys including selector spans | 83 | Candidate input equivalence, not certified full runtime equivalence |
| Certified complete runtime-function class count | Unknown | Do not advertise the graph-key count as this result |
| Active-path position / rotation / scale channels present | 85 / 60 / 42 macros | Channel presence, not materiality or engine interpretation |
| Active-path pre/post-scale channels present | 0 | No reason to implement those channels for the settled corpus now |
| Material non-unit active scale, exploratory `1e-5` threshold | 2 macros | ARG/TEL L Beam 01; small residues elsewhere are retained |
| Material Y/Z active rotation, same threshold | 14 macros | A shared general rotation question, not fourteen arbitrary new rules |
| Material direct-part translation, same threshold | 1 macro | Xenon M Gatling 02 |
| Unequal active position key triples | 2 macros | Boron L Laser 01 and Xenon L Laser 01 |
| No captured active ANI descriptors | 1 macro | Xenon XL Battleship 01; static/default path needs explicit treatment |

The `1e-5` feature threshold is an exploratory categorization only. It is **not** a proposed approximation tolerance or permission to erase source residues. Full stored values remain in the graph audit. **[design-choice]**

The two varying active records deserve different treatment. Boron L Laser 01 has position keys `(0,0,0)`, `(0,1.5,0)`, `(0,1.5,0)` on its relevant active part. Xenon L Laser 01 differs by about `9.536e-7 m` in an active Z key. Both prevent a literal claim of bit-exact phase invariance; their practical effects are very different. The former is a real 1.5 m state/time question. **[shipped-source values; inference about phase sensitivity]**

Equal first-three values alone do not prove constancy for an arbitrary cubic interpolation with independent handles. The KB's statement that every interpolation between equal endpoints is constant is too broad without validating interpolation/control fields. The oracle must prove constancy from the actual key function, or explicitly choose/evaluate the terminal reference state. Do not replace a per-macro LIVE requirement with an equally unjustified interpolation shortcut. **[inference: mathematical counterexample; engine interpolation remains qualified]**

The six multi-macro candidate graph groups are:

| Group | Exact macro members |
|---|---|
| Beam 02 | `turret_arg_m_beam_02_mk1_macro`, `turret_par_m_beam_02_mk1_macro`, `turret_tel_m_beam_02_mk1_macro` |
| M Gatling 02 A | `turret_arg_m_gatling_02_mk1_macro`, `turret_par_m_gatling_02_mk1_macro`, `turret_pir_m_battleship_01_gatling_02_mk1_macro`, `turret_tel_m_gatling_02_mk1_macro` |
| M Plasma 02 | `turret_par_m_plasma_02_mk1_macro`, `turret_tel_m_plasma_02_mk1_macro` |
| L Laser P6 | `turret_pir_l_battleship_01_laser_01_mk1_macro`, `turret_tel_l_laser_01_mk1_macro` |
| M Gatling 02 B | `turret_spl_m_gatling_02_mk1_macro`, `turret_ter_m_gatling_02_mk1_macro` |
| Xenon M 02 | `turret_xen_m_beam_02_mk1_macro`, `turret_xen_m_laser_02_mk1_macro` |

These groups save nine identities under this candidate graph comparison. They are useful differential checks. Only previously justified exact-sharing relationships should currently inherit accepted runtime proof; the other groups need completion of the fingerprint's semantic sufficiency argument.

**How many are fully resolved entirely offline?** Anchor identity: 92/92, conditional on the traced build-specific rule. A complete new universal reference-geometry oracle: **not established**. Existing source-resolved expressions: 37/92. Newly demonstrated independent complete-geometry proofs for the remaining 55: **zero**. This last number reports the actual research result, not that those 55 intrinsically need LIVE tests. There are no source-missing endpoint cases in the 92; the remaining blockers are semantic interpretation, state contract and production representation.

## 8. Minimum remaining LIVE work

No additional LIVE run is information-theoretically necessary to distinguish the known #155 endpoint models: the archived corpus plus static trace already distinguishes them. An endpoint-4 turret would be a valuable regression check of the general rule, but it is not a prerequisite imposed by missing per-macro information. **[inference / design-choice]**

A precise positive lower bound on remaining LIVE runs cannot be justified. Continued executable analysis could eliminate the remaining semantic uncertainty, making the lower bound **zero**. Nor is “three rules means three runs” valid: one run can measure many poses and turrets, while one poorly designed run can distinguish none. A certified minimum requires explicit competing models, their predicted observations and a measurement-noise model. Those are not yet complete for the whole animation/scene path.

The remaining questions can be organized into **five work packages**, rather than 55 or 92 turret tasks:

| Semantic package | Competing interpretations / discriminator | Source-selected candidate | Why it adds information |
|---|---|---|---|
| ANI rotation and articulation composition | Coordinate conversion, radian Euler composition, order relative to authored frames and joints | Split M Beam 01 asymmetric X pair; M Gatling 02 mixed XYZ profile | Existing ±35° and near-2π controls do not establish every noncommuting operation |
| Scale and scene transform path | Multiplicative scale versus ignored/stripped scale, and which translation/basis receives it | ARG L Beam 01 or TEL L Beam 01 | Unit-scale P6 cannot distinguish multiplication from ignoring a channel |
| Direct-part/default transform | Apply material part offset versus ignore/rebase it | `turret_xen_m_gatling_02_mk1_macro` | Authored `(0,-1,0)` part offset creates a ~1 m discriminator; float-noise offsets cannot |
| State/key evaluation | Hold terminal active value, interpolate, loop or inherit a prior/default value | Boron L Laser 01, with Xenon L Laser 01 as a precision audit | Actual unequal key values distinguish models that constant records cannot |
| Runtime observation and desired-pose contract | True joint/connection pose versus projectile/target-bearing proxy; scene-backed versus static fallback | An already strongly understood representative, plus static/no-ANI case only if needed | Removes observation ambiguity before interpreting residuals as geometry errors |

This is a work decomposition, not a claim that there are exactly five independent unknown scalar engine switches. General mathematical operations can resolve multiple packages; untraced conditional branches may add dependencies.

**Practical planning estimate [design-choice]:** after finishing the indicated static links, prepare one reusable automated observation fixture containing approximately **5–8 carefully selected representatives**, with multiple poses and timed state samples. One X4 session could collect those discriminator observations if the fixture/logging works on its first attempt. Budget a second session for a discovered instrumentation or model ambiguity. This is an engineering estimate, **not a proven minimum, acceptance guarantee, or instruction to launch now**.

Choose the final representatives mechanically:

1. Enumerate plausible remaining semantic models and generate their predicted position/direction curves for all 92.
2. Discard observations where models coincide or differ below the independently determined uncertainty.
3. Select observations covering the largest number of still-indistinguishable model pairs; solve the small set-cover problem exactly if useful.
4. Acquire all selected observations in one fixture/session; score each against predeclared predictions.
5. If every surviving model produces the same required quantity on the remaining corpus, the distinction is irrelevant to this product and needs no further experiment.

The lower-bound argument is then explicit: each unresolved pair must be separated by at least one observation or by authoritative static proof. Testing an arbitrary extra turret that separates no pair adds no semantic evidence.

### Better instrumentation before further geometry acceptance

Shipped `scriptproperties.xml` exposes componentslot `offset`, `rotation`, `relativeposition`, `relativerotation`, and static counterparts. This is a promising exact connection-pose route. However, a supported generic constructor/enumerator for arbitrary turret connections was **not established** in the searched schema/scripts. `create_position` does not have a generic `connection` attribute; do not invent one. The report therefore does not claim a ready-to-use exact-joint logger. **[shipped-source API fields; inference about availability]**

`common.xsd` exposes `aim_turret`, which is a useful lead for controlled aiming without using projectile creation as the only trigger. Its exact suitability for settled observation still needs verification. If no supported connection-pose access is found, automate settled position traces across known aiming states, retain raw data, and use the already reconstructed geometry to design observations that distinguish pose noise from model error. Do not use a noisy FIRED direction as ground-truth joint telemetry by declaration.

Recoil should be either modeled from the known firing state or excluded by an objectively observable non-firing state. Report full position error where measured. Use transverse projection only for a specifically transverse claim; pair it with an independent longitudinal observation if full anchor position is the acceptance target. Integration checks must record entry into the prospective branch so ordinary current-muzzle LOS cannot masquerade as a successful prospective test. **[design-choice]**

## 9. Comparison with the current strategy

| Dimension | Current #79 strategy | Proposed strategy |
|---|---|---|
| Unit of semantic proof | Distinct accepted geometry identity, frequently implemented as batches | Engine operation/state contract; exact source data are parameters |
| Endpoint discovery | Manual alternatives revealed during LIVE | Deterministic hash/filter rule for all 92; archived #155 already validates adversarial choice |
| Geometry equivalence | Hand-maintained signatures and narrow proof inheritance | Machine-generated graph key, promoted only after semantic sufficiency is established |
| Source coverage | 37 generated records on this branch, 55 still outside recognizers | All 92 endpoint choices audited now; general transform coverage remains explicit work |
| Effective current selection | 35 streamable; nine choose a different anchor under the trace | Explicit anchor identity; one/many endpoints handled by the same rule |
| Nominal macro-level evidence backlog | Up to 85 macro labels after crediting seven macros covered by the strongest representative/exact-sharing evidence in this review | No macro-by-macro geometry requirement demonstrated; operation proof plus targeted integration |
| Additional manual observations | Potentially dozens of identities and multiple poses each; no sound fixed launch count | Planning estimate 5–8 representative semantic experiments, mostly automated |
| Launches | Not inherently one per turret; actual process repeatedly requires owner-driven batches/reruns | Target one collection session, contingency second; theoretical minimum zero after sufficient static recovery |
| Proof artifacts | Per-batch fixture/acceptance records, repeated source checks, semantic-case expansion | One source/build manifest, deterministic corpus report, interpreter tests, small discriminator log corpus |
| Principal failure modes | Wrong endpoint index; circular parity tests; pose/recoil noise; broad acceptance from ENGAGEABLE | Wrong general interpretation or incomplete fingerprint; mitigated by executable linkage, adversarial corpus and fail-closed unknowns |

The seven credited macros are PAR M Laser 01; ARG/PAR/TEL M Beam 02; TEL/PIR L Laser P6; SPL M Laser 02. This is a comparison of existing evidence scope, not a blanket new acceptance decision. Exact graph equivalence alone saves only nine candidate identities. The radical improvement comes from not treating different numeric geometry as different engine semantics.

The current process has no measured fixed “launches per geometry” ratio, and one launch can host many observations. Therefore a claim such as “92 launches become three” would be fabricated. What can be quantified today is **92 endpoint determinations replaced by one recovered rule**, **274 source-file checks automated**, **nine current endpoint-selection discrepancies plus two absent payloads detected offline**, and a remaining semantic research agenda much smaller than the macro inventory.

## 10. Recommendation and proof contract

**HYBRID OFFLINE/LIVE.** The present requirement for fresh LIVE geometry proof of each distinct numeric geometry is stronger than the demonstrated uncertainty warrants. Replace that requirement with the following contract. **[design-choice]**

- A general engine interpretation needs an authoritative source/executable argument or a discriminating runtime corpus, with its exact scope recorded.
- Each macro needs deterministic source resolution and a machine-checkable record showing that all operations/state assumptions it uses are covered by that interpretation.
- Complete source-equivalent inputs can share proof; shared topology or `semantic_case` alone cannot.
- Production compilation/factorization needs offline equivalence verification against the interpreted function.
- A small runtime integration suite still checks instance identity, coordinate space, scene conditions and actual prospective-branch use.
- Unknown semantics remain fail-closed. An explicit unknown is preferable to a manually guessed endpoint or another macro-specific acceptance label.

**FULL OFFLINE is not yet justified**, because the animation/scene/joint data-flow reconstruction is incomplete and the dynamic/reference-state distinction is not yet a complete product contract. **KEEP CURRENT STRATEGY is also not justified**, because the most important hidden #155 fact has now been recovered offline, and there is no engine evidence that literal vector or angle changes create independent rules.

Fully offline *geometry support determination* is plausible: the engine's selection is static, ancestry and values are shipped, and the remaining transform path is accessible in the executable. Fully offline *live ENGAGEABLE status* is a different request and is not possible from static assets alone: actual targets, mount instances and collision state are runtime inputs. Nothing here proposes replacing the native LOS query with a hull-mesh simulator.

## 11. Smallest implementation plan — not implemented

1. **Finish and review the narrow semantic oracle.** Preserve the executable hash/trace and recover the remaining active transform/default/joint links. Do not build a broad reverse-engineering framework. Specify exactly whether the product predicts a settled non-recoiling anchor or an instantaneous emitter.
2. **Replace endpoint index policy at the generation boundary.** Generate explicit selected connection identity using the verified unsigned hash/tag rule. Have the consumer select that identity. Cover one, two and many endpoints through the same mechanism; include Plasma and a lexical-endpoint-4 adversarial test. No negative-X heuristic and no macro-name branch.
3. **Replace literal semantic-case guards incrementally with proved operations.** Keep only operations actually present in the 92 settled paths. No pre/post-scale implementation is currently needed. Compile to existing O/P/D only when mathematically valid; preserve a fail-closed result otherwise.
4. **Use one deterministic census artifact.** Emit source hashes, selected endpoint, expression/fingerprint and unresolved dependencies. Derive support counts from actual consumer eligibility rather than record count. Avoid a second hand-maintained acceptance inventory.
5. **Retain a small independent numerical corpus.** PAR M Laser absolute poses, Beam 02 unit discriminator, P6 scale control and Split Plasma endpoint counterexample are durable reusable regression evidence. Fix tests that merely duplicate the consumer or force endpoint 2. Do not add permanent snapshots of arbitrary experimental fixtures.
6. **Only then resolve residual semantic ambiguity at runtime.** Select discriminators from competing predictions, instrument once, retain one disabled reproducible fixture and raw correlated logs, and update #79's acceptance contract around the resulting general proof.

Per-batch fixtures, manually chosen endpoint indices, handwritten proof-inheritance lists and separate acceptance records for source-equivalent macros become unnecessary. Historical issue records remain provenance; they need not remain the execution mechanism for a source interpreter.

## Source inventory and research coverage

The parent and every directly referenced child/reopened issue were read with their available comments. The linked PR evidence and current draft #156 were inspected; additional historical implementation issues explain how generated geometry and consumer support became separate steps. No GitHub state was changed.

| Source | State/evidence relevant to this report |
|---|---|
| [#79](https://github.com/radlinsky/x4-gunnery-control/issues/79) | Open parent, 92-macro scope, strict refreshed proof policy |
| [#75](https://github.com/radlinsky/x4-gunnery-control/issues/75), [#83](https://github.com/radlinsky/x4-gunnery-control/issues/83), [#99](https://github.com/radlinsky/x4-gunnery-control/issues/99) | Reopened geometry validation; absolute/differential research and revoked Beam tolerance |
| [#102](https://github.com/radlinsky/x4-gunnery-control/issues/102), [#105](https://github.com/radlinsky/x4-gunnery-control/issues/105), [#125](https://github.com/radlinsky/x4-gunnery-control/issues/125) | Reopened coverage evidence; generated/model parity is not direct geometry proof |
| [#128](https://github.com/radlinsky/x4-gunnery-control/issues/128), [PR #129](https://github.com/radlinsky/x4-gunnery-control/pull/129) | Beam 02 radian discriminator, clean sample and bounded exact-sharing evidence |
| [#130](https://github.com/radlinsky/x4-gunnery-control/issues/130), [PR #131](https://github.com/radlinsky/x4-gunnery-control/pull/131) | Subsequent Laser 02 coverage, reopened proof requirements |
| [#132](https://github.com/radlinsky/x4-gunnery-control/issues/132), [PR #134](https://github.com/radlinsky/x4-gunnery-control/pull/134) | P6 scale discriminator and TEL/PIR relationship |
| [#135](https://github.com/radlinsky/x4-gunnery-control/issues/135), [PR #136](https://github.com/radlinsky/x4-gunnery-control/pull/136) | P8 historical measurement, reopened strict validation |
| [#137](https://github.com/radlinsky/x4-gunnery-control/issues/137) | Closed research map: 65 then-unsupported macros, corrected 16 B / 49 C, no D |
| [#151](https://github.com/radlinsky/x4-gunnery-control/issues/151), [PR #152](https://github.com/radlinsky/x4-gunnery-control/pull/152) | One/five-endpoint additions; reopened geometry proof |
| [#155](https://github.com/radlinsky/x4-gunnery-control/issues/155), [draft PR #156](https://github.com/radlinsky/x4-gunnery-control/pull/156) | Current branch, exact endpoint counterexample, retained failed Beam gate |
| [#163](https://github.com/radlinsky/x4-gunnery-control/issues/163), [PR #124](https://github.com/radlinsky/x4-gunnery-control/pull/124) | Catch-up proof for prior additions |
| [PR #126](https://github.com/radlinsky/x4-gunnery-control/pull/126), [PR #127](https://github.com/radlinsky/x4-gunnery-control/pull/127) | Earlier coverage/research context |
| [#73](https://github.com/radlinsky/x4-gunnery-control/issues/73), [#74](https://github.com/radlinsky/x4-gunnery-control/issues/74), [#96](https://github.com/radlinsky/x4-gunnery-control/issues/96), [#98](https://github.com/radlinsky/x4-gunnery-control/issues/98), [#101](https://github.com/radlinsky/x4-gunnery-control/issues/101), [#103](https://github.com/radlinsky/x4-gunnery-control/issues/103), [#104](https://github.com/radlinsky/x4-gunnery-control/issues/104) | Historical generation, consumer parity and source-arithmetic decisions |
| [Draft PR #162](https://github.com/radlinsky/x4-gunnery-control/pull/162) | Source-preflight efficiency work; useful complementary tooling, not muzzle-geometry proof |

Local authoritative integration sources: `docs/TURRET_ASSET_KINEMATICS.md`; `ui/gunnery_control.lua`; `ui/turret_muzzle_geometry.lua`; `md/x4_gunnery_control.xml`; `scripts/generate-turret-muzzle-geometry.py`; `scripts/census_pipeline.py`, `census_endpoint_paths.py`, `census_source_semantics.py`, `census_ani_parser.py`; Test Lab `md/x4_gunnery_control_testlab_observe.xml`; `tests/support/muzzle_geometry_eval.lua`; focused muzzle, generation, census and runtime-engageability tests; `tests/README.md`.

Focused knowledge base: `.agents/skills/research-x4-modding/references/` index, source policy/registry, tooling and the rank-2, Beam-02, P6, one-key-channel-0 and related turret records. Current official schema/scripts were kept in temporary external storage; exact combat source paths/hashes are listed in the manifest. Native trace helper addresses are pinned above rather than presented as public API names.

Public-source coverage: Egosoft's [Tags and flags](https://wiki.egosoft.com/X4%20Foundations%20Wiki/Modding%20Support/Assets%20Modding/Guides/Tags%20and%20flags/) and hosted [Making custom turrets](https://wiki.egosoft.com/X4%20Foundations%20Wiki/Modding%20Support/Assets%20Modding/Community%20Guides/Making%20custom%20turrets/) provide asset-authoring context, not the endpoint selection algorithm. The latter is a community guide, not authoritative engine source. Searches of official wiki/forum material did not locate a public specification of `barrelposition` selection. Current official Blender tooling was not available locally; the registered-download route was not accessible in this research. No private developer tooling or engine source availability is assumed.

## Knowledge-base corrections proposed with this report

The verified animation-state lookup was added to `references/md-ai.md` and linked in `references/index.md`, as required by the repository research instructions. No provisional executable semantic was promoted to the KB. Remaining proposed improvements are listed below:

- Completed: add `libraries/animation_sequences.xml` as the primary route for turret state-family questions before recommending LIVE discovery.
- Distinguish a `barrelposition` representative anchor from a cycling projectile emitter; preserve the traced rule as **inference**, executable-hash pinned, until reviewed.
- Replace the blanket equal-endpoints interpolation statement with a requirement to inspect key/control semantics.
- Record that exact connection-pose properties exist, but do not prescribe a generic slot construction API until one is actually established.
- Make research coverage reports distinguish generated records, streamable records, correctly selected anchors and accepted geometry evidence.

The report's conclusion does not depend on promoting any of these provisional findings to a durable global engine guarantee.

## Verification performed

The existing Lua turret-muzzle geometry tests and four endpoint-authored-geometry unit tests pass. The actual production derivation was exercised separately to demonstrate 37 generated versus 35 streamable records. The research audit verifies 92 unique CSV rows, 274 current source-file matches, collision-free per-turret endpoint hashes, and valid local report links. Skill validation and its focused contract test were run for the two research-reference updates. No full production validation or X4 runtime test was necessary for this documentation/research-only change.
