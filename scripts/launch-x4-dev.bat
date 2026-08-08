@echo off
setlocal EnableExtensions

rem X4 Gunnery Control development launcher.
rem Usage: scripts\launch-x4-dev.bat ["C:\path\to\X4 Foundations" or X4.exe]
rem Set X4GC_NO_PAUSE=1 to skip the final pause.
rem
rem Logging notes - all four points were established on Windows, do not "tidy" them:
rem 1. -logfile is required. -debug all on its own produces no log whatsoever.
rem 2. The value must be UNQUOTED. Do not add quotes here: -logfile debug.log works,
rem    -logfile "debug.log" produced no log at all.
rem 3. The value must be a bare filename. An absolute path makes X4 write to a file
rem    literally named INVALID.FILENAME inside its userdata folder.
rem 4. X4 truncates debug.log on every launch, so each run starts clean and the
rem    previous run's log is lost.
rem The log lands in the X4 userdata folder: Documents\Egosoft\X4\<id>\debug.log

set "X4GC_EXE="
set "X4GC_EXIT_CODE=0"
set "X4GC_KEEP_OPEN=1"
if defined X4GC_NO_PAUSE set "X4GC_KEEP_OPEN="

if not "%~1"=="" goto argument
if defined X4GC_EXE goto environmentexe
if defined X4GC_GAME_ROOT goto environment

if exist "%ProgramFiles(x86)%\Steam\steamapps\common\X4 Foundations\X4.exe" (
  set "X4GC_GAME_ROOT=%ProgramFiles(x86)%\Steam\steamapps\common\X4 Foundations"
  goto folder
)

if exist "%ProgramFiles%\Steam\steamapps\common\X4 Foundations\X4.exe" (
  set "X4GC_GAME_ROOT=%ProgramFiles%\Steam\steamapps\common\X4 Foundations"
  goto folder
)

if exist "%ProgramFiles(x86)%\GOG Galaxy\Games\X4 Foundations\X4.exe" (
  set "X4GC_GAME_ROOT=%ProgramFiles(x86)%\GOG Galaxy\Games\X4 Foundations"
  goto folder
)

echo X4 was not found in a default Steam or GOG location.
set /p "X4GC_GAME_ROOT=Paste the X4 Foundations installation folder: "
if not defined X4GC_GAME_ROOT goto missing
set "X4GC_GAME_ROOT=%X4GC_GAME_ROOT:"=%"
goto folder

:argument
if /I "%~x1"==".exe" goto executable
set "X4GC_GAME_ROOT=%~f1"
goto folder

:environment
set "X4GC_GAME_ROOT=%X4GC_GAME_ROOT:"=%"
for %%I in ("%X4GC_GAME_ROOT%") do set "X4GC_GAME_ROOT=%%~fI"
goto folder

:environmentexe
set "X4GC_EXE=%X4GC_EXE:"=%"
for %%I in ("%X4GC_EXE%") do set "X4GC_EXE=%%~fI"
for %%I in ("%X4GC_EXE%") do set "X4GC_GAME_ROOT=%%~dpI"
goto validate

:executable
set "X4GC_EXE=%~f1"
for %%I in ("%X4GC_EXE%") do set "X4GC_GAME_ROOT=%%~dpI"
goto validate

:folder
set "X4GC_EXE=%X4GC_GAME_ROOT%\X4.exe"

:validate
if not exist "%X4GC_EXE%" goto missing

rem Auto-reinstall: wipe and reinstall the mod before launch so stale code never runs.
rem -d %X4GC_DISTRO% is mandatory: this machine's default WSL distro is docker-desktop,
rem not Ubuntu. A bare wsl.exe runs there where /mnt/c does not exist and the repo is
rem absent. Every wsl.exe invocation below must carry -d %X4GC_DISTRO%.
set "X4GC_DP=%~dp0"
if /I not "%X4GC_DP:~0,16%"=="\\wsl.localhost\" goto skipinstall

for /f "tokens=1,2,* delims=\" %%a in ("%X4GC_DP%") do (
  set "X4GC_DISTRO=%%b"
  set "X4GC_REPO_REL=%%c"
)
set "X4GC_REPO_REL=%X4GC_REPO_REL:\=/%"
set "X4GC_INSTALLER=/%X4GC_REPO_REL%install-dev.sh"

for /f "delims=" %%I in ('wsl.exe -d %X4GC_DISTRO% wslpath -a "%X4GC_GAME_ROOT%"') do set "X4GC_GAME_WSL=%%I"

