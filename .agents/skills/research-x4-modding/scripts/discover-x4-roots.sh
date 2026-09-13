#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: discover-x4-roots.sh [--x4-root DIR] [--extracted-root DIR] [--format lines|shell]

Report existing X4 installation and unpacked-source roots without modifying them.
Explicit root options are for one-off research. Otherwise unpacked source is the
main checkout's .x4-research-cache/official-source-sets directory.
EOF
}

x4_root=${X4GC_X4_ROOT:-}
extracted_root=
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
  script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
  repo_dir=$(CDPATH= cd -- "$script_dir/../../../.." && pwd)
  git_common_dir=$(git -C "$repo_dir" rev-parse --path-format=absolute --git-common-dir)
  main_repo_dir=$(dirname "$git_common_dir")
  candidate="$main_repo_dir/.x4-research-cache/official-source-sets"
  if [[ -d "$candidate" ]]; then
    extracted_root=$candidate
  fi
fi

if [[ "$format" == shell ]]; then
  printf 'X4_ROOT=%q\nX4_EXTRACTED_ROOT=%q\n' "$x4_root" "$extracted_root"
else
  printf 'x4_root=%s\nextracted_root=%s\n' "$x4_root" "$extracted_root"
fi
