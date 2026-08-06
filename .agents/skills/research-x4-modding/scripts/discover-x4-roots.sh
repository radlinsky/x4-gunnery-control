#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: discover-x4-roots.sh [--x4-root DIR] [--extracted-root DIR] [--format lines|shell]

Report existing X4 installation and unpacked-source roots without modifying them.
Use X4GC_X4_ROOT and X4GC_EXTRACTED_ROOT to configure defaults. The script also
checks common Steam paths on Linux/WSL when no explicit value is supplied.
EOF
}

x4_root=${X4GC_X4_ROOT:-}
extracted_root=${X4GC_EXTRACTED_ROOT:-}
format=lines

while (($#)); do
  case "$1" in
    --x4-root) x4_root=${2:?missing path}; shift 2 ;;
    --extracted-root) extracted_root=${2:?missing path}; shift 2 ;;
    --format) format=${2:?missing format}; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$format" in lines|shell) ;; *) echo "invalid format: $format" >&2; exit 2;; esac

find_root() {
  local candidate
  for candidate in "$@"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

if [[ -z "$x4_root" ]]; then
  x4_root=$(find_root \
    '/mnt/c/Program Files (x86)/Steam/steamapps/common/X4 Foundations' \
    '/mnt/c/GOG Games/X4 Foundations' \
    "$PWD/X4 Foundations" || true)
fi
if [[ -z "$extracted_root" ]]; then
  extracted_root=$(find_root "$PWD/x4-extracted" "$PWD/.x4-research-cache/extracted" || true)
fi

if [[ "$format" == shell ]]; then
  printf 'X4_ROOT=%q\nX4_EXTRACTED_ROOT=%q\n' "$x4_root" "$extracted_root"
else
  printf 'x4_root=%s\nextracted_root=%s\n' "$x4_root" "$extracted_root"
fi
