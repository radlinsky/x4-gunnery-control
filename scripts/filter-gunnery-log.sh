#!/usr/bin/env bash
set -euo pipefail

# Single source of truth for what counts as a mod log line. tail-gunnery-log.sh
# sources this file to reuse it; sourcing stops here and defines nothing else.
# [X4GC TEST SCENARIO] is the spawner's own prefix. It was excluded until
# 2026-08-10 purely because the pattern demanded a "]" straight after "TEST",
# which silently hid every spawn and capture line from the filtered log.
# The TEST branch is therefore open-ended rather than an enumeration of known
# sub-prefixes: adding STATE, SOLUTION and MARK by name would have re-armed the
# exact same trap for the next prefix anyone invents. [^]]* stops at the closing
# bracket, so this still cannot swallow an unrelated line that merely mentions
# X4GC further along.
X4GC_LOG_PATTERN='\[X4GC( TEST[^]]*)?\]|[Ee]rror.*(X4GC|x4_gunnery)|[Ee]xception.*(X4GC|x4_gunnery)'
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/x4-gunnery-control-debug.log" >&2
  exit 2
fi

log_file=$1
if [[ ! -f "$log_file" ]]; then
  echo "Log file not found: $log_file" >&2
  exit 2
fi

grep -E "$X4GC_LOG_PATTERN" "$log_file" || true
