@echo off
REM Quinn Optimiser Toolkit Launcher
REM Launches the local runner in a hidden PowerShell window for consistent logging and startup behaviour.

setlocal enabledelayedexpansion

REM Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"

REM Run the local launcher instead of calling Intro.ps1 directly.
REM This keeps the batch path aligned with run-local.ps1 startup logging and validation.
powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run-local.ps1"

REM When Quinn closes, return to system32 directory
REM Use %SystemRoot% so this works on machines where Windows is not on C:.
cd /d "%SystemRoot%\System32"
cls
echo Quinn Optimiser Toolkit closed.
