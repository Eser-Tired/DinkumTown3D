extends Node
## 战斗系统专项自检 —— 可在主项目里跑
## 运行：Godot --headless --path <项目> res://tools/combat_check.tscn
##
## 覆盖：武器数据完整性 / 命中判定（距离 + 扇形 + 最近优先）/ 受击扣血 /
##       死亡掉落入库存 / 死亡后不可再命中 / 复活 / 存档往返

var m: Node3D
var fails := 0
var checks := 0
var log_lines: Array = []


func _ready() -> void:
	# headless 下 print 会走 stdout，但外部工具链不一定能可靠捕获；
	# 同时落一份文件，保证无论用什么方式跑都能拿到结果。
	_log("=== combat_check start ===")
	_flush()
	var MS = load("res://scripts/main.gd")
	if MS == null:
		_log("FATAL 无法加载 main.gd")
		_flush()
		get_tree().quit(2)
		return
	m = MS.new()
	add_child(m)
	for i in 10:
		await get_tree().process_frame

	_log("world ready, critters=%d" % m.critters.size())
	_flush()

	await _run()
	var tail := "==== COMBAT CHECK DONE checks=%d fails=%d ====" % [checks, fails]
	print(tail)
	_log(tail)
	_flush()
	get_tree().quit(1 if fails > 0 else 0)


func _log(s: String) -> void:
	log_lines.append(s)


## 每写一条就落盘：脚本中途崩溃时仍能看到走到哪一步
func _flush() -> void:
	var path := "res://combat_check.log"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		path = "user://combat_check.log"
		f = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(log_lines) + "\n")
		f.close()


