#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $*" >&2; exit 1; }
line_of() { grep -n -m1 -F "$1" "$2" | cut -d: -f1; }

agent=.agents/release.agent.md
prompt=.github/prompts/release.prompt.md

[[ -f "$prompt" && ! -L "$prompt" ]] || fail 'release prompt must be a regular file'
cmp -s "$agent" "$prompt" || fail 'release prompt must be byte-identical to its source'

propose=$(line_of '## Step 2 — Propose the version number' "$agent")
clean=$(line_of 'git status --porcelain' "$agent")
fetch=$(line_of 'git fetch --tags origin' "$agent")
upstream=$(line_of 'git rev-parse origin/main' "$agent")
tag=$(line_of 'git tag --list "v<VERSION>"' "$agent")
[[ -n "$propose" && -n "$clean" && -n "$fetch" && -n "$upstream" && -n "$tag" ]] \
  || fail 'release pre-flight commands are incomplete'
(( clean < fetch && fetch < upstream )) || fail 'clean-tree and upstream checks are out of order'
(( propose < tag )) || fail 'tag check occurs before a release version is confirmed'
grep -Fq 'Download the GitHub release ZIP' "$agent" || fail 'Nexus staging artifact guidance missing'
grep -Fq 'Run from WSL with Steam open on Windows' "$agent" || fail 'WSL Workshop guidance missing'
grep -Fq 'windows-contract:' .github/workflows/ci.yml || fail 'Windows contract CI job missing'
grep -Fq 'git config --global core.symlinks false' .github/workflows/ci.yml || fail 'Windows checkout symlink setting missing'
grep -Fq './scripts/validate-windows.ps1' .github/workflows/ci.yml || fail 'Windows contract script is not run by CI'
# shellcheck disable=SC2016 # The GitHub expression is intentionally literal.
grep -Fq 'X4GC_DIFF_BASE: ${{ github.event.pull_request.base.sha }}' .github/workflows/ci.yml \
  || fail 'PR-base whitespace gate missing'
grep -Fq 'deterministic missing-X4 exit 2' scripts/validate-windows.ps1 \
  || fail 'Windows launcher exit-code contract missing'
grep -Fq 'cygpath -u' scripts/validate-windows.ps1 \
  || fail 'Windows hook path is not converted for Git Bash'
# shellcheck disable=SC2016 # This PowerShell environment assignment is literal.
grep -Fq '$env:CLAUDE_PROJECT_DIR = $bashRoot' scripts/validate-windows.ps1 \
  || fail 'Windows hook does not set CLAUDE_PROJECT_DIR to the Git-Bash path'
grep -Fq 'Remove-Item Env:CLAUDE_PROJECT_DIR' scripts/validate-windows.ps1 \
  || fail 'Windows hook does not restore an unset CLAUDE_PROJECT_DIR'
grep -Fq 'owner-tested Windows task' DEVELOPMENT.md \
  || fail 'manual WSL/X4 owner-test boundary missing from developer guide'

python3 - .claude/settings.json .codex/hooks.json <<'PY'
import json
import sys

settings = json.load(open(sys.argv[1], encoding="utf-8"))
hooks = settings["hooks"]["PostToolUse"]
assert any(
    hook["matcher"] == "Edit|Write|NotebookEdit"
    and hook["hooks"][0]["command"] == '"$CLAUDE_PROJECT_DIR/.agents/hooks/reload-advice.sh"'
    for hook in hooks
)
codex = json.load(open(sys.argv[2], encoding="utf-8"))
hooks = codex["hooks"]["PostToolUse"]
assert any(
    "apply_patch" in hook["matcher"]
    and ".agents/hooks/reload-advice.sh" in hook["hooks"][0]["command"]
    and ".agents/hooks/reload-advice.sh" in hook["hooks"][0]["commandWindows"]
    for hook in hooks
)
PY

space_root=$(mktemp -d '/tmp/x4gc hook contract with spaces.XXXXXX')
trap 'rm -rf "$space_root"' EXIT
mkdir -p "$space_root/.agents/hooks"
cp .agents/hooks/reload-advice.sh "$space_root/.agents/hooks/reload-advice.sh"
hook_command=$(python3 -c '
import json
print(json.load(open(".claude/settings.json", encoding="utf-8"))["hooks"]["PostToolUse"][0]["hooks"][0]["command"])
')
hook_output=$(printf '{"tool_input":{"file_path":"%s/ui/gunnery_control.lua"}}\n' "$space_root" \
  | CLAUDE_PROJECT_DIR="$space_root" bash -c "$hook_command")
grep -Fq 'Reload UI' <<<"$hook_output" || fail 'quoted reload hook did not run from a spaced path'

# Execute the registered Codex command too. Codex supplies apply_patch source
# rather than Claude's one-file path, and resolves the shared hook from Git root.
git -C "$space_root" init -q
codex_hook_command=$(python3 -c '
import json
print(json.load(open(".codex/hooks.json", encoding="utf-8"))["hooks"]["PostToolUse"][0]["hooks"][0]["command"])
')
codex_payload=$(python3 -c '
import json
print(json.dumps({"tool_input": {"command": "*** Begin Patch\n*** Update File: ui/gunnery_control.lua\n*** End Patch"}}))
')
hook_output=$(cd "$space_root" && printf '%s\n' "$codex_payload" | bash -c "$codex_hook_command")
grep -Fq 'Reload UI' <<<"$hook_output" \
  || fail 'registered Codex reload hook did not run from a spaced path'

echo 'release and settings contracts passed'
