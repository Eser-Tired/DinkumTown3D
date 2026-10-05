extends Node
## 用实际渲染器复核材质；窗口模式运行，支持 -- --dir <输出目录>。

func _ready() -> void:
	var dir := "res://docs/shots/"
	var args := OS.get_cmdline_user_args()
	var i := args.find("--dir")
	if i >= 0 and i + 1 < args.size():
		dir = args[i + 1].trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	get_window().size = Vector2i(1280, 720)
	get_viewport().size = Vector2i(1280, 720)
	var MS = load("res://scripts/main.gd")
	var m: Node3D = MS.new()
	m.forced_map_seed = 20260921
	add_child(m)
	# 展示材质本身；截图工具隐藏叠加界面，游戏里的界面不受影响。
	for child in m.get_children():
		if child is CanvasLayer:
			child.visible = false
	m.dn.time = 0.46
	m.dn.speed_scale = 0.0
	var camera := Camera3D.new()
	camera.fov = 58.0
	m.add_child(camera)
	camera.global_position = Vector3(9, 17, 18)
	camera.look_at(Vector3(-8, 8.3, -5))
	camera.make_current()
	await _shot(dir + "materials_town.png")
	# 店铺近景：铁皮压纹、木纹和窗面。
	camera.global_position = Vector3(-3, 12.5, -6)
	camera.look_at(Vector3(0, 9.8, -19))
	await _shot(dir + "materials_detail.png")
	var dock: Node3D = m.get_node("Dock")
	m.player.restore_motion(dock.global_position + Vector3(0, 1.03, -7.0))
	camera.global_position = dock.global_position + Vector3(-10, 6, -20)
	camera.look_at(dock.global_position + Vector3(0, 0.3, -9))
	await _shot(dir + "materials_dock.png")
	m._on_weather("rain")
	await get_tree().create_timer(5.7).timeout
	await _shot(dir + "materials_wet.png")
	print("MATERIAL SCREENSHOTS: " + ProjectSettings.globalize_path(dir))
	get_tree().quit()


func _shot(path: String) -> void:
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	if err != OK:
		push_error("Screenshot failed: %s (%s)" % [path, err])
