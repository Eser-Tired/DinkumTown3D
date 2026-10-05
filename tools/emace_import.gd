extends SceneTree
## 在资源包自己的 Godot 项目中运行；输出仅放入被 Git 忽略的 local_assets。
## 不执行资源包脚本、不安装插件，只提取选定场景的静态网格和调色板。

const HOUSE := "res://Prefabs/Town/Building/EA03_Town_House_Comp_01a_PRE.prefab.scn"
const CRATE := "res://Prefabs/Prop/Container/EA03_Prop_Container_Crate_02a_PRE.prefab.scn"
const DOOR := "res://Prefabs/Environment/EA03_Prop_House_Door_01b_PRE.prefab.scn"
const CATALOG := {
	"barrel": "Prop/Container/EA03_Prop_Container_Barrel_01d_PRE.prefab.scn",
	"beam": "Prop/wooden/EA03_Prop_Village_Plank_01c_PRE.prefab.scn",
	"post": "Prop/wooden/EA03_Wooden_Pin_01a_PRE.prefab.scn",
	"fence": "Fence/Plank2/EA03_Fence_Plank_02a_PRE.prefab.scn",
	"tree": "Nature/Tree/EA03_Nature_Tree_01b_PRE.prefab.scn",
	"tree_alt": "Nature/Tree/EA03_Nature_Tree_06b_PRE.prefab.scn",
	"bush": "Nature/Bushes/EA03_Nature_Bush_01a_PRE.prefab.scn",
	"bush_alt": "Nature/Bushes/EA03_Nature_Bush_03b_PRE.prefab.scn",
	"rock": "Environment/Rock/EA03_Environment_Rock_CatHead_01b_PRE.prefab.scn",
	"rock_alt": "Environment/Rock/EA03_Environment_Rock_Flat_04c_PRE.prefab.scn",
	"stump": "Prop/Carpentry/EA03_Prop_Tool_Stump_02a_PRE.prefab.scn",
	# Forester 木料是碎板堆，不适合浮力圆木；选用完整带端面的圆柱木件。
	"log": "Prop/wooden/EA03_Wooden_Pin_01a_PRE.prefab.scn",
	"grass": "Nature/Grass/EA03_Plant_Grass_02a_PRE.prefab.scn",
	"bed": "Prop/Furniture/EA03_Prop_Town_Bed_01a.004_PRE.prefab.scn",
	"table": "Prop/Furniture/EA03_Prop_Tabble_01a_PRE.prefab.scn",
	"chair": "Prop/Furniture/EA03_Prop_Stool_01a_PRE.prefab.scn",
	"shelf": "Prop/Furniture/EA03_Prop_House_Shelf_01a_PRE.prefab.scn",
	"stove": "Prop/Village/EA03_Prop_House_Stove_01b_PRE.prefab.scn",
	"bag": "Prop/Container/EA03_Prop_Container_Bag_02a_PRE.prefab.scn",
	"cup": "Items/Crockery/EA03_Items_House_Cup_01a_PRE.prefab.scn",
	"bottle": "Items/Crockery/EA03_Items_House_Bottle_01a_PRE.prefab.scn",
	"firewood": "Items/House/EA03_Items_House_Firewood_01a_PRE.prefab.scn",
}
var output := ""
var palette: ImageTexture
var material: StandardMaterial3D
var failed := false
var _copied_textures := {}
var _copied_materials := {}


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
	_export(HOUSE, "shop", true)
	_export(CRATE, "crate", false)
	for key in CATALOG:
		_export_generic("res://Prefabs/" + CATALOG[key], key)
	for pair in [["ground_grass", "Flower_Grass.png"], ["ground_normal", "Flower_Grass_NM.png"], ["ground_earth", "Pobbles_Sand_Dirt.png"]]:
		var texture := _copy_texture("res://Textures/" + str(pair[1]), true)
		failed = failed or texture == null or ResourceSaver.save(texture, output + "/" + str(pair[0]) + ".res", ResourceSaver.FLAG_COMPRESS) != OK
	var manifest := FileAccess.open(output + "/manifest.json", FileAccess.WRITE)
	if manifest == null:
		failed = true
	else:
		manifest.store_string(JSON.stringify({"version": 2, "catalog": ["crate"] + CATALOG.keys(), "buildings": ["hut", "shop"], "textures": ["ground_grass", "ground_normal", "ground_earth"]}, "\t"))
		manifest.close()
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
		var building_scale := Vector3(1.35, 1.10, 1.15) if name == "shop" else Vector3.ONE
		var building_basis := Basis.from_scale(building_scale)
		for item in out.get_children():
			if item is MeshInstance3D:
				item.transform = Transform3D(building_basis, Vector3.ZERO) * item.transform
		bounds = Transform3D(building_basis, Vector3.ZERO) * bounds
		# 门洞实测中心Z=-2.2735，旋转后门向+Z，但门仍在横向偏左处。
		# 把这个偏移交给现有交互系统，不能用整栋房子的中心冒充门的中心。
		out.set_meta("entrance_origin", Vector2(-2.2735 * 0.72 * building_scale.x, 4.157 * 0.72 * building_scale.z - (3.3 if name == "shop" else 2.6)))
		out.set_meta("exit_distance", bounds.end.z + 1.2)
		# 实测台阶原Z约-0.9，旋转后X约-0.65；走门的轴线会撞左侧栏杆。
		out.set_meta("stair_x", -0.65 * building_scale.x)
		out.set_meta("collide_radius", 5.6 if name == "shop" else 4.6)
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


