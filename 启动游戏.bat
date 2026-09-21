@echo off
chcp 65001 >nul
set "GODOT=C:\Users\a2402\Documents\Code\Tools\Godot\Godot.exe"
set "PROJ=%~dp0"

rem 首次运行（或 .godot 缓存被清理后）先做一次导入，否则全局类无法解析
if not exist "%PROJ%.godot" (
  echo 首次运行，正在导入资源，请稍候……
  "%GODOT%" --headless --path "%PROJ%" --import
)

start "" "%GODOT%" --path "%PROJ%"
exit /b 0
