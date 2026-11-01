@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\learning.ps1" %*
exit /b %errorlevel%
