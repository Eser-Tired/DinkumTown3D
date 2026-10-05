extends SceneTree
## 将选中的 CC0 部件组合成游戏房屋，并烘焙统一包围盒；源包脚本永不执行。
const OUT := "res://assets/town/"
const RAW := "res://assets/kenney/"
const NATURE := {
	"tree": "CommonTree_1", "tree_alt": "TwistedTree_1", "bush": "Bush_Common",
	"bush_alt": "Bush_Common_Flowers", "rock": "Rock_Medium_1", "rock_alt": "Rock_Medium_2", "grass": "Grass_Common_Short"
}
var failed := false

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for kind in ["crate", "barrel", "log", "firewood", "bag", "cup", "bottle", "fence", "stump", "beam", "post", "bed", "table", "chair", "shelf", "stove"] + NATURE.keys():
		var path: String = "res://assets/quaternius/" + NATURE[kind] + ".scn" if NATURE.has(kind) else RAW + kind + ".scn"
		var source: Node3D = load(path).instantiate()
		var bounds: AABB = source.get_meta("source_bounds")
		var orientation := Basis.IDENTITY
		if kind == "log": orientation = Basis(Vector3.RIGHT, PI * 0.5)
		if kind == "bed": orientation = Basis(Vector3.UP, PI * 0.5)
		var rotated: AABB = Transform3D(orientation, Vector3.ZERO) * bounds
		var target := Vector3.ONE * (0.95 if kind == "crate" else 1.0)
		var transform := Transform3D(Basis.from_scale(target / rotated.size) * orientation, -rotated.get_center() * target / rotated.size)
		var model := _bake(source, transform)
		model.set_meta("visual_bounds", AABB(-target * 0.5, target))
		model.set_meta("asset_id", "public_" + kind)
		model.set_meta("visual_only", true)
		_save(model, kind)
		source.free()
	for kind in ["hut", "shop"]:
		_save(_house(kind == "shop"), kind)
	_ground()
	print("==== PUBLIC ART IMPORT DONE fails=%d ====" % int(failed))
	quit(1 if failed else 0)

func _bake(source: Node3D, transform: Transform3D) -> Node3D:
	var model := Node3D.new()
	model.name = "AssetVisual"
	var count := 0
	for mi in source.find_children("*", "MeshInstance3D", true, false):
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		copy.transform = transform * source.transform.affine_inverse() * _relative(mi, source)
		copy.material_override = mi.material_override
		model.add_child(copy)
		copy.owner = model
		for s in mi.mesh.get_surface_count(): count += mi.mesh.surface_get_array_index_len(s) / 3
	model.set_meta("triangle_count", count)
	return model

