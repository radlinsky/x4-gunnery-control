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
  out=$(.agents/hooks/reload-advice.sh "$path")
  grep -Fq "$needle" <<< "$out" || fail "$path did not advise '$needle'; got: ${out:-<nothing>}"
}

expect_contains "ui/gunnery_control.lua" "Reload UI"
expect_contains "md/x4_gunnery_control.xml" "Reload MD"
expect_contains "t/0001.xml" "full restart"
expect_contains "ui.xml" "full restart"
expect_contains "content.xml" "full restart"
# Test Lab reloads like any other extension. Live-verified 2026-08-09: a
# testlab/ui/*.lua edit applied on Reload UI, a testlab/md/*.xml edit on Reload
# MD, neither needed a restart. Structural Test Lab files still restart.
expect_contains "testlab/x4_gunnery_control_testlab/ui/testlab.lua" "Reload UI"
expect_contains "testlab/x4_gunnery_control_testlab/ui/testlab.lua" "X4GC_INSTALL_TESTLAB=1"
expect_contains "testlab/x4_gunnery_control_testlab/md/scenario.xml" "Reload MD"
expect_contains "testlab/x4_gunnery_control_testlab/ui.xml" "launch-x4-test-lab-dev.bat"
expect_contains "testlab/x4_gunnery_control_testlab/t/0001.xml" "launch-x4-test-lab-dev.bat"
expect_contains "libraries/example.xml" "Reload AI"
expect_contains "aiscripts/example.xml" "Reload AI"

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

# Text and structural Test Lab files must NOT be advised as a reload: those are
# the cases where the strict answer is a restart and the tempting answer is a
# button.
for path in t/0001.xml testlab/x4_gunnery_control_testlab/ui.xml testlab/x4_gunnery_control_testlab/t/0001.xml; do
  if .agents/hooks/reload-advice.sh "$path" | grep -Fq "Reload UI"; then
    fail "$path was advised as Reload UI, but it needs a restart"
  fi
done

# Files X4 never loads must stay silent, or every edit in the repo carries noise.
for path in README.md tests/test_reload_advice.sh scripts/validate.sh docs/RELOADING.md; do
  out=$(.agents/hooks/reload-advice.sh "$path")
  [[ -z "$out" ]] || fail "$path should produce no advice; got: $out"
done

# Hook mode: same mapping, wrapped in the PostToolUse JSON contract. An absolute
# path is what a real payload carries.
hook_out=$(printf '{"tool_input":{"file_path":"%s/ui/gunnery_control.lua"}}' "$PWD" \
  | .agents/hooks/reload-advice.sh)
grep -Fq '"hookEventName": "PostToolUse"' <<< "$hook_out" || fail "hook output missing hookEventName"
grep -Fq 'Reload UI' <<< "$hook_out" || fail "hook output missing the advice"

# A payload with no file_path (or malformed JSON) must exit clean and silent,
# otherwise every unrelated tool call surfaces a hook error to the user.
[[ -z "$(printf '{"tool_input":{}}' | .agents/hooks/reload-advice.sh)" ]] \
  || fail "a payload without file_path must produce no output"
[[ -z "$(printf 'not json' | .agents/hooks/reload-advice.sh)" ]] \
  || fail "malformed JSON must produce no output"

# Codex sends the complete apply_patch source as tool_input.command. A single
# edit maps normally; a patch spanning independent reload categories escalates
# to one restart, and Add/Delete only escalate when the path is X4-loaded.
codex_patch='*** Begin Patch
*** Update File: ui/gunnery_control.lua
@@
-old
+new
*** End Patch'
hook_out=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' \
  <<< "$codex_patch" | .agents/hooks/reload-advice.sh)
grep -Fq 'Reload UI' <<< "$hook_out" || fail "Codex UI patch did not advise Reload UI"

codex_patch='*** Begin Patch
*** Update File: ui/gunnery_control.lua
@@
-old
+new
*** Update File: md/x4_gunnery_control.xml
@@
-old
+new
*** End Patch'
hook_out=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' \
  <<< "$codex_patch" | .agents/hooks/reload-advice.sh)
