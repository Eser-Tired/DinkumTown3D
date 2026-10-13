extends RefCounted
class_name Props
## 建筑与道具工厂：可选本地美术与缺包时的程序化外观共用玩法入口。
## 每个 make_* 返回模型；正式放置时由 world_collision.gd 添加实体碰撞。
## collide_radius 只用于建筑占地检查。

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
const Surfaces := preload("res://scripts/materials.gd")
const Assets := preload("res://scripts/optional_assets.gd")
const Rooms := preload("res://scripts/interior.gd")


static func mat(color: Color, rough := 0.92, metal := 0.0) -> StandardMaterial3D:
	var key := "%d_%d_%d" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]
	key += "_%d_%d" % [int(rough * 100), int(metal * 100)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_mats[key] = m
	return m


static func surface(kind: String, color: Color, rough := 0.9, metal := 0.0) -> Material:
	return Surfaces.surface(kind, color, rough, metal)


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
	if m.get_meta("surface_kind", "") == "stone":
		Assets.cover_mesh(mi, "rock")
	return mi


static func _box(size: Vector3, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := _mi(b, Surfaces.for_box(m, size), pos, rot)
	if m.get_meta("surface_kind", "") == "wood":
		Assets.cover_mesh(mi, "beam")
	return mi


static func _cyl(r: float, h: float, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, seg := 8) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	var mi := _mi(c, m, pos, rot)
	if m.get_meta("surface_kind", "") in ["wood", "bark"]:
		Assets.cover_mesh(mi, "post")
	return mi


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
	var spec: Dictionary = Rooms.spec_of("tent")
	var r := float(spec.r)
	var h := float(spec.h)
	var door_w := float(spec.door_w)
	var door_h := float(spec.door_h)
	var floor_y := 0.18
	var wall := surface("canvas", C_CANVAS)
	root.add_child(_cyl(r, floor_y, surface("wood", C_WOOD), Vector3(0, floor_y * 0.5, 0), Vector3.ZERO, 24))
	var roof := Node3D.new()
	roof.name = "Roof"
	roof.add_child(_cone(r + 0.08, 1.5, wall, Vector3(0, floor_y + h + 0.75, 0), Vector3.ZERO, 24))
	root.add_child(roof)
	var width := 2.0 * r * sin(PI / 24.0)
	for i in 24:
		var angle := TAU * float(i) / 24.0
		var point := Vector3(sin(angle) * r, floor_y + h * 0.5, cos(angle) * r)
		# 用分段布墙留出前方门洞，整圆筒或整体凸包都会堵住可行走的内部。
		if point.z > 0 and absf(point.x) < door_w * 0.5 + width * 0.5: continue
		root.add_child(_box(Vector3(width + 0.03, h, 0.10), wall, point, Vector3(0, angle, 0)))
	_door_metadata(root, Vector3(r * 2.0, h, r * 2.0), door_w, door_h)
	var pivot: Node3D = root.get_node("DoorPivot")
	pivot.add_child(_box(Vector3(door_w, door_h, 0.08), wall, Vector3(door_w * 0.5, door_h * 0.5, 0)))
	root.set_meta("collide_radius", 2.7)
	return root

static func _door_metadata(root: Node3D, room_size: Vector3, width: float, height: float) -> void:
	root.set_meta("room_size", room_size)
	root.set_meta("floor_height", 0.18)
	root.set_meta("door_width", width)
	root.set_meta("door_height", height)
	root.set_meta("camera_obstacle", true)
	root.set_meta("entrance_origin", Vector2.ZERO)
	root.set_meta("stair_x", 0.0)
	root.set_meta("exit_distance", room_size.z * 0.5 + 1.45)
	var pivot := Node3D.new()
	pivot.name = "DoorPivot"
	pivot.position = Vector3(-width * 0.5, 0.18, room_size.z * 0.5)
	pivot.set_meta("visual_only", true)
	root.add_child(pivot)

static func _walkable_house(shop: bool, roof_color: Color) -> Node3D:
	var root := Node3D.new()
	var spec: Dictionary = Rooms.spec_of("shop" if shop else "hut")
	var size := Vector3(float(spec.w), float(spec.h), float(spec.d))
	var door_w := float(spec.door_w)
	var door_h := float(spec.door_h)
	var wall := surface("plaster", C_WALL)
	var wood := surface("wood", C_WOOD_DARK)
	root.add_child(_box(Vector3(size.x, 0.18, size.z), wood, Vector3(0, 0.09, 0)))
	for side in [-1.0, 1.0]:
		root.add_child(_box(Vector3(0.18, size.y, size.z), wall, Vector3(float(side) * size.x * 0.5, size.y * 0.5, 0)))
		var width := (size.x - door_w) * 0.5
		root.add_child(_box(Vector3(width, size.y, 0.18), wall, Vector3(float(side) * (door_w * 0.5 + width * 0.5), size.y * 0.5, size.z * 0.5)))
	root.add_child(_box(Vector3(size.x, size.y, 0.18), wall, Vector3(0, size.y * 0.5, -size.z * 0.5)))
	var lintel := size.y - door_h - 0.18
	root.add_child(_box(Vector3(door_w, lintel, 0.18), wall, Vector3(0, size.y - lintel * 0.5, size.z * 0.5)))
	var roof := Node3D.new()
	roof.name = "Roof"
	roof.add_child(_roof(size.x + 0.65, size.z + 0.7, 1.65, surface("iron", roof_color, 0.48), Vector3(0, size.y + 0.825, 0)))
	root.add_child(roof)
	_door_metadata(root, size, door_w, door_h)
	root.get_node("DoorPivot").add_child(_box(Vector3(door_w, door_h, 0.10), wood, Vector3(door_w * 0.5, door_h * 0.5, 0)))
	root.set_meta("collide_radius", Vector2(size.x, size.z).length() * 0.5 + 0.25)
	return root

# ——————————————— 可直接走入的房屋 ———————————————
static func make_hut(roof_col := C_IRON_RED) -> Node3D:
	var model := Assets.instantiate("hut")
	return model if model != null else _walkable_house(false, roof_col)

static func make_shop() -> Node3D:
	var model := Assets.instantiate("shop")
	if model == null: model = _walkable_house(true, C_IRON_GREEN)
	var size: Vector3 = model.get_meta("room_size", Vector3(11, 3.6, 8))
	var sign := Label3D.new()
	sign.text = "杂货铺"
	sign.font_size = 64
	sign.pixel_size = 0.016
	sign.position = Vector3(0, size.y + 0.32, size.z * 0.5 + 0.15)
	model.add_child(sign)
	return model


# ——————————————— 码头 / 木栈桥 ———————————————
static func make_dock(planks := 9) -> Node3D:
	var root := Node3D.new()
	root.set_meta("deck_length", float(planks) * 1.15 + 1.5)
	var wood := surface("wood", C_WOOD)
	var wood_d := surface("wood", C_WOOD_DARK)
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
	boat.add_child(_box(Vector3(0.08, 1.6, 0.08), surface("wood", C_WOOD_DARK), Vector3(0, 0.8, 0)))
	boat.set_meta("bob", 1.0)
	root.add_child(boat)
	root.set_meta("collide_radius", 2.6)
	return root


# ——————————————— 水塔 ———————————————
static func make_watertower() -> Node3D:
	var root := Node3D.new()
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		root.add_child(_box(Vector3(0.26, 5.0, 0.26), surface("wood", C_WOOD_DARK),
			Vector3(cos(a) * 1.5, 2.5, sin(a) * 1.5), Vector3(sin(a) * 0.05, 0, -cos(a) * 0.05)))
	for lvl in [1.4, 3.4]:
		root.add_child(_box(Vector3(3.4, 0.14, 0.14), surface("wood", C_WOOD), Vector3(0, lvl, -1.5)))
		root.add_child(_box(Vector3(3.4, 0.14, 0.14), surface("wood", C_WOOD), Vector3(0, lvl, 1.5)))
		root.add_child(_box(Vector3(0.14, 0.14, 3.4), surface("wood", C_WOOD), Vector3(-1.5, lvl, 0)))
		root.add_child(_box(Vector3(0.14, 0.14, 3.4), surface("wood", C_WOOD), Vector3(1.5, lvl, 0)))
	var tank := CylinderMesh.new()
	tank.top_radius = 2.0
	tank.bottom_radius = 2.0
	tank.height = 2.6
	tank.radial_segments = 10
	root.add_child(_mi(tank, surface("iron", C_IRON_BLUE, 0.48), Vector3(0, 6.3, 0)))
	root.add_child(_cone(2.2, 1.0, mat(C_IRON_RED, 0.7), Vector3(0, 8.1, 0), Vector3.ZERO, 10))
	root.add_child(_cyl(0.12, 2.0, surface("wood", C_WOOD_DARK), Vector3(1.8, 5.6, 0)))
	root.set_meta("collide_radius", 2.4)
	return root


# ——————————————— 风车 ———————————————
static func make_windmill() -> Node3D:
	var root := Node3D.new()
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		root.add_child(_box(Vector3(0.24, 6.4, 0.24), surface("wood", C_WOOD_DARK),
			Vector3(cos(a) * 1.3, 3.2, sin(a) * 1.3), Vector3(sin(a) * 0.08, 0, -cos(a) * 0.08)))
	root.add_child(_box(Vector3(1.6, 0.2, 1.6), surface("wood", C_WOOD), Vector3(0, 6.5, 0)))

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
		root.add_child(_cyl(0.10, 1.3, surface("wood", C_WOOD_DARK), Vector3(-len * 0.5 + float(i) * (len / float(posts - 1)), 0.65, 0), Vector3.ZERO, 6))
	for r in rails:
		root.add_child(_box(Vector3(len, 0.12, 0.10), surface("wood", C_WOOD), Vector3(0, 0.5 + float(r) * 0.5, 0)))
	root.set_meta("collide_radius", 0.0)
	Assets.replace_group(root, "fence", Vector3(len, 1.3, 0.20), Vector3(0, 0.65, 0))
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
		root.add_child(_mi(s, surface("stone", C_STONE), Vector3(cos(a) * 1.05, 0.13, sin(a) * 1.05)))
	var firewood := Node3D.new()
	for i in 4:
		var a := TAU * float(i) / 4.0
		firewood.add_child(_box(Vector3(1.5, 0.16, 0.16), surface("wood", C_WOOD_DARK),
			Vector3(0, 0.22, 0), Vector3(0.16, a, 0.22)))
	Assets.replace_group(firewood, "firewood", Vector3(1.5, 0.35, 1.5), Vector3(0, 0.225, 0))
	root.add_child(firewood)
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
	root.add_child(_cyl(0.11, 3.4, surface("wood", C_WOOD_DARK), Vector3(0, 1.7, 0), Vector3.ZERO, 6))
	root.add_child(_box(Vector3(0.7, 0.1, 0.1), surface("wood", C_WOOD_DARK), Vector3(0.3, 3.35, 0)))
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
		root.add_child(_box(Vector3(0.26, 2.6, 0.26), surface("wood", C_WOOD_DARK), Vector3(sx * 1.25, 1.3, 1.6)))
	root.add_child(_box(Vector3(3.2, 0.3, 0.34), surface("wood", C_WOOD_DARK), Vector3(0, 2.7, 1.6)))
	# 矿车轨道
	for i in 6:
		root.add_child(_box(Vector3(1.8, 0.08, 0.35), surface("wood", C_WOOD), Vector3(0, 0.05, 3.0 + float(i) * 0.7)))
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
	root.add_child(_cyl(0.10, 2.8, surface("wood", C_WOOD_DARK), Vector3(0, 1.4, 0), Vector3.ZERO, 6))
	root.add_child(_box(Vector3(2.2, 0.5, 0.08), surface("wood", C_WOOD_LIGHT), Vector3(0.5, 2.4, 0), Vector3(0, 0, -0.08)))
	root.add_child(_box(Vector3(1.8, 0.42, 0.08), mat(Color(0.55, 0.36, 0.22)), Vector3(-0.4, 1.9, 0.06), Vector3(0, 0, 0.1)))
	root.set_meta("collide_radius", 0.3)
	return root


# ——————————————— 晾衣绳 ———————————————
static func make_clothesline() -> Node3D:
	var root := Node3D.new()
	for sx in [-1.0, 1.0]:
		root.add_child(_cyl(0.09, 2.6, surface("wood", C_WOOD_DARK), Vector3(sx * 2.4, 1.3, 0), Vector3.ZERO, 6))
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
	root.add_child(_box(Vector3(1.0, 1.0, 1.0), surface("wood", C_WOOD_LIGHT), Vector3(0, 0.5, 0)))
	root.add_child(_box(Vector3(0.9, 0.9, 0.9), surface("wood", C_WOOD), Vector3(0.9, 0.45, 0.35), Vector3(0, 0.4, 0)))
	root.add_child(_box(Vector3(0.8, 0.8, 0.8), surface("wood", C_WOOD_LIGHT), Vector3(-0.2, 1.4, 0.1), Vector3(0, -0.3, 0)))
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.45
	barrel.bottom_radius = 0.45
	barrel.height = 1.1
	barrel.radial_segments = 8
	root.add_child(_mi(barrel, mat(Color(0.45, 0.31, 0.20)), Vector3(1.7, 0.55, -0.6)))
	for child in root.get_children():
		if child is MeshInstance3D:
			Assets.cover_mesh(child, "barrel" if child.mesh is CylinderMesh else "crate")
	root.set_meta("collide_radius", 1.2)
	return root
