extends CharacterBody3D
## 第三人称角色：WASD 移动 / 右键拖拽转视角 / 滚轮缩放 / 空格跳跃
## 贴地用地形高度函数，与建筑用圆形避让

const M := preload("res://scripts/props.gd")

var terrain: Node3D
var obstacles: Array = []          # [{pos:Vector2, r:float}]

var yaw := 0.0
var pitch := -0.35
var cam_dist := 9.0

var walk_speed := 5.2
var run_speed := 8.6
var jump_v := 0.0
var jump_h := 0.0
var on_ground := true
var walk_phase := 0.0

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

var cam_yaw: Node3D
var cam_pitch: Node3D
var cam: Camera3D
var model: Node3D

# —— 战斗（近战）——
const WeaponsS := preload("res://scripts/weapons.gd")
var weapon_idx := 0                # 当前武器在 WeaponsS.LIST 中的下标
var attack_cd := 0.0               # 剩余冷却
var swing_t := -1.0                # 挥砍动画进度（<0 表示未在挥）
var swing_dur := 0.30


func _ready() -> void:
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


func setup(terr: Node3D, obs: Array, spawn2: Vector2) -> void:
	terrain = terr
	obstacles = obs
	global_position = Vector3(spawn2.x, terr.height_at(spawn2.x, spawn2.y) + 0.1, spawn2.y)
	if terr != null and terr.has_method("water_level"):
		_water_level = float(terr.water_level())
	# 开局让身体朝向与相机一致。否则 model.rotation.y 停在 0，
	# 而相机在局部 +Z 侧朝 -Z 看，玩家一开局就是"背对相机站着"，
	# 建造预览会直接落在身后。朝向 = 相机朝向（aim_dir），即 yaw + PI。
	model.rotation.y = yaw + PI


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


func _process(dt: float) -> void:
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

	# 速度按水域打折。用本帧起点的位置判定即可——位移一帧只有几十厘米，
	# 不值得为此先把位移算出来再回填速度。
	var speed := run_speed if running else walk_speed
	if swimming:
		speed *= SWIM_SPEED_MUL
	elif swim_depth > 0.06:
		speed *= WADE_SPEED_MUL     # 趟浅水也慢一点

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

	# —— 跳跃（水里不适用：垂直方向交给漂浮/下潜接管）——
	var want_jump := Input.is_key_pressed(KEY_SPACE) or GameBus.touch_jump_edge
	GameBus.touch_jump_edge = false
	if not swimming:
		if want_jump and on_ground:
			jump_v = 7.4
			on_ground = false
		if not on_ground:
			jump_v -= 21.0 * dt
			jump_h += jump_v * dt
			if jump_h <= 0.0:
				jump_h = 0.0
				jump_v = 0.0
				on_ground = true

	# —— 位移 ——
	var p := global_position
	p.x += dir.x * speed * dt
	p.z += dir.z * speed * dt

	# 建筑圆形避让
	for o in obstacles:
		var d2 := Vector2(p.x - o.pos.x, p.z - o.pos.y)
		var min_d: float = o.r + 0.42
		if d2.length() < min_d and d2.length() > 0.001:
			d2 = d2.normalized() * min_d
			p.x = o.pos.x + d2.x
			p.z = o.pos.y + d2.y

	# 世界边界
	var lim := 112.0
	p.x = clampf(p.x, -lim, lim)
	p.z = clampf(p.z, -lim, lim)

	# —— 垂直：陆地贴地、水中漂浮 ——
	# 用位移【之后】的位置重新判定一次：这一步决定玩家是被地面托着还是被水托着，
	# 用水域起点位置判定会在跨过岸线的那一帧做错决定。
	var gy: float = terrain.height_at(p.x, p.z)
	swim_depth = _water_depth(p.x, p.z)
	swimming = swim_depth > SWIM_MIN
	if swimming:
		on_ground = false
		jump_h = 0.0
		jump_v = 0.0
		# 漂浮基准：身体没入水面 FLOAT_SUBMERGE，头露出呼吸
		var target := _water_level - FLOAT_SUBMERGE
		if diving:
			target = maxf(_water_level - DIVE_MAX, gy + 0.55)
		# 水里上下都"黏"：下潜比上浮略快（蹬水容易，浮起来慢），
		# 直接设位置会像电梯，用插值才有浮力感。
		# 但也不能太黏：2.4 的时间常数约 0.42 秒，从水面跳进湖要 2 秒才稳下来，
		# 手感是"陷在水里"。3.0/4.6 大约 1 秒到位，既有浮力感又不拖。
		var rate := (4.6 if diving else 3.0) * dt
		p.y = lerpf(p.y, target, clampf(rate, 0.0, 1.0))
		p.y = maxf(p.y, gy + 0.45)
	else:
		p.y = gy + jump_h
	global_position = p

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
		# 前倾角度：-0.5 rad ≈ 29°（漂着划水），-0.95 rad ≈ 54°（下潜时几乎趴平）。
		# 角度太小会像"站在水里"，太大又会变成游泳运动员那种水平姿态，低多边形角色撑不住。
		model.rotation.x = lerpf(model.rotation.x, -0.95 if diving else -0.5, 0.09)
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

	# 跳跃姿态
	# 【必须排除游泳】游泳时 on_ground 恒为 false，不加这个判断的话
	# 上面的划水动作会被"举双手"覆盖掉，水里看起来像在投降。
	model.position.y = 0.0
	if not on_ground and not swimming:
		var arm_l := model.get_node_or_null("ArmL")
		if arm_l:
			arm_l.rotation.x = -1.1
			ab.rotation.x = -1.1

	# —— 战斗冷却与挥砍动画 ——
	_update_combat(dt)


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
