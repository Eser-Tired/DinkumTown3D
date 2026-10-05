extends Node
## 保留历史测试入口，验证当前 CC0 外观不会破坏碰撞、入口与旧存档。

const Assets := preload("res://scripts/optional_assets.gd")
const InteriorS := preload("res://scripts/interior.gd")
var m: Node3D
var checks := 0
var fails := 0


func _ready() -> void:
	m = load("res://scripts/main.gd").new()
	m.forced_map_seed = 20260921
	add_child(m)
	await _wait(0.3)
	await _run()
	# 协程中途脚本错误也会返回 _ready，必须防止少跑断言却打印成功。
	var installed := ResourceLoader.exists(Assets.DIRECTORY + "hut.scn") and not OS.get_cmdline_user_args().has("--no-emace")
	_ok(checks == (33 if installed else 27), "完整执行预期数量的验收断言")
	print("==== EMACE CHECK DONE checks=%d fails=%d ====" % [checks, fails])
	get_tree().quit(1 if fails else 0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false, true).timeout
	await get_tree().process_frame


func _ok(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		fails += 1
	print(("PASS " if condition else "FAIL ") + message)


func _run() -> void:
	var installed := ResourceLoader.exists(Assets.DIRECTORY + "hut.scn") and not OS.get_cmdline_user_args().has("--no-emace")
	var hut: Node3D = m.get_node("SampleHut")
	var h: Dictionary = m.houses[1]
	_ok(m.houses.size() == 7 and h.id == "hut_0", "建筑数量与稳定ID保持一致")
	_ok(hut.has_meta("asset_id") == installed, "小屋使用资源包或缺包回退")
	var asset_nodes := 0
	for node in m.get_children():
		if node.has_meta("asset_id"):
			asset_nodes += 1
	_ok(asset_nodes == 4 * int(installed), "三栋小屋与商店全部替换")
	_ok(hut.find_children("*", "StaticBody3D", true, false).size() == 1, "小屋只有一套实体碰撞")
	var crate: RigidBody3D = m.physics_props[0]
	_ok(crate.has_node("AssetVisual") == installed, "第一只木箱使用资源包或缺包回退")
	_ok(m.physics_props[1].has_node("AssetVisual") == installed, "第二只木箱同步替换或缺包回退")
	_ok(crate.mass == 9.0 and crate.collision_layer == 4 and crate.collision_mask == 7, "木箱保持质量与物理层")
	var shape: BoxShape3D = crate.find_children("*", "CollisionShape3D", true, false)[0].shape
	_ok(shape.size.is_equal_approx(Vector3.ONE * 0.95), "木箱保留0.95米碰撞盒")
	if installed:
		for kind in ["hut", "crate"]:
			var delivered := true
			for dependency in ResourceLoader.get_dependencies(Assets.DIRECTORY + kind + ".scn"):
				delivered = delivered and str(dependency).contains("res://assets/")
			_ok(delivered, "%s场景依赖全部位于仓库assets" % kind)
		var bounds: AABB = hut.get_meta("visual_bounds")
		print("HUT size=%s entrance=%s exit=%s triangles=%d" % [bounds.size, h.entrance_origin, h.exit_point, hut.get_meta("triangle_count")])
		_ok(bounds.size.y > 4.5 and bounds.size.y < 5.5, "压缩高屋顶后高度处于实测适配范围")
		var box_bounds: AABB = crate.get_node("AssetVisual").get_meta("visual_bounds")
		_ok(box_bounds.position.is_equal_approx(Vector3.ONE * -0.475) and box_bounds.size.is_equal_approx(Vector3.ONE * 0.95), "木箱外观与实体盒精确对齐")
		var entrance_local: Vector3 = hut.to_local(Vector3(h.entrance_origin.x, hut.global_position.y, h.entrance_origin.y))
		var actual_door := entrance_local + Vector3(0, 0, 2.9)
		_ok(absf(actual_door.x) < 0.002 and absf(actual_door.z - 2.1) < 0.002, "交互点落在CC0房屋前门中轴")
	var center: Vector2 = h.get("entrance_origin", h.pos)
	var dp := InteriorS.door_point(center, h.rot, "hut")
	var ep: Vector2 = h.get("exit_point", InteriorS.exit_point(h.pos, h.rot, "hut"))
	_ok(dp.distance_to(ep) < InteriorS.DOOR_REACH, "出门落点在真实入口交互范围内")
	var exit_height: float = m.terrain.height_at(ep.x, ep.y)
	m.player.restore_motion(Vector3(ep.x, exit_height + 0.1, ep.y))
	await _wait(0.4)
	_ok(m.player.is_on_floor() and absf(m.player.global_position.y - exit_height) < 0.08, "出门落点能稳定站立，不与新屋碰撞")
	_ok(str(m._door_target().get("id", "")) == "hut_0", "真实门前仍能触发进屋")
	m._interact()
	await _wait(0.8)
	_ok(m.house_id == "hut_0" and m.player.indoor, "替换小屋仍可进入原室内")
	m._exit_house()
	await _wait(0.8)
	_ok(m.house_id == "" and not m.player.indoor, "替换小屋仍可正常出门")
	_ok(Vector2(m.player.global_position.x, m.player.global_position.z).distance_to(ep) < 0.08, "出门落在新的门廊外侧")
	# 从出门点实际走向门廊，不用传送到台阶上冒充可达。
	var face := InteriorS.door_dir(h.rot)
	m.player.yaw = 0.0
	GameBus.touch_move = Vector2(-face.x, -face.y)
	var start: Vector3 = m.player.global_position
	var reachable := false
	for i in 60:
		await _wait(0.05)
		var local: Vector3 = hut.to_local(m.player.global_position)
		if local.z < 2.7:
			reachable = true
			break
	GameBus.touch_move = Vector2.ZERO
	print("WALK start=%s end=%s local=%s" % [start, m.player.global_position, hut.to_local(m.player.global_position)])
	_ok(reachable and m.player.global_position.distance_to(start) > 0.8, "玩家能从出口走到门廊前")
	if installed:
		_ok(absf(hut.to_local(m.player.global_position).x) < 0.15 and m.player.is_on_floor() and str(m._door_target().get("id", "")) == "hut_0", "玩家可实际走到前门中轴并触发交互")
	var data: Array = m._serialize_props()
	_ok(str(data[0].get("visual", "")) == "emace_crate", "存档保存木箱的外观身份")
	m._restore_props(data)
	await _wait(0.1)
	_ok(m.physics_props[0].has_node("AssetVisual") == installed, "读档恢复第一只木箱的外观")
	for entry in data:
		entry.erase("visual")
	m._restore_props(data)
	await _wait(0.1)
	_ok(m.physics_props.size() == data.size() and m.physics_props[0].visual == "emace_crate" and m.physics_props[1].visual == "emace_crate", "旧存档全部迁移外观且数量不变")
	for index in [0, 2, 3]:
		var house: Dictionary = m.houses[index]
		var exit: Vector2 = house.get("exit_point", InteriorS.exit_point(house.pos, house.rot, house.kind))
		m.player.restore_motion(Vector3(exit.x, m.terrain.height_at(exit.x, exit.y) + 0.1, exit.y))
		await _wait(0.4)
		_ok(str(m._door_target().get("id", "")) == house.id and m.player.is_on_floor(), house.id + "出口站稳并能触发真实门")
		m._interact()
		await _wait(0.8)
		_ok(m.house_id == house.id and m.player.indoor, house.id + "可进入")
		m._exit_house()
		await _wait(0.8)
		_ok(not m.player.indoor and m.house_id == "" and Vector2(m.player.global_position.x, m.player.global_position.z).distance_to(exit) < 0.08, house.id + "可退出并回到新门廊外")
