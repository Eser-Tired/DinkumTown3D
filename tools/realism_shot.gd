extends Node
## 固定地图、光照、样板与采样帧数，避免用不同机位的截图冒充材质提升。

const P := preload("res://scripts/props.gd")
var output := "res://realism_shots/"
var m: Node3D
var camera: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--dir")
	if at >= 0 and at + 1 < args.size():
		output = args[at + 1].trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	seed(20260921)
	get_window().size = Vector2i(1440, 810)
	get_viewport().size = Vector2i(1440, 810)
	var start := Time.get_ticks_usec()
	m = load("res://scripts/main.gd").new()
	m.forced_map_seed = 20260921
	add_child(m)
	print("WORLD_BUILD_MS=%.2f" % ((Time.get_ticks_usec() - start) / 1000.0))
	if args.has("--build-only"):
		get_tree().quit()
		return
	for child in m.get_children():
		if child is CanvasLayer:
			child.visible = false
	m.dn.time = 0.39
	m.dn.speed_scale = 0.0
	camera = Camera3D.new()
	camera.fov = 58.0
	m.add_child(camera)
	camera.make_current()
	var y: float = m.terrain.height_at(-8, -5)
	camera.position = Vector3(9, y + 9, 18)
	camera.look_at(Vector3(-8, y + 0.6, -5))
	await _shot("town")
	var board := Node3D.new()
	board.position = Vector3(-12, m.terrain.height_at(-12, 9) + 0.3, 9)
	m.add_child(board)
	board.add_child(P._box(Vector3(7.2, 0.12, 3.2), P.mat(Color(0.16, 0.17, 0.18)), Vector3(0, 0, 0)))
	board.add_child(P._box(Vector3(2.8, 0.18, 0.8), P.surface("wood", P.C_WOOD_LIGHT), Vector3(-1.8, 0.22, -0.8)))
	board.add_child(P._box(Vector3(0.25, 1.7, 0.25), P.surface("wood", P.C_WOOD), Vector3(-3.0, 0.95, 0.7)))
	board.add_child(P._box(Vector3(0.9, 0.18, 2.0), P.surface("wood", P.C_WOOD_DARK), Vector3(-1.6, 0.22, 0.55)))
	board.add_child(P._box(Vector3(2.8, 0.18, 2.5), P.surface("iron", P.C_IRON_GREEN, 0.48), Vector3(1.8, 0.22, 0)))
	camera.global_position = board.global_position + Vector3(3.8, 4.6, 6.0)
	camera.look_at(board.global_position + Vector3(0, 0.2, 0))
	await _shot("surfaces")
	camera.global_position = board.global_position + Vector3(-1.4, 1.2, 0.6)
	camera.look_at(board.global_position + Vector3(-1.8, 0.2, -0.8))
	await _shot("wood_detail")
	camera.global_position = board.global_position + Vector3(2.8, 2.1, 2.5)
	camera.look_at(board.global_position + Vector3(1.8, 0.2, 0))
	await _shot("iron_detail")
	board.visible = false
	var ground := Vector3(-15, m.terrain.height_at(-15, 8), 8)
	camera.global_position = ground + Vector3(3.2, 2.4, 3.8)
	camera.look_at(ground)
	await _shot("ground_dry")
	m.terrain.target_wetness = 1.0
	m.terrain.wetness = 1.0
	await _shot("ground_wet")
	# 空跑热身后记录渲染主循环的帧间隔，不把首次 shader 编译算成稳态性能。
	for i in 100:
		await get_tree().process_frame
	var frame_times: Array[float] = []
	var previous := Time.get_ticks_usec()
	for i in 240:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_times.append((now - previous) / 1000.0)
		previous = now
	frame_times.sort()
	print("FRAME_INTERVAL_MS median=%.2f p95=%.2f samples=240 vsync=%d" % [frame_times[120], frame_times[228], DisplayServer.window_get_vsync_mode()])
	print("RENDER_MEMORY_MB=%.2f" % (RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0))
	print("==== REALISM SHOT DONE ====")
	get_tree().quit()


func _shot(name: String) -> void:
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output + name + ".png")
	if error != OK:
		push_error("截图失败 %s: %d" % [name, error])
