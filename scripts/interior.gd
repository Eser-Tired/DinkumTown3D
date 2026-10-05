extends Node3D
class_name InteriorSystem
## 可进入建筑的室内空间：懒加载生成 + 传送 + 过场
##
## 【为什么是"同场景隔离区"而不是切场景】
## 户外世界是程序化生成的，已采集资源、玩家建造物、动物血量、昼夜时间、农场状态
## 全都挂在同一个场景树上。真切一次场景就得把这一整包状态搬来搬去，
## 任何一处漏搬都会变成"进屋再出来，树又长回来了"这类玄学 bug。
## 所以室内就是同一个场景里的一块飞地：几何建在远离地图的坐标上，
## 玩家只是被传送过去，世界照常运转，存档逻辑一行都不用改。
##
## 【为什么飞地要抬到 y=40】
## 玩家的水下判定是 cam.global_position.y < water_level(0.0)。相机在玩家后方
## cam_dist 处，抬头（pitch 最大 0.55）时相机会沉到玩家脚下约 cam_dist*0.52 米；
## 滚轮还能把 cam_dist 拉到 22。室内地面若压在 0 附近，抬头俯角一大就会
## 误判成"相机入水"，HUD 立刻糊一层蓝。抬到 40 米后最坏情况相机仍在 28 米，
## 永远够不到水面，这条判定在室内自然失效，不用到处加 if。

# —— 飞地布局 ——
## 飞地起点与间隔。地形网格只有 ±130，玩家活动被 clamp 在 ±112，
## 900 起步意味着"离地图至少 770 米"：再远也看不见，再近就可能从窗口望到小镇。
const SECTOR_ORIGIN := Vector2(900.0, 900.0)
const SECTOR_STRIDE := 600.0
## 室内地面高度（见文件头说明）
const FLOOR_Y := 40.0

## 进门判定半径：玩家到门中心的距离小于它就认为"站在门口"。
## 【下限是被杂货铺卡出来的】门在中心外 3.3 米，而玩家被避让圆顶在 6.02 米外
## （collide_radius 5.6 + 0.42），正对门站着时离门还有 2.72 米；
## 判定半径必须比 2.72 大才按得出提示。取 3.8：侧面绕行时距离约 4.8 米，
## 不会走到屋子侧面就弹出"进入"。
const DOOR_REACH := 3.8
## 玩家必须在门的正面半空间里：屋后绕过来的距离本来就超，但侧面擦过时
## 距离可能刚好卡在阈值内，加一个朝向判断把这种情况排除掉。
const DOOR_FACE_DOT := -0.4

# —— 过场 ——
const FADE_OUT := 0.16
const FADE_IN := 0.28
## 过场层的 canvas layer：暂停菜单 40、触控 20、HUD 10，遮罩必须压在所有 UI 之上，
## 否则"变黑的只有 3D 画面，按钮还亮着"，看着像卡死。
const FADE_LAYER := 60

## 每种可进入建筑的规格。
## door_z：门外沿到房屋中心的水平距离，必须与 props.gd 里模型的门位置对齐
##          （hut 门板在 d*0.5+0.05 = 2.15、台阶在 2.45；shop 门板在 3.05；
##           tent 门帘在 2.45）。给得比模型稍微外扩一点，交互点落在台阶前。
## exit_pad：出门后站位相对门再往外推的距离，必须大于该建筑的避让半径
##           （hut 3.82 / shop 6.02 / tent 3.12），否则一出门就被碰撞圆顶开。
const SPEC := {
	"hut": {
		"title": "铁皮小屋", "shape": "box",
		"w": 7.6, "d": 6.6, "h": 2.9,
		"door_z": 2.6, "exit_pad": 2.2, "door_w": 1.4, "door_h": 2.1,
	},
	"shop": {
		"title": "杂货铺", "shape": "box",
		"w": 11.0, "d": 8.0, "h": 3.4,
		"door_z": 3.3, "exit_pad": 3.4, "door_w": 1.6, "door_h": 2.3,
	},
	"tent": {
		"title": "帐篷", "shape": "round",
		"r": 3.3, "h": 2.4,
		"door_z": 2.7, "exit_pad": 1.8, "door_w": 1.3, "door_h": 1.9,
	},
}

var _spaces: Dictionary = {}     # id -> {node, center, floor_y, spawn, half, colliders, kind, title}
var _slot := 0                   # 已分配飞地数量，用来给新 id 排位置
var _shown: String = ""          # 当前显示的室内 id
var busy := false                # 过场进行中，拒绝重复触发

var _fade_layer: CanvasLayer
var _fade: ColorRect


func _ready() -> void:
	_build_fade()


# ——————————————— 规格查询（main 在建世界时调用） ———————————————
static func is_enterable(kind: String) -> bool:
	return SPEC.has(kind)


