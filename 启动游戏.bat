@echo off
chcp 65001 >nul
set "PROJ=%~dp0"

rem 优先用项目同级的 Godot（Tools\Godot\Godot.exe），找不到则退回 PATH 里的 godot
set "GODOT=%PROJ%..\Tools\Godot\Godot.exe"
if not exist "%GODOT%" set "GODOT=godot"

rem 首次运行（或 .godot 缓存被清理后）先导入，否则 class_name 全局类无法解析
if not exist "%PROJ%.godot" (
  echo 首次运行，正在导入资源，请稍候……
  "%GODOT%" --headless --path "%PROJ%" --import
)

start "" "%GODOT%" --path "%PROJ%"
exit /b 0
