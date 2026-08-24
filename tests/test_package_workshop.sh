#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

###############################################################################
# test_package_workshop.sh
#
# Tests for scripts/package-workshop.sh
#
# 1. Without release/workshop-id.txt: staged content.xml keeps id="x4_gunnery_control"
# 2. With release/workshop-id.txt: staged content.xml has the substituted id
#    and all OTHER attributes + <dependency> elements are byte-identical to the
#    repo's content.xml.
# 3. The repo's own content.xml is untouched after running the script.
# 4. A present but unavailable wslpath does not abort staging.
###############################################################################

SCRIPT="scripts/package-workshop.sh"

if [[ ! -f "$SCRIPT" ]]; then
  echo "FAIL: $SCRIPT does not exist" >&2
  exit 1
fi

REPO_CONTENT_XML="content.xml"
# Capture the repo's content.xml before any run so we can compare after
ORIGINAL_CONTENT_XML=$(cat "$REPO_CONTENT_XML")

# package-workshop.sh requires VERSION to match content.xml's integer version.
xml_version_int=$(grep -o 'version="[0-9]*"' "$REPO_CONTENT_XML" | head -1 | grep -o '[0-9]*')
pkg_version=$(printf '%d.%02d' "$((xml_version_int / 100))" "$((xml_version_int % 100))")

WORKSHOP_ID_FILE="release/workshop-id.txt"

###############################################################################
# Helper: run the script and capture the staged content.xml path
###############################################################################
run_workshop_pkg() {
  # X4GC_SKIP_VALIDATE: skip the validate.sh call inside package-workshop.sh
  # to avoid recursive shell nesting (validate.sh runs all tests/*.sh, which
  # would call this script again).  validate.sh is tested separately.
  # Both streams are dropped: the script's stdout is the WorkshopTool command
  # print-out and its stderr is the skip-validate and missing-preview warnings,
  # neither of which is under test here. Letting them through means every
  # validate.sh run prints them twice, which trains the reader to ignore
  # warnings. The assertions below read the staged files directly.
  X4GC_SKIP_VALIDATE=1 bash "$SCRIPT" "$pkg_version" > /dev/null 2>&1
}

###############################################################################
# Test 1: without workshop-id.txt, staged id remains x4_gunnery_control
###############################################################################

# Remove any existing id file so we get the clean path
saved_id=""
if [[ -f "$WORKSHOP_ID_FILE" ]]; then
  saved_id=$(cat "$WORKSHOP_ID_FILE")
  rm "$WORKSHOP_ID_FILE"
fi

run_workshop_pkg

STAGED_CONTENT="dist/workshop/x4_gunnery_control/content.xml"

if [[ ! -f "$STAGED_CONTENT" ]]; then
  echo "FAIL: $STAGED_CONTENT not created by $SCRIPT" >&2
  exit 1
fi

staged_id=$(grep -o 'id="[^"]*"' "$STAGED_CONTENT" | head -1 | grep -o '"[^"]*"' | tr -d '"')
if [[ "$staged_id" != "x4_gunnery_control" ]]; then
  echo "FAIL: without workshop-id.txt, staged id should be 'x4_gunnery_control', got '$staged_id'" >&2
  exit 1
fi

###############################################################################
# Test 2: with workshop-id.txt, staged content.xml uses the numeric id
###############################################################################

mkdir -p release
echo "  1234567890  " > "$WORKSHOP_ID_FILE"

run_workshop_pkg

staged_id2=$(grep -o 'id="[^"]*"' "$STAGED_CONTENT" | head -1 | grep -o '"[^"]*"' | tr -d '"')
if [[ "$staged_id2" != "1234567890" ]]; then
  echo "FAIL: with workshop-id.txt containing '  1234567890  ', staged id should be '1234567890', got '$staged_id2'" >&2
  exit 1
fi

###############################################################################
# Test 2b: the kuertee dependency is rewritten to its Workshop counterpart
#
# WorkshopTool rejects any extension depending on a non-Workshop extension, so a
# staged copy still naming the Nexus id cannot be published at all.
###############################################################################

if ! grep -q 'id="ws_3477279743"' "$STAGED_CONTENT"; then
  echo "FAIL: staged content.xml should depend on the Workshop id ws_3477279743" >&2
  exit 1
fi
if grep -q 'kuerteeUIExtensionsAndHUD"' "$STAGED_CONTENT"; then
  echo "FAIL: staged content.xml still names the non-Workshop dependency id" >&2
  exit 1
fi
# Optional on purpose: subscribers who got UI Extensions from Nexus have the mod
# but not this id, and a hard dependency would disable us for them.
if ! grep '<dependency id="ws_3477279743"' "$STAGED_CONTENT" | grep -q 'optional="true"'; then
  echo "FAIL: the Workshop dependency should be optional=\"true\"" >&2
  exit 1
fi
# Dropped on purpose: the repackage's version integer is not ours to predict.
if grep '<dependency id="ws_3477279743"' "$STAGED_CONTENT" | grep -q 'version='; then
  echo "FAIL: the Workshop dependency should carry no version attribute" >&2
  exit 1
fi

# All OTHER attributes should be identical: compare by stripping the id= attribute
# from both the staged and repo content.xml and normalising the one dependency
# line the script is allowed to rewrite.
# The /<content / address is load-bearing. Stripping id= from every line would
# also strip it from each <dependency>, which is precisely how an unanchored
# substitution in package-workshop.sh — one that clobbered the kuertee
# dependency's id — passed this test before.
strip_id() {
  sed -e '/<content /s/ id="[^"]*"//' \
      -e '/kuerteeUIExtensionsAndHUD"\|ws_3477279743"/c\KUERTEE_DEPENDENCY'
}

staged_no_id=$(strip_id < "$STAGED_CONTENT")
repo_no_id=$(strip_id < "$REPO_CONTENT_XML")

if [[ "$staged_no_id" != "$repo_no_id" ]]; then
  echo "FAIL: after id substitution, the staged content.xml differs from repo content.xml in non-id content" >&2
  echo "  staged (id stripped):" >&2
  echo "$staged_no_id" >&2
  echo "  repo (id stripped):" >&2
  echo "$repo_no_id" >&2
  exit 1
fi

###############################################################################
# Test 3: repo's own content.xml is untouched
###############################################################################

current_content=$(cat "$REPO_CONTENT_XML")
if [[ "$current_content" != "$ORIGINAL_CONTENT_XML" ]]; then
  echo "FAIL: scripts/package-workshop.sh modified the repo's content.xml" >&2
  exit 1
fi

###############################################################################
# Test 4: an unusable wslpath falls back to Linux paths
###############################################################################

if ! grep -Fq "if windows_stage=\$(wslpath -w \"\$staged_abs\" 2>/dev/null); then" "$SCRIPT"; then
  echo "FAIL: package-workshop.sh does not guard a failing wslpath conversion" >&2
  exit 1
fi

###############################################################################
# Cleanup: restore original state of workshop-id.txt
###############################################################################

if [[ -n "$saved_id" ]]; then
  echo "$saved_id" > "$WORKSHOP_ID_FILE"
else
  rm -f "$WORKSHOP_ID_FILE"
fi

echo "package-workshop checks passed"
