extends RefCounted
## 美术适配层只驱动骨骼，不接管角色坐标、碰撞、战斗或存档。
var root: Node3D
var skeleton: Skeleton3D
var animation: AnimationPlayer
var current := ""
var gait_speeds := {}
var idle_name := "Idle"
static var _gait_cache := {}

func attach(parent: Node3D, path: String, height: float, yaw: float = 0.0) -> bool:
	if OS.get_cmdline_user_args().has("--no-characters") or not ResourceLoader.exists(path):
		return false
	root = load(path).instantiate()
	var bounds: AABB = root.get_meta("source_bounds")
	var factor := height / bounds.size.y
	root.scale = Vector3.ONE * factor
	root.position.y = -bounds.position.y * factor
	root.rotation.y = yaw
	parent.add_child(root)
	skeleton = root.find_children("*", "Skeleton3D", true, false)[0]
	animation = root.find_children("*", "AnimationPlayer", true, false)[0]
	# 每个实例复制动画资源：循环/速度调整不能污染共享的 PackedScene。
	for library_name in animation.get_animation_library_list():
		var library := animation.get_animation_library(library_name).duplicate(true)
		animation.remove_animation_library(library_name)
		animation.add_animation_library(library_name, library)
	# glTF 省略恒定轨道；待机没有脚的位置轨道，Godot 会保留上一个 Walk 的脚位。
	# 给每段动画补全骨骼局部 TRS，才能在停步、攻击和游泳结束后恢复完整姿态。
	_complete_tracks()
	idle_name = "Idle_Neutral" if animation.has_animation("Idle_Neutral") else "Idle"
	for name in ["Idle", "Idle_Neutral", "Walk", "Run", "Gallop"]:
		if animation.has_animation(name):
			var clip := animation.get_animation(name)
			clip.loop_mode = Animation.LOOP_LINEAR
			# Run 最后一帧未闭合，直接循环会让脚踝每圈跳一下；在末尾补首帧作连续插值。
			for t in clip.get_track_count():
				if clip.track_get_key_count(t) > 1:
					clip.track_insert_key(t, clip.length, clip.track_get_key_value(t, 0))
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for name in ["Walk", "Run", "Gallop"]:
		if animation.has_animation(name):
			var key: String = path + ":" + str(height) + ":" + name
			if not _gait_cache.has(key):
				_gait_cache[key] = _measure_gait(name)
			gait_speeds[name] = _gait_cache[key]
	play(idle_name, 0.0)
	_sample_pose(animation.get_animation(idle_name), 0.0)
	animation.advance(0)
	return true

func _complete_tracks() -> void:
	for name in animation.get_animation_list():
		var clip := animation.get_animation(name)
		var existing := {}
		var prefix := ""
		for t in clip.get_track_count():
			var path := clip.track_get_path(t)
			if path.get_subname_count() == 1:
				prefix = str(path).get_slice(":", 0)
				existing[str(path) + ":" + str(clip.track_get_type(t))] = true
		if prefix.is_empty():
			continue
		for b in skeleton.get_bone_count():
			var path := NodePath(prefix + ":" + skeleton.get_bone_name(b))
			var rest := skeleton.get_bone_rest(b)
			for type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
				if existing.has(str(path) + ":" + str(type)):
					continue
				var t := clip.add_track(type)
				clip.track_set_path(t, path)
				if type == Animation.TYPE_POSITION_3D:
					clip.position_track_insert_key(t, 0.0, rest.origin)
				elif type == Animation.TYPE_ROTATION_3D:
					clip.rotation_track_insert_key(t, 0.0, rest.basis.get_rotation_quaternion())
				else:
					clip.scale_track_insert_key(t, 0.0, rest.basis.get_scale())

