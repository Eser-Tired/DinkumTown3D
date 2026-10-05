extends SceneTree
## 在干净 Git 检出上遍历所有交付场景：仅查文件存在会漏掉白模和坏材质引用。
var failed := false
var scenes := 0
var textured_surfaces := 0
var textures := 0

func _initialize() -> void:
	for folder in ["quaternius", "characters", "animals", "kenney", "town"]:
		var directory: String = "res://assets/" + folder + "/"
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(".scn"):
				var packed: PackedScene = load(directory + file)
				if packed == null:
					failed = true
					continue
				var model := packed.instantiate()
				_validate(model)
				model.free()
				scenes += 1
		for sub in [directory, directory + "textures/"]:
			if not DirAccess.dir_exists_absolute(sub): continue
			for file in DirAccess.get_files_at(sub):
				if not file.ends_with(".res"): continue
				var resource = load(sub + file)
				if resource is Texture2D:
					var image: Image = resource.get_image()
					failed = failed or image == null or image.is_empty()
					textures += 1
	# 当前119场景的147个贴图表面已逐个验过；漏材质时不能靠其它表面凑到下限蒙混过关。
	failed = failed or scenes != 119 or textures != 19 or textured_surfaces != 147
	failed = failed or not preload("res://scripts/optional_assets.gd").DIRECTORY.begins_with("res://assets/")
	print("==== DELIVERY CHECK DONE scenes=%d textures=%d textured_surfaces=%d failed=%s ====" % [scenes, textures, textured_surfaces, failed])
	quit(1 if failed else 0)

func _validate(node: Node) -> void:
	if node.get_script() != null:
		push_error("素材不应携带外部脚本：" + str(node.name))
		failed = true
	if node is MeshInstance3D and node.layers != 0:
		for s in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(s)
			if material == null:
				push_error("缺失材质：" + str(node.name))
				failed = true
			elif material is StandardMaterial3D:
				if material.albedo_texture != null:
					failed = failed or material.albedo_texture.get_image() == null
					textured_surfaces += 1
			elif material is ShaderMaterial:
				failed = failed or material.shader == null
				var texture = material.get_shader_parameter("albedo_texture")
				if texture != null:
					failed = failed or texture.get_image() == null
					textured_surfaces += 1
	for child in node.get_children(): _validate(child)
