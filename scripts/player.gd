extends CharacterBody3D
## 第三人称角色：WASD 移动 / 右键拖拽转视角 / 滚轮缩放 / 空格跳跃
## 胶囊碰撞 + 固定步长移动；水深只负责游泳状态，不覆盖地面碰撞。

const M := preload("res://scripts/props.gd")

var terrain: Node3D
var obstacles: Array = []          # 保留 setup 契约；实体碰撞由引擎处理。

var yaw := 0.0
var pitch := -0.35
var cam_dist := 9.0

# 模型实测自然步速 1.39 / 3.12 m/s；1.8 / 5.2 留适度加速，避免旧速度下四倍快放走路。
var walk_speed := 1.8
var run_speed := 5.2
var jump_v := 0.0
var jump_h := 0.0
var on_ground := true
var walk_phase := 0.0
## 空中姿态权重 0..1：起跳/落地各留约 0.1 秒过渡，避免四肢瞬变
var _air_pose := 0.0
var _last_physics_pos := Vector3.ZERO
var _jump_was_pressed := false
var _motion_restored := false
const STEP_HEIGHT := 0.28

# —— 水域 ——
## 水深超过 SWIM_MIN 就进入游泳：玩家身高约 1.8，水过腰再走就不合理了
const SWIM_MIN := 1.15
## 漂浮时身体没入水面的深度。身体还会前倾（见 _process 的 model.rotation.x），
## 所以实际露出水面的比这个数字看起来更少——0.80 是"看得见头和肩"的手感值。
const FLOAT_SUBMERGE := 0.80
const DIVE_MAX := 7.5           ## 最大下潜深度（米）
const BREATH_MAX := 22.0        ## 一口气能憋多少秒
const HEAD_H := 1.70            ## 头顶高度，用来判断"头是否没入水中"
const SWIM_SPEED_MUL := 0.58    ## 游泳时的移动速度倍率
const WADE_SPEED_MUL := 0.78    ## 浅水趟水的速度倍率

var swim_depth := 0.0           ## 脚下水深（米），0 表示没水
var swimming := false           ## 是否处于游泳状态
var diving := false             ## 是否正在下潜
var breath := 1.0               ## 剩余憋气 0..1
var _water_level := 0.0         ## 水面高度（由 terrain 提供）

# —— 室内（飞地）模式 ——
## 进屋后玩家被传送到远离地图的室内空间（见 interior.gd）。那里既没有地形也没有水，
## 所以"贴地"和"是不是水"这两件事必须整体换数据源：继续问 terrain.height_at
## 会被户外地形高度硬拉回地表，玩家会站在半空中或者直接掉回小镇。
var indoor := false
var floor_y := 0.0              ## 室内地板高度（世界 y）
var bounds_center := Vector2.ZERO   ## 室内可行走矩形中心（xz）
var bounds_half := Vector2(112.0, 112.0)   ## 半宽 / 半深
## 第三人称在屋里必须拉近：默认 9 米的机位直接穿到墙外，屏幕上一半是墙背面。
## 上限 4.0 留给玩家用滚轮微调；进屋默认值 2.8 是"屋子宽 ~6 米时相机仍在墙内"算出来的。
const INDOOR_CAM_MAX := 4.0
const INDOOR_CAM_ENTER := 2.8
var _cam_dist_outdoor := 9.0

var cam_yaw: Node3D
var cam_pitch: Node3D
var cam: Camera3D
var model: Node3D
var rig := preload("res://scripts/rigged_visual.gd").new()

# —— 战斗（近战）——
const WeaponsS := preload("res://scripts/weapons.gd")
var weapon_idx := 0                # 当前武器在 WeaponsS.LIST 中的下标
var attack_cd := 0.0               # 剩余冷却
var swing_t := -1.0                # 挥砍动画进度（<0 表示未在挥）
var swing_dur := 0.30


