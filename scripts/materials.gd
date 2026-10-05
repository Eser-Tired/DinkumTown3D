extends RefCounted
## 风格化材质库：小张平铺纹理只生成一次，沿用模型原有色板。

static var _materials: Dictionary = {}
static var _textures: Dictionary = {}


static func surface(kind: String, color: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var key := "%s/%s/%.3f/%.3f" % [kind, color.to_html(), rough, metal]
	if _materials.has(key):
		return _materials[key]
	var maps := _maps(kind)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = maps["albedo"]
	m.normal_enabled = true
	m.normal_texture = maps["normal"]
	m.normal_scale = 0.45 if kind == "iron" else 0.28
	m.roughness = rough
	m.metallic = metal
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * (2.0 if kind == "stone" else 1.4)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_materials[key] = m
	return m


static func _maps(kind: String) -> Dictionary:
	if _textures.has(kind):
		return _textures[kind]
	const N := 128
	var albedo := Image.create(N, N, false, Image.FORMAT_RGB8)
	var bump := Image.create(N, N, false, Image.FORMAT_RGB8)
	for y in N:
		for x in N:
			var u := float(x) / N * TAU
			var v := float(y) / N * TAU
			var detail := sin(u * 17.0 + sin(v * 7.0)) * sin(v * 13.0 + cos(u * 3.0))
			var h := 0.5
			var shade := 0.9
			match kind:
				"wood", "bark":
					var grain := sin(u * 12.0 + sin(v * 2.0) * 0.8 + sin(v * 5.0) * 0.3)
					var lines := pow(absf(grain), 10.0)
					h = 0.5 + grain * 0.14 + detail * 0.04
					shade = 0.92 - lines * (0.22 if kind == "bark" else 0.13) + detail * 0.03
				"iron":
					var ridge := sin(u * 8.0)
					h = 0.5 + ridge * 0.28
					shade = 0.9 + ridge * 0.065 + detail * 0.015
				"canvas":
					h = 0.5 + sin(u * 32.0) * sin(v * 32.0) * 0.1
					shade = 0.94 + detail * 0.035
				"stone", "plaster":
					h = 0.5 + detail * 0.16 + sin(u * 4.0 + cos(v * 3.0)) * 0.12
					shade = 0.91 + (h - 0.5) * 0.3
			albedo.set_pixel(x, y, Color(shade, shade, shade))
			bump.set_pixel(x, y, Color(h, h, h))
	# OpenGL 法线；纹理在边界处周期连续。
	bump.bump_map_to_normal_map(2.0)
	albedo.generate_mipmaps()
	bump.generate_mipmaps()
	var maps := {"albedo": ImageTexture.create_from_image(albedo),
		"normal": ImageTexture.create_from_image(bump)}
	_textures[kind] = maps
	return maps
