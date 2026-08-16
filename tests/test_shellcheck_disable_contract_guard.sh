#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Black-box tests for the generalized ShellCheck disable contract guard. All
# exercises run the script as a subprocess and assert on observable exit status
# and stderr content.

hook=.agents/hooks/shellcheck-disable-contract-guard.sh
pass=0
fail=0

assert_ok() {
  local desc=$1 input=$2 path=$3
  if ! out=$(printf '%s\n' "$input" | "$hook" "$path"); then
    echo "FAIL: $desc (expected exit 0, got nonzero; stderr was: ${out:-<empty>})" >&2
    ((fail++)) || true
    return
  fi
  ((pass++)) || true
}

assert_reject() {
  local desc=$1 input=$2 path=$3 needle=$4
  if out=$(printf '%s\n' "$input" | "$hook" "$path" 2>&1); then
    echo "FAIL: $desc (expected nonzero, got exit 0; output was: ${out:-<empty>})" >&2
    ((fail++)) || true
    return
  fi
  if ! grep -Fq "$needle" <<< "$out"; then
    echo "FAIL: $desc (diagnostic missing needle '$needle'; stderr was: ${out:-<empty>})" >&2
    ((fail++)) || true
    return
  fi
  ((pass++)) || true
}

assert_usage() {
  local desc=$1
  if out=$(printf '' | "$hook" 2>&1); then
    echo "FAIL: $desc (expected nonzero with no path, got exit 0; output was: ${out:-<empty>})" >&2
    ((fail++)) || true
    return
  fi
  if ! grep -Eq 'usage:' <<< "$out"; then
    echo "FAIL: $desc (diagnostic missing 'usage:' hint; stderr was: ${out:-<empty>})" >&2
    ((fail++)) || true
    return
  fi
  ((pass++)) || true
}

# 1. Normal contract-test text is allowed.
assert_ok "normal contract edit" \
  $'grep -Fq "event.param3.$anchor" md/x4_gunnery_control.xml' \
  "tests/test_example_contract.sh"

# 2. # shellcheck disable=SC2016 is rejected.
assert_reject "disable=SC2016 rejected" \
  '# shellcheck disable=SC2016' \
  "tests/test_example_contract.sh" \
  "REJECTED in tests/test_example_contract.sh"

# 3. # shellcheck disable=SC2086 is rejected.
assert_reject "disable=SC2086 rejected" \
  '# shellcheck disable=SC2086' \
  "tests/test_example_contract.sh" \
  "REJECTED in tests/test_example_contract.sh"

# 4. # shellcheck disable=SC2034 is rejected.
assert_reject "disable=SC2034 rejected" \
  '# shellcheck disable=SC2034' \
  "tests/test_example_contract.sh" \
  "REJECTED in tests/test_example_contract.sh"

# 5. # shellcheck disable=all is rejected.
assert_reject "disable=all rejected" \
  '# shellcheck disable=all' \
  "tests/test_example_contract.sh" \
  "REJECTED in tests/test_example_contract.sh"

# 6. Multi-code disable is rejected.
assert_reject "multi-code disable rejected" \
  '# shellcheck disable=SC2016,SC2086' \
  "tests/test_example_contract.sh" \
  "REJECTED in tests/test_example_contract.sh"

# 7. #shellcheck disable=... (no space after #) is rejected.
assert_reject "no-space-after-hash rejected" \
  '#shellcheck disable=SC2086' \
  "tests/test_example_contract.sh" \
  "REJECTED in tests/test_example_contract.sh"

# 8. Leading indentation before the directive is rejected.
assert_reject "indented directive rejected" \
  '    # shellcheck disable=SC2016' \
  "tests/test_example_contract.sh" \
  "REJECTED in tests/test_example_contract.sh"

# 9. # shellcheck disable = SC2016 (space around =) is rejected.
assert_reject "space-around-equals rejected" \
  '# shellcheck disable = SC2016' \
  "tests/test_example_contract.sh" \
  "REJECTED in tests/test_example_contract.sh"

# 10. # shellcheck source=... is allowed.
assert_ok "shellcheck source allowed" \
  '# shellcheck source=scripts/lib-release.sh' \
  "tests/test_example_contract.sh"

# 11. Prose mentioning "shellcheck disable" is allowed.
assert_ok "prose mention allowed" \
  'echo "shellcheck disable=SC2016"' \
  "tests/test_example_contract.sh"

# 12. A disable directive on a non-contract test path is allowed by this guard.
assert_ok "non-contract path allowed" \
  '# shellcheck disable=SC2016' \
  "tests/test_runtime_ui_contract.sh.bak"

# 13. A disable directive outside tests/ is allowed by this guard.
assert_ok "outside-tests path allowed" \
  '# shellcheck disable=SC2016' \
  "docs/shellcheck-policy.md"

# 14. Missing path argument fails with usage text.
assert_usage "no-path invocation"

# 15. Rejection diagnostic includes the target path.
assert_reject "diagnostic includes path" \
  '# shellcheck disable=SC2016' \
  "tests/test_example_contract.sh" \
  "tests/test_example_contract.sh"

# 16. Rejection diagnostic tells the author to fix the code rather than suppress ShellCheck.
assert_reject "diagnostic advises fixing code" \
  '# shellcheck disable=SC2016' \
  "tests/test_example_contract.sh" \
  "Fix the shell expression instead of suppressing the warning"

# Repository-invariant: every real shell contract test currently in the
# repository must satisfy the shared guard. This covers edit paths that bypass
# client hooks (Bash commands, apply_patch, human editors, etc.). The scan
# automatically covers future tests/*contract*.sh additions without updating
# this file.
for path in tests/*contract*.sh; do
  content=$(cat -- "$path")
  if ! out=$(printf '%s\n' "$content" | "$hook" "$path" 2>&1); then
    echo "FAIL: repository invariant — $path rejected by shared guard: $out" >&2
    ((fail++)) || true
  else
    ((pass++)) || true
  fi
done

echo "shellcheck-disable contract guard checks passed: ${pass} passed, ${fail} failed"
if ((fail > 0)); then exit 1; fi