grep -Fq 'full restart' <<< "$hook_out" \
  || fail "mixed Codex UI/MD patch did not escalate to one full restart"

codex_patch='*** Begin Patch
*** Add File: ui/new_runtime.lua
+return {}
*** End Patch'
hook_out=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' \
  <<< "$codex_patch" | .agents/hooks/reload-advice.sh)
grep -Fq 'full restart' <<< "$hook_out" \
  || fail "new X4-loaded file did not advise a full restart"

codex_patch='*** Begin Patch
*** Add File: PR16_LIVE_TEST_CHECKLIST.md
+# Checklist
*** End Patch'
hook_out=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' \
  <<< "$codex_patch" | .agents/hooks/reload-advice.sh)
[[ -z "$hook_out" ]] || fail "new documentation file should not produce reload advice"

codex_patch='*** Begin Patch
*** Delete File: md/obsolete.xml
*** End Patch'
hook_out=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' \
  <<< "$codex_patch" | .agents/hooks/reload-advice.sh)
grep -Fq 'full restart' <<< "$hook_out" \
  || fail "deleted X4-loaded file did not advise a full restart"

codex_patch='*** Begin Patch
*** Update File: ui/gunnery_control.lua
@@
-old
+new
*** Update File: testlab/x4_gunnery_control_testlab/ui/testlab.lua
@@
-old
+new
*** End Patch'
hook_out=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' \
  <<< "$codex_patch" | .agents/hooks/reload-advice.sh)
grep -Fq 'launch-x4-test-lab-dev.bat' <<< "$hook_out" \
  || fail "Test Lab change did not select the Test Lab restart launcher"

codex_patch='*** Begin Patch
*** Update File: ui/retired_runtime.lua
*** Move to: docs/retired-runtime-example.lua
@@
-old
+new
*** End Patch'
hook_out=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' \
  <<< "$codex_patch" | .agents/hooks/reload-advice.sh)
grep -Fq 'full restart' <<< "$hook_out" \
  || fail "moving an X4-loaded file out of ui/ did not count as a deletion"

# Invoked from a repo subdirectory: the script must still match correctly
# regardless of what $PWD is when it is called.
(
  cd scripts
  out=$(../.agents/hooks/reload-advice.sh "ui/gunnery_control.lua")
  grep -Fq "Reload UI" <<< "$out" || fail "subdirectory caller: ui/gunnery_control.lua did not advise Reload UI; got: ${out:-<nothing>}"
)
(
  cd scripts
  out=$(../.agents/hooks/reload-advice.sh "md/x4_gunnery_control.xml")
  grep -Fq "Reload MD" <<< "$out" || fail "subdirectory caller: md/x4_gunnery_control.xml did not advise Reload MD; got: ${out:-<nothing>}"
)

# Path containing a space: the repo root itself may be in a directory with a
# space in its name, and the advice must still work via the hook's absolute path.
space_root=$(mktemp -d "/tmp/repo with spaces XXXXXX")
trap 'rm -rf "$space_root"' EXIT
mkdir -p "$space_root/.agents/hooks"
cp .agents/hooks/reload-advice.sh "$space_root/.agents/hooks/reload-advice.sh"
out=$("$space_root/.agents/hooks/reload-advice.sh" "ui/gunnery_control.lua")
grep -Fq "Reload UI" <<< "$out" \
  || fail "space in script path: ui/gunnery_control.lua did not advise Reload UI; got: ${out:-<nothing>}"
# Absolute path under the spaced root must also strip correctly.
out=$("$space_root/.agents/hooks/reload-advice.sh" "$space_root/ui/gunnery_control.lua")
grep -Fq "Reload UI" <<< "$out" \
  || fail "space in repo root (absolute): ui/gunnery_control.lua did not advise Reload UI; got: ${out:-<nothing>}"

echo "reload advice checks passed"
