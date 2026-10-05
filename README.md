# DinkumTown3D

Godot 4.7.2 第三人称小镇游戏，支持采集、建造、农耕、狩猎、昼夜季节、游泳与潜水。无需安装 addons。

## 下载与运行

克隆本仓库，用 Godot 4.7.2 打开 `project.godot`，按 F5 启动游戏。主场景是主菜单。Windows 启动脚本需要本机 Godot 位于相邻的 `../Tools/Godot/Godot.exe`。

所有运行时模型、骨骼动画、材质和贴图都已放入 `assets/` 并随 Git 提交。无需 Git LFS、资源安装脚本或另外下载素材。`.godot` 是可重建缓存，截图临时目录和个人存档不属于运行依赖。

## 控制

WASD 移动，Shift 跑步，空格跳跃；右键拖动视角，滚轮调整距离。水中 Ctrl/C 下潜。也支持触控操作。

人物步行 / 跑步速度为 1.8 / 5.2 米每秒，骨骼步频随碰撞后实际速度变化；站立用自然待机，顶墙时停止走路动画。动物转弯沿身体朝向前进。

## 素材与许可

自然、人物、动物来自 Quaternius；房屋、家具、容器与道具来自 Kenney，第三方源素材均为 CC0，原始许可保留在 `assets/` 各目录。地形、水、UI、作物及地表贴图由项目生成。旧 EmacE 资源已退役：历史文档和导入工具仅供记录，当前游戏不读取 `local_assets/`。

[素材说明](docs/nature_assets.md) · [本轮动作与完整交付验收](docs/motion_delivery.html)

## 验证

逻辑测试用 `Godot --headless --path . res://tools/<主题>_check.tscn --fixed-fps 60`。涉及存档的测试应在修改了 `config/name` 的独立检出中运行。`nature_check` 与截图脚本需要窗口模式；`delivery_check.gd` 和 `art_dependencies.gd` 用 `--script` 执行。

当前交付包含 119 个资产场景；验收覆盖待机恢复、完整步态、转弯、实体碰撞、进出房屋、读档、水域和 8 种触控分辨率。
