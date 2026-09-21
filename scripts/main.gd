extends Node3D
## Dinkum 风格 3D 澳洲内陆小镇 —— 世界组装、采集与建造

const PropsS := preload("res://scripts/props.gd")
const FloraS := preload("res://scripts/flora.gd")
const TerrainS := preload("res://scripts/terrain.gd")
const PlayerS := preload("res://scripts/player.gd")
const KangarooS := preload("res://scripts/kangaroo.gd")
const EmuS := preload("res://scripts/emu.gd")
const DayNightS := preload("res://scripts/day_night.gd")
const HUDS := preload("res://scripts/hud.gd")

const TOWN := Vector2(-14.0, -10.0)
const LAKE := Vector2(48.0, 22.0)

const BUILD_ITEMS := [
	{"name": "篝火", "cost": {"wood": 3}, "make": "campfire"},
	{"name": "帐篷", "cost": {"wood": 6, "fiber": 3}, "make": "tent"},
	{"name": "木栅栏", "cost": {"wood": 2}, "make": "fence"},
	{"name": "路灯", "cost": {"wood": 2, "stone": 1}, "make": "lamp"},
]

var terrain: Node3D
var player: CharacterBody3D
var dn: DayNight
var hud: GameHUD
var rng := RandomNumberGenerator.new()

var colliders: Array = []      # {node, pos:Vector2, r:float}
var resources: Array = []      # 可采集节点
var spins: Array = []
var bobs: Array = []
var flickers: Array = []
var placed_pts: Array = []     # 已占用点（避免重叠）

var inv := {"wood": 0, "stone": 0, "fiber": 0, "ore": 0}
var build_mode := false
var build_index := 0
var preview: Node3D = null
var preview_rot := 0.0
var hud_timer := 0.0


func _ready() -> void:
	rng.seed = 20260921

	terrain = TerrainS.new()
	terrain.name = "Terrain"
	add_child(terrain)

	_build_town()
	_scatter_flora()

	player = PlayerS.new()
	player.name = "Player"
	add_child(player)
	player.setup(terrain, colliders, TOWN + Vector2(0.0, 17.0))

	_spawn_critters()

	dn = DayNightS.new()
	dn.name = "DayNight"
	add_child(dn)
	dn.setup(self)
	dn.collect_night_lights(self)

	hud = HUDS.new()
	hud.name = "HUD"
	add_child(hud)
	hud.set_resources(inv)

	_check_auto_shot()


# ——————————————— 放置工具 ———————————————
func _place(node: Node3D, x: float, z: float, rot_y := 0.0, scl := 1.0) -> void:
	node.position = Vector3(x, terrain.height_at(x, z), z)
	node.rotation.y = rot_y
	node.scale = Vector3(scl, scl, scl)
	add_child(node)
	var r: float = node.get_meta("collide_radius", 0.0)
	if r > 0.0:
		colliders.append({"node": node, "pos": Vector2(x, z), "r": r * scl})
		placed_pts.append(Vector2(x, z))
	_collect_anims(node)


func _place_flora(node: Node3D, x: float, z: float, rot := 0.0, scl := 1.0) -> void:
	node.position = Vector3(x, terrain.height_at(x, z), z)
	node.rotation.y = rot
	node.scale = Vector3(scl, scl, scl)
	add_child(node)
	var r: float = node.get_meta("collide_radius", 0.0)
	if r > 0.0:
		colliders.append({"node": node, "pos": Vector2(x, z), "r": r * scl})
		placed_pts.append(Vector2(x, z))
	if node.has_meta("resource"):
		resources.append(node)


func _face_to(from2: Vector2, to2: Vector2) -> float:
	var d := to2 - from2
	return atan2(d.x, d.y)


func _collect_anims(root: Node) -> void:
	if root.has_meta("spin"):
		spins.append({"node": root, "speed": float(root.get_meta("spin"))})
	if root.has_meta("bob"):
		bobs.append({"node": root, "base": root.position.y})
	if root.has_meta("flicker"):
		flickers.append({"node": root, "speed": float(root.get_meta("flicker"))})
	for c in root.get_children():
		_collect_anims(c)


