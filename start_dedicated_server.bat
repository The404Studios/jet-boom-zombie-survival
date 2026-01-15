@echo off
REM Zombie Survival Dedicated Server Launch Script
REM This script starts the dedicated game server on Windows

REM Default configuration
if "%SERVER_NAME%"=="" set SERVER_NAME=Zombie Survival Server
if "%SERVER_PORT%"=="" set SERVER_PORT=7777
if "%MAX_PLAYERS%"=="" set MAX_PLAYERS=8
if "%REGION%"=="" set REGION=us-east
if "%MAP%"=="" set MAP=arena_01
if "%DIFFICULTY%"=="" set DIFFICULTY=Normal
if "%GAME_MODE%"=="" set GAME_MODE=survival

REM Paths
set SCRIPT_DIR=%~dp0
if "%GODOT_EXECUTABLE%"=="" set GODOT_EXECUTABLE=godot.exe

REM Display configuration
echo ============================================
echo   Zombie Survival Dedicated Server
echo ============================================
echo Server Name: %SERVER_NAME%
echo Port: %SERVER_PORT%
echo Max Players: %MAX_PLAYERS%
echo Region: %REGION%
echo Map: %MAP%
echo Difficulty: %DIFFICULTY%
echo Game Mode: %GAME_MODE%
echo ============================================

REM Check if project exists
if not exist "%SCRIPT_DIR%project.godot" (
    echo Error: project.godot not found at: %SCRIPT_DIR%
    pause
    exit /b 1
)

REM Start the dedicated server
echo Starting dedicated server...

%GODOT_EXECUTABLE% ^
    --path "%SCRIPT_DIR%" ^
    --headless ^
    --dedicated ^
    --server-name "%SERVER_NAME%" ^
    --port %SERVER_PORT% ^
    --max-players %MAX_PLAYERS% ^
    --region "%REGION%" ^
    --map "%MAP%" ^
    --difficulty "%DIFFICULTY%" ^
    --game-mode "%GAME_MODE%"

set EXIT_CODE=%ERRORLEVEL%

if %EXIT_CODE% neq 0 (
    echo Server exited with code: %EXIT_CODE%
)

pause
exit /b %EXIT_CODE%
