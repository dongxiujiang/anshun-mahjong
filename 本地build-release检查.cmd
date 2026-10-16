@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\release\local_build_release.ps1" -Mode Check %*
set "exit_code=%ERRORLEVEL%"
if "%exit_code%"=="0" goto passed
echo.
echo 本地检查失败，请查看上面的错误和 build\local-build-release 日志。
goto done
:passed
echo.
echo 本地检查通过，可以运行云端 Build release。
:done
pause
exit /b %exit_code%
