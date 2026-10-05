extends Node
## 用 preload 而不是 class_name：新建的脚本还没进全局类缓存时，
## 直接写 InteriorSystem 会报 "not declared in the current scope"。
const InteriorS := preload("res://scripts/interior.gd")
## 进屋流程自检：门的判定、传送、室内贴地与边界、出门回位、存档坐标、帐篷可进入
## 运行：Godot --headless --path . --scene res://tools/interior_check.tscn --quit-after 600

var m: Node3D
var fails := 0

## 等过场真正结束。
## 【必须按真实时间等，不能数帧】进屋/出门都有一段 0.44 秒的淡入淡出，
## 而 headless 没有渲染、帧率能跑到上千 fps，数 400 帧可能才过去零点几秒——
## 过场没走完就往下断言，下一次 _interact 又被 busy 挡掉，于是所有状态慢一拍。
func _wait_warp() -> void:
	for i in 80:
		await get_tree().create_timer(0.05).timeout
		if m.get_tree().paused:
			# 有模态面板没关：warp 的 Tween 跟随节点暂停状态，会一直停着不动，
			# 后面的断言就会集体错位。这里立刻报出来，别静默等满 4 秒。
			fails += 1
			print("FAIL 过场卡住：游戏仍处于暂停（有面板没关）")
			return
		if not m.interior.busy:
			return


func _ready() -> void:
	var MS = load("res://scripts/main.gd")
	m = MS.new()
	# 固定地图种子：门的位置、帐篷落点全是从地形派生的，
	# 地图一随机这些数就对不上，测的就不是同一件事了。
	m.forced_map_seed = 20260921
	add_child(m)
	await _frames(10)


	# houses 的登记顺序：shop_0, hut_0..2, tent_camp_0..2
	await _check_registry()
	await _check_door_reach(m.houses[0] as Dictionary)   # 杂货铺
	await _check_door_reach(m.houses[1] as Dictionary)   # 铁皮小屋
	await _check_enter_exit(m.houses[1] as Dictionary)
	await _check_enter_exit(m.houses[4] as Dictionary)   # 营地帐篷：圆形室内，尺寸又不一样
	await _check_tent()                                  # 玩家自建帐篷
	await _check_reload_keeps_camp()
	await _check_sleep()                                 # 睡觉放最后：它会推进天数与季节

	print("==== INTERIOR DONE fails=%d ====" % fails)
	get_tree().quit(1 if fails > 0 else 0)


# ——————————————— 登记与门位置 ———————————————
func _check_registry() -> void:
	# 3 间铁皮小屋 + 1 间杂货铺 + 3 顶营地帐篷
	_eq("houses_count", m.houses.size(), 7)

	var kinds := {}
	for h in m.houses:
		var hs: Dictionary = h
		kinds[str(hs.get("kind", ""))] = int(kinds.get(str(hs.get("kind", "")), 0)) + 1
	_eq("hut_count", int(kinds.get("hut", 0)), 3)
	_eq("shop_count", int(kinds.get("shop", 0)), 1)
	_eq("camp_tent_count", int(kinds.get("tent", 0)), 3)

	# id 必须两两不同：营地帐篷和玩家自建帐篷都叫 tent，
	# 撞了 id 会两顶共用同一间室内（进去看到的是别人的屋子）
	var seen := {}
	var dup := 0
	for h in m.houses:
		var hid := str((h as Dictionary).get("id", ""))
		if seen.has(hid):
			dup += 1
		seen[hid] = true
	_eq("house_id_dups", dup, 0)

	for h in m.houses:
		var hs: Dictionary = h
		var id := str(hs.get("id", ""))
		var kind := str(hs.get("kind", ""))
		var pos: Vector2 = hs.get("pos", Vector2.ZERO)
		var rot := float(hs.get("rot", 0.0))
		var sp: Dictionary = InteriorS.spec_of(kind)
		_check(not sp.is_empty(), "%s 有室内规格" % id)

		# 门必须在屋子正面：门点到中心的距离就该是 door_z
		var dp := InteriorS.door_point(pos, rot, kind)
		_close("%s_door_dist" % id, dp.distance_to(pos), float(sp.get("door_z", 0.0)), 0.001)

		# 门不能泡在水里（地形基准高度改过之后，一切都得跟水位比）
		_check(m.terrain.water_depth_at(dp.x, dp.y) <= 0.0, "%s 门不在水里" % id)

		# 出门落点必须落在房屋避让圆之外，否则一出门就被顶开
		var r_col: float = 0.0
		for c in m.colliders:
			if Vector2(c.pos.x, c.pos.y).distance_to(pos) < 0.01:
				r_col = float(c.r)
				break
		var ep := InteriorS.exit_point(pos, rot, kind)
		_check(ep.distance_to(pos) > r_col + 0.42, "%s 出门点不被避让圆顶开 (%.2f > %.2f)"
			% [id, ep.distance_to(pos), r_col + 0.42])


