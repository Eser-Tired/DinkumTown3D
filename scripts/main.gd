extends Node3D
## Dinkum 风格 3D 澳洲内陆小镇 —— 世界组装、采集与建造

const PropsS := preload("res://scripts/props.gd")
const FloraS := preload("res://scripts/flora.gd")
const TerrainS := preload("res://scripts/terrain.gd")
const PlayerS := preload("res://scripts/player.gd")
const KangarooS := preload("res://scripts/kangaroo.gd")
const EmuS := preload("res://scripts/emu.gd")
const WildlifeS := preload("res://scripts/wildlife.gd")
const DayNightS := preload("res://scripts/day_night.gd")
const HUDS := preload("res://scripts/hud.gd")
const AudioS := preload("res://scripts/audio.gd")
const SeasonS := preload("res://scripts/season.gd")
const FarmS := preload("res://scripts/farm.gd")
const SaveS := preload("res://scripts/save_system.gd")
const TouchS := preload("res://scripts/touch_controls.gd")
const WeaponsS := preload("res://scripts/weapons.gd")
const InvUIS := preload("res://scripts/inventory_ui.gd")
const PauseS := preload("res://scripts/pause_menu.gd")
const InteriorS := preload("res://scripts/interior.gd")
const SleepS := preload("res://scripts/sleep_panel.gd")
const CollisionS := preload("res://scripts/world_collision.gd")
const PhysicsPropS := preload("res://scripts/physics_prop.gd")

const TOWN := Vector2(-14.0, -10.0)
const LAKE := Vector2(48.0, 22.0)
const FARM_ORIGIN := Vector2(-10.0, 14.0)   # TOWN + (4, 24)，与菜地同侧

const BUILD_ITEMS := [
	{"name": "篝火", "cost": {"wood": 3}, "make": "campfire"},
	{"name": "帐篷", "cost": {"wood": 6, "fiber": 3}, "make": "tent"},
	{"name": "木栅栏", "cost": {"wood": 2}, "make": "fence"},
	{"name": "路灯", "cost": {"wood": 2, "stone": 1}, "make": "lamp"},
]

## 快捷物品栏槽位类型
const SLOT_EMPTY := "empty"      # 空格子
const SLOT_WEAPON := "weapon"    # 指向 WeaponsS 里的一件武器
const SLOT_BUILD := "build"      # 绑定建造菜单里的一项，选中即切换该建造物

## —— 触控参数 ——
## 轻点采集的角度上限：目标必须落在相机前方这个扇形内（弧度，半角）。
## 1.5 rad ≈ 86°，基本覆盖屏幕中部到偏下的可视区域，宽容但不至于误抓身后的东西。
const TAP_ARC := 1.5
## 轻点攻击的附加射程：比武器 reach 再放宽一点，否则手机上很难点中
const TAP_ATTACK_PAD := 0.9

## 建造预览沿视线推进的距离（触控拖动移动建造物时用）
const BUILD_DIST_MIN := 2.0
const BUILD_DIST_MAX := 12.0
const BUILD_DIST_DEFAULT := 4.5

var terrain: Node3D
var player: CharacterBody3D
var dn: DayNight
var hud: GameHUD
var rng := RandomNumberGenerator.new()

## 这一局的地图种子：地形起伏 / 河道走向 / 植被分布全由它派生。
## 新游戏时随机掷，读档时从存档 __meta 里取回——所以同一个存档永远回到同一张地图。
var map_seed := 20260921

## 非 0 时强制使用该种子，忽略"新游戏随机掷"。
## 【为什么需要它】地图一随机，自检脚本里那些固定期望值（资源数量、坐标、
## 存档往返比对）就全成了碰运气。测试要的是可复现，所以留一个外部指定种子的口子。
## 必须在 add_child 之前设置。
var forced_map_seed := 0

var colliders: Array = []      # {node, pos:Vector2, r:float}
var resources: Array = []      # 可采集节点
var spins: Array = []
var bobs: Array = []
var flickers: Array = []
var placed_pts: Array = []     # 已占用点（避免重叠）

var audio: AudioDirector
var season: SeasonManager
var farm: FarmSystem
var save_sys: SaveSystem

var inv := {"wood": 0, "stone": 0, "fiber": 0, "ore": 0, "food": 0}
var inv_ui: InventoryUI
var pause_menu: PauseMenu
## 可进入建筑登记表。每项 {id, kind, title, pos:Vector2, rot}
## id 必须稳定（同一座房子每次开局都算出来同一个），否则室内家具的随机摆设会变。
var houses: Array = []
## 当前所在的建筑 id，"" 表示在户外
var house_id := ""
## 出门后的落点。进门时就定好，存档也写它——室内坐标是飞地里的位置，
## 写进存档再读出来会落在一片虚空里。
var outdoor_exit := Vector3.ZERO
## 【为什么写成 Node3D 而不是 InteriorSystem】新脚本的 class_name 要等 Godot 重新
## 扫一遍工程才进全局类缓存，在那之前用 class_name 做类型注解会让 main.gd 直接
## 解析失败（"Could not find type"），整个游戏起不来。调用走动态派发，不受影响。
var interior: Node3D
## 睡觉面板（layer 35）。同样避开 class_name 注解。
var sleep_panel: CanvasLayer

var build_mode := false
var build_index := 0
var preview: Node3D = null
var preview_rot := 0.0
var hud_timer := 0.0
var preview_dist := BUILD_DIST_DEFAULT   # 预览离玩家的距离，触屏拖动时改

## —— 快捷物品栏 ——
## 内容由 _rebuild_hotbar() 生成，随后通过 GameBus.sync_hotbar() 下发给
## TouchControls 渲染。真正生效的持有物由 _equip() 落到 player/build_index 上，
## 槽位数组只是"显示层"，不做真值。
var hotbar: Array = []
var hotbar_sel := 0

# —— 存档相关 ——
var next_res_id := 0
var harvested_ids: Array = []    # 已被采集的资源稳定 id
var built_items: Array = []      # {kind, x, z, rot}
var step_dist := 0.0
var last_pos := Vector3.ZERO
var rain_particles: GPUParticles3D = null

## 可狩猎动物列表（重新生成时会整体清空重填）
var critters: Array = []
var physics_props: Array = []
const MAX_PHYSICS_PROPS := 24


func _ready() -> void:
	_resolve_map_seed()

	terrain = TerrainS.new()
	terrain.name = "Terrain"
	# 种子必须赶在 add_child 之前给：_ready() 里就会用它生成噪声与河道，
	# 挂进树之后再改，地面网格早就按旧种子烘好了。
	terrain.set_map_seed(map_seed)
	add_child(terrain)

	_build_town()
	_scatter_flora()
	preload("res://scripts/vegetation_scatter.gd").build(self, terrain, map_seed)

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
	hud.layout_changed.connect(func(bottom: float):
		var controls := get_node_or_null("TouchControls")
		if controls != null:
			controls.set_hud_column_bottom(bottom))
	hud.set_resources(inv)
	GameBus.toast.connect(Callable(hud, "toast"))

	# —— 背包界面（默认隐藏，layer 30 盖住 HUD 与触控层）——
	inv_ui = InvUIS.new()
	add_child(inv_ui)
	inv_ui.setup(_bag_inv, _bag_stat, _bag_equip)
	inv_ui.closed.connect(_on_bag_closed)

	# —— 音效（自己挂到 world 上）——
	audio = AudioS.new()
	audio.setup(self, player)
	audio.register_ambient_source("water", Vector3(LAKE.x, 0.4, LAKE.y))

	# —— 季节 / 天气 ——
	season = SeasonS.new()
	season.name = "Season"
	add_child(season)
	season.setup(dn, terrain)

	# —— 农场 ——
	farm = FarmS.new()
	farm.name = "Farm"
	add_child(farm)
	farm.setup(self, terrain, dn)

	# —— 室内空间（飞地，见 interior.gd）——
	# 放在 player 之后：进门时要读写 player 的状态。
	interior = InteriorS.new()
	interior.name = "Interiors"
	add_child(interior)

	# —— 睡觉面板（默认隐藏，layer 35：盖住背包、被暂停菜单盖住）——
	sleep_panel = SleepS.new()
	add_child(sleep_panel)
	sleep_panel.picked.connect(_on_sleep_picked)

	# —— 存档 ——
	save_sys = SaveS.new()
	save_sys.name = "SaveSystem"
	add_child(save_sys)
	save_sys.setup(self)
	GameBus.new_day.connect(_on_auto_save)

	# —— 暂停菜单（默认隐藏，layer 40 盖住上面所有层）——
	# 放在存档系统之后：菜单里的存档列表复用同一个 SaveSystem 实例，
	# 再 new 一个会和正在用的那份状态对不上。
	pause_menu = PauseS.new()
	pause_menu.set_save_system(save_sys)   # 先注入再挂载，面板就不会自己再造一个存档系统
	add_child(pause_menu)
	pause_menu.closed.connect(_on_pause_closed)
	pause_menu.quit_requested.connect(_on_pause_quit)
	pause_menu.load_requested.connect(_on_pause_load)

	GameBus.register_module("main", self)

	_setup_rain()
	GameBus.weather_changed.connect(_on_weather)
	if season != null:
		_on_weather(season.weather)

	# 物品栏在触控层挂载前先建好，桌面端也有一份（键盘 1-4 用）
	_rebuild_hotbar()

	_setup_touch()
	_consume_pending_load()
	_check_auto_shot()


