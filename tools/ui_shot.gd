extends Node
## 实际渲染后截图，横竖屏切换发生在已创建的界面里，兼顾动态重排验证。

var output := "res://ui_shots/"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--dir")
	if at >= 0 and at + 1 < args.size():
		output = args[at + 1].trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var m: Node3D = load("res://scripts/main.gd").new()
	m.forced_map_seed = 20260921
	add_child(m)
	m.dn.time = 0.42
	m.dn.speed_scale = 0.0
	for size in [Vector2i(1440, 810), Vector2i(720, 1280)]:
		get_window().size = size
		get_viewport().size = size
		var tag := "%dx%d" % [size.x, size.y]
		await _shot(tag + "_hud")
		m.inv_ui.open()
		await _shot(tag + "_bag")
		m.inv_ui.close()
		m.pause_menu.open()
		m.pause_menu._show_panel("settings")
		await _shot(tag + "_settings")
		m.pause_menu.close()
	# 触控截图走真实动作入口，避免只验证桌面界面而漏掉按钮占位。
	GameBus.touch_action.connect(m._on_touch_action)
	GameBus.touch_layout_changed.connect(m._on_touch_layout)
	GameBus.touch_tap.connect(m._on_touch_tap)
	GameBus.touch_build_drag.connect(m._on_touch_drag_build)
	m.add_child(load("res://scripts/touch_controls.gd").new())
	m._rebuild_hotbar()
	for size in [Vector2i(1440, 810), Vector2i(720, 1280)]:
		get_window().size = size
		get_viewport().size = size
		var tag := "%dx%d" % [size.x, size.y]
		await _shot(tag + "_touch")
		m._do_action("build")
		await _shot(tag + "_touch_build")
		m._do_action("build")
	m.queue_free()
	await get_tree().process_frame
	var menu: Control = load("res://scripts/main_menu.gd").new()
	add_child(menu)
	await _shot("720x1280_menu")
	print("==== UI SHOT DONE " + ProjectSettings.globalize_path(output) + " ====")
	get_tree().quit()


func _shot(name: String) -> void:
	await get_tree().create_timer(0.7, true).timeout
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(output + name + ".png")
	if err != OK:
		push_error("截图失败 %s: %s" % [name, err])
