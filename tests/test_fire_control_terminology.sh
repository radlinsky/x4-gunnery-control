#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# T06 — Retired fire-control terminology regression audit.
# Scans tracked text files for retired canonical labels, service identifiers,
# and historical tokens. The mutable Test Lab scenario spec is intentionally
# outside this permanent contract: it is operator-authored live-test input.
#
# Uppercase physical masking / ordinary firing-solution prose is preserved;
# only the current canonical label surface is rejected.

fail() { echo "FAIL: $1" >&2; exit 1; }

MUTABLE_LIVE_INPUT="testlab/x4_gunnery_control_testlab/ui/scenario_spec.lua"

# ── forbidden sets ───────────────────────────────────────────────────────────
CANONICAL_LABELS=(
  "ON SOLUTION"
  "MASKED"
  "OUT OF ARC"
  "NO SOLUTION"
  "NO FIRE-CONTROL TRACK"
  "NO CONTACT"
  "FIRE INHIBITED"
)

IDENTIFIERS=(
  "SolutionService"
  "SolutionBegin"
  "SolutionMember"
  "SolutionTarget"
  "SolutionCommit"
  "solution_batch_"
  "X4GunneryControl.SolutionResult"
  "X4GunneryControl.SolutionBatchComplete"
  "x4gcs"
  "requestSolution"
  "requestSolutions"
  "solutionText"
  "solutionAudit"
  "scheduleSolutionRepaint"
  "onSolutionResult"
  "onSolutionBatchComplete"
  "solution_state"
  "event=solution_batch"
)

# Historical tokens that must appear only in their approved durable records.
HISTORICAL_TOKENS=(
  "issue-1-on-solution-"
  "[X4GC TEST SOLUTION]"
)

# ── allowlist (path → regex, matched after whitespace normalisation) ──────────
ALLOWLIST_PATHS=(
  ".agents/skills/research-x4-modding/references/testing-experiments.md|issue-1-on-solution-"
  "testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_observe.xml|\[X4GC TEST SOLUTION\]"
  "testlab/x4_gunnery_control_testlab/ui/testlab.lua|\[X4GC TEST SOLUTION\]"
  "tests/test_filter_gunnery_log.sh|\[X4GC TEST SOLUTION\]"
)

# ── helpers ──────────────────────────────────────────────────────────────────
normalize() { tr -s '[:space:]' ' '; }

is_allowlisted() {
  local path=$1 match=$2
  for entry in "${ALLOWLIST_PATHS[@]}"; do
    local allow_path="${entry%%|*}"
    local allow_re="${entry##*|}"
    if [[ "$path" == "$allow_path" ]] && grep -Eq "$allow_re" <<< "$match"; then
      return 0
    fi
  done
  return 1
}

