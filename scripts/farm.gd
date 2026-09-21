extends Node
class_name FarmSystem
## 农场耕种系统：锄地 → 播种 → 浇水 → 生长 → 收获
## 全部模型用 PrimitiveMesh 程序化生成，零外部素材。
## 存档契约：serialize() / deserialize()，只含 JSON 安全类型。

# ——————————————— 作物表 ———————————————
const CROPS: Array = [
	{"key": "wheat",   "name": "小麦", "cost": {"fiber": 1},           "days": 3.0, "yield": 3, "out": "food",  "color": Color(0.85, 0.74, 0.36)},
	{"key": "pumpkin", "name": "南瓜", "cost": {"fiber": 1, "wood": 1}, "days": 4.5, "yield": 6, "out": "food",  "color": Color(0.86, 0.48, 0.16)},
	{"key": "tomato",  "name": "番茄", "cost": {"fiber": 2},           "days": 3.5, "yield": 4, "out": "food",  "color": Color(0.86, 0.24, 0.20)},
	{"key": "cotton",  "name": "棉花", "cost": {"fiber": 1},           "days": 4.0, "yield": 5, "out": "fiber", "color": Color(0.94, 0.94, 0.90)},
]

# 田块状态
const ST_WILD := 0     # 荒地（未锄）
const ST_TILLED := 1   # 已锄（可播种）
const ST_SEED := 2     # 幼苗
const ST_GROW := 3     # 生长中
const ST_RIPE := 4     # 成熟（可收获）

const COLS := 4
const ROWS := 3
const SPACING := 2.4
const REACH := 3.2          # 交互距离（XZ 平面）
const SEED_RATIO := 0.45    # 幼苗 → 生长中的阈值
const WATER_BONUS := 1.35   # 浇水生长加成
const FALLBACK_ORIGIN := Vector2(-10.0, 24.0)

# ——————————————— 公开状态 ———————————————
var plots: Array = []
var selected: int = 0

# ——————————————— 内部 ———————————————
var _world: Node3D = null
var _terrain: Node3D = null
var _dn: Node = null
var _last_day: int = -1
var _weather: String = "clear"
var _mats: Dictionary = {}
var _missing: Array = []     # setup() 时缺失的依赖项（供调试查看）


func _ready() -> void:
	set_process(true)


# ——————————————— 初始化 ———————————————
func setup(world: Node3D, terrain: Node3D, dn: Node) -> void:
	_world = world
	_terrain = terrain
	_dn = dn
	_missing = []

	if _world == null or not is_instance_valid(_world):
		_missing.append("world")
		_world = null

	if _terrain == null or not is_instance_valid(_terrain):
		# 尝试从 world 上取
		if _world != null:
			var t = _world.get("terrain")
			if t != null and is_instance_valid(t):
				_terrain = t as Node3D
		if _terrain == null or not is_instance_valid(_terrain):
			_terrain = null
			_missing.append("terrain")

	if _dn == null or not is_instance_valid(_dn):
		_dn = null
		_missing.append("dn")

	if _world != null and not _world.has_method("has_item"):
		_missing.append("world.has_item")
	if _world != null and not _world.has_method("take_item"):
		_missing.append("world.take_item")
	if _world != null and not _world.has_method("give_item"):
		_missing.append("world.give_item")

	set_process(true)
	_last_day = -1
	_bind_bus()
	_build_plots()


func _bind_bus() -> void:
	var b: Node = _bus()
	if b == null:
		return
	if b.has_signal("weather_changed") and not b.is_connected("weather_changed", Callable(self, "_on_weather_changed")):
		b.connect("weather_changed", Callable(self, "_on_weather_changed"))
	if b.has_method("register_module"):
		b.call("register_module", "farm", self)


# ——————————————— 田块构建 ———————————————
func _farm_origin() -> Vector2:
	if _world != null:
		var o = _world.get("FARM_ORIGIN")
		if o is Vector2:
			return o
	return FALLBACK_ORIGIN


func _ground_y(x: float, z: float) -> float:
	if _terrain == null or not is_instance_valid(_terrain):
		return 0.0
	if _terrain.has_method("height_at"):
		return float(_terrain.height_at(x, z))
	return 0.0


func _build_plots() -> void:
	_clear_plots()
	var o: Vector2 = _farm_origin()
	for r in ROWS:
		for c in COLS:
			var p: Vector2 = o + Vector2(float(c) * SPACING, float(r) * SPACING)
			plots.append(_make_plot(p))
	for pl: Dictionary in plots:
		_rebuild_visual(pl)


