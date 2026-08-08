#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
actual=$(./scripts/parse-testlab-log.sh tests/fixtures/testlab.log)
expected=$(<tests/fixtures/testlab.csv)
if [[ "$actual" != "$expected" ]]; then
  echo "test-lab log parser output differed from fixture" >&2
  exit 1
fi
echo "testlab log parser tests passed"