# ——————————————— 门口判定 ———————————————
func _check_door_reach(h: Dictionary) -> void:
	var kind := str(h.get("kind", "hut"))
	var pos: Vector2 = h.get("pos", Vector2.ZERO)
	var rot := float(h.get("rot", 0.0))
	var id := str(h.get("id", ""))

	# 站在门外：应命中
	var ep := InteriorS.exit_point(pos, rot, kind)
	await _stand(Vector3(ep.x, 0.0, ep.y))
	_eq("%s_门口命中" % id, str(m._door_target().get("id", "")), id)

	# 站在屋后同样距离：门在另一侧，不该命中
	await _stand(Vector3(pos.x, 0.0, pos.y) - Vector3(InteriorS.door_dir(rot).x, 0.0,
		InteriorS.door_dir(rot).y) * 5.2)
	_check(m._door_target().is_empty(), "%s 屋后不触发" % id)

	# 离得远：不该命中
	await _stand(Vector3(pos.x + 18.0, 0.0, pos.y + 18.0))
	_check(m._door_target().is_empty(), "%s 远处不触发" % id)


# ——————————————— 进出流程 ———————————————
func _check_enter_exit(h: Dictionary) -> void:
	var kind := str(h.get("kind", "hut"))
	var pos: Vector2 = h.get("pos", Vector2.ZERO)
	var rot := float(h.get("rot", 0.0))
	var id := str(h.get("id", ""))
	var ep := InteriorS.exit_point(pos, rot, kind)

	await _stand(Vector3(ep.x, 0.0, ep.y))
	m._interact()
	await _wait_warp()


	_eq("%s_进入" % id, m.house_id, id)
	_check(m.player.indoor, "%s player.indoor" % id)
	_close("%s_室内地面" % id, m.player.global_position.y, InteriorS.FLOOR_Y, 0.02)

	# 多跑几帧：贴地必须稳定，不能一帧高一帧低
	await _frames(20)

	_close("%s_室内地面_稳定" % id, m.player.global_position.y, InteriorS.FLOOR_Y, 0.02)

	# 屋里不该出现任何水域状态
	_check(not m.player.swimming, "%s 室内不游泳" % id)
	_check(not m.player.head_underwater(), "%s 室内头不入水" % id)
	_check(not m.player.camera_underwater(), "%s 室内相机不入水" % id)

	# 屋里有灯，而且不能被昼夜系统当成夜灯收走（白天会被整体关掉）
	var sp: Dictionary = m.interior.space_of(id)
	var node: Node3D = sp.get("node", null)
	# 合并实体物理后，不能只断言 y=40；必须实际落在地板上并能起跳再落地。
	_check(m.player.is_on_floor(), "%s 室内实体地板支撑角色" % id)
	GameBus.touch_jump_edge = true
	await _frames(8)
	_check(not m.player.is_on_floor() and m.player.global_position.y > InteriorS.FLOOR_Y + 0.2,
		"%s 室内真实跳跃" % id)
	var airborne_save: Dictionary = m.serialize()
	_check(airborne_save.get("player_velocity", []) == [0.0, 0.0, 0.0],
		"%s 室内存档不把跳跃速度带到门外" % id)
	await _frames(60)
	_check(m.player.is_on_floor(), "%s 室内跳跃后重新落地" % id)
	if kind == "hut":
		var bed: Vector3 = sp.get("bed", Vector3.ZERO)
		m.player.restore_motion(bed + Vector3(1.6, 0.02, 0))
		await _frames(15)
		GameBus.touch_move = Vector2(-1, 0)
		await _frames(40)
		GameBus.touch_move = Vector2.ZERO
		_check(m.player.get_slide_collision_count() > 0 and m.player.global_position.x > bed.x + 0.6,
			"%s 持续走向床侧，被实体家具阻挡" % id)
		m.player.restore_motion(sp.get("spawn", Vector3.ZERO))
		await _frames(20)
	var lights := 0
	var night := 0
	if node != null:
		for n in _all_nodes(node):
			if n is OmniLight3D:
				lights += 1
				if n.has_meta("night_light"):
					night += 1
	_check(lights >= 2, "%s 室内灯数=%d" % [id, lights])
	_eq("%s_夜灯误收" % id, night, 0)

	# 越界推进：室内边界必须把人挡住
	var center: Vector2 = sp.get("center", Vector2.ZERO)
	var half: Vector2 = sp.get("half", Vector2.ZERO)
	m.player.global_position = Vector3(center.x + 60.0, InteriorS.FLOOR_Y, center.y + 60.0)
	await get_tree().process_frame
	_check(absf(m.player.global_position.x - center.x) <= half.x + 0.01
		and absf(m.player.global_position.z - center.y) <= half.y + 0.01,
		"%s 室内边界生效 (%.2f/%.2f vs %.2f/%.2f)" % [id,
			absf(m.player.global_position.x - center.x), absf(m.player.global_position.z - center.y),
			half.x, half.y])

	# 屋里不许建造
	m._do_action("build")
	_check(not m.build_mode, "%s 室内禁止建造" % id)

	# 存档写的是门外那个点，不是飞地坐标
	var ser: Dictionary = m.serialize()
	var sp2: Array = ser.get("pos", [0.0, 0.0, 0.0])
	_close("%s_存档pos.x" % id, float(sp2[0]), m.outdoor_exit.x, 0.01)
	_close("%s_存档pos.z" % id, float(sp2[2]), m.outdoor_exit.z, 0.01)

	# —— 出门 ——
	m._interact()
	await _wait_warp()


	_eq("%s_已出门" % id, m.house_id, "")
	_check(not m.player.indoor, "%s 出门后 indoor=false" % id)
	var pp: Vector3 = m.player.global_position
	_close("%s_出门点x" % id, pp.x, m.outdoor_exit.x, 0.6)
	_close("%s_出门点z" % id, pp.z, m.outdoor_exit.z, 0.6)
	_close("%s_出门贴地" % id, pp.y, m.terrain.height_at(pp.x, pp.z), 0.25)
	_check(m.player.obstacles == m.colliders, "%s 出门后恢复户外避让圆" % id)


