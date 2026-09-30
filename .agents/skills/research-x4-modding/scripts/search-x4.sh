#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: search-x4.sh [--x4-root DIR] [--extracted DIR] [--extensions DIR] [--dry-run] -- PATTERN [RG_OPTIONS...]

Search this skill's KB and project first, then optional already-unpacked game and
installed-extension directories. Never writes files. Explicit paths take
precedence. When unset, unpacked source defaults to the main checkout's
.x4-research-cache/official-source-sets directory and common X4 install paths
are discovered automatically.
EOF
}

skill_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
repo_dir=$(CDPATH= cd -- "$skill_dir/../../.." && pwd)
extracted=
x4_root=${X4GC_X4_ROOT:-}
extensions=
dry_run=false

while (($#)); do
  case "$1" in
    --x4-root) x4_root=${2:?missing path}; shift 2 ;;
    --extracted) extracted=${2:?missing path}; shift 2 ;;
    --extensions) extensions=${2:?missing path}; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
if (($# == 0)); then echo 'missing search pattern' >&2; usage >&2; exit 2; fi

pattern=$1
shift
rg_options=("$@")

if [[ -z "$extracted" ]]; then
  git_common_dir=$(git -C "$repo_dir" rev-parse --path-format=absolute --git-common-dir)
  main_repo_dir=$(dirname "$git_common_dir")
  candidate="$main_repo_dir/.x4-research-cache/official-source-sets"
  if [[ -d "$candidate" ]]; then
    extracted=$candidate
  fi
fi
if [[ -z "$x4_root" ]]; then
  for candidate in \
    '/mnt/c/Program Files (x86)/Steam/steamapps/common/X4 Foundations' \
    '/mnt/c/GOG Games/X4 Foundations' \
    "$PWD/X4 Foundations"; do
    if [[ -d "$candidate" ]]; then x4_root=$candidate; break; fi
  done
fi
if [[ -z "$extensions" && -n "$x4_root" && -d "$x4_root/extensions" ]]; then
  extensions="$x4_root/extensions"
fi

roots=("$skill_dir/references" "$repo_dir")
if [[ -n "$extracted" ]]; then roots+=("$extracted"); fi
if [[ -n "$extensions" ]]; then roots+=("$extensions"); fi

for root in "${roots[@]}"; do
  if [[ ! -d "$root" ]]; then echo "missing search root: $root" >&2; exit 2; fi
done

if "$dry_run"; then
  printf 'pattern=%s\n' "$pattern"
  printf 'rg_option=%s\n' "${rg_options[@]}"
  printf 'root=%s\n' "${roots[@]}"
  exit 0
fi

rg -n --hidden --glob '!*.cat' --glob '!*.dat' "${rg_options[@]}" -- "$pattern" "${roots[@]}"