# ——————————————— 小镇 ———————————————
func _build_town() -> void:
	var c := TOWN

	# 中心广场篝火
	_place(PropsS.make_campfire(), c.x, c.y)

	# 杂货铺
	var shop_p := c + Vector2(14, -9)
	_place(PropsS.make_shop(), shop_p.x, shop_p.y, _face_to(shop_p, c))

	# 三间铁皮顶小屋
	var huts := [
		[Vector2(-12, -13), PropsS.C_IRON_RED],
		[Vector2(-4, 11), PropsS.C_IRON_GREEN],
		[Vector2(17, 7), PropsS.C_IRON_BLUE],
	]
	for it in huts:
		var p: Vector2 = c + it[0]
		_place(PropsS.make_hut(it[1]), p.x, p.y, _face_to(p, c) + PI)

	# 帐篷营地
	for off in [Vector2(-21, 3), Vector2(-26, -3), Vector2(-19, 11)]:
		var p: Vector2 = c + off
		_place(PropsS.make_tent(), p.x, p.y, rng.randf() * TAU)
	_place(PropsS.make_campfire(), c.x - 22, c.y + 6)

	# 水塔与风车
	_place(PropsS.make_watertower(), c.x - 10, c.y - 22)
	_place(PropsS.make_windmill(), c.x + 28, c.y - 24)

	# 菜地 + 围栏
	var g0 := c + Vector2(4, 24)
	for i in 3:
		for j in 2:
			var p := g0 + Vector2(float(i) * 4.8, float(j) * 4.8)
			_place(PropsS.make_garden(), p.x, p.y)
	for i in 6:
		var p := g0 + Vector2(-2.7 + float(i) * 4.8, -3.0)
		_place(PropsS.make_fence(4.6), p.x, p.y, 0.0)
	for j in 3:
		var p := g0 + Vector2(-3.0, -2.7 + float(j) * 4.8)
		_place(PropsS.make_fence(4.6), p.x, p.y, PI * 0.5)

	# 杂项
	_place(PropsS.make_clothesline(), c.x - 8, c.y + 12, 0.4)
	_place(PropsS.make_crates(), c.x + 9, c.y + 3)
	_place(PropsS.make_signpost(), c.x + 3, c.y + 13, _face_to(c + Vector2(3, 13), c))

	for off in [Vector2(7, -2), Vector2(-9, 5), Vector2(1, 11), Vector2(-17, -6), Vector2(15, 13)]:
		var p: Vector2 = c + off
		_place(PropsS.make_lamp(), p.x, p.y, rng.randf() * TAU)

	# 码头：从岸边伸入水潭
	var dock_z := 60.0
	for d in range(30, 62):
		var cand := LAKE + Vector2(0.0, float(d))
		if terrain.height_at(cand.x, cand.y) > 0.9:
			dock_z = LAKE.y + float(d)
			break
	if dock_z > 59.0:
		dock_z = LAKE.y + 46.0
	_place(PropsS.make_dock(10), LAKE.x, dock_z, 0.0)

	# 矿洞入口
	var mine_p := Vector2(-58.0, -46.0)
	_place(PropsS.make_mine(), mine_p.x, mine_p.y, _face_to(mine_p, TOWN))

	# 湖边棕榈：沿岸线找落点
	for i in 14:
		var a := rng.randf() * TAU
		var dir := Vector2(cos(a), sin(a))
		for d in range(28, 50):
			var p: Vector2 = LAKE + dir * float(d)
			if absf(p.x) > 100.0 or absf(p.y) > 100.0:
				break
			if terrain.height_at(p.x, p.y) > 1.0 and terrain.height_at(p.x, p.y) < 5.0:
				_place_flora(FloraS.make_palm(rng, rng.randf_range(0.85, 1.15)), p.x, p.y, rng.randf() * TAU)
				break


# ——————————————— 植被与岩石 ———————————————
func _ok_spot(p: Vector2, clear: float, min_town: float, min_lake: float) -> bool:
	if absf(p.x) > 102.0 or absf(p.y) > 102.0:
		return false
	if p.distance_to(TOWN) < min_town:
		return false
	if p.distance_to(LAKE) < min_lake:
		return false
	if terrain.height_at(p.x, p.y) < 0.95:
		return false
	for q in placed_pts:
		if p.distance_to(q) < clear:
			return false
	return true


func _random_spot(min_town: float, min_lake: float, clear: float, tries := 60) -> Vector2:
	for i in tries:
		var p := Vector2(rng.randf_range(-100.0, 100.0), rng.randf_range(-100.0, 100.0))
		if _ok_spot(p, clear, min_town, min_lake):
			placed_pts.append(p)
			return p
	return Vector2.ZERO


