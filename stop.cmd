@echo off
call "%~dp0dev.cmd" stop-all
set "stop_exit=%errorlevel%"
echo.
echo Press any key to close this window.
pause >nul
exit /b %stop_exit%
