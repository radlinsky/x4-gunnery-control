#!/usr/bin/env bash
set -euo pipefail
# Codex PreToolUse adapter for the shared ShellCheck-disable contract policy.
#
# Receives a Codex PreToolUse JSON payload on stdin, parses apply_patch sections,
# collects newly-added patch lines, and delegates to
# .agents/hooks/shellcheck-disable-contract-guard.sh.
#
# Exit 0 = allowed; exit 2 = blocked (Codex blocks the tool call).

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GUARD="$REPO_ROOT/.agents/hooks/shellcheck-disable-contract-guard.sh"

python3 -c "
import json, os, subprocess, sys


def die(msg):
    print(
        'Codex pre-edit policy hook could not safely inspect the proposed edit: ' + msg,
        file=sys.stderr,
    )
    sys.exit(2)


def run_guard(path, content):
    try:
        return subprocess.run(
            [GUARD_PATH, path],
            input=content,
            capture_output=True,
            text=True,
        )
    except OSError as exc:
        die('cannot execute shared guard (' + str(exc) + ')')


try:
    data = json.load(sys.stdin)
except Exception as exc:
    die('invalid JSON (' + str(exc) + ')')

if not isinstance(data, dict):
    die('expected JSON object at top level')

tool_name = data.get('tool_name')
if tool_name != 'apply_patch':
    sys.exit(0)

tool_input = data.get('tool_input')
if not isinstance(tool_input, dict):
    die('expected tool_input object')

command = tool_input.get('command')
if not isinstance(command, str):
    die('missing or invalid tool_input.command')

# Parse the patch into sections.  Codex apply_patch shape:
#   *** Add File: PATH
#   *** Update File: PATH
#   *** Delete File: PATH
# Optionally followed by:
#   *** Move to: DESTINATION
# Then zero or more diff-style lines starting with +, -, or ' '.

REPO_ROOT_NORM = os.path.normpath(sys.argv[1])
GUARD_PATH = sys.argv[2]

lines = command.splitlines()
i = 0
n = len(lines)
errors = []

while i < n:
    line = lines[i]

    if line.startswith('*** Add File: '):
        path = line[len('*** Add File: '):].strip()
        i += 1
        # Check for optional Move to.
        dest = None
        if i < n and lines[i].startswith('*** Move to: '):
            dest = lines[i][len('*** Move to: '):].strip()
            i += 1
        # Collect all added lines (start with +) until the next section header.
        added = []
        while i < n and not lines[i].startswith('*** '):
            if lines[i].startswith('+'):
                added.append(lines[i][1:])  # strip leading +
            i += 1
        if dest:
            effective_path = dest
        else:
            effective_path = path

    elif line.startswith('*** Update File: '):
        path = line[len('*** Update File: '):].strip()
        i += 1
        # Check for optional Move to.
        dest = None
        if i < n and lines[i].startswith('*** Move to: '):
            dest = lines[i][len('*** Move to: '):].strip()
            i += 1
        # Collect all added lines (start with +) until the next section header.
        added = []
        while i < n and not lines[i].startswith('*** '):
            if lines[i].startswith('+'):
                added.append(lines[i][1:])  # strip leading +
            i += 1
        if dest:
            effective_path = dest
        else:
            effective_path = path

    elif line.startswith('*** Delete File: '):
        i += 1
        # No added text to inspect.
        continue

    else:
        # Unrecognised section header — skip a line at a time; let
        # apply_patch's own validation catch syntax issues later.
        i += 1
        continue

    # Resolve repo-relative path for the guard.
    abspath = os.path.abspath(effective_path)
    norm_root = REPO_ROOT_NORM
    if abspath.startswith(norm_root + os.sep):
        rel_path = abspath[len(norm_root) + 1:]
    else:
        rel_path = abspath

    # If this is a move, also inspect the source file's complete current
    # contents using the shared guard with DEST as the guard path.  That
    # prevents existing forbidden content from being carried into a contract
    # path even when the patch adds no lines.
    if dest:
        try:
            with open(os.path.join(REPO_ROOT_NORM, path), 'r') as f:
                source_content = f.read()
        except Exception:
            # Source file does not exist — let apply_patch's own validation
            # catch the invalid patch; do not invent content.
            source_content = None
        if source_content is not None:
            result = run_guard(rel_path, source_content)
            if result.returncode != 0:
                errors.append(result.stderr)

    if not added:
        continue

    result = run_guard(rel_path, '\n'.join(added))
    if result.returncode != 0:
        errors.append(result.stderr)

if errors:
    sys.stderr.write('\n'.join(errors))
    sys.exit(2)

sys.exit(0)
" "$REPO_ROOT" "$GUARD"