func _run() -> void:
	var W = load("res://scripts/weapons.gd")

	# —— 1) 武器数据完整性 ——
	_check(W.count() >= 2, "武器表至少 2 把")
	for i in W.count():
		var w: Dictionary = W.get_at(i)
		_ok(not w.is_empty(), "武器 %d 数据非空" % i)
		_ok(int(w.get("dmg", 0)) > 0, "武器 %d 伤害 > 0" % i)
		_ok(float(w.get("reach", 0.0)) > 0.0, "武器 %d 距离 > 0" % i)
		_ok(float(w.get("cd", 0.0)) > 0.0, "武器 %d 冷却 > 0" % i)
	_ok(W.name_of("axe") == "斧头", "按 id 查名字")

	# 循环切换
	var n: int = W.count()
	_eq(W.cycle(0, 1), posmod(1, n), "cycle 前进")
	_eq(W.cycle(0, -1), posmod(-1, n), "cycle 后退")

	# —— 2) 动物已被登记 ——
	_ok(m.critters.size() > 0, "世界里有可狩猎动物（%d 只）" % m.critters.size())

	var target: Huntable = null
	for c in m.critters:
		if is_instance_valid(c) and not (c as Huntable).is_dead():
			target = c
			break
	_ok(target != null, "找到一只活着的动物")
	if target == null:
		return

	# died 信号必须已连到 main —— 否则击杀不会结算掉落
	_ok(target.died.is_connected(m._on_critter_died), "died 信号已连接到 main._on_critter_died")
	_ok(target.drop_table.size() > 0, "目标动物有掉落表（%s）" % str(target.drop_table.keys()))

	# —— 3) 命中判定：远处打不到 ——
	var hp0: int = target.max_hp
	_eq(target.hp, hp0, "初始血量为满")

	# 把玩家放到离动物 40 米处并背对它，挥砍应落空（距离是主因，朝向是次因）
	var far := Vector2(target.global_position.x + 40.0, target.global_position.z)
	_place_player(far, PI * 0.5)             # 朝 +x，背离动物
	m._attack()
	_eq(target.hp, hp0, "超出距离挥砍不扣血")

	# —— 4) 命中判定：站在动物正前方，朝向它 ——
	# 朝向约定：model.rotation.y = atan2(dir.x, dir.z)，模型正面是 +z。
	# 玩家站在动物 -z 侧 1.8 米、rotation.y = 0（面朝 +z），动物就在正前方。
	var tp := Vector2(target.global_position.x, target.global_position.z)
	var stand := tp + Vector2(0.0, -1.8)
	_place_player(stand, 0.0)
	m._attack()
	_ok(target.hp < hp0, "正前方近距挥砍命中（hp %d -> %d）" % [hp0, target.hp])

	# —— 5) 扇形判定：背对动物应落空 ——
	var hp1: int = target.hp
	_place_player(stand, PI)                 # 原地转身 180°
	m.player.attack_cd = 0.0
	m._attack()
	_eq(target.hp, hp1, "背对动物挥砍不扣血")

	# —— 6) 冷却：连续两次挥砍，第二次应被冷却挡住 ——
	_place_player(stand, 0.0)
	m._attack()
	var hp2: int = target.hp
	m._attack()                                # 立刻再来一次，冷却未好
	_eq(target.hp, hp2, "冷却期内再次挥砍无效")

	# —— 7) 用一只全新的动物验证击杀掉落 ——
	# 【为什么不能复用 target】前面的命中测试累积伤害可能已经把它打死了，
	# 而 _on_critter_died 是同步回调，掉落会在 take_hit() 内部就结算完，
	# 此时再取 food 基线只会读到结算后的值，断言恒等失败。
	var victim: Huntable = null
	for c in m.critters:
		if is_instance_valid(c) and not (c as Huntable).is_dead() and c != target:
			victim = c
			break
	_ok(victim != null, "找到第二只动物用于击杀测试")
	if victim == null:
		return
	# 血量回满，排除前面被误伤的可能
	victim.hp = victim.max_hp

	var food0 := int(m.inv.get("food", 0))
	var fiber0 := int(m.inv.get("fiber", 0))
	var swings := 0
	while not victim.is_dead() and swings < 40:
		swings += 1
		var vp := Vector2(victim.global_position.x, victim.global_position.z)
		_place_player(vp + Vector2(0.0, -1.5), 0.0)
		m._attack()
		await get_tree().process_frame
	_ok(victim.is_dead(), "连续攻击后动物死亡（用了 %d 刀）" % swings)

	var food1 := int(m.inv.get("food", 0))
	var fiber1 := int(m.inv.get("fiber", 0))
	_ok(food1 > food0, "击杀掉落食物已入库存（food %d -> %d）" % [food0, food1])
	_ok(fiber1 >= fiber0, "击杀掉落纤维已结算（fiber %d -> %d）" % [fiber0, fiber1])

	# 用 victim 继续做后面的死亡态断言
	target = victim

	# —— 8) 已死动物不可再被命中 ——
	var hp3: int = target.hp
	m.player.attack_cd = 0.0
	m.player.model.rotation.y = 0.0
	m._attack()
	_eq(target.hp, hp3, "已死动物不再掉血")

	# —— 9) 存档往返：死亡状态要保持 ——
	var before_dead: bool = target.is_dead()
	_ok(m.save_sys.save(1), "save(1) 成功")
	# 复活它再读档，确认读档把"已死"恢复回来
	target._respawn()
	_ok(not target.is_dead(), "手动复活成功")
	_ok(m.save_sys.load(1), "load(1) 成功")
	for i in 6:
		await get_tree().process_frame
	_ok((target as Huntable).is_dead() == before_dead,
		"读档恢复死亡状态（期望 %s 实得 %s）" % [str(before_dead), str(target.is_dead())])

	# —— 10) 武器槽位存档 ——
	m.player.weapon_idx = W.count() - 1
	_ok(m.save_sys.save(1), "save(1) 成功#2")
	m.player.weapon_idx = 0
	_ok(m.save_sys.load(1), "load(1) 成功#2")
	for i in 4:
		await get_tree().process_frame
	_eq(m.player.weapon_idx, W.count() - 1, "读档恢复武器槽位")

	# —— 11) 快捷物品栏 ——（触控重构新增）
	_check_hotbar()
	# —— 12) 轻点采集 / 攻击的扇形判定 ——（触控重构新增）
	await _check_tap_arc()
	# —— 13) 背包界面 ——（触控重构收尾）
	_check_bag()

	# —— 14) 暂停菜单 ——（放最后：它会真的暂停 SceneTree，
	# 中途残留 paused 会让后面所有 await 卡死，所以末尾强制恢复）
	_check_pause()