func _ready() -> void:
	collision_layer = 2
	collision_mask = 13
	floor_snap_length = 0.32
	floor_max_angle = deg_to_rad(48.0)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	model = Node3D.new()
	model.name = "Model"
	add_child(model)

	cam_yaw = Node3D.new()
	cam_yaw.name = "CamYaw"
	add_child(cam_yaw)
	cam_pitch = Node3D.new()
	cam_pitch.name = "CamPitch"
	cam_yaw.add_child(cam_pitch)
	cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0.0, 0.0, cam_dist)
	cam_pitch.add_child(cam)

	_build_model()
	if rig.attach(model, "res://assets/characters/Adventurer.scn", 1.82):
		for child in model.get_children():
			if child != rig.root:
				_hide_native_meshes(child)

func _hide_native_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		node.layers = 0
	for child in node.get_children():
		_hide_native_meshes(child)


func setup(terr: Node3D, obs: Array, spawn2: Vector2) -> void:
	terrain = terr
	obstacles = obs
	global_position = Vector3(spawn2.x, terr.height_at(spawn2.x, spawn2.y) + 0.1, spawn2.y)
	_last_physics_pos = global_position
	if terr != null and terr.has_method("water_level"):
		_water_level = float(terr.water_level())
	# 开局让身体朝向与相机一致。否则 model.rotation.y 停在 0，
	# 而相机在局部 +Z 侧朝 -Z 看，玩家一开局就是"背对相机站着"，
	# 建造预览会直接落在身后。朝向 = 相机朝向（aim_dir），即 yaw + PI。
	model.rotation.y = yaw + PI


## 传送进室内：切换地面参考、可行走矩形，并拉近镜头。
## cols 保留原接口；家具避让已由室内实体碰撞负责。
func enter_indoor(fy: float, center: Vector2, half: Vector2, cols: Array) -> void:
	indoor = true
	floor_y = fy
	bounds_center = center
	bounds_half = half
	obstacles = cols
	_cam_dist_outdoor = cam_dist
	cam_dist = minf(cam_dist, INDOOR_CAM_ENTER)
	# 水里进屋（虽然目前没有水上的屋子）不该带着游泳/下潜状态进屋
	swimming = false
	diving = false
	swim_depth = 0.0
	jump_h = 0.0
	jump_v = 0.0
	on_ground = true
	restore_motion(global_position)


## 回到户外：还原地形贴地、世界边界与镜头距离
func exit_indoor(cols: Array) -> void:
	indoor = false
	obstacles = cols
	cam_dist = _cam_dist_outdoor
	swim_depth = 0.0
	swimming = false
	diving = false
	jump_h = 0.0
	jump_v = 0.0
	on_ground = true
	restore_motion(global_position)


