#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib-release.sh
source scripts/lib-release.sh

# Check the effective tracked tree against the review base, including committed,
# staged, and unstaged work. In CI, the PR base SHA is supplied by the workflow
# so this is the full PR diff rather than a shallow-checkout guess.
if [[ -n "${X4GC_DIFF_BASE:-}" ]]; then
  whitespace_base=$X4GC_DIFF_BASE
elif git rev-parse --verify -q develop >/dev/null; then
  whitespace_base=$(git merge-base develop HEAD)
elif git rev-parse --verify -q origin/develop >/dev/null; then
  whitespace_base=$(git merge-base origin/develop HEAD)
else
  whitespace_base=""
  echo "warning: cannot find develop; checking staged and unstaged whitespace only" >&2
fi
if [[ -n "$whitespace_base" ]]; then
  git diff --check "$whitespace_base"
fi
git diff --cached --check
git diff --check

xmllint --noout content.xml ui.xml t/*.xml md/*.xml testlab/x4_gunnery_control_testlab/content.xml testlab/x4_gunnery_control_testlab/ui.xml testlab/x4_gunnery_control_testlab/t/*.xml
if command -v luac5.1 >/dev/null; then
  for file in ui/*.lua testlab/x4_gunnery_control_testlab/ui/*.lua tests/*.lua; do luac5.1 -p "$file"; done
elif command -v luac >/dev/null; then
  for file in ui/*.lua testlab/x4_gunnery_control_testlab/ui/*.lua tests/*.lua; do luac -p "$file"; done
else
  echo "warning: Lua compiler unavailable; skipped Lua syntax validation" >&2
fi
if command -v lua5.1 >/dev/null; then for file in tests/*.lua; do lua5.1 "$file"; done
elif command -v lua >/dev/null; then for file in tests/*.lua; do lua "$file"; done
else echo "warning: Lua runtime unavailable; skipped unit tests" >&2; fi
./scripts/check-coverage.sh
if command -v shellcheck >/dev/null; then
  shellcheck scripts/*.sh tests/*.sh .agents/hooks/*.sh
else
  echo "warning: shellcheck unavailable; skipped shell validation" >&2
fi
for file in tests/*.sh; do "$file"; done
# Line 19 runs the test scripts directly, so a .sh committed as 100644 fails
# validation on a fresh clone (it only worked where a local chmod +x was left).
if git ls-files -s '*.sh' | grep -v '^100755'; then
  echo "the shell scripts above are not executable; git update-index --chmod=+x them" >&2
  exit 1
fi
# .github/prompts/release.prompt.md must be a real file (not a symlink) that
# matches .agents/release.agent.md exactly. On Windows checkouts without symlink
# support Git would materialise a symlink as a text file containing the path,
# so VS Code would see no prompt content. Keeping them in sync is enforced here.
if [[ -L .github/prompts/release.prompt.md ]]; then
  echo ".github/prompts/release.prompt.md is a symlink; replace it with a real copy of .agents/release.agent.md" >&2
  exit 1
fi
if ! diff -q .agents/release.agent.md .github/prompts/release.prompt.md >/dev/null 2>&1; then
  echo ".github/prompts/release.prompt.md has drifted from .agents/release.agent.md; copy the source to the prompt file" >&2
  exit 1
fi
if git ls-files | grep -Eq '(^|/)(__folder_managed_by_vortex|.*\.(cat|dat)|debug\.log|x4-gunnery-control-debug\.log)$'; then
  echo "forbidden generated or Vortex files are tracked" >&2
  exit 1
fi
# release.yml passes this to action-gh-release's body_path; a missing file fails
# the release job after the tag is already pushed, which is annoying to undo.
if [[ ! -s release/RELEASE_NOTES.md ]]; then
  echo "release/RELEASE_NOTES.md is missing or empty; release.yml uses it as the release body" >&2
  exit 1
fi
grep -q 'id="x4_gunnery_control"' content.xml
# Must stay optional: UI Extensions has a different id on Nexus and on the
# Workshop, so a hard dependency disables us for whoever installed the other one.
grep -q 'id="kuerteeUIExtensionsAndHUD" version="900" optional="true"' content.xml
xml_ver=$(content_xml_version)
changelog_ver=$(grep -m1 '^## \[[0-9][^]]*\]' CHANGELOG.md | grep -o '\[[^]]*\]' | tr -d '[]')
if [[ ! "$changelog_ver" =~ ^(0|[1-9][0-9]*)\.[0-9][0-9]$ ]]; then
  echo "version mismatch: CHANGELOG.md newest heading [$changelog_ver] is not MAJOR.MINOR with a two-digit minor; content.xml version=\"$xml_ver\"" >&2
  exit 1
fi
expected_int=$(x4_version_int "$changelog_ver")
if [[ "$xml_ver" != "$expected_int" ]]; then
  echo "version mismatch: content.xml version=\"$xml_ver\" != CHANGELOG.md $changelog_ver -> $expected_int" >&2
  exit 1
fi
echo "validation passed"
