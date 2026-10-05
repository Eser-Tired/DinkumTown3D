extends RefCounted
## 新地被只装饰，不进入 resource_id 序列；旧地图采集点、动物位置和存档保持稳定。
const Art := preload("res://scripts/nature_assets.gd")
const TOWN := Vector2(-14, -10)
const FARM := Vector2(-10, 14)
const CELL := 28.0
const CATALOG := [
	["Grass_Common_Short", 0.48, 28000], ["Grass_Wispy_Short", 0.54, 18000],
	["Grass_Common_Tall", 0.7, 7000], ["Fern_1", 0.55, 420],
	["Clover_1", 0.17, 500], ["Clover_2", 0.19, 500],
	["Flower_3_Group", 0.48, 260], ["Flower_4_Group", 0.5, 260],
	["Plant_1", 0.65, 200], ["Plant_7", 0.6, 200],
	["Mushroom_Common", 0.2, 100], ["Pebble_Round_1", 0.12, 180],
	["Pebble_Square_2", 0.14, 180], ["Bush_Common", 0.8, 130],
	["Bush_Common_Flowers", 0.85, 130],
]

static func allowed(terrain: Node3D, p: Vector2) -> bool:
	# 镇中心、农田和通道留白；水域问地形，不能用绝对高度猜。
	if p.distance_to(TOWN) < 18.0 or p.distance_to(FARM) < 13.0:
		return false
	var closest := Geometry2D.get_closest_point_to_segment(p, TOWN, FARM)
	if closest.distance_to(p) < 5.0 or float(terrain.water_depth_at(p.x, p.y)) > 0.0:
		return false
	var h: float = terrain.height_at(p.x, p.y)
	# 坡度在两个轴上采样，避免漏掉侧向陡坡。
	return absf(float(terrain.height_at(p.x + 0.5, p.y)) - h) < 0.42 and absf(float(terrain.height_at(p.x, p.y + 0.5)) - h) < 0.42

static func build(parent: Node3D, terrain: Node3D, map_seed: int) -> Node3D:
	var root := Node3D.new()
	root.name = "DenseVegetation"
	parent.add_child(root)
	if not Art.enabled():
		root.set_meta("count", 0)
		return root
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed ^ 0x5a9173
	var count := 0
	var signature := PackedStringArray()
	for entry in CATALOG:
		var mesh := Art.batch_mesh(entry[0], entry[1])
		if mesh == null:
			continue
		var chunks := {}
		for i in int(entry[2]):
			var p := Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))
			# 低频聚集留下斑块式草甸，不把整张地图均匀撒满。
			if not allowed(terrain, p) or sin(p.x * 0.09 + map_seed % 31) * cos(p.y * 0.08) < -0.6:
				continue
			var cell := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
			if not chunks.has(cell):
				chunks[cell] = []
			var position := Vector3(p.x, float(terrain.height_at(p.x, p.y)) - 0.025, p.y)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3))
			chunks[cell].append(Transform3D(basis, position))
			signature.append(str(position))
			count += 1
		for cell in chunks:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = chunks[cell].size()
			var origin := Vector3(cell.x * CELL, 0, cell.y * CELL)
			for i in mm.instance_count:
				var transform: Transform3D = chunks[cell][i]
				transform.origin -= origin
				mm.set_instance_transform(i, transform)
			var mi := MultiMeshInstance3D.new()
			mi.name = str(entry[0]) + "_%d_%d" % [cell.x, cell.y]
			mi.position = origin
			mi.multimesh = mm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 65.0
			root.add_child(mi)
		for s in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(s)
			if not str(entry[0]).begins_with("Pebble") and not str(entry[0]).begins_with("Mushroom"):
				terrain.register_tintable(mat)
	root.set_meta("count", count)
	root.set_meta("fingerprint", ";".join(signature).sha256_text())
	return root
