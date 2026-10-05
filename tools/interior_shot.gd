extends Node2D
## 进屋流程截图 —— 门前提示 / 小屋室内 / 杂货铺室内 / 夜间室内
##
## 用法（必须窗口模式，headless 下 frame_post_draw 不发会卡死）：
##   Godot --path <项目> --scene res://tools/interior_shot.tscn -- --size 1600x900 --dir res://interior_shots/

const InteriorS := preload("res://scripts/interior.gd")

var m: Node3D
var dir := "res://interior_shots/"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var size := _arg_pair(args, "--size")
	dir = _arg_str(args, "--dir", "res://interior_shots/")
	# 先建目录：save_png 对不存在的目录是【静默失败】的，不报错也不落文件
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if size != Vector2i.ZERO:
		get_window().size = size
		get_viewport().size = size

	var MS = load("res://scripts/main.gd")
	m = MS.new()
	m.forced_map_seed = 20260921
	add_child(m)
	for i in 15:
		await get_tree().process_frame

	# 白天、停住时间：截图之间别让太阳跑掉
	m.dn.time = 0.42
	m.dn.speed_scale = 0.0

	await _shot_door()
	await _shot_hut()
	await _shot_shop()
	await _shot_camp()
	await _shot_sleep()
	await _shot_night()

	print("==== INTERIOR SHOT DONE ====")
	get_tree().quit(0)


## 1) 站在小屋门口：验证交互提示确实出现，并且门朝着广场
func _shot_door() -> void:
	# 按类型找，不要按 houses 的下标：登记顺序是"先杂货铺、后三间小屋"，
	# 写死下标会把小屋拍成铺子。
	var h: Dictionary = _house_of("hut")
	var kind := str(h.get("kind", "hut"))
	var pos: Vector2 = h.get("pos", Vector2.ZERO)
	var rot := float(h.get("rot", 0.0))
	var ep := InteriorS.exit_point(pos, rot, kind)

	# 站在门外，转身面对屋子：yaw 使相机看向 -Z…这里用模型的标准公式反推，
	# aim_dir = (-sin(yaw), -cos(yaw))，要让它指向屋子中心
	var to := pos - ep
	m.player.global_position = Vector3(ep.x, m.terrain.height_at(ep.x, ep.y) + 0.1, ep.y)
	m.player.yaw = atan2(-to.x, -to.y)
	m.player.pitch = -0.16
	await get_tree().create_timer(0.9).timeout
	print("door prompt = %s" % m.hud.prompt_label.text)
	await _save("interior0_door.png")


## 2) 进小屋：白天的室内采光
func _shot_hut() -> void:
	await _enter(_house_of("hut"))
	print("hut indoor=%s pos=%s" % [str(m.player.indoor), str(m.player.global_position)])
	await get_tree().create_timer(1.0).timeout
	await _save("interior1_hut_day.png")

	# 俯视角度再拍一张：平视会贴脸穿过家具（炉灶烟囱高过玩家，相机很容易撞上），
	# 俯视能把整个布局看清。
	m.player.yaw = 0.0
	m.player.pitch = -0.55
	await get_tree().create_timer(0.8).timeout
	await _save("interior2_hut_overlook.png")
	await _leave()


## 3) 杂货铺：空间与货架
func _shot_shop() -> void:
	await _enter(_house_of("shop"))
	await get_tree().create_timer(1.0).timeout
	await _save("interior3_shop.png")
	m.player.yaw = 2.2
	await get_tree().create_timer(0.8).timeout
	await _save("interior4_shop_shelf.png")
	await _leave()


## 3.5) 镇上的帐篷营地：门要朝镇中心（不再随机转），里面是圆形帐篷内饰
func _shot_camp() -> void:
	var h: Dictionary = _house_of("tent")
	if h.is_empty():
		print("WARN 没找到营地帐篷")
		return
	var kind := str(h.get("kind", "tent"))
	var pos: Vector2 = h.get("pos", Vector2.ZERO)
	var rot := float(h.get("rot", 0.0))
	var ep := InteriorS.exit_point(pos, rot, kind)

	var to := pos - ep
	m.player.global_position = Vector3(ep.x, m.terrain.height_at(ep.x, ep.y) + 0.1, ep.y)
	m.player.yaw = atan2(-to.x, -to.y)
	m.player.pitch = -0.14
	await get_tree().create_timer(0.9).timeout
	print("camp door prompt = %s" % m.hud.prompt_label.text)
	await _save("interior6_camp_door.png")

	await _enter(h)
	await get_tree().create_timer(1.0).timeout
	await _save("interior7_camp_inside.png")
	await _leave()


## 3.8) 睡觉：床边的提示 + 起床时刻面板
func _shot_sleep() -> void:
	var h: Dictionary = _house_of("hut")
	await _enter(h)
	var sp: Dictionary = m.interior.space_of(str(h.get("id", "")))
	var bed: Vector3 = sp.get("bed", Vector3.ZERO)
	if bed == Vector3.ZERO:
		print("WARN 小屋没有床")
		await _leave()
		return

	# 站到床边并转身面向床
	var px := bed.x + 1.4
	var pz := bed.z
	m.player.global_position = Vector3(px, m.player.global_position.y, pz)
	m.player.yaw = atan2(-(bed.x - px), -(bed.z - pz))
	m.player.pitch = -0.24
	await get_tree().create_timer(0.8).timeout
	print("bed prompt = %s" % m.hud.prompt_label.text)
	await _save("interior8_bed_prompt.png")

	m._interact()                       # 打开睡觉面板（会暂停游戏）
	await get_tree().create_timer(0.6).timeout
	print("sleep panel open = %s" % str(m.sleep_panel.is_open()))
	await _save("interior9_sleep_panel.png")

	m.sleep_panel.close()
	await get_tree().create_timer(0.3).timeout
	await _leave()


## 4) 夜里再进一次小屋：室内灯必须昼夜都亮
func _shot_night() -> void:
	m.dn.time = 0.93
	m.dn._update(0.0)
	await _enter(_house_of("hut"))
	await get_tree().create_timer(1.0).timeout
	await _save("interior5_hut_night.png")
	await _leave()


# ——————————————— 工具 ———————————————
func _house_of(kind: String) -> Dictionary:
	for h in m.houses:
		var hd: Dictionary = h
		if str(hd.get("kind", "")) == kind:
			return hd
	return {}


func _enter(h: Dictionary) -> void:
	var kind := str(h.get("kind", "hut"))
	var pos: Vector2 = h.get("pos", Vector2.ZERO)
	var rot := float(h.get("rot", 0.0))
	var ep := InteriorS.exit_point(pos, rot, kind)
	m.player.global_position = Vector3(ep.x, m.terrain.height_at(ep.x, ep.y) + 0.1, ep.y)
	await get_tree().process_frame
	m._interact()
	await _wait_warp()


func _leave() -> void:
	m._interact()
	await _wait_warp()


## 过场是有时长的（0.44 秒），按真实时间等它走完再拍，
## 否则拍到的是黑场中间那一帧。
func _wait_warp() -> void:
	for i in 80:
		await get_tree().create_timer(0.05).timeout
		if not m.interior.busy:
			return


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + name)
	print("saved " + name)


func _arg_str(args: PackedStringArray, key: String, def: String) -> String:
	var i: int = args.find(key)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return def


func _arg_pair(args: PackedStringArray, key: String) -> Vector2i:
	var s := _arg_str(args, key, "")
	if s == "":
		return Vector2i.ZERO
	var parts := s.split("x")
	if parts.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))