## 暂停菜单：层级 / 可点性 / 真暂停 / 逐层退出 / 退出前解除暂停
func _check_pause() -> void:
	if m.pause_menu == null:
		_ok(false, "暂停菜单已创建")
		return
	var pm = m.pause_menu
	_ok(true, "暂停菜单已创建")
	_ok(not pm.is_open(), "暂停菜单初始为关闭")

	# 层级必须盖住背包(30)，否则点菜单按钮时会同时触发下面的 UI
	_ok(pm.layer > m.inv_ui.layer, "暂停菜单层级高于背包（实得 %d > %d）" % [pm.layer, m.inv_ui.layer])

	# 【最关键的一条】游戏暂停后所有 INHERIT 节点的 _process/_input 全停，
	# 菜单自己不声明 ALWAYS 就会变成一张点不动、关不掉的死图。
	_ok(pm.process_mode == Node.PROCESS_MODE_ALWAYS, "暂停菜单 process_mode 为 ALWAYS")

	# 四个菜单项
	var want := ["继续游戏", "读取存档", "设置", "退出游戏"]
	for t in want:
		_ok(_pm_btn(t) != null, "菜单项存在：%s" % t)

	# —— 返回键打开 ——
	m._back_requested()
	_ok(pm.is_open(), "返回键（Esc/系统返回）能打开暂停菜单")
	_ok(get_tree().paused, "打开时游戏真暂停（get_tree().paused）")
	_ok(GameBus.ui_blocking, "打开时标记 ui_blocking")
	# 这两条才是"暂停"真正生效的证据：can_process() 直接反映引擎会不会
	# 调这个节点的 _process/_input。只断言 paused==true 是不够的——
	# 万一有人把 main 也设成 ALWAYS，玩家和昼夜照样在跑，而 paused 仍是 true。
	_ok(not m.can_process(), "暂停时 main 停摆（玩家 / 昼夜 / 动物全停）")
	_ok(pm.can_process(), "暂停时菜单自身仍可交互（否则点不动也关不掉）")

	# —— 子面板切换 ——
	var b_load := _pm_btn("读取存档")
	if b_load != null:
		b_load.pressed.emit()
	_ok(pm._slots != null and pm._slots.visible, "点读取存档进入存档列表")
	_ok(not pm._main_box.visible, "进子面板后首页隐藏")
	_ok(pm.go_back(), "go_back 从子面板返回首页")
	_ok(pm._main_box.visible and not pm._slots.visible, "返回后回到首页")

	var b_set := _pm_btn("设置")
	if b_set != null:
		b_set.pressed.emit()
	_ok(pm._settings != null and pm._settings.visible, "点设置进入设置面板")
	# 面板必须铺满父级：用 set_anchors_preset 会留下 size=0 的坑（锚点改了、offsets
	# 没归零），CenterContainer 于是 0 大、内容贴在中心右下角。这条断言守住它。
	var ss: Vector2 = pm._settings.size
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_ok(is_equal_approx(ss.x, vp.x) and is_equal_approx(ss.y, vp.y),
		"设置面板铺满视口（实得 %s vs %s）" % [str(ss), str(vp)])
	_ok(pm.go_back(), "go_back 从设置面板返回首页")

	# —— 菜单自己接 Esc（关键：paused 时 main 的 _unhandled_input 不会跑，
	#     菜单不自己接就会"打开得了、关不掉"）——
	_ok(pm._main_box.visible and pm.is_open(), "上一步已回到首页")
	pm._show_panel("settings")
	_ok(pm._settings.visible, "进设置面板用于 Esc 分层测试")
	_send_esc(pm)
	_ok(pm._main_box.visible and pm.is_open(), "Esc 在子面板只回首页、不关菜单")
	_send_esc(pm)
	_ok(not pm.is_open(), "Esc 在首页关闭菜单并继续游戏")
	_ok(not get_tree().paused, "Esc 关闭后解除暂停")

	# —— go_back 关闭 ——
	pm.open()
	_ok(pm.go_back(), "go_back 在首页时关闭菜单")
	_ok(not pm.is_open(), "菜单已关闭")
	_ok(not get_tree().paused, "关闭后解除暂停")
	_ok(not GameBus.ui_blocking, "关闭后解除 ui_blocking")

	# —— 触控左上「菜单」按钮 ——
	# 桌面测试场景下触控层没挂载，GameBus.touch_action 也就没人接。
	# 这里临时接上再发一次，才能真正覆盖"按钮 → 信号 → 动作 → 菜单"整条链路；
	# 只调 _do_action("pause") 会漏掉中间那段。
	var linked := GameBus.touch_action.is_connected(m._on_touch_action)
	if not linked:
		GameBus.touch_action.connect(m._on_touch_action)
	GameBus.touch_action.emit("pause")
	_ok(pm.is_open(), "触控「菜单」按钮能打开菜单")
	if not linked:
		GameBus.touch_action.disconnect(m._on_touch_action)
	pm.close()

	# —— 分层退出：背包开着时返回键只关背包，不开菜单 ——
	m._do_action("bag")
	_ok(m.inv_ui.is_open(), "打开背包用于分层测试")
	m._back_requested()
	_ok(not m.inv_ui.is_open() and not pm.is_open(), "背包开着时返回键只关背包")

	# —— 分层退出：建造模式下返回键只退建造，不开菜单 ——
	m._set_build_mode(true)
	m._back_requested()
	_ok(not m.build_mode and not pm.is_open(), "建造模式下返回键只退建造")
	m._refresh_preview()

	# —— 退出游戏必须先解除暂停，否则主界面会以 paused 状态启动、整个卡死 ——
	pm.open()
	# 临时断开真实退出流程：它真的会切场景，测试里跑不得
	pm.quit_requested.disconnect(m._on_pause_quit)
	var b_quit := _pm_btn("退出游戏")
	if b_quit != null:
		b_quit.pressed.emit()
	_ok(not get_tree().paused, "点退出游戏前已解除暂停")
	_ok(not GameBus.ui_blocking, "退出游戏时解除 ui_blocking")
	pm.quit_requested.connect(m._on_pause_quit)

	# 收尾：无论上面走到哪一步，都必须把暂停解除干净
	pm.visible = false
	get_tree().paused = false
	GameBus.ui_blocking = false
	_ok(not get_tree().paused, "收尾时暂停已解除")


