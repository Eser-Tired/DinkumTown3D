extends Node2D
## 水域专项截图 —— 俯视全湖 + 贴水面看岸线 + 玩家入水
##
## 用法（必须窗口模式，headless 下 frame_post_draw 不发会卡死）：
##   Godot --path <项目> res://tools/water_shot.tscn -- --size 1600x900 --dir res://water_shots/

var m: Node3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var size := _arg_pair(args, "--size")
	var dir := _arg_str(args, "--dir", "res://water_shots/")
	# 先建目录：save_png 对不存在的目录是【静默失败】的——不报错也不落文件，
	# 之前踩过一次，一大截截图凭空消失。
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if size != Vector2i.ZERO:
		get_window().size = size
		get_viewport().size = size

	var seed_val := int(_arg_str(args, "--seed", "20260921"))
	var MS = load("res://scripts/main.gd")
	m = MS.new()
	# 固定种子，截图才可复现（换 --seed 就能拍另一张地图做对比）
	m.forced_map_seed = seed_val
	add_child(m)
	for i in 12:
		await get_tree().process_frame

	var TS = load("res://scripts/terrain.gd")
	var lake: Vector2 = TS.LAKE_C
	print("SEED=%d LAKE_C=%s water_y=%s 河道折点=%d" % [
		seed_val, str(lake), str(TS.WATER_Y), m.terrain.river_pts.size()])

	# —— 0) 高空俯瞰：河与湖的全局关系 ——
	var ov := Camera3D.new()
	ov.fov = 62.0
	ov.far = 700.0
	add_child(ov)
	ov.global_position = Vector3(6.0, 300.0, 60.0)
	ov.look_at(Vector3(6.0, 0.0, 16.0), Vector3.UP)
	ov.make_current()
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "water0_overview.png")
	ov.queue_free()

	# —— 1) 俯视全湖：看水域覆盖到底连不连续 ——
	var top := Camera3D.new()
	top.fov = 62.0
	top.far = 400.0
	add_child(top)
	top.global_position = Vector3(lake.x, 96.0, lake.y + 46.0)
	top.look_at(Vector3(lake.x, 0.0, lake.y), Vector3.UP)
	top.make_current()
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "water1_lake_top.png")

	# —— 2) 更低、更斜：看岸线是不是一刀切 / 有没有被地形切断 ——
	top.global_position = Vector3(lake.x - 52.0, 26.0, lake.y + 62.0)
	top.look_at(Vector3(lake.x, -1.0, lake.y), Vector3.UP)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "water2_shore.png")

	# —— 3) 游泳：玩家漂在湖面 ——
	top.queue_free()
	m.player.pitch = -0.36
	m.player.cam_dist = 11.0
	m.player.global_position = Vector3(lake.x - 4.0, float(TS.WATER_Y) + 4.0, lake.y + 6.0)
	# 漂浮是插值趋近，要给足收敛时间，否则会拍到还在下沉的中间态
	await get_tree().create_timer(2.2).timeout
	await RenderingServer.frame_post_draw
	var py: float = m.player.global_position.y
	var gy: float = m.terrain.height_at(m.player.global_position.x, m.player.global_position.z)
	print("SWIM y=%.2f  ground=%.2f  swimming=%s  breath=%.2f" % [
		py, gy, str(m.player.swimming), m.player.breath])
	get_viewport().get_texture().get_image().save_png(dir + "water3_swim.png")

	# —— 4) 潜水：按住「潜」沉下去，应看到水下遮罩 ——
	GameBus.touch_dive = true
	await get_tree().create_timer(1.8).timeout
	await RenderingServer.frame_post_draw
	print("DIVE y=%.2f  diving=%s  head_uw=%s  cam_uw=%s  breath=%.2f" % [
		m.player.global_position.y, str(m.player.diving),
		str(m.player.head_underwater()), str(m.player.camera_underwater()), m.player.breath])
	get_viewport().get_texture().get_image().save_png(dir + "water4_dive.png")
	GameBus.touch_dive = false

	# —— 5) 岸上回望：水面与岸线的关系 ——
	# 站在湖的【北】岸：河从南边来，站北岸才不会站在河里
	await get_tree().create_timer(1.6).timeout
	m.player.global_position = Vector3(lake.x - 8.0, float(TS.WATER_Y) + 6.0, lake.y - 44.0)
	m.player.pitch = -0.22
	m.player.cam_dist = 16.0
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "water5_from_shore.png")

	# —— 6) 河流特写：河道中段的俯视 ——
	var rp: PackedVector2Array = m.terrain.river_pts
	if rp.size() >= 2:
		var mid: Vector2 = rp[rp.size() / 2]
		m.player.global_position = Vector3(mid.x, float(TS.WATER_Y) + 14.0, mid.y)
		m.player.pitch = -0.85
		m.player.cam_dist = 22.0
		await get_tree().create_timer(1.6).timeout
		await RenderingServer.frame_post_draw
		print("RIVER mid=(%.0f,%.0f) depth=%.2f" % [
			mid.x, mid.y, m.terrain.water_depth_at(mid.x, mid.y)])
		get_viewport().get_texture().get_image().save_png(dir + "water6_river.png")

	# —— 剖面诊断：从湖心向外找"水位穿越半径"（= 岸线在哪）——
	# 如果某个方位的岸线半径 > LAKE_R+SHORE，说明水面会顶到扫描范围的硬边上。
	var rim := float(TS.LAKE_R) + float(TS.SHORE)
	var beyond := 0
	var rep := "岸线半径(deg:r) "
	for k in 24:
		var a := TAU * float(k) / 24.0
		var r := 0.0
		var found := -1.0
		while r < 120.0:
			var px := lake.x + cos(a) * r
			var pz := lake.y + sin(a) * r
			if m.terrain.height_at(px, pz) > float(TS.WATER_Y):
				found = r
				break
			r += 0.5
		if found < 0.0 or found > rim:
			beyond += 1
		rep += "%d:%.0f " % [int(round(rad_to_deg(a))), found]
	print(rep)
	print("PROFILE 湖盆外缘 r=%.0f；岸线超出湖盆的方位数 = %d / 24" % [rim, beyond])

	# 湖心到岸线的深度剖面（正东方向），用来看湖盆剖面是否单调
	var prof := "DEPTH(东向) "
	var rr := 0.0
	while rr <= 50.0:
		prof += "%.0f:%.1f " % [rr, float(TS.WATER_Y) - m.terrain.height_at(lake.x + rr, lake.y)]
		rr += 2.5
	print(prof)

	get_tree().quit()


func _arg_str(args: PackedStringArray, key: String, def: String) -> String:
	var i: int = args.find(key)
	if i < 0 or i + 1 >= args.size():
		return def
	return args[i + 1]


func _arg_pair(args: PackedStringArray, key: String) -> Vector2i:
	var s := _arg_str(args, key, "")
	if s == "":
		return Vector2i.ZERO
	var parts: PackedStringArray = s.split("x")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))
