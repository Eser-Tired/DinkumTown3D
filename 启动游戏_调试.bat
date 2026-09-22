@echo off
setlocal
rem Debug launcher: keeps the console open so you can read Godot output / exit code.
rem ASCII only: cmd.exe parses .bat with the legacy code page.
set "PROJ=%~dp0"
set "GODOT=%PROJ%..\Tools\Godot\Godot.exe"
if not exist "%GODOT%" set "GODOT=godot"

cd /d "%PROJ%"
echo Project: %PROJ%
echo Godot  : %GODOT%
echo Starting... (close this window to stop the game)
echo -----------------------------------------------
"%GODOT%" --path .
echo -----------------------------------------------
echo Godot exit code: %ERRORLEVEL%
if not "%ERRORLEVEL%"=="0" pause
endlocal
