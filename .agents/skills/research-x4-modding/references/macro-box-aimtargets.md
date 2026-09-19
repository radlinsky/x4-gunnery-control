# Macro bounding boxes and authored aim targets

Use this focused route before repeating native box/aimtarget discovery.
The runtime box and an authored aim point are different metadata; do not
assume containment or replace the box with an all-parts union to obtain it.

## Build pin and recovered paths

- X4: 9.00 build 611726
- Status: inference
- Source: installed `X4.exe`, SHA-256
  `19750a6563889a970f434b5566eb396c6b2dc29ff814bd3e336f838176ad6891`,
  rechecked 2026-09-16; see [native-analysis.md](native-analysis.md).
- Live test: no — native interpretation, with bounded earlier LIVE
  corroboration described below.
- Finding: the script property path at RVA `0x00CE7BC4` reads the macro box
  at `+0x140`; `0x00CE7C38` reads its half-extents at `+0x150`. The initializer
  copies template `+0x250` to macro `+0x140` at `0x00A27AB8–0x00A27ADA`.
  Do not substitute the neighboring alternate/all-parts box slots.

Template assembly starts from its authored size/zero accumulator (copy at
`0x00888F00`). At `0x00888FE3–0x00889012`, eligible part flag `0x04000000`
gates union into template `+0x250`. Connection finalization at
`0x0088A04B–0x0088A0B4` clears that flag for `nocollision`,
`nocollision_jolt`, or `platformcollision`. Referenced source-connection tags
must be merged before eligibility. `0x014E1BD0` performs transformed box
union; macro child contribution uses the same helper at `0x00A27E9B`.
These analyst descriptions are not recovered public function names.

The independent nearest-authored-point selector at `0x005210E0` reads the
defaults collection at `+0x760`. Its loop at `0x00521140–0x0052117A` computes
binary32 squared distance to connection `+0x60` and keeps the nearer entry;
`0x00521181` returns that translation's address. There is no box read,
containment check, or clamp in this authored-point branch. The absent/empty
collection fallback is a different branch and is not characterized here.

The accepted caller trace is `create_orientation useaimtarget` through
`0x00BE1970 → 0x00C707A0 → 0x003EC190`; the call at `0x003EC313` reaches
the selector. Target-local origin and selected point are transformed by
`0x003DB8A0` on either side. The loader writes raw authored translation at
connection `+0x60`; parent-composed transforms use separate storage. For an
unparented aim connection, the raw translation and the macro/component box
are in the same component frame. Do not invent a parent transform for it.

## Bounded source structure check

- X4: 9.00
- Status: shipped-source
- Source: `assets/props/WeaponSystems/energy/turret_arg_m_beam_02_mk1.xml`;
  `ego_dlc_boron/assets/props/weaponsystems/boron/turret_bor_m_guided_01_mk1.xml`;
  `ego_dlc_terran/assets/props/weaponsystems/energy/turret_ter_m_beam_02_mk1.xml`;
  `ego_dlc_terran/assets/props/weaponsystems/energy/turret_ter_m_base_01.xml`;
  the corresponding macro component references.
- Live test: no — these representative box measurements remain pending as of
  2026-09-16.
- Finding: these assets author an unparented aim connection above their
  eligible socket geometry; upper turret parts carry `nocollision`. The
  Boron socket uses a connection translation and has a contained parented
  decal; the Terran socket inherits its size from an explicit part reference.
  Their eligible part offsets are identity. These source facts do not by
  themselves constitute runtime box measurements.

This gives a concrete, source-backed reason to question universal aim-point
containment. Native analysis supports independent box construction and raw
point selection, but runtime claims for new structural cases must retain the
measurement boundary. `PART_OFFSETS=False` matching earlier samples is not
a universal engine rule. First check whether nonidentity offsets actually
occur on eligible geometry; a toggle that affects only excluded parts cannot
explain an observed collision-filtered box discrepancy.

## Earlier LIVE boundary

- X4: 9.00 build 611726
- Status: live-tested
- Source: [accepted five-discriminator record](https://github.com/radlinsky/x4-gunnery-control/issues/167#issuecomment-5685758987),
  fixture `2dde8de8d8ad1d10331eb9a1065e601d8423e09b`.
- Live test: yes — previously accepted record, re-read 2026-09-16; no new
  runtime execution or promotion in this audit.
- Finding: the Teladi XL builder, Argon M frigate, Teladi M gatling, Argon L
  engine, and Teladi L container corroborated the stated transform convention,
  half-extents, origin inclusion, collision filtering, child contribution,
  and effective referenced-connection tag filtering. They did not measure
  every turret socket structure or prove universal aim-point containment.

For the bounded pending discriminator, predictions and source population see
[the research audit](../../../../research/issue167-p3c/outside-box-audit.md).
Keep experiment counts and task status there or in the owning issue, not in
this reference's technical index entry.
