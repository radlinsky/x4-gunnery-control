# Paranid L Beam candidate-channel-0 semantics (X4 9.00)

**CHANNEL 0 POSITION SEMANTIC: UNPROVEN**

Candidate channel 0 is the first of the five ordered ANI key-record groups in
this project's structural vocabulary. The available X4Converter interpretation
calls it position/location, but no checked evidence independent of X4Converter
establishes that meaning for the exact Paranid L Beam records.

## Scope and raw shipped facts

- Repository starting SHA: `237be7a5a66b9bc4ebe99237c379e68e5297cbcb`.
- Installed X4: 9.00 (`version.dat` value `900`).
- Exact resource:
  `assets/props/WeaponSystems/energy/TURRET_PAR_L_BEAM_01_MK1_DATA.ANI`.
- Exact `turret_active` descriptors checked:
  - index 12, `(part_rotator, turret_active)`: `[2, 0, 0, 0, 0]`
  - index 22, `(anim_barrel, turret_active)`: `[2, 0, 0, 0, 0]`
- The ANI header/table and 128-byte record framing close exactly at the file
  end: 25 descriptors, key-data offset 4016, 24 records, file size 7088 bytes.
- Under the existing candidate-channel framing, descriptor 12's two channel-0
  records have leading triples `(0, 6.145042419433594, 0)` and descriptor 22's
  have `(0, -0.23982000350952148, 27.710205078125)`. Each descriptor repeats
  its triple in both records. Numeric triples and their ordering do not by
  themselves distinguish position from another vector semantic.
- The component XML names the two parts, hierarchy, selector, restrictions,
  and connection offsets, but does not name any ANI binary channel or bind the
  first key-record group to translation. No `NumPosKeys`, `posKeys`,
  `rotation_euler`, or equivalent ANI-layout documentation was found in the
  checked X4 9.00 extracted game source/data.

These identities, counts, bytes, and framing are `shipped-source`. Calling the
first group candidate channel 0 assigns no transform meaning.

## X4Converter semantic lead

Pinned X4Converter commit
`0be4b494089ba7719d4c5d351e63160ef3843ef5` claims that the first count and
record block represent position:

- `X4ConverterTools/include/X4ConverterTools/ani/AnimDesc.h` names the first
  count/vector `NumPosKeys` and `posKeys`.
- `X4ConverterTools/src/ani/AnimDesc.cpp:21` reads `NumPosKeys` first;
  lines 90–92 read the first records into `posKeys`.
- The same file labels those records `Position Keyframes` at lines 214–217 and
  maps `posKeys` to intermediate-output key type `location` at lines 277 and
  290–291.

This confirms exactly what X4Converter claims, not what X4 itself guarantees.
Classification: `third-party-technique`. The accepted Issue #72 checkpoint at
`c02360fa7d26608f72b7f8ce615455823bb4dbb3` was reused; no broad converter
reverse engineering was repeated.

## Independent corroboration checked

### Current shipped data

- X4 9.00 ANI and component data named above were checked directly.
- The shipped structural invariant proves record size and exact file closure,
  but does not discriminate semantic channel order.
- The two exact descriptors' leading triples are compatible with positional
  values, but compatibility is not semantic proof. No matching shipped label,
  schema, Lua/MD declaration, or documented binary-field name was found.

Result: `shipped-source` facts, but no independent channel-0 semantic evidence.

### Official Egosoft documentation

Checked 2026-09-01:

- [X4 Modding Support hub](https://wiki.egosoft.com/X4%20Foundations%20Wiki/Modding%20Support/)
  lists animation tooling but does not specify the binary ANI descriptor layout
  or identify the first key-record block as position.
- [Egosoft X4 bonus downloads](https://www.egosoft.com/download/x4/bonus_en.php)
  identifies Blender Mod Tools 0.7.0 for X4 9.00+, but the download and included
  `readme.txt` require a registered game/forum account and were unavailable to
  this investigation. The public page contains no binary channel semantics.

Result: no `documented-public` corroboration found. Absence from the checked
pages is an `inference`, not a guarantee that Egosoft has never documented it.

### Other public evidence

- The Egosoft-forum community guide
  [Restoring Animations](https://forum.egosoft.com/viewtopic.php?t=474546)
  describes Blender keyframes and `.ani` export, but explicitly requires
  X4Converter and uses its `.anixml` output; it is derivative and cannot
  independently corroborate X4Converter's channel naming.
- Targeted searches of the official wiki, Egosoft forums, public repositories,
  and X2/X3/X4 ANI-format terms found no separate implementation or format
  specification that specifically maps the first X4 ANI block to translation.
- A search result for `xypwn/filediver` was rejected: that repository is an
  unofficial Helldivers 2 Stingray extractor, not an Egosoft X4 ANI parser.

Result: no independently useful semantic corroboration found.

## Conclusion and proof boundary

**CHANNEL 0 POSITION SEMANTIC: UNPROVEN.** X4Converter consistently interprets
candidate channel 0 as position/location, and the exact shipped records do not
contradict that interpretation, but neither fact independently proves it.

Evidence still needed is one of:

1. an accessible Egosoft format statement, exporter source/readme, or other
   official artifact that explicitly identifies the first count/record block
   as translation; or
2. an independently implemented and provenance-checked parser, or a controlled
   translation-only authoring/export experiment, that discriminates the first
   block from competing vector meanings without relying on X4Converter names.

No claim is made about coordinate frame, units, axis convention, interpolation,
timing, pivot, transform order/composition, or runtime propagation. No live X4
test was performed.

## Evidence records

### Exact stored descriptor facts

- X4: 9.00
- Status: shipped-source
- Source: `assets/props/WeaponSystems/energy/TURRET_PAR_L_BEAM_01_MK1_DATA.ANI`;
  `assets/props/WeaponSystems/energy/turret_par_l_beam_01_mk1.xml`
- Live test: no — offline source verification only, 2026-09-01
- Finding: descriptors 12 and 22 are the exact named `turret_active` records
  with `[2, 0, 0, 0, 0]`; their bytes and structural framing do not name the
  first group as position.

### Candidate-channel-0 position interpretation

- X4: 9.00
- Status: third-party-technique
- Source: X4Converter commit
  `0be4b494089ba7719d4c5d351e63160ef3843ef5`, `AnimDesc.h` and
  `AnimDesc.cpp`
- Live test: no — offline source verification only, 2026-09-01
- Finding: X4Converter calls the first count/vector `NumPosKeys`/`posKeys`,
  labels its records position keyframes, and exports them as `location`; no
  checked independent evidence promotes that interpretation to an X4 semantic
  conclusion.