## 合成一次 Esc 按键并喂给暂停菜单自己的输入处理
func _send_esc(pm) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	pm._unhandled_input(ev)


func _pm_btn(text: String) -> Button:
	if m.pause_menu == null or m.pause_menu._main_box == null:
		return null
	for c in m.pause_menu._main_box.get_children():
		if c is Button and (c as Button).text == text:
			return c as Button
	return null


## 背包：开关、内容刷新、装备联动、输入屏蔽
func _check_bag() -> void:
	if m.inv_ui == null:
		_ok(false, "背包界面已创建")
		return
	_ok(true, "背包界面已创建")
	_ok(not m.inv_ui.is_open(), "背包初始为关闭")

	# 打开：应可见并屏蔽世界输入
	m._do_action("bag")
	_ok(m.inv_ui.is_open(), "按 bag 动作能打开背包")
	_ok(GameBus.ui_blocking, "背包打开时标记 ui_blocking")

	# 内容：资源数应与 inv 一致（先塞点东西确保不是全 0）
	m.inv["wood"] = 7
	m.inv_ui.refresh()
	var txt := ""
	for c in m.inv_ui._cells:
		var lb: Label = c.label
		if str(c.kind) == "wood":
			txt = lb.text
	_ok(txt.contains("7"), "背包资源格显示实时数量（实得 '%s'）" % txt.replace("\n", "/"))

	# 统计行非空
	var st: String = str(m._bag_stat())
	_ok(st.length() > 8, "背包统计行非空")

	# 装备联动：点第 2 把武器，player 应切过去
	var W2 = load("res://scripts/weapons.gd")
	if W2.count() >= 2:
		var want_id: String = str(W2.get_at(1).get("id", ""))
		m._bag_equip(want_id)
		_eq(m.player.weapon_id(), want_id, "背包装备后 player 手持同步")
		_eq(m.inv_ui._equipped_id, want_id, "背包记录当前装备 id")
		# 装备后物品栏高亮也要跟着走（两套 UI 不能各说各话）
		var found := false
		for i in m.hotbar.size():
			var s: Dictionary = m.hotbar[i]
			if str(s.get("kind", "")) == "weapon" and str(s.get("id", "")) == want_id:
				found = (m.hotbar_sel == i)
				break
		_ok(found, "背包装备后底栏高亮同步")

	# 关闭：应还原输入屏蔽
	m._do_action("bag")
	_ok(not m.inv_ui.is_open(), "再按一次能关闭背包")
	_ok(not GameBus.ui_blocking, "关闭后解除 ui_blocking")

	# Esc 关背包
	m._do_action("bag")
	_ok(m.inv_ui.is_open(), "重新打开用于 Esc 测试")
	m._do_action("esc")
	_ok(not m.inv_ui.is_open(), "Esc 能关闭背包")
	_ok(not GameBus.ui_blocking, "Esc 关闭后解除 ui_blocking")

	# 进背包应自动退建造模式
	m._set_build_mode(true)
	m._do_action("bag")
	_ok(m.inv_ui.is_open() and not m.build_mode, "进背包自动退出建造模式")
	m._do_action("bag")
	_ok(not m.inv_ui.is_open(), "收尾关闭背包")


