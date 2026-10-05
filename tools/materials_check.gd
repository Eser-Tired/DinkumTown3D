extends Node3D
## 用真实渲染器读回纹理，二维网格覆盖整张贴图，检查粗糙度、金属分区与平铺接缝。

const M := preload("res://scripts/materials.gd")
const P := preload("res://scripts/props.gd")
var checks := 0
var fails := 0


func _ok(value: bool, message: String) -> void:
	checks += 1
	if not value:
		fails += 1
		print("FAIL " + message)


func _ready() -> void:
	var started := Time.get_ticks_usec()
	for kind in ["wood", "iron", "bark", "canvas", "stone", "plaster"]:
		var material: Material = M.surface(kind, Color(0.45, 0.40, 0.30))
		_ok(material == M.surface(kind, Color(0.45, 0.40, 0.30)), kind + " 材质缓存")
		var maps := M._maps(kind)
		var detail: Image = maps.albedo.get_image()
		var normal: Image = maps.normal.get_image()
		var orm: Image = maps.orm.get_image()
		_ok(detail != null and normal != null and orm != null, kind + " 纹理读回")
		if detail == null or normal == null or orm == null:
			continue
		var n := 512 if kind in ["wood", "iron"] else 128
		_ok(detail.get_width() == n and normal.get_width() == n and orm.get_width() == n, kind + " 分辨率")
		_ok(detail.has_mipmaps() and normal.has_mipmaps() and orm.has_mipmaps(), kind + " 远景 mipmaps")
		var low := 1.0
		var high := 0.0
		var paint := 0
		var metal := 0
		var rust := 0
		var wear_sum := 0.0
		var across := 0.0
		var along := 0.0
		for row in 37:
			for col in 37:
				var x := int((col + 0.5) * n / 37.0)
				var y := int((row + 0.5) * n / 37.0)
				var data := detail.get_pixel(x, y)
				if kind == "wood":
					across += absf(data.r - detail.get_pixel((x + 7) % n, y).r)
					along += absf(data.r - detail.get_pixel(x, (y + 7) % n).r)
				var packed := orm.get_pixel(x, y)
				low = minf(low, packed.g)
				high = maxf(high, packed.g)
				var rgb := normal.get_pixel(x, y)
				var direction := Vector3(rgb.r, rgb.g, rgb.b) * 2.0 - Vector3.ONE
				_ok(absf(direction.length() - 1.0) < 0.025 and direction.z > 0.0, kind + " 有效法线")
				if kind == "iron":
					wear_sum += data.r
					paint += int(data.r < 0.05)
					metal += int(packed.b > 0.65)
					rust += int(data.g > 0.60)
		_ok(high - low > 0.03, kind + " 粗糙度不是常数")
		if kind == "wood":
			print("WOOD across=%.4f along=%.4f" % [across / 1369.0, along / 1369.0])
			_ok(across > along * 1.4, "木纹实际图像具有纵向纤维方向")
		var seam := 0.0
		for step in 37:
			var at := int((step + 0.5) * n / 37.0)
			seam += absf(detail.get_pixel(0, at).r - detail.get_pixel(n - 1, at).r)
			seam += absf(detail.get_pixel(at, 0).r - detail.get_pixel(at, n - 1).r)
		_ok(seam / 74.0 < 0.065, kind + " 平铺亮度接缝")
		if kind == "iron":
			print("IRON samples=1369 paint=%d exposed=%d rust=%d wear_average=%.4f roughness=%.3f..%.3f" % [paint, metal, rust, wear_sum / 1369.0, low, high])
			_ok(paint > 900 and metal > 0 and rust > 0, "铁皮漆面占主体且有裸露金属与锈迹")
			_ok(wear_sum / 1369.0 < 0.20, "掉漆覆盖率过高")
		var mesh := P._box(Vector3(1, 1, 1), material, Vector3(checks % 6, 0, 0))
		add_child(mesh)
	var wood := M.surface("wood", P.C_WOOD)
	for axis in 3:
		var size := Vector3.ONE * 0.2
		size[axis] = 3.0
		var mesh := P._box(size, wood, Vector3.ZERO, Vector3(0.2, 0.4, 0.3))
		_ok(mesh.material_override.get_shader_parameter("grain_axis") == axis, "木纹沿构件本地最长边 axis=%d" % axis)
		_ok(mesh.material_override == M.for_box(wood, size), "木纹方向缓存 axis=%d" % axis)
		mesh.free()
	_ok(M._textures.size() == 6, "颜色和朝向不能额外生成纹理")
	var terrain: Node3D = load("res://scripts/terrain.gd").new()
	terrain.map_seed = 20260921
	add_child(terrain)
	var height: float = terrain.height_at(-15, 8)
	terrain.set_process(false)
	terrain.target_wetness = 1.0
	terrain._process(1.0)
	_ok(terrain.wetness > 0.0 and terrain.wetness < 1.0, "雨后湿润渐变")
	_ok(is_equal_approx(terrain.ground_mi.material_override.get_shader_parameter("wetness"), terrain.wetness), "湿度传给地面shader")
	terrain._process(10.0)
	_ok(is_equal_approx(terrain.wetness, 1.0), "持续降雨达到湿润上限")
	terrain.target_wetness = 0.0
	terrain._process(10.0)
	_ok(is_zero_approx(terrain.wetness), "雨停后干燥")
	_ok(is_equal_approx(terrain.height_at(-15, 8), height), "干湿材质不改变地形高度真值")
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(3, 3, 8)
	camera.look_at(Vector3(3, 0, 0))
	camera.make_current()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	print("MATERIAL_GENERATION_MS=%.2f CHECK_ELAPSED_MS=%.2f" % [M.generation_ms, (Time.get_ticks_usec() - started) / 1000.0])
	print("==== MATERIALS CHECK DONE checks=%d fails=%d ====" % [checks, fails])
	get_tree().quit(1 if fails else 0)