func _make_plot(pos: Vector2) -> Dictionary:
	var n := Node3D.new()
	n.name = "Plot"
	n.position = Vector3(pos.x, _ground_y(pos.x, pos.y), pos.y)
	if _world != null and is_instance_valid(_world):
		_world.add_child(n)
	else:
		add_child(n)
	return {
		"pos": pos,
		"state": ST_WILD,
		"crop": "",
		"growth": 0.0,
		"watered": false,
		"node": n,
	}


func _clear_plots() -> void:
	for pl in plots:
		var n = pl.get("node", null)
		if n != null and is_instance_valid(n):
			n.queue_free()
	plots.clear()


# ——————————————— 材质与网格工具 ———————————————
func _mat(color: Color) -> StandardMaterial3D:
	var key: String = "%d_%d_%d" % [int(color.r * 255.0), int(color.g * 255.0), int(color.b * 255.0)]
	if _mats.has(key):
		var got: StandardMaterial3D = _mats[key]
		return got
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, 1.0)
	m.roughness = 0.9
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_mats[key] = m
	return m


func _mi(mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	return mi


func _box_mi(size: Vector3, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mi(b, m, pos, rot)


func _cyl_mi(r: float, h: float, m: Material, pos: Vector3, rot := Vector3.ZERO, seg := 6) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return _mi(c, m, pos, rot)


func _sphere_mi(r: float, m: Material, pos: Vector3) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 4
	return _mi(s, m, pos)


func _hash01(pl: Dictionary) -> float:
	var p: Vector2 = pl["pos"]
	var v: float = sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453
	return v - floor(v)


# ——————————————— 视觉 ———————————————
func _soil_color(pl: Dictionary) -> Color:
	var st: int = int(pl["state"])
	if st == ST_WILD:
		return Color(0.24, 0.34, 0.17)          # 荒地：草绿偏暗
	if bool(pl["watered"]):
		return Color(0.24, 0.16, 0.10)          # 浇过水：更暗
	return Color(0.36, 0.24, 0.15)             # 锄过：深褐


func _rebuild_visual(pl: Dictionary) -> void:
	var n: Node3D = pl["node"]
	if n == null or not is_instance_valid(n):
		return
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

	var col: Color = _soil_color(pl)
	n.add_child(_box_mi(Vector3(2.0, 0.18, 2.0), _mat(col), Vector3(0, 0.09, 0)))

	# 四角小土块点缀
	var dk: Color = Color(col.r * 0.82, col.g * 0.82, col.b * 0.82, 1.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var h: float = 0.10 + _hash01(pl) * 0.10
			var rot: float = _hash01(pl) * TAU
			n.add_child(_box_mi(Vector3(0.36, h, 0.36), _mat(dk),
				Vector3(sx * 0.80, h * 0.5 + 0.14, sz * 0.80), Vector3(0, rot, 0)))

	if int(pl["state"]) >= ST_SEED:
		n.add_child(_make_crop(pl))


func _make_crop(pl: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Crop"

	var key: String = String(pl["crop"])
	var ci: int = _crop_index(key)
	if ci < 0:
		ci = 0
	var crop: Dictionary = CROPS[ci]
	var col: Color = crop["color"]
	var days: float = maxf(float(crop["days"]), 0.001)
	var t: float = clampf(float(pl["growth"]) / days, 0.0, 1.0)
	var spin: float = _hash01(pl) * TAU
	var stem_c: Color = Color(0.38, 0.50, 0.24)
	var leaf_c: Color = Color(0.30, 0.55, 0.22)

	if t < SEED_RATIO:
		# 幼苗：三片小绿叶斜插
		var k: float = 0.45 + t * 0.9
		for i in 3:
			var a: float = spin + TAU * float(i) / 3.0
			root.add_child(_box_mi(Vector3(0.06, 0.30 * k, 0.03), _mat(Color(0.42, 0.66, 0.26)),
				Vector3(cos(a) * 0.09, 0.16 * k, sin(a) * 0.09),
				Vector3(cos(a) * 0.40, a, sin(a) * 0.40)))
		return root

	if t < 1.0:
		# 中期：主茎 + 几片叶
		var h: float = 0.30 + (t - SEED_RATIO) / (1.0 - SEED_RATIO) * 0.22
		root.add_child(_cyl_mi(0.045, h, _mat(stem_c), Vector3(0, h * 0.5, 0)))
		for i in 4:
			var a: float = spin + TAU * float(i) / 4.0
			root.add_child(_box_mi(Vector3(0.34, 0.03, 0.10), _mat(leaf_c),
				Vector3(cos(a) * 0.17, h * (0.40 + float(i) * 0.13), sin(a) * 0.17),
				Vector3(0.0, a, -0.42)))
		return root

	# 成熟：主茎 0.9 + 果实
	var hh: float = 0.9
	root.add_child(_cyl_mi(0.05, hh, _mat(stem_c), Vector3(0, hh * 0.5, 0)))
	for i in 4:
		var a: float = spin + TAU * float(i) / 4.0
		root.add_child(_box_mi(Vector3(0.40, 0.03, 0.12), _mat(leaf_c),
			Vector3(cos(a) * 0.20, hh * (0.28 + float(i) * 0.13), sin(a) * 0.20),
			Vector3(0.0, a, -0.40)))

	match key:
		"pumpkin":
			root.add_child(_sphere_mi(0.30, _mat(col), Vector3(0.0, 0.30, 0.05)))
		"tomato":
			for i in 3:
				var a: float = spin + TAU * float(i) / 3.0
				root.add_child(_sphere_mi(0.11, _mat(col),
					Vector3(cos(a) * 0.16, 0.32 + float(i) * 0.15, sin(a) * 0.16)))
		"wheat":
			root.add_child(_cyl_mi(0.055, 0.42, _mat(col), Vector3(0, hh + 0.16, 0)))
			root.add_child(_cyl_mi(0.080, 0.12, _mat(col), Vector3(0, hh + 0.38, 0)))
		"cotton":
			for i in 4:
				var a: float = spin + TAU * float(i) / 4.0
				root.add_child(_sphere_mi(0.10, _mat(col),
					Vector3(cos(a) * 0.15, hh + 0.04 + float(i) * 0.11, sin(a) * 0.15)))
		_:
			root.add_child(_sphere_mi(0.16, _mat(col), Vector3(0, hh * 0.62, 0)))
	return root


# ——————————————— 查询辅助 ———————————————
func _crop_index(key: String) -> int:
	for i in CROPS.size():
		var c: Dictionary = CROPS[i]
		if String(c["key"]) == key:
			return i
	return -1


func _selected_crop() -> Dictionary:
	if CROPS.is_empty():
		return {}
	if selected < 0 or selected >= CROPS.size():
		selected = 0
	var c: Dictionary = CROPS[selected]
	return c


func _days_of(key: String) -> float:
	var i: int = _crop_index(key)
	if i < 0:
		return 1.0
	return maxf(float(CROPS[i]["days"]), 0.001)


func _pct(pl: Dictionary) -> float:
	return clampf(float(pl["growth"]) / _days_of(String(pl["crop"])) * 100.0, 0.0, 100.0)


func _cost_text(cost: Dictionary) -> String:
	var s := ""
	for k in cost:
		s += "%s×%d " % [String(k), int(cost[k])]
	return s.strip_edges()


func _nearest(player_pos: Vector3, reach: float) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = reach
	for pl: Dictionary in plots:
		var p: Vector2 = pl["pos"]
		var d: float = Vector2(p.x - player_pos.x, p.y - player_pos.z).length()
		if d < bd:
			bd = d
			best = pl
	return best


# ——————————————— 公开 API ———————————————
func prompt_text(player_pos: Vector3) -> String:
	if plots.is_empty():
		return ""
	var pl: Dictionary = _nearest(player_pos, REACH)
	if pl.is_empty():
		return ""
	var st: int = int(pl["state"])
	if st == ST_WILD:
		return "[F] 锄地"
	if st == ST_TILLED:
		var c: Dictionary = _selected_crop()
		if c.is_empty():
			return ""
		return "[F] 播种 %s（%s）" % [String(c["name"]), _cost_text(c["cost"])]
	if st == ST_SEED or st == ST_GROW:
		var nm: String = String(pl["crop"])
		var ci: int = _crop_index(nm)
		if ci >= 0:
			nm = String(CROPS[ci]["name"])
		if bool(pl["watered"]):
			return "%s 已浇水 %.0f%%" % [nm, _pct(pl)]
		return "[F] 浇水 · %s %.0f%%" % [nm, _pct(pl)]
	if st == ST_RIPE:
		var rn: String = String(pl["crop"])
		var ri: int = _crop_index(rn)
		if ri >= 0:
			rn = String(CROPS[ri]["name"])
		return "[F] 收获 %s" % rn
	return ""


func interact(player_pos: Vector3) -> void:
	if plots.is_empty():
		return
	var pl: Dictionary = _nearest(player_pos, REACH)
	if pl.is_empty():
		return
	var st: int = int(pl["state"])
	if st == ST_WILD:
		pl["state"] = ST_TILLED
		pl["watered"] = false
		_rebuild_visual(pl)
		_toast("已锄地")
		return
	if st == ST_TILLED:
		_plant(pl)
		return
	if st == ST_SEED or st == ST_GROW:
		pl["watered"] = true
		_rebuild_visual(pl)
		_toast("已浇水")
		return
	if st == ST_RIPE:
		_harvest(pl)


func cycle_crop(dirn: int = 1) -> String:
	var n: int = CROPS.size()
	if n <= 0:
		return ""
	selected = (selected + dirn) % n
	if selected < 0:
		selected += n
	return selected_crop_name()


func selected_crop_name() -> String:
	var c: Dictionary = _selected_crop()
	if c.is_empty():
		return ""
	return String(c["name"])


# ——————————————— 行为 ———————————————
func _plant(pl: Dictionary) -> void:
	var c: Dictionary = _selected_crop()
	if c.is_empty():
		return
	var cost: Dictionary = c["cost"]
	for k in cost:
		if not _world_has(String(k), int(cost[k])):
			_toast("资源不足")
			return
	for k in cost:
		if not _world_take(String(k), int(cost[k])):
			_toast("资源不足")
			return
	pl["state"] = ST_SEED
	pl["crop"] = String(c["key"])
	pl["growth"] = 0.0
	pl["watered"] = false
	_rebuild_visual(pl)
	_toast("已播种 " + String(c["name"]))


func _harvest(pl: Dictionary) -> void:
	var key: String = String(pl["crop"])
	var ci: int = _crop_index(key)
	if ci < 0:
		pl["state"] = ST_TILLED
		pl["crop"] = ""
		pl["growth"] = 0.0
		pl["watered"] = false
		_rebuild_visual(pl)
		return
	var c: Dictionary = CROPS[ci]
	var amount: int = int(c["yield"])
	var out: String = String(c["out"])
	_world_give(out, amount)
	pl["state"] = ST_TILLED
	pl["crop"] = ""
	pl["growth"] = 0.0
	pl["watered"] = false
	_rebuild_visual(pl)
	_toast("+%d %s" % [amount, String(c["name"])])
	var n: Node3D = pl["node"]
	if n != null and is_instance_valid(n):
		if n.is_inside_tree():
			_emit_res(out, amount, n.global_position)
		else:
			var p: Vector2 = pl["pos"]
			_emit_res(out, amount, Vector3(p.x, _ground_y(p.x, p.y), p.y))


# ——————————————— world 资源接口（缺方法时安全降级） ———————————————
func _world_has(kind: String, n: int) -> bool:
	if _world == null or not is_instance_valid(_world):
		return true
	if not _world.has_method("has_item"):
		return true
	return bool(_world.has_item(kind, n))


func _world_take(kind: String, n: int) -> bool:
	if _world == null or not is_instance_valid(_world):
		return true
	if not _world.has_method("take_item"):
		return true
	return bool(_world.take_item(kind, n))


func _world_give(kind: String, n: int) -> void:
	if _world == null or not is_instance_valid(_world):
		return
	if not _world.has_method("give_item"):
		return
	_world.give_item(kind, n)


# ——————————————— 事件总线（运行时查找 + 全空值保护） ———————————————
## autoload 在 --script 模式下未必注册为全局标识符，统一走 /root/<name> 运行时查找
func _tree_root() -> Node:
	if is_inside_tree():
		var t := get_tree()
		if t != null:
			return t.root
	var ml = Engine.get_main_loop()
	if ml is SceneTree:
		var st: SceneTree = ml
		return st.root
	return null


func _bus() -> Node:
	var r: Node = _tree_root()
	if r == null:
		return null
	var n: Node = r.get_node_or_null("GameBus")
	if n == null or not is_instance_valid(n):
		return null
	return n


func _toast(msg: String) -> void:
	var b: Node = _bus()
	if b == null or not b.has_signal("toast"):
		return
	b.emit_signal("toast", msg)


func _emit_res(kind: String, amount: int, pos: Vector3) -> void:
	var b: Node = _bus()
	if b == null or not b.has_signal("res_harvested"):
		return
	b.emit_signal("res_harvested", kind, amount, pos)


func _growth_mult() -> float:
	var b: Node = _bus()
	if b == null:
		return 1.0
	if not ("modules" in b):
		return 1.0
	var mods = b.get("modules")
	if not (mods is Dictionary):
		return 1.0
	var md: Dictionary = mods
	if not md.has("season"):
		return 1.0
	var s = md["season"]
	if s == null or not is_instance_valid(s):
		return 1.0
	if not ("growth_mult" in s):
		return 1.0
	return maxf(float(s.get("growth_mult")), 0.0)


func _on_weather_changed(weather: String) -> void:
	_weather = String(weather)
	if _weather != "rain" and _weather != "storm":
		return
	var changed: int = 0
	for pl: Dictionary in plots:
		var st: int = int(pl["state"])
		if st >= ST_SEED and not bool(pl["watered"]):
			pl["watered"] = true
			changed += 1
			_rebuild_visual(pl)
	if changed > 0:
		_toast("雨水滋润了农田")


func _is_raining() -> bool:
	return _weather == "rain" or _weather == "storm"


# ——————————————— 生长 ———————————————
func _process(dt: float) -> void:
	if _dn == null or not is_instance_valid(_dn):
		return
	if plots.is_empty():
		return

	var ss: float = 1.0
	if "speed_scale" in _dn:
		ss = float(_dn.speed_scale)
	var dl: float = 420.0
	if "day_length" in _dn:
		dl = float(_dn.day_length)
	if dl <= 0.0:
		dl = 420.0

	var day_delta: float = dt * ss / dl
	if day_delta <= 0.0:
		return

	# 跨天：干燥（下雨时保持湿润）
	var dc: int = 1
	if "day_count" in _dn:
		dc = int(_dn.day_count)
	if _last_day < 0:
		_last_day = dc
	elif dc != _last_day:
		_last_day = dc
		if not _is_raining():
			for pl: Dictionary in plots:
				if bool(pl["watered"]):
					pl["watered"] = false
					_rebuild_visual(pl)

	var gm: float = _growth_mult()
	for pl: Dictionary in plots:
		var st: int = int(pl["state"])
		if st < ST_SEED or st > ST_RIPE:
			continue
		var key: String = String(pl["crop"])
		var days: float = _days_of(key)
		var boost: float = WATER_BONUS if bool(pl["watered"]) else 1.0
		pl["growth"] = float(pl["growth"]) + day_delta * gm * boost
		var ratio: float = float(pl["growth"]) / days
		var ns: int = st
		if ratio >= 1.0:
			ns = ST_RIPE
		elif ratio > SEED_RATIO:
			ns = ST_GROW
		else:
			ns = ST_SEED
		if ns != st:
			pl["state"] = ns
			_rebuild_visual(pl)


# ——————————————— 存档 ———————————————
func serialize() -> Dictionary:
	var out: Array = []
	for pl: Dictionary in plots:
		var p: Vector2 = pl["pos"]
		out.append({
			"p": [p.x, p.y],
			"s": int(pl["state"]),
			"c": String(pl["crop"]),
			"g": float(pl["growth"]),
			"w": bool(pl["watered"]),
		})
	return {"selected": int(selected), "plots": out}


func deserialize(d: Dictionary) -> void:
	if d == null:
		return
	_clear_plots()

	if d.has("selected"):
		selected = int(d["selected"])
	if CROPS.is_empty():
		selected = 0
	elif selected < 0 or selected >= CROPS.size():
		selected = 0

	var arr: Array = []
	if d.has("plots"):
		var raw = d["plots"]
		if raw is Array:
			arr = raw

	for e in arr:
		if not (e is Dictionary):
			continue
		var rec: Dictionary = e

		var p: Vector2 = Vector2.ZERO
		if rec.has("p"):
			var pv = rec["p"]
			if pv is Array and pv.size() >= 2:
				p = Vector2(float(pv[0]), float(pv[1]))
			elif pv is Vector2:
				p = pv

		var st: int = int(rec.get("s", 0))
		if st < ST_WILD or st > ST_RIPE:
			st = ST_WILD

		var crop: String = String(rec.get("c", ""))
		if st >= ST_SEED and _crop_index(crop) < 0:
			# 未知作物：退回可播种状态，不崩
			st = ST_TILLED
			crop = ""

		var g: float = float(rec.get("g", 0.0))
		if g < 0.0:
			g = 0.0
		var w: bool = bool(rec.get("w", false))

		var pl: Dictionary = _make_plot(p)
		pl["state"] = st
		pl["crop"] = crop
		pl["growth"] = g
		pl["watered"] = w
		plots.append(pl)
		_rebuild_visual(pl)

	if plots.is_empty():
		_build_plots()

	_last_day = -1
