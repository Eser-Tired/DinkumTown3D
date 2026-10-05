extends Node
## 遍历所有骨骼与完整步态周期，专门防止停步残留、速度错配和顶墙原地跑复发。
const Rig := preload("res://scripts/rigged_visual.gd")
var checks := 0
var fails := 0

class FlatGround extends Node3D:
	func height_at(_x: float, _z: float) -> float: return 0.0
	func water_depth_at(_x: float, _z: float) -> float: return 0.0
	func water_level() -> float: return -10.0

func _ok(value: bool, label: String) -> void:
	checks += 1
	fails += int(not value)
	print(("PASS " if value else "FAIL ") + label)

func _ready() -> void:
	for kind in ["Adventurer", "Deer", "Stag", "Fox"]:
		var parent := Node3D.new()
		var rig := Rig.new()
		rig.attach(parent, "res://assets/" + ("characters/" if kind == "Adventurer" else "animals/") + kind + ".scn", 1.82 if kind == "Adventurer" else (1.65 if kind == "Deer" else (2.0 if kind == "Stag" else 0.82)))
		var expected_speed: float = {"Adventurer": 1.38994, "Deer": 0.96984, "Stag": 0.93422, "Fox": 0.83855}[kind]
		_ok(not parent.is_inside_tree() and absf(float(rig.gait_speeds["Walk"]) - expected_speed) < 0.002, kind + "进场景树前步速与完整姿态实测一致")
		add_child(parent)
		print("GAIT ", kind, " ", rig.gait_speeds)
		var complete := true
		for name in rig.animation.get_animation_list():
			var clip := rig.animation.get_animation(name)
			var channels := {}
			for t in clip.get_track_count():
				channels[str(clip.track_get_path(t)) + ":" + str(clip.track_get_type(t))] = true
			complete = complete and channels.size() >= rig.skeleton.get_bone_count() * 3
		_ok(complete, kind + "全部动画覆盖每根骨骼的局部TRS")
		var baseline := _pose(rig)
		for action in (["Walk", "Run", "Sword_Slash", "Walk"] if kind == "Adventurer" else ["Walk", "Gallop", "Death", "Walk"]):
			rig.play(action, 0.0)
			rig.animation.advance(rig.animation.get_animation(action).length * 0.37)
			rig.play(rig.idle_name, 0.12)
			# 待机整周期结束并超过混合时间；不能只检查初始化的正常姿态。
			for i in 240:
				rig.animation.advance(1.0 / 60.0)
			var max_position := 0.0
			var feet_stable := true
			for b in rig.skeleton.get_bone_count():
				var bn := rig.skeleton.get_bone_name(b)
				if bn.contains("Foot") or bn.begins_with("IK"):
					var drift: float = rig.skeleton.get_bone_pose_position(b).distance_to(baseline[b].origin)
					max_position = maxf(max_position, drift)
					feet_stable = feet_stable and drift < 0.0001
			print("RESTORE ",kind," after=",action," foot_drift=",max_position)
			_ok(feet_stable, kind + "从" + action + "恢复待机不残留脚位")
		for name in rig.gait_speeds:
			var speed: float = rig.gait_speeds[name]
			_ok(speed > 0.5 and speed < 6.0, kind + name + "测量完整周期得到有效自然步速")
			var clip: Animation = rig.animation.get_animation(name)
			var closed := true
			for t in clip.get_track_count():
				var a = clip.track_get_key_value(t, 0)
				var b = clip.track_get_key_value(t, clip.track_get_key_count(t) - 1)
				closed = closed and a.is_equal_approx(b)
			_ok(closed, kind + name + "首尾轨道闭合，不在循环边界跳脚")
			rig.locomote(name, speed * 1.4)
			var before := rig.animation.current_animation_position
			rig.animation.advance(0.1)
			var distance: float = fposmod(rig.animation.current_animation_position - before, rig.animation.current_animation_length)
			_ok(absf(distance - 0.14) < 0.0001, kind + name + "实际播放进度随移动速度改变")
		parent.free()
	await _movement()
	print("==== MOTION CHECK DONE checks=%d fails=%d ====" % [checks, fails])
	get_tree().quit(1 if fails else 0)

func _pose(rig: RefCounted) -> Array:
	var result := []
	for b in rig.skeleton.get_bone_count():
		result.append(rig.skeleton.get_bone_pose(b))
	return result

func _box(size: Vector3, position: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	body.position = position
	add_child(body)

func _movement() -> void:
	var ground := FlatGround.new()
	add_child(ground)
	_box(Vector3(30, 0.2, 30), Vector3(0, -0.1, 0))
	_box(Vector3(6, 4, 0.4), Vector3(0, 2, 3))
	var player: CharacterBody3D = load("res://scripts/player.gd").new()
	add_child(player)
	player.setup(ground, [], Vector2.ZERO)
	for i in 20: await get_tree().physics_frame
	_ok(player.rig.current == "Idle_Neutral" and player.is_on_floor(), "真实物理帧启动后自然站立")
	GameBus.touch_move = Vector2(0, 1)
	for i in 20: await get_tree().physics_frame
	_ok(player.rig.current in ["Walk", "Run"], "实际行走驱动骨骼动作")
	for i in 240: await get_tree().physics_frame
	_ok(player.rig.current == "Idle_Neutral" and player.position.z < 2.5, "持续顶墙输入仍恢复待机，不原地跑")
	GameBus.touch_move = Vector2.ZERO
	player.set_physics_process(false)
	player.on_ground = true
	player.swimming = true
	player.model.get_node("ArmR").rotation.x = 1.2
	for i in 60: player.rig.update_player(player, 1.0 / 60, false, false, 0.0)
	player.swimming = false
	for i in 90: player.rig.update_player(player, 1.0 / 60, false, false, 0.0)
	var arm: int = player.rig.skeleton.find_bone("UpperArm.R")
	var expected: Quaternion = player.rig.animation.get_animation("Idle_Neutral").rotation_track_interpolate(_arm_track(player.rig, arm), player.rig.animation.current_animation_position)
	_ok(player.rig.skeleton.get_bone_pose_rotation(arm).angle_to(expected) < 0.001, "游泳后骨骼不会累积划水旋转")
	for kind in ["Deer", "Stag", "Fox"]:
		var animal: Node3D = load("res://scripts/wildlife.gd").new()
		animal.species = kind
		animal.small = kind == "Fox"
		add_child(animal)
		animal.setup(ground, Vector2(-6, -6), player)
		animal.set_process(false)
		player.position = Vector3(100, 0, 100)
		animal.target = Vector2(6, -6)
		animal.timer = 20
		animal.rotation.y = 0
		var sideways := 0.0
		for i in 60:
			var before := animal.position
			animal._process(1.0 / 60)
			var delta := animal.position - before
			if delta.length() > 0.0001:
				sideways = maxf(sideways, absf(delta.normalized().dot(animal.basis.x)))
		_ok(sideways < 0.001, kind + "转弯时位移沿身体前方，不横向滑行")
		animal.target = Vector2(animal.position.x, animal.position.z)
		animal._process(1.0 / 60)
		_ok(animal.rig.current == "Idle", kind + "到达目标立即待机")
		animal.free()
	player.free()
	ground.free()

func _arm_track(rig: RefCounted, arm: int) -> int:
	var clip: Animation = rig.animation.get_animation("Idle_Neutral")
	for t in clip.get_track_count():
		if clip.track_get_type(t) == Animation.TYPE_ROTATION_3D and str(clip.track_get_path(t)).ends_with(":" + rig.skeleton.get_bone_name(arm)):
			return t
	return -1
