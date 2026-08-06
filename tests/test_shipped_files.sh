#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=scripts/lib-release.sh
source scripts/lib-release.sh

###############################################################################
# copy_extension_files: exact shipped-set test
#
# Asserts that copy_extension_files copies exactly:
#   content.xml  ui.xml  README.md  LICENSE  md/  ui/  t/
# and does NOT include:
#   testlab/  cutscenes/  scripts/  tests/  docs/
#   CHANGELOG.md  DEVELOPMENT.md  TESTING.md
###############################################################################

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

dest="$tmpdir/ext"
mkdir -p "$dest"
copy_extension_files "$dest"

assert_present() {
  local path="$dest/$1"
  if [[ ! -e "$path" ]]; then
    echo "FAIL: expected '$1' to be present in shipped set, but it is missing" >&2
    exit 1
  fi
}

assert_absent() {
  local path="$dest/$1"
  if [[ -e "$path" ]]; then
    echo "FAIL: '$1' must NOT be in the shipped set, but it was copied" >&2
    exit 1
  fi
}

# -- Must be present --
assert_present "content.xml"
assert_present "ui.xml"
assert_present "README.md"
assert_present "LICENSE"
assert_present "md"
assert_present "ui"
assert_present "t"

# -- Must NOT be present --
assert_absent "testlab"
assert_absent "cutscenes"
assert_absent "scripts"
assert_absent "tests"
assert_absent "docs"
assert_absent "CHANGELOG.md"
assert_absent "DEVELOPMENT.md"
assert_absent "TESTING.md"

echo "shipped-files checks passed"
