extends Node2D
## 跳跃姿态截图 —— 起跳滞空那一下的手臂与腿是什么样
##
## 用法（必须窗口模式，headless 下 frame_post_draw 不发会卡死）：
##   Godot --path <项目> --scene res://tools/jump_shot.tscn -- --size 1600x900 --dir res://jump_shots/
##
## 【为什么要专门拍它】跳跃姿态只在滞空的零点几秒里出现，手点不出来，
## 而它恰恰是最容易改坏的地方（曾经把双臂拧到身前，看起来像在推门）。

var m: Node3D
var dir := "res://jump_shots/"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var size := _arg_pair(args, "--size")
	dir = _arg_str(args, "--dir", "res://jump_shots/")
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

	m.dn.time = 0.35
	m.dn.speed_scale = 0.0
	# 找个空旷平地：镇外的干草地，镜头里不会全是建筑
	m.player.global_position = Vector3(30.0, m.terrain.height_at(30.0, -30.0) + 0.1, -30.0)
	await _frames(6)

	# 侧后方机位：能同时看清手臂和腿的摆向（正后方只看得到背包）
	m.player.yaw = 2.3
	m.player.pitch = -0.08
	await get_tree().create_timer(0.8).timeout
	await _save("jump0_ground.png")

	# 使用真实跳跃输入；jump_v 现在只记录结果，直接赋值不会驱动角色移动。
	GameBus.touch_jump_edge = true
	# 等姿态权重到位（_air_pose 的时间常数约 0.08 秒）再拍，否则拍到过渡中间帧
	await get_tree().create_timer(0.22).timeout
	print("air pose: y=%.2f on_ground=%s jump_h=%.2f"
		% [m.player.global_position.y, str(m.player.on_ground), m.player.jump_h])
	await _save("jump1_air.png")

	# 落地前一瞬：确认落地后能干净地回到走路/待机姿态
	await get_tree().create_timer(0.55).timeout
	await _frames(4)
	await _save("jump2_landed.png")

	print("==== JUMP SHOT DONE ====")
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


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