func _mi(mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	return mi


func _build_model() -> void:
	var root := model
	var skin := M.mat(Color(0.85, 0.66, 0.50))
	var shirt := M.mat(Color(0.30, 0.52, 0.62))
	var pants := M.mat(Color(0.36, 0.36, 0.40))
	var hat_m := M.mat(Color(0.55, 0.40, 0.26))
	var boot := M.mat(Color(0.28, 0.22, 0.18))

	# 躯干
	var torso := CapsuleMesh.new()
	torso.radius = 0.28
	torso.height = 0.72
	torso.radial_segments = 8
	torso.rings = 4
	root.add_child(_mi(torso, shirt, Vector3(0, 1.06, 0)))

	# 背包
	root.add_child(_mi(BoxMesh.new(), M.mat(Color(0.45, 0.35, 0.24)),
		Vector3(0, 1.10, 0.30), Vector3.ZERO, Vector3(0.46, 0.52, 0.26)))

	# 头 + 宽檐帽（Akubra）
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.62, 0)
	var sk := SphereMesh.new()
	sk.radius = 0.21
	sk.height = 0.42
	sk.radial_segments = 8
	sk.rings = 5
	head.add_child(_mi(sk, skin))
	var brim := CylinderMesh.new()
	brim.top_radius = 0.44
	brim.bottom_radius = 0.46
	brim.height = 0.06
	brim.radial_segments = 12
	head.add_child(_mi(brim, hat_m, Vector3(0, 0.16, 0)))
	var crown := CylinderMesh.new()
	crown.top_radius = 0.23
	crown.bottom_radius = 0.26
	crown.height = 0.22
	crown.radial_segments = 10
	head.add_child(_mi(crown, hat_m, Vector3(0, 0.28, 0)))
	root.add_child(head)

	# 手臂
	for s in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "Arm%s" % ("L" if s < 0 else "R")
		arm.position = Vector3(s * 0.33, 1.36, 0)
		var b := BoxMesh.new()
		b.size = Vector3(0.14, 0.52, 0.14)
		arm.add_child(_mi(b, skin, Vector3(0, -0.26, 0)))
		root.add_child(arm)

	# 腿
	for s in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "Leg%s" % ("L" if s < 0 else "R")
		leg.position = Vector3(s * 0.15, 0.78, 0)
		var b := BoxMesh.new()
		b.size = Vector3(0.17, 0.62, 0.17)
		leg.add_child(_mi(b, pants, Vector3(0, -0.31, 0)))
		leg.add_child(_mi(BoxMesh.new(), boot, Vector3(0, -0.64, 0.03), Vector3.ZERO, Vector3(0.20, 0.14, 0.28)))
		root.add_child(leg)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.0055
		pitch = clampf(pitch - event.relative.y * 0.004, -1.15, 0.55)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = maxf(3.5, cam_dist - 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = minf(22.0, cam_dist + 0.9)
			# 屋里再往后拉就穿墙了，上限压住（室外不生效）
			if indoor:
				cam_dist = minf(cam_dist, INDOOR_CAM_MAX)


func _physics_process(dt: float) -> void:
	if terrain == null:
		return
	# —— 触控：视角拖拽 / 双指缩放（读后清零，桌面恒为零值，无副作用）——
	if GameBus.touch_look != Vector2.ZERO:
		yaw -= GameBus.touch_look.x * 0.0055
		pitch = clampf(pitch - GameBus.touch_look.y * 0.004, -1.15, 0.55)
		GameBus.touch_look = Vector2.ZERO
	if GameBus.touch_zoom != 0.0:
		cam_dist = clampf(cam_dist + GameBus.touch_zoom, 3.5, 22.0)
		GameBus.touch_zoom = 0.0

	cam_yaw.rotation.y = yaw
	cam_pitch.rotation.x = pitch
	cam.position.z = lerpf(cam.position.z, cam_dist, 0.15)

	# —— 输入 ——
	var ix := 0.0
	var iz := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): iz -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): iz += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): ix -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): ix += 1.0
	var tv := GameBus.touch_move
	if tv.length() > 0.02:
		ix += tv.x
		iz += tv.y
	ix = clampf(ix, -1.0, 1.0)
	iz = clampf(iz, -1.0, 1.0)
	var running := Input.is_key_pressed(KEY_SHIFT) or GameBus.touch_run
	var dir := Vector3(ix, 0.0, iz)
	if dir.length() > 0.01:
		dir = dir.normalized().rotated(Vector3.UP, yaw)

	# —— 下潜与憋气 ——
	# 松手 / 气用完 / 上岸，三种情况都要退出下潜，所以直接算成一行。
	var want_dive := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C) \
		or GameBus.touch_dive
	diving = swimming and want_dive and breath > 0.0
	# 只有头真的埋进水里才耗气：漂在水面上（哪怕在游泳）不消耗。
	# 气耗尽不扣血（游戏没有生命值系统），只是不能再往下，会自己浮回水面。
	if head_underwater():
		breath = maxf(0.0, breath - dt / BREATH_MAX)
	else:
		# 出水回气更快，不至于让玩家在岸边干等
		breath = minf(1.0, breath + dt / (BREATH_MAX * 0.32))

	# 外部读档/测试传送后清掉旧速度，防止把传送前的落体速度带到新位置。
	if global_position.distance_to(_last_physics_pos) > 2.0:
		velocity = Vector3.ZERO
		_motion_restored = true
	# 室内位于地图之外，地面参考和边界仍用室内规格，移动统一走实体碰撞。
	var gy: float = floor_y if indoor else terrain.height_at(global_position.x, global_position.z)
	swim_depth = 0.0 if indoor else _water_depth(global_position.x, global_position.z)
	swimming = swim_depth > SWIM_MIN and not _dry_support()
	diving = swimming and want_dive and breath > 0.0
	# 老存档可能在地形以下；只修正陆地上的非法位置。
	if not swimming and global_position.y < gy - 0.35:
		global_position.y = gy + 0.04
		velocity.y = 0.0

	var speed := run_speed if running else walk_speed
	if swimming:
		speed *= SWIM_SPEED_MUL
	elif swim_depth > 0.06 and global_position.y < _water_level + 0.2:
		speed *= WADE_SPEED_MUL
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	var jump_pressed := Input.is_key_pressed(KEY_SPACE)
	var want_jump := (jump_pressed and not _jump_was_pressed) or GameBus.touch_jump_edge
	_jump_was_pressed = jump_pressed
	GameBus.touch_jump_edge = false
	if swimming:
		motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		var target := _water_level - FLOAT_SUBMERGE
		if diving:
			target = maxf(_water_level - DIVE_MAX, gy + 0.55)
		velocity.y = clampf((target - global_position.y) * (4.6 if diving else 3.0), -6.0, 6.0)
	else:
		motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
		if is_on_floor() and not _motion_restored:
			velocity.y = 7.4 if want_jump else 0.0
		else:
			velocity.y -= 21.0 * dt
		if is_on_floor() and not _motion_restored and velocity.y <= 0.0 and dir.length() > 0.01:
			_try_step(dir * speed * dt)
	_push_props(dt)
	var motion_origin := global_position
	move_and_slide()
	_motion_restored = false
	if indoor:
		global_position.x = clampf(global_position.x, bounds_center.x - bounds_half.x, bounds_center.x + bounds_half.x)
		global_position.z = clampf(global_position.z, bounds_center.y - bounds_half.y, bounds_center.y + bounds_half.y)
	else:
		global_position.x = clampf(global_position.x, -112.0, 112.0)
		global_position.z = clampf(global_position.z, -112.0, 112.0)
	on_ground = is_on_floor() and not swimming
	jump_v = velocity.y
	jump_h = maxf(0.0, global_position.y - gy) if not swimming else 0.0
	_last_physics_pos = global_position
	# —— 朝向与程序化动画 ——
	if dir.length() > 0.01:
		var target_yaw := atan2(dir.x, dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 0.22)

	var la := model.get_node_or_null("LegL")
	var lb := model.get_node_or_null("LegR")
	var aa := model.get_node_or_null("ArmL")
	var ab := model.get_node_or_null("ArmR")

	if swimming:
		# —— 游泳：手臂大幅划水、腿小幅打水，身体前倾（下潜时更趴）——
		# 节拍不跟速度走：水里划水的节奏由人决定，不是由移动快慢决定
		walk_phase += dt * 5.4
		var s := sin(walk_phase)
		if aa:
			aa.rotation.x = -s * 1.55
		if ab:
			ab.rotation.x = s * 1.55
		if la:
			la.rotation.x = s * 0.42
		if lb:
			lb.rotation.x = -s * 0.42
		# 本游戏人物朝 +Z；绕 X 的正角才让头朝 +Z 前倾。负号会让新骨骼像仰泳。
		# 0.5 rad ≈ 29°（漂着划水），0.95 rad ≈ 54°（下潜时几乎趴平）。
		# 角度太小会像"站在水里"，太大又会变成游泳运动员那种水平姿态，低多边形角色撑不住。
		model.rotation.x = lerpf(model.rotation.x, 0.95 if diving else 0.5, 0.09)
	else:
		model.rotation.x = lerpf(model.rotation.x, 0.0, 0.15)
		if dir.length() > 0.01:
			walk_phase += dt * (10.0 if running else 7.0)
		else:
			walk_phase = lerpf(walk_phase, 0.0, 0.12)
		var swing := sin(walk_phase) * 0.55 * clampf(dir.length(), 0.0, 1.0)
		if la:
			la.rotation.x = swing
			lb.rotation.x = -swing
			aa.rotation.x = -swing * 0.75
			ab.rotation.x = swing * 0.75

	var head := model.get_node_or_null("Head")
	if head:
		head.rotation.z = sin(walk_phase * 0.5) * 0.03
		head.position.y = 1.62 + abs(sin(walk_phase)) * 0.02

	# —— 空中姿态：收腿 + 手臂向后下方摆 ——
	# 【必须排除游泳】游泳时 on_ground 恒为 false，不加这个判断的话
	# 上面的划水动作会被空中姿态覆盖掉，水里看起来像在蹬腿。
	#
	# 【为什么不再举双手】旧版把双臂硬拧到 -1.1 rad，手臂末端正好落到模型 +Z 侧
	# （也就是身前），跳起来像在推门/投降。现在改成：腿向前收起（跳跃的"提膝"），
	# 手臂自然后摆一点，落点更像在跳而不是在够东西。
	#
	# 【为什么用权重而不是直接赋值】硬切会在起跳和落地各闪一下。
	# 这里把"空中姿态"当成一个 0→1 的权重去混地面姿态，两个方向各约 0.1 秒过渡。
	# 注意这段必须在走路/游泳姿态【之后】执行，否则会被它们覆盖。
	model.position.y = 0.0
	var want_air := 0.0 if (on_ground or swimming) else 1.0
	_air_pose = lerpf(_air_pose, want_air, clampf(dt * 12.0, 0.0, 1.0))
	if _air_pose > 0.001:
		if la:
			la.rotation.x = lerpf(la.rotation.x, -0.55, _air_pose)
		if lb:
			lb.rotation.x = lerpf(lb.rotation.x, -0.28, _air_pose)
		if aa:
			aa.rotation.x = lerpf(aa.rotation.x, 0.42, _air_pose)
		if ab:
			ab.rotation.x = lerpf(ab.rotation.x, 0.42, _air_pose)

	# —— 战斗冷却与挥砍动画 ——
	_update_combat(dt)
	# 按碰撞之后的真实位移驱动步态，顶着墙按 W 时必须待机，不能原地跑。
	var movement := global_position - motion_origin
	var actual_speed := Vector2(movement.x, movement.z).length() / maxf(dt, 0.0001)
	rig.update_player(self, dt, actual_speed > 0.08, running, actual_speed)


