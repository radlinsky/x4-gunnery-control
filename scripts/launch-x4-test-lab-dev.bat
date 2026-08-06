@echo off
setlocal EnableExtensions

rem X4 Gunnery Control Test Lab development launcher.
rem Installs the developer-only Test Lab extension, then hands off to
rem launch-x4-dev.bat which reinstalls the main mod and starts X4.
rem Usage: scripts\launch-x4-test-lab-dev.bat ["C:\path\to\X4 Foundations" or X4.exe]
rem All arguments and environment (X4GC_EXE, X4GC_GAME_ROOT, X4GC_NO_PAUSE) pass through.
rem
rem X4GC_INSTALL_TESTLAB tells install-dev.sh to also lay down the Test Lab
rem extension. WSLENV propagates it across the cmd -> wsl.exe boundary; without
rem that line the variable never reaches the installer running inside WSL.
set "X4GC_INSTALL_TESTLAB=1"
set "WSLENV=X4GC_INSTALL_TESTLAB:%WSLENV%"

call "%~dp0launch-x4-dev.bat" %*
exit /b %errorlevel%
