extends Node
## 必须窗口模式：headless 的 Dummy RenderingServer 不保存 MultiMesh 变换，读回会全为零。
## 用真实渲染后端逐实例测贴地/水域/禁种区，覆盖骨骼动画、密度和旧存档身份。
const Art := preload("res://scripts/nature_assets.gd")
const Scatter := preload("res://scripts/vegetation_scatter.gd")
var checks := 0
var fails := 0

func _ok(value: bool, message: String) -> void:
	checks += 1
	if not value:
		fails += 1
	print(("PASS " if value else "FAIL ") + message)

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("nature_check 需要窗口模式读回真实 MultiMesh 变换")
		get_tree().quit(2)
		return
	var models := 0
	var triangles := 0
	for file in DirAccess.get_files_at(Art.DIRECTORY):
		if file.get_extension() != "scn":
			continue
		var model := Art.instantiate(file.get_basename())
		_ok(model != null and model.has_meta("source_bounds"), file + "可加载")
		if model == null:
			continue
		models += 1
		for mi in model.get_children():
			if mi is MeshInstance3D:
				for s in mi.mesh.get_surface_count():
					triangles += mi.mesh.surface_get_array_index_len(s) / 3
		_ok(model.find_children("*", "CollisionObject3D", true, false).is_empty(), file + "不带多余碰撞")
		model.free()
	_ok(models == 68, "免费包68个模型完整转换")
	for file in DirAccess.get_files_at(Art.DIRECTORY + "textures"):
		var texture: Texture2D = load(Art.DIRECTORY + "textures/" + file)
		_ok(texture.get_width() <= 1024 and texture.get_height() <= 1024, "共享纹理≤1024：" + file)
	var main: Node3D = load("res://scripts/main.gd").new()
	main.forced_map_seed = 20260921
	add_child(main)
	main.player.set_physics_process(false)
	for animal in main.critters:
		animal.set_process(false)
	var signature := ""
	for resource in main.resources:
		signature += "%s:%d:%s;" % [resource.get_meta("resource"), resource.get_meta("amount"), resource.position]
	_ok(main.resources.size() == 191 and signature.sha256_text() == "f5ffc69462f7c76e611bf1c96d51bd06bbb00315d4e8ef952928aa5eb807ebbb", "191个旧采集点数量/类型/位置指纹不变")
	var dense: Node3D = main.get_node("DenseVegetation")
	var count := 0
	var bad := 0
	var groups := 0
	for mi in dense.get_children():
		if not mi is MultiMeshInstance3D:
			continue
		groups += 1
		for i in mi.multimesh.instance_count:
			var p: Vector3 = mi.position + mi.multimesh.get_instance_transform(i).origin
			if not Scatter.allowed(main.terrain, Vector2(p.x, p.z)) or absf(p.y - float(main.terrain.height_at(p.x, p.z)) + 0.025) > 0.002:
				if bad < 2:
					print("GEOMETRY_DIAG ", mi.name, " instance=", i, " p=", p, " ground=", main.terrain.height_at(p.x, p.z), " allowed=", Scatter.allowed(main.terrain, Vector2(p.x, p.z)))
				bad += 1
			count += 1
	_ok(count == int(dense.get_meta("count")) and count > 30000, "实际新增地被超过3万，计数一致")
	_ok(bad == 0, "全图逐点检查：贴地、水域、农田和通道 bad=0")
	_ok(dense.find_children("*", "CollisionObject3D", true, false).is_empty(), "地被不阻挡玩家/动物")
	var repeat := Scatter.build(main, main.terrain, 20260921)
	_ok(repeat.get_meta("fingerprint") == dense.get_meta("fingerprint"), "同种子全图分布完全一致")
	repeat.free()
	var alternate := Scatter.build(main, main.terrain, 20260922)
	_ok(alternate.get_meta("fingerprint") != dense.get_meta("fingerprint"), "换种子全图分布改变")
	alternate.free()
	_ok(main.player.rig.root != null and main.player.rig.skeleton.get_bone_count() > 20, "玩家真实骨骼模型已接入")
	var arm: int = main.player.rig.skeleton.find_bone("UpperArm.R")
	main.player.on_ground = true
	main.player.rig.update_player(main.player, 0.2, true, false)
	_ok(main.player.rig.current == "Walk", "行走用Walk骨骼动画")
	main.player.rig.update_player(main.player, 0.2, true, true)
	_ok(main.player.rig.current == "Run" and is_equal_approx(main.player.rig.animation.speed_scale, 1.0), "跑步和速度倍率正常")
	main.player.swing_t = 0.1
	main.player.rig.update_player(main.player, 0.15, false, false)
	_ok(main.player.rig.current == "Sword_Slash", "挥砍用Sword_Slash动画")
	main.player.swing_t = -1
	main.player.rig.update_player(main.player, 0.2, true, false)
	_ok(main.player.rig.current == "Walk" and is_equal_approx(main.player.rig.animation.speed_scale, 1.0), "攻击后行走不会继承挥砍加速")
	main.player.swimming = true
	main.player.model.get_node("ArmR").rotation.x = 1.3
	main.player.rig.update_player(main.player, 0.2, false, false)
	var pose: Quaternion = main.player.rig.skeleton.get_bone_pose_rotation(arm)
	main.player.model.get_node("ArmR").rotation.x = -1.3
	main.player.rig.update_player(main.player, 0.2, false, false)
	_ok(pose.angle_to(main.player.rig.skeleton.get_bone_pose_rotation(arm)) > 1.0, "游泳划水作用于真实骨骼")
	main.player.swimming = false
	var species := {}
	for animal in main.critters:
		species[animal.species] = true
		_ok(animal.rig.root != null and animal.rig.animation.has_animation("Death") and animal.rig.animation.has_animation("Walk"), animal.species + "带完整步态和死亡动画")
	_ok(species.size() == 3 and main.critters.size() == 15, "3种动物沿用15个狩猎槽位")
	var animal: Huntable = main.critters[0]
	animal.take_hit(999, main.player.global_position)
	animal._process(0.2)
	_ok(animal.dead and animal.rig.current == "Death" and is_zero_approx(animal.model.rotation.z), "死亡播真实动画，不再叠加原模型侧翻")
	animal._respawn()
	animal._process(0.016)
	_ok(not animal.dead and animal.hp == animal.max_hp and animal.rig.current != "Death", "重生恢复血量和活动动画")
	print("NATURE_STATS catalog=", models, " catalog_triangles=", triangles, " dense=", count, " chunks=", groups, " bad=", bad)
	var original_grass := 0
	for mi in main.get_children():
		if mi is MultiMeshInstance3D:
			for i in mi.multimesh.instance_count:
				if mi.multimesh.get_instance_transform(i).origin.y > -9000:
					original_grass += 1
	print("DENSITY_BASE=", original_grass, " DENSITY_TOTAL=", original_grass + count)
	print("==== NATURE CHECK DONE checks=%d fails=%d ====" % [checks, fails])
	get_tree().quit(1 if fails else 0)
