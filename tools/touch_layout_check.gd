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
	GameBus.touch_layout_changed.connect(func(w: float, h: float, k: float):
		hud.set_touch_mode(w, h, k))
	add_child(tc)

	await get_tree().process_frame
	await get_tree().process_frame

	var vs := get_viewport().get_visible_rect().size
	print("==== TOUCH LAYOUT CHECK %dx%d ====" % [vs.x, vs.y])

	# HUD 保留区（触摸模式重排后的实际矩形）
	var reserved := [
		Rect2(hud.res_label.position, hud.res_label.size),
		Rect2(hud.clock_label.position, hud.clock_label.size),
		Rect2(hud.season_label.position, hud.season_label.size),
		Rect2(hud.prompt_label.position, hud.prompt_label.size),
		Rect2(hud.build_label.position, hud.build_label.size),
	]

	var btns := []
	for c in tc.get_children():
		if c is Button:
			btns.append(c)

	var bad := 0
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

	print("buttons=%d joy_center=(%.0f, %.0f) joy_r=%.0f k=%.2f" % [btns.size(), jc.x, jc.y, jr_radius, tc._k])
	print("==== CHECK %s bad=%d ====" % ["PASS" if bad == 0 else "FAIL", bad])
	get_tree().quit(1 if bad > 0 else 0)


func _overlap(a: Rect2, b: Rect2) -> bool:
	return a.intersects(b) and a.intersection(b).get_area() > 1.0


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
