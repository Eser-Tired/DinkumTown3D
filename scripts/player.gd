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

var cam_yaw: Node3D
var cam_pitch: Node3D
var cam: Camera3D
var model: Node3D


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
	var speed := run_speed if running else walk_speed

	# —— 跳跃 ——
	var want_jump := Input.is_key_pressed(KEY_SPACE) or GameBus.touch_jump_edge
	GameBus.touch_jump_edge = false
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

	# 贴地
	var gy: float = terrain.height_at(p.x, p.z)
	p.y = gy + jump_h
	global_position = p

	# —— 朝向与程序化动画 ——
	if dir.length() > 0.01:
		var target_yaw := atan2(dir.x, dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 0.22)
		walk_phase += dt * (10.0 if running else 7.0)
	else:
		walk_phase = lerpf(walk_phase, 0.0, 0.12)

	var swing := sin(walk_phase) * 0.55 * clampf(dir.length(), 0.0, 1.0)
	var la := model.get_node_or_null("LegL")
	var lb := model.get_node_or_null("LegR")
	var aa := model.get_node_or_null("ArmL")
	var ab := model.get_node_or_null("ArmR")
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
	model.position.y = 0.0
	if not on_ground:
		var arm_l := model.get_node_or_null("ArmL")
		if arm_l:
			arm_l.rotation.x = -1.1
			ab.rotation.x = -1.1
