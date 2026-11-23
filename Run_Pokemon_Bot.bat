@echo off
title Pokemon Stage Runner - BlueStacks Bot

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%run_pokemon_stages.ps1"
if not exist "%PS_SCRIPT%" (
    set "PS_SCRIPT=%SCRIPT_DIR%leetcode\run_pokemon_stages.ps1"
)
if not exist "%PS_SCRIPT%" (
    echo [ERROR] Cannot find run_pokemon_stages.ps1
    echo Make sure run_pokemon_stages.ps1 is in the same folder as this bat file
    echo or inside a subfolder named "leetcode".
    pause
    exit /b 1
)

:MENU
cls
echo ========================================================
echo       POKEMON STAGE RUNNER  -  BLUESTACKS BOT
echo ========================================================
echo.
echo  [1] Quick Run      - currently open map, single chapter, skip cleared
echo  [2] Custom Run     - choose map, mode, stages
echo  [3] Auto-Chain Run - clear whenever it can (auto-clears map and chains to next until locked)
echo  [4] List all maps
echo  [0] Exit
echo.
echo ========================================================
set "CHOICE="
set /p "CHOICE=Select option (0-4): "

if "%CHOICE%"==""  set "CHOICE=1"
if "%CHOICE%"=="0" exit /b 0
if "%CHOICE%"=="1" goto QUICK_RUN
if "%CHOICE%"=="2" goto CUSTOM_RUN
if "%CHOICE%"=="3" goto CHAIN_RUN
if "%CHOICE%"=="4" goto LIST_MAPS
echo.
echo  Invalid choice, try again.
timeout /t 2 >nul
goto MENU

:: ---- Quick Run (no map arg - uses whatever is open) ----
:QUICK_RUN
cls
echo [RUNNING] Quick Run - currently open map, all stages, skip cleared...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -StartStage 1 -EndStage 0 -SkipCleared
goto DONE

:: ---- Auto-Chain Run (clears current map & chains to next until locked) ----
:CHAIN_RUN
cls
echo [RUNNING] Auto-Chain Run - clear maps continuously, skip cleared, stop when locked...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -StartStage 1 -EndStage 0 -SkipCleared -Chain
goto DONE

:: ---- List Maps ----
:LIST_MAPS
cls
echo Listing all available maps...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -ListMaps
goto DONE

:: ---- Custom Run ----
:CUSTOM_RUN
cls
echo --- Custom Stage Runner ---
echo.
set "CUST_MAP="
set /p "CUST_MAP=Map name (blank = use already-open map): "
set "CUST_MODE="
set /p "CUST_MODE=Mode - Normal or Hard (Enter = Normal): "
if "%CUST_MODE%"=="" set "CUST_MODE=Normal"
set "CUST_START="
set /p "CUST_START=Start Stage (Enter = 1): "
if "%CUST_START%"=="" set "CUST_START=1"
set "CUST_END="
set /p "CUST_END=End Stage  (Enter = 0 = all to chapter end): "
if "%CUST_END%"=="" set "CUST_END=0"
set "CUST_SKIP="
set /p "CUST_SKIP=Skip already cleared stages? Y/N (Enter = Y): "
if "%CUST_SKIP%"=="" set "CUST_SKIP=Y"

set "CUST_CHAIN="
set /p "CUST_CHAIN=Auto-chain to next maps when finished? Y/N (Enter = N): "
if "%CUST_CHAIN%"=="" set "CUST_CHAIN=N"

set "SKIP_PARAM="
if /i "%CUST_SKIP%"=="Y" set "SKIP_PARAM=-SkipCleared"

set "CHAIN_PARAM="
if /i "%CUST_CHAIN%"=="Y" set "CHAIN_PARAM=-Chain"

set "MAP_PARAM="
if not "%CUST_MAP%"=="" set "MAP_PARAM=-MapName ""%CUST_MAP%"""

echo.
echo [RUNNING] Starting custom run...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %MAP_PARAM% -Mode "%CUST_MODE%" -StartStage %CUST_START% -EndStage %CUST_END% %SKIP_PARAM% %CHAIN_PARAM%
goto DONE

:DONE
echo.
echo ========================================================
echo              EXECUTION FINISHED
echo ========================================================
echo.
pause
goto MENU