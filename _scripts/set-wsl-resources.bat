@echo off
setlocal
title Configure WSL2 Host Resources

echo ==========================================================
echo        Launching WSL2 Resource Adjuster
echo ==========================================================
echo.

:: Get directory where this .bat is located (resolves UNC and local paths)
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%set-wsl-resources.ps1"

if not exist "%PS_SCRIPT%" (
    echo [ERROR] Could not find set-wsl-resources.ps1 at:
    echo "%PS_SCRIPT%"
    echo.
    pause
    exit /b 1
)

:: Run PowerShell with ExecutionPolicy Bypass and Unblock-File
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { Unblock-File -Path '%PS_SCRIPT%' -ErrorAction SilentlyContinue; & '%PS_SCRIPT%' }"

echo.
pause
endlocal
