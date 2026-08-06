#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

launcher=scripts/launch-x4-dev.bat
test -f "$launcher"

grep -Fq 'if not exist "%X4GC_EXE%" goto missing' "$launcher"
grep -Fq 'if defined X4GC_EXE goto environmentexe' "$launcher"
grep -Fq 'if defined X4GC_GAME_ROOT goto environment' "$launcher"
grep -Fq 'rem Set X4GC_NO_PAUSE=1 to skip the final pause.' "$launcher"
grep -Fq 'set "X4GC_KEEP_OPEN=1"' "$launcher"
grep -Fq 'if defined X4GC_NO_PAUSE set "X4GC_KEEP_OPEN="' "$launcher"
# type nul precheck must be gone
if grep -Fq '>>"%X4GC_LOG_FILE%" type nul' "$launcher"; then
  echo "FAIL: stale type nul precheck still present" >&2
  exit 1
fi
# Fixed-string match: *.bat is eol=crlf per .gitattributes, so avoid line anchors.
grep -Fq 'start "" /D "%X4GC_GAME_ROOT%" "%X4GC_EXE%" -prefersinglefiles -debug all -logfile debug.log' "$launcher"
grep -Fq 'Gunnery diagnostics will be written to:' "$launcher"
# logfailed block must be gone
if grep -Fq 'echo ERROR: Could not create or write the debug log file:' "$launcher"; then
  echo "FAIL: stale logfailed block still present" >&2
  exit 1
fi
grep -Fq 'if defined X4GC_KEEP_OPEN pause' "$launcher"
grep -Fq 'endlocal & exit /b %X4GC_EXIT_CODE%' "$launcher"
# 2^>nul inside for /f suppresses all results on Windows and must not come back
if grep -Fq '2^>nul' "$launcher"; then
  echo "FAIL: 2^>nul present in for /f command string" >&2
  exit 1
fi
grep -Fq 'echo You may also set X4GC_EXE to the full X4.exe path before running' "$launcher"
# -logfile's value must stay unquoted: -logfile "debug.log" produced no log at all.
# Explanatory rem lines may show the quoted form as a warning; real lines may not.
if grep -v '^ *rem ' "$launcher" | grep -Fq -- '-logfile "'; then
  echo "FAIL: quoted -logfile argument present outside explanatory rem text" >&2
  exit 1
fi
# userdata-directory resolution must be present
grep -Fq 'Egosoft\X4' "$launcher"
grep -Fq 'debug.log' "$launcher"

# Auto-reinstall block assertions
# Installer must be invoked before the log-directory resolution (launch block)
installer_line=$(grep -n 'wsl.exe -d %X4GC_DISTRO% -- "%X4GC_INSTALLER%"' "$launcher" | head -1 | cut -d: -f1)
logdir_line=$(grep -n 'rem Resolve the directory X4 will actually write the log into' "$launcher" | head -1 | cut -d: -f1)
if [[ -z "$installer_line" || -z "$logdir_line" ]]; then
  echo "FAIL: installer invocation or log-dir resolution block not found" >&2
  exit 1
fi
if [[ "$installer_line" -ge "$logdir_line" ]]; then
  echo "FAIL: installer invocation (line $installer_line) must come before log-dir resolution (line $logdir_line)" >&2
  exit 1
fi

# Every wsl.exe call outside rem lines must carry -d
if grep -v '^ *rem ' "$launcher" | grep -i 'wsl\.exe' | grep -iv -- '-d '; then
  echo "FAIL: a wsl.exe invocation outside rem lines is missing -d" >&2
  exit 1
fi

# installfailed error handler must be present
grep -Fq 'if errorlevel 1 goto installfailed' "$launcher"

# WSL UNC path substring guard must be present
grep -Fq '"\\wsl.localhost\"' "$launcher"

echo "Windows development launcher checks passed"
