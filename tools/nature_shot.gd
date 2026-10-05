extends Node
## 固定世界、光照与机位；三个禁用参数能拍摄上一版同机位对照。
var main: Node3D
var camera: Camera3D
var output := "res://asset_shots_nature/"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--dir")
	if at >= 0:
		output = args[at + 1].trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	get_window().size = Vector2i(1440, 810)
	seed(20260921)
	main = load("res://scripts/main.gd").new()
	main.forced_map_seed = 20260921
	add_child(main)
	for child in main.get_children():
		if child is CanvasLayer:
			child.visible = false
	for animal in main.critters:
		animal.set_process(false)
	main.player.set_physics_process(false)
	main.dn.time = 0.39
	main.dn.speed_scale = 0.0
	camera = Camera3D.new()
	camera.fov = 58.0
	main.add_child(camera)
	camera.make_current()
	var tree: Node3D = main.resources[0]
	camera.position = tree.position + Vector3(8, 6, 12)
	camera.look_at(tree.position + Vector3(0, 3.5, 0))
	await _shot("forest")
	var p := Vector2(-31, 20)
	var ground := Vector3(p.x, main.terrain.height_at(p.x, p.y), p.y)
	camera.position = ground + Vector3(4, 2.0, 5)
	camera.look_at(ground + Vector3(0, 0.35, 0))
	await _shot("meadow")
	main.player.position = ground
	main.player.model.rotation = Vector3.ZERO
	camera.position = ground + Vector3(2.8, 1.65, 3.6)
	camera.look_at(ground + Vector3(0, 0.95, 0))
	if main.player.rig.root != null:
		main.player.rig.play("Idle", 0.0)
		main.player.rig.animation.advance(0.35)
	await _shot("player")
	if main.player.rig.root != null:
		main.player.rig.play("Walk", 0.0)
		main.player.rig.animation.advance(0.28)
	else:
		# 对照组也取旧程序化走路的一帧，不能把静止姿态标成旧行走效果。
		main.player.model.get_node("LegL").rotation.x = 0.5
		main.player.model.get_node("LegR").rotation.x = -0.5
		main.player.model.get_node("ArmL").rotation.x = -0.375
		main.player.model.get_node("ArmR").rotation.x = 0.375
	await _shot("walk")
	if main.player.rig.root != null:
		main.player.swing_t = 0.05
		main.player.rig.update_player(main.player, 0.2, false, false)
	else:
		main.player.swing_t = 0.0
		main.player._update_combat(0.15)
	await _shot("attack")
	if main.player.rig.root != null:
		main.player.swing_t = -1
		main.player.swimming = true
		main.player.position = Vector3(main.LAKE.x, -0.8, main.LAKE.y - 12)
		main.player.model.rotation.x = 0.5
		camera.position = main.player.position + Vector3(2.8, 3.0, 4.0)
		camera.look_at(main.player.position + Vector3(0, 1.1, 0))
		main.player.model.get_node("ArmL").rotation.x = -1.0
		main.player.model.get_node("ArmR").rotation.x = 1.0
		main.player.rig.update_player(main.player, 0.15, false, false)
		await _shot("swim_pose")
		main.player.swimming = false
		main.player.model.rotation.x = 0
	main.player.position = Vector3(300, 0, 300)
	var shown := {}
	for animal in main.critters:
		var script_path: String = animal.get_script().resource_path
		var species := str(animal.get_meta("species_name", "袋鼠" if script_path.ends_with("kangaroo.gd") else "鸸鹋"))
		if shown.has(species):
			continue
		shown[species] = true
		animal.position = ground
		animal.rotation.y = 0
		if animal.get("rig") != null:
			animal.rig.play("Idle", 0.0)
			animal.rig.animation.advance(0.2)
		camera.position = ground + Vector3(3.0, 1.65, 4.0)
		camera.look_at(ground + Vector3(0, 0.8, 0))
		await _shot("animal_" + species)
		if species == "雄鹿" and animal.get("rig") != null:
			animal.rig.play("Death", 0.0)
			animal.rig.animation.advance(animal.rig.animation.get_animation("Death").length)
			await _shot("death")
		animal.position = Vector3(300, 0, 300)
	print("DENSE_COUNT=", main.get_node("DenseVegetation").get_meta("count"))
	print("RENDER_OBJECTS=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), " DRAWS=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " PRIMITIVES=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	# 全部资源和 shader 预热后量真实渲染帧时间，记录范围，不能用 headless 推断 GPU 性能。
	var times: Array[float] = []
	var previous := Time.get_ticks_usec()
	for i in 120:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		times.append((now - previous) / 1000.0)
		previous = now
	times.sort()
	print("FRAME_MS median=", times[60], " p95=", times[114], " GPU=", RenderingServer.get_video_adapter_name())
	print("==== NATURE SHOT DONE ====")
	get_tree().quit()

func _shot(name: String) -> void:
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output + name + ".png")
	if error != OK:
		push_error("截图失败：" + name)
