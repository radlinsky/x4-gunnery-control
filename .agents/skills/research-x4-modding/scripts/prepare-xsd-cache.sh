#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: prepare-xsd-cache.sh --source EXTRACTED_DIR --cache-root IGNORED_DIR [--dry-run]

Copy md/md.xsd and its recursive schemaLocation include/import dependencies from
an already extracted game tree to CACHE_ROOT/schema. CACHE_ROOT is explicit and
the destination must not exist. The script never unpacks catalogs or writes to X4.
EOF
}

source_dir=
cache_root=
dry_run=false
while (($#)); do
  case "$1" in
    --source) source_dir=${2:?missing directory}; shift 2 ;;
    --cache-root) cache_root=${2:?missing directory}; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
if [[ -z "$source_dir" || ! -f "$source_dir/md/md.xsd" ]]; then echo 'source must contain md/md.xsd' >&2; exit 2; fi
source_dir=$(realpath -e -- "$source_dir")
if [[ -z "$cache_root" || "$cache_root" == / || "$cache_root" == . ]]; then echo 'provide a specific non-root --cache-root' >&2; exit 2; fi
dest="$cache_root/schema"
if [[ -e "$dest" ]]; then echo "refusing existing destination: $dest" >&2; exit 2; fi

declare -a queue=('md/md.xsd')
declare -A seen=()
declare -a files=()
while ((${#queue[@]})); do
  relative=${queue[0]}
  queue=("${queue[@]:1}")
  [[ -n ${seen[$relative]:-} ]] && continue
  seen[$relative]=1
  source_file="$source_dir/$relative"
  [[ -f "$source_file" ]] || { echo "missing schema dependency: $relative" >&2; exit 2; }
  files+=("$relative")
  source_parent=$(dirname -- "$relative")
  while IFS= read -r include; do
    dependency=$(cd "$source_dir/$source_parent" && realpath -m --relative-to="$source_dir" "$include")
    case "$dependency" in ../*|..) echo "schema dependency escapes source: $include" >&2; exit 2;; esac
    queue+=("$dependency")
  done < <(grep -oE 'schemaLocation="[^"]+"' "$source_file" | sed -E 's/^schemaLocation="(.*)"$/\1/' || true)
done

if "$dry_run"; then
  printf 'destination=%s\n' "$dest"
  printf 'copy=%s\n' "${files[@]}"
  exit 0
fi
mkdir -p -- "$dest"
for relative in "${files[@]}"; do
  mkdir -p -- "$dest/$(dirname -- "$relative")"
  cp -- "$source_dir/$relative" "$dest/$relative"
done
