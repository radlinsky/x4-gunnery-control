# X4 evidence index

Use this index to find concise, dated evidence. Re-check the installed build
before relying on any claim.

| Topic | Reference | Current evidence |
|---|---|---|
| Turret asset, mounting, and runtime identity terminology | [TURRET_ASSET_KINEMATICS.md](../../../../docs/TURRET_ASSET_KINEMATICS.md) | Canonical identity layers and X4 9.00 illustrative chain |
| Source hierarchy and classification | [source-policy.md](source-policy.md) | Rules and claim record shape |
| External and local source routes | [source-registry.md](source-registry.md) | Official wiki/forums, installed sources, public mods, and community leads |
| UI, menu, camera, targeting | [ui-lua-menu-camera.md](ui-lua-menu-camera.md) | X4 9.00 shipped-source findings |
| MD, AI, and XSD | [md-ai.md](md-ai.md) | X4 9.00 lookup and combat findings |
| Catalog tool | [tooling.md](tooling.md) | Verified XRCatTool v1.11 interface and limits |
| Debug logging | [debug-logging.md](debug-logging.md) | X4 9.00 `-logfile` argument form and log location |
| Ware `<use>` entries and purpose restriction | [x4-ware-use-semantics.md](x4-ware-use-semantics.md) | X4 9.00 shipped-source ware `<use>` corpus; COMBAT_RULE_SUPPORTED for multi-entry wares with no `purposes` |
| Turret macros with no equipment ware | [turret-no-ware-macros.md](turret-no-ware-macros.md) | X4 9.00 shipped-source COMBAT_CANDIDATE evidence for `turret_xen_l_laser_01_mk1_scenario_macro` |
| Combat topology group priorities | [turret-topology-priorities.md](turret-topology-priorities.md) | X4 9.00 shipped-source inventory of the 38 COMBAT_CANDIDATE endpoint-topology groups (92 macros, 91 components) in schema-25 census order |
| Rank-1 turret `turret_active` descriptor profiles | [turret-rank1-animation-profile.md](turret-rank1-animation-profile.md) | X4 9.00 shipped-source record of all 20 rank-1 components' muzzle-path `turret_active` descriptors with same-name selector coverage: 9 distinct profiles |
| Rank-2 turret candidate-channel-0 records | [turret-rank2-channel0-records.md](turret-rank2-channel0-records.md) | X4 9.00 shipped-source record for the seven depth-5 components; active path channel-0 first-three values are constant within each stored pair |
| Rank-2 turret candidate-channel-1 `part_arm` records | [turret-rank2-channel1-part-arm-records.md](turret-rank2-channel1-part-arm-records.md) | X4 9.00 shipped-source bytes for the seven components' active `part_arm` record pairs; no runtime semantic assigned |
| Rank-2 turret candidate-channel-1 rotator-base records | [turret-rank2-channel1-rotator-base-records.md](turret-rank2-channel1-rotator-base-records.md) | X4 9.00 shipped-source bytes for the seven components' active rotator-base record pairs; no runtime semantic assigned |
| Rank-2 settled `turret_active` transform | [turret-rank2-settled-active-transform.md](turret-rank2-settled-active-transform.md) | X4 9.00 accepted ANI `(-x, y, z)` conversion and additive local-X ±35° rule for the seven depth-5 components; exact Paranid M laser representative passed corrected nine-pose absolute-position validation at approximately 3.3e-6..1.57e-5 m without a fitted runtime constant |
| Rank-2 Teladi candidate-channel-0 resolution | [turret-rank2-teladi-channel0-resolution.md](turret-rank2-teladi-channel0-resolution.md) | X4 9.00 bounded resolution for the three Teladi rank-2 members: retain the exact rotator-base channel-0 vector as local-position translation; no Teladi-specific semantic split |
| Paranid L Beam candidate-channel-0 semantics | [paranid-l-beam-channel0-semantics.md](paranid-l-beam-channel0-semantics.md) | X4 9.00 translation semantic live-tested for the exact Beam path; current production `D` omits the accepted descriptor-22 `anim_barrel` channel-0 Y contribution, with production correction tracked separately |
| Paranid L Beam mount geometry | [paranid-l-beam-mount-geometry.md](paranid-l-beam-mount-geometry.md) | X4 9.00 shipped-source ventral-rear centerline mount geometry used to diagnose the invalid forward/above live fixture |
| Live tests and observations | [testing-experiments.md](testing-experiments.md) | Historical experiment archive and regression matrix |

Search these references before adding a record. Keep one primary source per
claim and add a second only when it materially corroborates the finding.
