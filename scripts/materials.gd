extends RefCounted
## 程序化 PBR 材质：纹理按种类共享，颜色与木纹方向只占材质参数，避免每棵树重做纹理。

static var _materials: Dictionary = {}
static var _textures: Dictionary = {}
static var generation_ms := 0.0
const AGED := preload("res://shaders/aged_surface.gdshader")


static func surface(kind: String, color: Color, rough := 0.9, metal := 0.0, axis := 1) -> Material:
	var key := "%s/%s/%.3f/%.3f/%d" % [kind, color.to_html(), rough, metal, axis]
	if _materials.has(key):
		return _materials[key]
	var maps := _maps(kind)
	var m: Material
	if kind == "wood" or kind == "iron":
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = AGED
		shader_mat.set_shader_parameter("base_color", color)
		shader_mat.set_shader_parameter("surface_kind", 1 if kind == "iron" else 0)
		shader_mat.set_shader_parameter("grain_axis", axis)
		shader_mat.set_shader_parameter("base_roughness", rough)
		shader_mat.set_shader_parameter("base_metallic", metal)
		shader_mat.set_shader_parameter("detail_map", maps["albedo"])
		shader_mat.set_shader_parameter("normal_map", maps["normal"])
		shader_mat.set_shader_parameter("orm_map", maps["orm"])
		m = shader_mat
	else:
		var standard := StandardMaterial3D.new()
		standard.albedo_color = color
		standard.albedo_texture = maps["albedo"]
		standard.normal_enabled = true
		standard.normal_texture = maps["normal"]
		standard.normal_scale = 0.28
		standard.roughness = rough
		standard.roughness_texture = maps["orm"]
		standard.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		standard.metallic = metal
		standard.ao_enabled = true
		standard.ao_texture = maps["orm"]
		standard.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		standard.uv1_triplanar = true
		standard.uv1_scale = Vector3.ONE * (2.0 if kind == "stone" else 1.4)
		standard.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		m = standard
	m.set_meta("surface_kind", kind)
	m.set_meta("surface_color", color)
	m.set_meta("surface_roughness", rough)
	m.set_meta("surface_metallic", metal)
	_materials[key] = m
	return m


static func for_box(material: Material, size: Vector3) -> Material:
	if material == null or material.get_meta("surface_kind", "") != "wood":
		return material
	# 木纹沿本地最长边走，旋转构件后仍跟着构件走，不能使用整张地图的世界方向。
	var axis := 1
	if size.x > size.y and size.x >= size.z:
		axis = 0
	elif size.z > size.y and size.z > size.x:
		axis = 2
	return surface("wood", material.get_meta("surface_color"),
		material.get_meta("surface_roughness"), material.get_meta("surface_metallic"), axis)


static func _noise_image(n: int, seed_value: int, cycles: float) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = cycles / float(n)
	noise.fractal_octaves = 3
	# 噪声图在 C++ 内批量生成；循环里多次调用 get_noise_2d 会拖慢世界创建。
	return noise.get_seamless_image(n, n)


static func _maps(kind: String) -> Dictionary:
	if _textures.has(kind):
		return _textures[kind]
	var start := Time.get_ticks_usec()
	# 512 只用于玩家经常近看的木板和铁皮；远景树皮与石块继续控制显存占用。
	var n := 512 if kind == "wood" or kind == "iron" else 128
	var macro := _noise_image(n, 871 + kind.hash() % 1024, 5.0)
	var micro := _noise_image(n, 1397 + kind.hash() % 1024, 54.0)
	var albedo := Image.create(n, n, false, Image.FORMAT_RGB8)
	var bump := Image.create(n, n, false, Image.FORMAT_RGB8)
	var orm := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var u := float(x) / n * TAU
			var v := float(y) / n * TAU
			var broad := macro.get_pixel(x, y).r
			var fine := micro.get_pixel(x, y).r
			var detail := (fine - 0.5) * 2.0
			var height := 0.5
			var shade := 0.9
			var roughness := 0.88 + fine * 0.12
			var occlusion := 1.0
			var metallic := 0.0
			var data := Color.WHITE
			match kind:
				"wood", "bark":
					# 周期坐标下的结疤与扭曲木纹，使平铺边缘连续，减少规则正弦条纹的塑料感。
					var knot := exp(-((1.0 - cos(u - 2.2)) * 18.0 + (1.0 - cos(v - 2.8)) * 3.5))
					var phase := u * 18.0 + sin(v * 2.0) * 1.1 + sin(v * 5.0) * 0.35 + knot * 6.0
					var grain := sin(phase)
					var lines := pow(absf(grain), 18.0)
					var pores := smoothstep(0.63, 0.79, fine) * lines
					height = 0.5 + grain * 0.09 - pores * 0.16 - knot * 0.045 + detail * 0.025
					shade = 0.90 - lines * 0.19 - knot * 0.23 + (broad - 0.5) * 0.16 + detail * 0.035
					occlusion = 1.0 - pores * 0.18
					roughness = clampf(0.76 + fine * 0.20 + lines * 0.04, 0.0, 1.0)
				"iron":
					var ridge := sin(u * 8.0)
					# 此阈值在整图 37×37 采样中给出约 6% 的掉漆权重，保留漆面主体，避免迷彩图案。
					var wear := smoothstep(0.73, 0.84, broad + detail * 0.025)
					var rust := wear * smoothstep(0.34, 0.54, fine + (1.0 - ridge) * 0.05)
					metallic = wear * (1.0 - rust)
					height = 0.5 + ridge * 0.23 + detail * (0.008 + rust * 0.05)
					roughness = lerpf(0.86 + fine * 0.12, 0.55 + fine * 0.25, wear)
					occlusion = 0.96 + ridge * 0.04
					# 铁皮颜色图保存掉漆、锈迹和漆面亮度；shader 分别上色，锈迹不能乘成绿色。
					data = Color(wear, rust, 0.85 + broad * 0.12 + ridge * 0.025)
				"canvas":
					height = 0.5 + sin(u * 32.0) * sin(v * 32.0) * 0.1
					shade = 0.94 + detail * 0.035
				"stone", "plaster":
					height = 0.5 + detail * 0.16 + (broad - 0.5) * 0.25
					shade = 0.91 + (height - 0.5) * 0.3
			if kind != "iron":
				data = Color(shade, shade, shade)
			albedo.set_pixel(x, y, data)
			bump.set_pixel(x, y, Color(height, height, height))
			orm.set_pixel(x, y, Color(occlusion, roughness, metallic))
	# 法线生成使用周期邻域，避免 bump_map_to_normal_map 在平铺边界留下亮缝。
	var normal := Image.create(n, n, false, Image.FORMAT_RGB8)
	var depth := 8.0 if n == 512 else 2.0
	for y in n:
		for x in n:
			var dx := bump.get_pixel((x + 1) % n, y).r - bump.get_pixel(posmod(x - 1, n), y).r
			var dy := bump.get_pixel(x, (y + 1) % n).r - bump.get_pixel(x, posmod(y - 1, n)).r
			var direction := Vector3(-dx * depth, dy * depth, 1.0).normalized()
			normal.set_pixel(x, y, Color(direction.x * 0.5 + 0.5, direction.y * 0.5 + 0.5, direction.z * 0.5 + 0.5))
	for image in [albedo, normal, orm]:
		image.generate_mipmaps()
	var maps := {"albedo": ImageTexture.create_from_image(albedo),
		"normal": ImageTexture.create_from_image(normal), "orm": ImageTexture.create_from_image(orm)}
	_textures[kind] = maps
	generation_ms += (Time.get_ticks_usec() - start) / 1000.0
	return maps
