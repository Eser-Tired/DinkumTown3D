extends Node
## 水域专项自检 —— 水面覆盖完整性 / 岸线闭合 / 游泳 / 潜水 / 憋气 / 水中禁用动作
##
## 运行：
##   Godot --headless --path <项目> --scene res://tools/water_check.tscn --quit-after 600

var m: Node3D
var fails := 0
var checks := 0
var log_lines: Array = []


func _ready() -> void:
	_log("=== water_check start ===")
	_flush()
	var MS = load("res://scripts/main.gd")
	if MS == null:
		_log("FATAL 无法加载 main.gd")
		_flush()
		get_tree().quit(2)
		return
	m = MS.new()
	# 固定种子：本脚本有大量具体数值期望（湖心水深、河道折点数、岸线半径），
	# 换个种子这些数字就全变了。种子随机性由脚本末尾那组确定性断言单独负责。
	m.forced_map_seed = 20260921
	add_child(m)
	for i in 12:
		await get_tree().process_frame

	await _run()
	var tail := "==== WATER CHECK DONE checks=%d fails=%d ====" % [checks, fails]
	print(tail)
	_log(tail)
	_flush()
	get_tree().quit(1 if fails > 0 else 0)


func _log(s: String) -> void:
	log_lines.append(s)


func _flush() -> void:
	var path := "res://water_check.log"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		path = "user://water_check.log"
		f = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(log_lines) + "\n")
		f.close()


