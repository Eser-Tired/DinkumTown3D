extends Huntable
## 袋鼠：澳洲内陆主角。大后腿、粗尾、跳跃移动。可狩猎，掉肉 + 少量纤维。


func _mi(mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	return mi


func _build_model() -> Node3D:
	walk_speed = 2.3
	flee_speed = 8.8
	hop_height = 1.05
	hop_interval = 0.74
	flee_dist = 12.0
	wander_r = 26.0

	var root := Node3D.new()
	var M := preload("res://scripts/props.gd")
	var is_red := rng.randf() < 0.55
	var fur := M.mat(Color(0.58, 0.38, 0.27) if is_red else Color(0.51, 0.46, 0.40))
	var fur_dark := M.mat(Color(0.42, 0.27, 0.19) if is_red else Color(0.38, 0.34, 0.30))
	var pale := M.mat(Color(0.78, 0.70, 0.60))

	# 躯干
	var body := SphereMesh.new()
	body.radius = 0.5
	body.height = 1.0
	body.radial_segments = 8
	body.rings = 4
	root.add_child(_mi(body, fur, Vector3(0, 0.92, 0), Vector3(0.25, 0, 0), Vector3(0.80, 0.72, 1.25)))

	# 胸腹
	var chest := SphereMesh.new()
	chest.radius = 0.38
	chest.height = 0.7
	chest.radial_segments = 7
	chest.rings = 3
	root.add_child(_mi(chest, pale, Vector3(0, 0.86, 0.34), Vector3.ZERO, Vector3(0.85, 1.0, 0.85)))

	# 粗尾（分节，向后下方）
	var tail := Node3D.new()
	tail.position = Vector3(0, 0.80, -0.55)
	var tz := 0.0
	var ty := 0.0
	for i in 4:
		var r := 0.19 - float(i) * 0.035
		var seg := CylinderMesh.new()
		seg.top_radius = r - 0.03
		seg.bottom_radius = r
		seg.height = 0.42
		seg.radial_segments = 6
		tail.add_child(_mi(seg, fur_dark, Vector3(0, ty, tz), Vector3(1.15, 0, 0)))
		tz -= 0.34
		ty -= 0.10
	root.add_child(tail)

	# 后腿（大腿 + 小腿 + 长脚）
	for s in [-1.0, 1.0]:
		var thigh := SphereMesh.new()
		thigh.radius = 0.30
		thigh.height = 0.55
		thigh.radial_segments = 6
		thigh.rings = 3
		root.add_child(_mi(thigh, fur, Vector3(s * 0.30, 0.68, -0.18), Vector3.ZERO, Vector3(0.75, 1.15, 1.05)))

		var shin := CylinderMesh.new()
		shin.top_radius = 0.075
		shin.bottom_radius = 0.095
		shin.height = 0.55
		shin.radial_segments = 5
		root.add_child(_mi(shin, fur_dark, Vector3(s * 0.30, 0.36, 0.02), Vector3(-0.45, 0, 0)))

		var foot := BoxMesh.new()
		foot.size = Vector3(0.17, 0.10, 0.52)
		root.add_child(_mi(foot, fur_dark, Vector3(s * 0.30, 0.06, 0.22)))

	# 前爪
	for s in [-1.0, 1.0]:
		var arm := CylinderMesh.new()
		arm.top_radius = 0.065
		arm.bottom_radius = 0.085
		arm.height = 0.44
		arm.radial_segments = 5
		root.add_child(_mi(arm, fur, Vector3(s * 0.24, 0.86, 0.30), Vector3(-0.55, 0, s * 0.12)))

	# 脖子 + 头
	var neck := CylinderMesh.new()
	neck.top_radius = 0.13
	neck.bottom_radius = 0.19
	neck.height = 0.55
	neck.radial_segments = 6
	root.add_child(_mi(neck, fur, Vector3(0, 1.34, 0.34), Vector3(-0.62, 0, 0)))

	var head := Node3D.new()
	head.position = Vector3(0, 1.60, 0.56)
	var sk := SphereMesh.new()
	sk.radius = 0.17
	sk.height = 0.30
	sk.radial_segments = 7
	sk.rings = 4
	head.add_child(_mi(sk, fur, Vector3.ZERO, Vector3.ZERO, Vector3(0.85, 0.95, 1.25)))
	# 吻
	head.add_child(_mi(BoxMesh.new(), fur_dark, Vector3(0, -0.03, 0.20), Vector3.ZERO, Vector3(0.14, 0.13, 0.30)))
	head.add_child(_mi(SphereMesh.new(), M.mat(Color(0.15, 0.12, 0.11)), Vector3(0, -0.01, 0.34), Vector3.ZERO, Vector3(0.07, 0.07, 0.07)))
	# 眼
	for s in [-1.0, 1.0]:
		head.add_child(_mi(SphereMesh.new(), M.mat(Color(0.08, 0.07, 0.06)),
			Vector3(s * 0.11, 0.06, 0.11), Vector3.ZERO, Vector3(0.055, 0.055, 0.055)))
	# 大耳朵
	for s in [-1.0, 1.0]:
		var ear := BoxMesh.new()
		ear.size = Vector3(0.08, 0.32, 0.14)
		head.add_child(_mi(ear, fur_dark, Vector3(s * 0.11, 0.26, -0.04), Vector3(-0.18, 0, s * 0.30)))
	root.add_child(head)

	# —— 战斗属性：血量 / 掉落 / 命中盒 ——
	# 血量 30：斧头 2 刀、长矛 3 刀，制造"换武器有意义"的差异
	_configure(30, {
		"food": [2, 4],      # 袋鼠肉
		"fiber": [0, 2],     # 尾巴上的粗毛，低概率
	}, 1.0)

	return root
