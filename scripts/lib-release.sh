#!/usr/bin/env bash
# Shared release helpers.  Source this file; do not execute it directly.
# Usage:
#   source scripts/lib-release.sh
#   x4_version_int "0.20"        # prints 20
#   content_xml_version          # prints the version="..." integer from content.xml
#   copy_extension_files <dest>  # copies the shipped main extension set into <dest>

x4_version_int() {
  local ver="$1"
  local major minor rest
  IFS='.' read -r major minor rest <<< "$ver"
  # X4 stores version as an integer displayed with a decimal point two places
  # from the right.  EgoSoft's example: to display v2.50 you specify
  # version="250".  So the integer is MAJOR*100 + MINOR, MINOR being the
  # two-digit decimal part as written.  Requiring both digits keeps the mapping
  # injective: "0.1" and "0.10" would otherwise be the same string for
  # different versions.
  if [[ -n "$rest" ]] || [[ ! "$minor" =~ ^[0-9][0-9]$ ]]; then
    echo "x4_version_int: version must be MAJOR.MINOR with a two-digit minor (e.g. 0.20, 2.50); got: $ver" >&2
    return 1
  fi
  echo $(( major * 100 + 10#$minor ))
}

content_xml_version() {
  # cd to repo root so the path works regardless of where the script was sourced
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  grep -o 'version="[0-9]*"' "$root/content.xml" | head -1 | grep -o '[0-9]*'
}

content_xml_version_dotted() {
  # Inverse of x4_version_int: 30 -> 0.30.  Lets callers that just want "the
  # version this tree is at" avoid repeating it (CI used to hardcode it and rot).
  local int
  int=$(content_xml_version)
  printf '%d.%02d\n' $(( int / 100 )) $(( int % 100 ))
}

# copy_extension_files <dest>
# Copies the complete shipped set of the MAIN extension (not Test Lab) into the
# directory given as $1.  The directory must already exist.  Behaviour is
# identical whether the caller is package.sh or install-dev.sh.
#
# Shipped set: content.xml  ui.xml  README.md  LICENSE  md/  ui/  t/
# Deliberately excluded: testlab/  cutscenes/  scripts/  tests/  docs/
#                        CHANGELOG.md  DEVELOPMENT.md  TESTING.md
copy_extension_files() {
  local dest="$1"
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  cp "$root/content.xml" "$root/ui.xml" "$root/README.md" "$root/LICENSE" "$dest/"
  cp -R "$root/md" "$root/ui" "$root/t" "$dest/"
}
