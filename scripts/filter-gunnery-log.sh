#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/x4-gunnery-control-debug.log" >&2
  exit 2
fi

log_file=$1
if [[ ! -f "$log_file" ]]; then
  echo "Log file not found: $log_file" >&2
  exit 2
fi

grep -E '\[X4GC( TEST)?\]|[Ee]rror.*(X4GC|x4_gunnery)|[Ee]xception.*(X4GC|x4_gunnery)' "$log_file" || true
