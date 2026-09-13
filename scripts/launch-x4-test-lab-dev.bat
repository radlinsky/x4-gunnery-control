@echo off
setlocal EnableExtensions

set "X4GC_INSTALL_TESTLAB=1"
set "WSLENV=X4GC_INSTALL_TESTLAB:%WSLENV%"
set "X4GC_TAIL_LOG=1"

call "%~dp0launch-x4-dev.bat" %*
exit /b %errorlevel%
