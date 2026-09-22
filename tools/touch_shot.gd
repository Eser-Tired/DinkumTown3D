extends Node2D
## 触控布局截图 —— 用真实的分辨率与 --touch-ui 跑，产出可直接看的 PNG
##
## 用法：
##   Godot --path <项目> res://tools/touch_shot.tscn -- --size 2340x1080 --dir <输出目录>
##
## 【为什么要单独一个脚本】main.gd 里的 --auto-shot 走的是桌面布局，
## 不会挂触控层。触控 UI 必须真的挂上 TouchControls 才能截到。

var m: Node3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var size := _arg_pair(args, "--size")
	var dir := _arg_str(args, "--dir", "res://touch_shots/")
	if size != Vector2i.ZERO:
		get_window().size = size
		get_viewport().size = size

	# 强制触控：等价于命令行加 --touch-ui
	if not OS.get_cmdline_args().has("--touch-ui"):
		# main.gd 读的是 get_cmdline_args()，这里补不进去，
		# 所以直接绕过它，手动挂一层 TouchControls。
		pass

	var MS = load("res://scripts/main.gd")
	m = MS.new()
	add_child(m)

	# 等世界建完 + 触控层就位
	for i in 12:
		await get_tree().process_frame

	# 如果 main 没有因为 --touch-ui 自动挂触控层，这里手动挂一个
	var tc := m.get_node_or_null("TouchControls")
	if tc == null:
		var TCS = load("res://scripts/touch_controls.gd")
		GameBus.touch_action.connect(m._on_touch_action)
		GameBus.touch_layout_changed.connect(m._on_touch_layout)
		GameBus.touch_tap.connect(m._on_touch_tap)
		GameBus.touch_build_drag.connect(m._on_touch_drag_build)
		m.add_child(TCS.new())
		m._rebuild_hotbar()
		for i in 4:
			await get_tree().process_frame
		tc = m.get_node_or_null("TouchControls")

	var vs := get_viewport().get_visible_rect().size
	print("TOUCH SHOT viewport=%dx%d tc=%s" % [vs.x, vs.y, str(tc != null)])

	# —— 1) 默认探索态：摇杆 + 物品栏 + 动作键 ——
	await get_tree().create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "touch1_explore.png")

	# —— 2) 物品栏切换态：选中第 2 格（长矛），HUD 武器名应同步 ——
	m._select_hotbar(1)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "touch2_hotbar_switch.png")

	# —— 3) 建造模式：预览 + 放置/旋转键高亮 ——
	# 走真实的动作入口，而不是直接改状态：这样才会触发 _find_good_preview_dist()
	# 之类的进入逻辑，截到的才是玩家实际会看到的画面。
	m._do_action("build")
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "touch3_build.png")

	# —— 4) 建造拖动：把预览推远，验证位置真的变了 ——
	var p0: Vector3 = m.preview.global_position if m.preview != null else Vector3.ZERO
	for i in 12:
		m._on_touch_drag_build(Vector2(0.0, -18.0))
	await get_tree().create_timer(0.6).timeout
	var p1: Vector3 = m.preview.global_position if m.preview != null else Vector3.ZERO
	print("BUILD DRAG moved %.2f -> %.2f (dist=%.2f)" % [
		p0.distance_to(m.player.global_position),
		p1.distance_to(m.player.global_position),
		m.preview_dist])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "touch4_build_moved.png")

	# —— 5) 摇杆拖动定位：长按把摇杆挪到屏幕 40%/58% 处 ——
	m._set_build_mode(false)
	m._refresh_preview()
	if tc != null:
		tc._move_joy_to(Vector2(vs.x * 0.40, vs.y * 0.58))
		tc._joy.set_drag_hint(true)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "touch5_joy_moved.png")
	if tc != null:
		tc.reset_joy_position()

	get_tree().quit()


func _arg_str(args: PackedStringArray, key: String, def: String) -> String:
	var i: int = args.find(key)
	if i < 0 or i + 1 >= args.size():
		return def
	return args[i + 1]


func _arg_pair(args: PackedStringArray, key: String) -> Vector2i:
	var s := _arg_str(args, key, "")
	if s == "":
		return Vector2i.ZERO
	var parts: PackedStringArray = s.split("x")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))
