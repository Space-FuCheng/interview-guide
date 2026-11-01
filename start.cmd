@echo off
call "%~dp0dev.cmd" start
set "startup_exit=%errorlevel%"
echo.
echo Press any key to close this launcher window. Started services keep running.
pause >nul
exit /b %startup_exit%
