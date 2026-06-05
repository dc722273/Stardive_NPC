@echo off
setlocal

set "PROJECT_DIR=%~dp0"
cd /d "%PROJECT_DIR%"

if not defined GODOT_CONSOLE_EXE (
  if exist "D:\Codex\Godot_v4.6.3-stable_mono_win64\Godot_v4.6.3-stable_mono_win64\Godot_v4.6.3-stable_mono_win64_console.exe" (
    set "GODOT_CONSOLE_EXE=D:\Codex\Godot_v4.6.3-stable_mono_win64\Godot_v4.6.3-stable_mono_win64\Godot_v4.6.3-stable_mono_win64_console.exe"
  )
)

echo [Stardive Sandbox] Starting Godot project...
call "%PROJECT_DIR%tools\godot\godot.cmd" %*

endlocal
exit /b %ERRORLEVEL%
