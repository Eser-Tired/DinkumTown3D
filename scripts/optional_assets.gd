extends RefCounted
## 可公开交付的 CC0 外观随仓库安装；旧 emace_* 存档身份继续映射，避免破坏读档。

const DIRECTORY := "res://assets/town/"
static var _scenes: Dictionary = {}
static var _textures: Dictionary = {}
const KINDS := ["hut", "shop", "crate", "barrel", "beam", "post", "fence", "tree", "tree_alt", "bush", "bush_alt", "rock", "rock_alt", "stump", "log", "grass", "bed", "table", "chair", "shelf", "stove", "bag", "cup", "bottle", "firewood"]


static func instantiate(kind: String) -> Node3D:
	if not kind in KINDS or OS.get_cmdline_user_args().has("--no-emace"):
		return null
	var path := DIRECTORY + kind + ".scn"
	if not ResourceLoader.exists(path):
		return null
	if not _scenes.has(kind):
		var scene := load(path) as PackedScene
		if scene == null:
			return null
		_scenes[kind] = scene
	return _scenes[kind].instantiate() as Node3D


static func texture(kind: String) -> Texture2D:
	if not kind in ["ground_grass", "ground_normal", "ground_earth"] or OS.get_cmdline_user_args().has("--no-emace"):
		return null
	var path := DIRECTORY + kind + ".res"
	if not ResourceLoader.exists(path):
		return null
	if not _textures.has(kind):
		_textures[kind] = load(path)
	return _textures[kind] as Texture2D


static func fitted(kind: String, size: Vector3, center := Vector3.ZERO, quarter_turn := false) -> Node3D:
	var model := instantiate(kind)
	if model == null:
		return null
	model.name = "AssetVisual"
	model.set_meta("visual_only", true)
	# 导入器归一化的是包围盒；先转家具长轴，再在父坐标中缩放，避免床/桌宽深互换。
	var source_size: Vector3 = model.get_meta("visual_bounds").size
	var orientation := Basis(Vector3.UP, PI * 0.5 if quarter_turn else 0.0)
	if kind == "log" or (kind == "beam" and size.x >= size.y and size.x >= size.z):
		orientation = Basis(Vector3.BACK, PI * 0.5)
	elif kind == "beam" and size.z > size.y:
		orientation = Basis(Vector3.RIGHT, PI * 0.5)
	model.transform = Transform3D(Basis.from_scale(size / source_size) * orientation, center)
	return model


static func cover_mesh(mi: MeshInstance3D, kind: String) -> void:
	var box := mi.mesh.get_aabb()
	var model := fitted(kind, box.size, box.get_center())
	if kind in ["rock", "rock_alt"]:
		var nature := preload("res://scripts/nature_assets.gd").instantiate("Rock_Medium_2" if kind == "rock_alt" else "Rock_Medium_1")
		if nature != null:
			if model != null:
				model.free()
			model = nature
			var bounds: AABB = model.get_meta("source_bounds")
			model.scale = box.size / bounds.size
			model.position = box.get_center() - bounds.get_center() * model.scale
	if model != null:
		# visible=false 会连带隐藏新模型；layers=0 只隐藏原网格，仍保留它生成的简化碰撞。
		for child in mi.get_children():
			if child.has_meta("visual_only"):
				mi.remove_child(child)
				child.free()
		mi.layers = 0
		mi.add_child(model)


static func replace_group(root: Node3D, kind: String, size: Vector3, center: Vector3, quarter_turn := false) -> void:
	var model := fitted(kind, size, center, quarter_turn)
	if model == null:
		return
	_hide_meshes(root)
	root.add_child(model)


static func _hide_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		# 矿簇和炉火是玩法标记，不能被通用外观替换抹掉。
		var material: Material = node.material_override
		if not (material is StandardMaterial3D and material.emission_enabled):
			node.layers = 0
	for child in node.get_children():
		_hide_meshes(child)
