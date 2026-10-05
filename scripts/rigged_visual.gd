extends RefCounted
## 美术适配层只驱动骨骼，不接管角色坐标、碰撞、战斗或存档。
var root: Node3D
var skeleton: Skeleton3D
var animation: AnimationPlayer
var current := ""

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
	for name in ["Idle", "Walk", "Run", "Gallop"]:
		if animation.has_animation(name):
			animation.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	play("Idle", 0.0)
	animation.advance(0)
	return true

func play(name: String, blend := 0.12, speed := 1.0) -> void:
	if animation == null or not animation.has_animation(name):
		return
	if name != current:
		animation.play(name, blend)
		current = name
	animation.speed_scale = speed

func update_player(player: Node3D, dt: float, moving: bool, running: bool) -> void:
	if root == null:
		return
	if player.swimming:
		play("Idle", 0.12)
	elif player.swing_t >= 0.0:
		play("Sword_Slash", 0.06, animation.get_animation("Sword_Slash").length / player.swing_dur)
	elif not player.on_ground:
		play("Idle", 0.12)
	else:
		play("Run" if running and moving else ("Walk" if moving else "Idle"))
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
