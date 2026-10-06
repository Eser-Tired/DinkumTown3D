extends Node2D
## 临时自检：触控 UI 在各种分辨率下是否与 HUD / 自身重叠
## 用法（二选一）：
##   Godot --path <proj> --resolution WxH res://tools/touch_layout_check.tscn   （编辑器/调试器注入）
##   Godot --headless --path <proj> res://tools/touch_layout_check.tscn -- --size WxH
##
## 【为什么要 --size】headless 模式下 --resolution 不生效，viewport 恒为 64x64，
## 自检会在错误的分辨率上跑并全部 FAIL。所以这里自己也接一个 --size 兜底。

const FALLBACK := Vector2i(1440, 810)

func _ready() -> void:
	var forced := _parse_size()
	if forced != Vector2i.ZERO:
		# headless 下窗口尺寸锁死，直接改根视口尺寸才能让锚点布局按目标分辨率计算
		get_window().size = forced
		get_viewport().size = forced

	var hud: CanvasLayer = load("res://scripts/hud.gd").new()
	add_child(hud)
	var tc: CanvasLayer = load("res://scripts/touch_controls.gd").new()
	hud.layout_changed.connect(func(bottom: float): tc.set_hud_column_bottom(bottom))
	# 与真实顺序一致：先连接再挂载（TouchControls._ready 会发出首次布局事件）
	# 与 main._on_touch_layout 保持同一套算法，否则自检用的是和线上不同的布局
	GameBus.touch_layout_changed.connect(func(w: float, h: float, k: float):
		var k_text: float = load("res://scripts/ui_layout.gd").text_scale(Vector2(w, h))
		var bottom: float = hud.set_touch_mode(w, h, k, k_text)
		tc.set_hud_column_bottom(bottom))
	add_child(tc)

	await get_tree().process_frame
	await get_tree().process_frame

	var vs := get_viewport().get_visible_rect().size
	print("==== TOUCH LAYOUT CHECK %dx%d ====" % [vs.x, vs.y])

	# HUD 保留区（触摸模式重排后的实际矩形）—— 取面板层，不含其内部标签
	var reserved: Array = hud.touch_reserved_rects()

	var bad := 0
	# 0) HUD 自身各块不得互相重叠。
	# 注意：面板"包含"自己的文字标签是正常设计，不算重叠——
	# 只有「部分交叠」（两边都有露在外面的部分）才是布局事故。
	for i in reserved.size():
		for j in range(i + 1, reserved.size()):
			var ra: Rect2 = reserved[i]
			var rb: Rect2 = reserved[j]
			if _partial_overlap(ra, rb):
				print("FAIL HUD SELF overlap %s vs %s" % [ra, rb])
				bad += 1

	# 【只收可见按钮】旋转 / 潜 平时是隐藏的，隐藏的东西不会造成视觉或操作冲突，
	# 拿它去跑重叠断言只会误报；它们的显隐由第 10 步单独验。
	var btns := []
	for c in tc.get_children():
		if c is Button and (c as Button).visible:
			btns.append(c)

	# 1) 按钮两两不得重叠
	for i in btns.size():
		for j in range(i + 1, btns.size()):
			var a: Button = btns[i]
			var b: Button = btns[j]
			if _overlap(a.get_global_rect(), b.get_global_rect()):
				# 带上实际矩形：按钮的最终尺寸会被主题最小尺寸钳一下，
				# 光看按钮名算不出是谁挤了谁。
				print("FAIL OVERLAP btn '%s' %s min=%s vs '%s' %s min=%s"
					% [a.text, a.get_global_rect(), a.get_combined_minimum_size(),
						b.text, b.get_global_rect(), b.get_combined_minimum_size()])
				bad += 1
	# 2) 按钮不得压住 HUD 保留区
	for i in btns.size():
		var bb: Button = btns[i]
		for r in reserved:
			if _overlap(bb.get_global_rect(), r):
				print("FAIL HUD btn '%s' covers %s" % [bb.text, r])
				bad += 1
	# 3) 摇杆【静止位】圆盘不得压住任何按钮。
	# 注意：现在摇杆的感应区是整个左半屏，这里检查的是松手后那个"提示圆盘"的
	# 落点别压在按钮上——按下时圆盘会跟着手指跑，那是设计如此，不算事故。
	var joy: Control = tc.get_child(0)
	var jc: Vector2 = joy.position + joy.size * 0.5
	var jr_radius: float = tc._joy_r * 1.2
	for i in btns.size():
		var bb: Button = btns[i]
		if _rect_circle(bb.get_global_rect(), jc, jr_radius):
			print("FAIL JOY vs btn '%s'" % bb.text)
			bad += 1
	# 4) 所有控件必须留在屏幕内（拖动定位后的摇杆最容易跑出去）
	for c in tc.get_children():
		if c is Control:
			var cr: Rect2 = c.get_global_rect()
			if cr.position.x < -1.0 or cr.position.y < -1.0 or cr.end.x > vs.x + 1.0 or cr.end.y > vs.y + 1.0:
				print("FAIL OFFScreen '%s' rect=%s vs=%s" % [c.name if c.name != "" else c.get_class(), cr, vs])
				bad += 1
	# 5) 物品栏：4 格必须在底部、且在屏幕内
	if tc._hotbar_btns.size() != 4:
		print("FAIL HOTBAR count=%d (expect 4)" % tc._hotbar_btns.size())
		bad += 1
	else:
		for i in tc._hotbar_btns.size():
			var hb: Button = tc._hotbar_btns[i]
			var hr: Rect2 = hb.get_global_rect()
			if hr.end.y > vs.y + 1.0 or hr.end.x > vs.x + 1.0:
				print("FAIL HOTBAR cell%d out of screen %s" % [i + 1, hr])
				bad += 1
			if hr.position.y < vs.y * 0.5:
				print("FAIL HOTBAR cell%d not at bottom %s" % [i + 1, hr])
				bad += 1
	# 6) 物品栏同步：模拟 main 下发一次，看格子文字有没有跟上
	GameBus.sync_hotbar([
		{"kind": "weapon", "id": "axe", "name": "斧头", "label": "斧头"},
		{"kind": "weapon", "id": "spear", "name": "长矛", "label": "长矛"},
		{"kind": "empty", "id": "", "name": "", "label": ""},
		{"kind": "empty", "id": "", "name": "", "label": ""},
	], 1)
	if tc._hotbar_btns.size() == 4:
		if not tc._hotbar_btns[0].text.contains("斧头"):
			print("FAIL HOTBAR sync slot1 text='%s'" % tc._hotbar_btns[0].text)
			bad += 1
		if not tc._hotbar_btns[1].text.contains("长矛"):
			print("FAIL HOTBAR sync slot2 text='%s'" % tc._hotbar_btns[1].text)
			bad += 1
	# 7) 浮动摇杆：左半屏落指 → 摇杆就长在该处，且拖动期间不许自己移位
	var ta := Vector2(vs.x * 0.22, vs.y * 0.62)
	_feed_touch(tc, 11, ta, true)
	if tc._joy_id != 11:
		print("FAIL JOY left-half touch not captured (joy_id=%d)" % tc._joy_id)
		bad += 1
	if tc._joy_center().distance_to(ta) > 1.0:
		print("FAIL JOY center=%s (expect at finger %s)" % [tc._joy_center(), ta])
		bad += 1
	# 落指瞬间不该有位移，否则"手指一放上去人就窜出去"
	if GameBus.touch_move.length() > 0.001:
		print("FAIL JOY on-press move=%s (expect zero)" % GameBus.touch_move)
		bad += 1
	var td := ta + Vector2(0.0, -60.0 * tc._k)
	_feed_drag(tc, 11, td)
	if tc._joy_center().distance_to(ta) > 1.0:
		print("FAIL JOY center drifted to %s (must stay at %s)" % [tc._joy_center(), ta])
		bad += 1
	# 向上推 → touch_move.y 为负（向前）
	if GameBus.touch_move.y > -0.3:
		print("FAIL JOY move=%s (expect forward, y<0)" % GameBus.touch_move)
		bad += 1
	_feed_touch(tc, 11, td, false)
	if tc._joy_id != -1 or GameBus.touch_move != Vector2.ZERO:
		print("FAIL JOY release not cleared id=%d move=%s" % [tc._joy_id, GameBus.touch_move])
		bad += 1
	if tc._joy_center().distance_to(tc._joy_rest_center()) > 1.0:
		print("FAIL JOY not back to rest %s (expect %s)" % [tc._joy_center(), tc._joy_rest_center()])
		bad += 1

	# 8) 右半屏落指必须留给视角/点击，不能被摇杆抢走。
	# 取 62%/35%：再往右会撞到「潜 / 跳 / 系统钮」，撞了就测不到"空白区"这条路径。
	var tb := Vector2(vs.x * 0.62, vs.y * 0.35)
	_feed_touch(tc, 12, tb, true)
	if tc._joy_id != -1:
		print("FAIL JOY stole right-half touch (joy_id=%d)" % tc._joy_id)
		bad += 1
	if not tc._active.has(12):
		print("FAIL right-half touch not registered for look")
		bad += 1
	_feed_touch(tc, 12, tb, false)

	# 9) 左半屏的按钮优先于摇杆（否则摇杆区会盖掉菜单/背包/建造）
	var lbtn := _first_left_button(btns, vs)
	if lbtn == null:
		print("FAIL no left-half button to test")
		bad += 1
	else:
		var lr: Rect2 = (lbtn as Button).get_global_rect()
		_feed_touch(tc, 13, lr.get_center(), true)
		if tc._joy_id != -1:
			print("FAIL JOY stole button '%s'" % (lbtn as Button).text)
			bad += 1
		_feed_touch(tc, 13, lr.get_center(), false)

	# 10) 模式键：默认隐藏，开建造 / 入水才出现，且出现后仍不压住别的按钮
	var rot := _find_btn_by_text(tc, "旋转")
	var dive := _find_btn_by_text(tc, "潜")
	if rot == null or dive == null:
		print("FAIL missing mode buttons rot=%s dive=%s" % [rot != null, dive != null])
		bad += 1
	elif rot.visible or dive.visible:
		print("FAIL mode buttons visible at rest rot=%s dive=%s" % [rot.visible, dive.visible])
		bad += 1
	else:
		# 「放置」= 建造模式下的「使用」，是个纯重复入口，不许再加回来
		if _find_btn_by_text(tc, "放置") != null:
			print("FAIL 'place' button exists (duplicate of 'use' in build mode)")
			bad += 1
		GameBus.build_mode = true
		GameBus.player_swimming = true
		tc._sync_mode_buttons()
		if not rot.visible or not dive.visible:
			print("FAIL mode buttons not shown rot=%s dive=%s" % [rot.visible, dive.visible])
			bad += 1
		var vis: Array = []
		for c in tc.get_children():
			if c is Button and (c as Button).visible:
				vis.append(c)
		for i in vis.size():
			for j in range(i + 1, vis.size()):
				var va: Button = vis[i]
				var vb: Button = vis[j]
				if _overlap(va.get_global_rect(), vb.get_global_rect()):
					print("FAIL OVERLAP(mode) '%s' vs '%s'" % [va.text, vb.text])
					bad += 1
		GameBus.build_mode = false
		GameBus.player_swimming = false
		tc._sync_mode_buttons()

	print("buttons=%d joy_center=(%.0f, %.0f) joy_r=%.0f k=%.2f" % [btns.size(), jc.x, jc.y, jr_radius, tc._k])
	print("==== CHECK %s bad=%d ====" % ["PASS" if bad == 0 else "FAIL", bad])
	get_tree().quit(1 if bad > 0 else 0)


