extends Node
## 固定步长的行为测试；必须在独立 user:// 的验证副本中运行。
## Godot --headless --path <副本> --fixed-fps 60 res://tools/physics_check.tscn

var m: Node3D
var checks := 0
var fails := 0


func _ready() -> void:
	var MS = load("res://scripts/main.gd")
	m = MS.new()
	m.forced_map_seed = 20260921
	add_child(m)
	await _wait(0.8)
	await _run()
	print("==== PHYSICS CHECK DONE checks=%d fails=%d ====" % [checks, fails])
	get_tree().quit(1 if fails else 0)


func _ok(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		fails += 1
	print(("PASS " if condition else "FAIL ") + message)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false, true).timeout
	# physics_frame 在节点积分之前发出，再等 process_frame 读最终结果。
	await get_tree().process_frame


func _teleport(pos: Vector3) -> void:
	m.player.velocity = Vector3.ZERO
	m.player.global_position = pos
	GameBus.touch_move = Vector2.ZERO
	GameBus.touch_dive = false


func _box_at(pos: Vector3, size: Vector3) -> Node3D:
	var props = load("res://scripts/props.gd")
	var collision = load("res://scripts/world_collision.gd")
	var root := Node3D.new()
	root.add_child(props._box(size, props.mat(Color.WHITE), Vector3(0, size.y * 0.5, 0)))
	root.position = pos
	collision.attach(root)
	m.add_child(root)
	return root


