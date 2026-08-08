#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=scripts/lib-release.sh
source scripts/lib-release.sh

###############################################################################
# 1. Helper: x4_version_int conversion
###############################################################################
check_int() {
  local input="$1" expected="$2"
  local got
  got=$(x4_version_int "$input")
  if [[ "$got" != "$expected" ]]; then
    echo "FAIL: x4_version_int $input: expected $expected, got $got" >&2
    exit 1
  fi
}

check_int "0.20" "20"
check_int "1.00" "100"
check_int "2.50" "250"
check_int "9.00" "900"
check_int "0.10" "10"

# 0.10 and 1.00 must not collide
got_010=$(x4_version_int "0.10")
got_100=$(x4_version_int "1.00")
if [[ "$got_010" == "$got_100" ]]; then
  echo "FAIL: 0.10 and 1.00 map to the same integer ($got_010)" >&2
  exit 1
fi

# Rejection: one-digit minor must be rejected
if x4_version_int "0.2" 2>/dev/null; then
  echo "FAIL: x4_version_int accepted one-digit minor 0.2" >&2
  exit 1
fi

# Rejection: three-part version must be rejected by x4_version_int
if x4_version_int "0.2.0" 2>/dev/null; then
  echo "FAIL: x4_version_int accepted three-part version 0.2.0" >&2
  exit 1
fi

###############################################################################
# 2. Three-part version rejected by package.sh
###############################################################################
if ./scripts/package.sh 0.2.0 2>/dev/null; then
  echo "FAIL: package.sh accepted three-part version 0.2.0" >&2
  exit 1
fi

# One-digit minor rejected by package.sh
if ./scripts/package.sh 0.2 2>/dev/null; then
  echo "FAIL: package.sh accepted one-digit minor 0.2" >&2
  exit 1
fi

###############################################################################
# 3. Three-part version rejected by package-testlab.sh
###############################################################################
if ./scripts/package-testlab.sh 0.2.0 2>/dev/null; then
  echo "FAIL: package-testlab.sh accepted three-part version 0.2.0" >&2
  exit 1
fi

# One-digit minor rejected by package-testlab.sh
if ./scripts/package-testlab.sh 0.2 2>/dev/null; then
  echo "FAIL: package-testlab.sh accepted one-digit minor 0.2" >&2
  exit 1
fi

###############################################################################
# 4. Mismatched content.xml detected by validate.sh
###############################################################################
# Temporarily write a content.xml with a known wrong version integer and a
# matching CHANGELOG so the ONLY failure is the mismatch between the two.
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Build a minimal repo skeleton that validate.sh can use for its version check.
# We only test the version-consistency fragment; use the real repo for everything
# else by pointing BASH_SOURCE at the real lib.

fake_content="$tmpdir/content.xml"
fake_changelog="$tmpdir/CHANGELOG.md"

cat > "$fake_content" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<content id="x4_gunnery_control" name="X4 Gunnery Control" version="99" date="2026-08-06"/>
EOF

cat > "$fake_changelog" <<'EOF'
# Changelog
## [0.20] - 2026-08-06
- entry
## [0.1.0] - 2026-08-03
- initial
EOF

# Source the helper and replicate the validation logic inline so we can test
# it with arbitrary files without running the full validate.sh (which touches
# real files and runs all other checks).

validate_version_consistency() {
  local content_file="$1" changelog_file="$2"

  local xml_ver
  xml_ver=$(grep -o 'version="[0-9]*"' "$content_file" | head -1 | grep -o '[0-9]*')

  local changelog_ver
  changelog_ver=$(grep -m1 '^## \[[0-9]' "$changelog_file" | grep -o '\[[^]]*\]' | tr -d '[]')

  local expected_int
  expected_int=$(x4_version_int "$changelog_ver")

  if [[ "$xml_ver" != "$expected_int" ]]; then
    echo "version mismatch: content.xml version=\"$xml_ver\" != CHANGELOG $changelog_ver -> $expected_int" >&2
    return 1
  fi
}

# Mismatched: content.xml=99, changelog says 0.20 -> 20
if validate_version_consistency "$fake_content" "$fake_changelog" 2>/dev/null; then
  echo "FAIL: version mismatch not detected (xml=99 vs changelog->20)" >&2
  exit 1
fi

# Matching: update content.xml to 20
cat > "$fake_content" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<content id="x4_gunnery_control" name="X4 Gunnery Control" version="20" date="2026-08-06"/>
EOF

if ! validate_version_consistency "$fake_content" "$fake_changelog" 2>&1; then
  echo "FAIL: matching versions reported as mismatch" >&2
  exit 1
fi

###############################################################################
# 5. package.sh VERSION vs content.xml mismatch
###############################################################################
# We can't easily swap content.xml, so verify the error message text when we
# call package.sh with a version whose integer differs from the real content.xml.
# The real content.xml currently has version="10" (0.1 -> 10).
# Passing 0.3 -> 30, which != 10, must fail.
real_xml_ver=$(content_xml_version)
# Find a two-part version whose integer != real_xml_ver
test_ver="0.99"
test_int=$(x4_version_int "$test_ver")
if [[ "$test_int" == "$real_xml_ver" ]]; then
  test_ver="1.00"
  test_int=$(x4_version_int "$test_ver")
fi

if ./scripts/package.sh "$test_ver" 2>/dev/null; then
  echo "FAIL: package.sh did not reject version $test_ver (int $test_int) mismatching content.xml (int $real_xml_ver)" >&2
  exit 1
fi

echo "version consistency checks passed"
