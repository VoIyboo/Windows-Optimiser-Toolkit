@echo off
setlocal DisableDelayedExpansion
powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-local.ps1"
exit /b %errorlevel%
