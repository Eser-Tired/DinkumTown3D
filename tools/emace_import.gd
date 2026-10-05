extends SceneTree
## 在资源包自己的 Godot 项目中运行；输出仅放入被 Git 忽略的 local_assets。
## 不执行资源包脚本、不安装插件，只提取选定场景的静态网格和调色板。

const HOUSE := "res://Prefabs/Town/Building/EA03_Town_House_Comp_01a_PRE.prefab.scn"
const CRATE := "res://Prefabs/Prop/Container/EA03_Prop_Container_Crate_02a_PRE.prefab.scn"
const DOOR := "res://Prefabs/Environment/EA03_Prop_House_Door_01b_PRE.prefab.scn"
var output := ""
var palette: ImageTexture
var material: StandardMaterial3D
var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--output")
	if at < 0 or at + 1 >= args.size():
		push_error("必须指定 --output <游戏项目>/local_assets/emace")
		quit(1)
		return
	output = args[at + 1].replace("\\", "/").trim_suffix("/")
	if not output.ends_with("/local_assets/emace"):
		push_error("授权素材只允许输出到 local_assets/emace")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://Textures/EA03_FREE_Slavica.png"))
	if image == null or image.is_empty():
		push_error("找不到资源包调色板")
		quit(1)
		return
	palette = ImageTexture.create_from_image(image)
	material = StandardMaterial3D.new()
	material.albedo_texture = palette
	# 调色板 UV 在很小的色块内，线性过滤会串色；与原包相同使用最近邻。
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_export(HOUSE, "hut", true)
	_export(CRATE, "crate", false)
	var license_file := FileAccess.open(output + "/LICENSE.txt", FileAccess.WRITE)
	if license_file == null:
		failed = true
	else:
		license_file.store_string(FileAccess.get_file_as_string("res://LICENSE.txt"))
		license_file.close()
	print("==== EMACE IMPORT DONE fails=%d ====" % int(failed))
	quit(1 if failed else 0)


func _export(path: String, name: String, house: bool) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		failed = true
		return
	var source := scene.instantiate() as Node3D
	root.add_child(source)
	var out := Node3D.new()
	out.name = "Emace" + name.capitalize()
	out.set_meta("asset_id", "emace_" + name)
	var count := 0
	var triangles := 0
	var source_bounds := AABB()
	var bounds := AABB()
	for child in source.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var original := mi.global_transform
		var b: AABB = original * mi.get_aabb()
		source_bounds = b if count == 0 else source_bounds.merge(b)
		var item := MeshInstance3D.new()
		item.name = "Mesh%d" % count
		# 清除原网格材料中的 res:// 外部引用，生成场景无需完整原包和 FBX。
		item.mesh = mi.mesh.duplicate() as Mesh
		for surface in item.mesh.get_surface_count():
			item.mesh.surface_set_material(surface, material)
		item.material_override = material
		var adapt := Transform3D.IDENTITY
		if house:
			# 实测原墙门洞宽1.113、高1.97米。水平0.72保留0.80米门宽，
			# 垂直0.95保留1.87米门高；屋顶单独压缩，不能整屋缩小成娃娃屋。
			var sy := 0.95
			var y_shift := -0.78
			var part := str(source.get_path_to(mi))
			if part.contains("Foundation") or part.contains("Porch"):
				sy = 0.35
				y_shift = 0.0
			elif part.contains("EA_Roof"):
				sy = 0.45
				y_shift = 3.24 - 4.242155 * sy
			adapt = Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(0.72, sy, 0.72)), Vector3(0, y_shift, 0))
		else:
			# 原箱子1.041×0.853×0.977，归一为现有0.95米碰撞盒，底部不会悬空。
			var size := b.size
			var scale_box := Vector3.ONE * 0.95 / size
			adapt = Transform3D(Basis.from_scale(scale_box), -b.get_center() * scale_box)
		item.transform = adapt * original
		out.add_child(item)
		item.owner = out
		var bb: AABB = item.transform * item.get_aabb()
		bounds = bb if count == 0 else bounds.merge(bb)
		triangles += mi.mesh.get_faces().size() / 3
		count += 1
	if house:
		var door_scene := load(DOOR) as PackedScene
		if door_scene == null:
			failed = true
			out.free()
			source.free()
			return
		var door := door_scene.instantiate() as Node3D
		root.add_child(door)
		for child in door.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = child
			var b: AABB = mi.global_transform * mi.get_aabb()
			var scale_door := Vector3(0.08, 1.87, 0.80) / b.size
			var normalize := Transform3D(Basis.from_scale(scale_door), -b.get_center() * scale_door)
			var item := MeshInstance3D.new()
			item.name = "Door"
			item.mesh = mi.mesh.duplicate() as Mesh
			for surface in item.mesh.get_surface_count():
				item.mesh.surface_set_material(surface, material)
			item.material_override = material
			item.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-1.63692, 1.276, 3.012)) * normalize * mi.global_transform
			out.add_child(item)
			item.owner = out
			triangles += item.mesh.get_faces().size() / 3
			count += 1
			door.free()
			break
		# 原组合屋只有外墙，没有室内；暗色内衬让窗洞看到墙内而不是穿屋看天空。
		var backing := MeshInstance3D.new()
		backing.name = "InnerBacking"
		var box := BoxMesh.new()
		box.size = Vector3(5.5, 2.5, 5.5)
		backing.mesh = box
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.16, 0.14, 0.11)
		dark.roughness = 1.0
		backing.material_override = dark
		backing.position = Vector3(0.12, 1.70, 0.04)
		out.add_child(backing)
		backing.owner = out
		count += 1
		triangles += 12
		# 门洞实测中心Z=-2.2735，旋转后门向+Z，但门仍在横向偏左处。
		# 把这个偏移交给现有交互系统，不能用整栋房子的中心冒充门的中心。
		out.set_meta("entrance_origin", Vector2(-2.2735 * 0.72, 4.157 * 0.72 - 2.6))
		out.set_meta("exit_distance", bounds.end.z + 1.2)
		# 实测台阶原Z约-0.9，旋转后X约-0.65；走门的轴线会撞左侧栏杆。
		out.set_meta("stair_x", -0.65)
		out.set_meta("collide_radius", 4.6)
		var body := StaticBody3D.new()
		body.name = "Solid"
		body.collision_layer = 1
		body.collision_mask = 6
		out.add_child(body)
		body.owner = out
		for item in out.get_children():
			if item is MeshInstance3D and item != backing:
				# 木屋门廊、台阶与墙是凹结构，整网格转凸包会填平台阶并封掉门廊。
				var faces: PackedVector3Array = item.mesh.get_faces()
				for i in faces.size():
					faces[i] = item.transform * faces[i]
				var shape := ConcavePolygonShape3D.new()
				shape.set_faces(faces)
				shape.backface_collision = true
				var cs := CollisionShape3D.new()
				cs.shape = shape
				body.add_child(cs)
				cs.owner = out
	out.set_meta("visual_bounds", bounds)
	out.set_meta("triangle_count", triangles)
	var packed := PackedScene.new()
	var error := packed.pack(out)
	if error == OK:
		error = ResourceSaver.save(packed, output + "/" + name + ".scn", ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES)
	failed = failed or error != OK or count == 0
	print("EMACE %s meshes=%d triangles=%d source=%s adapted=%s saved=%d" % [name, count, triangles, source_bounds, bounds, error])
	out.free()
	source.free()
