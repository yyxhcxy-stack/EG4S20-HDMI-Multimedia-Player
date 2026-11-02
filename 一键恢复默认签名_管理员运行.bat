@echo off
chcp 65001 >nul
title 恢复 Windows 默认驱动签名验证

echo ===================================================================
echo       Windows 11 恢复系统默认驱动签名验证规则
echo ===================================================================
echo.

rem 检查管理员权限
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [错误] 请右键点击本脚本，选择【以管理员身份运行】！
    echo.
    pause
    exit /b 1
)

echo 正在恢复 Windows 官方默认安全策略...
bcdedit /deletevalue loadoptions
bcdedit /set nointegritychecks off
bcdedit /set testsigning off

echo.
echo ===================================================================
echo 已恢复 Windows 默认驱动签名验证！
echo 重启电脑后系统将回到默认安全状态。
echo ===================================================================
echo.
pause
