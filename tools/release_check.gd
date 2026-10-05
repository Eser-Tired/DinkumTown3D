extends SceneTree
## 用编辑器 --main-pack <导出EXE或安卓assets ZIP> --script 本脚本审计实际发布资源。
## release 模板不能执行外部脚本，故运行包审计与 EXE 的真实启动测试分开进行。
var failures := 0
var scene_count := 0
var license_count := 0

func _initialize() -> void:
	_check(ProjectSettings.get_setting("application/config/version", "") == "1.1.0", "运行包版本正确")
	_check(not DirAccess.dir_exists_absolute("res://docs"), "运行包不含文档截图")
	_check(not DirAccess.dir_exists_absolute("res://tools"), "运行包不含开发测试")
	_check(not DirAccess.dir_exists_absolute("res://local_assets"), "运行包不依赖旧素材目录")
	for folder in ["quaternius", "characters", "animals", "kenney", "town"]:
		for file in DirAccess.get_files_at("res://assets/" + folder):
			if file.ends_with(".scn"):
				var path: String = "res://assets/" + folder + "/" + file
				var packed: PackedScene = load(path)
				_check(packed != null, path)
				if packed != null:
					var model := packed.instantiate()
					_check(model != null, "实例化 " + path)
					model.free()
					scene_count += 1
	for path in ["quaternius/LICENSE.txt", "characters/LICENSE.txt", "animals/LICENSE.txt", "kenney/licenses/FantasyTown.txt", "kenney/licenses/Furniture.txt", "kenney/licenses/Survival.txt", "town/NOTICE.txt", "engine/LICENSE.txt", "engine/COPYRIGHT.txt"]:
		var full: String = "res://assets/" + path
		_check(FileAccess.file_exists(full) and not FileAccess.get_file_as_string(full).is_empty(), "随包许可 " + path)
		license_count += 1
	_check(scene_count == 119, "119 个资产场景完整")
	_check(ResourceLoader.exists("res://assets/app_icon.svg"), "应用图标完整")
	_check(ResourceLoader.exists("res://scenes/main_menu.tscn"), "主菜单入口完整")
	_check(ResourceLoader.exists("res://scenes/main.tscn"), "游戏入口完整")
	print("==== RELEASE CHECK DONE scenes=%d licenses=%d fails=%d ====" % [scene_count, license_count, failures])
	quit(1 if failures else 0)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL " + label)
