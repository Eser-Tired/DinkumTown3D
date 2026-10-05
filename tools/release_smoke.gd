extends SceneTree
## 在实际导出资源上走完菜单→新游戏→移动；截图必须窗口模式，不能 headless。
var failures := 0
var output_dir := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--out")
	if at >= 0 and at + 1 < args.size(): output_dir = args[at + 1]
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1440, 810)
	change_scene_to_file("res://scenes/main_menu.tscn")
	await create_timer(2.0).timeout
	_check(current_scene._ver_label.text.begins_with("v1.1.0"), "主菜单发布版本")
	await _capture("menu.png")
	current_scene._start_new()
	await create_timer(3.0).timeout
	var game := current_scene
	_check(game.scene_file_path == "res://scenes/main.tscn", "新游戏切换成功")
	_check(game.player != null and game.terrain != null, "玩家与地形已实例化")
	_check(game.dn.env.environment.ssao_enabled == (RenderingServer.get_current_rendering_method() != "mobile"), "SSAO 与渲染器能力一致")
	var bus := root.get_node("GameBus")
	var before: Vector3 = game.player.global_position
	bus.touch_move = Vector2(0, 1)
	for i in 60: await physics_frame
	bus.touch_move = Vector2.ZERO
	var after: Vector3 = game.player.global_position
	var distance := Vector2(after.x - before.x, after.z - before.z).length()
	_check(distance > 0.3, "实际移动 %.3f 米" % distance)
	await create_timer(0.4).timeout
	await _capture("game.png")
	print("==== RELEASE SMOKE DONE moved=%.3f fails=%d ====" % [distance, failures])
	quit(1 if failures else 0)

func _capture(name: String) -> void:
	if output_dir.is_empty(): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output_dir)
	_check(root.get_texture().get_image().save_png(output_dir.path_join(name)) == OK, "截图落盘 " + name)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL " + label)