# ── shared scanner ───────────────────────────────────────────────────────────
# scan_file <path> [content...]
#   When called with only a path: reads from the file (main-scan mode).
#   When called with path + content: checks the given text (self-check mode).
#   The mutable live scenario spec is skipped in either mode.
#   Returns 0 if the file/content passes, sets SCANNER_ERROR on failure.
SCANNER_ERROR=""
scan_file() {
  local file=$1
  shift

  [[ "$file" == "$MUTABLE_LIVE_INPUT" ]] && return 0

  local normalized
  if [[ $# -eq 0 ]]; then
    # Main-scan mode — only scan tracked text files.
    [[ "$file" == "tests/test_fire_control_terminology.sh" ]] && return 0
    [[ -f "$file" ]] || return 0
    grep -Iq . "$file" || return 0   # skip binary / empty files
    normalized=$(normalize < "$file")
  else
    # Self-check mode — content supplied explicitly.
    normalized=$(printf '%s' "$*" | normalize)
  fi

  for label in "${CANONICAL_LABELS[@]}" "${HISTORICAL_TOKENS[@]}"; do
    if grep -Fq "$label" <<< "$normalized"; then
      is_allowlisted "$file" "$label" \
        || { SCANNER_ERROR="uppercase label '$label' in $file"; return 1; }
    fi
  done

  for id in "${IDENTIFIERS[@]}"; do
    if grep -Fq "$id" <<< "$normalized"; then
      is_allowlisted "$file" "$id" \
        || { SCANNER_ERROR="retired identifier '$id' in $file"; return 1; }
    fi
  done

  return 0
}

# ── main scan ────────────────────────────────────────────────────────────────
errors=()
while IFS= read -r file; do
  if ! scan_file "$file"; then
    errors+=("$SCANNER_ERROR")
  fi
done < <(git ls-files)

if [[ ${#errors[@]} -gt 0 ]]; then
  echo "retired fire-control terminology found:" >&2
  for e in "${errors[@]}"; do echo "  $e" >&2; done
  exit 1
fi

echo "fire-control terminology audit passed"

# ── matcher self-checks ───────────────────────────────────────────────────────
# These prove the shared scanner catches what it should and allows what it must.
# Each test calls scan_file (the same function used by the repository loop) and
# asserts the expected pass/fail outcome. A failure here means the audit rules
# are broken even if the repo currently scans clean.

_tmpdir=$(mktemp -d)
trap 'rm -rf "$_tmpdir"' EXIT

# 1. Rejects multiline OUT OF ARC.
cat > "$_tmpdir/multiline.txt" <<'EOF'
The target is
OUT OF
ARC
EOF
scan_file "$_tmpdir/multiline.txt" && \
  fail "self-check: multiline OUT OF ARC should be rejected"

# 2. Rejects SolutionService.
cat > "$_tmpdir/identifier.txt" <<'EOF'
local svc = SolutionService.$nonce
EOF
scan_file "$_tmpdir/identifier.txt" && \
  fail "self-check: SolutionService should be rejected"

# 3. Allows genuine "firing solution".
cat > "$_tmpdir/firesol.txt" <<'EOF'
A turret with no firing solution on the target holds fire.
EOF
scan_file "$_tmpdir/firesol.txt" || \
  fail "self-check: 'firing solution' should be allowed"

# 4. Allows lowercase "masked".
cat > "$_tmpdir/lowercase.txt" <<'EOF'
The shot path is masked by own-hull obstruction.
EOF
scan_file "$_tmpdir/lowercase.txt" || \
  fail "self-check: lowercase 'masked' should be allowed"

# 5. Rejects issue-1-on-solution-* at a wrong logical path.
cat > "$_tmpdir/wrong-path.txt" <<'EOF'
Historical experiment issue-1-on-solution-masked-clear-r1 ran on 2026-08-11.
EOF
scan_file "$_tmpdir/wrong-path.txt" && \
  fail "self-check: issue-1-on-solution-* must NOT be allowed outside its approved file"

# 6. Allows it at its approved logical path.
scan_file ".agents/skills/research-x4-modding/references/testing-experiments.md" "issue-1-on-solution-" \
  || fail "self-check: issue-1-on-solution-* MUST be allowed in testing-experiments.md"

# 7. Rejects [X4GC TEST SOLUTION] at a wrong path and allows its approved path.
scan_file "some/other/file.xml" "[X4GC TEST SOLUTION]" && \
  fail "self-check: [X4GC TEST SOLUTION] must NOT be allowed outside observe.xml"
scan_file "testlab/x4_gunnery_control_testlab/md/x4_gunnery_control_testlab_observe.xml" "[X4GC TEST SOLUTION]" \
  || fail "self-check: [X4GC TEST SOLUTION] MUST be allowed in observe.xml"

# 8. The mutable live scenario is not a permanent terminology contract.
scan_file "$MUTABLE_LIVE_INPUT" "ON SOLUTION SolutionService issue-1-on-solution-live" \
  || fail "self-check: mutable live scenario input must be excluded from the terminology audit"

echo "fire-control terminology matcher self-checks passed"
