# Ware `<use>` entry semantics (X4 9.00)

Research question (Issue #72 A3): whether multiple direct `<use>` elements on a
ware with different `factions`/`threshold` values but no `purposes` restriction
have a source-supported interpretation under which the ware satisfies the
Issue #72 no-authored-purposes-restriction combat rule. Applied to four turret
wares currently UNRESOLVED as `MULTIPLE_DIRECT_USE_ELEMENTS`:
`turret_xen_l_laser_01_mk1`, `turret_xen_l_plasma_01_mk1`,
`turret_xen_m_gatling_01_mk1`, `turret_xen_m_gatling_02_mk1`.

All corpus facts below were enumerated from `libraries/wares.xml` in the eight
shipped X4 9.00 catalogs (`base` plus seven DLC catalogs, 7,529 ware records),
extracted to the ignored `.x4-research-cache/issue72-a2-sources/`.

## Evidence

### Ware `<use>` attribute vocabulary is exactly {threshold, factions, purposes}
- X4: 9.00
- Status: shipped-source
- Source: `libraries/wares.xml`, all 8 shipped catalogs
- Live test: no — untested as of 2026-08-31
- Finding: Across all 591 direct `<use>` elements the only attribute names
  ever authored are `threshold` (591 elements), `factions` (73), and
  `purposes` (29). `purposes` appears only on `<use>` elements, nowhere else
  in the ware files. The only `purposes` token values in the entire corpus are
  `mine` (28 entries) and `salvage` (1 entry) — both non-combat utility
  purposes. No `combat` or other purpose token exists. `threshold` is numeric
  with a 13-value set (`0`, `0.1`, `0.31`, `0.34`, `0.36`, `0.4`, `0.41`,
  `0.49`, `0.5`, `0.53`, `0.7`, `0.71`, `0.91`); its exact semantics are not
  established by shipped source and it is orthogonal to the purposes axis.

### Direct `<use>` entry counts and combinations
- X4: 9.00
- Status: shipped-source
- Source: `libraries/wares.xml`, all 8 shipped catalogs
- Live test: no — untested as of 2026-08-31
- Finding: 6,954 wares carry zero direct `<use>` elements (fully default),
  559 carry exactly one, and 16 carry exactly two. Per-entry attribute
  combinations observed: single entry with `threshold` only (491); single entry
  with `factions`+`threshold` (40); single entry with `purposes`+`threshold`
  (27); two entries each with `factions`+`threshold` (15); one single-entry
  ware with all three attributes; one two-entry ware combining all three. No
  ware has more than two direct `<use>` elements.

### Multiple direct `<use>` elements each carry one named faction
- X4: 9.00
- Status: shipped-source
- Source: `libraries/wares.xml`, all 8 shipped catalogs
- Live test: no — untested as of 2026-08-31
- Finding: All 16 multi-entry wares are equipment wares whose entries each
  name exactly one faction (observed values: `xenon` in 16 entries, `player`
  in 16): 14 wares differ only in `factions`, 1 shield differs in
  `factions` and `threshold` (`0.4` vs `0`), and 1 weapon differs in
  `factions` and `purposes`. The dual-entry shape recurs verbatim across
  unrelated equipment groups (engines, shields, weapons, turrets), e.g. an
  engine ware authored as
  `<use threshold="0" factions="xenon" /><use threshold="0" factions="player"
  />` — consistent with per-faction access entries (bounded interpretation;
  engine-side semantics are not demonstrated, see Limitations). No
  multi-entry ware expresses a purpose restriction other than through an
  entry's own `purposes` attribute.

### The one multi-entry ware with `purposes` carries it on exactly one entry
- X4: 9.00
- Status: shipped-source
- Source: `libraries/wares.xml` (base catalog), ware `weapon_xen_m_mining_02_mk1`
- Live test: no — untested as of 2026-08-31
- Finding: The sole ware combining multiple entries with `purposes` is the
  Xenon mining laser, authored as
  `<use threshold="0" purposes="mine" factions="xenon" /><use threshold="0"
  factions="player" />` — the `purposes` attribute is written on exactly one
  of the two entries, while the other entry is left without it, matching the
  unrestricted single-entry pattern used by the other non-utility wares.
  Within the Issue #72 rule framing, the entry-level placement is consistent
  with the restriction applying to the faction named by that entry (bounded
  interpretation), and the bare `<use threshold="0" factions="player" />`
  entry is attribute-for-attribute the same entry shape carried by the four
  turret wares under review.

### Single-entry faction-restricted turret wares are accepted combat candidates
- X4: 9.00
- Status: shipped-source
- Source: `libraries/wares.xml`, all 8 shipped catalogs; project A2 census
  output `.x4-research-cache/issue72-eligibility-failclosed-census.json`
  (offline reconciliation at commit `d397cfc`)
- Live test: no — untested as of 2026-08-31
- Finding: Six turret wares carry a single `<use threshold="0"
  factions="…"/>` entry with no `purposes` (`turret_kha_l_beam_01_mk1`,
  `turret_kha_m_beam_01_mk1`, `turret_xen_m_beam_02_mk1`,
  `turret_xen_m_laser_01_mk1`, `turret_xen_m_laser_02_mk1`,
  `turret_xen_xl_battleship_01_mk1`); the project's A2 fail-closed census, a
  reconciliation over this same shipped corpus, classifies all six as
  COMBAT_CANDIDATE. The four dual-entry turrets are structurally identical to
  these apart from the additional faction entry, and no shipped ware anywhere
  uses an additional `<use>` entry to add a purpose restriction that an entry's
  own `purposes` attribute does not already state.

### General rule supported by the corpus
- X4: 9.00
- Status: shipped-source
- Note: corpus-enumeration generalization, not a normative engine
  specification (see Limitations)
- Source: `libraries/wares.xml`, all 8 shipped catalogs
- Live test: no — untested as of 2026-08-31
- Finding: Two directions. First — every authored purposes restriction in the
  corpus is expressed by a `purposes` attribute on a direct `<use>` entry
  (guaranteed by exhaustive enumeration: `purposes` appears nowhere else). The
  29 such entries are the corpus's complete set of expressed restrictions. A
  ware therefore has an authored purposes restriction only if at least one of
  its direct `<use>` elements carries the attribute. Second — an entry lacking
  the attribute expresses no purpose restriction; this holds in the hundreds
  of single-entry examples (plus the 6,954 wares with no `<use>` element at
  all) and in the multi-entry subset alike, so multiple entries do not change
  what the absence of `purposes` means. For any ware whose entries carry no
  `purposes` attribute, the two plausible readings of multi-entry structure —
  independent per-faction entries, or a flat union — converge on the same
  result: no authored purposes restriction.

## Conclusion

**COMBAT_RULE_SUPPORTED.** The exact authored structure of the four wares (all
four identical in shape):

```xml
<use threshold="0" factions="xenon" />
<use threshold="0" factions="player" />
```

No entry carries a `purposes` attribute, so under the corpus-supported rule no
authored purposes restriction exists on any entry. These four wares satisfy
the Issue #72 no-authored-purposes-restriction combat rule, and the general
classifier rule is: *a conventional turret ware with multiple direct `<use>`
entries satisfies the combat rule when none of those entries carries a
`purposes` attribute.* The classification is attribute-based; no ware name,
display name, or faction identity was used in the rule.

## Limitations

- Corpus-enumeration evidence, not a normative engine specification: no ware
  XSD is shipped, so the attribute semantics are established by enumerating all
  8 shipped catalogs, not by a schema or in-engine documentation.
- Engine-side consumption of multi-`<use>` wares at runtime is not verifiable
  offline; this finding is about the authored structure and its supported
  interpretation, not a live-test claim about engine behavior.
- The multi-entry pattern is observed only on equipment wares granting access
  to two named factions (observed values include `xenon` and `player`); the
  rule is stated over attributes, but other entry configurations (more than
  two entries, other faction sets) do not occur in the X4 9.00 corpus and are
  not covered.
- `threshold` semantics (13-value set from `0` to `0.91`, see record above)
  remain unestablished by shipped source; the conclusion does not depend on
  them.
- Wares mixing a `purposes`-bearing entry with an unrestricted one (the mining
  laser pattern) remain faction-specific and are outside this finding; no such
  turret ware exists in the corpus.
