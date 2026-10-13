extends Node
## 真实门洞、连续走入走出、碰撞、相机、天气和室内存档；测试传送只用于摆放起始点。
const InteriorS := preload("res://scripts/interior.gd")
var m: Node3D
var checks := 0
var fails := 0
var max_step := 0.0

func _ready() -> void:
	m = load("res://scripts/main.gd").new()
	m.forced_map_seed = 20260921
	add_child(m)
	m.dn.speed_scale = 0
	await _frames(12)
	_ok(m.houses.size() == 7 and m.interior._spaces.size() == 7, "七栋建筑内部就地建立")
	for house in m.houses:
		await _walk_house(house)
	await _wall_and_save()
	await _built_tent()
	await _sleep()
	GameBus.touch_move = Vector2.ZERO
	GameBus.touch_run = false
	print("==== INTERIOR DONE checks=%d fails=%d max_step=%.4f ====" % [checks, fails, max_step])
	get_tree().quit(1 if fails else 0)

func _walk_house(house: Dictionary) -> void:
	var space: Dictionary = m.interior.space_of(str(house.id))
	var frame: Node3D = space.frame
	var spec: Dictionary = InteriorS.spec_of(str(house.kind))
	var floor_local := float(frame.get_meta("floor_height"))
	var outside := frame.to_global(Vector3(0, floor_local + 0.03, float(spec.door_z) + 1.45))
	m.player.restore_motion(outside)
	m.player.yaw = 0
	await _frames(15)
	m.interior.set_open(str(house.id), false)
	await _frames(20)
	_ok(m.house_id == "", str(house.id) + "门外状态")
	_ok(frame.get_meta("room_size").is_equal_approx(Vector3(float(spec.get("w", 5)), float(spec.h), float(spec.get("d", 5)))), str(house.id) + "内外尺寸一致")
	_ok(space.node.get_parent() == frame and space.node.position.x == 0 and space.node.position.z == 0, str(house.id) + "家具处于真实外壳内")
	var before: Vector3 = m.player.global_position
	m._interact()
	_ok(before.distance_to(m.player.global_position) < 0.001 and m.house_id == "" and not m.interior.busy, str(house.id) + "F只开门，不传送或黑屏")
	await _frames(20)
	_ok(absf(float(space.door.rotation.y) - InteriorS.DOOR_OPEN_ANGLE) < 0.02, str(house.id) + "真实门扇绕铰链开启")
	m.interior.set_open(str(house.id), false)
	await _frames(20)
	_ok(absf(float(space.door.rotation.y)) < 0.01, str(house.id) + "门可以关闭")
	var closed_test: Transform3D = m.player.global_transform
	closed_test.origin = frame.to_global(Vector3(0, floor_local + 0.03, float(spec.door_z) + 0.7))
	_ok(m.player.test_move(closed_test, frame.global_basis * Vector3(0, 0, -1.4)), str(house.id) + "关门时通道被真实门板阻挡")
	var leaf: AnimatableBody3D = space.door
	_ok(leaf.get_child(1) is CollisionShape3D, str(house.id) + "门扇有真实碰撞")
	var target := frame.to_global(Vector3(0, floor_local + 0.03, float(spec.door_z) - 1.5))
	await _walk_to(target, str(house.id) + "自动推门并实际进入", house.kind == "shop")
	await _frames(5)
	_ok(m.house_id == house.id and m.player.indoor and space.open, str(house.id) + "进入由实际位置触发")
	_ok(m.player.is_on_floor() and absf(m.player.global_position.y - float(space.floor_y)) < 0.12, str(house.id) + "真实地板支撑")
	_ok(not m.player.swimming and not m.player.camera_underwater(), str(house.id) + "室内不误判水域")
	_ok(not m.interior.busy and not m.interior._fade_layer.visible, str(house.id) + "进门无淡出过场")
	m.season.weather = "rain"
	m._on_weather("rain")
	_ok(not m.rain_particles.emitting, str(house.id) + "室内遮雨")
	_ok(not m.interior.set_open(str(house.id), false), str(house.id) + "门扇范围有人时不夹人")
	await _walk_to(outside, str(house.id) + "原路实际走出")
	await _frames(5)
	_ok(m.house_id == "" and not m.player.indoor, str(house.id) + "跨出门口回到户外")
	_ok(m.rain_particles.emitting, str(house.id) + "出门恢复雨幕")
	_ok(not m.interior.busy, str(house.id) + "出门无传送")
	m.season.weather = "clear"
	m._on_weather("clear")

