extends RigidBody3D
## 少量可推动道具；浮力采样与玩家共用 terrain 的水域真值。

const PropsS := preload("res://scripts/props.gd")
var kind := "crate"
var terrain: Node3D
var _pending_restore: Dictionary = {}


func configure(p_kind: String, terr: Node3D) -> void:
	kind = p_kind
	terrain = terr
	collision_layer = 4
	collision_mask = 7
	mass = 3.5 if kind == "log" else 9.0
	continuous_cd = true
	linear_damp = 0.35
	angular_damp = 0.65
	var pm := PhysicsMaterial.new()
	pm.friction = 0.75
	pm.bounce = 0.08
	physics_material_override = pm
	var shape_node := CollisionShape3D.new()
	var mi := MeshInstance3D.new()
	if kind == "log" or kind == "barrel":
		var mesh := CylinderMesh.new()
		mesh.radial_segments = 10
		mesh.top_radius = 0.28 if kind == "log" else 0.45
		mesh.bottom_radius = mesh.top_radius
		mesh.height = 1.65 if kind == "log" else 1.1
		mi.mesh = mesh
		var shape := CylinderShape3D.new()
		shape.radius = mesh.top_radius
		shape.height = mesh.height
		shape_node.shape = shape
		if kind == "log":
			mi.rotation.z = PI * 0.5
			shape_node.rotation.z = PI * 0.5
	else:
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * 0.95
		mi.mesh = mesh
		var shape := BoxShape3D.new()
		shape.size = mesh.size
		shape_node.shape = shape
	mi.material_override = PropsS.surface("wood", PropsS.C_WOOD_LIGHT if kind == "crate" else PropsS.C_WOOD)
	add_child(mi)
	add_child(shape_node)
	if kind == "crate":
		# 面板外侧的压条，让可推动木箱更容易辨认。
		for z in [-0.48, 0.48]:
			for y in [-0.33, 0.33]:
				var slat := MeshInstance3D.new()
				var mesh := BoxMesh.new()
				mesh.size = Vector3(1.0, 0.08, 0.04)
				slat.mesh = mesh
				slat.position = Vector3(0, y, z)
				slat.material_override = PropsS.surface("wood", PropsS.C_WOOD_DARK)
				add_child(slat)


func _physics_process(_dt: float) -> void:
	if kind != "log" or terrain == null:
		return
	# 水中不能永久休眠，否则上浮力不再积分；陆地上仍可自动休眠。
	if terrain.water_depth_at(global_position.x, global_position.z) > 0.05 \
			and global_position.y < terrain.water_level() + 0.35:
		sleeping = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _pending_restore.is_empty():
		state.transform = Transform3D(Basis.from_euler(_read_vec(_pending_restore.get("rot", []))),
			_read_vec(_pending_restore.get("pos", [])))
		state.linear_velocity = _read_vec(_pending_restore.get("linear", []))
		state.angular_velocity = _read_vec(_pending_restore.get("angular", []))
		state.sleeping = bool(_pending_restore.get("sleeping", false))
		_pending_restore.clear()
	if kind != "log" or terrain == null:
		return
	var submerged := 0.0
	for x in [-0.6, 0.0, 0.6]:
		var sample: Vector3 = state.transform * Vector3(x, 0, 0)
		if terrain.water_depth_at(sample.x, sample.z) <= 0.02:
			continue
		var depth: float = terrain.water_level() - sample.y
		var fraction := clampf((depth + 0.28) / 0.56, 0.0, 1.0)
		submerged += fraction / 3.0
		var force := Vector3.UP * mass * state.total_gravity.length() * 1.8 * fraction / 3.0
		state.apply_force(force, sample - state.transform.origin)
	if submerged > 0.0:
		state.linear_velocity *= exp(-1.8 * submerged * state.step)
		state.angular_velocity *= exp(-3.0 * submerged * state.step)


func serialize() -> Dictionary:
	return {"kind": kind, "pos": _vec(global_position), "rot": _vec(global_rotation),
		"linear": _vec(linear_velocity), "angular": _vec(angular_velocity), "sleeping": sleeping}


func restore(data: Dictionary) -> void:
	_pending_restore = data.duplicate(true)
	global_position = _read_vec(data.get("pos", []))
	global_rotation = _read_vec(data.get("rot", []))
	sleeping = false


static func _vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _read_vec(v: Variant) -> Vector3:
	if v is Array and v.size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO
