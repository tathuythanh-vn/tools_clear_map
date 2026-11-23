@echo off
title Pokemon Auto-Clear - BlueStacks Bot

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%run_auto_clear.ps1"
if not exist "%PS_SCRIPT%" (
    echo [ERROR] Cannot find run_auto_clear.ps1
    echo Make sure run_auto_clear.ps1 is in the same folder as this bat file
    pause
    exit /b 1
)

:MENU
cls
echo ========================================================
echo       POKEMON AUTO-CLEAR  -  BLUESTACKS BOT
echo ========================================================
echo.
echo  [1] Run          - infinite auto-clear + VIT refill loop
echo  [2] Dry Run      - classify screens, log taps, tap nothing
echo  [3] Run N refills- stop after N refills
echo  [4] Calibrate    - capture screen + coordinate viewer
echo  [5] Self-Test    - verify tap safety guards (no ADB)
echo  [0] Exit
echo.
echo ========================================================
set "CHOICE="
set /p "CHOICE=Select option (0-5): "

if "%CHOICE%"==""  set "CHOICE=1"
if "%CHOICE%"=="0" exit /b 0
if "%CHOICE%"=="1" goto RUN
if "%CHOICE%"=="2" goto DRY_RUN
if "%CHOICE%"=="3" goto RUN_N
if "%CHOICE%"=="4" goto CALIBRATE
if "%CHOICE%"=="5" goto SELF_TEST
echo.
echo  Invalid choice, try again.
timeout /t 2 >nul
goto MENU

:: ---- Run (infinite) ----
:RUN
cls
echo [RUNNING] Auto-clear loop - clears raids, refills VIT with Hamburger, forever...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
goto DONE

:: ---- Dry Run ----
:DRY_RUN
cls
echo [RUNNING] Dry run - classifies screens and logs intended taps only...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -DryRun
goto DONE

:: ---- Run N refills ----
:RUN_N
cls
set "N_REFILLS="
set /p "N_REFILLS=Stop after how many refills? (Enter = 10): "
if "%N_REFILLS%"=="" set "N_REFILLS=10"
echo.
echo [RUNNING] Auto-clear loop - stop after %N_REFILLS% refill(s)...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -MaxCycles %N_REFILLS%
goto DONE

:: ---- Calibrate ----
:CALIBRATE
cls
echo [CALIBRATE] Capturing screen and opening coordinate viewer...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Calibrate
goto DONE

:: ---- Self-Test ----
:SELF_TEST
cls
echo [SELF-TEST] Verifying tap safety guards...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -SelfTest
goto DONE

:DONE
echo.
echo ========================================================
echo              EXECUTION FINISHED
echo ========================================================
echo.
pause
goto MENU
