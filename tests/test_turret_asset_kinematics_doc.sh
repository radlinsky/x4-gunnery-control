#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

doc=docs/TURRET_ASSET_KINEMATICS.md
fail() { echo "FAIL: $1" >&2; exit 1; }

[[ -f "$doc" ]] || fail "$doc is missing"

# A1 owns the vocabulary for every layer used by later source and runtime work.
for term in \
  'turret component asset' \
  'equipment macro' \
  'geometry source' \
  'ANI file' \
  'ANI descriptor' \
  'geometry part' \
  'component connection' \
  'articulated joint' \
  'hull turret group' \
  'runtime turret instance' \
  'muzzle endpoint'; do
  grep -Fiq "$term" "$doc" || fail "canonical term is missing: $term"
done

grep -Fq '(part, subname)' "$doc" || fail 'ANI descriptor tuple is not explicit'
grep -Eq '^## .*Identity chain' "$doc" || fail 'identity-chain section is missing'
for identity_class in 'Source identity' 'Runtime identity' 'Descriptive/display label'; do
  grep -Fq "$identity_class" "$doc" || fail "identity class is missing: $identity_class"
done

grep -Fq 'X4: 9.00' "$doc" || fail 'X4 evidence version is missing'
grep -Fq 'Status: shipped-source' "$doc" || fail 'shipped-source classification is missing'
grep -Fq 'Live test: no' "$doc" || fail 'offline evidence boundary is missing'
grep -Fq 'Missing, orphaned, or ambiguous links fail closed.' "$doc" \
  || fail 'fail-closed identity rule is missing'
grep -Fq 'A1 establishes no ANI transform, axis-sign, frame, order, or active-pose semantics.' "$doc" \
  || fail 'A3 ANI-semantics boundary is missing'
grep -Fq 'catalog enumeration (not a derived filename)' "$doc" \
  || fail 'ANI resource example does not reject filename derivation'
for example_identity in \
  turret_par_l_beam_01_mk1_macro \
  turret_par_l_beam_01_mk1 \
  ship_par_l_destroyer_02_a_macro \
  ship_par_l_destroyer_02 \
  'PAR L Mass Driver Turret Mk1'; do
  grep -Fq "$example_identity" "$doc" \
    || fail "verified X4 9.00 example identity is missing: $example_identity"
done

# Agent workflows point at one canonical definition instead of cloning it, and
# each Markdown target resolves from the file that contains it.
for pointer in \
  AGENTS.md \
  .agents/skills/research-x4-modding/SKILL.md \
  .agents/skills/research-x4-modding/references/index.md \
  .agents/skills/spawn-gunnery-scenario/SKILL.md; do
  target=$(grep -oE '\([^)]*TURRET_ASSET_KINEMATICS\.md\)' "$pointer" | head -n 1 | tr -d '()')
  [[ -n "$target" ]] || fail "canonical document pointer is missing from $pointer"
  [[ -f "$(dirname "$pointer")/$target" ]] \
    || fail "canonical document pointer does not resolve from $pointer: $target"
done

# A1 is terminology/identity only, not the later census or transform proof.
if grep -Eiq '79.*(component|asset)|(component|asset).*79' "$doc"; then
  fail 'historical 79-asset count leaked into the A1 document'
fi

echo 'turret asset/kinematics document contract passed'