## 物品栏：格子数、类型、选中与 player.weapon_idx 的一致性
func _check_hotbar() -> void:
	_eq(m.hotbar.size(), 4, "物品栏恰好 4 格")
	_ok(m.hotbar.size() == 4, "物品栏非空")
	if m.hotbar.size() != 4:
		return
	# 前若干格必须是武器，且与 WeaponsS 顺序一致
	var weapons := 0
	for i in m.hotbar.size():
		var s: Dictionary = m.hotbar[i]
		if str(s.get("kind", "")) == "weapon":
			weapons += 1
	_ok(weapons >= 2, "物品栏至少含 2 件武器（实得 %d）" % weapons)

	# 选第 2 格（武器）应把 player.weapon_idx 切过去，且高亮跟着走
	m._select_hotbar(1)
	var s1: Dictionary = m.hotbar[1]
	if str(s1.get("kind", "")) == "weapon":
		_eq(m.player.weapon_id(), str(s1.get("id", "")), "选格后 player 手持同步")
		_eq(m.hotbar_sel, 1, "选格后高亮下标同步")
		_ok(not m.build_mode, "选武器自动退出建造模式")

	# 建格子：应进建造模式并把 build_index 对上
	var bi := -1
	for i in m.hotbar.size():
		if str(m.hotbar[i].get("kind", "")) == "build":
			bi = i
			break
	if bi >= 0:
		m._select_hotbar(bi)
		_ok(m.build_mode, "选建造格进入建造模式")
		_eq(m.build_index, int(m.hotbar[bi].get("build_index", -1)), "选建造格同步 build_index")
		m._set_build_mode(false)

	# 空格子：不改状态、不崩溃
	var before_sel: int = m.hotbar_sel
	m._select_hotbar(99)
	_eq(m.hotbar_sel, before_sel, "越界点选不改选中态")


