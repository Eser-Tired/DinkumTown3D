extends CharacterBody3D
## 村民是友好实体，不继承 Huntable，不能混入狩猎掉落或动物存档索引。
const Rig := preload("res://scripts/rigged_visual.gd")
const U := preload("res://scripts/ui_layout.gd")
const SPEED := 1.25
const RADIUS := 7.0 # 以各自门前为中心；不跨整个地图，避免把日常散步变成远途寻路。
var npc_id := ""
var display_name := ""
var merchant := false
var world: Node3D
var home := Vector2.ZERO
var target := Vector2.ZERO
var initial_position := Vector3.ZERO
var initial_yaw := 0.0
var wait_left := 1.0
var blocked_time := 0.0
var engaged := false
var actual_speed := 0.0
var rng := RandomNumberGenerator.new()
var rig := Rig.new()
var model: Node3D

func configure(main: Node3D, id: String, title: String, pos: Vector3, yaw: float, seller: bool, tint: Color) -> void:
	world = main
	npc_id = id
	display_name = title
	merchant = seller
	position = pos
	initial_position = pos
	initial_yaw = yaw
	rotation.y = yaw
	home = Vector2(pos.x, pos.z)
	target = home
	# 独立随机流：新增人不能挤掉原世界的资源或动物随机样本。
	rng.seed = absi(hash(id) ^ main.map_seed)
	set_meta("tint", tint)

func _ready() -> void:
	collision_layer = 32
	collision_mask = 39 # 世界、玩家、动态道具、其它村民；相机不把人当建筑。
	floor_snap_length = 0.32
	floor_max_angle = deg_to_rad(48)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.76
	shape.shape = capsule
	shape.position.y = 0.88
	add_child(shape)
	model = Node3D.new()
	add_child(model)
	if rig.attach(model, "res://assets/characters/Adventurer.scn", 1.76):
		for mesh in rig.root.find_children("*", "MeshInstance3D", true, false):
			for s in mesh.mesh.get_surface_count():
				var material: Material = mesh.get_active_material(s).duplicate()
				# 模型材质按身体部位分开；只给衣裤配色，不能把皮肤一起染成绿色。
				if material is StandardMaterial3D and material.resource_name in ["Green", "LightGreen", "Brown", "Brown2"]:
					material.albedo_color *= get_meta("tint")
				mesh.set_surface_override_material(s, material)
	else:
		# 缺角色包时仍有可见友好胶囊，交互与碰撞不依赖美术安装。
		var fallback := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.32
		mesh.height = 1.76
		fallback.mesh = mesh
		fallback.position.y = 0.88
		var mat := StandardMaterial3D.new()
		mat.albedo_color = get_meta("tint")
		fallback.material_override = mat
		model.add_child(fallback)
	var label := Label3D.new()
	label.text = display_name
	label.font = U.font()
	label.font_size = 38
	label.pixel_size = 0.005
	label.position.y = 2.04
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	add_child(label)

func valid_point(point: Vector2) -> bool:
	if point.distance_to(home) > RADIUS or world.terrain.water_depth_at(point.x, point.y) > 0: return false
	if world._inside_building(point, 0.65): return false
	var height: float = world.terrain.height_at(point.x, point.y)
	if absf(height - world.terrain.height_at(home.x, home.y)) > 1.8: return false
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.40
	capsule.height = 1.7
	query.shape = capsule
	query.transform.origin = Vector3(point.x, height + 0.96, point.y)
	query.collision_mask = 37
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _pick_target() -> void:
	for i in 24:
		# sqrt 半径在圆盘内均匀采样，不能只围着一条线测随机范围。
		var angle := rng.randf() * TAU
		var point := home + Vector2(cos(angle), sin(angle)) * sqrt(rng.randf()) * RADIUS
		if valid_point(point):
			target = point
			return
	target = Vector2(global_position.x, global_position.z)
	wait_left = 1.0

func _physics_process(dt: float) -> void:
	var before := global_position
	var point := Vector2(before.x, before.z)
	var direction := target - point
	velocity.x = 0
	velocity.z = 0
	if engaged or merchant:
		if world.player.global_position.distance_to(before) < 4.0:
			var face: Vector3 = world.player.global_position - before
			rotation.y = lerp_angle(rotation.y, atan2(face.x, face.z), 1.0 - exp(-6.0 * dt))
	elif wait_left > 0:
		wait_left -= dt
		if wait_left <= 0: _pick_target()
	elif direction.length() < 0.3:
		wait_left = rng.randf_range(1.5, 4.0)
	else:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.y), 1.0 - exp(-5.0 * dt))
		var forward := Vector2(sin(rotation.y), cos(rotation.y))
		var speed := SPEED * maxf(0, forward.dot(direction.normalized()))
		var next := point + forward * minf(speed * dt, direction.length())
		# 每一步问地形并守半径；拒绝移动时播放待机，不能原地跑步。
		if next.distance_to(home) <= RADIUS and not world._inside_building(next, 0.65) and world.terrain.water_depth_at(next.x, next.y) <= 0 and absf(world.terrain.height_at(next.x, next.y) - before.y) < 0.35:
			var probe := global_transform
			probe.origin.y += 0.03
			# 移动前检查实体，拒绝顶墙侧滑；步速不能拿意图速度冒充实际移动。
			if not test_move(probe, Vector3(forward.x, 0, forward.y) * speed * dt):
				velocity.x = forward.x * speed
				velocity.z = forward.y * speed
		else:
			blocked_time += dt
	velocity.y = -1.0 if is_on_floor() else maxf(velocity.y - 24.0 * dt, -20.0)
	move_and_slide()
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z)
	actual_speed = moved.length() / dt
	if not merchant and not engaged and wait_left <= 0 and direction.length() >= 0.3:
		if actual_speed < 0.08: blocked_time += dt
		else: blocked_time = 0
		if blocked_time > 0.6:
			blocked_time = 0
			wait_left = rng.randf_range(0.3, 0.8)
	if rig.root != null:
		if actual_speed > 0.08: rig.locomote("Walk", actual_speed)
		else: rig.play(rig.idle_name)
		rig.animation.advance(dt)

func snapshot() -> Dictionary:
	return {"pos": [position.x, position.y, position.z], "yaw": rotation.y,
		"target": [target.x, target.y], "wait": wait_left, "rng": str(rng.state)}

func restore(data: Dictionary) -> void:
	rng.seed = absi(hash(npc_id) ^ world.map_seed)
	position = initial_position
	rotation.y = initial_yaw
	target = home
	wait_left = 1.0
	velocity = Vector3.ZERO
	engaged = false
	blocked_time = 0
	var p: Variant = data.get("pos", [])
	if not merchant and p is Array and p.size() == 3:
		var point := Vector2(float(p[0]), float(p[2]))
		if valid_point(point): position = Vector3(point.x, world.terrain.height_at(point.x, point.y) + 0.03, point.y)
	rotation.y = float(data.get("yaw", initial_yaw))
	var t: Variant = data.get("target", [])
	if t is Array and t.size() == 2:
		var point := Vector2(float(t[0]), float(t[1]))
		if valid_point(point): target = point
	wait_left = clampf(float(data.get("wait", 1.0)), 0, 4.0)
	# RNG state 用十进制字符串，JSON 浮点不能精确承载64位随机状态。
	var saved_rng := str(data.get("rng", ""))
	if saved_rng.is_valid_int(): rng.state = int(saved_rng)
