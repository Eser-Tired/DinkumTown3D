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
	# 与真实顺序一致：先连接再挂载（TouchControls._ready 会发出首次布局事件）
	# 与 main._on_touch_layout 保持同一套算法，否则自检用的是和线上不同的布局
	GameBus.touch_layout_changed.connect(func(w: float, h: float, k: float):
		var k_text := maxf(k, clampf(minf(w, h) / 810.0, 0.0, 1.0))
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

	var btns := []
	for c in tc.get_children():
		if c is Button:
			btns.append(c)

	# 1) 按钮两两不得重叠
	for i in btns.size():
		for j in range(i + 1, btns.size()):
			var a: Button = btns[i]
			var b: Button = btns[j]
			if _overlap(a.get_global_rect(), b.get_global_rect()):
				print("FAIL OVERLAP btn '%s' vs '%s'" % [a.text, b.text])
				bad += 1
	# 2) 按钮不得压住 HUD 保留区
	for i in btns.size():
		var bb: Button = btns[i]
		for r in reserved:
			if _overlap(bb.get_global_rect(), r):
				print("FAIL HUD btn '%s' covers %s" % [bb.text, r])
				bad += 1
	# 3) 摇杆命中圆不得压住任何按钮（实际代码也是圆形判定）
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
	# 7) 摇杆拖动落位：模拟挪到屏幕 40% 处，检查比例是否被正确记录
	var want := Vector2(vs.x * 0.4, vs.y * 0.55)
	tc._move_joy_to(want)
	tc._commit_joy_pos()
	if absf(tc._joy_pos_ratio.x - 0.4) > 0.02 or absf(tc._joy_pos_ratio.y - 0.55) > 0.02:
		print("FAIL JOY commit ratio=%s (expect ~0.40, 0.55)" % tc._joy_pos_ratio)
		bad += 1
	# 落位后重建布局，摇杆中心应贴近目标点
	tc._rebuild()
	var jc2: Vector2 = tc.get_child(0).position + tc.get_child(0).size * 0.5
	if jc2.distance_to(want) > 2.0:
		print("FAIL JOY rebuild center=%s (expect %s)" % [jc2, want])
		bad += 1
	# 复位，别把测试结果写进真实设置
	tc.reset_joy_position()

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


func _rect_circle(r: Rect2, c: Vector2, rad: float) -> bool:
	var nearest := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
	return nearest.distance_to(c) < rad
