extends SceneTree
## 导入后审计：列出未被场景引用的旧材质，检查可再分发资产的依赖没有落到临时路径。
var used := {}
var failed := false

func _initialize() -> void:
	for folder in ["quaternius", "characters", "animals", "kenney", "town"]:
		var directory: String = "res://assets/" + folder + "/"
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(".scn") or file.ends_with(".res"):
				_visit(directory + file)
		if not DirAccess.dir_exists_absolute(directory + "materials"):
			continue
		for file in DirAccess.get_files_at(directory + "materials"):
			var path := directory + "materials/" + file
			if not used.has(path):
				print("ORPHAN ", ProjectSettings.globalize_path(path))
	print("DEPENDENCIES count=", used.size(), " failed=", failed)
	quit(1 if failed else 0)

func _visit(path: String) -> void:
	if used.has(path):
		return
	used[path] = true
	for dep in ResourceLoader.get_dependencies(path):
		var parts := dep.split("::")
		var target: String = parts[parts.size() - 1]
		if not target.begins_with("res://assets/") and not target.begins_with("res://shaders/"):
			push_error("不可交付的外部依赖：" + target)
			failed = true
		_visit(target)
