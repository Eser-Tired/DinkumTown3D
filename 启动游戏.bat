@echo off
setlocal
rem ASCII only: cmd.exe parses .bat with the legacy code page, non-ASCII breaks syntax.
set "PROJ=%~dp0"

rem Prefer Godot next to the project (..\Tools\Godot\Godot.exe), fall back to PATH.
set "GODOT=%PROJ%..\Tools\Godot\Godot.exe"
if not exist "%GODOT%" set "GODOT=godot"

rem First run (or after .godot is deleted) needs an import pass or class_name globals fail.
if not exist "%PROJ%.godot" (
  echo First run: importing assets, please wait...
  "%GODOT%" --headless --path "%PROJ%" --import
)

start "" "%GODOT%" --path "%PROJ%"
endlocal
exit /b 0