func _relative(node: Node3D, source: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != source and parent is Node3D:
		result = parent.transform * result
		parent = parent.get_parent()
	return result

func _part(model: Node3D, kind: String, size: Vector3, center: Vector3, rotate := false) -> void:
	var source: Node3D = load(RAW + kind + ".scn").instantiate()
	var bounds: AABB = source.get_meta("source_bounds")
	var orientation := Basis(Vector3.UP, PI * 0.5) if rotate else Basis.IDENTITY
	var rotated: AABB = Transform3D(orientation, Vector3.ZERO) * bounds
	var part := _bake(source, Transform3D(Basis.from_scale(size / rotated.size) * orientation, center - rotated.get_center() * size / rotated.size))
	part.set_meta("visual_only", true)
	model.add_child(part)
	part.owner = model
	for child in part.get_children(): child.owner = model
	source.free()

func _solid(model: Node3D, size: Vector3, center: Vector3) -> void:
	# 单一简化墙面提供原玩法碰撞；装饰部件不再各加一份凸包。
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = center
	mi.layers = 0
	model.add_child(mi)
	mi.owner = model

func _house(shop: bool) -> Node3D:
	var model := Node3D.new()
	var w := 7.0 if shop else 5.0
	var d := 5.2 if shop else 4.2
	var h := 3.1 if shop else 2.8
	var roof_h := 1.65
	for side in [-1.0, 1.0]:
		_part(model, "window", Vector3(0.18, h, d), Vector3(side * w * 0.5, h * 0.5, 0))
		_solid(model, Vector3(0.18, h, d), Vector3(side * w * 0.5, h * 0.5, 0))
	_part(model, "wall", Vector3(w, h, 0.18), Vector3(0, h * 0.5, -d * 0.5), true)
	_solid(model, Vector3(w, h, 0.18), Vector3(0, h * 0.5, -d * 0.5))
	# 门保持在 +Z 中轴，左右窗墙独立适配，不拉伸单个门到整栋墙宽。
	_part(model, "door", Vector3(1.3, h, 0.18), Vector3(0, h * 0.5, d * 0.5), true)
	for side in [-1.0, 1.0]:
		var width := (w - 1.3) * 0.5
		_part(model, "window", Vector3(width, h, 0.18), Vector3(side * (0.65 + width * 0.5), h * 0.5, d * 0.5), true)
	_solid(model, Vector3(w, h, 0.18), Vector3(0, h * 0.5, d * 0.5))
	_part(model, "roof-end", Vector3(w + 0.65, roof_h, d + 0.7), Vector3(0, h + roof_h * 0.5, 0), true)
	_part(model, "chimney", Vector3(0.5, 1.15, 0.6), Vector3(w * 0.27, h + roof_h * 0.8, -0.4))
	_part(model, "beam", Vector3(1.8, 0.16, 0.7), Vector3(0, 0.08, d * 0.5 + 0.4))
	_solid(model, Vector3(1.8, 0.16, 0.7), Vector3(0, 0.08, d * 0.5 + 0.4))
	model.set_meta("asset_id", "public_shop" if shop else "public_hut")
	model.set_meta("collide_radius", 5.6 if shop else 3.4)
	# door_point 固定在原点前2.9/4米，把入口原点移到真实门板之前而不是沿用旧侧门。
	model.set_meta("entrance_origin", Vector2(0, d * 0.5 - (4.0 if shop else 2.9)))
	model.set_meta("stair_x", 0.0)
	model.set_meta("exit_distance", d * 0.5 + 1.45)
	model.set_meta("visual_bounds", AABB(Vector3(-w * 0.5 - 0.325, 0, -d * 0.5 - 0.35), Vector3(w + 0.65, h + roof_h * 0.8 + 0.575, d + 0.7)))
	var triangles := 0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.layers == 0: continue
		for s in mi.mesh.get_surface_count(): triangles += mi.mesh.surface_get_array_index_len(s) / 3
	model.set_meta("triangle_count", triangles)
	return model

func _save(model: Node3D, kind: String) -> void:
	var packed := PackedScene.new()
	packed.pack(model)
	# 已落盘的共享材质不能再 FLAG_BUNDLE：Godot 4.7 二进制打包会产生坏的纹理索引。
	# 材质/纹理均随 assets 提交，保留正常资源依赖能避免白模并减少重复纹理。
	failed = ResourceSaver.save(packed, OUT + kind + ".scn", ResourceSaver.FLAG_COMPRESS) != OK or failed
	model.free()

func _ground() -> void:
	# 自制可平铺贴图取代受限地表图；确定种子与周期噪声保证仓库中的最终贴图可重建。
	var noise := FastNoiseLite.new()
	noise.seed = 73021
	noise.frequency = 0.08
	noise.fractal_octaves = 4
	var height := noise.get_seamless_image(512, 512)
	var grass := Image.create(512, 512, false, Image.FORMAT_RGB8)
	var earth := grass.duplicate()
	for y in 512:
		for x in 512:
			var n := height.get_pixel(x, y).r
			grass.set_pixel(x, y, Color(0.32, 0.42, 0.16).lerp(Color(0.52, 0.57, 0.28), n))
			earth.set_pixel(x, y, Color(0.42, 0.28, 0.17).lerp(Color(0.66, 0.49, 0.31), n))
	var normal := height.duplicate()
	normal.bump_map_to_normal_map(2.0)
	for entry in [["ground_grass", grass], ["ground_earth", earth], ["ground_normal", normal]]:
		entry[1].generate_mipmaps()
		failed = ResourceSaver.save(ImageTexture.create_from_image(entry[1]), OUT + entry[0] + ".res", ResourceSaver.FLAG_COMPRESS) != OK or failed