## 决定这一局用哪张地图。
## 【为什么要在建世界之前单独跑一趟】地形是程序化生成的，只有种子是"来自过去"的信息；
## 而 main 模块的存档数据要等 save_sys.load() 里反序列化，那时地形早就烘好了。
## 所以种子走 __meta 这条能提前读的通道。
func _resolve_map_seed() -> void:
	var slot: int = GameBus.pending_load_slot if GameBus != null else -1
	if forced_map_seed != 0:
		# 自检脚本指定了种子：一律照办，保证每次跑出来是同一张图
		map_seed = forced_map_seed
	elif slot >= 0:
		var s: int = SaveS.peek_terrain_seed(slot)
		if s >= 0:
			map_seed = s
		else:
			# 旧存档没记种子：退回一个固定值，至少保证"同一个旧档每次都开出同一张图"，
			# 而不是每次读档都换一片大陆。
			map_seed = 20260921
	else:
		map_seed = _roll_map_seed()
	if GameBus != null:
		GameBus.terrain_seed = map_seed
	# 世界内容（植被、石头、动物的随机分布）跟着同一个种子走，
	# 否则读档后树会长到别的地方去。
	rng.seed = map_seed


## 掷一个地图种子。上限压在 int32 以内：这个数字要进存档 JSON，
## 太大可能被写成科学计数法，读回来就对不上了。
func _roll_map_seed() -> int:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r.randi_range(1, 2147483000)


## 消费主界面写下的握手值：决定这一局是新游戏还是读档
func _consume_pending_load() -> void:
	if GameBus == null:
		return
	var slot: int = GameBus.pending_load_slot
	GameBus.pending_load_slot = -1
	if slot < 0:
		return                      # -1/-2：新游戏，什么都不做
	if save_sys != null:
		save_sys.load(slot)


## 返回主界面（暂停菜单 / 触控系统按钮都走这里）
func return_to_menu() -> void:
	# 兜底：任何路径退出都要解除暂停。带着 paused 切场景会让主界面整个卡死，
	# 而这种 bug 只在"从暂停菜单退出"这条路上出现，很难靠手测发现。
	if get_tree() != null:
		get_tree().paused = false
	if GameBus != null:
		GameBus.ui_blocking = false
	if save_sys != null:
		save_sys.save(0)            # 离开前留一份自动存档，避免进度丢失
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ——————————————— 移动端触控适配 ———————————————
func _setup_touch() -> void:
	var forced := OS.get_cmdline_args().has("--touch-ui")
	# 只在真正的移动平台自动挂载：Windows 触摸屏笔记本会被 is_touchscreen_available 误判
	if not OS.has_feature("mobile") and not forced:
		return
	# 必须先连接再挂载：TouchControls._ready 会立刻发出首次布局事件，
	# connect 晚了这一帧就丢了，HUD 将永远停在桌面布局上。
	GameBus.touch_action.connect(_on_touch_action)
	GameBus.touch_layout_changed.connect(_on_touch_layout)
	GameBus.touch_tap.connect(_on_touch_tap)
	GameBus.touch_build_drag.connect(_on_touch_drag_build)
	add_child(TouchS.new())
	if forced:
		# 桌面调试：把鼠标当一根手指用
		ProjectSettings.set_setting("input_devices/pointing/emulate_touch_from_mouse", true)
	# 物品栏必须在 TouchControls 挂载之后再下发，否则它还没连上信号
	_rebuild_hotbar()


## 视口变化时 HUD 同步避让（首次挂载时 TouchControls 也会 emit 一次）
func _on_touch_layout(w: float, h: float, k: float) -> void:
	if hud == null:
		return
	# 【为什么要单独算文字缩放】k = min(W/1440, H/810)，竖屏手机算出来只有 0.75，
	# 再被触控层的 0.60 下限压住，HUD 文字就只剩 12px——分辨率完全够，字却看不清。
	# 触控层的下限是为「按钮不能太小」设的，不该直接传导到字号上。
	# 字号按短边独立放大，高分辨率也不再被原来的 1.0 上限卡住。
	var k_text: float = preload("res://scripts/ui_layout.gd").text_scale(Vector2(w, h))
	# 【为什么要先算 HUD 再算按钮】右侧竖列多高取决于字号和实测文字宽度，
	# 把它复制到触控层里重算一定会漂。改成 HUD 算完把真实底边报回来，
	# 触控层从那条线下面开始排——单向数据流，以后改 HUD 不用记得改触控层。
	var bottom: float = hud.set_touch_mode(w, h, k, k_text)
	var tc := get_node_or_null("TouchControls")
	if tc != null and tc.has_method("set_hud_column_bottom"):
		tc.set_hud_column_bottom(bottom)
	elif tc != null and tc.has_method("set_text_scale"):
		tc.set_text_scale(k_text)


func _on_touch_action(a: String) -> void:
	# 「使用」在门口 / 屋里就是 F 键那个交互：手机上没有 F，
	# 与其再加一个按钮挤占本来就紧张的右下角，不如让主键跟着上下文变。
	# 优先级高于建造落位——站在门口按「使用」去放建筑不是玩家想要的。
	if a == "use" and (house_id != "" or not _door_target().is_empty()):
		_do_action("interact")
		return
	# 建造模式下「使用」键的语义变成"落位"，与桌面端左键一致
	if a == "use" and build_mode:
		_do_action("place")
		return
	_do_action(a)


## 屏幕轻点：就近判定采集 / 攻击
## 关于视角：触屏没有右键转视角，相机就是"准星"。角色的身体朝向在移动中会
## 滞后于相机（转身有插值），所以这里一律用 aim_dir()（相机朝向）做扇形判定，
## 玩家「看着哪就采哪」才符合直觉。
func _on_touch_tap(pos: Vector2) -> void:
	if player == null:
		return
	if build_mode:
		# 建造模式下轻点是"把预览挪到这"，不是采集
		var g := _pick_ground(pos)
		if g != Vector3.ZERO:
			_set_preview_pos(g)
		return

	if not _can_act():
		return

	# 优先打动物：动物会跑，机会成本比资源高
	var beast := _find_critter_in_arc(player.global_position, player.aim_dir(), true)
	if beast != null:
		_attack_at(beast)
		return

	# 其次采集资源
	var n := _find_resource_in_arc(player.global_position, player.aim_dir())
	if n != null:
		_collect_resource(n)
		return

	hud.toast("这里没有可采集的东西")


## 菜单 / 提示里的键位说明：触控模式换成不带键位的说法
func _hint(kbd: String, touch: String) -> String:
	return touch if GameBus.touch_enabled else kbd


## 触控模式没有鼠标射线，建造预览改落在玩家正前方的地面上。
## dist 为沿视线推进的距离，触摸拖动会改它。
func _preview_in_front(dist := -1.0) -> Vector3:
	if player == null or terrain == null:
		return Vector3.ZERO
	var d: float = preview_dist if dist < 0.0 else dist
	var dir: Vector3 = player.aim_dir()
	var p: Vector3 = player.global_position + dir * d
	p.y = terrain.height_at(p.x, p.z)
	return p


## 找一个"站得住"的预览距离：从近到远扫一遍，返回第一个 _place_ok 通过的。
## 为什么要这个：触控下预览距离是固定初值，玩家一进建造模式可能正对着房子，
## 预览直接卡在墙里，提示"此处放不下"，但玩家不知道要往前还是往后拖。
## 自动找一个合法起点，剩下的微调交给拖动。
func _find_good_preview_dist() -> float:
	var d := BUILD_DIST_MIN
	while d <= BUILD_DIST_MAX:
		var p := _preview_in_front(d)
		if _place_ok(p, 1.0):
			return d
		d += 0.5
	return BUILD_DIST_DEFAULT


## 统一入口：把预览摆到某个世界坐标，并更新可放置高亮
func _set_preview_pos(g: Vector3) -> void:
	if preview == null or not is_instance_valid(preview):
		return
	preview.global_position = g
	preview.rotation.y = preview_rot


## 触屏拖动建造物：手指上下拖动改变预览离玩家的距离。
## 为什么用"距离"而不是直接投射到手指下的地面：手指会挡住目标点，
## 而且手机上射线投影到远处地面噪声极大；改距离的手感稳定得多。
func _on_touch_drag_build(rel: Vector2) -> void:
	if not build_mode or preview == null:
		return
	preview_dist = clampf(preview_dist - rel.y * 0.02, BUILD_DIST_MIN, BUILD_DIST_MAX)
	_set_preview_pos(_preview_in_front())


## 雨幕：跟随玩家的粒子柱，weather_changed 驱动
func _setup_rain() -> void:
	rain_particles = GPUParticles3D.new()
	rain_particles.emitting = false
	rain_particles.amount = 900
	rain_particles.lifetime = 1.1
	rain_particles.visibility_aabb = AABB(Vector3(-15, -9, -15), Vector3(30, 20, 30))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13.0, 0.5, 13.0)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 2.0
	pm.initial_velocity_min = 17.0
	pm.initial_velocity_max = 21.0
	pm.gravity = Vector3(0.0, -22.0, 0.0)
	rain_particles.process_material = pm

	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.5, 0.02)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.65, 0.75, 0.90, 0.42)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = m
	rain_particles.draw_pass_1 = bm

	rain_particles.position = Vector3(0.0, 11.0, 0.0)
	player.add_child(rain_particles)


