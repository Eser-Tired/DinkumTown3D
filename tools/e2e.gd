extends Node
## 端到端存档往返测试 —— 只在验证副本里跑，不进主项目
## 运行：Godot --headless --path <副本> res://tools/e2e.tscn

var m: Node3D
var fails := 0


func _ready() -> void:
	var MS = load("res://scripts/main.gd")
	m = MS.new()
	# 固定地图种子：本脚本里全是写死的期望值（资源数、坐标、存档往返比对），
	# 地图一随机就变成碰运气。要测的是"存读档是否等价"，不是"随机是否好看"。
	m.forced_map_seed = 20260921
	add_child(m)
	for i in 8:
		await get_tree().process_frame

	# —— 构造存档点状态 ——
	m.give_item("wood", 25)
	m.give_item("stone", 12)
	m.give_item("fiber", 10)
	m.dn.day_count = 5
	m.dn.time = 0.42
	m.player.global_position = Vector3(-14.0, 3.0, 7.0)

	var plots: Array = m.farm.plots
	var p0: Dictionary = plots[0]
	var pp0: Vector2 = p0["pos"]
	m.player.global_position = Vector3(pp0.x, m.terrain.height_at(pp0.x, pp0.y) + 0.4, pp0.y)
	m.farm.interact(m.player.global_position)          # 锄 plot0

	var p1: Dictionary = plots[1]
	var pp1: Vector2 = p1["pos"]
	m.player.global_position = Vector3(pp1.x, m.terrain.height_at(pp1.x, pp1.y) + 0.4, pp1.y)
	m.farm.interact(m.player.global_position)          # 锄 plot1
	m.farm.interact(m.player.global_position)          # 播种 plot1

	var cf: Node3D = m._make_build("campfire")
	cf.set_meta("player_built", true)
	m.built_items.append({"kind": "campfire", "x": -20.0, "z": 2.0, "rot": 0.5})
	m._place(cf, -20.0, 2.0, 0.5)

	if m.resources.size() > 0:
		m._collect_resource(m.resources[0])            # 存档前采一个

	for i in 6:
		await get_tree().process_frame

	var A := _snap()
	_check(m.save_sys.save(1), "save(1) 返回 true")

	# —— 破坏现场（不采集，避免不可逆差异：读档不复活资源节点） ——
	m.inv["wood"] = 1
	m.inv["food"] = 99
	m.dn.day_count = 12
	m.dn.time = 0.90
	m.player.global_position = Vector3(60.0, 4.0, 60.0)
	var lp: Node3D = m._make_build("lamp")
	lp.set_meta("player_built", true)
	m.built_items.append({"kind": "lamp", "x": -22.0, "z": 4.0, "rot": 0.0})
	m._place(lp, -22.0, 4.0, 0.0)
	for i in 6:
		await get_tree().process_frame

	_check(m.save_sys.load(1), "load(1) 返回 true")
	for i in 8:
		await get_tree().process_frame

	var B := _snap()
	_cmp(A, B)
	print("==== E2E DONE fails=%d ====" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _snap() -> Dictionary:
	var inv_d: Dictionary = {}
	for k in m.inv:
		inv_d[k] = int(m.inv[k])
	var pp: Vector3 = m.player.global_position
	var plots_arr: Array = []
	for pl in m.farm.plots:
		plots_arr.append([int(pl["state"]), String(pl["crop"])])
	var s = m.season
	return {
		"wood": int(inv_d.get("wood", 0)),
		"stone": int(inv_d.get("stone", 0)),
		"fiber": int(inv_d.get("fiber", 0)),
		"food": int(inv_d.get("food", 0)),
		"day": int(m.dn.day_count),
		"time": float(m.dn.time),
		"px": pp.x,
		"py": pp.y,
		"pz": pp.z,
		"res_count": m.resources.size(),
		"built_count": m.built_items.size(),
		"season": int(s.season),
		"weather": String(s.weather),
		"plots": plots_arr,
	}


func _cmp(a: Dictionary, b: Dictionary) -> void:
	for k in ["wood", "stone", "fiber", "food", "day", "res_count", "built_count", "season", "weather"]:
		_eq(k, a[k], b[k])
	_close("time", float(a["time"]), float(b["time"]), 0.02)
	for k in ["px", "py", "pz"]:
		_close(k, float(a[k]), float(b[k]), 0.06)
	var pa: Array = a["plots"]
	var pb: Array = b["plots"]
	_eq("plots_count", pa.size(), pb.size())
	for i in mini(pa.size(), pb.size()):
		_eq("plot%d" % i, str(pa[i]), str(pb[i]))


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
