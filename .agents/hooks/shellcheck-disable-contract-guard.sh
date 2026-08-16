#!/usr/bin/env bash
set -euo pipefail
# Shared policy engine: reject any line-level ShellCheck disable directive in
# shell contract tests.
#
# CLI:
#   .agents/hooks/shellcheck-disable-contract-guard.sh <repo-relative-path>
#
# stdin: proposed/new text for the target file.
#
# Exit 0 = allowed; nonzero = rejected with a diagnostic on stderr.

DIAGNOSTIC="Line-level ShellCheck disable directives are not allowed in shell contract tests. Fix the shell expression instead of suppressing the warning."

# Require exactly one argument: the path being edited.
if [[ $# -ne 1 ]]; then
  echo "usage: shellcheck-disable-contract-guard.sh <repo-relative-path>" >&2
  exit 1
fi

TARGET_PATH=$1

# Scope: only paths under tests/ whose basename contains "contract" and ends
# in .sh. Anything outside that scope is allowed through without inspection.
case "$TARGET_PATH" in
  tests/*contract*.sh) ;;
  *) exit 0 ;;
esac

# Read stdin once.
proposed=$(cat)

# Detect line-level ShellCheck disable directives with ordinary whitespace
# variation. Reject only actual directive lines, not prose mentions of the
# phrase or other ShellCheck directives (e.g. source=). The pattern matches:
#   # shellcheck disable=SC2016
#   #shellcheck disable=SC2086
#       # shellcheck disable=SC2034
#   # shellcheck disable=all
#   # shellcheck disable = SC2016
if grep -Eq '^[[:space:]]*#[[:space:]]*shellcheck[[:space:]]+disable[=[:space:]]' <<< "$proposed"; then
  echo "REJECTED in ${TARGET_PATH}: $DIAGNOSTIC" >&2
  exit 1
fi

exit 0
