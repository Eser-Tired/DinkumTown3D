extends RefCounted
## 可再分发的 CC0 自然包随源码交付；与旧存档、采集碰撞和随机流无关。
const DIRECTORY := "res://assets/quaternius/"
static var _scenes := {}
static var _meshes := {}

static func enabled() -> bool:
	return not OS.get_cmdline_user_args().has("--no-nature")

static func instantiate(kind: String, height: float = 0.0) -> Node3D:
	if not enabled():
		return null
	var path := DIRECTORY + kind + ".scn"
	if not ResourceLoader.exists(path):
		return null
	if not _scenes.has(kind):
		_scenes[kind] = load(path)
	var root: Node3D = _scenes[kind].instantiate()
	if height > 0.0:
		var box: AABB = root.get_meta("source_bounds")
		root.scale = Vector3.ONE * height / box.size.y
	return root

static func replace(root: Node3D, kind: String, height: float) -> bool:
	var model := instantiate(kind, height)
	if model == null:
		return false
	_clear_visuals(root)
	_hide(root)
	root.add_child(model)
	return true

static func _clear_visuals(root: Node) -> void:
	for child in root.get_children():
		if child.has_meta("visual_only"):
			root.remove_child(child)
			child.free()
		else:
			_clear_visuals(child)

static func _hide(root: Node) -> void:
	if root is MeshInstance3D:
		var mat: Material = root.material_override
		if not (mat is StandardMaterial3D and mat.emission_enabled):
			root.layers = 0
	for child in root.get_children():
		_hide(child)

static func batch_mesh(kind: String, height: float) -> ArrayMesh:
	var key := "%s/%.3f" % [kind, height]
	if _meshes.has(key):
		return _meshes[key]
	var model := instantiate(kind, height)
	if model == null:
		return null
	var result := ArrayMesh.new()
	for mi in model.get_children():
		if mi is MeshInstance3D:
			for s in mi.mesh.get_surface_count():
				var st := SurfaceTool.new()
				st.append_from(mi.mesh, s, model.transform * mi.transform)
				st.commit(result)
				result.surface_set_material(result.get_surface_count() - 1, mi.mesh.surface_get_material(s))
	model.free()
	_meshes[key] = result
	return result

static func replace_stump(root: Node3D) -> void:
	var dead_tree := instantiate("DeadTree_1")
	if dead_tree == null:
		return
	# 包里没有独立树桩；保留原桩尺寸，用同包枯树的树皮/法线材质，防止缩整棵枯树成盆景。
	var material: Material = dead_tree.get_child(0).mesh.surface_get_material(0)
	dead_tree.free()
	_clear_visuals(root)
	_hide(root)
	var visual := Node3D.new()
	visual.name = "AssetVisual"
	visual.set_meta("visual_only", true)
	visual.set_meta("art_source", "quaternius")
	for child in root.get_children():
		if child is MeshInstance3D:
			var mi := MeshInstance3D.new()
			mi.mesh = child.mesh
			mi.transform = child.transform
			mi.material_override = material
			visual.add_child(mi)
	root.add_child(visual)
