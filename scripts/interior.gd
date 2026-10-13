extends Node3D
class_name InteriorSystem
## 室内家具在实际建筑里生成。出入只更新环境状态，不传送、不切场景、不冻结运动。
## 门洞与可转动门板来自同一建筑规格，碰撞和可见模型共享铰链。
const Assets := preload("res://scripts/optional_assets.gd")
const DOOR_REACH := 1.8
# 95度给门框留余量；每秒360度，使一扇门约0.26秒打开，跑向门口时仍能及时通过。
const DOOR_OPEN_ANGLE := 1.658063
const DOOR_SPEED := 6.283185
const FADE_OUT := 0.16
const FADE_IN := 0.28
const FADE_LAYER := 60
const SPEC := {
	"hut": {"title": "木顶小屋", "shape": "box", "w": 7.6, "d": 6.6, "h": 3.2,
		"door_z": 3.3, "exit_pad": 1.45, "door_w": 1.8, "door_h": 2.5},
	"shop": {"title": "杂货铺", "shape": "box", "w": 11.0, "d": 8.0, "h": 3.6,
		"door_z": 4.0, "exit_pad": 1.45, "door_w": 2.2, "door_h": 2.7},
	"tent": {"title": "帐篷", "shape": "round", "r": 2.5, "h": 2.3,
		"door_z": 2.5, "exit_pad": 1.45, "door_w": 1.6, "door_h": 2.1},
}
var _spaces: Dictionary = {}
var busy := false # 仅睡觉推进时间使用淡出；走门不经过此状态。
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _player: Node3D

func _ready() -> void: _build_fade()

static func is_enterable(kind: String) -> bool: return SPEC.has(kind)
static func spec_of(kind: String) -> Dictionary: return SPEC.get(kind, {})
static func door_dir(rot: float) -> Vector2: return Vector2(sin(rot), cos(rot))
static func door_point(center2: Vector2, rot: float, kind: String) -> Vector2:
	return center2 + door_dir(rot) * float(spec_of(kind).get("door_z", 3.3))
static func exit_point(center2: Vector2, rot: float, kind: String) -> Vector2:
	var spec: Dictionary = spec_of(kind)
	return door_point(center2, rot, kind) + door_dir(rot) * float(spec.get("exit_pad", 1.45))
static func at_door(pos: Vector3, center2: Vector2, rot: float, kind: String) -> bool:
	var offset := Vector2(pos.x, pos.z) - door_point(center2, rot, kind)
	var side := Vector2(cos(rot), -sin(rot))
	return offset.length() < DOOR_REACH and absf(offset.dot(side)) < float(spec_of(kind).get("door_w", 1.8)) * 0.5 + 0.3

func register(id: String, kind: String, seed_val: int, house: Node3D) -> Dictionary:
	if _spaces.has(id): return _spaces[id]
	var spec: Dictionary = spec_of(kind)
	var room := Node3D.new()
	room.name = "RoomContents"
	room.position.y = float(house.get_meta("floor_height", 0.18))
	room.set_meta("camera_obstacle", true)
	house.add_child(room)
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(seed_val * 31 + hash(id)) % 2147483000
	var cols: Array = []
	var bed := Vector3.ZERO
	if kind == "tent":
		bed = _build_tent(room, float(spec.r), float(spec.h), rng, false)
	elif kind == "shop":
		_build_shop(room, float(spec.w), float(spec.d), float(spec.h), {}, rng, Vector2.ZERO, cols, false)
	else:
		bed = _build_hut(room, float(spec.w), float(spec.d), float(spec.h), {}, rng, Vector2.ZERO, cols, false)
	preload("res://scripts/world_collision.gd").attach(room)
	var pivot: Node3D = house.get_node_or_null("DoorPivot")
	var door := AnimatableBody3D.new()
	door.name = "DoorSolid"
	door.collision_layer = 17
	door.collision_mask = 6
	# 每个物理帧由主控推进铰链，避免同时使用 Tween 和物理同步互相覆盖。
	door.sync_to_physics = false
	door.position = pivot.position
	house.add_child(door)
	pivot.reparent(door, false)
	pivot.position = Vector3.ZERO
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(float(spec.door_w), float(spec.door_h), 0.10)
	collision.shape = box
	collision.position = Vector3(float(spec.door_w) * 0.5, float(spec.door_h) * 0.5, 0)
	door.add_child(collision)
	var center3: Vector3 = room.global_position
	var half := Vector2(float(spec.get("w", float(spec.get("r", 2.5)) * 2.0)), float(spec.get("d", float(spec.get("r", 2.5)) * 2.0))) * 0.5
	var space := {"id": id, "kind": kind, "title": spec.title, "node": room, "frame": house,
		"center": Vector2(center3.x, center3.z), "floor_y": center3.y, "half": half,
		"spawn": room.to_global(Vector3(0, 0.03, 0)), "colliders": [],
		"bed": room.to_global(bed), "can_sleep": kind != "shop", "door": door, "open": false}
	_spaces[id] = space
	return space