func _run() -> void:
	var p = m.player
	var t = m.terrain
	var spawn := Vector3(-14, float(t.height_at(-14, 7)), 7)
	_teleport(spawn + Vector3.UP * 3.0)
	await _wait(0.9)
	_ok(p.is_on_floor() and absf(p.global_position.y - spawn.y) < 0.08,
		"从空中落地，脚底与渲染地面一致")
	GameBus.touch_jump_edge = true
	await _wait(0.22)
	_ok(not p.is_on_floor() and p.global_position.y > spawn.y + 0.7, "跳跃真正离开地面")
	await _wait(1.0)
	_ok(p.is_on_floor(), "跳跃后重新落地")

	var wall := _box_at(Vector3(-14, spawn.y, 10), Vector3(3, 2, 0.4))
	_teleport(Vector3(-14, spawn.y + 0.04, 12))
	await _wait(0.2)
	GameBus.touch_move = Vector2(0, -1)
	await _wait(0.9)
	_ok(p.global_position.z > 10.5 and p.global_position.z < 10.8, "向墙持续走动，被实体墙阻挡")
	GameBus.touch_move = Vector2.ZERO
	wall.queue_free()
	await _wait(0.1)
	var step := _box_at(Vector3(-14, spawn.y, 16), Vector3(2.5, 0.18, 3.0))
	_teleport(Vector3(-14, spawn.y + 0.04, 13.8))
	await _wait(0.2)
	GameBus.touch_move = Vector2(0, 1)
	await _wait(0.5)
	GameBus.touch_move = Vector2.ZERO
	_ok(p.global_position.z > 15.0 and p.global_position.y > spawn.y + 0.15,
		"步行跨上18厘米台阶，无需跳跃 pos=%s" % p.global_position)
	step.queue_free()
	await _wait(0.1)

	var dock: Node3D = m.get_node("Dock")
	var dock_pt := dock.global_position + Vector3(0, 0.99, -12.7)
	var approach_z := dock.global_position.z + 4.5
	_teleport(Vector3(dock.global_position.x, float(t.height_at(dock.global_position.x, approach_z)) + 0.04, approach_z))
	await _wait(0.2)
	GameBus.touch_move = Vector2(0, -1)
	var dry_crossing := true
	for i in 90:
		await _wait(0.05)
		dry_crossing = dry_crossing and not p.swimming
		if p.global_position.z < dock.global_position.z - 12.0:
			break
	GameBus.touch_move = Vector2.ZERO
	_ok(dry_crossing and p.global_position.z < dock.global_position.z - 10.0,
		"从岸上沿坡道走到码头尽头，板缝不会触发游泳 pos=%s" % p.global_position)
	_teleport(dock_pt)
	await _wait(0.6)
	_ok(p.is_on_floor() and not p.swimming and absf(p.global_position.y - dock_pt.y) < 0.06,
		"深水上方的码头可站立，不误判为游泳")
	# 从码头横向走出，而不是直接传送到水里。
	GameBus.touch_move = Vector2(1, 0)
	await _wait(1.4)
	GameBus.touch_move = Vector2.ZERO
	await _wait(1.2)
	_ok(p.swimming and p.global_position.y < 0.0, "从码头边缘走入水，进入游泳")
	GameBus.touch_dive = true
	await _wait(1.0)
	_ok(p.diving and p.head_underwater(), "碰撞启用后仍能下潜")
	GameBus.touch_dive = false

	var crate: RigidBody3D
	var log_body: RigidBody3D
	for body in m.physics_props:
		if body.kind == "crate" and crate == null:
			crate = body
		if body.kind == "log":
			log_body = body
	var initial := crate.global_position
	_teleport(initial + Vector3(-1.35, -0.46, 0))
	await _wait(0.3)
	GameBus.touch_move = Vector2(1, 0)
	await _wait(1.2)
	GameBus.touch_move = Vector2.ZERO
	_ok(crate.global_position.x > initial.x + 0.35,
		"角色接触推动木箱产生真实位移 crate=%s player=%s" % [crate.global_position, p.global_position])
	_ok(crate.global_position.y > spawn.y + 0.3, "木箱保持在地表，没有穿地")
	await _wait(3.0)
	_ok(log_body.global_position.y > -0.4 and log_body.global_position.y < 0.35,
		"木段稳定漂浮在水面附近，未沉入湖底")
	log_body.apply_central_impulse(Vector3.DOWN * 12.0)
	await _wait(0.3)
	_ok(log_body.global_position.y < 0.0, "冲量能把漂木压入水中")
	await _wait(3.0)
	_ok(log_body.global_position.y > -0.3, "受扰动后漂木自动上浮")

	var saved: Array = m._serialize_props()
	var saved_crate: Dictionary = saved[0]
	crate.global_position += Vector3(8, 2, 0)
	m._restore_props(JSON.parse_string(JSON.stringify(saved)))
	await _wait(0.04)
	var restored: Array = m._serialize_props()
	var restored_pos := Vector3(float(restored[0].pos[0]), float(restored[0].pos[1]), float(restored[0].pos[2]))
	var expected := Vector3(float(saved_crate.pos[0]), float(saved_crate.pos[1]), float(saved_crate.pos[2]))
	_ok(restored.size() == saved.size() and restored_pos.distance_to(expected) < 0.12,
		"经过JSON存档往返，道具数量和木箱位置恢复")
	var old_count: int = m.physics_props.size()
	m._restore_props(null)
	_ok(m.physics_props.size() == old_count, "旧存档缺少道具字段时保留初始道具")
	# 在空中存档，直接检查重新建立的刚体是否恢复了旋转和运动，而非只恢复位置。
	var moving: RigidBody3D = m._spawn_prop("crate", Vector3(-35, 15, 5))
	moving.rotation = Vector3(0.2, 0.5, 0.1)
	moving.linear_velocity = Vector3(2, -1, 0.6)
	moving.angular_velocity = Vector3(0.1, 0.3, 0.2)
	var motion_data: Dictionary = moving.serialize()
	var replacement: RigidBody3D = m._spawn_prop("crate", Vector3(-35, 15, 5))
	moving.freeze = true
	moving.collision_layer = 0
	moving.collision_mask = 0
	moving.queue_free()
	replacement.restore(JSON.parse_string(JSON.stringify(motion_data)))
	await _wait(0.04)
	_ok(replacement.linear_velocity.x > 1.7 and replacement.angular_velocity.y > 0.2,
		"空中道具读档后恢复线速度和角速度")
	_ok(replacement.global_rotation.distance_to(Vector3(0.2, 0.5, 0.1)) < 0.1,
		"空中道具读档后恢复旋转")
	var char_pos := Vector3(-40, 13, -10)
	p.restore_motion(char_pos, Vector3(1, -2, 0))
	await _wait(0.04)
	_ok(p.velocity.y < -2.0 and p.global_position.y < char_pos.y,
		"空中角色恢复运动状态后继续下落")

	var wood: ShaderMaterial = load("res://scripts/props.gd").surface("wood", Color(0.54, 0.38, 0.25))
	_ok(wood.get_shader_parameter("detail_map") != null and wood.get_shader_parameter("normal_map") != null,
		"木材有颜色和法线纹理")
	var shape_before = t.ground_body.get_node("Shape").shape
	t.apply_season_tint(Color(1, 0.8, 0.4), 0.4)
	_ok(t.ground_body.get_node("Shape").shape == shape_before, "季节染色不重建物理地形")
	t.set_weather("rain")
	await _wait(1.0)
	_ok(t.wetness > 0.1, "雨天逐渐润湿地表材质")
	var preview: Node3D = m._make_build("tent")
	_ok(not preview.has_node("Solid"), "建造预览没有实体碰撞")
	preview.free()
