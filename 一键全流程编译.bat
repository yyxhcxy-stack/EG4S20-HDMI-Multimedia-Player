@echo off
chcp 65001 >nul
echo Compiling THIS delivery folder in an isolated ASCII build directory.
echo Candidate files: output\extension_v2_6 (original bitstream is preserved).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build_extension.ps1"
set "BUILD_RESULT=%ERRORLEVEL%"
if "%~1" neq "--no-pause" pause
exit /b %BUILD_RESULT%