func _ok(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("PASS " + msg)
		_log("PASS " + msg)
	else:
		fails += 1
		print("FAIL " + msg)
		_log("FAIL " + msg)
	_flush()


func _eq(got, want, msg: String) -> void:
	var ok: bool = (got == want)
	if not ok:
		_ok(false, "%s（期望 %s 实得 %s）" % [msg, str(want), str(got)])
	else:
		_ok(true, msg)


func _run() -> void:
	var TS = load("res://scripts/terrain.gd")
	var terr = m.terrain
	var lake: Vector2 = TS.LAKE_C
	var wy: float = terr.water_level()
	var rim: float = float(TS.LAKE_R) + float(TS.SHORE)
	var step: float = float(TS.SIZE) / float(TS.GRID)

	# ——————— 1) 水深查询 ———————
	_ok(terr.water_depth_at(lake.x, lake.y) > 4.0,
		"湖心水深超过 4 米（实得 %.2f）" % terr.water_depth_at(lake.x, lake.y))
	_eq(terr.water_depth_at(0.0, 0.0), 0.0, "镇中心没有水")
	_ok(terr.water_depth_at(lake.x + rim - 2.0, lake.y) >= 0.0, "水深不会为负")
	# 【不能再写"离湖够远就没水"】现在还有河，离湖远不等于没水。
	# 换一个明确既远离湖、又远离河的点：地图西北角。
	# 河道的起点方位以「湖指向小镇的反方向」为中心，永远到不了西北角。
	var far_pt := Vector2(-96.0, -96.0)
	_ok(not terr.in_water(far_pt.x, far_pt.y), "远离湖与河的地方不属于水体范围")
	_eq(terr.water_depth_at(far_pt.x, far_pt.y), 0.0, "远离湖与河的地方没有水")

	# ——————— 2) 岸线闭合：湖盆之外不再低于水位 ———————
	# 这是"湖有岸"的前提。地形基准高度改过之后必须重新确认这条，
	# 否则水面会一路蔓延出湖盆、撞上扫描范围的硬边。
	# 【为什么要放过有河的方位】河是合法地"低于水位"的一类地形——
	# 湖盆外本该处处高于水位，唯独河流汇入的那一段例外。
	# 不排除的话，这条断言会把正确的河道误判成"岸没闭合"。
	var beyond := 0
	for k in 24:
		var a := TAU * float(k) / 24.0
		var r := rim
		var crossed_river := false
		while r < rim + 42.0:
			var px := lake.x + cos(a) * r
			var pz := lake.y + sin(a) * r
			if terr.river_dist(px, pz) < 1e8:
				crossed_river = true
			if terr.height_at(px, pz) > wy:
				break
			r += 0.5
		if r >= rim + 42.0 and not crossed_river:
			beyond += 1
	_eq(beyond, 0, "湖盆外缘之外处处高于水位（岸线闭合，河流汇入口除外）")

	# ——————— 3) 水面覆盖完整性 ———————
	# 【为什么这条最重要】用户看到的问题就是"有的地方有水、有的地方没水"。
	# 逐点比对"地形在水下"与"这里有水面"，任何一处漏盖都会被抓出来。
	var bare := 0            ## 地形在水下、却没有水面
	var floating := 0        ## 有水面、但地形明显高于水位（悬空的水）
	var covered := 0
	var reach := rim + step * 2.0
	var x := lake.x - reach
	while x <= lake.x + reach:
		var z := lake.y - reach
		while z <= lake.y + reach:
			if Vector2(x, z).distance_to(lake) <= rim:
				# terr 是 Node3D，方法返回值是 Variant，必须显式标类型
				var h: float = terr.height_at(x, z)
				var surf: bool = terr.water_surface_at(x, z)
				if h < wy - 0.05:
					if surf:
						covered += 1
					else:
						bare += 1
				elif surf and h > wy + 0.30:
					floating += 1
			z += step * 0.5
		x += step * 0.5
	_eq(bare, 0, "水下处处有水面，没有断水（采样 %d 点）" % covered)
	var wet_total := covered + floating
	var float_pct := 0.0 if wet_total == 0 else float(floating) / float(wet_total) * 100.0
	# 允许少量：水面按格子生成，岸线那一圈格子必然有一小部分探进陆地（约 1 个格子宽）
	_ok(float_pct < 15.0,
		"悬空水面占比很低（%.1f%%，%d/%d）—— 预期只有岸边一圈" % [float_pct, floating, wet_total])

	# ——————— 3b) 河流：覆盖稳定性 ———————
	# 用户的要求是"保证河流覆盖的稳定性"。地形是随机的，河必须照样贯通，
	# 所以这里沿中心线逐点验证——而不是只看一眼截图。
	var rp: PackedVector2Array = terr.river_pts
	_ok(rp.size() >= 2, "河道路径已生成（%d 个折点）" % rp.size())
	if rp.size() >= 2:
		var dry := 0
		var min_depth := 1e9
		var samples := 0
		for i in range(rp.size() - 1):
			var a2: Vector2 = rp[i]
			var b2: Vector2 = rp[i + 1]
			var n := maxi(1, int(ceil(a2.distance_to(b2) / 2.0)))
			for k in range(n):
				var p := a2.lerp(b2, float(k) / float(n))
				var d: float = terr.water_depth_at(p.x, p.y)
				samples += 1
				if d <= 0.0:
					dry += 1
				min_depth = minf(min_depth, d)
		_eq(dry, 0, "河道中心线处处有水，没有断流（采样 %d 点）" % samples)
		# 河床被 min() 强制削到 RIVER_BED_Y，所以最浅也有 2 米出头
		_ok(min_depth > 2.0, "河道最浅处 %.2f 米（足以游泳）" % min_depth)

		# 河不能穿过小镇——游戏里没有桥，穿镇等于把镇子切成两半
		var min_town_d := 1e9
		for q in rp:
			min_town_d = minf(min_town_d, (q as Vector2).distance_to(Vector2(TS.TOWN_CENTER)))
		var need: float = float(TS.TOWN_R) + 6.0
		_ok(min_town_d > need,
			"河道离小镇中心 %.0f 米 > %.0f 米，不会把镇子切开" % [min_town_d, need])

	# ——————— 3c) 水面不会漏到地图各处 ———————
	# 湖与河道之外不该再有低于水位的地方，否则水面会从水体里"漏"出去——
	# 这正是改动前水面一路蔓延到地图边缘的原因。
	var strays := 0
	var sx := -122.0
	while sx <= 122.0:
		var sz := -122.0
		while sz <= 122.0:
			if Vector2(sx, sz).distance_to(lake) > rim \
					and terr.river_dist(sx, sz) > 1e8 \
					and terr.height_at(sx, sz) <= wy:
				strays += 1
			sz += 4.0
		sx += 4.0
	_eq(strays, 0, "湖与河道之外没有低于水位的地方（水面不漏）")

	# ——————— 4) 游泳 ———————
	var player = m.player
	# 直接读脚本常量，别把数字抄一遍——抄了就会在调手感时忘记同步
	var PS = load("res://scripts/player.gd")
	var flt: float = wy - float(PS.FLOAT_SUBMERGE)
	player.jump_h = 0.0
	player.jump_v = 0.0
	player.global_position = Vector3(lake.x, wy + 4.0, lake.y)
	# 给足收敛时间：漂浮是插值趋近，不是瞬移。容差 0.30 米才算真的"稳在水面"，
	# 放宽到 0.45 的话收敛慢一半也能蒙混过去。
	await get_tree().create_timer(1.8).timeout
	_ok(player.swimming, "湖心进入游泳状态")
	var y_float: float = player.global_position.y
	_ok(absf(y_float - flt) < 0.30,
		"漂在水面附近（实得 %.2f，期望 ≈ %.2f，差 %.2f）" % [y_float, flt, absf(y_float - flt)])
	var bed: float = terr.height_at(lake.x, lake.y)
	_ok(y_float > bed + 3.0, "没有沉到湖底（湖底 %.2f，玩家 %.2f）" % [bed, y_float])
	_ok(not player.head_underwater(), "漂浮时头露出水面（可以呼吸）")

	m._update_water_hud()
	_ok(not m.hud.breath_panel.visible, "漂在水面时不显示憋气条")

	# ——————— 5) 潜水与憋气 ———————
	GameBus.touch_dive = true
	await get_tree().create_timer(1.4).timeout
	var y_dive: float = player.global_position.y
	_ok(player.diving, "按住「潜」进入下潜状态")
	_ok(y_dive < y_float - 1.0, "下潜让身体下沉（%.2f -> %.2f）" % [y_float, y_dive])
	_ok(player.head_underwater(), "下潜后头部没入水中")
	_ok(player.breath < 0.98, "潜水时憋气在消耗（剩 %.0f%%）" % (player.breath * 100.0))
	m._update_water_hud()
	_ok(m.hud.breath_panel.visible, "憋气时显示憋气条")
	_ok(m.hud.uw_overlay.visible, "相机没入水面后显示水下遮罩")

	# ——————— 6) 水中禁用采集 / 建造 ———————
	var wood_before := int(m.inv.get("wood", 0))
	m._harvest()
	_eq(int(m.inv.get("wood", 0)), wood_before, "水中不能采集")
	m._do_action("build")
	_ok(not m.build_mode, "水中不能进入建造模式")

	# ——————— 7) 松开上浮 + 出水 ———————
	GameBus.touch_dive = false
	await get_tree().create_timer(1.6).timeout
	_ok(player.global_position.y > y_dive + 1.0,
		"松开「潜」后自动上浮（%.2f -> %.2f）" % [y_dive, player.global_position.y])
	_ok(player.breath > 0.5, "浮出水面后憋气开始恢复（%.0f%%）" % (player.breath * 100.0))

	# 走到岸上
	player.global_position = Vector3(lake.x, wy + 2.0, lake.y + rim + 10.0)
	await get_tree().create_timer(1.0).timeout
	_ok(not player.swimming, "上岸后退出游泳状态")
	var gy: float = terr.height_at(player.global_position.x, player.global_position.z)
	_ok(absf(player.global_position.y - gy) < 0.35,
		"上岸后重新贴地（地面 %.2f，玩家 %.2f）" % [gy, player.global_position.y])
	m._update_water_hud()
	_ok(not m.hud.uw_overlay.visible, "出水后水下遮罩关闭")

	GameBus.touch_dive = false

	# ——————— 8) 地图随机生成 = 种子确定性 ———————
	# "随机地图"必须建立在"同种子 = 同地图"之上，否则存档里记的种子毫无意义，
	# 读档会开到另一片大陆。这两条一起才能定义"随机但可复原"。
	#
	# 不 add_child：不挂进树就不会生成地面网格，只算高度函数，快得多。
	var t_same = TS.new()
	t_same.set_map_seed(m.map_seed)
	var same_diff := 0.0
	for i in 40:
		var px2 := -100.0 + float(i) * 5.0
		same_diff = maxf(same_diff, absf(float(t_same.height_at(px2, 33.0))
			- float(terr.height_at(px2, 33.0))))
	_ok(same_diff < 0.0001, "同一种子重建出完全一致的地形（最大偏差 %.6f 米）" % same_diff)

	var t_other = TS.new()
	t_other.set_map_seed(m.map_seed + 12345)
	# 【为什么要铺二维网格】低频噪声的波长约 139 米，地图才 260 米宽——
	# 沿一条线取 40 个点只覆盖了不到两个波，样本严重偏斜，会得出
	# "换种子地图差不多"的错误结论。铺满整张图才代表"这是另一张地图"。
	var diff := 0
	var total := 0
	var abs_sum := 0.0
	for gx in range(-6, 7):
		for gz in range(-6, 7):
			var px3 := float(gx) * 19.0
			var pz3 := float(gz) * 19.0
			var d3 := absf(float(t_other.height_at(px3, pz3))
				- float(terr.height_at(px3, pz3)))
			total += 1
			abs_sum += d3
			if d3 > 0.5:
				diff += 1
	var mean_diff := abs_sum / float(total)
	_ok(diff > total / 2,
		"换个种子后多数采样点地形不同（%d/%d 个点差异 > 0.5 米）" % [diff, total])
	_ok(mean_diff > 1.0, "换个种子后地形平均相差 %.2f 米" % mean_diff)

	var rp_other: PackedVector2Array = t_other.river_pts
	_ok(rp_other.size() >= 2 and rp_other[0].distance_to(rp[0]) > 1.0,
		"换个种子河道也跟着变（起点位移 %.1f 米）" % rp_other[0].distance_to(rp[0]))

	# 河道换了，但"处处有水"这条必须仍然成立——这才是稳定性的完整含义
	var dry_other := 0
	for i in range(rp_other.size() - 1):
		var pa: Vector2 = rp_other[i]
		var pb: Vector2 = rp_other[i + 1]
		var nn := maxi(1, int(ceil(pa.distance_to(pb) / 4.0)))
		for k in range(nn):
			var p2 := pa.lerp(pb, float(k) / float(nn))
			if float(t_other.water_depth_at(p2.x, p2.y)) <= 0.0:
				dry_other += 1
	_eq(dry_other, 0, "换个种子后河道依然不断流")

	t_same.free()
	t_other.free()

	# ——————— 9) 种子必须能存档 ———————
	# 读档流程要在地形生成【之前】拿到种子，所以它走 __meta 而不是模块数据。
	var SaveS = load("res://scripts/save_system.gd")
	m.save_sys.save(2)
	var back: int = SaveS.peek_terrain_seed(2)
	_eq(back, int(GameBus.terrain_seed), "存档 __meta 记下了地图种子，且能预读回来")