func _on_weather(w: String) -> void:
	if terrain != null:
		terrain.set_weather(w)
	if rain_particles != null:
		# 屋里不下雨：雨幕是挂在玩家身上的粒子柱，跟着人一起进屋就成了室内暴雨
		rain_particles.emitting = (w == "rain" or w == "storm") and house_id == ""


# ——————————————— 放置工具 ———————————————
func _place(node: Node3D, x: float, z: float, rot_y := 0.0, scl := 1.0) -> void:
	node.position = Vector3(x, terrain.height_at(x, z), z)
	node.rotation.y = rot_y
	node.scale = Vector3(scl, scl, scl)
	CollisionS.attach(node)
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
	if float(node.get_meta("collide_radius", 0.0)) > 0.0:
		CollisionS.attach(node, true)
	add_child(node)
	var r: float = node.get_meta("collide_radius", 0.0)
	if r > 0.0:
		colliders.append({"node": node, "pos": Vector2(x, z), "r": r * scl})
		placed_pts.append(Vector2(x, z))
	if node.has_meta("resource"):
		node.set_meta("rid", next_res_id)
		next_res_id += 1
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
func _adapt_house_entry(model: Node3D) -> void:
	if not model.has_meta("entrance_origin"):
		return
	# 房屋和商店都按网格实测的侧门/台阶更新，不能只迁移第一栋入口。
	var offset: Vector2 = model.get_meta("entrance_origin")
	var origin: Vector3 = model.transform * Vector3(offset.x, 0, offset.y)
	houses[-1]["entrance_origin"] = Vector2(origin.x, origin.z)
	var exit_world := model.transform * Vector3(float(model.get_meta("stair_x")), 0, float(model.get_meta("exit_distance")))
	houses[-1]["exit_point"] = Vector2(exit_world.x, exit_world.z)
	if houses[-1]["kind"] == "hut":
		houses[-1]["title"] = "木顶小屋"


func _build_town() -> void:
	var c := TOWN

	# 中心广场篝火
	_place(PropsS.make_campfire(), c.x, c.y)

	# 杂货铺
	var shop_p := c + Vector2(14, -9)
	var shop_rot := _face_to(shop_p, c)
	var shop := PropsS.make_shop()
	_place(shop, shop_p.x, shop_p.y, shop_rot)
	_register_house("shop", shop_p, shop_rot, 0)
	_adapt_house_entry(shop)

	# 所有小屋共用资源工厂；缺包时自动恢复程序化外观。
	var huts := [
		[Vector2(-12, -13), PropsS.C_IRON_RED],
		[Vector2(-4, 11), PropsS.C_IRON_GREEN],
		[Vector2(17, 7), PropsS.C_IRON_BLUE],
	]
	for i in huts.size():
		var it: Array = huts[i]
		var p: Vector2 = c + it[0]
		# 【门必须朝广场】make_shop / make_hut 的门都做在模型局部 +Z 侧，
		# _face_to(p, c) 正好把 +Z 转向镇中心。原来小屋多转了 PI，三间屋子集体
		# 背对广场，玩家从中心走过去只看到没门的后墙——能进屋之后这就很致命。
		var rot := _face_to(p, c)
		var hut := PropsS.make_hut(it[1])
		if i == 0:
			hut.name = "SampleHut"
		_place(hut, p.x, p.y, rot)
		_register_house("hut", p, rot, i)
		_adapt_house_entry(hut)

	# 帐篷营地：三顶都能进
	# 【为什么不再用随机朝向】帐篷的门帘做在模型局部 +Z 侧，随机转一圈意味着
	# 玩家得绕着帐篷找门。改成统一朝向镇中心，从镇上走过去就是门。
	var tents := [Vector2(-21, 3), Vector2(-26, -3), Vector2(-19, 11)]
	for i in tents.size():
		var p: Vector2 = c + tents[i]
		var rot := _face_to(p, c)
		_place(PropsS.make_tent(), p.x, p.y, rot)
		_register_house("tent", p, rot, i, "_camp")
	_place(PropsS.make_campfire(), c.x - 22, c.y + 6)

	# 水塔与风车
	_place(PropsS.make_watertower(), c.x - 10, c.y - 22)
	_place(PropsS.make_windmill(), c.x + 28, c.y - 24)

	# 菜地区域已交给农场系统（FarmSystem 在 FARM_ORIGIN 自建田块）

	# 杂项
	_place(PropsS.make_clothesline(), c.x - 8, c.y + 12, 0.4)
	_spawn_prop("crate", Vector3(c.x + 9, terrain.height_at(c.x + 9, c.y + 3) + 0.5, c.y + 3), "emace_crate")
	_spawn_prop("crate", Vector3(c.x + 10.1, terrain.height_at(c.x + 10.1, c.y + 3.4) + 0.5, c.y + 3.4))
	_spawn_prop("barrel", Vector3(c.x + 11.3, terrain.height_at(c.x + 11.3, c.y + 2.5) + 0.6, c.y + 2.5))
	_place(PropsS.make_signpost(), c.x + 3, c.y + 13, _face_to(c + Vector2(3, 13), c))

	for off in [Vector2(7, -2), Vector2(-9, 5), Vector2(1, 11), Vector2(-17, -6), Vector2(15, 13)]:
		var p: Vector2 = c + off
		_place(PropsS.make_lamp(), p.x, p.y, rng.randf() * TAU)

	# 码头：从岸边伸入水潭
	# 【为什么用 water_depth_at 而不是 height_at】地形整体抬升过（见 terrain.BASE_LIFT），
	# 拿绝对高度跟 0.9 比已经不是在判断"有没有水"了。所有"是不是水"的判断
	# 都必须走 water_depth_at，否则地形一变就集体失效。
	var dock_z := LAKE.y + 44.0
	for d in range(28, 62):
		var cand := LAKE + Vector2(0.0, float(d))
		if terrain.water_depth_at(cand.x, cand.y) <= 0.0:
			dock_z = LAKE.y + float(d)
			break
	var dock := PropsS.make_dock(10)
	dock.name = "Dock"
	dock.position = Vector3(LAKE.x, terrain.water_level(), dock_z)
	# 坡道在干岸与码头甲板之间衔接，不让第一块板悬在玩家腰间。
	var shore_z := dock_z + 4.0
	var shore_y: float = terrain.height_at(LAKE.x, shore_z) + 0.04
	var start := Vector3(0, 0.94, 0.45)
	var end := Vector3(0, shore_y - terrain.water_level(), 4.0)
	var span := end - start
	dock.add_child(PropsS._box(Vector3(4.2, 0.14, span.length()),
		PropsS.surface("wood", PropsS.C_WOOD), (start + end) * 0.5,
		Vector3(-atan2(span.y, span.z), 0, 0)))
	CollisionS.attach(dock)
	add_child(dock)
	_collect_anims(dock)
	_spawn_prop("log", Vector3(LAKE.x - 6.0, terrain.water_level() + 0.6, LAKE.y + 8.0))
	_spawn_prop("log", Vector3(LAKE.x + 5.0, terrain.water_level() + 0.8, LAKE.y + 4.0))

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
			# 岸边（水线以上、但还没爬上高坡）——用离水面的高差判定，
			# 不用绝对高度：地形基准高度改过一次，绝对阈值就全靠不住了
			var above: float = terrain.height_at(p.x, p.y) - terrain.water_level()
			if above > 0.2 and above < 4.0:
				_place_flora(FloraS.make_palm(rng, rng.randf_range(0.85, 1.15)), p.x, p.y, rng.randf() * TAU)
				break


# ——————————————— 房屋：进入 / 离开 ———————————————
## 登记一栋可进入建筑。
## idx   —— 同类里的编号，用来拼稳定 id。玩家自建的帐篷传 built_items 的下标，
##          读档按同样顺序重建才能对上同一间室内。
## tag   —— id 前缀，用来把"同一类建筑的不同来源"分开：镇上的帐篷营地是 _camp，
##          玩家自建的是空。不加这个，营地第一顶帐篷和玩家造的第一顶会撞成同一个 id，
##          两顶帐篷共用一间室内（进去看到的是别人的屋子）。
## built —— 是否是玩家建造的。读档时要清掉旧的玩家建造物再按存档重建，
##          靠它区分"该清"和"场景自带的、要留着"。
func _register_house(kind: String, pos2: Vector2, rot: float, idx := 0,
		tag := "", built := false) -> String:
	if not InteriorS.is_enterable(kind):
		return ""
	var id := "%s%s_%d" % [kind, tag, idx]
	houses.append({
		"id": id,
		"kind": kind,
		"title": str(InteriorS.spec_of(kind).get("title", "屋子")),
		"pos": pos2,
		"rot": rot,
		"built": built,
	})
	return id


## 玩家脚下够得着的那扇门（户外才有意义）
func _door_target() -> Dictionary:
	if house_id != "" or player == null:
		return {}
	for h in houses:
		var hd: Dictionary = h
		if InteriorS.at_door(player.global_position, hd.get("entrance_origin", hd.get("pos", Vector2.ZERO)),
				float(hd.get("rot", 0.0)), str(hd.get("kind", "hut"))):
			return hd
	return {}


func _house_title(id: String) -> String:
	for h in houses:
		if str(h.get("id", "")) == id:
			return str(h.get("title", "屋子"))
	return "屋子"


