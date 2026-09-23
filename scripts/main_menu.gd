extends Control
## 主界面 —— 标题 + 四个菜单项 + 存档列表 + 设置
##
## 【背景实现】WorldBG 是 SubViewportContainer，内含一个精简 3D 世界（MenuWorld）。
## 它是真实渲染的，昼夜与天气会自己走，所以背景是"游戏内世界的随机动态时间天气变化"，
## 不是预烘焙的静态图或视频。
##
## 【流程】启动进本菜单 → 点"开始/继续" → change_scene_to_file 到 main.tscn。
## main.tscn 侧读取 GameBus.pending_load_slot 决定是开新档还是读档。

const MenuWorldS := preload("res://scripts/menu_world.gd")
const SaveS := preload("res://scripts/save_system.gd")

const GAME_SCENE := "res://scenes/main.tscn"

## 主题色（暖色澳洲内陆调）
const C_TITLE := Color(1.0, 0.86, 0.62)
const C_TITLE_SHADOW := Color(0.16, 0.09, 0.03, 0.85)
const C_SUB := Color(0.92, 0.88, 0.78)
const C_BTN := Color(0.14, 0.13, 0.12, 0.62)
const C_BTN_HOVER := Color(0.85, 0.62, 0.26, 0.85)
const C_BTN_DISABLED := Color(0.10, 0.10, 0.10, 0.35)

var _save: SaveSystem
var _world_ref: Node3D = null        # SaveSystem.setup 需要 Node3D；菜单态没有世界，传背景世界
var _panels: Dictionary = {}      # name -> Control
var _menu_box: VBoxContainer
var _title_box: VBoxContainer
var _ver_label: Label
var _toast: Label

var _slots: SaveSlotsPanel
var _settings: SettingsPanel

## 【为什么设置项不在这里】设置要落盘到 user://settings.cfg，主界面和游戏内
## 暂停菜单各写一份读写逻辑，将来加一项就得改两处。所以读写只在
## scripts/settings_panel.gd 里有一份，两边共用同一个控件类。


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_build_background()
	_build_ui()

	_save = SaveS.new()
	_save.name = "MenuSaveSystem"
	add_child(_save)
	# SaveSystem.setup 的类型签名是 Node3D，菜单里没有玩家世界；
	# 传背景世界的根节点只为了满足签名——菜单只用它的读取类 API（slot_text/delete_save）。
	_save.setup(_world_ref)
	# 存档列表复用菜单自己的 SaveSystem：它已经 setup 过，
	# 再让面板自己 new 一个会和这份状态对不上。
	if _slots != null:
		_slots.set_save_system(_save)

	_show_panel("main")
	_check_auto_shot()


# ——————————————— 自动截图（--auto-shot，仅调试用） ———————————————
func _check_auto_shot() -> void:
	if not OS.get_cmdline_args().has("--auto-shot"):
		return
	var base := _shot_dir()
	var args := OS.get_cmdline_args()
	var only_main := args.has("--shot-main-only")

	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "menu1_main.png")

	if only_main:
		get_tree().quit()
		return

	_show_panel("slots")
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "menu2_slots.png")

	_show_panel("settings")
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "menu3_settings.png")

	# 夜晚 + 雨天：验证背景世界确实在跑时间与天气。
	# 天气的视觉强度靠 Environment 的雾/天光渐变，_i_rain 是 move_toward 累加的，
	# 必须给它足够时间收敛，否则拍出来还是晴天。
	_show_panel("main")
	var world := _world_ref as MenuWorld
	if world != null:
		world.dn.time = 0.30
		if world.season != null:
			world.season.weather = "rain"
			world.season.weather_left = 9.9   # 别让它在我们拍照前又切走
			world.season._apply_now()
	await get_tree().create_timer(3.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "menu4_rain.png")

	# 天气摘要：Windows GUI 模式下 print 不走 stdout，直接写文件以便自动验证。
	# 注意只读 SeasonManager 真实存在的属性——fog_mult/sun_mult 是 _apply_now 的局部量，不是字段。
	if world != null and world.season != null:
		var line := "weather=%s season=%s time=%s day=%d\n" % [
			world.season.weather, world.season.season_name,
			world.dn.clock_string(), world.dn.day_count
		]
		var lf := FileAccess.open(base + "menu_weather.txt", FileAccess.WRITE)
		if lf != null:
			lf.store_string(line)
			lf.close()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "menu5_rain_late.png")

	get_tree().quit()


