@echo off
rem Build a validated local zip. Pass --target BRANCH for detached checkouts.
rem Set EUI_PYTHON to the validated Python 3 executable; requires Git Bash, svn and zip.
setlocal

set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%BASH%" set "BASH=bash"
if "%BASH%"=="bash" where bash >nul 2>nul || (echo Git for Windows not found: install it, plus svn and zip, then run this again.& exit /b 1)

"%BASH%" "%~dp0release.sh" %*
exit /b %ERRORLEVEL%
