extends RefCounted
## 世界层=1，角色层=2，动态道具层=4。
## 只在正式放置时建碰撞，预览和菜单背景仍只是模型。


static func attach(root: Node3D, flora := false) -> void:
	if root.has_node("Solid"):
		return
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = 1
	body.collision_mask = 6
	# 工厂会缩放树木；把尺寸烘进 Shape，避免缩放物理节点。
	body.scale = Vector3.ONE / root.scale
	var base := Transform3D(Basis.from_scale(root.scale), Vector3.ZERO)
	if root.has_meta("deck_length"):
		# 窄板缝是视觉细节；连续的简化甲板避免脚底贴地射线落进缝隙。
		var length: float = root.get_meta("deck_length")
		var deck := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.2, 0.16, length) * root.scale
		deck.shape = box
		deck.position = Vector3(0, 0.9, 0.5 - length * 0.5) * root.scale
		body.add_child(deck)
	var meshes: Array[MeshInstance3D] = []
	if flora:
		# 树只碰树干，叶冠与细枝不阻挡；岩石碰所有主体。
		for c in root.get_children():
			if c is MeshInstance3D:
				if c.mesh is CylinderMesh or c.mesh is SphereMesh:
					meshes.append(c)
					if c.mesh is CylinderMesh:
						break
	else:
		_collect(root, meshes)
	for mi in meshes:
		var xform := base * _relative_transform(mi, root)
		if mi.mesh is CylinderMesh and not mi.mesh.cap_top and not mi.mesh.cap_bottom:
			# 帐篷布墙是空心圆筒，实心 CylinderShape 会把整个可行走空间堵住。
			_add_cylinder_wall(body, mi.mesh, xform)
			continue
		var shape_node := CollisionShape3D.new()
		if mi.mesh is BoxMesh:
			var box := BoxShape3D.new()
			box.size = mi.mesh.size * xform.basis.get_scale()
			shape_node.shape = box
			shape_node.transform = Transform3D(xform.basis.orthonormalized(), xform.origin)
		elif mi.mesh is CylinderMesh and mi.mesh.top_radius > 0.0:
			var cylinder := CylinderShape3D.new()
			var mesh_scale := xform.basis.get_scale()
			cylinder.radius = maxf(mi.mesh.top_radius, mi.mesh.bottom_radius) * maxf(mesh_scale.x, mesh_scale.z)
			cylinder.height = mi.mesh.height * mesh_scale.y
			shape_node.shape = cylinder
			shape_node.transform = Transform3D(xform.basis.orthonormalized(), xform.origin)
		else:
			var convex := mi.mesh.create_convex_shape(true, true)
			if convex == null:
				shape_node.free()
				continue
			var pts := convex.points
			for i in pts.size():
				pts[i] = xform * pts[i]
			convex.points = pts
			shape_node.shape = convex
		body.add_child(shape_node)
	if body.get_child_count() == 0:
		body.free()
	else:
		root.add_child(body)


static func _add_cylinder_wall(body: StaticBody3D, mesh: CylinderMesh, xform: Transform3D) -> void:
	var count := mesh.radial_segments
	var radius := maxf(mesh.top_radius, mesh.bottom_radius)
	var width := 2.0 * radius * sin(PI / count)
	var middle := radius * cos(PI / count)
	for i in count:
		var angle := TAU * (i + 0.5) / count
		var segment := xform * Transform3D(Basis(Vector3.UP, angle),
			Vector3(sin(angle), 0, cos(angle)) * middle)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# 8厘米只代表布墙厚度，圆筒内部保持空旷。
		box.size = Vector3(width, mesh.height, 0.08) * segment.basis.get_scale()
		shape.shape = box
		shape.transform = Transform3D(segment.basis.orthonormalized(), segment.origin)
		body.add_child(shape)


static func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node.has_meta("bob") or node.has_meta("spin") or node.has_meta("flicker"):
		return
	if node is MeshInstance3D and node.mesh != null:
		out.append(node)
	for child in node.get_children():
		_collect(child, out)


static func _relative_transform(mi: Node3D, root: Node3D) -> Transform3D:
	var result := mi.transform
	var parent := mi.get_parent()
	while parent != root and parent is Node3D:
		result = parent.transform * result
		parent = parent.get_parent()
	return result