## F 键的语义：屋里就是"离开"，屋外优先"进屋"，都不沾边才落到农事上。
## 农事原来独占 F，现在让位给门——站在门口按 F 却去锄地才叫反直觉。
func _interact() -> void:
	if player == null:
		return
	if house_id != "":
		# 屋里只有一个交互键：站在床边是睡觉，其余位置是出门。
		# 不做成两个键（比如 F 睡觉 / Esc 出门）：床上按 F 却把人赶出屋子才是反直觉。
		if _bed_near():
			_open_sleep()
			return
		_exit_house()
		return
	var h := _door_target()
	if not h.is_empty():
		_enter_house(h)
		return
	if farm != null:
		farm.interact(player.global_position)


func _enter_house(h: Dictionary) -> void:
	if interior == null or player == null or terrain == null:
		return
	if interior.busy:
		return
	var id := str(h.get("id", ""))
	var kind := str(h.get("kind", "hut"))
	var sp: Dictionary = interior.ensure(id, kind, map_seed)
	if sp.is_empty():
		return
	sp["title"] = str(h.get("title", sp.get("title", "屋子")))

	# 出门落点现在就定死：出门、存档都用它，避免"退出点"被玩家走动带偏
	var pos2: Vector2 = h.get("pos", Vector2.ZERO)
	var ex2: Vector2 = h.get("exit_point", InteriorS.exit_point(pos2, float(h.get("rot", 0.0)), kind))
	outdoor_exit = Vector3(ex2.x, terrain.height_at(ex2.x, ex2.y) + 0.1, ex2.y)

	# 建造模式的预览是跟着视线落在地面上的，屋里没有地；带着它进屋会留下一个
	# 悬空的半透明帐篷。所以进门一律先收掉建造模式。
	if build_mode:
		_set_build_mode(false)
		_refresh_preview()
		_restore_hotbar_after_build()

	interior.warp(func(): _apply_enter(id, sp))


func _apply_enter(id: String, sp: Dictionary) -> void:
	house_id = id
	interior.show_only(id)
	player.global_position = sp.get("spawn", Vector3.ZERO)
	player.yaw = float(sp.get("spawn_yaw", 0.0))
	player.pitch = -0.22
	player.enter_indoor(float(sp.get("floor_y", 40.0)), sp.get("center", Vector2.ZERO),
		sp.get("half", Vector2(4.0, 4.0)), sp.get("colliders", []))
	# 屋里不该下雨：雨幕是挂在玩家身上的粒子柱，不关掉就成了"室内暴雨"
	_on_weather(season.weather if season != null else "clear")
	if hud != null:
		hud.toast(str(sp.get("title", "屋子")))


func _exit_house(silent := false) -> void:
	if house_id == "" or interior == null:
		return
	if interior.busy:
		return
	interior.warp(func(): _apply_exit(silent))


func _apply_exit(_silent := false) -> void:
	house_id = ""
	if player != null:
		player.exit_indoor(colliders)
		player.global_position = outdoor_exit
		player.pitch = -0.35
	if interior != null:
		interior.hide_all()
	_on_weather(season.weather if season != null else "clear")
	if hud != null and not _silent:
		hud.toast("已出门")


# ——————————————— 睡觉 ———————————————
## 床边判定半径：玩家到床（或睡袋）中心的水平距离小于它就认为"站在床边"。
## 【下限】床的避让圆是 1.2，加上玩家半径 0.42 → 最近只能站到 1.62 米，
## 判定半径必须比它大，否则会出现"贴着床却按不出睡觉"。
## 【上限】它也不能太大：帐篷里的出生点离睡袋只有 2 米出头，判定圈一旦罩住出生点，
## 玩家一进门按 F 就是"睡觉"而不是"出门"——门都出不去（真踩过）。
## 1.75 落在 1.62 与 2.04 之间，两头都留了余量。
const SLEEP_REACH := 1.75


## 当前所在室内有没有床、玩家是不是站在床边
func _bed_near() -> bool:
	if house_id == "" or interior == null or player == null:
		return false
	var sp: Dictionary = interior.space_of(house_id)
	if not bool(sp.get("can_sleep", false)):
		return false
	var bed: Vector3 = sp.get("bed", Vector3.ZERO)
	return Vector2(player.global_position.x - bed.x,
		player.global_position.z - bed.z).length() < SLEEP_REACH


func _open_sleep() -> void:
	if sleep_panel == null or dn == null:
		return
	# 把"现在几点"做成回调传进去：面板是常驻实例，睡一次时间就变了，
	# 不能在建面板时把时刻写死。
	sleep_panel.open(func(): return dn.time * 24.0)


func _on_sleep_picked(hour: float) -> void:
	if dn == null:
		return
	# 黑屏过场里推进时间：玩家不会看到太阳"啪"地跳过去
	if interior != null:
		interior.warp(func(): _apply_sleep(hour))
	else:
		_apply_sleep(hour)


## 真正推进时间。
## 【为什么不手动 emit new_day】季节模块每帧比较 day_count 与它记的上一次值，
## 发现变大就自己推进季节/天气并发出 new_day，自动存档挂在那个信号上。
## 这里只要改 day_count，剩下的一条链会自动跑完；手动再 emit 一次反而会重复推进。
func _apply_sleep(hour: float) -> void:
	var cur := dn.time * 24.0
	var days := 0
	if hour <= cur + 0.02:
		days = 1                    # 目标时刻已经过去（或就是现在）→ 睡到明天
	dn.day_count += days
	dn.time = hour / 24.0
	# 睡醒复位：憋气回满、退出下潜姿态
	if player != null:
		player.breath = 1.0
		player.diving = false
	if hud != null:
		var txt := "睡到 %s" % _clock_text(hour)
		if days > 0:
			txt += "　第 %d 天" % dn.day_count
		hud.toast(txt)


func _clock_text(h: float) -> String:
	return "%02d:%02d" % [int(h) % 24, int(roundf((h - floorf(h)) * 60.0))]


# ——————————————— 植被与岩石 ———————————————
func _ok_spot(p: Vector2, clear: float, min_town: float, min_lake: float) -> bool:
	if absf(p.x) > 102.0 or absf(p.y) > 102.0:
		return false
	if p.distance_to(TOWN) < min_town:
		return false
	if p.distance_to(LAKE) < min_lake:
		return false
	# 水里不撒：跟水位比，别跟绝对高度比（见 terrain.BASE_LIFT）
	if terrain.water_depth_at(p.x, p.y) > 0.0:
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
		terrain.register_tintable(mmi.material_override)


# ——————————————— 动物 ———————————————
func _spawn_critters() -> void:
	for i in 11:
		var p := _random_spot(42.0, 38.0, 3.0)
		if p == Vector2.ZERO:
			continue
		var k: Node3D = KangarooS.new() if OS.get_cmdline_user_args().has("--no-characters") else WildlifeS.new()
		if k is WildlifeS:
			k.species = "Stag" if i % 3 == 0 else "Deer"
		add_child(k)
		k.setup(terrain, p, player)
		_register_critter(k)

	for i in 4:
		var p := _random_spot(48.0, 40.0, 4.0)
		if p == Vector2.ZERO:
			continue
		var e: Node3D = EmuS.new() if OS.get_cmdline_user_args().has("--no-characters") else WildlifeS.new()
		if e is WildlifeS:
			e.species = "Fox"
			e.small = true
		add_child(e)
		e.setup(terrain, p, player)
		_register_critter(e)


## 把一只可狩猎动物纳入管理：接死亡信号，登记碰撞体（玩家不能穿过去）
func _register_critter(c: Node3D) -> void:
	if not (c is Huntable):
		return
	critters.append(c)
	var h := c as Huntable
	h.died.connect(_on_critter_died)
	var body := AnimatableBody3D.new()
	body.name = "AnimalCollision"
	body.sync_to_physics = false
	body.collision_layer = 8
	body.collision_mask = 2
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = h.hit_radius * 0.45
	capsule.height = maxf(1.35, capsule.radius * 2.0)
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	body.add_child(shape)
	c.add_child(body)
	# 保留占地记录，供建筑放置检查使用。
	colliders.append({
		"node": c,
		"pos": Vector2(c.global_position.x, c.global_position.z),
		"r": h.hit_radius * 0.55,
	})


func _on_critter_died(drop: Dictionary, pos: Vector3) -> void:
	var h := _find_critter_at(pos)
	if h == null:
		_diag("died 回调找不到对应动物 pos=%s critters=%d" % [str(pos), critters.size()])
		return
	var got := h.roll_drops()
	var txt := ""
	for d in got:
		var kind: String = d.kind
		var amt: int = d.amount
		inv[kind] = int(inv.get(kind, 0)) + amt
		txt += "+%d %s  " % [amt, hud.RES_NAME.get(kind, kind)]
		GameBus.res_harvested.emit(kind, amt, pos)
	_diag("died 结算 got=%s inv_food=%d" % [str(got), int(inv.get("food", 0))])
	if txt != "":
		hud.toast(txt.strip_edges())
		hud.set_resources(inv)


## 轻量诊断：只在带 --combat-diag 时把内容追加到 res://combat_diag.log
func _diag(msg: String) -> void:
	if not OS.get_cmdline_args().has("--combat-diag"):
		return
	var path := "res://combat_diag.log"
	# 用 READ_WRITE 打开后在末尾写；文件不存在时退回 WRITE 新建
	var f: FileAccess = null
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_line(msg)
		f.close()


func _find_critter_at(pos: Vector3) -> Huntable:
	for c in critters:
		if not is_instance_valid(c):
			continue
		if (c as Huntable).global_position.distance_to(pos) < 0.01:
			return c as Huntable
	return null