func _scatter_flora() -> void:
	for i in 78:
		var p := _random_spot(33.0, 34.0, 4.4)
		if p != Vector2.ZERO:
			_place_flora(FloraS.make_eucalyptus(rng, rng.randf_range(0.8, 1.25)), p.x, p.y, rng.randf() * TAU)

	for i in 34:
		var p := _random_spot(30.0, 32.0, 3.4)
		if p != Vector2.ZERO:
			_place_flora(FloraS.make_acacia(rng, rng.randf_range(0.85, 1.2)), p.x, p.y, rng.randf() * TAU)

	for i in 46:
		var p := _random_spot(26.0, 31.0, 2.4)
		if p != Vector2.ZERO:
			_place_flora(FloraS.make_bush(rng, rng.randf_range(0.8, 1.3)), p.x, p.y, rng.randf() * TAU)

	for i in 24:
		var p := _random_spot(28.0, 31.0, 3.0)
		if p != Vector2.ZERO:
			_place_flora(FloraS.make_rock(rng, rng.randf_range(0.8, 1.4), false), p.x, p.y, rng.randf() * TAU)

	for i in 9:
		var p := _random_spot(36.0, 33.0, 3.4)
		if p != Vector2.ZERO:
			_place_flora(FloraS.make_rock(rng, rng.randf_range(0.9, 1.3), true), p.x, p.y, rng.randf() * TAU)

	# 干草地被（三个 MultiMesh 变体）
	for v in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = FloraS.grass_mesh(rng)
		mm.instance_count = 520
		for i in 520:
			var p := Vector2(rng.randf_range(-100.0, 100.0), rng.randf_range(-100.0, 100.0))
			var y: float = terrain.height_at(p.x, p.y)
			if y < 0.95 or p.distance_to(TOWN) < 13.0:
				mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x, -9999.0, p.y)))
				continue
			var b := Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4))
			mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, y - 0.05, p.y)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = FloraS.grass_material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


# ——————————————— 动物 ———————————————
func _spawn_critters() -> void:
	for i in 11:
		var p := _random_spot(42.0, 38.0, 3.0)
		if p == Vector2.ZERO:
			continue
		var k: Node3D = KangarooS.new()
		add_child(k)
		k.setup(terrain, p, player)

	for i in 4:
		var p := _random_spot(48.0, 40.0, 4.0)
		if p == Vector2.ZERO:
			continue
		var e: Node3D = EmuS.new()
		add_child(e)
		e.setup(terrain, p, player)


# ——————————————— 输入 ———————————————
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				_harvest()
			KEY_B:
				build_mode = not build_mode
				_refresh_preview()
			KEY_1, KEY_2, KEY_3, KEY_4:
				build_index = event.keycode - KEY_1
				build_mode = true
				_refresh_preview()
			KEY_R:
				if build_mode:
					preview_rot += PI * 0.25
			KEY_T:
				dn.toggle_speed()
			KEY_H:
				hud.help_label.visible = not hud.help_label.visible
			KEY_ESCAPE:
				build_mode = false
				_refresh_preview()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and build_mode:
			_try_place_at_mouse()


# ——————————————— 采集 ———————————————
func _nearest_resource() -> Node3D:
	var pp := player.global_position
	var best: Node3D = null
	var bd := 3.8
	for n in resources:
		if not is_instance_valid(n):
			continue
		var d := Vector2(n.global_position.x - pp.x, n.global_position.z - pp.z).length()
		if d < bd:
			bd = d
			best = n
	return best


func _harvest() -> void:
	var n := _nearest_resource()
	if n == null:
		return
	var kind: String = n.get_meta("resource", "wood")
	var amt: int = int(n.get_meta("amount", 1))
	inv[kind] = int(inv.get(kind, 0)) + amt
	hud.set_resources(inv)
	hud.toast("+%d %s" % [amt, hud.RES_NAME[kind]])

	var p := n.global_position
	resources.erase(n)
	for i in range(colliders.size() - 1, -1, -1):
		if colliders[i].node == n:
			colliders.remove_at(i)
			break
	n.queue_free()

	if kind == "wood":
		var stump := FloraS.make_stump()
		stump.position = Vector3(p.x, terrain.height_at(p.x, p.z), p.z)
		add_child(stump)


# ——————————————— 建造 ———————————————
func _make_build(kind: String) -> Node3D:
	match kind:
		"campfire": return PropsS.make_campfire()
		"tent": return PropsS.make_tent()
		"fence": return PropsS.make_fence(4.6)
		"lamp": return PropsS.make_lamp()
	return PropsS.make_campfire()


func _refresh_preview() -> void:
	if preview != null and is_instance_valid(preview):
		preview.queue_free()
	preview = null
	if not build_mode:
		return
	preview = _make_build(BUILD_ITEMS[build_index].make)
	for mi in _all_meshes(preview):
		mi.transparency = 0.5
	add_child(preview)


func _all_meshes(root: Node) -> Array:
	var out := []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_all_meshes(c))
	return out


