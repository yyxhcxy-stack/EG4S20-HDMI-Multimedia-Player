@echo off
chcp 65001 >nul
title 永久关闭驱动签名强制（需要先在BIOS中关闭Secure Boot）

echo ===================================================================
echo       安路 FPGA 下载器 - 永久关闭驱动签名强制配置工具
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

echo [1/3] 正在配置 Windows 引导项为免签名与测试模式...
bcdedit /set loadoptions DDISABLE_INTEGRITY_CHECKS
bcdedit /set nointegritychecks on
bcdedit /set testsigning on

if %errorLevel% neq 0 (
    echo.
    echo ===================================================================
    echo [提示] 命令执行被拦截！
    echo 原因：您的主板开启了 UEFI Secure Boot (安全启动)。
    echo 微软 Windows 11 规定：在安全启动开启时，禁止任何软件永久修改驱动签名规则。
    echo.
    echo 解决方法（只需操作一次）：
    echo 1. 重启电脑，开机连续按 F2 进入 BIOS 界面；
    echo 2. 按 F7 切换到高级模式 (Advanced Mode)；
    echo 3. 找到【Security】(安全性) -^>【Secure Boot】(安全启动)；
    echo 4. 将【Secure Boot Control】设置为【Disabled】(关闭)；
    echo 5. 按 F10 保存并退出，重新进入 Windows 系统；
    echo 6. 重新以管理员身份运行本脚本即可！
    echo ===================================================================
    echo.
    pause
    exit /b 1
)

echo.
echo [2/3] 正在预注册安路 DL-Cable 与 AL-Link 驱动...
pnputil.exe /add-driver "C:\fpga\driver\dl-cable\win10\cyusb.inf" /install
pnputil.exe /add-driver "C:\fpga\driver\al-link\win10\x64\anlocyusb.inf" /install

echo.
echo [3/3] 配置成功！
echo ===================================================================
echo Windows 11 已永久允许加载安路下载器驱动！
echo 重启电脑后将永久生效，以后正常开机即可直接烧录，无需再按 F7。
echo.
echo (若日后需要恢复默认签名规则，可运行【一键恢复默认签名_管理员运行.bat】)
echo ===================================================================
echo.
pause
