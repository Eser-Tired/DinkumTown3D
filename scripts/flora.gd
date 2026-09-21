extends RefCounted
class_name Flora
## 澳洲内陆植被：桉树 / 金合欢 / 棕榈 / 灌木 / 干草 / 岩石 / 铁矿

const M := preload("res://scripts/props.gd")


static func _mi(mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	return mi


# ——————————————— 桉树 ———————————————
static func make_eucalyptus(rng: RandomNumberGenerator, scale := 1.0) -> Node3D:
	var root := Node3D.new()
	var h := rng.randf_range(6.0, 10.0) * scale
	var bark := M.mat(Color(0.62, 0.56, 0.46).lerp(Color(0.48, 0.40, 0.32), rng.randf()))

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.28 * scale
	trunk.bottom_radius = 0.52 * scale
	trunk.height = h
	trunk.radial_segments = 7
	trunk.rings = 2
	var tilt := rng.randf_range(-0.05, 0.05)
	root.add_child(_mi(trunk, bark, Vector3(0, h * 0.5, 0), Vector3(tilt, rng.randf() * TAU, tilt)))

	# 稀疏的伞状叶团（桉树特征：叶子分散、透光）
	var clumps := rng.randi_range(3, 5)
	for i in clumps:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(0.4, 1.9) * scale
		var s := SphereMesh.new()
		s.radius = rng.randf_range(1.3, 2.3) * scale
		s.height = s.radius * rng.randf_range(0.85, 1.25)
		s.radial_segments = 7
		s.rings = 4
		var leaf_col := Color(0.36, 0.45, 0.24).lerp(Color(0.52, 0.56, 0.30), rng.randf())
		root.add_child(_mi(s, M.mat(leaf_col),
			Vector3(cos(a) * rr, h * rng.randf_range(0.72, 1.02), sin(a) * rr),
			Vector3(0, rng.randf() * TAU, 0),
			Vector3(1.0, 0.42, 1.0)))

	# 枯枝
	if rng.randf() < 0.5:
		var br := CylinderMesh.new()
		br.top_radius = 0.05
		br.bottom_radius = 0.12
		br.height = 1.8 * scale
		br.radial_segments = 5
		root.add_child(_mi(br, bark,
			Vector3(rng.randf_range(-0.8, 0.8) * scale, h * 0.62, rng.randf_range(-0.8, 0.8) * scale),
			Vector3(0, rng.randf() * TAU, rng.randf_range(0.7, 1.1))))

	root.set_meta("collide_radius", 0.95 * scale)
	root.set_meta("resource", "wood")
	root.set_meta("amount", 3)
	return root


# ——————————————— 金合欢（wattle，黄花） ———————————————
static func make_acacia(rng: RandomNumberGenerator, scale := 1.0) -> Node3D:
	var root := Node3D.new()
	var h := rng.randf_range(3.0, 4.6) * scale
	var bark := M.mat(Color(0.45, 0.35, 0.26))

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16 * scale
	trunk.bottom_radius = 0.34 * scale
	trunk.height = h
	trunk.radial_segments = 6
	root.add_child(_mi(trunk, bark, Vector3(0, h * 0.5, 0)))

	# 宽扁伞状冠
	var s := SphereMesh.new()
	s.radius = rng.randf_range(2.2, 3.2) * scale
	s.height = s.radius * 0.55
	s.radial_segments = 8
	s.rings = 3
	root.add_child(_mi(s, M.mat(Color(0.42, 0.50, 0.26)),
		Vector3(0, h + 0.5 * scale, 0), Vector3(0, rng.randf() * TAU, 0), Vector3(1.0, 0.6, 1.0)))

	# 黄花串
	for i in rng.randi_range(6, 12):
		var a := rng.randf() * TAU
		var rr := rng.randf_range(0.6, 2.4) * scale
		var fs := SphereMesh.new()
		fs.radius = 0.26 * scale
		fs.height = 0.5 * scale
		fs.radial_segments = 5
		fs.rings = 2
		root.add_child(_mi(fs, M.mat(Color(0.92, 0.78, 0.22)),
			Vector3(cos(a) * rr, h + rng.randf_range(0.2, 0.9) * scale, sin(a) * rr)))

	root.set_meta("collide_radius", 0.7 * scale)
	root.set_meta("resource", "wood")
	root.set_meta("amount", 2)
	return root


# ——————————————— 棕榈 ———————————————
static func make_palm(rng: RandomNumberGenerator, scale := 1.0) -> Node3D:
	var root := Node3D.new()
	var h := rng.randf_range(5.0, 7.5) * scale
	var bark := M.mat(Color(0.56, 0.46, 0.34))

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.20 * scale
	trunk.bottom_radius = 0.36 * scale
	trunk.height = h
	trunk.radial_segments = 6
	var bend := rng.randf_range(0.06, 0.16)
	root.add_child(_mi(trunk, bark, Vector3(0, h * 0.5, 0), Vector3(bend, rng.randf() * TAU, 0)))

	var top := Node3D.new()
	top.position = Vector3(0, h, 0)
	top.rotation = Vector3(bend, 0, 0)
	var fronds := rng.randi_range(7, 9)
	for i in fronds:
		var a := TAU * float(i) / float(fronds)
		var f := BoxMesh.new()
		f.size = Vector3(0.5, 0.06, 3.0)
		var pivot := Node3D.new()
		pivot.rotation = Vector3(0, a, 0)
		var leaf := _mi(f, M.mat(Color(0.28, 0.46, 0.22)),
			Vector3(0, 0, 1.5), Vector3(rng.randf_range(0.45, 0.85), 0, 0))
		pivot.add_child(leaf)
		top.add_child(pivot)
	top.add_child(_mi(SphereMesh.new(), M.mat(Color(0.42, 0.35, 0.26)), Vector3(0, 0.1, 0)))
	root.add_child(top)

	root.set_meta("collide_radius", 0.6 * scale)
	return root


# ——————————————— 灌木 ———————————————
static func make_bush(rng: RandomNumberGenerator, scale := 1.0) -> Node3D:
	var root := Node3D.new()
	for i in rng.randi_range(2, 4):
		var s := SphereMesh.new()
		s.radius = rng.randf_range(0.5, 0.9) * scale
		s.height = s.radius * rng.randf_range(0.7, 1.0)
		s.radial_segments = 6
		s.rings = 3
		root.add_child(_mi(s, M.mat(Color(0.38, 0.44, 0.22).lerp(Color(0.54, 0.55, 0.28), rng.randf())),
			Vector3(rng.randf_range(-0.4, 0.4), s.radius * 0.75, rng.randf_range(-0.4, 0.4))))
	root.set_meta("collide_radius", 0.0)
	root.set_meta("resource", "fiber")
	root.set_meta("amount", 2)
	return root


# ——————————————— 干草丛（供 MultiMesh） ———————————————
static func grass_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := 6
	for i in blades:
		var a := TAU * float(i) / float(blades) + rng.randf_range(-0.3, 0.3)
		var lean := rng.randf_range(0.25, 0.75)
		var h := rng.randf_range(0.45, 0.85)
		var w := rng.randf_range(0.07, 0.13)
		var dx := cos(a) * lean
		var dz := sin(a) * lean
		var px := cos(a + PI * 0.5) * w
		var pz := sin(a + PI * 0.5) * w
		var base := Vector3(0, 0, 0)
		var tip := Vector3(dx, h, dz)
		st.set_color(Color(0.40, 0.38, 0.17))
		st.set_normal(Vector3.UP)
		st.add_vertex(base + Vector3(px, 0, pz))
		st.set_color(Color(0.58, 0.53, 0.26))
		st.add_vertex(base - Vector3(px, 0, pz))
		st.set_color(Color(0.66, 0.60, 0.30))
		st.add_vertex(tip)
		# 背面
		st.add_vertex(base - Vector3(px, 0, pz))
		st.add_vertex(base + Vector3(px, 0, pz))
		st.add_vertex(tip)
	st.generate_normals()
	return st.commit()


static func grass_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


# ——————————————— 岩石 ———————————————
static func make_rock(rng: RandomNumberGenerator, scale := 1.0, ore := false) -> Node3D:
	var root := Node3D.new()
	var base_col := Color(0.50, 0.47, 0.42).lerp(Color(0.58, 0.36, 0.26), rng.randf())
	var rock_col := base_col if not ore else Color(0.40, 0.38, 0.36)

	var s := SphereMesh.new()
	s.radius = rng.randf_range(0.9, 1.7) * scale
	s.height = s.radius * rng.randf_range(0.7, 1.1)
	s.radial_segments = 7
	s.rings = 3
	root.add_child(_mi(s, M.mat(rock_col), Vector3(0, s.radius * 0.55, 0),
		Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))))

	if rng.randf() < 0.6:
		var s2 := SphereMesh.new()
		s2.radius = rng.randf_range(0.4, 0.9) * scale
		s2.height = s2.radius
		s2.radial_segments = 6
		s2.rings = 3
		root.add_child(_mi(s2, M.mat(rock_col.lightened(0.06)),
			Vector3(rng.randf_range(-1.2, 1.2), s2.radius * 0.6, rng.randf_range(-1.2, 1.2))))

	if ore:
		# 铁矿石：发光晶簇
		for i in rng.randi_range(3, 6):
			var a := rng.randf() * TAU
			var rr := rng.randf_range(0.3, 1.0) * scale
			var c := CylinderMesh.new()
			c.bottom_radius = 0.22 * scale
			c.top_radius = 0.0
			c.height = 0.62 * scale
			c.radial_segments = 5
			c.rings = 1
			root.add_child(_mi(c, M.glow_mat(Color(0.95, 0.62, 0.30)),
				Vector3(cos(a) * rr, s.radius * rng.randf_range(0.6, 1.0), sin(a) * rr),
				Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))))
		root.set_meta("resource", "ore")
		root.set_meta("amount", 2)
	else:
		root.set_meta("resource", "stone")
		root.set_meta("amount", 2)

	root.set_meta("collide_radius", 1.1 * scale)
	return root


# ——————————————— 枯树桩（采集后残留） ———————————————
static func make_stump() -> Node3D:
	var root := Node3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.5
	c.bottom_radius = 0.62
	c.height = 0.55
	c.radial_segments = 7
	root.add_child(_mi(c, M.mat(Color(0.42, 0.32, 0.24)), Vector3(0, 0.27, 0)))
	root.set_meta("collide_radius", 0.0)
	return root
