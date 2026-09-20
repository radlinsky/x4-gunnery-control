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

## Authored aim points across the whole ship corpus

- X4: 9.00; SWI 0.9.1 HF
- Status: inference, from `shipped-source` official XML and
  `third-party-technique` mod XML
- Source: every component behind a `ship_s`/`ship_m`/`ship_l`/`ship_xl` macro,
  censused as two independent games because SWI is an overhaul whose ships never
  share a game with vanilla's: pristine X4 9.00 (203 components, 285 macros, 39
  authored `aimtarget` connections, every runtime box resolving) and SWI
  0.9.1 HF's own ships (226 components, 257 macros, 795 connections, 223 boxes).
  A SWI census member is a component behind a ship-class macro defined in a SWI
  file; the vanilla definitions stay loaded as dependencies, since SWI ships
  attach vanilla docks, bridges and shields, but are not SWI-game ships.
  Parser and full analysis: `research/issue184/ship_aimpoint_census.py`.
- Live test: no — source census only; no runtime measurement.
- Finding: authored aim points are hand-placed constants with no derivation
  rule. Four properties hold with no counterexample in either game: the ordered
  point list is a property of the *component*, identical in every macro that
  uses it, while the reconstructed box varies by up to 25.2 m between a
  component's macros; no aim connection carries a `parent` attribute, so the
  authored offset is already the component-frame position; selection order is
  the native connection-name hash and differs from document order for most
  multi-point components; and every single-point ship places its point on
  `x = 0` (5 of 5 vanilla, 97 of 97 SWI).
  Nothing else generalizes, and the two games disagree about how close the
  near-rules come. A single point is neither the component origin (0 of 5
  vanilla, 47 of 97 SWI) nor the reconstructed box centre (0 of 5 vanilla, 18
  of 97 SWI). Lateral symmetry is authored exactly on 127 of 128 SWI multi-point
  components but on only 9 of 14 vanilla ones, 11 within 1 mm: two vanilla ships
  are mirrored to 0.3 mm in the authored text, and three are genuinely
  asymmetric.
  Eight points lie outside their own reconstructed runtime box, reaching a
  normalized |n| of 3.17 on x — corroborating at corpus scale that aim-point
  containment must not be assumed — though all eight are SWI-authored and
  vanilla has none. Pooling the two games inflates every one of these
  near-rules and must not be done.

**Most ships author no aim point at all.** 184 of the 203 `ship_s`–`ship_xl`
components in pristine 9.00 carry no `aimtarget` connection; only 19 do. For
those 184 the nearest-authored-point selector's absent/empty collection branch
decides, and that branch is not characterized above. Any work that treats
authored aim points as the general answer for vanilla ships is addressing 9% of
them. SWI is the mirror image: it authors points on 225 of its 226 ships, the
lone exception being `mandator`. Pooling the two games therefore misstates both,
and a count taken over the union of their source data is not a population at
all.

A narrower earlier count of 50 vanilla whole-ship aim-point components is the
same data under a different scope: it selects by the component's own `class`
attribute and includes 31 `ship_xs` drones, lasertowers and pods. Excluding
`ship_xs`, as the four supported ship classes do, leaves exactly the same 19.

SWI 0.9.1 HF is an overhaul, so its ships and vanilla ships never share a game
and corpus statistics must be read per population. Applying its 214 `<diff>`
files (443 `<remove>`, 932 `<replace>`, 5 `<add>`) changes the reconstructed
box, because those operations delete and retag connections that feed it, but
**no SWI diff anywhere modifies an `aimtarget` connection**: every SWI aim
point is authored in a full component definition. SWI also refers to some
official assets with different capitalisation than the official file uses, and
defines 41 names in two files each.

**Name-to-file resolution is the `index/` lookup, not a file scan.** X4 resolves
a component or macro name through `index/components.xml` and `index/macros.xml`
(base: catalog `08.cat`; an extension adds its own entries with
`<add sel="/index">`). When two files define the same name, the index entry
decides which one the engine uses; filesystem order, alphabetical order and
filename convention establish nothing. SWI 0.9.1 HF has 41 such duplicate
names, six of them ships whose aim-point sets differ between the two files, and
its index resolves every one of them to the primary asset file rather than to
the `backup/` or `*_data/` copy. Its ship and index XML is confined to `ext_01`:
`ext_02` carries only `md/`, `aiscripts/`, `libraries/` and `t/`, and its three
`subst_*` catalogs — which could otherwise replace base-game files outright —
contain no XML at all, only voice, UI `.xpl` and images. Any tool that indexes X4 XML by scanning
directories must consult these index files before claiming which definition is
effective.
