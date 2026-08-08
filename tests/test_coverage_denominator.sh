#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v luac5.1 >/dev/null; then
  echo "warning: Lua 5.1 compiler unavailable; skipped coverage-denominator test" >&2
  exit 0
fi

fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
fixture=$fixture_dir/jump_lines.lua
printf '%s\n' \
  'local function firstTruthy(values)' \
  '    for _, value in ipairs(values) do' \
  '        if value then' \
  '            break' \
  '        end' \
  '    end' \
  'end' >"$fixture"

denominator=$(./scripts/coverage-executable-lines.sh "$fixture")
if ! grep -qx '4' <<<"$denominator"; then
  echo "coverage denominator incorrectly omitted JMP-only break line" >&2
  exit 1
fi
if grep -qx '5' <<<"$denominator" || grep -qx '6' <<<"$denominator"; then
  echo "coverage denominator retained a JMP-only structural end line" >&2
  exit 1
fi
echo "coverage denominator checks passed"