func ensure(id: String, _kind: String, _seed: int) -> Dictionary: return space_of(id)
func space_of(id: String) -> Dictionary: return _spaces.get(id, {})
func forget(id: String) -> void: _spaces.erase(id)

func covers_ground(point: Vector2, margin := 0.25) -> bool:
	for space: Dictionary in _spaces.values():
		if not is_instance_valid(space.frame): continue
		if _covers(space.frame, str(space.kind), point, margin): return true
	return false

static func _covers(frame: Node3D, kind: String, point: Vector2, margin: float) -> bool:
	var local := frame.to_local(Vector3(point.x, frame.global_position.y, point.y))
	var spec: Dictionary = spec_of(kind)
	if kind == "tent": return Vector2(local.x, local.z).length() < float(spec.r) + margin
	return absf(local.x) < float(spec.w) * 0.5 + margin and absf(local.z) < float(spec.d) * 0.5 + margin

func clear_groundcover(world: Node3D, frame: Node3D, kind: String) -> void:
	# 玩家自建帐篷时清掉既有地被；headless 的 Dummy 后端不能读回真实变换，禁止误删。
	if DisplayServer.get_name() == "headless": return
	for instance in world.find_children("*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = instance.multimesh
		var kept: Array[Transform3D] = []
		for index in mm.instance_count:
			var transform := mm.get_instance_transform(index)
			var point: Vector3 = instance.global_transform * transform.origin
			if point.y < -100 or not _covers(frame, kind, Vector2(point.x, point.z), 0.3): kept.append(transform)
		if kept.size() == mm.instance_count: continue
		mm.instance_count = kept.size()
		for index in kept.size(): mm.set_instance_transform(index, kept[index])

func space_at(pos: Vector3) -> Dictionary:
	for space: Dictionary in _spaces.values():
		var house: Node3D = space.frame
		if not is_instance_valid(house): continue
		var local := house.to_local(pos)
		var spec: Dictionary = spec_of(space.kind)
		if local.y < float(house.get_meta("floor_height", 0.18)) - 0.12 or local.y > float(spec.h): continue
		var inside: bool
		if space.kind == "tent":
			inside = Vector2(local.x, local.z).length() < float(spec.r) - 0.12
		else:
			inside = absf(local.x) < float(spec.w) * 0.5 - 0.12 and absf(local.z) < float(spec.d) * 0.5 - 0.12
		if inside: return space
	return {}

func near_door(id: String, pos: Vector3) -> bool:
	var space := space_of(id)
	if space.is_empty(): return false
	var local: Vector3 = space.frame.to_local(pos)
	var spec: Dictionary = spec_of(space.kind)
	var offset := Vector2(local.x, local.z - float(spec.door_z))
	return absf(local.x) < float(spec.door_w) * 0.5 + 0.3 and offset.length() < DOOR_REACH and local.y > -0.3 and local.y < float(spec.door_h) + 0.3

func set_open(id: String, value: bool) -> bool:
	var space := space_of(id)
	if space.is_empty(): return false
	if not value and is_instance_valid(_player):
		var local: Vector3 = space.frame.to_local(_player.global_position)
		var spec: Dictionary = spec_of(space.kind)
		# 门扇扫过的矩形加胶囊半径；有人站在其中时拒绝关门，不能夹住或把人顶出墙。
		if absf(local.x) < float(spec.door_w) * 0.5 + 0.42 and local.z < float(spec.door_z) + 0.45 and local.z > float(spec.door_z) - float(spec.door_w) - 0.45:
			return false
	space.open = value
	return true

func tick_doors(player: Node3D, dt: float) -> void:
	_player = player
	for space: Dictionary in _spaces.values():
		var house: Node3D = space.frame
		if not is_instance_valid(house): continue
		var local := house.to_local(player.global_position)
		var spec: Dictionary = spec_of(space.kind)
		var offset := local.z - float(spec.door_z)
		var velocity: Vector3 = house.global_basis.inverse() * player.velocity
		# 只在门前真正向门推进时推开；路过旁边或静止站门口不会自动开门。
		if absf(local.x) < float(spec.door_w) * 0.5 - 0.25 and absf(offset) < 1.0 and local.y < float(spec.door_h) and velocity.z * signf(offset) < -0.05:
			space.open = true
		space.door.rotation.y = move_toward(space.door.rotation.y, DOOR_OPEN_ANGLE if space.open else 0.0, DOOR_SPEED * dt)

func serialize_doors() -> Dictionary:
	var states := {}
	for id in _spaces: states[id] = bool(_spaces[id].open)
	return states
func restore_doors(states: Variant) -> void:
	for id in _spaces:
		var open: bool = states is Dictionary and bool(states.get(id, false))
		_spaces[id].open = open
		_spaces[id].door.rotation.y = DOOR_OPEN_ANGLE if open else 0.0

# ——————————————— 过场 ———————————————
## 淡出后推进睡觉时间再淡入；出入建筑不得调用此方法。
func warp(mid: Callable) -> void:
	if busy:
		return
	busy = true
	_fade_layer.visible = true
	_fade.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, FADE_OUT)
	tw.tween_callback(mid)
	tw.tween_property(_fade, "modulate:a", 0.0, FADE_IN)
	tw.tween_callback(func():
		busy = false
		_fade_layer.visible = false
	)