# ——————————————— 玩家自建的帐篷 ———————————————
func _check_tent() -> void:
	# m 是动态拿到的 Node3D，返回值没有静态类型，这里必须显式标注
	var spot: Vector2 = m._random_spot(45.0, 45.0, 6.0)
	_check(spot != Vector2.ZERO, "找到空地放帐篷")
	if spot == Vector2.ZERO:
		return

	var bn: Node3D = m._make_build("tent")
	bn.set_meta("player_built", true)
	m._place(bn, spot.x, spot.y, 0.4)
	m.built_items.append({"kind": "tent", "x": spot.x, "z": spot.y, "rot": 0.4})
	var tid: String = m._register_house("tent", spot, 0.4, m.built_items.size() - 1, "", true)
	_check(tid != "", "帐篷已登记 (%s)" % tid)
	await get_tree().process_frame

	# 圆形室内的边界是半径而不是矩形，单独验一次
	var ep := InteriorS.exit_point(spot, 0.4, "tent")
	await _stand(Vector3(ep.x, 0.0, ep.y))
	_eq("帐篷_门口命中", str(m._door_target().get("id", "")), tid)

	m._interact()
	await _wait_warp()

	_eq("帐篷_进入", m.house_id, tid)
	_close("帐篷_室内地面", m.player.global_position.y, InteriorS.FLOOR_Y, 0.02)

	m._interact()
	await _wait_warp()

	_eq("帐篷_已出门", m.house_id, "")