## 扇形判定：正前方能选到，正后方选不到；轻点射程比桌面端更宽
func _check_tap_arc() -> void:
	# 找一只活着的动物，把它搬到玩家附近并锁住
	var beast: Huntable = null
	for c in m.critters:
		if is_instance_valid(c) and not (c as Huntable).is_dead():
			beast = c
			break
	if beast == null:
		return

	m.player.global_position = Vector3(0.0, m.terrain.height_at(0.0, 0.0), 0.0)
	var origin: Vector3 = m.player.global_position
	var fwd := Vector3(0.0, 0.0, 1.0)
	var back := Vector3(0.0, 0.0, -1.0)

	# 明确固定成斧头（reach 2.6），否则前面的存档往返测试会把武器留在长矛上，
	# 距离断言就失去意义了。
	m.player.weapon_idx = 0
	_ok(m.player.weapon_id() == "axe", "固定为斧头做扇区测试")

	# 有效射程 = reach + 动物 hit_radius（袋鼠 1.0），斧头即 3.6。
	# 取 2.0（稳进）与 4.2（稳出）两个不会踩边的距离。
	beast.global_position = origin + fwd * 2.0
	_ok(m._find_critter_in_arc(origin, fwd, false) == beast, "正前方 2.0 处能选中")
	_ok(m._find_critter_in_arc(origin, back, false) == null, "正后方选不中（扇形生效）")

	beast.global_position = origin + fwd * 4.2
	_ok(m._find_critter_in_arc(origin, fwd, false) == null, "4.2 超出 axe 有效射程")
	_ok(m._find_critter_in_arc(origin, fwd, true) == beast, "4.2 在轻点放宽射程内")

	# 侧后方 120°：超出斧头 35° 半角，选不中
	beast.global_position = origin + Vector3(1.7, 0.0, -1.0)
	_ok(m._find_critter_in_arc(origin, fwd, true) == null, "120° 侧后方选不中")

	# 资源扇形：目标是资源节点，用宽容角 86°
	if m.resources.size() > 0:
		var res: Node3D = m.resources[0]
		res.global_position = origin + fwd * 2.5
		_ok(m._find_resource_in_arc(origin, fwd) == res, "正前方资源能选中")
		res.global_position = origin + back * 2.5
		_ok(m._find_resource_in_arc(origin, fwd) == null, "正后方资源选不中")


## 把玩家瞬移到指定水平位置并设定朝向，同时清空攻击冷却
## 【为什么还要设 cam_yaw】攻击判定走的是 player.aim_dir()（相机朝向），
## 因为身体朝向 model.rotation.y 是跟"移动方向"插值的，会滞后于视线。
## 只设 model 不设相机，就会重现"看着它却打空"的问题。
func _place_player(pos2: Vector2, face_y: float) -> void:
	m.player.global_position = Vector3(
		pos2.x, m.terrain.height_at(pos2.x, pos2.y), pos2.y)
	m.player.model.rotation.y = face_y
	# 相机朝前 = 身体朝前 + PI（相机 z 轴与模型 +Z 相反）
	m.player.cam_yaw.rotation.y = face_y + PI
	m.player.attack_cd = 0.0


func _check(cond: bool, name: String) -> void:
	checks += 1
	var line := ("PASS " if cond else "FAIL ") + name
	if not cond:
		fails += 1
	print(line)
	_log(line)
	_flush()


func _ok(cond: bool, name: String) -> void:
	_check(cond, name)


func _eq(a, b, name: String) -> void:
	_check(a == b, "%s（期望 %s 实得 %s）" % [name, str(b), str(a)])
