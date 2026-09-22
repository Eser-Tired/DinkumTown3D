extends Node2D
## 临时自检：触控 UI 在各种分辨率下是否与 HUD / 自身重叠
## 用法：Godot --path <proj> [--resolution WxH] res://tools/_touch_check.tscn

func _ready() -> void:
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


func _rect_circle(r: Rect2, c: Vector2, rad: float) -> bool:
	var nearest := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
	return nearest.distance_to(c) < rad
