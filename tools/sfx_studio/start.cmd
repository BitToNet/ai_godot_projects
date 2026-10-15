@echo off
rem ===========================================================================
rem  Sfx Studio launcher -- double-click this file, or run it from a cmd prompt.
rem
rem  It only wraps start.ps1 (same folder): locate PowerShell -> pass every
rem  switch through -> surface the exit code. All real work lives in start.ps1.
rem
rem  WHY THIS FILE IS 7-BIT ASCII, AND WHY IT NEVER CALLS chcp:
rem    * cmd decodes a .cmd file with the *active console code page*, so Chinese
rem      text here would only display correctly if the file held GBK bytes --
rem      machine-specific, and unreadable in git diff / code review. Every
rem      Chinese message the user sees comes from start.ps1 (saved as UTF-8 with
rem      BOM, correct under Windows PowerShell 5.1) and from README.md.
rem    * chcp 65001 would *garble* start.ps1's output instead of fixing it:
rem      PowerShell 5.1 writes non-ASCII through the console code page.
rem  Keep this file ASCII, keep the code page alone.
rem
rem  Usage:
rem    start.cmd                    default port 8787, opens the browser
rem    start.cmd -Port 8790         any start.ps1 switch is passed through
rem    start.cmd -NoOpen -SkipExport
rem  Ending it: just close this window (Ctrl+C also works; cmd then asks Y/N).
rem ===========================================================================
setlocal
set "PS1=%~dp0start.ps1"

if not exist "%PS1%" (
	echo [X] start.ps1 is missing next to this launcher: "%PS1%"
	pause
	exit /b 1
)

rem Pick a PowerShell host: 5.1 ships with Windows, pwsh is the fallback.
set "PSEXE="
for %%P in (powershell.exe pwsh.exe) do (
	if not defined PSEXE (
		where %%P >nul 2>nul && set "PSEXE=%%P"
	)
)
if not defined PSEXE (
	echo [X] Neither powershell.exe nor pwsh.exe was found on PATH.
	pause
	exit /b 1
)

title Sfx Studio - Warband Strategic Map
echo Sfx Studio: export preview audio - generate manifest - start local server
echo (the browser opens by itself; close this window to stop the server)
echo.

"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"

rem 0 = stopped by Ctrl+C / window close in the normal way -> stay quiet.
if "%RC%"=="0" goto :done
if "%RC%"=="130" goto :done
if "%RC%"=="3221225786" goto :done
if "%RC%"=="-1073741510" goto :done

echo.
echo [X] Launcher exited with code %RC%.
echo     Run it from a cmd prompt to read the full output, for example:
echo         "%~dp0start.cmd" -NoOpen
pause

:done
exit /b %RC%