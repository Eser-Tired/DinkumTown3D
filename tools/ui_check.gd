extends Node
## 验证真实字体尺寸与控件边界，并在同一个已打开的界面里切换横竖屏。

var checks := 0
var fails := 0
var m: Node3D
var menu: Control


func _ok(on: bool, message: String) -> void:
	checks += 1
	if not on:
		fails += 1
		print("FAIL " + message)


func _settle() -> void:
	for i in 8:
		await get_tree().process_frame


func _inside(control: Control, screen: Vector2, name: String) -> void:
	var r := control.get_global_rect()
	_ok(r.position.x >= -1 and r.position.y >= -1 and r.end.x <= screen.x + 1 and r.end.y <= screen.y + 1,
		"%s 越屏 %s screen=%s" % [name, r, screen])


func _text(label: Label, name: String) -> void:
	var font := label.get_theme_font("font")
	var fs := label.get_theme_font_size("font_size")
	_ok(font is SystemFont and font.font_weight == 700, name + " 使用真实粗体")
	_ok(label.get_minimum_size().y <= label.size.y + 1, name + " 文字高度被裁切")
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		for line in label.text.split("\n"):
			var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_ok(width <= label.size.x + 1, "%s 文字溢出 %.1f/%.1f" % [name, width, label.size.x])


func _ready() -> void:
	m = load("res://scripts/main.gd").new()
	m.forced_map_seed = 20260921
	add_child(m)
	m.set_process(false) # 固定长文案，避免游戏的定时 HUD 更新覆盖被检查的状态。
	menu = load("res://scripts/main_menu.gd").new()
	add_child(menu)
	menu.visible = false
	var original_size := 0
	for size in [Vector2i(1440, 810), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440),
			Vector2i(720, 1280), Vector2i(810, 1440), Vector2i(1080, 1920), Vector2i(1440, 2560), Vector2i(3840, 2160)]:
		get_window().size = size
		get_viewport().size = size
		await _settle()
		var vs := Vector2(size)
		var hud = m.hud
		hud.set_resources({"wood": 12345, "stone": 45678, "fiber": 99999, "ore": 88888, "food": 43210})
		hud.set_clock(88, "23:59", 1.0)
		hud.set_weapon("武器：长矛")
		hud.set_prompt("[F] 进入铁皮小屋 · 建造帐篷需要木材6和纤维3")
		hud.set_build("建造（1-4 选择）\n1. 篝火 木材3\n2. 帐篷 木材6 纤维3\n3. 木栅栏 木材2\n4. 路灯 木材2 石头1")
		hud.toast("建造帐篷需要木材6和纤维3，请先采集资源")
		await _settle()
		for label in [hud.res_label, hud.clock_label, hud.season_label, hud.weapon_label, hud.toast_label]:
			_inside(label, vs, "HUD")
			_text(label, "HUD")
		_ok(hud.res_panel.get_global_rect().encloses(hud.res_label.get_global_rect()),
			"资源文字超出背景面板 panel=%s label=%s" % [hud.res_panel.get_global_rect(), hud.res_label.get_global_rect()])
		for label in [hud.prompt_label, hud.build_label, hud.help_label]:
			_inside(label, vs, "HUD长文案")
		var font_size: int = hud.res_label.get_theme_font_size("font_size")
		if size == Vector2i(1440, 810):
			original_size = font_size
		if size == Vector2i(3840, 2160):
			_ok(font_size >= original_size * 2, "4K 字号没有明显增大")
		m.inv_ui.open()
		await _settle()
		_inside(m.inv_ui._box, vs, "背包")
		for cell in m.inv_ui._cells:
			_text(cell.label, "背包资源")
			_ok(cell.panel.get_global_rect().encloses(cell.label.get_global_rect()), "背包资源文字超出格子")
		_inside(m.inv_ui._stat, vs, "背包统计")
		m.inv_ui.close()
		m.pause_menu.open()
		await _settle()
		_inside(m.pause_menu._main_box, vs, "暂停菜单")
		m.pause_menu._show_panel("settings")
		await _settle()
		_inside(m.pause_menu._settings._box, vs, "设置")
		m.pause_menu._show_panel("slots")
		await _settle()
		_inside(m.pause_menu._slots._box, vs, "存档")
		m.pause_menu.close()
		m.sleep_panel.open(func(): return 9.0)
		await _settle()
		_inside(m.sleep_panel._main_box, vs, "睡觉")
		m.sleep_panel.close()
		_inside(menu._title_box, vs, "主菜单标题")
		_inside(menu._menu_box, vs, "主菜单按钮")
		print("UI %dx%d resource_font=%d bold=700" % [size.x, size.y, font_size])
	# 触控既检查真实按钮文字，也检查提示、建造菜单和憋气条同时出现的占位。
	var tc: CanvasLayer = load("res://scripts/touch_controls.gd").new()
	GameBus.touch_layout_changed.connect(m._on_touch_layout)
	m.add_child(tc)
	for size in [Vector2i(1440, 810), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440),
			Vector2i(720, 1280), Vector2i(810, 1440), Vector2i(1080, 1920), Vector2i(1440, 2560)]:
		get_window().size = size
		get_viewport().size = size
		m.hud.set_breath(0.7)
		await _settle()
		for child in tc.get_children():
			if child is Button and not child.is_queued_for_deletion():
				_inside(child, Vector2(size), "触控按钮")
				var fs: int = child.get_theme_font_size("font_size")
				var font: Font = child.get_theme_font("font")
				_ok(font is SystemFont and font.font_weight == 700, "触控按钮不是粗体")
				for line in child.text.split("\n"):
					_ok(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= child.size.x - 3,
						"触控文字溢出: " + child.text)
				for rect in m.hud.touch_reserved_rects():
					_ok(not child.get_global_rect().intersects(rect), "触控键压住HUD: " + child.text + " size=" + str(size))
		print("TOUCH UI %dx%d" % [size.x, size.y])
	# 不重新打开面板，直接旋转屏幕，确保回调在暂停中也会触发。
	m.pause_menu.open()
	m.pause_menu._show_panel("settings")
	get_window().size = Vector2i(720, 1280)
	get_viewport().size = Vector2i(720, 1280)
	await _settle()
	_inside(m.pause_menu._settings._box, Vector2(720, 1280), "打开设置后旋转")
	m.pause_menu.close()
	print("==== UI CHECK DONE checks=%d fails=%d ====" % [checks, fails])
	get_tree().quit(1 if fails else 0)
