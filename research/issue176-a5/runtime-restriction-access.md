# A5: can a normal mod read a turret's authored rotation restrictions? — 2026-09-18

Scope: [Issue #176](https://github.com/radlinsky/x4-gunnery-control/issues/176)
A5. Starting SHA `e3917b3`. X4 9.00 build 611726. Static research only. The
durable facts are in the reference
[`turret-aim-feasibility-surface.md`](../../.agents/skills/research-x4-modding/references/turret-aim-feasibility-surface.md),
in its last record.

## A. Routes that actually work

None.

## B. Plausible routes still missing one fact

None worth pursuing. The only open item is the unnamed hashed data-getter
keys: 31 in `GetMacroData` and 111 in `GetComponentData`. Static inspection
found no handler that reads connection restriction records or the internal
limit pair, so naming those keys cannot yield limits.

## C. Dead ends, so they are not repeated

- `componentslot` and `macroslot`: no restriction property, and no producer
  reaches a turret joint.
- `UIComponentSlot` and the connection-name FFI getters: no rotation or limit
  data.
- Upgrade and fitting FFI (`GetUpgradeGroupInfo`, `GetSlotCompatibilities`,
  `GetUpgradeSlotCurrentMacro`, and similar): mounted macro and compatibility
  tags only.
- `GetLibraryEntry` turret entries: `rotation` is rotation speed.
  `maxyawangle`/`maxpitchangle` belong to scanner software.
- The encyclopedia, ship-configuration and comparison UI never show turret
  arcs.
- The `macro` script datatype has no component or connection accessors.
- Undeclared exports: nothing structural.

## D. Final answer

1. **Can a normal X4 mod read an arbitrary turret's authored rotation
   restrictions at runtime?** No.
2. **Smallest usable route:** none exists.
3. **Only simple yaw/pitch limits available?** Not applicable. Even the
   engine's internal `Weapon::Defaults` pair would give only one yaw and one
   pitch range per macro. Reversed-XY, rotation-Z and bounded-traverse
   turrets, and any turret whose pivot offsets matter, would need full joint
   geometry beyond that.
4. **Exact blocker:** restriction records live on component connection
   objects, and in the lossy `Weapon::Defaults` copy. X4 exposes connections
   to scripts only through slot types and structs limited to name, tags,
   group, offset and rotation, and only for NPC, dock and control slots.
   Every loaded-data lookup (`GetMacroData`, `GetComponentData`,
   `GetLibraryEntry`, the upgrade APIs) omits restriction data. The only code
   that reads the limits is the no-argument player HUD export
   `IsPointingWithinAimingRange`.
5. **Any normal-mod route left to research?** No. With shot learning, native
   helpers, file parsing and prebuilt tables excluded, unknown turrets should
   return UNKNOWN for CANNOT BEAR.
