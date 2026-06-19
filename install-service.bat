@echo off
setlocal EnableExtensions

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process -FilePath '%~f0' -WorkingDirectory '%~dp0' -Verb RunAs -Wait -PassThru; exit $p.ExitCode"
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-service.ps1"
)
set "EXIT_CODE=%errorlevel%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo Installation failed with exit code %EXIT_CODE%.
) else (
    echo Installation completed successfully.
)
pause
exit /b %EXIT_CODE%