func _wall_and_save() -> void:
	var space: Dictionary = m.interior.space_of("hut_0")
	var frame: Node3D = space.frame
	var floor_local := float(frame.get_meta("floor_height"))
	m.player.restore_motion(frame.to_global(Vector3(0, floor_local + 0.04, 0)))
	await _frames(12)
	_ok(m.house_id == "hut_0", "真实室内坐标可识别")
	m._do_action("build")
	_ok(not m.build_mode, "室内禁止建造")
	m.player.yaw = float(frame.rotation.y)
	GameBus.touch_move = Vector2(-1, 0)
	GameBus.touch_run = true
	await _frames(85)
	GameBus.touch_move = Vector2.ZERO
	GameBus.touch_run = false
	var local: Vector3 = frame.to_local(m.player.global_position)
	_ok(local.x > -3.45 and local.x < -2.6, "持续奔向侧墙由实体碰撞阻挡")
	m.player.restore_motion(frame.to_global(Vector3(0, floor_local + 0.04, 0)))
	await _frames(12)
	var pos: Vector3 = m.player.global_position
	var save: Dictionary = m.serialize()
	_ok(Vector3(save.pos[0], save.pos[1], save.pos[2]).distance_to(pos) < 0.001, "室内保存实际位置")
	m.interior.set_open("hut_0", true)
	save = m.serialize()
	m.deserialize(save)
	_ok(m.player.global_position.distance_to(pos) < 0.001 and m.house_id == "hut_0", "室内读档保留位置与环境")
	_ok(m.interior.space_of("hut_0").open, "门状态随存档恢复")
	# restore_motion 会清空接地缓存；先实际落地，再验证按键起跳，不能在读档同帧注入跳跃。
	await _frames(12)
	GameBus.touch_jump_edge = true
	await _frames(10)
	_ok(m.player.global_position.y > float(space.floor_y) + 0.2, "室内跳跃使用真实物理")
	var airborne: Dictionary = m.serialize()
	_ok(absf(float(airborne.player_velocity[1])) > 0.1, "室内存档保留实际跳跃速度")
	await _frames(70)
	_ok(m.player.is_on_floor(), "室内跳跃后落回地板")
	m.player.cam_dist = 22
	for yaw in [0.0, 1.57, 3.14, 4.71]:
		m.player.yaw = float(frame.rotation.y) + float(yaw)
		await _frames(20)
		_ok(m.player.cam.position.z < 4.1, "室内相机自动收近")
		var ray := PhysicsRayQueryParameters3D.create(m.player.cam_pitch.global_position, m.player.cam.global_position, 16)
		_ok(m.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "相机与角色之间没有建筑遮挡")
	var legacy := save.duplicate(true)
	legacy.erase("doors")
	legacy.pos = [-35.0, m.terrain.height_at(-35, -13) + 0.1, -13.0]
	m.deserialize(legacy)
	_ok(m.house_id == "" and not m.interior.space_of("hut_0").open, "旧存档无门字段仍可读取")

func _built_tent() -> void:
	var point: Vector2 = m._random_spot(45, 45, 6)
	var tent: Node3D = m._make_build("tent")
	tent.set_meta("player_built", true)
	m._place(tent, point.x, point.y, 0.4)
	m.built_items.append({"kind": "tent", "x": point.x, "z": point.y, "rot": 0.4})
	var id: String = m._register_house("tent", point, 0.4, m.built_items.size() - 1, "", true)
	_ok(id != "tent_camp_0" and m.interior.space_of(id).frame == tent, "自建帐篷有独立真实室内")
	await _walk_house(m.houses[-1])
	var total: int = m.houses.size()
	var save: Dictionary = m.serialize()
	m.deserialize(save)
	await _frames(10)
	_ok(m.houses.size() == total and m.interior._spaces.size() == total, "读档重建不遗留旧室内")
	_ok(not m.interior.space_of("tent_camp_0").is_empty(), "读档保留场景自带营地")
	await _walk_house(m.houses[-1])

func _sleep() -> void:
	var space: Dictionary = m.interior.space_of("hut_0")
	var frame: Node3D = space.frame
	var local: Vector3 = frame.to_local(space.bed)
	m.player.restore_motion(frame.to_global(local + Vector3(1.25, 0.03, 0)))
	await _frames(12)
	_ok(m._bed_near(), "真实房间里仍可在床边睡觉")
	m._interact()
	_ok(m.sleep_panel.is_open() and get_tree().paused, "床边交互打开睡觉面板")
	m.sleep_panel.close()
	_ok(not get_tree().paused, "关闭睡觉面板解除暂停")
	m.dn.time = 22.0 / 24.0
	var day: int = m.dn.day_count
	var before: Vector3 = m.player.global_position
	m._apply_sleep(6.0)
	_ok(m.dn.day_count == day + 1 and absf(m.dn.time * 24 - 6) < 0.01, "睡觉推进到次日清晨")
	_ok(m.player.global_position.distance_to(before) < 0.001, "睡觉不改变真实房间位置")

func _walk_to(target: Vector3, label: String, run := false) -> void:
	m.player.yaw = 0
	GameBus.touch_run = run
	for i in 360:
		var position: Vector3 = m.player.global_position
		var offset := Vector2(target.x - position.x, target.z - position.z)
		if offset.length() < 0.12: break
		GameBus.touch_move = offset.normalized()
		await get_tree().physics_frame
		var after: Vector3 = m.player.global_position
		var step := Vector2(after.x - position.x, after.z - position.z).length()
		max_step = maxf(max_step, step)
		if step > 0.18:
			_ok(false, "行走发生不连续位移 %.3f" % step)
			break
	GameBus.touch_move = Vector2.ZERO
	GameBus.touch_run = false
	var distance := Vector2(target.x - m.player.global_position.x, target.z - m.player.global_position.z).length()
	_ok(distance < 0.16, label + " 剩余距离 %.3f" % distance)

func _frames(count: int) -> void:
	for i in count: await get_tree().physics_frame
func _ok(ok: bool, label: String) -> void:
	checks += 1
	if not ok: fails += 1
	print(("PASS " if ok else "FAIL ") + label)
