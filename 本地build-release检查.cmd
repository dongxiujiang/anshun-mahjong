@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"

set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" set "PS_EXE=powershell.exe"

echo ============================================
echo  本地 Build-Release 预检查
echo ============================================
echo 项目路径：%CD%
echo.
echo 检查内容：
echo   1. Godot 导入检查
echo   2. 导出配置验证
echo   3. 核心回归测试（41项，含未叫牌出牌鸡、杠中鸡补付）
echo   4. 网络联机测试
echo   5. 在线房间测试
echo   6. 断线重连测试
echo.
echo 进度会实时显示，完整日志保存在：
echo   build\local-build-release\[时间戳]
echo.
echo 开始检查...
echo.

"%PS_EXE%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0tools\release\local_build_release.ps1" -Mode Check %*

set "exit_code=%ERRORLEVEL%"
if "%exit_code%"=="0" goto passed

echo.
echo ============================================
echo  × 检查失败
echo ============================================
echo 请查看上方错误信息和最新的日志目录：
echo   build\local-build-release\[最新时间戳]
echo.
echo 重点日志文件：
echo   - core_tests.log       （核心回归）
echo   - network_tests.log    （网络测试）
echo   - reconnect_tests.log  （断线重连）
echo   - import.log           （Godot导入）
echo ============================================
goto done

:passed
echo.
echo ============================================
echo  ✓ 检查通过！
echo ============================================
echo 所有测试已通过，可以继续云端 Build release 流程。
echo ============================================

:done
echo.
pause
exit /b %exit_code%