func _copy_texture(path: String, mipmaps := false) -> ImageTexture:
	if _copied_textures.has(path):
		return _copied_textures[path]
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		failed = true
		return null
	if mipmaps:
		image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_copied_textures[path] = texture
	return texture


func _copy_material(original: Material) -> Material:
	if original == null:
		return material
	if _copied_materials.has(original):
		return _copied_materials[original]
	var result: Material = original.duplicate()
	if result is StandardMaterial3D:
		if original.albedo_texture != null:
			result.albedo_texture = _copy_texture(original.albedo_texture.resource_path)
		result.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif result is ShaderMaterial:
		# 草的透明裁切和风动画来自原包，仅在本地场景内嵌入，不能公开复制其源码。
		result.shader = original.shader.duplicate()
		for parameter in ["albedo_texture", "normal_texture", "gust_noise"]:
			var texture: Texture2D = original.get_shader_parameter(parameter)
			if texture != null:
				result.set_shader_parameter(parameter, _copy_texture(texture.resource_path, true))
	_copied_materials[original] = result
	return result


func _shaft_mesh(mesh: Mesh, transform: Transform3D, cutoff: float) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for index in vertices.size():
				indices.append(index)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var kept := 0
		for offset in range(0, indices.size(), 3):
			var polygon: Array = []
			for index in [indices[offset], indices[offset + 1], indices[offset + 2]]:
				polygon.append({"p": vertices[index], "n": normals[index], "uv": uvs[index]})
			var clipped: Array = []
			for index in 3:
				var a: Dictionary = polygon[index]
				var b: Dictionary = polygon[(index + 1) % 3]
				var ay: float = (transform * a.p).y
				var by: float = (transform * b.p).y
				if ay <= cutoff:
					clipped.append(a)
				if (ay <= cutoff) != (by <= cutoff):
					var t := (cutoff - ay) / (by - ay)
					clipped.append({"p": a.p.lerp(b.p, t), "n": a.n.lerp(b.n, t).normalized(), "uv": a.uv.lerp(b.uv, t)})
			for index in range(1, clipped.size() - 1):
				for point in [clipped[0], clipped[index], clipped[index + 1]]:
					st.set_normal(point.n)
					st.set_uv(point.uv)
					st.add_vertex(point.p)
				kept += 1
		if kept > 0:
			st.set_material(mesh.surface_get_material(surface))
			st.commit(result)
	# 木杆裁掉销帽后需要封住端面；沿实测截面封口，不能留下可见的空心洞。
	var bounds := result.get_aabb()
	var cap := SurfaceTool.new()
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := PackedVector2Array()
	for surface in result.get_surface_count():
		var vertices: PackedVector3Array = result.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			if absf(vertex.y - bounds.end.y) < 0.0001:
				outline.append(Vector2(vertex.x, vertex.z))
	var hull := Geometry2D.convex_hull(outline)
	for index in range(1, hull.size() - 2):
		for point in [hull[0], hull[index], hull[index + 1]]:
			cap.set_normal(Vector3.UP)
			cap.add_vertex(Vector3(point.x, bounds.end.y, point.y))
	var end_material := StandardMaterial3D.new()
	end_material.albedo_color = Color(0.57, 0.41, 0.27)
	end_material.roughness = 0.95
	end_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cap.set_material(end_material)
	cap.commit(result)
	print("EMACE log shaft bounds=%s triangles=%d" % [result.get_aabb(), result.get_faces().size() / 3])
	return result


func _export_generic(path: String, key: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		failed = true
		return
	var source := packed.instantiate() as Node3D
	root.add_child(source)
	var bounds := AABB()
	var meshes: Array[MeshInstance3D] = []
	for child in source.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.visibility_range_begin > 0.0:
			continue
		if key == "log":
			# 裁取木销前63%的木杆，去掉后段的大帽与装饰，避免漂浮物像螺栓。
			var full: AABB = mi.global_transform * mi.get_aabb()
			mi.mesh = _shaft_mesh(mi.mesh, mi.global_transform, full.position.y + full.size.y * 0.63)
		var b: AABB = mi.global_transform * mi.get_aabb()
		bounds = b if meshes.is_empty() else bounds.merge(b)
		meshes.append(mi)
	if meshes.is_empty() or bounds.size.x < 0.001 or bounds.size.y < 0.001 or bounds.size.z < 0.001:
		failed = true
		source.free()
		return
	# 统一成居中的一米盒，调用方按已量化的旧物件占地适配，不在运行时猜源模型单位。
	var canonical := Transform3D(Basis.from_scale(Vector3.ONE / bounds.size), -bounds.get_center() / bounds.size)
	var out := Node3D.new()
	out.name = "Emace" + key.capitalize()
	out.set_meta("asset_id", "emace_" + key)
	out.set_meta("visual_only", true)
	var combined := ArrayMesh.new()
	var triangles := 0
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.append_from(mi.mesh, s, canonical * mi.global_transform)
			st.set_material(_copy_material(mi.get_active_material(s)))
			st.commit(combined)
		triangles += mi.mesh.get_faces().size() / 3
	var item := MeshInstance3D.new()
	item.name = "Mesh"
	item.mesh = combined
	out.add_child(item)
	item.owner = out
	out.set_meta("visual_bounds", combined.get_aabb())
	out.set_meta("triangle_count", triangles)
	out.set_meta("source_bounds", bounds)
	var result := PackedScene.new()
	var error := result.pack(out)
	if error == OK:
		error = ResourceSaver.save(result, output + "/" + key + ".scn", ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES)
	failed = failed or error != OK
	print("EMACE %s triangles=%d source=%s canonical=%s saved=%d" % [key, triangles, bounds, combined.get_aabb(), error])
	out.free()
	source.free()
