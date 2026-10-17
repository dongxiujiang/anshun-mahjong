@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"

set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" set "PS_EXE=powershell.exe"
echo ==== Local build-release preflight ====
echo Project: %CD%
echo The check runs import, export configuration, AI 50-round regression, and network tests.
echo Progress is printed live; full logs are saved under build\local-build-release.
echo.

"%PS_EXE%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0tools\release\local_build_release.ps1" -Mode Check %*
set "exit_code=%ERRORLEVEL%"
if "%exit_code%"=="0" goto passed
echo.
echo Local preflight failed. Review the error above and the latest build\local-build-release log directory.
goto done
:passed
echo.
echo Local preflight passed. It is ready for the cloud Build release workflow.
:done
echo.
pause
exit /b %exit_code%