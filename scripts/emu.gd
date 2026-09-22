extends Huntable
## 鸸鹋：澳洲国鸟，长脖子大步走。可狩猎，掉肉 + 羽毛（记作纤维）。


func _mi(mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	return mi


func _build_model() -> Node3D:
	walk_speed = 3.4
	flee_speed = 9.5
	hop_height = 0.12
	hop_interval = 0.42
	flee_dist = 16.0
	wander_r = 34.0

	var root := Node3D.new()
	var M := preload("res://scripts/props.gd")
	var feather := M.mat(Color(0.44, 0.38, 0.31))
	var feather_d := M.mat(Color(0.33, 0.28, 0.23))
	var leg_m := M.mat(Color(0.38, 0.33, 0.26))

	# 圆胖身体
	var body := SphereMesh.new()
	body.radius = 0.62
	body.height = 1.2
	body.radial_segments = 8
	body.rings = 4
	root.add_child(_mi(body, feather, Vector3(0, 1.05, 0), Vector3.ZERO, Vector3(0.85, 0.85, 1.10)))
	# 尾羽
	root.add_child(_mi(SphereMesh.new(), feather_d, Vector3(0, 1.05, -0.62), Vector3.ZERO, Vector3(0.42, 0.40, 0.36)))

	# 长脖子
	var neck := CylinderMesh.new()
	neck.top_radius = 0.09
	neck.bottom_radius = 0.14
	neck.height = 1.05
	neck.radial_segments = 6
	root.add_child(_mi(neck, M.mat(Color(0.42, 0.48, 0.52)), Vector3(0, 1.72, 0.22), Vector3(-0.42, 0, 0)))

	# 头 + 喙
	var head := Node3D.new()
	head.position = Vector3(0, 2.15, 0.44)
	head.add_child(_mi(SphereMesh.new(), feather, Vector3.ZERO, Vector3.ZERO, Vector3(0.19, 0.19, 0.24)))
	head.add_child(_mi(BoxMesh.new(), M.mat(Color(0.28, 0.26, 0.22)), Vector3(0, -0.02, 0.22), Vector3.ZERO, Vector3(0.09, 0.09, 0.26)))
	for s in [-1.0, 1.0]:
		head.add_child(_mi(SphereMesh.new(), M.mat(Color(0.85, 0.72, 0.25)),
			Vector3(s * 0.11, 0.04, 0.06), Vector3.ZERO, Vector3(0.05, 0.05, 0.05)))
	root.add_child(head)

	# 长腿
	for s in [-1.0, 1.0]:
		var thigh := CylinderMesh.new()
		thigh.top_radius = 0.09
		thigh.bottom_radius = 0.11
		thigh.height = 0.55
		thigh.radial_segments = 5
		root.add_child(_mi(thigh, feather_d, Vector3(s * 0.22, 0.72, 0.0)))

		var shin := CylinderMesh.new()
		shin.top_radius = 0.05
		shin.bottom_radius = 0.06
		shin.height = 0.62
		shin.radial_segments = 5
		root.add_child(_mi(shin, leg_m, Vector3(s * 0.22, 0.32, 0.02)))

		root.add_child(_mi(BoxMesh.new(), leg_m, Vector3(s * 0.22, 0.04, 0.12), Vector3.ZERO, Vector3(0.13, 0.08, 0.30)))

	# —— 战斗属性：比袋鼠脆（22 血），但掉更多羽毛 ——
	_configure(22, {
		"food": [2, 3],      # 鸸鹋肉（澳洲确实是红肉）
		"fiber": [1, 3],     # 羽毛归入纤维
	}, 1.05)

	return root