func _shot_dir() -> String:
	var args := OS.get_cmdline_args()
	var di: int = args.find("--shot-dir")
	if di >= 0 and di + 1 < args.size():
		var d: String = args[di + 1]
		if not d.ends_with("/") and not d.ends_with("\\"):
			d += "/"
		return d
	var root := ProjectSettings.globalize_path("res://")
	if not root.ends_with("/"):
		root += "/"
	return root


# ——————————————— 背景 ———————————————
func _build_background() -> void:
	var sub := SubViewport.new()
	sub.name = "BGViewport"
	sub.size = Vector2i(1440, 810)
	sub.own_world_3d = true          # 独立世界，绝不污染主场景的 3D 世界
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.msaa_3d = Viewport.MSAA_2X
	sub.transparent_bg = false

	var world: Node3D = MenuWorldS.new()
	world.name = "MenuWorld"
	sub.add_child(world)
	_world_ref = world

	var cont := SubViewportContainer.new()
	cont.name = "WorldBG"
	cont.stretch = true
	cont.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cont.add_child(sub)
	add_child(cont)

	# 背景压暗：菜单 UI 要在任何天色下都可读，所以固定叠一层冷色降亮。
	# 不用全屏黑（会把世界压死），而是偏蓝的暗色 + 低透明度，保留世界颜色。
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.05, 0.07, 0.12, 0.46)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var grad := TextureRect.new()
	grad.name = "Vignette"
	grad.texture = _make_vignette()
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grad)


## 程序化生成一个上下压暗、中段透明的渐变贴图（纯代码，零素材）
func _make_vignette() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.03, 0.06, 0.72))
	g.set_color(1, Color(0.02, 0.03, 0.06, 0.58))
	g.add_point(0.42, Color(0.02, 0.03, 0.06, 0.10))
	g.add_point(0.72, Color(0.02, 0.03, 0.06, 0.30))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 16
	t.height = 256
	return t


# ——————————————— UI 骨架 ———————————————
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UiLayer"
	add_child(layer)

	var root := Control.new()
	root.name = "UiRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# 顶部标题
	_title_box = VBoxContainer.new()
	_title_box.name = "TitleBox"
	_title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_box.add_theme_constant_override("separation", 2)
	_title_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title_box.offset_top = 84.0
	_title_box.offset_bottom = 230.0
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_title_box)

	var title := Label.new()
	title.text = "DINKUM TOWN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 88)
	title.add_theme_color_override("font_color", C_TITLE)
	title.add_theme_color_override("font_shadow_color", C_TITLE_SHADOW)
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_constant_override("shadow_outline_size", 10)
	_title_box.add_child(title)

	var sub_title := Label.new()
	sub_title.text = "澳洲内陆小镇 · 生存与建造"
	sub_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_title.add_theme_font_size_override("font_size", 22)
	sub_title.add_theme_color_override("font_color", C_SUB)
	sub_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	sub_title.add_theme_constant_override("shadow_offset_y", 2)
	_title_box.add_child(sub_title)

	# 中央菜单盒
	# 【为什么套 CenterContainer】给 VBoxContainer 设 PRESET_CENTER 是个陷阱：
	# 它在按钮加进来之前就把 offsets 按"当时最小尺寸"（0）算死，之后按钮撑开
	# 只会往右下长，菜单会整体偏离屏幕中心。CenterContainer 每次重排都会重新居中。
	var center := CenterContainer.new()
	center.name = "MenuCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	_menu_box = VBoxContainer.new()
	_menu_box.name = "MenuBox"
	_menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_box.add_theme_constant_override("separation", 14)
	_menu_box.custom_minimum_size = Vector2(340.0, 0.0)
	center.add_child(_menu_box)

	# 左下角版本号 / 右下角提示
	_ver_label = Label.new()
	_ver_label.text = "v0.3 · Godot 4.7"
	_ver_label.add_theme_font_size_override("font_size", 15)
	_ver_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.75))
	_ver_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_ver_label.offset_left = 22.0
	_ver_label.offset_top = -40.0
	_ver_label.offset_bottom = -16.0
	_ver_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_ver_label)

	_toast = Label.new()
	_toast.name = "Toast"
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_toast.add_theme_constant_override("shadow_offset_y", 2)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_top = -84.0
	_toast.offset_bottom = -52.0
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)

	# 子面板（存档列表与设置是与宿主无关的纯控件，与暂停菜单共用同一个类）
	_panels["main"] = _menu_box

	_slots = SaveSlotsPanel.new()
	_slots.visible = false
	_slots.slot_picked.connect(_load_slot)
	_slots.back_requested.connect(func(): _show_panel("main"))
	root.add_child(_slots)
	_panels["slots"] = _slots

	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.back_requested.connect(func(): _show_panel("main"))
	root.add_child(_settings)
	_panels["settings"] = _settings

	if GameBus != null:
		GameBus.toast.connect(_on_toast)