func _build_fade() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "InteriorFade"
	_fade_layer.layer = FADE_LAYER
	_fade_layer.visible = false
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.02, 0.03, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 必须一次性把锚点和 offsets 都设了：只设 anchors 的话新建控件会带着
	# offset_right = -W，铺不满屏幕，黑场只在左半边出现。
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade)
	add_child(_fade_layer)


# ——————————————— 几何工具 ———————————————
## 室内材质【不】走 Props.mat：那个工厂按颜色缓存并返回同一个实例，
## 室内为了挡住穿墙的相机要把 cull_mode 改成双面，改一下会波及户外所有同色物件。
static var _mats: Dictionary = {}


static func _mat(color: Color, rough := 0.92) -> StandardMaterial3D:
	var key := "%d_%d_%d_%d" % [int(color.r * 255), int(color.g * 255), int(color.b * 255), int(rough * 100)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# 双面：第三人称相机没有碰撞，玩家贴墙站或抬头时相机会穿到墙外/天花板上方。
	# 单面材质那时会被背面剔除，直接看穿整个屋子。双面起码挡成一片实色。
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


static func glow_mat(color: Color) -> StandardMaterial3D:
	var m := _mat(color, 0.5)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.4
	return m


static func _mi(mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	return mi


static func _box(size: Vector3, m: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := _mi(b, m, pos)
	if m.get_meta("surface_kind", "") == "wood":
		Assets.cover_mesh(mi, "beam")
	return mi


static func _cyl(r: float, h: float, m: Material, pos := Vector3.ZERO, seg := 10) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return _mi(c, m, pos)


## 墙的一段：a..b 是沿墙长度方向的区间，y0..y1 是竖直区间。
## 用来拼"带洞的墙"——Godot 的 PrimitiveMesh 没有开洞能力，只能切成几块凑。
static func _piece(along_x: bool, a: float, b: float, y0: float, y1: float, t: float, m: Material) -> MeshInstance3D:
	var L := b - a
	var h := y1 - y0
	if L <= 0.002 or h <= 0.002:
		return null
	var mid := (a + b) * 0.5
	var cy := (y0 + y1) * 0.5
	if along_x:
		return _box(Vector3(L, h, t), m, Vector3(mid, cy, 0.0))
	return _box(Vector3(t, h, L), m, Vector3(0.0, cy, mid))


## 一面墙。hole 为空就是整面；否则拆成左右两段 + 门楣（洞下方那块只有门槛时才需要）。
static func _wall(L: float, H: float, t: float, along_x: bool, hole: Dictionary, m: Material) -> Node3D:
	var root := Node3D.new()
	if hole.is_empty():
		root.add_child(_piece(along_x, -L * 0.5, L * 0.5, 0.0, H, t, m))
		return root
	var ha: float = float(hole.get("at", 0.0)) - float(hole.get("w", 1.4)) * 0.5
	var hb: float = float(hole.get("at", 0.0)) + float(hole.get("w", 1.4)) * 0.5
	var y0: float = float(hole.get("y0", 0.0))
	var y1: float = float(hole.get("y1", 2.1))
	for p in [
		_piece(along_x, -L * 0.5, ha, 0.0, H, t, m),
		_piece(along_x, hb, L * 0.5, 0.0, H, t, m),
		_piece(along_x, ha, hb, y1, H, t, m),
		_piece(along_x, ha, hb, 0.0, y0, t, m),
	]:
		if p != null:
			root.add_child(p)
	return root


## 窗：一块半透明玻璃贴在墙洞里 + 一盏冷色补光，让白天室内不至于死黑。
## pos 是玻璃中心（相对所在墙节点的局部坐标），inward 是"朝屋内"的方向，
## 补光按它往里挪一米——贴在墙面上的灯会被墙挡住，等于白放。
static func _window(along_x: bool, at: float, w: float, y0: float, y1: float,
		pos: Vector3, inward: Vector3) -> Node3D:
	var root := Node3D.new()
	var gm := _mat(Color(0.72, 0.84, 0.92, 1.0), 0.15)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.72, 0.84, 0.92, 0.35)
	var cy := (y0 + y1) * 0.5
	var g: MeshInstance3D
	if along_x:
		g = _box(Vector3(w, y1 - y0, 0.06), gm, Vector3(pos.x + at, cy, pos.z))
	else:
		g = _box(Vector3(0.06, y1 - y0, w), gm, Vector3(pos.x, cy, pos.z + at))
	root.add_child(g)

	var l := OmniLight3D.new()
	# 【为什么不带 night_light 这个 meta】day_night 只收带它的灯当"夜灯"，
	# 白天会被整体关掉。室内的灯必须昼夜都亮，否则白天进屋一片漆黑。
	l.light_color = Color(0.86, 0.92, 1.0)
	l.light_energy = 2.6
	l.omni_range = 6.0
	if along_x:
		l.position = Vector3(pos.x + at, cy, pos.z) + inward
	else:
		l.position = Vector3(pos.x, cy, pos.z + at) + inward
	root.add_child(l)
	return root


## 暖光顶灯：屋子主光源。能量压到 1.6 ——室内本来就该比户外暗一档，
## 但全靠它就太暗，配合窗光刚好。
static func _lamp(pos: Vector3, energy := 1.6, range_m := 8.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.80, 0.56)
	l.light_energy = energy
	l.omni_range = range_m
	l.position = pos
	return l


# ——————————————— 铁皮小屋室内 ———————————————
## 返回床的局部坐标（玩家睡觉的交互点）
static func _build_hut(root: Node3D, w: float, d: float, h: float, hole: Dictionary,
		rng: RandomNumberGenerator, center: Vector2, cols: Array, shell := true) -> Vector3:
	var floor_m := _mat(Color(0.52, 0.36, 0.24))
	floor_m.set_meta("surface_kind", "wood")
	var wall_m := _mat(Color(0.88, 0.84, 0.74))
	var wood := _mat(Color(0.46, 0.31, 0.20))
	wood.set_meta("surface_kind", "wood")
	var wood_l := _mat(Color(0.68, 0.50, 0.33))
	wood_l.set_meta("surface_kind", "wood")
	var iron := _mat(Color(0.36, 0.36, 0.38), 0.7)

	if shell:
		root.add_child(_box(Vector3(w, 0.24, d), floor_m, Vector3(0, -0.12, 0)))
		root.add_child(_box(Vector3(w, 0.24, d), _mat(Color(0.74, 0.70, 0.62)), Vector3(0, h + 0.12, 0)))

		# 门在 +Z 墙（与室外模型一致：玩家从 +Z 方向进来）
		var door_w: float = float(hole.get("w", 1.4))
		var door_h: float = float(hole.get("y1", 2.1))
		var wp := _wall(w, h, 0.28, true, hole, wall_m)
		wp.position.z = d * 0.5
		root.add_child(wp)
		# 完整壳体模式仅用于独立家具预览；正式房屋传shell=false，不重复生成外墙与门。
		# 正式门洞与活动门由外部建筑提供。
		root.add_child(_box(Vector3(door_w + 0.3, door_h + 0.12, 0.34), wood,
			Vector3(0, (door_h + 0.12) * 0.5, d * 0.5)))
		root.add_child(_box(Vector3(door_w - 0.08, door_h - 0.08, 0.10), wood_l,
			Vector3(0, door_h * 0.5, d * 0.5)))

		var wz := _wall(w, h, 0.28, true, {}, wall_m)
		wz.position.z = -d * 0.5
		root.add_child(wz)

		var win_hole := {"at": 0.0, "w": 1.8, "y0": 1.05, "y1": 2.05}
		for s in [-1.0, 1.0]:
			var wx := _wall(d, h, 0.28, false, win_hole, wall_m)
			wx.position.x = s * w * 0.5
			root.add_child(wx)
			root.add_child(_window(false, 0.0, 1.8, 1.05, 2.05,
				Vector3(s * w * 0.5, 0.0, 0.0), Vector3(-s * 1.0, 0.0, 0.0)))

		# —— 家具 ——
	# 床：靠 -X 墙
	var bed := Node3D.new()
	bed.position = Vector3(-w * 0.5 + 1.5, 0.0, -d * 0.5 + 1.7)
	bed.add_child(_box(Vector3(1.25, 0.34, 2.2), wood, Vector3(0, 0.30, 0)))
	bed.add_child(_box(Vector3(1.15, 0.22, 2.1), _mat(Color(0.80, 0.78, 0.70)), Vector3(0, 0.58, 0)))
	bed.add_child(_box(Vector3(0.9, 0.16, 0.42), _mat(Color(0.90, 0.88, 0.82)), Vector3(0, 0.74, -0.78)))
	bed.add_child(_box(Vector3(1.2, 0.5, 0.12), wood, Vector3(0, 0.5, -1.12)))
	Assets.replace_group(bed, "bed", Vector3(1.25, 0.90, 2.24), Vector3(0, 0.45, 0), true)
	root.add_child(bed)
	cols.append({"pos": center + Vector2(-w * 0.5 + 1.5, -d * 0.5 + 1.7), "r": 1.2})

	# 木桌 + 两把椅子
	var tx := w * 0.5 - 2.1
	var tz := -d * 0.5 + 1.9
	var table := Node3D.new()
	table.position = Vector3(tx, 0, tz)
	table.add_child(_box(Vector3(1.7, 0.12, 0.95), wood_l, Vector3(0, 0.76, 0)))
	for sx in [-0.72, 0.72]:
		for sz in [-0.36, 0.36]:
			table.add_child(_box(Vector3(0.11, 0.76, 0.11), wood, Vector3(sx, 0.38, sz)))
	Assets.replace_group(table, "table", Vector3(1.7, 0.82, 0.95), Vector3(0, 0.41, 0), true)
	root.add_child(table)
	cols.append({"pos": center + Vector2(tx, tz), "r": 1.0})
	for s in [-1.0, 1.0]:
		var ch := Node3D.new()
		ch.position = Vector3(tx + s * 1.35, 0.0, tz + 0.15)
		ch.add_child(_box(Vector3(0.5, 0.10, 0.5), wood_l, Vector3(0, 0.46, 0)))
		ch.add_child(_box(Vector3(0.5, 0.55, 0.09), wood, Vector3(0, 0.74, -0.21)))
		for ax in [-0.2, 0.2]:
			for az in [-0.2, 0.2]:
				ch.add_child(_box(Vector3(0.08, 0.46, 0.08), wood, Vector3(ax, 0.23, az)))
		Assets.replace_group(ch, "chair", Vector3(0.5, 0.55, 0.5), Vector3(0, 0.275, 0))
		root.add_child(ch)

	# 铁皮炉灶 + 烟囱：屋里的视觉中心，也是主光源
	var sx := w * 0.5 - 1.6
	var sz := d * 0.5 - 2.4
	var stove := Node3D.new()
	stove.position = Vector3(sx, 0.0, sz)
	stove.add_child(_cyl(0.44, 1.15, iron, Vector3(0, 0.58, 0), 10))
	stove.add_child(_box(Vector3(0.34, 0.30, 0.10), glow_mat(Color(1.0, 0.55, 0.18)), Vector3(0, 0.42, 0.45)))
	stove.add_child(_cyl(0.15, h - 1.15, iron, Vector3(0, 1.15 + (h - 1.15) * 0.5, 0), 8))
	Assets.replace_group(stove, "stove", Vector3(0.88, h, 0.9), Vector3(0, h * 0.5, 0))
	root.add_child(stove)
	root.add_child(_lamp(Vector3(sx, 1.1, sz), 2.2, 7.5))
	cols.append({"pos": center + Vector2(sx, sz), "r": 0.62})

	# 木箱：靠门这侧，进门第一眼能看到
	for i in 2:
		var bx := -w * 0.5 + 1.2 + float(i) * 1.0
		var bz := d * 0.5 - 1.3
		var box := _box(Vector3(0.82, 0.72, 0.82), wood_l, Vector3(bx, 0.36, bz))
		Assets.cover_mesh(box, "crate")
		root.add_child(box)
		var lid := _box(Vector3(0.86, 0.08, 0.86), wood, Vector3(bx, 0.76, bz))
		if box.has_node("AssetVisual"):
			lid.layers = 0
		root.add_child(lid)
		if i == 0:
			cols.append({"pos": center + Vector2(bx, bz), "r": 0.6})

	# 地毯
	root.add_child(_box(Vector3(3.4, 0.04, 2.4), _mat(Color(0.55, 0.24, 0.22)), Vector3(0, 0.02, 0.4)))

	# 桌上的油灯（发光体 + 小范围暖光）
	root.add_child(_cyl(0.10, 0.26, iron, Vector3(tx - 0.5, 0.95, tz - 0.2), 8))
	root.add_child(_box(Vector3(0.18, 0.22, 0.18), glow_mat(Color(1.0, 0.86, 0.55)), Vector3(tx - 0.5, 1.16, tz - 0.2)))
	root.add_child(_lamp(Vector3(tx - 0.5, 1.25, tz - 0.2), 1.1, 4.0))

	# 中央顶灯：保证屋子中间不至于暗角
	root.add_child(_lamp(Vector3(0, h - 0.5, 0), 1.5, 8.5))

	# 墙上的挂画（位置随机但可复现）
	var pic_y := 1.7 + rng.randf() * 0.3
	root.add_child(_box(Vector3(1.0, 0.72, 0.06), _mat(Color(0.72, 0.42, 0.26)),
		Vector3(0, pic_y, -d * 0.5 + 0.2)))

	return bed.position


# ——————————————— 杂货铺室内 ———————————————
static func _build_shop(root: Node3D, w: float, d: float, h: float, hole: Dictionary,
		rng: RandomNumberGenerator, center: Vector2, cols: Array, shell := true) -> void:
	var floor_m := _mat(Color(0.58, 0.44, 0.30))
	floor_m.set_meta("surface_kind", "wood")
	var wall_m := _mat(Color(0.90, 0.86, 0.76))
	var wood := _mat(Color(0.44, 0.30, 0.19))
	wood.set_meta("surface_kind", "wood")
	var wood_l := _mat(Color(0.70, 0.53, 0.35))
	wood_l.set_meta("surface_kind", "wood")

	if shell:
		root.add_child(_box(Vector3(w, 0.24, d), floor_m, Vector3(0, -0.12, 0)))
		root.add_child(_box(Vector3(w, 0.24, d), _mat(Color(0.76, 0.72, 0.64)), Vector3(0, h + 0.12, 0)))

		var door_w: float = float(hole.get("w", 1.6))
		var door_h: float = float(hole.get("y1", 2.3))
		var wp := _wall(w, h, 0.3, true, hole, wall_m)
		wp.position.z = d * 0.5
		root.add_child(wp)
		root.add_child(_box(Vector3(door_w + 0.4, door_h + 0.14, 0.36), wood,
			Vector3(0, (door_h + 0.14) * 0.5, d * 0.5)))
		root.add_child(_box(Vector3(door_w - 0.10, door_h - 0.08, 0.10), wood_l,
			Vector3(0, door_h * 0.5, d * 0.5)))

		var wz := _wall(w, h, 0.3, true, {}, wall_m)
		wz.position.z = -d * 0.5
		root.add_child(wz)

		# 两侧各两个高窗。_wall 一次只支持一个洞，两个洞就手工切成三段墙柱 + 两段窗肚。
		for s in [-1.0, 1.0]:
			var hw: float = 0.8
			var a0 := -d * 0.22
			var a1 := d * 0.22
			var wy0 := 1.5
			var wy1 := 2.6
			var wx := Node3D.new()
			wx.position.x = s * w * 0.5
			for sg in [[-d * 0.5, a0 - hw], [a0 + hw, a1 - hw], [a1 + hw, d * 0.5]]:
				var p := _piece(false, float(sg[0]), float(sg[1]), 0.0, h, 0.3, wall_m)
				if p != null:
					wx.add_child(p)
			for at in [a0, a1]:
				for pr in [[wy1, h], [0.0, wy0]]:
					var q := _piece(false, at - hw, at + hw, float(pr[0]), float(pr[1]), 0.3, wall_m)
					if q != null:
						wx.add_child(q)
				wx.add_child(_window(false, at, 1.6, wy0, wy1,
					Vector3(0.0, 0.0, 0.0), Vector3(-s * 1.2, 0.0, 0.0)))
			root.add_child(wx)

		# —— 柜台 ——
	var cz := -d * 0.5 + 1.8
	root.add_child(_box(Vector3(4.6, 1.05, 0.75), wood, Vector3(-1.2, 0.52, cz)))
	root.add_child(_box(Vector3(4.8, 0.10, 0.92), wood_l, Vector3(-1.2, 1.09, cz)))
	cols.append({"pos": center + Vector2(-1.2, cz), "r": 2.5})
	# 柜台上的秤与罐
	root.add_child(_box(Vector3(0.5, 0.16, 0.5), _mat(Color(0.40, 0.40, 0.44), 0.6), Vector3(-2.4, 1.22, cz)))
	root.add_child(_cyl(0.16, 0.34, _mat(Color(0.72, 0.68, 0.58)), Vector3(0.2, 1.31, cz), 8))

	# —— 货架：两侧靠墙，三层 ——
	# 循环变量取自无类型数组，是 Variant；直接拿它做算术会让下游变量全变成
	# "无法推断类型"，所以先显式转成 float。
	for sv in [-1.0, 1.0]:
		var s := float(sv)
		var sx := s * (w * 0.5 - 0.9)
		var sh := Node3D.new()
		sh.position = Vector3(sx, 0.0, -0.6)
		for i in 3:
			sh.add_child(_box(Vector3(0.85, 0.10, 4.2), wood_l, Vector3(0, 0.6 + float(i) * 0.85, 0)))
			# 层板上的货：颜色随机但由种子决定
			for j in 4:
				var gc := Color(0.42 + rng.randf() * 0.4, 0.34 + rng.randf() * 0.35, 0.26 + rng.randf() * 0.3)
				sh.add_child(_box(Vector3(0.42, 0.42, 0.42), _mat(gc),
					Vector3(0, 0.88 + float(i) * 0.85, -1.6 + float(j) * 1.05)))
		sh.add_child(_box(Vector3(0.12, 3.2, 4.2), wood, Vector3(-s * 0.42, 1.6, 0)))
		Assets.replace_group(sh, "shelf", Vector3(0.85, 3.2, 4.2), Vector3(0, 1.6, 0), true)
		# 货品仍消耗原随机数，换种子和进屋顺序不会改变世界；新货瓶是纯视觉节点。
		for level in 3:
			for item in 4:
				var goods := Assets.fitted("bottle" if item % 2 else "cup", Vector3(0.24, 0.32, 0.24), Vector3(0, 0.78 + level * 0.85, -1.6 + item * 1.05))
				if goods != null:
					sh.add_child(goods)
		root.add_child(sh)
		cols.append({"pos": center + Vector2(sx, -0.6), "r": 0.95})

	# —— 桶与麻袋 ——
	for i in 3:
		var bx := w * 0.5 - 1.3
		var bz := d * 0.5 - 1.6 - float(i) * 1.15
		var barrel := _cyl(0.42, 0.9, wood, Vector3(bx, 0.45, bz), 10)
		Assets.cover_mesh(barrel, "barrel")
		root.add_child(barrel)
		var rim := _cyl(0.44, 0.10, _mat(Color(0.34, 0.34, 0.36), 0.6), Vector3(bx, 0.92, bz), 10)
		if barrel.has_node("AssetVisual"):
			rim.layers = 0
		root.add_child(rim)
	for i in 2:
		var pz := d * 0.5 - 1.4 - float(i) * 1.0
		var bag := _box(Vector3(0.9, 0.8, 0.7), _mat(Color(0.76, 0.68, 0.48)), Vector3(-w * 0.5 + 1.1, 0.4, pz))
		Assets.cover_mesh(bag, "bag")
		root.add_child(bag)

	# —— 灯：铺子要比屋子亮 ——
	root.add_child(_lamp(Vector3(0.0, h - 0.6, 0.0), 2.0, 12.0))
	root.add_child(_lamp(Vector3(-3.2, h - 0.8, -1.5), 1.4, 9.0))
	root.add_child(_lamp(Vector3(3.2, h - 0.8, 1.5), 1.4, 9.0))


# ——————————————— 帐篷室内 ———————————————
## 返回睡袋的局部坐标（帐篷里睡觉的交互点）
static func _build_tent(root: Node3D, r: float, h: float, rng: RandomNumberGenerator, shell := true) -> Vector3:
	var canvas := _mat(Color(0.86, 0.80, 0.65))
	var wood := _mat(Color(0.46, 0.31, 0.20))
	wood.set_meta("surface_kind", "wood")

	if shell:
		root.add_child(_cyl(r, 0.2, _mat(Color(0.60, 0.52, 0.38)), Vector3(0, -0.1, 0), 12))

		# 侧壁：关掉上下盖，只留一圈布
		var wall := CylinderMesh.new()
		wall.top_radius = r
		wall.bottom_radius = r
		wall.height = h
		wall.radial_segments = 12
		wall.rings = 1
		wall.cap_top = false
		wall.cap_bottom = false
		root.add_child(_mi(wall, canvas, Vector3(0, h * 0.5, 0)))

		# 锥顶
		var cone := CylinderMesh.new()
		cone.bottom_radius = r
		cone.top_radius = 0.0
		cone.height = 1.5
		cone.radial_segments = 12
		cone.rings = 1
		root.add_child(_mi(cone, canvas, Vector3(0, h + 0.75, 0)))

		# 睡袋 + 木箱 + 小灯
	root.add_child(_box(Vector3(1.1, 0.24, 2.2), _mat(Color(0.42, 0.50, 0.40)), Vector3(-r * 0.45, 0.12, -0.6)))
	root.add_child(_box(Vector3(0.8, 0.16, 0.45), _mat(Color(0.88, 0.86, 0.78)), Vector3(-r * 0.45, 0.30, -1.5)))
	var crate := _box(Vector3(0.78, 0.62, 0.78), wood, Vector3(r * 0.5, 0.31, -0.9))
	Assets.cover_mesh(crate, "crate")
	root.add_child(crate)
	root.add_child(_cyl(0.13, 0.34, _mat(Color(0.34, 0.34, 0.36), 0.6), Vector3(r * 0.5, 0.72, -0.9), 8))
	root.add_child(_box(Vector3(0.18, 0.20, 0.18), glow_mat(Color(1.0, 0.84, 0.52)), Vector3(r * 0.5, 0.94, -0.9)))
	root.add_child(_lamp(Vector3(r * 0.5, 1.05, -0.9), 1.6, 6.0))
	root.add_child(_lamp(Vector3(0.0, h * 0.72, 0.4), 1.0, 5.5))

	return Vector3(-r * 0.45, 0.0, -0.6)