# ——————————————— 睡觉 ———————————————
## 床边判定 / 面板开关 / 时间推进 / 跨天与同天的区别
func _check_sleep() -> void:
	var h := _house_by_id("hut_0")
	_check(not h.is_empty(), "找到 hut_0")
	if h.is_empty():
		return
	var id := str(h.get("id", ""))

	# 进屋
	var kind := str(h.get("kind", "hut"))
	var pos: Vector2 = h.get("pos", Vector2.ZERO)
	var rot := float(h.get("rot", 0.0))
	var ep := InteriorS.exit_point(pos, rot, kind)
	await _stand(Vector3(ep.x, 0.0, ep.y))
	m._interact()
	await _wait_warp()
	_eq("睡觉_已进屋", m.house_id, id)

	# 冻结时间：否则 dn._process 每帧都在推进 time，断言的期望值就没法精确
	m.dn.speed_scale = 0.0

	var sp: Dictionary = m.interior.space_of(id)
	_check(bool(sp.get("can_sleep", false)), "小屋可睡")
	var bed: Vector3 = sp.get("bed", Vector3.ZERO)
	_check(bed != Vector3.ZERO, "小屋有床 %s" % str(bed))

	# 站在床边能睡、走开不能
	m.player.global_position = Vector3(bed.x + 1.5, InteriorS.FLOOR_Y, bed.z)
	await _frames(2)
	_check(m._bed_near(), "站在床边可睡")
	m.player.global_position = Vector3(bed.x + 4.0, InteriorS.FLOOR_Y, bed.z)
	await _frames(2)
	_check(not m._bed_near(), "离床远了不可睡")

	# 面板：打开要暂停，选完要解除暂停并推进时间
	m.player.global_position = Vector3(bed.x + 1.5, InteriorS.FLOOR_Y, bed.z)
	await _frames(2)
	m.dn.time = 0.10                      # 02:24 → 06:00 还在今天
	var day0: int = m.dn.day_count
	m.sleep_panel.open(func(): return m.dn.time * 24.0)
	_check(m.sleep_panel.is_open(), "睡觉面板已打开")
	_check(m.get_tree().paused, "面板打开时游戏暂停")
	m.sleep_panel._pick(6.0)
	_check(not m.sleep_panel.is_open(), "选完自动关闭")
	_check(not m.get_tree().paused, "关闭后解除暂停")
	await _wait_warp()
	_close("同天睡到 06:00", m.dn.time * 24.0, 6.0, 0.01)
	_eq("同一天不跨天", m.dn.day_count, day0)

	# 跨天：22:00 睡到 06:00
	m.dn.time = 22.0 / 24.0
	var day1: int = m.dn.day_count
	m.sleep_panel.open(func(): return m.dn.time * 24.0)
	m.sleep_panel._pick(6.0)
	await _wait_warp()
	_close("跨天睡到 06:00", m.dn.time * 24.0, 6.0, 0.01)
	_eq("跨天 day+1", m.dn.day_count, day1 + 1)
	# 季节模块靠比较 day_count 自己推进，给它几帧走完
	await _frames(6)

	# 出门。注意必须先从床边走开：床边的 F 是"睡觉"不是"出门"（设计如此，
	# 面板里也有「再想想」可以退出来）。这里按真实操作走。
	m.player.global_position = Vector3(bed.x + 3.2, InteriorS.FLOOR_Y, bed.z + 1.0)
	await _frames(2)
	_check(not m._bed_near(), "走开后不再判定床边")
	m._interact()
	await _wait_warp()
	_eq("睡觉_已出门", m.house_id, "")

	m.dn.speed_scale = 1.0

	# 杂货铺没床、帐篷（睡袋）能睡
	var shop_sp: Dictionary = m.interior.ensure("shop_0", "shop", m.map_seed)
	_check(not bool(shop_sp.get("can_sleep", true)), "杂货铺不能睡")

	# 帐篷里出生点必须落在睡袋判定圈【外】：
	# 落在里面的话，进门第一下按 F 是"睡觉"不是"出门"，玩家会被困在帐篷里。
	var th := _house_by_id("tent_camp_0")
	_check(not th.is_empty(), "找到 tent_camp_0")
	if not th.is_empty():
		var tk := str(th.get("kind", "tent"))
		var tp: Vector2 = th.get("pos", Vector2.ZERO)
		var tr := float(th.get("rot", 0.0))
		var tep := InteriorS.exit_point(tp, tr, tk)
		await _stand(Vector3(tep.x, 0.0, tep.y))
		m._interact()
		await _wait_warp()
		_eq("帐篷_已进屋", m.house_id, "tent_camp_0")
		_check(not m._bed_near(), "帐篷出生点不在睡袋判定圈内")
		_check(bool(m.interior.space_of("tent_camp_0").get("can_sleep", false)), "帐篷睡袋能睡")
		m._interact()
		await _wait_warp()
		_eq("帐篷_按 F 能出门", m.house_id, "")


