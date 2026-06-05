@echo off
setlocal

set "PROJECT_DIR=%~dp0"
cd /d "%PROJECT_DIR%"

echo [Stardive Sandbox] Stopping existing Godot runtime...
taskkill /F /IM Godot_v4.6.3-stable_mono_win64.exe >nul 2>nul
taskkill /F /IM Godot_v4.6.3-stable_mono_win64_console.exe >nul 2>nul
taskkill /F /IM Godot_v4.6.3-stable_win64.exe >nul 2>nul
taskkill /F /IM Godot_v4.6.3-stable_win64_console.exe >nul 2>nul

timeout /T 1 /NOBREAK >nul

echo [Stardive Sandbox] Restarting runtime...
call "%PROJECT_DIR%start-game.bat"

endlocal
exit /b %ERRORLEVEL%