func _pick_ground(mouse: Vector2) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var t := 0.0
	for i in 320:
		var p := from + dir * t
		if absf(p.x) > 140.0 or absf(p.z) > 140.0:
			break
		if p.y < terrain.height_at(p.x, p.z):
			var lo := maxf(0.0, t - 0.8)
			var hi := t
			for k in 14:
				var mid := (lo + hi) * 0.5
				var pm := from + dir * mid
				if pm.y < terrain.height_at(pm.x, pm.z):
					hi = mid
				else:
					lo = mid
			return from + dir * hi
		t += 0.8
	return Vector3.ZERO


func _can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if int(inv.get(k, 0)) < int(cost[k]):
			return false
	return true


func _place_ok(p: Vector3, r: float) -> bool:
	if p.distance_to(player.global_position) > 15.0:
		return false
	if terrain.height_at(p.x, p.z) < 1.0:
		return false
	if Vector2(p.x, p.z).distance_to(LAKE) < 27.0:
		return false
	for c in colliders:
		if Vector2(p.x, p.z).distance_to(c.pos) < c.r + r + 0.6:
			return false
	return true


func _try_place_at_mouse() -> void:
	if preview == null:
		return
	var p := preview.global_position
	var item: Dictionary = BUILD_ITEMS[build_index]
	if not _place_ok(p, 1.0):
		hud.toast("这里放不下")
		return
	if not _can_afford(item.cost):
		hud.toast("资源不足")
		return
	for k in item.cost:
		inv[k] = int(inv.get(k, 0)) - int(item.cost[k])
	hud.set_resources(inv)
	_place(_make_build(item.make), p.x, p.z, preview_rot)
	hud.toast("已放置 " + item.name)
	dn.collect_night_lights(self)


# ——————————————— 主循环 ———————————————
func _process(dt: float) -> void:
	var t := Time.get_ticks_msec() * 0.001

	for s in spins:
		s.node.rotate_z(s.speed * dt)
	for b in bobs:
		b.node.position.y = b.base + sin(t * 1.1 + b.base * 3.0) * 0.09
		b.node.rotation.z = sin(t * 0.9) * 0.03
	for f in flickers:
		var k := 0.85 + sin(t * 9.0 * f.speed) * 0.12 + sin(t * 21.0 * f.speed) * 0.05
		f.node.scale = Vector3(k, k * 1.1, k)
		f.node.rotation.y += dt * 1.4

	if not build_mode:
		var n := _nearest_resource()
		if n != null:
			var kind: String = n.get_meta("resource", "wood")
			hud.set_prompt("[E] 采集 %s  ×%d" % [hud.RES_NAME[kind], int(n.get_meta("amount", 1))])
		else:
			hud.set_prompt("")
	else:
		var item: Dictionary = BUILD_ITEMS[build_index]
		var cost_txt := ""
		for k in item.cost:
			cost_txt += "%s%d " % [hud.RES_NAME[k], int(item.cost[k])]
		hud.set_prompt("建造模式：左键放置 %s（%s）  [R]旋转  [Esc]退出" % [item.name, cost_txt])

	if build_mode and preview != null:
		var g := _pick_ground(get_viewport().get_mouse_position())
		if g != Vector3.ZERO:
			preview.global_position = g
			preview.rotation.y = preview_rot
			var ok := _place_ok(g, 1.0) and _can_afford(BUILD_ITEMS[build_index].cost)
			for mi in _all_meshes(preview):
				mi.transparency = 0.45 if ok else 0.8

	hud_timer -= dt
	if hud_timer <= 0.0:
		hud_timer = 0.2
		hud.set_clock(dn.day_count, dn.clock_string(), dn.speed_scale)
		hud.set_build(_build_menu_text())


func _build_menu_text() -> String:
	if not build_mode:
		return "[B] 建造模式"
	var s := "建造（1-4 选择）\n"
	for i in BUILD_ITEMS.size():
		var it: Dictionary = BUILD_ITEMS[i]
		var cost := ""
		for k in it.cost:
			cost += "%s%d " % [hud.RES_NAME[k], int(it.cost[k])]
		var mark := ">" if i == build_index else " "
		s += "%s%d. %s  %s\n" % [mark, i + 1, it.name, cost]
	return s


# ——————————————— 自动截图（--auto-shot） ———————————————
func _check_auto_shot() -> void:
	if not OS.get_cmdline_args().has("--auto-shot"):
		return
	var base := "C:/Users/a2402/Documents/Code/DinkumTown3D/"

	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "shot1_morning.png")

	dn.time = 0.72
	player.yaw = -1.80
	player.pitch = -0.22
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "shot2_dusk_lake.png")

	dn.time = 0.02
	player.yaw = 0.35
	player.pitch = -0.42
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "shot3_night.png")

	get_tree().quit()
