#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v lua5.1 >/dev/null || ! command -v luac5.1 >/dev/null; then
  echo "warning: Lua 5.1 runtime/compiler unavailable; skipped executable-line coverage" >&2
  exit 0
fi

if [[ -n "${X4GC_DIFF_BASE:-}" ]]; then
  coverage_base=$X4GC_DIFF_BASE
elif git rev-parse --verify -q develop >/dev/null; then
  coverage_base=$(git merge-base develop HEAD)
elif git rev-parse --verify -q origin/develop >/dev/null; then
  coverage_base=$(git merge-base origin/develop HEAD)
else
  echo "warning: cannot find develop; skipped changed ui/gunnery_control.lua coverage" >&2
  coverage_base=""
fi

coverage_dir=$(mktemp -d)
trap 'rm -rf "$coverage_dir"' EXIT
coverage_hits=$coverage_dir/hits
: >"$coverage_hits"
targets=(ui/gunnery_state.lua ui/gunnery_persistence.lua ui/gunnery_control.lua)
# Globs so a split file (test_gunnery_state_surface.lua, test_runtime_targeting_pov.lua)
# is picked up automatically and keeps contributing its covered lines.
tests=(tests/test_gunnery_state*.lua tests/test_gunnery_persistence.lua tests/test_runtime_*.lua)
# The coverage runner uses an instruction-level debug hook, so this is the slowest
# part of validation. The tests are independent processes, so run them concurrently;
# each writes its own hits file so parallel appends cannot corrupt a shared one.
pids=()
for test_file in "${tests[@]}"; do
  lua5.1 tests/support/coverage_runner.lua "$coverage_dir/hits.$(basename "$test_file")" "${targets[@]}" -- "$test_file" >/dev/null &
  pids+=("$!")
done
coverage_failed=0
for pid in "${pids[@]}"; do wait "$pid" || coverage_failed=1; done
if [[ "$coverage_failed" -ne 0 ]]; then echo "a coverage test process failed" >&2; exit 1; fi
cat "$coverage_dir"/hits.* >"$coverage_hits"
sort -u "$coverage_hits" -o "$coverage_hits"

executable_lines() {
  ./scripts/coverage-executable-lines.sh "$1"
}

covered_lines() {
  local file=$1
  sed -n 's#^'"$file"':\([0-9][0-9]*\)$#\1#p' "$coverage_hits" | sort -u
}

require_covered() {
  local file=$1 expected=$coverage_dir/expected actual=$coverage_dir/actual missing=$coverage_dir/missing
  executable_lines "$file" >"$expected"
  covered_lines "$file" >"$actual"
  comm -23 "$expected" "$actual" >"$missing"
  if [[ -s "$missing" ]]; then
    echo "coverage missing executable lines in $file: $(paste -sd, "$missing")" >&2
    return 1
  fi
}

require_covered ui/gunnery_state.lua
require_covered ui/gunnery_persistence.lua

if [[ -n "$coverage_base" ]]; then
  control_expected=$coverage_dir/control-executable
  control_added=$coverage_dir/control-added
  control_required=$coverage_dir/control-required
  control_actual=$coverage_dir/control-actual
  control_excluded=$coverage_dir/control-excluded
  control_missing=$coverage_dir/control-missing
  executable_lines ui/gunnery_control.lua >"$control_expected"
  git diff --unified=0 "$coverage_base" -- ui/gunnery_control.lua \
    | sed -n 's/^@@ -[^+]*+\([0-9][0-9]*\)\(,\([0-9][0-9]*\)\)\? @@.*/\1 \3/p' \
    | awk '{ count = ($2 == "" ? 1 : $2); for (line = $1; line < $1 + count; line++) print line }' \
    | sort -u >"$control_added"
  comm -12 "$control_expected" "$control_added" >"$control_required"
  # An exclusion is deliberately line-specific. It must name a required line
  # and give a reason, so a refactor cannot leave an unreviewed broad waiver.
  awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    /^ui\/gunnery_control\.lua:[0-9]+[[:space:]]+#[[:space:]]+.+$/ {
      split($1, key, ":"); print key[2]; next
    }
    { print "invalid coverage exclusion: " $0 > "/dev/stderr"; exit 1 }
  ' tests/support/coverage_exclusions.txt | sort -u >"$control_excluded"
  if comm -23 "$control_excluded" "$control_required" | grep -q .; then
    echo "coverage exclusion is stale or not an added executable control line" >&2
    exit 1
  fi
  comm -23 "$control_required" "$control_excluded" >"$control_required.remaining"
  covered_lines ui/gunnery_control.lua >"$control_actual"
  comm -23 "$control_required.remaining" "$control_actual" >"$control_missing"
  if [[ -s "$control_missing" ]]; then
    echo "coverage missing changed executable control lines: $(paste -sd, "$control_missing")" >&2
    exit 1
  fi
  control_count=$(wc -l <"$control_required.remaining")
  control_exclusion_count=$(wc -l <"$control_excluded")
else
  control_count=0
  control_exclusion_count=0
fi

state_count=$(executable_lines ui/gunnery_state.lua | wc -l)
persistence_count=$(executable_lines ui/gunnery_persistence.lua | wc -l)
echo "coverage passed: state ${state_count}/${state_count}, persistence ${persistence_count}/${persistence_count}, changed control ${control_count}/${control_count} executable lines"
if [[ "$control_exclusion_count" -gt 0 ]]; then
  echo "coverage note: ${control_exclusion_count} documented engine-only changed-control exclusion(s)" >&2
fi
