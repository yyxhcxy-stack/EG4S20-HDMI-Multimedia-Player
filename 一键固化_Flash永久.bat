@echo off
setlocal
chcp 65001 >nul
echo ========================================================
echo   HX4S20 HDMI Player - SPI Flash 永久固化 (上电不丢失)
echo ========================================================
echo.

set SCRIPT_DIR=%~dp0
set BIT_FILE=%SCRIPT_DIR%HX4S20_HDMI_Player.bit

if not exist "%BIT_FILE%" (
    echo [ERROR] 未找到待固化的位流文件: %BIT_FILE%
    exit /b 1
)

set BW_EXE=C:\fpga\bin\bw_commands_prompt.exe
if not exist "%BW_EXE%" if defined TD_HOME set BW_EXE=%TD_HOME%\bin\bw_commands_prompt.exe
if not exist "%BW_EXE%" if exist "D:\TD\bin\bw_commands_prompt.exe" set BW_EXE=D:\TD\bin\bw_commands_prompt.exe
if not exist "%BW_EXE%" if exist "C:\Anlogic\TD6.2.1\bin\bw_commands_prompt.exe" set BW_EXE=C:\Anlogic\TD6.2.1\bin\bw_commands_prompt.exe
if not exist "%BW_EXE%" if exist "C:\Anlogic\TD6.2\bin\bw_commands_prompt.exe" set BW_EXE=C:\Anlogic\TD6.2\bin\bw_commands_prompt.exe

if not exist "%BW_EXE%" (
    echo [ERROR] 未能自动定位安路 BitWriter bw_commands_prompt.exe
    exit /b 1
)

echo [检测到下载器] %BW_EXE%
echo [待固化位流]   %BIT_FILE%
echo.

set TEMP_BIT=%TEMP%\fpga_flash_temp.bit
copy /y "%BIT_FILE%" "%TEMP_BIT%" >nul
set BIT_FWD=%TEMP_BIT:\=/%
set TCL_FILE=%TEMP%\flash_program.tcl

(
echo list_cable
echo download -bit "%BIT_FWD%" -mode program_spi
echo exit
) > "%TCL_FILE%"

echo 正在烧录位流至板载 SPI Flash (约需 30~50 秒)...
type "%TCL_FILE%" | "%BW_EXE%"
set RES=%ERRORLEVEL%

if exist "%TCL_FILE%" del "%TCL_FILE%" >nul 2>&1
if exist "%TEMP_BIT%" del "%TEMP_BIT%" >nul 2>&1

echo.
if %RES% equ 0 (
    echo ========================================================
    echo [成功] SPI Flash 固化写入完成！
    echo 现在断电重启或按开发板 Config 键即可自动脱机加载运行！
    echo ========================================================
) else (
    echo [失败] 固化失败，错误返回码: %RES%
)

if "%~1" neq "--no-pause" pause
exit /b %RES%