# ——————————————— 输入 ———————————————
## 系统返回键（Android 返回手势 / 键）。
## _notification 不受 get_tree().paused 影响，所以暂停菜单开着时也一定收得到；
## 统一走 _back_requested()，与键盘 Esc 共用同一套"逐层退出"逻辑。
func _notification(what: int) -> void:
	if what == Node.NOTIFICATION_WM_GO_BACK_REQUEST:
		_back_requested()


## Esc / 返回键的统一处理：从最内层往外一层层退。
## 顺序：暂停菜单子面板 → 暂停菜单 → 背包 → 建造模式 → 都没了才开暂停菜单。
func _back_requested() -> void:
	# 睡觉面板把游戏暂停了，桌面 Esc 会由面板自己接走；
	# 但 Android 的返回键走 _notification（不受 paused 影响），会到这里，先关它。
	if sleep_panel != null and sleep_panel.is_open():
		sleep_panel.close()
		return
	if pause_menu != null and pause_menu.go_back():
		return
	_do_action("esc")


## 返回键去重：Android 上 _notification 与 ui_cancel 可能【同时】报到同一个返回动作，
## 两次都处理就成了"打开又立刻关闭"，看起来像按了没反应。
## 窗口取 100ms——足够盖住同一帧的重复，又不会吞掉玩家正常的连按。
var _back_last_ms := 0


func _back_debounce() -> bool:
	var now := Time.get_ticks_msec()
	if now - _back_last_ms < 100:
		return false
	_back_last_ms = now
	return true


func _unhandled_input(event: InputEvent) -> void:
	# 【为什么 Esc 要在这里单独接一次】ui_cancel 除了键盘 Esc 还覆盖手柄的 B、
	# 以及部分平台把返回键也映射成它。但 Android 返回键主要走 _notification，
	# 两边都发时会出现"开一下又关一下"等于没反应，所以这里用时间窗去重。
	if event.is_action_pressed("ui_cancel"):
		if _back_debounce():
			_back_requested()
			get_viewport().set_input_as_handled()
		return

	# 背包打开时只放行"关背包"和"再按一次背包键"，其余游戏输入一律吞掉。
	# 否则会出现"点背包里的武器按钮 -> 同一帧鼠标左键也触发一次挥砍"。
	if inv_ui != null and inv_ui.is_open():
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_ESCAPE: _back_requested()
				KEY_I, KEY_TAB: _do_action("bag")
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E: _do_action("harvest")
			KEY_B: _do_action("build")
			KEY_I: _do_action("bag")
			KEY_TAB: _do_action("bag")
			# 数字键在建造模式下等价于直接放建筑，否则切武器。这样一套键位
			# 在两种模式下都说得通，不用记两套。
			KEY_1, KEY_2, KEY_3, KEY_4:
				if build_mode:
					_do_action("pick%d" % (event.keycode - KEY_1 + 1))
				else:
					_do_action("hot%d" % (event.keycode - KEY_1 + 1))
			KEY_R: _do_action("rotate")
			KEY_F: _do_action("interact")
			KEY_Q: _do_action("swap_weapon")
			KEY_F2: _do_action("save")
			KEY_F3: _do_action("load")
			KEY_G: _do_action("crop")
			KEY_M: _do_action("mute")
			KEY_T: _do_action("time")
			KEY_H: _do_action("help")
			KEY_ESCAPE: _back_requested()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if build_mode and not GameBus.touch_enabled:
				# 建造模式：左键落下建筑
				_try_place_at_mouse()
			elif not build_mode and not GameBus.touch_enabled:
				# 探索模式：左键挥砍
				_attack()


## 所有游戏动作的唯一入口：键盘与触控按钮共用
func _do_action(a: String) -> void:
	match a:
		"harvest":
			_harvest()
		"bag":
			_toggle_bag()
		"build":
			# 屋里不建：预览是靠地面射线 / 视线前方距离定位的，室内没有地形可落
			if house_id != "":
				if hud != null:
					hud.toast("室内不能建造")
				return
			# 水里不建：预览会浮在水面上，落位判定也过不去，直接不进这个模式
			if not _can_act():
				return
			build_mode = not build_mode
			if build_mode:
				preview_dist = _find_good_preview_dist()
				# 进建造模式时把物品栏切到当前建筑对应的那一格，避免"看到的是斧头，
				# 放下去的却是帐篷"这种不一致
				_equip_build_slot(build_index)
			_refresh_preview()
		"rotate":
			if build_mode:
				preview_rot += PI * 0.25
		"place":
			_try_place_at_mouse()
		"farm":
			if farm != null:
				farm.interact(player.global_position)
		"interact":
			_interact()
		"attack", "use":
			if build_mode:
				_try_place_at_mouse()
			else:
				_attack()
		"swap_weapon":
			_cycle_held_weapon(1)
		"save":
			if save_sys != null:
				save_sys.save(1)
		"load":
			if save_sys != null:
				save_sys.load(1)
		"crop":
			if farm != null:
				hud.toast("作物：" + farm.cycle_crop(1))
		"mute":
			AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0))
			hud.toast("音效已" + ("静音" if AudioServer.is_bus_mute(0) else "开启"))
		"time":
			dn.toggle_speed()
		"help":
			if hud != null:
				var on := not hud.help_label.visible
				hud.show_help_panel(on)
		"esc":
			if sleep_panel != null and sleep_panel.is_open():
				sleep_panel.close()
				return
			# Esc 是"退出当前这一层"：先关背包，再退建造模式，都没有才开暂停菜单。
			# 注意暂停菜单自身的关闭不在这里——它走 pause_menu.go_back()，
			# 因为菜单打开时游戏是 paused 的，_unhandled_input 根本不会跑到这里。
			if inv_ui != null and inv_ui.is_open():
				inv_ui.close()
				return
			if build_mode:
				_set_build_mode(false)
				_restore_hotbar_after_build()
				_refresh_preview()
				return
			_toggle_pause()
		"pause":
			_toggle_pause()
		"reset_joy":
			# 设置面板里"重置摇杆"发来的：光写配置文件不够，挂载中的
			# TouchControls 不会重读，必须让它自己重排一次。
			var tc := get_node_or_null("TouchControls")
			if tc != null and tc.has_method("reset_joy_position"):
				tc.reset_joy_position()
		"menu":
			return_to_menu()
		"jump":
			GameBus.touch_jump_edge = true
		_:
			if a.begins_with("pick"):
				var i := int(a.substr(4)) - 1
				if i >= 0 and i < BUILD_ITEMS.size():
					build_index = i
					_set_build_mode(true)
					preview_dist = _find_good_preview_dist()
					_equip_build_slot(i)
					_refresh_preview()
			elif a.begins_with("hot"):
				var i := int(a.substr(3)) - 1
				_select_hotbar(i)


# ——————————————— 快捷物品栏 ———————————————
## 重建槽位表：3 件武器 + 3 项建筑，取前 4 个能装下的组合。
## 为什么是"武器在前、建筑在后"：探索采集占玩家 80% 的时间，武器必须零成本可及；
## 建筑放后面，进建造模式时会被 _equip_build_slot() 临时顶到第 1 格。
func _rebuild_hotbar() -> void:
	var slots: Array = []
	var n: int = WeaponsS.count()
	for i in n:
		if slots.size() >= 4:
			break
		var w: Dictionary = WeaponsS.get_at(i)
		slots.append({
			"kind": SLOT_WEAPON,
			"id": str(w.get("id", "")),
			"name": str(w.get("name", "武器")),
			"label": str(w.get("name", "武器")),
		})
	for i in BUILD_ITEMS.size():
		if slots.size() >= 4:
			break
		var it: Dictionary = BUILD_ITEMS[i]
		slots.append({
			"kind": SLOT_BUILD,
			"id": str(it.get("make", "")),
			"name": str(it.get("name", "建筑")),
			"label": str(it.get("name", "建筑")),
			"build_index": i,
		})
	hotbar = slots
	hotbar_sel = clampi(hotbar_sel, 0, maxi(0, hotbar.size() - 1))
	_sync_hotbar()


func _sync_hotbar() -> void:
	if GameBus == null:
		return
	GameBus.sync_hotbar(hotbar, hotbar_sel)


func _slot(i: int) -> Dictionary:
	if i < 0 or i >= hotbar.size():
		return {}
	return hotbar[i]


## 点选物品栏某一格：按槽位类型落到 player.weapon_idx 或 build_index 上
func _select_hotbar(i: int) -> void:
	var s := _slot(i)
	if s.is_empty():
		return
	var kind := str(s.get("kind", SLOT_EMPTY))
	if kind == SLOT_EMPTY:
		hud.toast("第 %d 格是空的" % (i + 1))
		return
	hotbar_sel = i
	if kind == SLOT_WEAPON:
		# 选武器 = 退出建造模式，避免"拿着斧头还在建造"
		if build_mode:
			_set_build_mode(false)
			_refresh_preview()
		_equip_weapon(str(s.get("id", "")))
	elif kind == SLOT_BUILD:
		build_index = int(s.get("build_index", 0))
		_set_build_mode(true)
		preview_dist = _find_good_preview_dist()
		_refresh_preview()
	_sync_hotbar()


## 建造模式开关的唯一出口：顺带把状态镜像到 GameBus，
## 让触控层知道单指拖动该转视角还是该挪建造预览。
func _set_build_mode(on: bool) -> void:
	build_mode = on
	GameBus.build_mode = on


