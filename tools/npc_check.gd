extends Node
## 真实物理帧验证友好村民、步态、范围、交易原子性和旧存档兼容，不读写用户存档。
var m: Node3D
var checks := 0
var fails := 0
func ok(value: bool, message: String) -> void:
	checks += 1
	if not value:
		fails += 1
		print("FAIL ", message)
func frames(count: int) -> void:
	for i in count: await get_tree().physics_frame
func ledger() -> Array: return [m.coins, m.inv.duplicate(), m.shop_stock.duplicate()]
func _ready() -> void:
	m = load("res://scripts/main.gd").new()
	m.forced_map_seed = 20260921
	add_child(m)
	await frames(15)
	ok(m.npcs.size() == 4, "1老板和3村民")
	ok(m.resources.size() == 191, "NPC不改变旧采集点数量")
	var data := {}
	for npc in m.npcs:
		ok(not npc is Huntable and not m.critters.has(npc), npc.npc_id + "友好且独立于狩猎")
		ok(npc.collision_layer == 32 and m.player.collision_mask & 32 != 0, "友好碰撞层")
		if not OS.get_cmdline_user_args().has("--no-characters"):
			ok(npc.rig.root != null and npc.rig.current == npc.rig.idle_name, "实际骨骼待机")
		data[npc.npc_id] = {"last": npc.global_position, "travel": 0.0, "max_r": 0.0, "max_step": 0.0,
			"wet": 0, "inside": 0, "moving": 0, "idle": 0, "slide": 0, "cells": {}}
	# 60秒、整圆活动范围采样；不能只看一帧或同一条线判断随机游走。
	for i in 3600:
		await get_tree().physics_frame
		for npc in m.npcs:
			var d: Dictionary = data[npc.npc_id]
			var point := Vector2(npc.position.x, npc.position.z)
			var step := Vector2(npc.position.x - d.last.x, npc.position.z - d.last.z)
			d.last = npc.position
			d.travel += step.length()
			d.max_step = maxf(d.max_step, step.length())
			d.max_r = maxf(d.max_r, point.distance_to(npc.home))
			d.cells[Vector2i(floori(point.x), floori(point.y))] = true
			if not npc.merchant:
				if m.terrain.water_depth_at(point.x, point.y) > 0: d.wet += 1
				if m._inside_building(point, 0.12): d.inside += 1
			if npc.actual_speed > 0.08:
				d.moving += 1
				var forward := Vector2(sin(npc.rotation.y), cos(npc.rotation.y))
				if forward.dot(step.normalized()) < 0.95: d.slide += 1
				if npc.rig.root != null and npc.rig.current != "Walk": d.slide += 1
			else:
				d.idle += 1
				if npc.rig.root != null and npc.rig.current != npc.rig.idle_name: d.slide += 1
	for npc in m.npcs:
		var d: Dictionary = data[npc.npc_id]
		print("NPC_MEASURE ", npc.npc_id, " travel=", d.travel, " range=", d.max_r, " max_step=", d.max_step, " cells=", d.cells.size(), " moving=", d.moving, " idle=", d.idle, " slide=", d.slide)
		if npc.merchant:
			ok(d.travel < 0.02, "老板留在柜台后")
		else:
			ok(d.travel > 8 and d.cells.size() >= 5, "村民确实在不同位置行走")
			ok(d.max_r <= 7.01 and d.max_step < 0.024, "守活动半径且无瞬移")
			ok(d.wet == 0 and d.inside == 0, "不进水不穿房屋")
			ok(d.moving > 100 and d.idle > 30 and d.slide == 0, "停走交替、沿身体方向移动且步频同步")
	# 柜台前实际可达位置；不是隔墙直接调用接口。
	var room: Dictionary = m.interior.space_of("shop_0")
	m.player.restore_motion(room.frame.to_global(Vector3(-1.2, 0.22, -0.9)))
	await frames(15)
	ok(m.can_talk(m.merchant), "实际柜台前可交易")
	m._do_action("interact")
	ok(m.trade_panel.is_open() and m.trade_panel.speaker == m.merchant and GameBus.ui_blocking, "键盘/触控共用交易入口")
	var standing: Vector3 = m.player.position
	GameBus.touch_move = Vector2(1,0)
	GameBus.touch_jump_edge = true
	await frames(10)
	ok(m.player.position.distance_to(standing) < 0.01, "交易时残留移动与跳跃输入不能穿透")
	GameBus.touch_move = Vector2.ZERO
	m.coins = 0
	m.inv.wood = 20
	var before := ledger()
	m.trade("wood", true, 1)
	ok(ledger() == before, "缺金币拒绝且不改账")
	m.trade("food", false, 10)
	ok(ledger() == before, "缺资源拒绝且不改账")
	for request in [["gold", true, 1], ["wood", true, -1], ["wood", false, 0], ["ore", true, 999]]:
		m.trade(request[0], request[1], request[2])
		ok(ledger() == before, "无效物品/数量拒绝")
	m.trade_panel.rows[0].sell.emit_signal("pressed")
	ok(m.coins == 2 and m.inv.wood == 19 and m.shop_stock.wood == 21, "真实按钮卖1个木材")
	m.trade_panel.batch_button.emit_signal("pressed")
	m.trade_panel.rows[0].sell.emit_signal("pressed")
	ok(m.coins == 22 and m.inv.wood == 9 and m.shop_stock.wood == 31, "真实按钮批量卖10个")
	m.trade_panel.batch_button.emit_signal("pressed")
	m.trade_panel.rows[0].buy.emit_signal("pressed")
	ok(m.coins == 18 and m.inv.wood == 10 and m.shop_stock.wood == 30, "真实按钮买1个")
	m.trade("wood", false, 1)
	ok(m.coins == 20, "倒卖不增金币")
	m.shop_stock.food = 0
	before = ledger()
	m.trade("food", true, 1)
	ok(before == ledger(), "缺库存拒绝且不改账")
	m.dn.day_count += 1
	m.restock_shop()
	ok(m.shop_stock.food == 20 and m.shop_stock.wood == 31, "次日补货不吞收购库存")
	m.shop_stock.food = 3
	m.restock_shop()
	ok(m.shop_stock.food == 3, "同日不无限补货")
	# 离开柜台必须自动结束；拒绝后台交易；关闭后触控不残留。
	m.player.restore_motion(Vector3(-14, 7.43, 7))
	await frames(3)
	ok(not m.trade_panel.is_open() and not GameBus.ui_blocking and not m.merchant.engaged, "离店自动关闭且释放输入")
	before = ledger()
	m.trade("wood", false, 1)
	ok(before == ledger(), "离店不能交易")
	# 友好碰撞：沿真实身体方向推动玩家撞老板，角色不能重合。
	m.merchant.set_physics_process(false)
	m.player.restore_motion(room.frame.to_global(Vector3(-0.3, 0.22, -3.25)))
	await frames(3)
	var probe: Transform3D = m.player.global_transform
	probe.origin.y += 0.03
	var hit := KinematicCollision3D.new()
	ok(m.player.test_move(probe, room.frame.global_basis * Vector3(-0.9, 0, 0), hit) and hit.get_collider() == m.merchant, "实际撞到老板身体，不能拿墙壁当友好碰撞证据")
	m.merchant.set_physics_process(true)
	# 保存/读档不生成重复NPC，经济与独立随机状态保持。
	for npc in m.npcs: npc.set_physics_process(false)
	var saved: Dictionary = m.serialize()
	m.coins = 999
	m.shop_stock.food = 0
	m.deserialize(saved)
	ok(m.coins == saved.coins and m.shop_stock == saved.shop_stock, "经济存档往返")
	ok(m.npcs.size() == 4, "读档不复制NPC")
	for npc in m.npcs:
		var state: Dictionary = saved.npcs[npc.npc_id]
		ok(str(npc.rng.state) == state.rng, "NPC随机状态保留64位精度")
		ok(npc.target.distance_to(Vector2(state.target[0], state.target[1])) < 0.01, "NPC活动目标保留")
		ok(npc.position.distance_to(Vector3(state.pos[0], state.pos[1], state.pos[2])) < 0.06, "NPC实际位置恢复")
	ok(m.save_sys.save(2), "真实存档文件保存")
	m.coins = 987654
	m.shop_stock.food = 0
	ok(m.save_sys.load(2) and m.coins == saved.coins and m.shop_stock.food == saved.shop_stock.food, "JSON存档经济往返")
	for npc in m.npcs: ok(str(npc.rng.state) == saved.npcs[npc.npc_id].rng, "JSON随机状态往返")
	# 缺新字段的旧档不奖励货币、不抹已有资源。
	for key in ["coins", "shop_stock", "shop_stock_day", "npcs"]: saved.erase(key)
	m.deserialize(saved)
	ok(m.coins == 0 and m.shop_stock.food == 20 and m.inv == saved.inv, "旧存档兼容默认经济")
	# 已打开的交易窗口动态横竖旋转：量文字、按钮和几何，不只验证缩放常量。
	m.player.restore_motion(room.frame.to_global(Vector3(-1.2, 0.22, -0.9)))
	await frames(12)
	m.trade_panel.open(m, m.merchant)
	m.coins = 999999999
	for kind in m.trade_panel.GOODS: m.inv[kind] = 999999999
	m.trade_panel.refresh()
	for size in [Vector2i(1440,810), Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(720,1280), Vector2i(810,1440), Vector2i(1080,1920), Vector2i(1440,2560)]:
		get_window().size = size
		get_viewport().size = size
		await frames(3)
		var controls: Array = [m.trade_panel.title, m.trade_panel.greeting, m.trade_panel.balance, m.trade_panel.notice, m.trade_panel.close_button, m.trade_panel.batch_button]
		for row in m.trade_panel.rows: controls.append_array([row.label, row.buy, row.sell])
		for control: Control in controls:
			ok(m.trade_panel.panel.get_global_rect().encloses(control.get_global_rect()), "交易控件不越面板 size=%s text=%s panel=%s control=%s" % [size, control.text, m.trade_panel.panel.get_global_rect(), control.get_global_rect()])
			var font := control.get_theme_font("font")
			var fs := control.get_theme_font_size("font_size")
			ok(font is SystemFont and font.font_weight == 700, "交易文字实际粗体")
			ok(control.get_minimum_size().y <= control.size.y + 1, "文字不裁切")
			if control is Label and control.autowrap_mode == TextServer.AUTOWRAP_OFF:
				for line in control.text.split("\n"): ok(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= control.size.x + 1, "交易文字宽度")
		for row in m.trade_panel.rows:
			ok(not row.buy.get_global_rect().intersects(row.sell.get_global_rect()), "买卖按钮不重叠")
	m._back_requested()
	ok(not m.trade_panel.is_open() and not GameBus.ui_blocking, "Esc/安卓返回关窗口")
	var villager: CharacterBody3D = m.npcs[1]
	m.player.restore_motion(villager.global_position + Vector3(0.85,0,0))
	await frames(8)
	m._on_touch_action("use")
	ok(m.trade_panel.is_open() and not m.trade_panel.batch_button.visible and villager.engaged, "村民可交谈且停步")
	ok(m.trade_panel.panel.size.y < m.trade_panel.panel.size.x * 0.4, "对话使用紧凑面板")
	m._back_requested()
	ok(not villager.engaged, "交谈结束释放村民")
	print("==== NPC CHECK DONE checks=%d fails=%d ====" % [checks, fails])
	get_tree().quit(1 if fails else 0)
