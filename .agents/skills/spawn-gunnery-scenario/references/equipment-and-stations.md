# X4 equipment and station fixtures

Read this only when a Test Lab fixture needs a sparse or unusual game loadout,
exact surface identity, or a spawned station.

## Asset identity

Use [../../../../docs/TURRET_ASSET_KINEMATICS.md](../../../../docs/TURRET_ASSET_KINEMATICS.md)
for the distinction between an X4 equipment macro, component asset, hull
connection or group, runtime instance, endpoint, and player-visible label.

Resolve unfamiliar macros and connection semantics from the current installed X4
sources through `research-x4-modding`; do not infer them from display names or
faction prefixes.

For deterministic turret equipment, prefer group-targeted loadout entries such
as `<turrets macro="..." group="..." exact="N"/>`. Do not use a singular turret
path to isolate one slot unless current X4 source or live evidence proves that
path form for the exact asset.

A group-targeted entry can equip every slot in the group. Verify the group's slot
count and required tags before the run. If a multi-slot group cannot be reduced
to one member, distinguish members through correlated per-instance test evidence
rather than inventing unsupported per-slot fixture behavior.

READY must verify exact operational counts and the required equipment-macro
multiset. A count alone cannot distinguish the right number of the wrong game
asset. Keep ordinary and missile turret groups in HOLD FIRE until the intended
post-setup activation when the fixture requires an isolated shooter.

Internal connection/group ids are not operator labels. Any surface the owner
must click needs one unique visible macro/label or another proven exact marker.

## Stations

A created station root, visible shell, or expected module count is not enough to
claim an equipped station fixture. Withhold READY until the live census proves
the required operational modules and relevant game equipment.

Apply station equipment to the intended operational station module, not the
station root. Verify the module's exact macro before applying a loadout.

For an exact deterministic set, build a loadout whose group/path form matches the
module's actual connection semantics and apply it to that module. For a generated
faction loadout, generate and apply it per operational module using the current
shipped-source pattern. In either case, the final exact census is the readiness
gate; creation success is not.

If timing is itself under test, keep immediate, delayed, and final censuses as
separate evidence. Otherwise do not add timing probes or delays merely because a
past fixture once needed them.
