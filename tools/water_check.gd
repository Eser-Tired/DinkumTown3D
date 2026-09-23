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
	_eq(terr.water_depth_at(lake.x + rim + 8.0, lake.y), 0.0, "湖区之外没有水")
	_ok(terr.water_depth_at(lake.x + rim - 2.0, lake.y) >= 0.0, "水深不会为负")

	# ——————— 2) 岸线闭合：湖盆之外不再低于水位 ———————
	# 这是"湖有岸"的前提。地形基准高度改过之后必须重新确认这条，
	# 否则水面会一路蔓延出湖盆、撞上扫描范围的硬边。
	var beyond := 0
	for k in 24:
		var a := TAU * float(k) / 24.0
		var r := rim
		while r < rim + 42.0:
			if terr.height_at(lake.x + cos(a) * r, lake.y + sin(a) * r) <= wy:
				beyond += 1
				break
			r += 0.5
	_eq(beyond, 0, "湖盆外缘之外处处高于水位（岸线闭合）")

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