# ——————————————— 主菜单 ———————————————
func _show_panel(name: String) -> void:
	for k in _panels.keys():
		var c: Control = _panels[k]
		c.visible = (k == name)
	_title_box.visible = (name == "main")

	if name == "main":
		_rebuild_main_menu()
	elif name == "slots" and _slots != null:
		_slots.set_ui_scale(_ui_scale())
		_slots.refresh()
	elif name == "settings" and _settings != null:
		_settings.set_ui_scale(_ui_scale())
		_settings.refresh()


## 主界面的分辨率缩放：与暂停菜单同一套算法（短边 / 810，夹在 0.85~1.8）。
## 手机上按 1440x810 定死的 54px 按钮只有屏高的 5%，点不准。
func _ui_scale() -> float:
	var vs := get_viewport().get_visible_rect().size
	if vs.x < 8.0 or vs.y < 8.0:
		return 1.0
	return clampf(minf(vs.x, vs.y) / 810.0, 0.85, 1.8)


func _rebuild_main_menu() -> void:
	for c in _menu_box.get_children():
		c.queue_free()

	var has_any := false
	if _save != null:
		for i in range(SaveS.SLOTS):
			if _save.has_save(i):
				has_any = true
				break

	_add_menu_button("开始新游戏", func(): _start_new())
	_add_menu_button("读取存档", func(): _show_panel("slots"), not has_any)
	_add_menu_button("设置", func(): _show_panel("settings"))
	_add_menu_button("退出游戏", func(): _quit())


func _add_menu_button(text: String, cb: Callable, disabled := false) -> Button:
	var k := _ui_scale()
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.custom_minimum_size = Vector2(340.0, 54.0) * k
	b.add_theme_font_size_override("font_size", maxi(14, int(24.0 * k)))

	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BTN
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.86, 0.68, 0.38, 0.55)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", _btn_style(C_BTN_HOVER))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.62, 0.42, 0.16, 0.9)))
	# 禁用态：明显区别于可用态（无边框 + 极低透明度），避免玩家点了没反应却不知道
	b.add_theme_stylebox_override("disabled", _disabled_style())
	b.add_theme_color_override("font_color", C_SUB)
	b.add_theme_color_override("font_hover_color", Color(0.14, 0.10, 0.05))
	b.add_theme_color_override("font_disabled_color", Color(0.72, 0.72, 0.72, 0.34))

	if not disabled:
		b.pressed.connect(cb)
	_menu_box.add_child(b)
	return b


func _btn_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.96, 0.82, 0.52, 0.75)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	return sb


## 禁用态：明显区别于可用态（无边框 + 极低透明度），避免玩家点了没反应却不知道
func _disabled_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.09, 0.28)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.55, 0.55, 0.55, 0.18)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	return sb



# ——————————————— 流程 ———————————————
func _start_new() -> void:
	if GameBus != null:
		# -2 是"新游戏"哨兵：main 侧看到它就跳过读档、从零开始
		GameBus.pending_load_slot = -2
	_fade_to_game()


func _load_slot(slot: int) -> void:
	if GameBus != null:
		GameBus.pending_load_slot = slot
	_fade_to_game()


func _fade_to_game() -> void:
	# 简单淡出，避免切场景时画面生硬跳变
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(fade)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func(): get_tree().change_scene_to_file(GAME_SCENE))


func _quit() -> void:
	# 不需要在这里存设置：SettingsPanel 每次改动都会立刻落盘，
	# 退出时再存一次反而可能把默认值写回去覆盖掉玩家的调整。
	get_tree().quit()


func _on_toast(msg: String) -> void:
	_toast_msg(msg)


func _toast_msg(msg: String) -> void:
	if _toast == null:
		return
	_toast.text = msg
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.6)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _panels.get("slots", null) != null and _panels["slots"].visible:
			_show_panel("main")
			get_viewport().set_input_as_handled()
		elif _panels.get("settings", null) != null and _panels["settings"].visible:
			_show_panel("main")
			get_viewport().set_input_as_handled()
