#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

validator=scripts/validate.sh

grep -Fq 'for shell_test in tests/*.sh; do' "$validator" \
  || fail "validate.sh does not run shell tests serially"
grep -Fq "timeout 120s bash \"\$shell_test\"" "$validator" \
  || fail "validate.sh does not bound each shell test"
if grep -Eq 'xargs .*bash \{\}' "$validator"; then
  fail "validate.sh still runs shell tests concurrently"
fi

echo "validate shell runner contract tests passed"