func _measure_gait(name: String) -> float:
	# 完整周期四只脚逐帧采样，取近地且向后移动的支撑段；不拿摆腿跨度猜步速。
	var feet: Array[int] = []
	for b in skeleton.get_bone_count():
		var bn := skeleton.get_bone_name(b)
		if bn in ["Foot.L", "Foot.R", "IKFrontLeg.L", "IKFrontLeg.R", "IKBackLeg.L", "IKBackLeg.R"]:
			feet.append(b)
	var clip := animation.get_animation(name)
	var samples := []
	var lowest := {}
	for i in 121:
		# 动物 setup 在 add_child 之前调用，AnimationPlayer 离树时 seek 不会写骨骼。
		# 从原轨道直接采样局部姿态，测量不能依赖节点是否已进场景树。
		_sample_pose(clip, clip.length * i / 120.0)
		var points := []
		for b in feet:
			# Skeleton 的全局缓存也在离树时不更新；沿父骨骼链累乘局部姿态才是有效采样。
			var transform := skeleton.get_bone_pose(b)
			var parent := skeleton.get_bone_parent(b)
			while parent >= 0:
				transform = skeleton.get_bone_pose(parent) * transform
				parent = skeleton.get_bone_parent(parent)
			var point := transform.origin * root.scale.x
			points.append(point)
			lowest[b] = minf(float(lowest.get(b, INF)), point.y)
		samples.append(points)
	var speeds: Array[float] = []
	var dt := clip.length / 120.0
	for i in range(1, 120):
		for j in feet.size():
			var p: Vector3 = samples[i][j]
			var previous: Vector3 = samples[i-1][j]
			var v := (p - previous) / dt
			if p.y < float(lowest[feet[j]]) + 0.035 and absf(v.y) < 0.25 and v.z < -0.1:
				speeds.append(-v.z)
	if speeds.is_empty():
		push_error("缺少支撑段步速样本：" + name)
		return 1.0
	speeds.sort()
	return speeds[speeds.size() / 2]

func _sample_pose(clip: Animation, time: float) -> void:
	for t in clip.get_track_count():
		var path := clip.track_get_path(t)
		if path.get_subname_count() != 1: continue
		var b := skeleton.find_bone(path.get_subname(0))
		if b < 0: continue
		match clip.track_get_type(t):
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(b, clip.position_track_interpolate(t, time))
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(b, clip.rotation_track_interpolate(t, time))
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(b, clip.scale_track_interpolate(t, time))

func play(name: String, blend := 0.12, speed := 1.0) -> void:
	if animation == null or not animation.has_animation(name):
		return
	if name != current:
		animation.play(name, blend)
		current = name
	animation.speed_scale = speed

func locomote(name: String, speed: float) -> void:
	var phase := 0.0
	var preserve := current in gait_speeds and name in gait_speeds and current != name
	if preserve:
		phase = animation.current_animation_position / animation.current_animation_length
	play(name, 0.12, speed / float(gait_speeds[name]))
	if preserve:
		animation.seek(phase * animation.get_animation(name).length)

func update_player(player: Node3D, dt: float, moving: bool, running: bool, actual_speed := -1.0) -> void:
	if root == null:
		return
	if player.swimming:
		play(idle_name, 0.12)
	elif player.swing_t >= 0.0:
		play("Sword_Slash", 0.06, animation.get_animation("Sword_Slash").length / player.swing_dur)
	elif not player.on_ground:
		play(idle_name, 0.12)
	else:
		var speed: float = (player.run_speed if running else player.walk_speed) if actual_speed < 0.0 and moving else maxf(0.0, actual_speed)
		if speed > 0.08:
			locomote("Run" if running or speed > float(gait_speeds["Walk"]) * 1.8 else "Walk", speed)
		else:
			play(idle_name)
	animation.advance(dt)
	# 包里没有游泳/跳跃，按已验证的原程序化姿态混到实际骨骼上。
	# 先播基础动画再加局部姿态，否则下一个动画帧会把划水覆盖掉。
	if player.swimming or player._air_pose > 0.001:
		for pair in [["UpperArm.L", "ArmL"], ["UpperArm.R", "ArmR"], ["UpperLeg.L", "LegL"], ["UpperLeg.R", "LegR"]]:
			var bone := skeleton.find_bone(pair[0])
			var proxy: Node3D = player.model.get_node(pair[1])
			var local_axis := skeleton.get_bone_global_rest(bone).basis.inverse() * Vector3.RIGHT
			var angle: float = proxy.rotation.x
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * Quaternion(local_axis.normalized(), angle))
