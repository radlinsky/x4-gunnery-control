# Rank-2 Teladi `turret_active` channel-0 resolution (X4 9.00)

## Decision

The three Teladi members of the accepted seven-component rank-2 cohort do not
become ambiguous because of their additional rotator-base candidate-channel-0
input. Retain the exact stored vector as a local position translation inside
the already accepted rank-2 transform:

`(4.6193599700927734e-7, 8.195638656616211e-8, -2.7567148208618164e-7)`

This applies to the rank-2 source-semantic case only. It does not establish a
global rule for arbitrary candidate-channel-0 records.

## Evidence

- X4: 9.00
- Status: shipped-source
- Source: the three Teladi ANI/component resources recorded in
  `turret-rank2-channel0-records.md` and the rank-2 authored hierarchy recorded
  in `turret-rank2-settled-active-transform.md`.
- Live test: no — source/topology resolution only.
- Finding: all three Teladi rank-2 components store the same repeated
  rotator-base candidate-channel-0 vector above. The accepted rank-2 transform
  places candidate-channel-0 input on the child part's local-position layer.

- X4: 9.00
- Status: third-party-technique
- Source: pinned X4Converter commit
  `0be4b494089ba7719d4c5d351e63160ef3843ef5`.
- Live test: no.
- Finding: the first ANI key group is interpreted as position/location and is
  added to the animated part's starting local position.

- X4: 9.00 build 611726
- Status: live-tested
- Source: `paranid-l-beam-channel0-semantics.md`.
- Live test: yes — 2026-09-01.
- Finding: an independent X4 discriminator established candidate-channel-0
  translation use for the exact Paranid L Beam source path. This is evidence
  for the ANI field meaning, not permission to reuse that Beam's geometry or
  transform order on unrelated topologies.

## Bounded inference for the rank-2 cohort

Applying the independently corroborated channel-0 field meaning inside the
separately source-resolved rank-2 hierarchy is a bounded `inference`. The
rank-2 reference supplies the topology-specific composition, while the Beam
live result supplies independent corroboration that this ANI key group is a
translation input. No faction, macro, component, or part-name special case is
needed.

The stored Teladi vector is retained exactly; it is not rounded away. Its
Euclidean magnitude is `5.441474806222383e-7 m`. As a sanity bound only,
omitting a local translation of that magnitude could move the final muzzle
origin by at most the same amount because the downstream operations are rigid
rotations/translations. This is about 91,887 times smaller than B4's minimum
`0.05 m` position tolerance. The tolerance comparison is not the semantic
justification.

## Boundary

The Teladi M Beam, Pulse, and Plasma Mk1 members remain eligible for
`SOURCE_RESOLVED` classification with the other four rank-2 members. B4 still
must runtime-validate the final resolved topology set under its nine-pose
position contract. This note does not generalize candidate channel 0 outside
the exact rank-2 source-semantic case.