func _overlap(a: Rect2, b: Rect2) -> bool:
	return a.intersects(b) and a.intersection(b).get_area() > 1.0


## 部分交叠：两边都有露在外面的部分。
## 一块完全包住另一块（面板 ⊃ 标签）不算——那是正常的层级关系。
func _partial_overlap(a: Rect2, b: Rect2) -> bool:
	if not _overlap(a, b):
		return false
	if a.encloses(b) or b.encloses(a):
		return false
	return true


## 解析 --size 1440x810（兜底用，headless 下 --resolution 无效）
## 注意：`--` 之后的参数属于"用户参数"，必须用 get_cmdline_user_args()，
## get_cmdline_args() 拿不到它们。
func _parse_size() -> Vector2i:
	var args := OS.get_cmdline_user_args()
	var i: int = args.find("--size")
	if i < 0 or i + 1 >= args.size():
		return Vector2i.ZERO
	var parts: PackedStringArray = args[i + 1].split("x")
	if parts.size() != 2:
		return Vector2i.ZERO
	var w := int(parts[0])
	var h := int(parts[1])
	if w < 320 or h < 240:
		return Vector2i.ZERO
	return Vector2i(w, h)


## 直接喂一个屏幕触摸事件给触控层（绕过引擎的 GUI 派发，测的是它自己的判定逻辑）
func _feed_touch(tc: CanvasLayer, idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	tc._input(e)


func _feed_drag(tc: CanvasLayer, idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	tc._input(e)


func _find_btn_by_text(tc: CanvasLayer, text: String) -> Button:
	for c in tc.get_children():
		if c is Button and (c as Button).text == text:
			return c as Button
	return null


## 找一个落在左半屏的按钮（摇杆区与按钮区重叠时用于验证优先级）
func _first_left_button(btns: Array, vs: Vector2) -> Button:
	for b in btns:
		var bb: Button = b
		if bb.get_global_rect().get_center().x < vs.x * 0.5:
			return bb
	return null


func _rect_circle(r: Rect2, c: Vector2, rad: float) -> bool:
	var nearest := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
	return nearest.distance_to(c) < rad
