@echo off
chcp 65001 >nul
setlocal
title 启动 NapCat (QQ 机器人框架)

rem 从同目录 config.json 读取 NapCat 安装目录，避免隐私路径写死在脚本里
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "$c=Get-Content -LiteralPath '%~dp0config.json' -Raw -Encoding UTF8|ConvertFrom-Json; Write-Output $c.NapCatDir" 2^>nul`) do set "NAPCAT_DIR=%%i"
if "%NAPCAT_DIR%"=="" set "NAPCAT_DIR=C:\path\to\NapCat-QCE-Windows-x64"

if not exist "%NAPCAT_DIR%\launcher-user.bat" (
    echo [错误] 找不到 NapCat：%NAPCAT_DIR%
    echo 请修改同目录 config.json 里的 NapCatDir 字段。
    pause
    exit /b 1
)

echo ============================================
echo   启动 NapCat
echo ============================================
echo.
echo 注意：NapCat 必须由自己启动 QQ 才能注入。
echo       下面会先关闭当前已运行的 QQ 进程。
echo       关闭前请确认 QQ 里没有正在编辑的内容。
echo.
set /p GO="继续？(Y/N): "
if /i not "%GO%"=="Y" (
    echo 已取消。
    pause
    exit /b 0
)

echo.
echo [1/2] 关闭已运行的 QQ ...
taskkill /F /IM QQ.exe >nul 2>&1
taskkill /F /IM QQEX.exe >nul 2>&1
timeout /t 3 /nobreak >nul

echo [2/2] 通过 NapCat 启动 QQ ...
cd /d "%NAPCAT_DIR%"
call "%NAPCAT_DIR%\launcher-user.bat"

echo.
echo NapCat 窗口已退出。
echo 若登录成功，另开一个终端运行：
echo   powershell -ExecutionPolicy Bypass -File "%~dp0send-group-notice.ps1" -DryRun
pause