echo Reinstalling loose development files...
wsl.exe -d %X4GC_DISTRO% -- "%X4GC_INSTALLER%" "%X4GC_GAME_WSL%"
if errorlevel 1 goto installfailed
goto postinstall

:skipinstall
echo launcher is not on a \\wsl.localhost path; skipping automatic reinstall

:postinstall

rem Resolve the directory X4 will actually write the log into.
set "X4GC_LOG_DIR="
if exist "%USERPROFILE%\Documents\Egosoft\X4" (
  for /f "delims=" %%I in ('dir /b /ad /o-d "%USERPROFILE%\Documents\Egosoft\X4" ^| findstr /r "^[0-9][0-9]*$"') do (
    set "X4GC_LOG_DIR=%USERPROFILE%\Documents\Egosoft\X4\%%I"
    goto logdirfound
  )
)
if defined OneDrive (
  if exist "%OneDrive%\Documents\Egosoft\X4" (
    for /f "delims=" %%I in ('dir /b /ad /o-d "%OneDrive%\Documents\Egosoft\X4" ^| findstr /r "^[0-9][0-9]*$"') do (
      set "X4GC_LOG_DIR=%OneDrive%\Documents\Egosoft\X4\%%I"
      goto logdirfound
    )
  )
)
goto logdirunknown

:logdirfound
echo Launching:
echo   "%X4GC_EXE%" -prefersinglefiles -debug all -logfile debug.log
echo Gunnery diagnostics will be written to:
echo   %X4GC_LOG_DIR%\debug.log
echo X4 truncates debug.log on every launch; the previous run's log is lost.
goto launch

:logdirunknown
echo Launching:
echo   "%X4GC_EXE%" -prefersinglefiles -debug all -logfile debug.log
echo Gunnery diagnostics will be written to:
echo   ^<X4 userdata folder^>\debug.log   (could not auto-detect; look under Documents\Egosoft\X4\)
echo X4 truncates debug.log on every launch; the previous run's log is lost.

:launch
rem If X4GC_TAIL_LOG is set, open a second console window running tail-gunnery-log.sh
rem so the developer sees [X4GC] lines live without starting a second terminal by hand.
rem
rem Started BEFORE X4, deliberately. The tailer skips whatever the previous run
rem left in the log and prints only what arrives after, so it has to be watching
rem before X4 truncates. Launched the other way round it can prime itself on the
rem new, already-truncated log and silently swallow the initializing lines.
rem
rem X4GC_DISTRO and X4GC_REPO_REL are only available when we parsed a \\wsl.localhost\ path
rem above; if that was skipped (skipinstall branch) we cannot build the WSL script path.
rem X4GC_TAIL_LOG is consumed here in Windows — it does not need to cross into WSL, so
rem it intentionally does NOT appear in WSLENV.
if not defined X4GC_TAIL_LOG goto notail
if not defined X4GC_DISTRO (
  echo Note: X4GC_TAIL_LOG set but launcher is not on a \\wsl.localhost path; tail not started.
  goto notail
)
set "X4GC_TAILER=/%X4GC_REPO_REL%tail-gunnery-log.sh"
start "X4 Gunnery Log" wsl.exe -d %X4GC_DISTRO% -- "%X4GC_TAILER%"
:notail

start "" /D "%X4GC_GAME_ROOT%" "%X4GC_EXE%" -prefersinglefiles -debug all -logfile debug.log
if errorlevel 1 goto failed

set "X4GC_EXIT_CODE=0"
goto finish

:missing
echo.
echo ERROR: X4.exe was not found.
echo Usage: scripts\launch-x4-dev.bat "C:\path\to\X4 Foundations"
echo    or: scripts\launch-x4-dev.bat "C:\path\to\X4 Foundations\X4.exe"
echo.
echo You may also set X4GC_EXE to the full X4.exe path before running
echo this launcher without an argument.
echo You may also set X4GC_GAME_ROOT to the installation folder before running
echo this launcher without an argument.
set "X4GC_EXIT_CODE=2"
goto finish

:installfailed
echo ERROR: install-dev.sh failed; X4 was not launched.
echo The game was not started because it would have run stale mod code.
echo Fix the install error above, then re-run the launcher.
set "X4GC_EXIT_CODE=4"
goto finish

:failed
echo ERROR: Windows could not start X4. Error level %errorlevel%.
set "X4GC_EXIT_CODE=3"
goto finish

:finish
if defined X4GC_KEEP_OPEN pause
endlocal & exit /b %X4GC_EXIT_CODE%
