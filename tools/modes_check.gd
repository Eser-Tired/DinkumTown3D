extends Node
const S := preload("res://scripts/survival.gd")
var m: Node3D
var fails := 0
var checks := 0
func ok(value: bool, why: String) -> void:
	checks += 1
	if not value:
		fails += 1
		print("FAIL ", why)
func frames(count: int) -> void:
	for i in count: await get_tree().physics_frame
func health_reset() -> void:
	m.survival.health = 100
	m.survival.damage_grace = 0
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	m = load("res://scripts/main.gd").new()
	m.forced_map_seed = 20260921
	add_child(m)
	await frames(15)
	var life: Node = m.survival
	ok(life.mode == S.NORMAL and life.health == 100, "默认普通生存和100生命")
	ok(S.valid_id(life.world_id), "世界有独立稳定ID")
	var legacy: Dictionary = m.serialize()
	legacy.erase("survival")
	m.deserialize(legacy)
	ok(life.mode == S.NORMAL and life.health == 100 and m.inv == legacy.inv, "旧档补充普通模式且保留库存")
	m.inv.wood = 7
	m.inv.fiber = 2
	m.inv.ore = 9
	m.coins = 18
	m.save_sys.save(1)
	var finite: Dictionary = m.inv.duplicate()
	var old_file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(m.save_sys.save_path(1)))
	old_file.main.erase("survival")
	for key in ["mode","world_id","ended"]: old_file.__meta.erase(key)
	var legacy_file := FileAccess.open(m.save_sys.save_path(1),FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(old_file))
	legacy_file.close()
	ok(m.save_sys.load(1) and life.mode == S.NORMAL, "真实旧JSON存档可读取")
	var migrated: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(m.save_sys.save_path(1)))
	var adopted_id: String = life.world_id
	ok(migrated.main.survival.world_id == adopted_id and m.save_sys.load(1) and life.world_id == adopted_id, "旧档ID立即写回，重复读档身份不改变")
	# 点击暂停设置真实的模式控件；改变的是当前槽位，不是settings.cfg。
	m.pause_menu.open()
	m.pause_menu._show_panel("settings")
	var settings: Control = m.pause_menu._settings
	settings._mode_option.emit_signal("item_selected", 2)
	ok(life.creative() and settings._mode_label.text == "当前存档模式", "设置切换当前存档为创造")
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(m.save_sys.save_path(1)))
	ok(stored.main.survival.mode == S.CREATIVE and stored.__meta.mode == S.CREATIVE, "当前槽位与元数据立即保存模式")
	ok(m.inv == finite and m._can_afford({"wood":999}), "创造模式不篡改有限库存")
	for kind in m.inv:
		ok(m.has_item(kind, 999999) and m.take_item(kind, 999999), "创造资源接口无限且可消费")
	ok(m.inv == finite, "无限消费后原库存不变")
	ok(not m.take_item("wood", -2) and not m.has_item("unknown",1), "无效资源/负数不能造假")
	m.inv_ui.open()
	ok(m.inv_ui._cells[0].label.text.contains("∞") and m.hud.res_label.text.contains("∞"), "背包与HUD显示无限")
	m.inv_ui.close()
	life.damage(500,"测试伤害")
	ok(life.health == 100 and not life.ended, "创造免伤")
	var ledger: Array = [m.inv.duplicate(), m.coins, m.shop_stock.duplicate()]
	m.trade("wood", false, 10)
	ok([m.inv,m.coins,m.shop_stock] == ledger, "创造无限资源不能兑出金币")
	m.pause_menu.close()
	# 真正建造一件物体，不能只验证can_afford返回值。
	var point := Vector2(-14, 16)
	m.player.restore_motion(Vector3(point.x,m.terrain.height_at(point.x,point.y)+0.1,point.y))
	await frames(12)
	m.build_index = 0
	m._set_build_mode(true)
	m._refresh_preview()
	m.preview.position = Vector3(-12,m.terrain.height_at(-12,20),20)
	var built: int = m.built_items.size()
	m._try_place_at_mouse()
	ok(m.built_items.size() == built + 1 and m.inv == finite, "创造实际建造不扣资源")
	m._set_build_mode(false)
	m._refresh_preview()
	var plot: Dictionary = m.farm.plots[0]
	m.player.restore_motion(Vector3(plot.pos.x,m.terrain.height_at(plot.pos.x,plot.pos.y)+0.1,plot.pos.y))
	m.farm.interact(m.player.position)
	m.farm.interact(m.player.position)
	ok(m.farm.plots[0].state == 2 and m.inv == finite, "创造播种不扣原库存")
	ok(life.set_mode(S.NORMAL), "死亡前可切回普通")
	ok(m.inv == finite and not m.hud.res_label.text.contains("∞"), "切回普通恢复真实库存显示")
	ok(not m._can_afford({"wood":99}), "普通仍要求真实资源")
	m.take_item("wood",2)
	ok(m.inv.wood == 5, "普通消费照常扣资源")
	# 非致命伤、无敌间隔与睡觉恢复。
	life.damage(20,"测试受伤")
	ok(life.health == 80 and m.hud.res_label.text.contains("生命 80/100"), "生命与HUD同步")
	life.damage(20,"重复受伤")
	ok(life.health == 80, "同帧多次反击不叠加")
	m._apply_sleep(12)
	ok(life.health == 100, "睡觉恢复生命")
	# 实际物理落地：日常跳跃安全，8米自由落体会扣血。
	m.player.restore_motion(Vector3(-14,m.terrain.height_at(-14,14)+0.1,14))
	await frames(15)
	health_reset()
	GameBus.touch_jump_edge = true
	await frames(70)
	ok(life.health == 100, "正常跳跃不摔伤")
	m.player.restore_motion(Vector3(-14,m.terrain.height_at(-14,14)+8,14))
	await frames(100)
	ok(life.health < 100 and life.health > 0 and m.player.is_on_floor(), "8米真实落地发生摔伤")
	print("FALL_HEALTH=",life.health)
	# 固定身体在真实深水位置，排除自动上浮；只耗尽氧气且头部在水下才受伤。
	health_reset()
	m.player.restore_motion(Vector3(48,m.terrain.water_level()-2.2,22))
	await frames(2)
	m.player.set_physics_process(false)
	m.player.breath = 0
	await frames(60)
	ok(life.health < 90 and life.health > 85, "真实缺氧水下1秒约损失12生命")
	m.player.position.y = m.terrain.water_level()+1
	var before: float = life.health
	await frames(30)
	ok(is_equal_approx(life.health,before), "出水停止溺水伤害")
	m.player.set_physics_process(true)
	m.player.restore_motion(Vector3(-14,m.terrain.height_at(-14,14)+0.1,14))
	await frames(15)
	# 被激怒的实际动物追近后反击；非激怒接触和隔墙不攻击。
	health_reset()
	var beast: Huntable = m.critters[0]
	beast.set_process(false)
	beast.dead = false
	beast.hp = 30
	beast.stun = 0
	beast.position = m.player.position + Vector3(0,0,1.7)
	beast.rotation.y = PI
	beast.retaliate_time = 0
	await frames(60)
	ok(life.health == 100, "普通路过动物不无故攻击")
	beast.retaliate_time = 5
	await frames(70)
	ok(life.health == 90, "实际近距离反击扣10生命")
	beast.retaliate_time = 0
	beast.set_process(true)
	# 真实攻击入口和追近，而非只手填反击状态。沿身体方向移动且到近身距离停下。
	health_reset()
	beast.position = m.player.position + Vector3(0,0,3.2)
	beast.rotation.y = PI
	m.player.attack_cd = 0
	m._attack_at(beast)
	ok(beast.retaliate_time > 0 and beast.hp == 12, "实际攻击入口激怒尚未死亡的动物")
	var start_distance: float = beast.global_position.distance_to(m.player.global_position)
	await frames(65)
	ok(beast.global_position.distance_to(m.player.global_position) < start_distance - 0.5, "被攻击的动物实际追近")
	beast.retaliate_time = 0
	# 普通死亡回镇上且保留资源。
	m.player.restore_motion(Vector3(20,m.terrain.height_at(20,0)+0.1,0))
	var inventory: Dictionary = m.inv.duplicate()
	var id: String = life.world_id
	health_reset()
	life.damage(1000,"普通死亡")
	await frames(4)
	ok(life.health == 100 and life.playable() and not get_tree().paused, "普通死亡可恢复游戏")
	ok(Vector2(m.player.position.x,m.player.position.z).distance_to(m.TOWN+Vector2(0,17))<0.05 and m.inv == inventory, "普通回镇上且背包保留")
	ok(life.world_id == id and not S.is_locked(id), "普通死亡不结束世界")
	# 模式/生命/世界ID真实JSON往返，并保证主菜单选项不修改已有世界。
	life.set_mode(S.HARDCORE)
	life.health = 63
	m.save_sys.save(1)
	m.save_sys.save(2)
	var backup: Dictionary = m.serialize()
	life.set_mode(S.CREATIVE)
	ok(m.save_sys.load(1) and life.mode == S.HARDCORE and life.health == 63 and life.world_id == id, "真实模式生命与ID存档往返")
	var menu_settings: Control = load("res://scripts/settings_panel.gd").new()
	add_child(menu_settings)
	menu_settings._mode_option.emit_signal("item_selected", 2)
	ok(GameBus.new_game_mode == S.CREATIVE and life.mode == S.HARDCORE, "主菜单新存档选项不更改当前世界")
	menu_settings.free()
	# 8种分辨率下打开设置并旋转，量模式说明、控件与实际字体。
	m.pause_menu.open()
	m.pause_menu._show_panel("settings")
	for size in [Vector2i(1440,810),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(720,1280),Vector2i(810,1440),Vector2i(1080,1920),Vector2i(1440,2560)]:
		get_window().size=size
		get_viewport().size=size
		await frames(8)
		var box: Rect2 = settings._box.get_global_rect()
		ok(Rect2(Vector2.ZERO,Vector2(size)).encloses(box), "模式设置不越屏 %s %s" %[size,box])
		for control: Control in [settings._mode_option,settings._mode_label,settings._mode_note]:
			ok(box.encloses(control.get_global_rect()), "模式控件在面板内")
			ok(control.get_theme_font("font") is SystemFont and control.get_theme_font("font").font_weight == 700, "真实粗体")
			ok(control.size.y + 1 >= control.get_minimum_size().y, "模式说明不裁切")
	m.pause_menu.close()
	# 死亡前旧档含同一ID；真正死亡先落世界标记，再保存结束状态。
	health_reset()
	life.damage(1000,"真实死亡")
	await frames(4)
	ok(life.ended and life.health == 0 and get_tree().paused and GameBus.ui_blocking, "真实死亡停止世界并显示结束画面")
	ok(S.is_locked(id) and not life.set_mode(S.CREATIVE), "死亡后永久锁定且不能改模式")
	ok(life.death_loot == inventory and m.inv.values().all(func(value): return value == 0), "背包全部掉落而非凭空删除")
	ok(is_instance_valid(life._drop) and life._drop.get_meta("death_loot") == inventory, "死亡位置生成实际资源掉落")
	ok(not m.save_sys.load(1) and not m.save_sys.load(2), "死亡档与死亡前旧槽位都不能复活")
	m.deserialize(backup)
	ok(life.ended and m.inv.values().all(func(value): return value == 0), "直接反序列化旧快照也不能回滚复活")
	m.pause_menu._slots.refresh()
	ok(m.pause_menu._slots._slot_btns[1].disabled and m.pause_menu._slots._slot_btns[2].disabled and m.save_sys.slot_text(2).contains("已结束"), "存档列表标记结束并禁止读取")
	for size in [Vector2i(1440,810),Vector2i(720,1280),Vector2i(2560,1440)]:
		get_window().size=size
		get_viewport().size=size
		await frames(8)
		for node: Control in [life._title,life._message,life._back]:
			ok(life._panel.get_global_rect().encloses(node.get_global_rect()), "死亡界面控件边界 %s text=%s panel=%s node=%s" % [size,node.text,life._panel.get_global_rect(),node.get_global_rect()])
			ok(node.get_minimum_size().y <= node.size.y+1, "死亡界面不裁切")
	get_tree().paused=false
	GameBus.ui_blocking=false
	print("==== MODES CHECK DONE checks=%d fails=%d ====" %[checks,fails])
	get_tree().quit(1 if fails else 0)
