extends RefCounted
class_name Props
## 建筑与道具工厂：全部用 PrimitiveMesh 拼装的低多边形模型
## 每个 make_* 返回 Node3D，并带 meta "collide_radius" 供角色圆形避让

# —— 澳洲内陆色板 ——
const C_WOOD      := Color(0.54, 0.38, 0.25)
const C_WOOD_DARK := Color(0.38, 0.26, 0.17)
const C_WOOD_LIGHT:= Color(0.70, 0.53, 0.36)
const C_IRON_RED  := Color(0.55, 0.22, 0.17)
const C_IRON_GREEN:= Color(0.28, 0.42, 0.31)
const C_IRON_BLUE := Color(0.32, 0.40, 0.47)
const C_CANVAS    := Color(0.86, 0.80, 0.65)
const C_WALL      := Color(0.90, 0.86, 0.75)
const C_STONE     := Color(0.53, 0.51, 0.46)
const C_ROPE      := Color(0.62, 0.53, 0.38)

static var _mats := {}
static var _meshes := {}


static func mat(color: Color, rough := 0.92, metal := 0.0) -> StandardMaterial3D:
	var key := "%d_%d_%d" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]
	key += "_%d_%d" % [int(rough * 100), int(metal * 100)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_mats[key] = m
	return m


static func glow_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.2
	m.roughness = 0.6
	return m


static func _mi(mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	return mi


static func _box(size: Vector3, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mi(b, m, pos, rot)


static func _cyl(r: float, h: float, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, seg := 8) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return _mi(c, m, pos, rot)


## Godot 4.7 已移除 ConeMesh，用 top_radius=0 的圆柱代替
static func _cone(r: float, h: float, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, seg := 8) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.bottom_radius = r
	c.top_radius = 0.0
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return _mi(c, m, pos, rot)


static func _roof(w: float, d: float, h: float, m: Material, pos := Vector3.ZERO, along_z := true) -> MeshInstance3D:
	var p := PrismMesh.new()
	p.size = Vector3(w, h, d)
	var rot := Vector3.ZERO
	if not along_z:
		rot.y = PI * 0.5
	return _mi(p, m, pos, rot)


# ——————————————— 帐篷 ———————————————
static func make_tent() -> Node3D:
	var root := Node3D.new()
	root.add_child(_cone(2.5, 2.6, mat(C_CANVAS), Vector3(0, 2.3, 0), Vector3.ZERO, 8))

	var wall := CylinderMesh.new()
	wall.top_radius = 2.5
	wall.bottom_radius = 2.5
	wall.height = 1.0
	wall.radial_segments = 8
	root.add_child(_mi(wall, mat(C_CANVAS), Vector3(0, 0.5, 0)))

	root.add_child(_box(Vector3(1.1, 1.7, 0.10), mat(Color(0.35, 0.26, 0.19)), Vector3(0, 0.85, 2.45)))
	root.add_child(_cyl(0.08, 4.2, mat(C_WOOD_DARK), Vector3(0, 2.1, 0)))
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		root.add_child(_cyl(0.05, 1.4, mat(C_WOOD_DARK),
			Vector3(cos(a) * 2.9, 0.5, sin(a) * 2.9), Vector3(0, 0, cos(a) * 0.35)))
	root.set_meta("collide_radius", 2.7)
	return root


# ——————————————— 铁皮顶木屋 ———————————————
static func make_hut(roof_col := C_IRON_RED) -> Node3D:
	var root := Node3D.new()
	var w := 5.0
	var d := 4.2
	var h := 2.6

	root.add_child(_box(Vector3(w, h, d), mat(C_WALL), Vector3(0, h * 0.5, 0)))
	# 木框立柱
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			root.add_child(_box(Vector3(0.28, h, 0.28), mat(C_WOOD_DARK),
				Vector3(sx * (w * 0.5 - 0.14), h * 0.5, sz * (d * 0.5 - 0.14))))
	# 屋顶（带屋檐）
	var roof := _roof(w + 1.4, d + 1.4, 1.7, mat(roof_col, 0.75), Vector3(0, h + 0.85, 0))
	root.add_child(roof)
	# 门与窗
	root.add_child(_box(Vector3(1.0, 1.8, 0.12), mat(C_WOOD_DARK), Vector3(0, 0.9, d * 0.5 + 0.05)))
	root.add_child(_box(Vector3(1.1, 0.9, 0.10), mat(Color(0.55, 0.72, 0.78, 1.0), 0.25), Vector3(-1.6, 1.7, d * 0.5 + 0.04)))
	root.add_child(_box(Vector3(1.1, 0.9, 0.10), mat(Color(0.55, 0.72, 0.78, 1.0), 0.25), Vector3(1.6, 1.7, d * 0.5 + 0.04)))
	# 门前小台阶
	root.add_child(_box(Vector3(1.6, 0.18, 0.7), mat(C_WOOD), Vector3(0, 0.09, d * 0.5 + 0.35)))
	root.set_meta("collide_radius", 3.4)
	return root


# ——————————————— 杂货铺 / 商店 ———————————————
static func make_shop() -> Node3D:
	var root := Node3D.new()
	var w := 8.0
	var d := 6.0
	var h := 3.2

	root.add_child(_box(Vector3(w, h, d), mat(Color(0.88, 0.82, 0.68)), Vector3(0, h * 0.5, 0)))
	root.add_child(_roof(w + 1.6, d + 1.6, 1.9, mat(C_IRON_GREEN, 0.7), Vector3(0, h + 0.95, 0)))

	# 门廊
	var porch_y := h + 0.2
	for sx in [-1.0, 0.0, 1.0]:
		root.add_child(_cyl(0.14, 2.6, mat(C_WOOD_DARK), Vector3(sx * 3.0, 1.3, d * 0.5 + 1.4)))
	root.add_child(_box(Vector3(9.0, 0.22, 3.2), mat(C_WOOD), Vector3(0, 2.75, d * 0.5 + 1.4)))
	root.add_child(_roof(9.4, 3.6, 0.9, mat(C_IRON_GREEN, 0.7), Vector3(0, 3.35, d * 0.5 + 1.4)))

	# 橱窗与门
	root.add_child(_box(Vector3(2.4, 1.6, 0.12), mat(Color(0.55, 0.72, 0.78, 1.0), 0.25), Vector3(-2.2, 1.6, d * 0.5 + 0.05)))
	root.add_child(_box(Vector3(1.2, 2.1, 0.14), mat(C_WOOD_DARK), Vector3(1.4, 1.05, d * 0.5 + 0.05)))

	# 招牌
	root.add_child(_box(Vector3(4.2, 1.0, 0.14), mat(Color(0.42, 0.24, 0.16)), Vector3(0, h + 2.0, d * 0.5 + 0.1)))
	var flag := Node3D.new()
	flag.position = Vector3(4.2, h + 3.6, d * 0.5)
	flag.add_child(_cyl(0.07, 2.4, mat(C_WOOD_DARK), Vector3(0, 1.2, 0)))
	flag.add_child(_box(Vector3(1.4, 0.9, 0.06), mat(Color(0.85, 0.62, 0.18)), Vector3(0.7, 2.0, 0)))
	flag.set_meta("spin", 0.35)
	root.add_child(flag)

	# 门口货箱
	root.add_child(_box(Vector3(0.9, 0.9, 0.9), mat(C_WOOD_LIGHT), Vector3(-3.4, 0.45, d * 0.5 + 1.0)))
	root.add_child(_box(Vector3(0.9, 0.9, 0.9), mat(C_WOOD_LIGHT), Vector3(-3.4, 1.35, d * 0.5 + 1.0)))
	root.set_meta("collide_radius", 5.6)
	return root


# ——————————————— 码头 / 木栈桥 ———————————————
static func make_dock(planks := 9) -> Node3D:
	var root := Node3D.new()
	var wood := mat(C_WOOD)
	var wood_d := mat(C_WOOD_DARK)
	for i in planks:
		var z := -float(i) * 1.15
		root.add_child(_box(Vector3(4.2, 0.16, 1.0), wood if (i % 2 == 0) else wood_d, Vector3(0, 0.9, z)))
		if i % 3 == 0:
			for sx in [-1.0, 1.0]:
				root.add_child(_cyl(0.16, 3.2, wood_d, Vector3(sx * 1.9, -0.7, z)))
	# 尽头平台
	root.add_child(_box(Vector3(5.4, 0.18, 3.0), wood, Vector3(0, 0.9, -float(planks) * 1.15 - 1.2)))
	# 系船柱
	root.add_child(_cyl(0.18, 1.0, wood_d, Vector3(2.2, 1.4, -float(planks) * 1.15 - 1.8)))
	# 小船
	var boat := Node3D.new()
	boat.position = Vector3(-3.6, 0.35, -float(planks) * 1.15 - 1.0)
	boat.rotation.y = 0.6
	var hull := SphereMesh.new()
	hull.radius = 1.0
	hull.height = 1.1
	hull.radial_segments = 8
	hull.rings = 4
	boat.add_child(_mi(hull, mat(Color(0.45, 0.33, 0.22)), Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0.7, 0.42, 1.9)))
	boat.add_child(_box(Vector3(0.08, 1.6, 0.08), mat(C_WOOD_DARK), Vector3(0, 0.8, 0)))
	boat.set_meta("bob", 1.0)
	root.add_child(boat)
	root.set_meta("collide_radius", 2.6)
	return root


# ——————————————— 水塔 ———————————————
static func make_watertower() -> Node3D:
	var root := Node3D.new()
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		root.add_child(_box(Vector3(0.26, 5.0, 0.26), mat(C_WOOD_DARK),
			Vector3(cos(a) * 1.5, 2.5, sin(a) * 1.5), Vector3(sin(a) * 0.05, 0, -cos(a) * 0.05)))
	for lvl in [1.4, 3.4]:
		root.add_child(_box(Vector3(3.4, 0.14, 0.14), mat(C_WOOD), Vector3(0, lvl, -1.5)))
		root.add_child(_box(Vector3(3.4, 0.14, 0.14), mat(C_WOOD), Vector3(0, lvl, 1.5)))
		root.add_child(_box(Vector3(0.14, 0.14, 3.4), mat(C_WOOD), Vector3(-1.5, lvl, 0)))
		root.add_child(_box(Vector3(0.14, 0.14, 3.4), mat(C_WOOD), Vector3(1.5, lvl, 0)))
	var tank := CylinderMesh.new()
	tank.top_radius = 2.0
	tank.bottom_radius = 2.0
	tank.height = 2.6
	tank.radial_segments = 10
	root.add_child(_mi(tank, mat(C_IRON_BLUE, 0.7), Vector3(0, 6.3, 0)))
	root.add_child(_cone(2.2, 1.0, mat(C_IRON_RED, 0.7), Vector3(0, 8.1, 0), Vector3.ZERO, 10))
	root.add_child(_cyl(0.12, 2.0, mat(C_WOOD_DARK), Vector3(1.8, 5.6, 0)))
	root.set_meta("collide_radius", 2.4)
	return root


# ——————————————— 风车 ———————————————
static func make_windmill() -> Node3D:
	var root := Node3D.new()
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		root.add_child(_box(Vector3(0.24, 6.4, 0.24), mat(C_WOOD_DARK),
			Vector3(cos(a) * 1.3, 3.2, sin(a) * 1.3), Vector3(sin(a) * 0.08, 0, -cos(a) * 0.08)))
	root.add_child(_box(Vector3(1.6, 0.2, 1.6), mat(C_WOOD), Vector3(0, 6.5, 0)))

	var head := Node3D.new()
	head.position = Vector3(0, 7.0, 0)
	var hub := Node3D.new()
	hub.position = Vector3(0, 0, 0.9)
	hub.add_child(_cyl(0.35, 0.5, mat(Color(0.35, 0.35, 0.38), 0.5),
		Vector3(0, 0, 0), Vector3(PI * 0.5, 0, 0), 8))
	for i in 12:
		var a := TAU * float(i) / 12.0
		var blade := BoxMesh.new()
		blade.size = Vector3(0.55, 2.0, 0.06)
		hub.add_child(_mi(blade, mat(Color(0.80, 0.78, 0.72), 0.6),
			Vector3(cos(a) * 1.35, sin(a) * 1.35, 0.12), Vector3(0, 0, a - PI * 0.5)))
	hub.set_meta("spin", 1.1)
	head.add_child(hub)
	# 尾舵
	head.add_child(_box(Vector3(0.08, 1.0, 1.8), mat(Color(0.75, 0.73, 0.68), 0.6), Vector3(0, 0.4, -1.4)))
	root.add_child(head)
	root.set_meta("collide_radius", 2.0)
	return root


# ——————————————— 围栏段 ———————————————
static func make_fence(len := 4.0, rails := 2) -> Node3D:
	var root := Node3D.new()
	var posts := int(len / 1.8) + 1
	for i in posts:
		root.add_child(_cyl(0.10, 1.3, mat(C_WOOD_DARK), Vector3(-len * 0.5 + float(i) * (len / float(posts - 1)), 0.65, 0), Vector3.ZERO, 6))
	for r in rails:
		root.add_child(_box(Vector3(len, 0.12, 0.10), mat(C_WOOD), Vector3(0, 0.5 + float(r) * 0.5, 0)))
	root.set_meta("collide_radius", 0.0)
	return root


# ——————————————— 篝火 ———————————————
static func make_campfire() -> Node3D:
	var root := Node3D.new()
	for i in 8:
		var a := TAU * float(i) / 8.0
		var s := SphereMesh.new()
		s.radius = 0.32
		s.height = 0.5
		s.radial_segments = 6
		s.rings = 3
		root.add_child(_mi(s, mat(C_STONE), Vector3(cos(a) * 1.05, 0.13, sin(a) * 1.05)))
	for i in 4:
		var a := TAU * float(i) / 4.0
		root.add_child(_box(Vector3(1.5, 0.16, 0.16), mat(C_WOOD_DARK),
			Vector3(0, 0.22, 0), Vector3(0.16, a, 0.22)))
	var flame_mi := _cone(0.45, 1.3, glow_mat(Color(1.0, 0.52, 0.14)), Vector3(0, 0.85, 0), Vector3.ZERO, 6)
	flame_mi.set_meta("flicker", 1.0)
	root.add_child(flame_mi)
	var inner_mi := _cone(0.24, 0.8, glow_mat(Color(1.0, 0.88, 0.42)), Vector3(0, 0.6, 0), Vector3.ZERO, 5)
	inner_mi.set_meta("flicker", 1.6)
	root.add_child(inner_mi)

	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.1, 0)
	light.light_color = Color(1.0, 0.62, 0.26)
	light.light_energy = 6.0
	light.omni_range = 14.0
	light.set_meta("night_light", true)
	root.add_child(light)
	root.set_meta("collide_radius", 1.2)
	return root


# ——————————————— 路灯 ———————————————
static func make_lamp() -> Node3D:
	var root := Node3D.new()
	root.add_child(_cyl(0.11, 3.4, mat(C_WOOD_DARK), Vector3(0, 1.7, 0), Vector3.ZERO, 6))
	root.add_child(_box(Vector3(0.7, 0.1, 0.1), mat(C_WOOD_DARK), Vector3(0.3, 3.35, 0)))
	var bulb := SphereMesh.new()
	bulb.radius = 0.22
	bulb.height = 0.44
	bulb.radial_segments = 6
	var bulb_mi := _mi(bulb, glow_mat(Color(1.0, 0.86, 0.55)), Vector3(0.62, 3.15, 0))
	root.add_child(bulb_mi)
	var light := OmniLight3D.new()
	light.position = Vector3(0.62, 3.15, 0)
	light.light_color = Color(1.0, 0.84, 0.55)
	light.light_energy = 5.0
	light.omni_range = 12.0
	light.set_meta("night_light", true)
	root.add_child(light)
	root.set_meta("collide_radius", 0.4)
	return root


# ——————————————— 矿洞入口 ———————————————
static func make_mine() -> Node3D:
	var root := Node3D.new()
	# 岩壁
	var rock := SphereMesh.new()
	rock.radius = 3.2
	rock.height = 4.4
	rock.radial_segments = 8
	rock.rings = 4
	root.add_child(_mi(rock, mat(Color(0.40, 0.35, 0.30)), Vector3(0, 1.6, -1.0), Vector3.ZERO, Vector3(1.0, 0.85, 0.8)))
	# 洞口
	root.add_child(_box(Vector3(2.0, 2.4, 0.6), mat(Color(0.06, 0.05, 0.05)), Vector3(0, 1.2, 1.4)))
	# 木支撑
	for sx in [-1.0, 1.0]:
		root.add_child(_box(Vector3(0.26, 2.6, 0.26), mat(C_WOOD_DARK), Vector3(sx * 1.25, 1.3, 1.6)))
	root.add_child(_box(Vector3(3.2, 0.3, 0.34), mat(C_WOOD_DARK), Vector3(0, 2.7, 1.6)))
	# 矿车轨道
	for i in 6:
		root.add_child(_box(Vector3(1.8, 0.08, 0.35), mat(C_WOOD), Vector3(0, 0.05, 3.0 + float(i) * 0.7)))
	root.add_child(_box(Vector3(1.1, 0.7, 0.9), mat(Color(0.35, 0.35, 0.38), 0.5), Vector3(0, 0.45, 3.4)))
	root.set_meta("collide_radius", 3.0)
	return root


# ——————————————— 菜地 ———————————————
static func make_garden() -> Node3D:
	var root := Node3D.new()
	root.add_child(_box(Vector3(3.6, 0.3, 3.6), mat(Color(0.33, 0.22, 0.14)), Vector3(0, 0.15, 0)))
	for i in 3:
		for j in 3:
			var sp := SphereMesh.new()
			sp.radius = 0.3
			sp.height = 0.42
			sp.radial_segments = 6
			sp.rings = 3
			root.add_child(_mi(sp, mat(Color(0.32, 0.52, 0.20)),
				Vector3(-1.1 + float(i) * 1.1, 0.42, -1.1 + float(j) * 1.1)))
	root.set_meta("collide_radius", 0.0)
	return root


# ——————————————— 路牌 ———————————————
static func make_signpost() -> Node3D:
	var root := Node3D.new()
	root.add_child(_cyl(0.10, 2.8, mat(C_WOOD_DARK), Vector3(0, 1.4, 0), Vector3.ZERO, 6))
	root.add_child(_box(Vector3(2.2, 0.5, 0.08), mat(C_WOOD_LIGHT), Vector3(0.5, 2.4, 0), Vector3(0, 0, -0.08)))
	root.add_child(_box(Vector3(1.8, 0.42, 0.08), mat(Color(0.55, 0.36, 0.22)), Vector3(-0.4, 1.9, 0.06), Vector3(0, 0, 0.1)))
	root.set_meta("collide_radius", 0.3)
	return root


# ——————————————— 晾衣绳 ———————————————
static func make_clothesline() -> Node3D:
	var root := Node3D.new()
	for sx in [-1.0, 1.0]:
		root.add_child(_cyl(0.09, 2.6, mat(C_WOOD_DARK), Vector3(sx * 2.4, 1.3, 0), Vector3.ZERO, 6))
	root.add_child(_cyl(0.03, 4.8, mat(C_ROPE), Vector3(0, 2.5, 0), Vector3(0, 0, PI * 0.5), 4))
	var cols := [Color(0.85, 0.35, 0.35), Color(0.4, 0.6, 0.85), Color(0.9, 0.85, 0.5), Color(0.6, 0.8, 0.6)]
	for i in 4:
		root.add_child(_box(Vector3(0.7, 0.9, 0.04), mat(cols[i]),
			Vector3(-1.6 + float(i) * 1.05, 2.0, 0)))
	root.set_meta("collide_radius", 0.0)
	return root


# ——————————————— 木箱堆 / 桶 ———————————————
static func make_crates() -> Node3D:
	var root := Node3D.new()
	root.add_child(_box(Vector3(1.0, 1.0, 1.0), mat(C_WOOD_LIGHT), Vector3(0, 0.5, 0)))
	root.add_child(_box(Vector3(0.9, 0.9, 0.9), mat(C_WOOD), Vector3(0.9, 0.45, 0.35), Vector3(0, 0.4, 0)))
	root.add_child(_box(Vector3(0.8, 0.8, 0.8), mat(C_WOOD_LIGHT), Vector3(-0.2, 1.4, 0.1), Vector3(0, -0.3, 0)))
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.45
	barrel.bottom_radius = 0.45
	barrel.height = 1.1
	barrel.radial_segments = 8
	root.add_child(_mi(barrel, mat(Color(0.45, 0.31, 0.20)), Vector3(1.7, 0.55, -0.6)))
	root.set_meta("collide_radius", 1.2)
	return root