static func spec_of(kind: String) -> Dictionary:
	return SPEC.get(kind, {})


## 门的世界坐标（xz 平面 + 地形高度由调用方决定，这里只给水平位置与朝向）。
## 【为什么门的朝向直接用 +Z 旋转后的向量】所有可进入建筑的门都做在模型局部 +Z 侧
## （props.gd 里门板/台阶/门帘的 z 全是正的），_place 时只转了 rotation.y，
## 所以门的方向恒为 (sin(rot), cos(rot))，不需要为每种建筑记一套。
static func door_dir(rot: float) -> Vector2:
	return Vector2(sin(rot), cos(rot))


static func door_point(center2: Vector2, rot: float, kind: String) -> Vector2:
	var sp: Dictionary = spec_of(kind)
	return center2 + door_dir(rot) * float(sp.get("door_z", 2.6))


## 出门后的落脚点：门外再推 exit_pad，保证不会卡进房屋的避让圆里
static func exit_point(center2: Vector2, rot: float, kind: String) -> Vector2:
	var sp: Dictionary = spec_of(kind)
	return center2 + door_dir(rot) * (float(sp.get("door_z", 2.6)) + float(sp.get("exit_pad", 2.0)))


## 玩家是否够得着这扇门
static func at_door(player_pos: Vector3, center2: Vector2, rot: float, kind: String) -> bool:
	var dp := door_point(center2, rot, kind)
	var to := Vector2(player_pos.x - dp.x, player_pos.z - dp.y)
	if to.length() > DOOR_REACH:
		return false
	# 站在门的两侧/背面不该触发：门的法线朝外，玩家在门前方时投影为正
	return to.dot(door_dir(rot)) > DOOR_FACE_DOT * 3.0


# ——————————————— 空间（懒加载） ———————————————
## 取（或首次生成）某个建筑的室内，返回给 main 用于传送的落点信息。
## 生成只发生在第一次进入：小镇有 4 座房子 + 玩家可能造一堆帐篷，
## 开局就全建出来纯属浪费，而且玩家可能一局都不进去。
func ensure(id: String, kind: String, seed_val: int) -> Dictionary:
	if _spaces.has(id):
		return _spaces[id]
	var sp: Dictionary = spec_of(kind)
	if sp.is_empty():
		return {}

	var rng := RandomNumberGenerator.new()
	# 室内摆设跟着"地图种子 + 建筑 id"走：同一个存档进去看到的永远是同一间屋子，
	# 而不是每次进门家具换个位置。
	rng.seed = absi(seed_val * 31 + hash(id)) % 2147483000

	var center := SECTOR_ORIGIN + Vector2(float(_slot % 8) * SECTOR_STRIDE,
		float(_slot / 8) * SECTOR_STRIDE)
	_slot += 1

	var root := Node3D.new()
	root.name = "Interior_%s" % id
	root.position = Vector3(center.x, FLOOR_Y, center.y)

	var half := Vector2(float(sp.get("w", 7.6)) * 0.5 - 0.75, float(sp.get("d", 6.6)) * 0.5 - 0.75)
	var spawn := Vector3(0.0, 0.0, 0.0)
	var cols: Array = []

	# 床（或睡袋）的局部坐标由各个构建函数返回，而不是在别处再抄一份——
	# main 靠它判断"玩家是不是站在床边"，抄一份就迟早会和家具实际位置对不上。
	var bed := Vector3.ZERO
	var can_sleep := false

	if str(sp.get("shape", "box")) == "round":
		var r: float = float(sp.get("r", 3.3))
		half = Vector2(r - 0.7, r - 0.7)
		bed = _build_tent(root, r, float(sp.get("h", 2.4)), rng)
		can_sleep = true
		# 出生点要同时满足两件事：
		#   1) 不能太靠后——相机在玩家身后约 2.8，帐篷半径只有 3.3，
		#      往后多挪半米相机就顶到布墙、视野被自己的后背糊满；
		#   2) 不能贴着睡袋——睡袋在 (-r*0.45, -0.6) 一带，进门就落在它的
		#      睡觉判定圈里的话，第一下按 F 是"睡觉"而不是"出门"，人会被困在帐篷里。
		# (0.35, 0.3) 到睡袋约 2.04 米，离后墙还有 0.2 米余量，两边都够。
		spawn = Vector3(0.35, 0.0, 0.3)
		cols.append({"pos": center + Vector2(0.0, -r * 0.35), "r": 0.9})
	else:
		var w: float = float(sp.get("w", 7.6))
		var d: float = float(sp.get("d", 6.6))
		var h: float = float(sp.get("h", 2.9))
		var hole := {"at": 0.0, "w": float(sp.get("door_w", 1.4)), "y0": 0.0, "y1": float(sp.get("door_h", 2.1))}
		match kind:
			"shop":
				# 铺子里没有床，睡不了
				_build_shop(root, w, d, h, hole, rng, center, cols)
			_:
				bed = _build_hut(root, w, d, h, hole, rng, center, cols)
				can_sleep = true
		# 必须把出生点推到屋子深处，让身后的相机离门墙 > cam_dist，
		# 否则第三人称直接穿到 +Z 墙外——屏幕里只剩一坨门板和远处的草坪。
		# 相机在玩家身后（+Z 侧）约 2.8，hut d/2=3.3、shop d/2=4，spawn.z=-1.2 都够安全。
		spawn = Vector3(0.0, 0.0, -1.2)

	add_child(root)
	# 家具避让圆在构建时就已换算成世界 xz（玩家只认世界坐标），
	# 这里不再叠加飞地偏移——否则避让圆会整体飘到屋子外面去。

	var space := {
		"id": id,
		"kind": kind,
		"title": str(sp.get("title", "屋子")),
		"node": root,
		"center": center,
		"floor_y": FLOOR_Y,
		"half": half,
		"spawn": root.position + spawn,
		# 进门后朝向屋子深处：yaw=0 时相机看向 -Z，而门在 +Z 墙，正好背对门。
		"spawn_yaw": 0.0,
		"colliders": cols,
		# 床的世界坐标 + 这间屋子能不能睡。main 用它做"靠近床边按 F"的判定。
		"bed": root.position + bed,
		"can_sleep": can_sleep,
	}
	_spaces[id] = space
	return space


