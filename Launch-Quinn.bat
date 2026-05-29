@echo off
REM Quinn Optimizer Toolkit Launcher
REM Launches the app with hidden PowerShell window for a clean user experience

setlocal enabledelayedexpansion

REM Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"

REM Run PowerShell in hidden window
powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -STA -File "%SCRIPT_DIR%src\Intro\Intro.ps1"

REM When Quinn closes, return to system32 directory
REM Use %SystemRoot% so this works on machines where Windows is not on C:.
cd /d "%SystemRoot%\System32"
cls
echo Quinn Optimizer Toolkit closed.

