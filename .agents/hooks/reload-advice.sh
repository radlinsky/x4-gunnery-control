#!/usr/bin/env bash
set -euo pipefail
# Shared Claude/Codex PostToolUse advisor for X4-loaded file changes.
#
# Direct CLI:
#   .agents/hooks/reload-advice.sh <repo-relative-or-absolute-path>
# Hook mode:
#   - Claude supplies tool_input.file_path.
#   - Codex apply_patch supplies the patch in tool_input.command.
#
# Hook mode considers every path in one edit and emits one instruction. If an
# edit spans independent reload categories, a full restart is the only honest
# single reset.

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)

repo_relative() {
  local input=$1
  if [[ "$input" == "$REPO_ROOT"/* ]]; then
    printf '%s\n' "${input#"$REPO_ROOT"/}"
  else
    printf '%s\n' "$input"
  fi
}

category_for() {
  local operation=$1
  local path
  path=$(repo_relative "$2")

  local loaded=false
  case "$path" in
    ui.xml|content.xml|t/*.xml|ui/*.lua|md/*.xml|libraries/*.xml|aiscripts/*|testlab/*)
      loaded=true ;;
  esac
  [[ "$loaded" == true ]] || return 0

  if [[ "$path" == testlab/* ]]; then
    printf 'restart-testlab\t%s\n' "$path"
  elif [[ "$operation" == add || "$operation" == delete ]]; then
    printf 'restart\t%s\n' "$path"
  else
    case "$path" in
      ui.xml|content.xml|t/*.xml) printf 'restart\t%s\n' "$path" ;;
      ui/*.lua)                  printf 'ui\t%s\n' "$path" ;;
      md/*.xml)                  printf 'md\t%s\n' "$path" ;;
      libraries/*.xml|aiscripts/*) printf 'ai\t%s\n' "$path" ;;
    esac
  fi
}

render_advice() {
  local category=$1 paths=$2
  case "$category" in
    restart-testlab)
      echo "RELOAD: **full restart**. Exit X4 and run scripts/launch-x4-test-lab-dev.bat. Test Lab files changed: ${paths}." ;;
    restart)
      echo "RELOAD: **full restart**. Exit X4 and run scripts/launch-x4-dev.bat (it installs on its own). A reload cannot safely apply all changed X4 files: ${paths}." ;;
    ui)
      echo "RELOAD: run scripts/install-dev.sh \"<game path>\" yourself, then tell the owner: sit at a gunnery console -> use the Test Lab button for the phase under test -> **Reload UI**, and confirm the log shows the runtimeBuild id you installed. THREE Test Lab buttons exist: console action row / target browser action row / engaged panel. A UI reload wipes Lua state. Changed: ${paths}." ;;
    md)
      echo "RELOAD: run scripts/install-dev.sh \"<game path>\" yourself, then tell the owner: sit at a gunnery console -> use the Test Lab button for the phase under test -> **Reload MD**, then trigger the changed cue again. THREE Test Lab buttons exist: console action row / target browser action row / engaged panel. refreshmd keeps cue variables and does not re-run completed cues. Changed: ${paths}." ;;
    ai)
      echo "RELOAD: run scripts/install-dev.sh \"<game path>\" yourself, then tell the owner: sit at a gunnery console -> use the Test Lab button for the phase under test -> **Reload AI**. THREE Test Lab buttons exist: console action row / target browser action row / engaged panel. This route is not live-verified here; if it fails, require a full restart. Changed: ${paths}." ;;
  esac
  echo "See docs/RELOADING.md. Apply the strictest category across the whole change and give the owner one authoritative reset, never a choice."
}

advise_targets() {
  local categories=() paths=()
  local operation path classified category classified_path
  while IFS=$'\t' read -r operation path; do
    [[ -n "$path" ]] || continue
    classified=$(category_for "$operation" "$path")
    [[ -n "$classified" ]] || continue
    IFS=$'\t' read -r category classified_path <<< "$classified"
    categories+=("$category")
    paths+=("$classified_path")
  done

  ((${#categories[@]} > 0)) || return 0

  local chosen=${categories[0]} distinct=${categories[0]}
  for category in "${categories[@]:1}"; do
    if [[ "$category" != "$distinct" ]]; then
      chosen=restart
      break
    fi
  done
  for category in "${categories[@]}"; do
    if [[ "$category" == restart-testlab ]]; then chosen=restart-testlab; break; fi
    if [[ "$category" == restart ]]; then chosen=restart; fi
  done

  local joined
  joined=$(IFS=', '; echo "${paths[*]}")
  render_advice "$chosen" "$joined"
}

if [[ $# -ge 1 ]]; then
  advise_targets <<< $'edit\t'"$1"
  exit 0
fi

# Parse both clients without grepping JSON. For Codex patches, Add/Delete are
# distinguished because any new/deleted X4-loaded file requires a restart.
targets=$(python3 -c '
import json, re, sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
tool_input = data.get("tool_input") or {}
path = tool_input.get("file_path")
if isinstance(path, str) and path:
    print("edit\t" + path)
command = tool_input.get("command")
if isinstance(command, str):
    targets = []
    for line in command.splitlines():
        match = re.match(r"^\*\*\* (Add|Update|Delete) File: (.+)$", line)
        if match:
            targets.append([match.group(1).lower().replace("update", "edit"), match.group(2)])
        else:
            match = re.match(r"^\*\*\* Move to: (.+)$", line)
            if match:
                # apply_patch expresses a move as Update File + Move to. The
                # source disappears, so an X4-loaded source is a deletion even
                # when the destination is documentation or another unloaded path.
                if targets and targets[-1][0] == "edit":
                    targets[-1][0] = "delete"
                targets.append(["add", match.group(1)])
    for operation, target in targets:
        print(operation + "\t" + target)
' || true)

[[ -n "$targets" ]] || exit 0
text=$(advise_targets <<< "$targets")
[[ -n "$text" ]] || exit 0

python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": sys.stdin.read().strip(),
}}))
' <<< "$text"