func space_of(id: String) -> Dictionary:
	return _spaces.get(id, {})


## 只显示当前所在的那间。
## 【为什么其它飞地要藏起来】每间屋子都带 2~3 盏 OmniLight，飞地之间隔 600 米
## 但它们仍在同一个渲染场景里，灯光与网格照样进剔除和光照计算。
## 藏掉不可见的那些，等于把"玩家造了 20 个帐篷"的代价压回常数级。
func show_only(id: String) -> void:
	_shown = id
	for k in _spaces.keys():
		var s: Dictionary = _spaces[k]
		var n: Node3D = s.get("node", null)
		if n != null and is_instance_valid(n):
			n.visible = (k == id)


func hide_all() -> void:
	_shown = ""
	for k in _spaces.keys():
		var n: Node3D = _spaces[k].get("node", null)
		if n != null and is_instance_valid(n):
			n.visible = false


# ——————————————— 过场 ———————————————
## 淡出 → 执行 mid（传送 / 建屋子）→ 淡入。
## 不做真正的"读条"：屋子是几毫秒就能拼出来的原始几何，
## 但瞬移没有过渡会让玩家搞不清自己是怎么到的屋里，所以留一个短黑场当标点。
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
	return _mi(b, m, pos)


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
		rng: RandomNumberGenerator, center: Vector2, cols: Array) -> Vector3:
	var floor_m := _mat(Color(0.52, 0.36, 0.24))
	var wall_m := _mat(Color(0.88, 0.84, 0.74))
	var wood := _mat(Color(0.46, 0.31, 0.20))
	var wood_l := _mat(Color(0.68, 0.50, 0.33))
	var iron := _mat(Color(0.36, 0.36, 0.38), 0.7)

	root.add_child(_box(Vector3(w, 0.24, d), floor_m, Vector3(0, -0.12, 0)))
	root.add_child(_box(Vector3(w, 0.24, d), _mat(Color(0.74, 0.70, 0.62)), Vector3(0, h + 0.12, 0)))

	# 门在 +Z 墙（与室外模型一致：玩家从 +Z 方向进来）
	var door_w: float = float(hole.get("w", 1.4))
	var door_h: float = float(hole.get("y1", 2.1))
	var wp := _wall(w, h, 0.28, true, hole, wall_m)
	wp.position.z = d * 0.5
	root.add_child(wp)
	# 门框 + 门板。门板是关着的：门洞外是飞地之外的虚空（只有雾），
	# 留一个通透的洞会让玩家看见"门外什么都没有"，很出戏。
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
	root.add_child(bed)
	cols.append({"pos": center + Vector2(-w * 0.5 + 1.5, -d * 0.5 + 1.7), "r": 1.2})

	# 木桌 + 两把椅子
	var tx := w * 0.5 - 2.1
	var tz := -d * 0.5 + 1.9
	root.add_child(_box(Vector3(1.7, 0.12, 0.95), wood_l, Vector3(tx, 0.76, tz)))
	for sx in [-0.72, 0.72]:
		for sz in [-0.36, 0.36]:
			root.add_child(_box(Vector3(0.11, 0.76, 0.11), wood, Vector3(tx + sx, 0.38, tz + sz)))
	cols.append({"pos": center + Vector2(tx, tz), "r": 1.0})
	for s in [-1.0, 1.0]:
		var ch := Node3D.new()
		ch.position = Vector3(tx + s * 1.35, 0.0, tz + 0.15)
		ch.add_child(_box(Vector3(0.5, 0.10, 0.5), wood_l, Vector3(0, 0.46, 0)))
		ch.add_child(_box(Vector3(0.5, 0.55, 0.09), wood, Vector3(0, 0.74, -0.21)))
		for ax in [-0.2, 0.2]:
			for az in [-0.2, 0.2]:
				ch.add_child(_box(Vector3(0.08, 0.46, 0.08), wood, Vector3(ax, 0.23, az)))
		root.add_child(ch)

	# 铁皮炉灶 + 烟囱：屋里的视觉中心，也是主光源
	var sx := w * 0.5 - 1.6
	var sz := d * 0.5 - 2.4
	var stove := Node3D.new()
	stove.position = Vector3(sx, 0.0, sz)
	stove.add_child(_cyl(0.44, 1.15, iron, Vector3(0, 0.58, 0), 10))
	stove.add_child(_box(Vector3(0.34, 0.30, 0.10), glow_mat(Color(1.0, 0.55, 0.18)), Vector3(0, 0.42, 0.45)))
	stove.add_child(_cyl(0.15, h - 1.15, iron, Vector3(0, 1.15 + (h - 1.15) * 0.5, 0), 8))
	root.add_child(stove)
	root.add_child(_lamp(Vector3(sx, 1.1, sz), 2.2, 7.5))
	cols.append({"pos": center + Vector2(sx, sz), "r": 0.62})

	# 木箱：靠门这侧，进门第一眼能看到
	for i in 2:
		var bx := -w * 0.5 + 1.2 + float(i) * 1.0
		var bz := d * 0.5 - 1.3
		root.add_child(_box(Vector3(0.82, 0.72, 0.82), wood_l, Vector3(bx, 0.36, bz)))
		root.add_child(_box(Vector3(0.86, 0.08, 0.86), wood, Vector3(bx, 0.76, bz)))
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
		rng: RandomNumberGenerator, center: Vector2, cols: Array) -> void:
	var floor_m := _mat(Color(0.58, 0.44, 0.30))
	var wall_m := _mat(Color(0.90, 0.86, 0.76))
	var wood := _mat(Color(0.44, 0.30, 0.19))
	var wood_l := _mat(Color(0.70, 0.53, 0.35))

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
		root.add_child(sh)
		cols.append({"pos": center + Vector2(sx, -0.6), "r": 0.95})

	# —— 桶与麻袋 ——
	for i in 3:
		var bx := w * 0.5 - 1.3
		var bz := d * 0.5 - 1.6 - float(i) * 1.15
		root.add_child(_cyl(0.42, 0.9, wood, Vector3(bx, 0.45, bz), 10))
		root.add_child(_cyl(0.44, 0.10, _mat(Color(0.34, 0.34, 0.36), 0.6), Vector3(bx, 0.92, bz), 10))
	for i in 2:
		var pz := d * 0.5 - 1.4 - float(i) * 1.0
		root.add_child(_box(Vector3(0.9, 0.8, 0.7), _mat(Color(0.76, 0.68, 0.48)),
			Vector3(-w * 0.5 + 1.1, 0.4, pz)))

	# —— 灯：铺子要比屋子亮 ——
	root.add_child(_lamp(Vector3(0.0, h - 0.6, 0.0), 2.0, 12.0))
	root.add_child(_lamp(Vector3(-3.2, h - 0.8, -1.5), 1.4, 9.0))
	root.add_child(_lamp(Vector3(3.2, h - 0.8, 1.5), 1.4, 9.0))


# ——————————————— 帐篷室内 ———————————————
## 返回睡袋的局部坐标（帐篷里睡觉的交互点）
static func _build_tent(root: Node3D, r: float, h: float, rng: RandomNumberGenerator) -> Vector3:
	var canvas := _mat(Color(0.86, 0.80, 0.65))
	var wood := _mat(Color(0.46, 0.31, 0.20))

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
	root.add_child(_box(Vector3(0.78, 0.62, 0.78), wood, Vector3(r * 0.5, 0.31, -0.9)))
	root.add_child(_cyl(0.13, 0.34, _mat(Color(0.34, 0.34, 0.36), 0.6), Vector3(r * 0.5, 0.72, -0.9), 8))
	root.add_child(_box(Vector3(0.18, 0.20, 0.18), glow_mat(Color(1.0, 0.84, 0.52)), Vector3(r * 0.5, 0.94, -0.9)))
	root.add_child(_lamp(Vector3(r * 0.5, 1.05, -0.9), 1.6, 6.0))
	root.add_child(_lamp(Vector3(0.0, h * 0.72, 0.4), 1.0, 5.5))

	return Vector3(-r * 0.45, 0.0, -0.6)
