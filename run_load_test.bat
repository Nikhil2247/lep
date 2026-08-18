@echo off
setlocal
:: ============================================================
::  LEP Load Test Launcher  —  Bun Edition
::  Double-click to run. Edit PRESET below to pick load level.
:: ============================================================

:: ── PICK YOUR TEST LEVEL ─────────────────────────────────────
::   1 = Quick Baseline   20 VUs / 60s    <-- START HERE
::   2 = Medium Load      50 VUs / 120s
::   3 = Heavy Load      100 VUs / 300s
::   4 = Stress Test     200 VUs / 300s  (aggressive)
set PRESET=1

:: ── TARGET URL ───────────────────────────────────────────────
set URL=https://nagaland.lep.2026.vibha.org

:: ============================================================
echo.
echo  ============================================================
echo    LEP Load Test Launcher  --  Bun Edition
echo  ============================================================
echo.

:: -- Check Bun --
where bun >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] Bun is not installed or not in PATH.
    echo.
    echo  Install Bun on Windows:
    echo    1. Open PowerShell as Administrator
    echo    2. Run:  powershell -c "irm bun.sh/install.ps1 | iex"
    echo    3. Restart this window and try again.
    echo.
    echo  Or visit: https://bun.sh
    echo.
    pause
    exit /b 1
)
for /f "tokens=*" %%v in ('bun --version 2^>^&1') do echo  Bun v%%v detected.
echo.

:: -- Run selected preset --
if "%PRESET%"=="1" (
    echo  PRESET 1: Quick Baseline -- 20 VUs / 60s
    echo.
    bun load_test.js --url %URL% --vu 20 --duration 60 --ramp 5
)
if "%PRESET%"=="2" (
    echo  PRESET 2: Medium Load -- 50 VUs / 120s
    echo.
    bun load_test.js --url %URL% --vu 50 --duration 120 --ramp 15
)
if "%PRESET%"=="3" (
    echo  PRESET 3: Heavy Load -- 100 VUs / 300s
    echo.
    bun load_test.js --url %URL% --vu 100 --duration 300 --ramp 30
)
if "%PRESET%"=="4" (
    echo  PRESET 4: Stress Test -- 200 VUs / 300s (aggressive)
    echo.
    bun load_test.js --url %URL% --vu 200 --duration 300 --think 0.5 --ramp 30
)

echo.
echo  ============================================================
echo    Test complete.
echo  ============================================================
echo.
pause
endlocal
