#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# The hook exists so an agent cannot forget which reset a change needs. The
# failure it prevents is silent — "click Reload UI" for a change that needed a
# restart looks exactly like a change that did not work — so the mapping itself
# is what is worth testing, in both call modes.

fail() { echo "FAIL: $1" >&2; exit 1; }

expect_contains() {
  local path=$1 needle=$2
  local out
  out=$(scripts/reload-advice.sh "$path")
  grep -Fq "$needle" <<< "$out" || fail "$path did not advise '$needle'; got: ${out:-<nothing>}"
}

expect_contains "ui/gunnery_control.lua" "Reload UI"
expect_contains "md/x4_gunnery_control.xml" "Reload MD"
expect_contains "t/0001.xml" "full restart"
expect_contains "ui.xml" "full restart"
expect_contains "content.xml" "full restart"
expect_contains "testlab/x4_gunnery_control_testlab/ui/testlab.lua" "launch-x4-test-lab-dev.bat"

# "Click Reload UI" is not actionable on its own: the button lives in Test Lab,
# which is opened from the gunnery console, which only exists while seated. The
# owner asked for these steps by name after being told just the button.
expect_contains "ui/gunnery_control.lua" "sit at a gunnery console"
expect_contains "ui/gunnery_control.lua" "Test Lab"
expect_contains "ui/gunnery_control.lua" "runtimeBuild"
expect_contains "md/x4_gunnery_control.xml" "sit at a gunnery console"

# And "the Test Lab button" is still ambiguous: there are three, on the console
# action row, the target browser action row and the engaged panel. Which one is
# clicked decides what session gets parked and therefore what the reload
# restores, so the advice has to say there is a choice to make.
expect_contains "ui/gunnery_control.lua" "THREE Test Lab buttons"
expect_contains "md/x4_gunnery_control.xml" "THREE Test Lab buttons"

# t/ and testlab/ must NOT be advised as a reload: those are the two cases where
# the strict answer is a restart and the tempting answer is a button.
for path in t/0001.xml testlab/x4_gunnery_control_testlab/ui/testlab.lua; do
  if scripts/reload-advice.sh "$path" | grep -Fq "Reload UI"; then
    fail "$path was advised as Reload UI, but it needs a restart"
  fi
done

# Files X4 never loads must stay silent, or every edit in the repo carries noise.
for path in README.md tests/test_reload_advice.sh scripts/validate.sh docs/RELOADING.md; do
  out=$(scripts/reload-advice.sh "$path")
  [[ -z "$out" ]] || fail "$path should produce no advice; got: $out"
done

# Hook mode: same mapping, wrapped in the PostToolUse JSON contract. An absolute
# path is what a real payload carries.
hook_out=$(printf '{"tool_input":{"file_path":"%s/ui/gunnery_control.lua"}}' "$PWD" \
  | scripts/reload-advice.sh)
grep -Fq '"hookEventName": "PostToolUse"' <<< "$hook_out" || fail "hook output missing hookEventName"
grep -Fq 'Reload UI' <<< "$hook_out" || fail "hook output missing the advice"

# A payload with no file_path (or malformed JSON) must exit clean and silent,
# otherwise every unrelated tool call surfaces a hook error to the user.
[[ -z "$(printf '{"tool_input":{}}' | scripts/reload-advice.sh)" ]] \
  || fail "a payload without file_path must produce no output"
[[ -z "$(printf 'not json' | scripts/reload-advice.sh)" ]] \
  || fail "malformed JSON must produce no output"

echo "reload advice checks passed"