# ——————————————— 背包界面 ———————————————
func _toggle_bag() -> void:
	if inv_ui == null:
		return
	# 进背包前先退建造模式：两者的"当前手持物"语义会打架
	if not inv_ui.is_open() and build_mode:
		_set_build_mode(false)
		_refresh_preview()
	inv_ui.toggle()
	# 同步高亮到当前手持武器（可能刚被换过）
	if inv_ui.is_open():
		inv_ui.set_equipped(player.weapon_id())


func _on_bag_closed() -> void:
	_release_touch()


## 关掉任何模态界面后都要清一次触控残留：同一帧可能还有手指按着，
## 不清就会出现"关掉菜单后角色自己往前走"。
func _release_touch() -> void:
	var tc := get_node_or_null("TouchControls")
	if tc != null and tc.has_method("release_all"):
		tc.release_all()


# ——————————————— 暂停菜单 ———————————————
func _toggle_pause() -> void:
	if pause_menu == null:
		return
	if pause_menu.is_open():
		pause_menu.close()
		return
	# 背包与暂停菜单叠在一起时，关掉菜单会露出一个孤儿背包，先收掉
	if inv_ui != null and inv_ui.is_open():
		inv_ui.close()
	# 建造模式【不】主动退出：玩家可能只是中途看一眼，回来要接着摆。
	# 暂停期间预览不动，没有副作用。
	pause_menu.open()


func _on_pause_closed() -> void:
	_release_touch()


func _on_pause_quit() -> void:
	# 菜单自己已经解除了暂停（否则主界面会以 paused 状态启动、一动不动）
	return_to_menu()


## 菜单里选了槽位：先关菜单解除暂停，再就地读档回到这个世界
func _on_pause_load(slot: int) -> void:
	if save_sys == null:
		return
	pause_menu.close()
	var ok: bool = save_sys.load(slot)
	# 武器槽位与物品栏是存档内容的一部分，读档后要重建下发
	_rebuild_hotbar()
	if hud != null:
		hud.toast("已读取槽位 %d" % (slot + 1) if ok else "读取失败")


## 背包数据源：资源计数（只读快照）
func _bag_inv() -> Dictionary:
	return inv


## 背包数据源：底部统计行
func _bag_stat() -> String:
	var total := 0
	for k in inv:
		total += int(inv[k])
	var alive := 0
	for c in critters:
		if is_instance_valid(c):
			var h := c as Huntable
			if h != null and not h.is_dead():
				alive += 1
	return "第 %d 天 · 资源合计 %d · 已建造 %d 座 · 已采集 %d 处 · 野外动物 %d 只" % [
		dn.day_count, total, built_items.size(), harvested_ids.size(), alive]


## 背包里点某把武器 -> 装备（与物品栏走同一套真值）
func _bag_equip(id: String) -> void:
	_equip_weapon(id)
	hud.toast("已装备 " + player.weapon_name())


## 把 player 的当前武器同步到数据层，并刷新物品栏选中态
func _equip_weapon(id: String) -> void:
	var w: Dictionary = WeaponsS.find(id)
	if w.is_empty():
		return
	var n: int = WeaponsS.count()
	for i in n:
		if str(WeaponsS.get_at(i).get("id", "")) == id:
			player.weapon_idx = i
			break
	GameBus.tool_changed.emit(player.weapon_name())
	hud.set_weapon("武器：" + player.weapon_name() + _hint("（Q 切换）", ""))
	_sync_sel_to_weapon()
	_sync_equipped_marks()


## 武器换过之后，背包里那把的 ▶ 标记也要跟着走（背包没开时只记 id，开时顺带重绘）
func _sync_equipped_marks() -> void:
	if inv_ui != null:
		inv_ui.set_equipped(player.weapon_id())


## 按当前手持武器反推应该高亮哪一格
func _sync_sel_to_weapon() -> void:
	for i in hotbar.size():
		var s: Dictionary = hotbar[i]
		if str(s.get("kind", "")) == SLOT_WEAPON and str(s.get("id", "")) == player.weapon_id():
			hotbar_sel = i
			_sync_hotbar()
			return


## 切武器：既改 player 也改高亮，两者始终一致
func _cycle_held_weapon(dir: int) -> void:
	player.cycle_weapon(dir)
	hud.toast("武器：" + player.weapon_name())
	_sync_sel_to_weapon()
	_sync_equipped_marks()


## 进建造模式：把当前建筑临时塞到第 1 格并选中，用完 _restore_hotbar_after_build() 还原
func _equip_build_slot(bi: int) -> void:
	if bi < 0 or bi >= BUILD_ITEMS.size():
		return
	var it: Dictionary = BUILD_ITEMS[bi]
	hotbar_sel = 0
	_sync_hotbar()
	hud.toast("建造：" + str(it.get("name", "")))


func _restore_hotbar_after_build() -> void:
	_sync_sel_to_weapon()


# ——————————————— 战斗 ———————————————
## 挥砍一次：判定前方扇形内最近的一只可狩猎动物
## 水里能不能做采集/攻击/放置这类"手上活"
## 【为什么直接禁掉而不是让它在水下也能用】玩家在水里是游泳姿态、双手在划水，
## 挥斧头和挖树桩都不成立；而且水下还有动物贴着湖底走的话，
## 允许攻击会变成"站在岸上隔水砍湖底的东西"这种更奇怪的画面。
func _can_act() -> bool:
	return player == null or not player.swimming


func _attack() -> void:
	if not _can_act():
		return
	var beast := _find_critter_in_arc(player.global_position, player.aim_dir(), false)
	if beast == null:
		# 没打到也要挥出去，否则触屏连点毫无反馈
		player.start_attack()
		return
	_attack_at(beast)


## 对指定目标出手。扇形判定已在 _find_critter_in_arc 里做完了，这里只做伤害结算。
func _attack_at(beast: Huntable) -> void:
	var w: Dictionary = player.start_attack()
	if w.is_empty():
		return                       # 冷却未好 / 无武器

	var dmg: int = int(w.get("dmg", 10))
	var res: Dictionary = beast.take_hit(dmg, player.global_position)
	if bool(res.get("dead", false)):
		hud.toast("猎获！")
	else:
		hud.toast("命中 -%d" % dmg)


## 扇形内最近的动物。
## padded = true 时额外放宽射程 TAP_ATTACK_PAD——触屏点选是"我指哪打哪"，
## 手指没有准星精度，用桌面端的严格 reach 会导致大量落空。
func _find_critter_in_arc(origin: Vector3, dir: Vector3, padded: bool) -> Huntable:
	var w: Dictionary = player.weapon()
	var reach: float = float(w.get("reach", 2.6))
	if padded:
		reach += TAP_ATTACK_PAD
	var arc: float = float(w.get("arc", 0.6))

	var best: Huntable = null
	# 注意 best_d 必须让"命中盒放宽"也算进去，否则会出现这种矛盾：
	# 距离检查用的是 reach + hit_radius（够得着），但 best_d 仍是 reach（被判出局），
	# 结果贴脸站着的大动物反而打不到。所以初值给一个大到不会被误判的上界。
	var best_d := INF
	for c in critters:
		if not is_instance_valid(c):
			continue
		var h := c as Huntable
		if h == null or h.is_dead():
			continue
		var to: Vector3 = h.global_position - origin
		to.y = 0.0
		var d: float = to.length()
		# 命中盒：动物半径算进去，大动物更容易被打到
		if d > reach + h.hit_radius:
			continue
		if d > 0.01:
			var cos_a: float = dir.dot(to.normalized())
			if cos_a < cos(arc):
				continue
		if d < best_d:
			best_d = d
			best = h
	return best


