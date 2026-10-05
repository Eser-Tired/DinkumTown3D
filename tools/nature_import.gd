extends SceneTree
## 只导入 CC0 美术，不执行下载包里的代码；纹理共享、缩至 1024，避免每棵树嵌一份 4K 图。

var textures := {}
var materials := {}
var output := "res://assets/quaternius/"
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("参数：<解压后的 glTF 目录> <输出 res:// 目录> [--rigged]")
		quit(1)
		return
	output = args[1].trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output + "textures"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output + "materials"))
	# 选取多包文件时保留原始目录，GLB 可能引用相邻的外部调色板，不能只复制 GLB。
	var files := {}
	if args[0].ends_with(".json"):
		files = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	else:
		for file in DirAccess.get_files_at(args[0]):
			files[file] = args[0].path_join(file)
	var count := 0
	for file in files:
		if file.get_extension() not in ["gltf", "glb"]:
			continue
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var error := doc.append_from_file(files[file], state)
		if error != OK:
			failed = true
			push_error("导入失败：" + file)
			continue
		var source := doc.generate_scene(state)
		get_root().add_child(source)
		var root := Node3D.new()
		root.name = "AssetVisual"
		root.set_meta("visual_only", true)
		root.set_meta("art_source", "kenney" if output.begins_with("res://assets/kenney/") else "quaternius")
		var bounds := AABB()
		var first := true
		for mi in source.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = mi.global_transform * mi.mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			for s in mi.mesh.get_surface_count():
				var material: Material = mi.mesh.surface_get_material(s)
				if material is StandardMaterial3D:
					mi.mesh.surface_set_material(s, _material(material))
		if args.has("--rigged"):
			for player in source.find_children("*", "AnimationPlayer", true, false):
				if player.has_animation("Idle"):
					player.play("Idle")
					player.advance(0)
			for skeleton in source.find_children("*", "Skeleton3D", true, false):
				skeleton.force_update_all_bone_transforms()
			bounds = _posed_bounds(source)
			source.get_parent().remove_child(source)
			root.add_child(source)
			_owner(source, root)
			root.set_meta("source_bounds", bounds)
			for player in source.find_children("*", "AnimationPlayer", true, false):
				print("ANIMATIONS ", player.get_animation_list())
			for skeleton in source.find_children("*", "Skeleton3D", true, false):
				for bone in skeleton.get_bone_count():
					print("BONE ", bone, " ", skeleton.get_bone_name(bone), " ", skeleton.get_bone_rest(bone).origin)
		else:
			# 树根/草根贴地，中心在 XZ 原点；保持原比例，运行时按高度缩放。
			var offset := Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
			for mi in source.find_children("*", "MeshInstance3D", true, false):
				var copy := MeshInstance3D.new()
				copy.name = mi.name
				copy.mesh = mi.mesh
				copy.transform = mi.global_transform
				copy.position += offset
				root.add_child(copy)
				copy.owner = root
			root.set_meta("source_bounds", AABB(bounds.position + offset, bounds.size))
			source.free()
		var packed := PackedScene.new()
		packed.pack(root)
		error = ResourceSaver.save(packed, output + file.get_basename() + ".scn", ResourceSaver.FLAG_COMPRESS)
		failed = failed or error != OK
		print("IMPORTED ", file, " BOUNDS=", bounds.size, " error=", error)
		root.free()
		count += 1
	print("IMPORT_DONE count=", count, " textures=", textures.size(), " materials=", materials.size(), " failed=", failed)
	quit(1 if failed else 0)

func _posed_bounds(source: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mi in source.find_children("*", "MeshInstance3D", true, false):
		var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			var bones = arrays[Mesh.ARRAY_BONES]
			for i in vertices.size():
				var point: Vector3 = vertices[i]
				if skeleton != null and mi.skin != null and weights != null and weights.size() > 0:
					point = Vector3.ZERO
					var influences: int = weights.size() / vertices.size()
					for j in influences:
						var weight: float = weights[i * influences + j]
						if weight <= 0:
							continue
						var bind: int = bones[i * influences + j]
						var bone: int = mi.skin.get_bind_bone(bind)
						if bone < 0:
							bone = skeleton.find_bone(mi.skin.get_bind_name(bind))
						point += (skeleton.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind) * vertices[i]) * weight
					point = skeleton.global_transform * point
				else:
					point = mi.global_transform * point
				if first:
					result = AABB(point, Vector3.ZERO)
					first = false
				else:
					result = result.expand(point)
	return result

func _owner(node: Node, root: Node) -> void:
	node.owner = root
	for child in node.get_children():
		_owner(child, root)

func _texture(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var image := texture.get_image()
	var key := image.get_data().hex_encode().sha256_text().substr(0, 16)
	if textures.has(key):
		return textures[key]
	if image.is_compressed():
		image.decompress()
	var largest := maxi(image.get_width(), image.get_height())
	if largest > 1024:
		image.resize(maxi(1, image.get_width() * 1024 / largest), maxi(1, image.get_height() * 1024 / largest), Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps()
	var result := ImageTexture.create_from_image(image)
	var path := output + "textures/" + key + ".res"
	failed = failed or ResourceSaver.save(result, path, ResourceSaver.FLAG_COMPRESS) != OK
	result.take_over_path(path)
	textures[key] = result
	return result

func _material(original: StandardMaterial3D) -> Material:
	var result: Material = original.duplicate()
	result.albedo_texture = _texture(original.albedo_texture)
	result.normal_texture = _texture(original.normal_texture)
	result.roughness = 0.95
	result.metallic = 0.0
	result.emission_enabled = false
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 同名材质有多个叶片贴图；纹理路径必须参与键，不能只按名称复用。
	var key: String = (original.resource_name + (result.albedo_texture.resource_path if result.albedo_texture != null else "") + (result.normal_texture.resource_path if result.normal_texture != null else "") + str(original.albedo_color)).sha256_text().substr(0, 16)
	if materials.has(key):
		return materials[key]
	if original.normal_texture != null:
		result.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	var foliage := original.resource_name.contains("Leaves") or original.resource_name.contains("Leaf") or original.resource_name in ["Grass", "Flowers"]
	if (foliage or original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED) and original.normal_texture == null and not OS.get_cmdline_user_args().has("--rigged"):
		var wind := ShaderMaterial.new()
		wind.shader = load("res://shaders/nature_foliage.gdshader")
		wind.set_shader_parameter("albedo_texture", result.albedo_texture)
		wind.set_shader_parameter("alpha_cutoff", 0.3)
		wind.set_shader_parameter("wind_strength", 0.02)
		result = wind
	var path := output + "materials/" + key + ".res"
	failed = failed or ResourceSaver.save(result, path, ResourceSaver.FLAG_COMPRESS) != OK
	result.take_over_path(path)
	materials[key] = result
	return result