# ——————————————— 读档后场景自带的建筑不能丢 ———————————————
## 读档会整批重建"玩家建造物"，houses 也跟着重建。
## 【为什么必须断言这个】清旧建造物时如果按 kind 过滤（曾经就是按 kind == "tent"），
## 会把镇上的帐篷营地一起删掉——而营地不随存档重建，读档后就再也进不去，
## 而且不报任何错，只有真去按 F 才发现门没了。
func _check_reload_keeps_camp() -> void:
	_eq("读档前营地数", _camp_count(), 3)
	# 总数含玩家自建的那顶帐篷（前面的用例刚放的），所以跟读档前比而不是写死数字
	var total_before: int = m.houses.size()
	_check(m.save_sys.save(1), "save(1) 返回 true")
	_check(m.save_sys.load(1), "load(1) 返回 true")
	await _frames(10)

	_eq("读档后营地数", _camp_count(), 3)
	_eq("读档后房屋总数", m.houses.size(), total_before)

	var h := _house_by_id("tent_camp_0")
	_check(not h.is_empty(), "读档后仍能找到营地帐篷")
	if h.is_empty():
		return

	var kind := str(h.get("kind", "tent"))
	var pos: Vector2 = h.get("pos", Vector2.ZERO)
	var rot := float(h.get("rot", 0.0))
	var ep := InteriorS.exit_point(pos, rot, kind)
	await _stand(Vector3(ep.x, 0.0, ep.y))
	_eq("读档后营地门口命中", str(m._door_target().get("id", "")), "tent_camp_0")

	m._interact()
	await _wait_warp()
	_eq("读档后营地能进", m.house_id, "tent_camp_0")
	m._interact()
	await _wait_warp()
	_eq("读档后营地能出", m.house_id, "")


func _camp_count() -> int:
	var n := 0
	for h in m.houses:
		if str((h as Dictionary).get("id", "")).begins_with("tent_camp_"):
			n += 1
	return n


func _house_by_id(id: String) -> Dictionary:
	for h in m.houses:
		var hd: Dictionary = h
		if str(hd.get("id", "")) == id:
			return hd
	return {}


# ——————————————— 工具 ———————————————
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## 把玩家摆到某个点并等一帧（让 player._process 重算贴地/避让）
func _stand(p: Vector3) -> void:
	m.player.global_position = Vector3(p.x, m.terrain.height_at(p.x, p.z) + 0.1, p.z)
	await get_tree().process_frame
	await get_tree().process_frame


func _all_nodes(root: Node) -> Array:
	var out := [root]
	for c in root.get_children():
		out.append_array(_all_nodes(c))
	return out


func _eq(k: String, x, y) -> void:
	if x != y:
		fails += 1
		print("FAIL %s: %s != %s" % [k, str(x), str(y)])
	else:
		print("PASS %s = %s" % [k, str(x)])


func _close(k: String, x: float, y: float, eps: float) -> void:
	if absf(x - y) > eps:
		fails += 1
		print("FAIL %s: %f vs %f" % [k, x, y])
	else:
		print("PASS %s ~ %f" % [k, x])


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL " + what)
	else:
		print("PASS " + what)
