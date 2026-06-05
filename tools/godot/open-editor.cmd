@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0open-editor.ps1" %*
exit /b %ERRORLEVEL%