## 扇形内最近的资源节点。资源不会跑，判定比动物宽容：
## 角度放宽到 TAP_ARC，距离用 _nearest_resource 的 3.8 上限再松一点。
func _find_resource_in_arc(origin: Vector3, dir: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := 5.6
	for n in resources:
		if not is_instance_valid(n):
			continue
		var to: Vector3 = n.global_position - origin
		to.y = 0.0
		var d: float = to.length()
		if d > bd:
			continue
		if d > 0.01:
			var cos_a: float = dir.dot(to.normalized())
			if cos_a < cos(TAP_ARC):
				continue
		bd = d
		best = n
	return best


## 返回附近可攻击动物的中文名（无则空串）。用于准星附近的交互提示。
func _nearest_critter() -> String:
	var pp := player.global_position
	var w: Dictionary = player.weapon()
	var reach: float = float(w.get("reach", 2.6))
	var best := ""
	var bd: float = reach + 1.4
	for c in critters:
		if not is_instance_valid(c):
			continue
		var h := c as Huntable
		if h == null or h.is_dead():
			continue
		var d := Vector2(h.global_position.x - pp.x, h.global_position.z - pp.z).length()
		if d < bd:
			bd = d
			# 用脚本资源判断种类：kangaroo.gd / emu.gd 都没有 class_name，不能用 is
			var sp: String = h.get_script().resource_path if h.get_script() != null else ""
			best = str(h.get_meta("species_name", "袋鼠" if sp.ends_with("kangaroo.gd") else "鸸鹋"))
	return best


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
	if not _can_act():
		return
	var n := _nearest_resource()
	if n == null:
		return
	_collect_resource(n)


## 收走一个资源节点：silent=true 时只移除不入库（读档时回放已采集状态）
func _collect_resource(n: Node3D, silent := false) -> void:
	var kind: String = n.get_meta("resource", "wood")
	var amt: int = int(n.get_meta("amount", 1))
	var p := n.global_position
	var rid: int = int(n.get_meta("rid", -1))

	if not silent:
		inv[kind] = int(inv.get(kind, 0)) + amt
		hud.set_resources(inv)
		hud.toast("+%d %s" % [amt, hud.RES_NAME[kind]])
		GameBus.res_harvested.emit(kind, amt, p)

	if rid >= 0 and not harvested_ids.has(rid):
		harvested_ids.append(rid)

	resources.erase(n)
	for i in range(colliders.size() - 1, -1, -1):
		if colliders[i].node == n:
			colliders.remove_at(i)
			break
	n.queue_free()

	if kind == "wood" and not silent:
		var stump := FloraS.make_stump()
		stump.position = Vector3(p.x, terrain.height_at(p.x, p.z), p.z)
		add_child(stump)
		# 采集收益仍立即入包；木段是可推动的环境反馈，不重复发资源。
		_spawn_prop("log", p + Vector3(0.9, 1.1, 0.4))


func _spawn_prop(kind: String, pos: Vector3, visual := "") -> RigidBody3D:
	physics_props = physics_props.filter(func(p): return is_instance_valid(p) and not p.is_queued_for_deletion())
	if physics_props.size() >= MAX_PHYSICS_PROPS:
		# 只回收最早生成的木段，保留玩家已经推走的木箱。
		var oldest := -1
		for i in physics_props.size():
			if physics_props[i].kind == "log":
				oldest = i
				break
		if oldest < 0:
			return null
		physics_props[oldest].queue_free()
		physics_props.remove_at(oldest)
	var body := PhysicsPropS.new()
	body.configure(kind, terrain, visual)
	body.position = pos
	add_child(body)
	physics_props.append(body)
	return body


func _serialize_props() -> Array:
	var out: Array = []
	for prop in physics_props:
		if is_instance_valid(prop) and not prop.is_queued_for_deletion():
			out.append(prop.serialize())
	return out


func _restore_props(data: Variant) -> void:
	# 没有这个字段的旧存档继续使用开局的木箱与漂木。
	if not data is Array:
		return
	for prop in physics_props:
		if is_instance_valid(prop):
			prop.freeze = true
			prop.collision_layer = 0
			prop.collision_mask = 0
			prop.queue_free()
	physics_props.clear()

	for entry in data:
		if not entry is Dictionary or physics_props.size() >= MAX_PHYSICS_PROPS:
			continue
		var kind := str(entry.get("kind", "crate"))
		if not kind in ["crate", "barrel", "log"]:
			continue
		# 外观按种类迁移，不改变存档中的道具数量与运动状态。
		var visual := str(entry.get("visual", "emace_" + kind))
		var body := _spawn_prop(kind, PhysicsPropS._read_vec(entry.get("pos", [])), visual)
		if body != null:
			body.restore(entry)


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
	# 立刻摆到正前方，避免第一帧出现在原点
	_set_preview_pos(_preview_in_front())


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
	# 水里不能放：用实际水深判定，覆盖整个水面（比原来的固定半径圆更贴合岸线）
	if terrain.water_depth_at(p.x, p.z) > 0.15:
		return false
	# 水面线以上再留一点干燥边距，别让建筑半只脚泡在水里
	if p.y < terrain.water_level() + 0.25:
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
	var bn := _make_build(item.make)
	bn.set_meta("player_built", true)
	_place(bn, p.x, p.z, preview_rot)
	hud.toast("已放置 " + item.name)
	built_items.append({"kind": item.make, "x": p.x, "z": p.z, "rot": preview_rot})
	# 帐篷能进：编号用它在 built_items 里的下标，读档按同样顺序重建才能对上同一间
	_register_house(item.make, Vector2(p.x, p.z), preview_rot, built_items.size() - 1, "", true)
	dn.collect_night_lights(self)
	GameBus.item_built.emit(item.make, p)


# ——————————————— 主循环 ———————————————
func _process(dt: float) -> void:
	var t := Time.get_ticks_msec() * 0.001

	for s in spins:
		if not is_instance_valid(s.node):
			continue
		s.node.rotate_z(s.speed * dt)
	for b in bobs:
		if not is_instance_valid(b.node):
			continue
		b.node.position.y = b.base + sin(t * 1.1 + b.base * 3.0) * 0.09
		b.node.rotation.z = sin(t * 0.9) * 0.03
	for f in flickers:
		if not is_instance_valid(f.node):
			continue
		var k := 0.85 + sin(t * 9.0 * f.speed) * 0.12 + sin(t * 21.0 * f.speed) * 0.05
		f.node.scale = Vector3(k, k * 1.1, k)
		f.node.rotation.y += dt * 1.4

	if not build_mode and player != null and player.swimming:
		# 水里优先播报水域状态：这时采集/攻击/农事都不可用，显示那些只会误导
		var tip := "下潜中" if player.diving else "游泳中"
		hud.set_prompt("%s · 按住 %s 下潜　松开上浮" % [tip, _hint("[Ctrl]", "「潜」")])
		hud.set_build("")
	elif not build_mode:
		if house_id != "":
			if _bed_near():
				hud.set_prompt(_hint("[F] 睡觉", "点「使用」睡觉"))
			else:
				# 屋里按 F 直接出门，不要求走回门口：房间就这么大，
				# 非要走到门垫上才能出去只会让人烦躁。
				hud.set_prompt(_hint("[F] 离开 %s", "点「使用」离开 %s") % _house_title(house_id))
		else:
			var hh := _door_target()
			if not hh.is_empty():
				hud.set_prompt(_hint("[F] 进入 %s", "点「使用」进入 %s") % str(hh.get("title", "屋子")))
			else:
				var n := _nearest_resource()
				var beast := _nearest_critter()
				if n != null:
					var kind: String = n.get_meta("resource", "wood")
					hud.set_prompt(_hint("[E] 采集 %s  ×%d", "点击采集 %s  ×%d") % [hud.RES_NAME[kind], int(n.get_meta("amount", 1))])
				elif beast != null:
					hud.set_prompt(_hint("[左键] 攻击 %s　[Q] 换武器", "点击攻击 %s") % beast)
				else:
					hud.set_prompt("")
				if farm != null:
					var fp := farm.prompt_text(player.global_position)
					if fp != "":
						hud.set_prompt(fp + _hint("　[G] 切换作物：", "　切换作物：") + farm.selected_crop_name())
	else:
		var item: Dictionary = BUILD_ITEMS[build_index]
		var cost_txt := ""
		for k in item.cost:
			cost_txt += "%s%d " % [hud.RES_NAME[k], int(item.cost[k])]
		var ok_now := _place_ok(_preview_in_front(), 1.0) if GameBus.touch_enabled else true
		var tip := "可放置" if ok_now else "此处放不下"
		# 【两条分支必须各自格式化】桌面那句只有 2 个 %s，触控那句有 3 个，
		# 用 _hint() 选出句子后再统一 % 一个三元组，桌面端每帧都会抛
		# "not all arguments converted" —— 参数多了。所以分支里各写一次。
		if GameBus.touch_enabled:
			hud.set_prompt("建造模式：拖动调整位置 · 点「放置」确认 %s（%s）· %s"
				% [item.name, cost_txt, tip])
		else:
			hud.set_prompt("建造模式：左键放置 %s（%s）  [R]旋转  [Esc]退出"
				% [item.name, cost_txt])

	if build_mode and preview != null:
		# 触控：预览固定在视线前方 preview_dist 处，由拖动/轻点调整；
		# 桌面：跟随鼠标地面射线，保持原有手感。
		var g := _preview_in_front() if GameBus.touch_enabled else _pick_ground(get_viewport().get_mouse_position())
		if g != Vector3.ZERO:
			_set_preview_pos(g)
			var ok := _place_ok(g, 1.0) and _can_afford(BUILD_ITEMS[build_index].cost)
			for mi in _all_meshes(preview):
				mi.transparency = 0.45 if ok else 0.8

	# —— 脚步事件（音效模块消费）——
	var ppos := player.global_position
	var moved := ppos.distance_to(last_pos)
	last_pos = ppos
	if moved > 0.0005:
		step_dist += moved
		if step_dist >= 1.9:
			step_dist = 0.0
			# 角色按固定物理帧移动，渲染帧的 moved/dt 会随刷新率抖动；用真实速度驱动音高。
			GameBus.player_step.emit(Vector2(player.velocity.x, player.velocity.z).length(), ppos)

	_update_water_hud()

	hud_timer -= dt
	if hud_timer <= 0.0:
		hud_timer = 0.2
		hud.set_clock(dn.day_count, dn.clock_string(), dn.speed_scale)
		hud.set_build(_build_menu_text())
		hud.set_weapon("武器：" + player.weapon_name() + _hint("（Q 切换）", ""))
		if season != null:
			hud.set_season("%s · 第 %d 天 · %s" % [season.season_name, dn.day_count, _weather_cn(season.weather)])


## 水域相关的 HUD 刷新。
## 【为什么不能塞进 0.2 秒的 hud_timer】水下遮罩是"相机一入水就变色"，
## 延迟 0.2 秒会看到明显的卡顿；憋气条也会一跳一跳。这两样必须每帧跟手。
func _update_water_hud() -> void:
	if hud == null or player == null:
		return
	hud.set_underwater(player.camera_underwater())
	# 头入水时显示；出水后等气回满再收起来，免得条子在屏幕边缘一闪一闪
	if player.head_underwater() or player.breath < 0.995:
		hud.set_breath(player.breath)
	else:
		hud.set_breath(-1.0)


func _weather_cn(w: String) -> String:
	match w:
		"clear": return "晴"
		"sunny": return "晴"
		"cloudy": return "多云"
		"rain": return "下雨"
		"storm": return "暴风雨"
		"heat": return "热浪"
	return w


## 每日自动存档（槽 0）
func _on_auto_save(_day: int, _season: int) -> void:
	if save_sys != null:
		save_sys.save(0)


func _build_menu_text() -> String:
	if house_id != "":
		# 屋里不能建造，再挂一行"[B] 建造模式"就是骗人点了才报错
		return ""
	if not build_mode:
		# 【触控模式为什么留空】桌面这行是「[B] 建造模式」的操作提示，
		# 但触控模式已经有左侧「建造」按钮，再显示一行纯文字只会盖在摇杆上
		# （HUD 顶部区在竖屏下正好压到摇杆命中圆）。
		return _hint("[B] 建造模式", "")
	var s := _hint("建造（1-4 选择）\n", "建造（点按钮选择）\n")
	for i in BUILD_ITEMS.size():
		var it: Dictionary = BUILD_ITEMS[i]
		var cost := ""
		for k in it.cost:
			cost += "%s%d " % [hud.RES_NAME[k], int(it.cost[k])]
		var mark := ">" if i == build_index else " "
		s += "%s%d. %s  %s\n" % [mark, i + 1, it.name, cost]
	return s


# ——————————————— 资源接口（农场模块依赖） ———————————————
func has_item(kind: String, n: int) -> bool:
	return int(inv.get(kind, 0)) >= n


func take_item(kind: String, n: int) -> bool:
	if not has_item(kind, n):
		return false
	inv[kind] = int(inv.get(kind, 0)) - n
	hud.set_resources(inv)
	return true


func give_item(kind: String, n: int) -> void:
	inv[kind] = int(inv.get(kind, 0)) + n
	hud.set_resources(inv)


# ——————————————— 存档契约 ———————————————
func serialize() -> Dictionary:
	var pp := player.global_position
	# 人在屋里时写门外那个点：室内坐标是飞地里的位置，
	# 读档时飞地还没建（是懒加载的），玩家会直接掉进虚空。
	if house_id != "":
		pp = outdoor_exit
	return {
		"inv": inv.duplicate(),
		"time": dn.time,
		"day": dn.day_count,
		"pos": [pp.x, pp.y, pp.z],
		# 室内存的是门外落点，不能把室内跳跃速度带到户外读档位置。
		"player_velocity": PhysicsPropS._vec(Vector3.ZERO if house_id != "" else player.velocity),
		"yaw": player.yaw,
		"pitch": player.pitch,
		"harvested": harvested_ids.duplicate(),
		"built": built_items.duplicate(),
		"weapon": player.weapon_idx,
		# 动物状态：只存"血量 + 是否已死"，位置不存——动物一直在动，存了也没意义，
		# 读档后从 home 重新游走即可。索引与 _spawn_critters 的生成顺序一一对应。
		"critters": _serialize_critters(),
		"physics_props": _serialize_props(),
	}


func _serialize_critters() -> Array:
	var out: Array = []
	for c in critters:
		if not is_instance_valid(c):
			out.append([0, false])
			continue
		var h := c as Huntable
		if h == null:
			out.append([0, false])
			continue
		out.append([h.hp, h.dead])
	return out


func _deserialize_critters(arr: Variant) -> void:
	if not (arr is Array):
		return
	var a: Array = arr
	for i in range(mini(a.size(), critters.size())):
		var c: Node3D = critters[i]
		if not is_instance_valid(c):
			continue
		var h := c as Huntable
		if h == null:
			continue
		var pair: Variant = a[i]
		if not (pair is Array) or (pair as Array).size() < 2:
			continue
		var pa: Array = pair
		if bool(pa[1]):
			# 存档时已死：直接置死，不播动画（respawn_delay 到点会自己重生）
			h.dead = true
			h.hp = 0
		else:
			h.dead = false
			h.hp = clampi(int(pa[0]), 1, h.max_hp)
		if h.has_node("AnimalCollision"):
			h.get_node("AnimalCollision").collision_layer = 0 if h.dead else 8


func deserialize(d: Dictionary) -> void:
	# 读档一律回到户外。存档不记室内状态（见 serialize），而保存可能是在屋里按的；
	# 这里同步送出门，不用等过场动画——读档本身就是一次跳变，再淡入淡出反而拖沓。
	if house_id != "":
		_apply_exit(true)

	var iv: Variant = d.get("inv", {})
	if iv is Dictionary:
		for k in (iv as Dictionary):
			inv[k] = int((iv as Dictionary)[k])
	hud.set_resources(inv)

	dn.day_count = int(d.get("day", 1))
	dn.time = float(d.get("time", 0.30))

	var p: Variant = d.get("pos", [0.0, 0.0, 0.0])
	if p is Array and (p as Array).size() >= 3:
		var pa: Array = p
		player.restore_motion(Vector3(float(pa[0]), float(pa[1]), float(pa[2])),
			PhysicsPropS._read_vec(d.get("player_velocity", [])))
		last_pos = player.global_position
	player.yaw = float(d.get("yaw", 0.0))
	player.pitch = float(d.get("pitch", -0.35))
	_restore_props(d.get("physics_props", null))

	# 回放已采集：世界是按固定随机种子重建的，按稳定 id 移除即可
	var hv: Variant = d.get("harvested", [])
	if hv is Array:
		harvested_ids = (hv as Array).duplicate()
		for n in resources.duplicate():
			if is_instance_valid(n) and harvested_ids.has(int(n.get_meta("rid", -1))):
				_collect_resource(n, true)

	# 重建玩家建造物：先清掉读档前放置的（避免孤儿节点），再按存档重建。
	# 帐篷同时占着 houses 里的一条，一并清掉，否则旧帐篷的入口会留在镇上。
	# 【按 built 而不是按 kind 过滤】镇上的帐篷营地 kind 也是 tent，
	# 按 kind 清会把它们一起删掉，而那些帐篷不会随存档重建——读档后营地就进不去了。
	houses = houses.filter(func(h): return not bool(h.get("built", false)))
	for c in get_children():
		if c is Node3D and c.has_meta("player_built"):
			for i in range(colliders.size() - 1, -1, -1):
				if colliders[i].node == c:
					colliders.remove_at(i)
					break
			c.queue_free()
	# 动画数组里可能引用了刚释放的节点，一并清理
	spins = spins.filter(func(e): return is_instance_valid(e.node))
	bobs = bobs.filter(func(e): return is_instance_valid(e.node))
	flickers = flickers.filter(func(e): return is_instance_valid(e.node))
	var bv: Variant = d.get("built", [])
	if bv is Array:
		built_items = (bv as Array).duplicate()
		for bi in built_items.size():
			var b: Variant = built_items[bi]
			if b is Dictionary:
				var bd: Dictionary = b
				var nb := _make_build(str(bd.get("kind", "campfire")))
				nb.set_meta("player_built", true)
				var bx := float(bd.get("x", 0.0))
				var bz := float(bd.get("z", 0.0))
				var brot := float(bd.get("rot", 0.0))
				_place(nb, bx, bz, brot)
				_register_house(str(bd.get("kind", "")), Vector2(bx, bz), brot, bi, "", true)
	dn.collect_night_lights(self)
	if season != null:
		_on_weather(str(season.weather))

	# 武器与动物状态
	player.weapon_idx = clampi(int(d.get("weapon", 0)), 0, WeaponsS.count() - 1)
	_deserialize_critters(d.get("critters", []))
	# 死亡时模型是侧翻的，读档直接置死的那些要补上倒地姿态
	for c in critters:
		if is_instance_valid(c):
			var h := c as Huntable
			if h != null and h.dead and h.model != null:
				h.model.rotation.z = 1.35
				h.model.position.y = -0.15


# ——————————————— 自动截图（--auto-shot） ———————————————
func _check_auto_shot() -> void:
	if not OS.get_cmdline_args().has("--auto-shot"):
		return
	var base := _shot_dir()

	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "shot1_morning.png")

	dn.time = 0.72
	player.yaw = 1.30
	player.pitch = -0.18
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "shot2_dusk_lake.png")

	dn.time = 0.02
	player.yaw = 0.35
	player.pitch = -0.42
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "shot3_night.png")

	# 雨天：验证雨幕 + 雾浓度 + 日照衰减的联动
	if season != null:
		season.weather = "rain"
		season._apply_now()
	_on_weather("rain")
	dn.time = 0.45
	player.yaw = 0.80
	player.pitch = -0.15
	await get_tree().create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "shot4_rain.png")

	get_tree().quit()


## 截图输出目录：默认项目根，可用 --shot-dir <路径> 覆盖
func _shot_dir() -> String:
	var args := OS.get_cmdline_args()
	var di: int = args.find("--shot-dir")
	if di >= 0 and di + 1 < args.size():
		var d := args[di + 1]
		if not d.ends_with("/") and not d.ends_with("\\"):
			d += "/"
		return d
	# 默认输出到项目根（不硬编码本机路径，便于仓库共享）
	var root := ProjectSettings.globalize_path("res://")
	if not root.ends_with("/"):
		root += "/"
	return root
