extends Node3D
class_name MenuWorld
## 主界面背景世界 —— 真实 3D 世界，随昼夜与天气动态变化
##
## 【为什么不用主场景】
## 直接复用 main.tscn 需要在「世界在跑但玩家不可控」这个状态上加一堆分支，
## 耦合太重。这里单独组一个精简世界：地形 + 光照 + 季节天气 + 环绕相机，
## 不建玩家、不建 HUD、不建存档系统、不建采集物。
##
## 承载方式是 SubViewport，与菜单 UI 完全解耦；切换场景靠 change_scene_to_file。

const TerrainS := preload("res://scripts/terrain.gd")
const DayNightS := preload("res://scripts/day_night.gd")
const SeasonS := preload("res://scripts/season.gd")
const FloraS := preload("res://scripts/flora.gd")
const PropsS := preload("res://scripts/props.gd")

const TOWN := Vector2(-14.0, -10.0)
const LAKE := Vector2(48.0, 22.0)

## 环绕半径（米）与高度。俯角要够大，否则远处会露出地形边缘的"切边"。
const ORBIT_R := 34.0
const ORBIT_H := 20.0
## 环绕角速度（弧度/秒），一整圈约 72 秒
const ORBIT_W := 0.087
## 注视点：小镇中心。相机从这个点向外绕，所以小镇始终在画面正中。
## y 在 _ready 里按实际地形高度补——地形基准高度调整过一次，
## 写死的 2.6 会变成"看向地面以下"，画面里只剩一片草皮。
var look_target := Vector3(-14.0, 2.6, -10.0)

var terrain: Node3D
var dn: DayNight
var season: SeasonManager
var cam: Camera3D
var _angle := 0.0
var _shake := 0.0

## 背景世界的地图种子。<= 0 表示"本次启动随机"。
## 背景每次都换一张图：它展示的正是"这个游戏的地图是随机生成的"。
## 和进游戏后那张图没有关系——那边由 main 单独掷种子。
var menu_seed := 0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	if menu_seed <= 0:
		rng.randomize()
		menu_seed = rng.randi_range(1, 2147483000)

	terrain = TerrainS.new()
	terrain.name = "MenuTerrain"
	terrain.set_map_seed(menu_seed)
	add_child(terrain)

	# 注视点落在小镇地面之上：高度必须问地形，不能写死
	look_target = Vector3(TOWN.x, float(terrain.height_at(TOWN.x, TOWN.y)) + 0.8, TOWN.y)

	# 只铺植被与少量建筑剪影，不铺可采集物（没有玩家去采）
	_scatter_decor()

	# 昼夜：把时间起点设成清晨，菜单一进来就是透亮的早上
	dn = DayNightS.new()
	dn.name = "MenuDayNight"
	add_child(dn)
	dn.setup(self)
	dn.time = 0.34
	dn.speed_scale = 1.0
	# 菜单里的时间走快一点：玩家在菜单停留几十秒就能看到天色变化
	dn.day_length = 96.0
	dn.collect_night_lights(self)

	# 季节天气：让背景有随机天气（雨/晴/热）
	season = SeasonS.new()
	season.name = "MenuSeason"
	add_child(season)
	season.setup(dn, terrain)

	# 环绕相机
	cam = Camera3D.new()
	cam.name = "MenuCam"
	cam.fov = 62.0
	cam.near = 0.1
	cam.far = 400.0
	add_child(cam)
	_update_cam(0.0)
	cam.current = true


func _scatter_decor() -> void:
	var rng := RandomNumberGenerator.new()
	# 跟地形同一个种子（加盐区分流），植被分布才能和这张地图对上
	rng.seed = menu_seed + 991

	# —— 植被（密度接近游戏内，让菜单画面够饱满）——
	_flora_pass(rng, 62, 28.0, 30.0, 4.0, "eucalyptus")
	_flora_pass(rng, 26, 26.0, 28.0, 3.2, "acacia")
	_flora_pass(rng, 38, 22.0, 27.0, 2.2, "bush")
	_flora_pass(rng, 20, 24.0, 27.0, 2.8, "rock")

	# —— 干草地被 ——
	for v in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = FloraS.grass_mesh(rng)
		mm.instance_count = 500
		for i in 500:
			var p := Vector2(rng.randf_range(-96.0, 96.0), rng.randf_range(-96.0, 96.0))
			var y: float = terrain.height_at(p.x, p.y)
			if y < 0.95 or p.distance_to(TOWN) < 12.0:
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

	# —— 小镇剪影：几间小屋 + 营火 + 路灯，撑起画面重心 ——
	for i in range(6):
		var a := float(i) / 6.0 * TAU
		var p := TOWN + Vector2(cos(a), sin(a)) * 11.5
		var y: float = terrain.height_at(p.x, p.y)
		var b: Node3D = PropsS.make_tent() if i % 2 == 0 else PropsS.make_lamp()
		b.position = Vector3(p.x, y, p.y)
		b.rotation.y = a + PI
		add_child(b)

	var cy: float = terrain.height_at(TOWN.x, TOWN.y)
	var fire: Node3D = PropsS.make_campfire()
	fire.position = Vector3(TOWN.x, cy, TOWN.y)
	add_child(fire)


func _flora_pass(rng: RandomNumberGenerator, count: int, min_town: float,
		min_lake: float, clear: float, kind: String) -> void:
	var placed: Array = []
	for i in count:
		var p := Vector2.ZERO
		var ok := false
		for t in 40:
			var c := Vector2(rng.randf_range(-96.0, 96.0), rng.randf_range(-96.0, 96.0))
			if c.distance_to(TOWN) < min_town or c.distance_to(LAKE) < min_lake:
				continue
			# 水里不撒：跟水位比，别跟绝对高度比（地形基准高度会变，见 terrain.BASE_LIFT）
			if terrain.water_depth_at(c.x, c.y) > 0.0:
				continue
			var clash := false
			for q in placed:
				if c.distance_to(q) < clear:
					clash = true
					break
			if clash:
				continue
			p = c
			ok = true
			break
		if not ok:
			continue
		placed.append(p)
		var node: Node3D
		match kind:
			"eucalyptus": node = FloraS.make_eucalyptus(rng, rng.randf_range(0.8, 1.25))
			"acacia": node = FloraS.make_acacia(rng, rng.randf_range(0.85, 1.2))
			"bush": node = FloraS.make_bush(rng, rng.randf_range(0.8, 1.3))
			"rock": node = FloraS.make_rock(rng, rng.randf_range(0.8, 1.4), false)
			_: node = FloraS.make_bush(rng, 1.0)
		node.position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
		node.rotation.y = rng.randf() * TAU
		add_child(node)


func _update_cam(dt: float) -> void:
	_angle += dt * ORBIT_W
	# 轻微呼吸感：让相机高度有极缓慢的起伏，避免画面完全死板
	_shake += dt
	var h := ORBIT_H + sin(_shake * 0.31) * 1.4
	var pos := Vector3(
		look_target.x + cos(_angle) * ORBIT_R,
		h,
		look_target.z + sin(_angle) * ORBIT_R
	)
	cam.position = pos
	cam.look_at(look_target + Vector3(0.0, 0.6, 0.0), Vector3.UP)


func _process(dt: float) -> void:
	if cam != null:
		_update_cam(dt)