func _dry_support() -> bool:
	if global_position.y < _water_level + 0.15:
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.12,
		global_position - Vector3.UP * 0.38, 5)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.normal.y > 0.6 and hit.position.y > _water_level + 0.15


func _try_step(motion: Vector3) -> void:
	# 只对真正的低台阶抬脚：先确认平移受阻，再验证上方净空和落脚面。
	if not test_move(global_transform, motion):
		return
	var raised := global_transform
	if test_move(raised, Vector3.UP * STEP_HEIGHT):
		return
	raised.origin.y += STEP_HEIGHT
	if test_move(raised, motion):
		return
	var forward := raised.origin + motion + motion.normalized() * 0.38
	var query := PhysicsRayQueryParameters3D.create(forward,
		forward - Vector3.UP * (STEP_HEIGHT + 0.06), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < cos(floor_max_angle):
		return
	var rise: float = hit.position.y - global_position.y
	if rise > 0.015 and rise <= STEP_HEIGHT:
		global_position.y += rise + 0.015


func _push_props(dt: float) -> void:
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	if horizontal.length() < 0.1:
		return
	var collision := KinematicCollision3D.new()
	if not test_move(global_transform, horizontal.normalized() * 0.12, collision):
		return
	var body := collision.get_collider() as RigidBody3D
	if body != null:
		var normal := -collision.get_normal()
		normal.y = 0.0
		if normal.length() > 0.01:
			# 9kg 木箱的静摩擦约53N；自然步速降低后仍需至少72N，不能让慢走失去推动能力。
			body.apply_central_impulse(normal.normalized() * clampf(horizontal.length(), 3.0, 6.0) * dt * 24.0)


func restore_motion(pos: Vector3, saved_velocity := Vector3.ZERO) -> void:
	global_position = pos
	velocity = saved_velocity
	_last_physics_pos = pos
	jump_v = saved_velocity.y
	_jump_was_pressed = Input.is_key_pressed(KEY_SPACE)
	# move_and_slide 的贴地状态仍属于传送前一帧，恢复时必须重新检测。
	_motion_restored = true


# ——————————————— 战斗 ———————————————
## 返回当前武器数据（空字典表示无武器）
func weapon() -> Dictionary:
	return WeaponsS.get_at(weapon_idx)


func weapon_name() -> String:
	return WeaponsS.name_of(str(weapon().get("id", "")))


## 当前武器的稳定 id（用于物品栏反查高亮格）
func weapon_id() -> String:
	return str(weapon().get("id", ""))


## 切到下一把武器，返回新武器名
func cycle_weapon(dir := 1) -> String:
	weapon_idx = WeaponsS.cycle(weapon_idx, dir)
	GameBus.tool_changed.emit(weapon_name())
	# 换武器时立刻打断挥砍，避免动画串味
	swing_t = -1.0
	return weapon_name()


## 能否出手（冷却好了）
func can_attack() -> bool:
	return attack_cd <= 0.0


## 发起一次挥砍。返回本次使用的武器数据（冷却未好时返回空字典）。
func start_attack() -> Dictionary:
	if attack_cd > 0.0:
		return {}
	var w := weapon()
	if w.is_empty():
		return {}
	attack_cd = float(w.get("cd", 0.5))
	swing_t = 0.0
	GameBus.tool_used.emit(weapon_name(), global_position)
	return w


# ——————————————— 水域 ———————————————
## 脚下水深（米）。terrain 没提供就当没有水，老测试场景不会炸。
func _water_depth(x: float, z: float) -> float:
	if terrain == null or not terrain.has_method("water_depth_at"):
		return 0.0
	return float(terrain.water_depth_at(x, z))


## 头是否已经没入水面 —— 憋气与水下视野都以它为准。
## 用"头"而不是"脚"：脚进水但头在外面时玩家还在呼吸，不该开始扣气。
func head_underwater() -> bool:
	return swimming and (global_position.y + HEAD_H) < _water_level


## 相机是否在水面以下（HUD 的水下遮罩用）。
## 与 head_underwater 分开：下潜时相机先入水、头后入水，两者不是一回事。
func camera_underwater() -> bool:
	if cam == null:
		return false
	return cam.global_position.y < _water_level


## 玩家朝向的水平前方单位向量（模型朝向，不是相机朝向）
func facing() -> Vector3:
	var y := model.rotation.y if model != null else yaw
	return Vector3(sin(y), 0.0, cos(y))


## 相机朝向的水平前方单位向量 —— "玩家看着哪"。
##
## 【为什么攻击/建造都以它为准，而不是 facing()】
## facing() 读的是 model.rotation.y，那个值有两个问题：
##   1. 它是被移动方向驱动的（W 键 → 局部 -Z），玩家站着不动时它永远停在
##      上一次移动的朝向，甚至在开局时还是 0（正对相机，方向全反）。
##   2. 它是插值跟随的（lerp 0.22），转身时明显滞后。
## 而相机朝向由鼠标右键 / 触屏拖动直接驱动，永远即时且与视线一致。
## 视觉上"看着它"和"打中它"必须一致，所以以相机为准。
func aim_dir() -> Vector3:
	if cam_yaw == null:
		return facing()
	var y := cam_yaw.rotation.y
	return Vector3(-sin(y), 0.0, -cos(y))


func _update_combat(dt: float) -> void:
	if attack_cd > 0.0:
		attack_cd = maxf(0.0, attack_cd - dt)

	if swing_t < 0.0:
		return

	swing_t += dt
	var k := swing_t / swing_dur
	if k >= 1.0:
		swing_t = -1.0
		# 收势：只复位持械的手臂
		_reset_weapon_arms()
		return

	# 挥砍曲线：前 35% 快速下劈，之后缓慢回位
	var s := 0.0
	if k < 0.35:
		s = k / 0.35
	else:
		s = 1.0 - (k - 0.35) / 0.65
	# 用力曲线：让中段更快、两端更黏
	s = smoothstep(0.0, 1.0, s)

	var arm_r := model.get_node_or_null("ArmR")
	if arm_r != null:
		# 从抬起（-1.9）劈到身前（0.5）
		arm_r.rotation.x = lerpf(-1.9, 0.5, s)
	var arm_l := model.get_node_or_null("ArmL")
	if arm_l != null:
		arm_l.rotation.x = lerpf(-0.5, 0.25, s)


func _reset_weapon_arms() -> void:
	for nm in ["ArmL", "ArmR"]:
		var a := model.get_node_or_null(nm)
		if a != null:
			a.rotation.x = 0.0
