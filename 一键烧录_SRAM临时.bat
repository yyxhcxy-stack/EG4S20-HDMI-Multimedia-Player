@echo off
setlocal
echo ========================================================
echo   HX4S20 HDMI Player - SRAM JTAG Load
echo ========================================================

set SCRIPT_DIR=%~dp0
set BIT_FILE=%SCRIPT_DIR%HX4S20_HDMI_Player.bit

if not exist "%BIT_FILE%" (
    echo [ERROR] Cannot find: %BIT_FILE%
    exit /b 1
)

set BW_EXE=C:\fpga\bin\bw_commands_prompt.exe
if not exist "%BW_EXE%" if defined TD_HOME set BW_EXE=%TD_HOME%\bin\bw_commands_prompt.exe
if not exist "%BW_EXE%" if exist "D:\TD\bin\bw_commands_prompt.exe" set BW_EXE=D:\TD\bin\bw_commands_prompt.exe
if not exist "%BW_EXE%" if exist "C:\Anlogic\TD6.2.1\bin\bw_commands_prompt.exe" set BW_EXE=C:\Anlogic\TD6.2.1\bin\bw_commands_prompt.exe

if not exist "%BW_EXE%" (
    echo [ERROR] bw_commands_prompt.exe not found!
    exit /b 1
)

set TEMP_BIT=%TEMP%\fpga_temp.bit
copy /y "%BIT_FILE%" "%TEMP_BIT%" >nul
set BIT_FWD=%TEMP_BIT:\=/%
set TCL_FILE=%TEMP%\sram_dl.tcl
set TCL_FWD=%TCL_FILE:\=/%

(
echo list_cable
echo download -bit "%BIT_FWD%" -mode jtag
echo exit
) > "%TCL_FILE%"

echo Loading into EG4S20 SRAM...
"%BW_EXE%" "%TCL_FWD%"
set RES=%ERRORLEVEL%

if exist "%TCL_FILE%" del "%TCL_FILE%" >nul 2>&1
if exist "%TEMP_BIT%" del "%TEMP_BIT%" >nul 2>&1

if %RES% equ 0 (
    echo [SUCCESS] SRAM Load Finished! FPGA is running.
) else (
    echo [FAILED] Download error code: %RES%
)

if "%~1" neq "--no-pause" pause
exit /b %RES%
