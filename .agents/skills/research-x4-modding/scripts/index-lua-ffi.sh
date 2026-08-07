#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: index-lua-ffi.sh --source DIR [--output NEW_FILE] [--dry-run]

Print line-addressed declarations inside LuaJIT ffi.cdef blocks. --output writes
only to an explicit file that does not already exist. Never reads catalogs or
writes into X4.
EOF
}

source_dir=
output=
dry_run=false
while (($#)); do
  case "$1" in
    --source) source_dir=${2:?missing directory}; shift 2 ;;
    --output) output=${2:?missing file}; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
if [[ -z "$source_dir" || ! -d "$source_dir" ]]; then echo 'provide an existing --source directory' >&2; exit 2; fi
if [[ -n "$output" && -e "$output" ]]; then echo "refusing to overwrite: $output" >&2; exit 2; fi

if "$dry_run"; then
  printf 'source=%s\noutput=%s\n' "$source_dir" "${output:-stdout}"
  exit 0
fi

index() {
  local file
  while IFS= read -r -d '' file; do
    awk -v file="$file" '
      /ffi[[:space:]]*\.cdef[[:space:]]*\[\[/ { inside=1; next }
      inside && /\]\]/ { inside=0; next }
      inside && NF { print file ":" FNR ":" $0 }
    ' "$file"
  done < <(find "$source_dir" -type f \( -name '*.lua' -o -name '*.xpl' \) -print0 | sort -z)
}

if [[ -n "$output" ]]; then
  parent=$(dirname -- "$output")
  [[ -d "$parent" ]] || { echo "output parent does not exist: $parent" >&2; exit 2; }
  index >"$output"
else
  index
fi
