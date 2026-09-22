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

var _slot_buttons: Array = []
var _slot_del_buttons: Array = []
var _vol_slider: HSlider
var _vol_value: Label
var _quality_option: OptionButton
var _fs_check: CheckBox

# 设置项（暂存内存，落盘到 user://settings.cfg）
var _vol_master := 1.0
var _quality := 1
var _fullscreen := false
var _joystick_offset := Vector2(-1.0, -1.0)   # -1 表示"未自定义"，用默认贴边位置
var _settings_path := "user://settings.cfg"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_build_background()
	_build_ui()

	_save = SaveS.new()
	_save.name = "MenuSaveSystem"
	add_child(_save)
	# SaveSystem.setup 的类型签名是 Node3D，菜单里没有玩家世界；
	# 传背景世界的根节点只为了满足签名——菜单只用它的读取类 API（slot_text/delete_save）。
	_save.setup(_world_ref)

	_load_settings()
	_refresh_slots()
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
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cont.add_child(sub)
	add_child(cont)

	# 背景压暗：菜单 UI 要在任何天色下都可读，所以固定叠一层冷色降亮。
	# 不用全屏黑（会把世界压死），而是偏蓝的暗色 + 低透明度，保留世界颜色。
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.05, 0.07, 0.12, 0.46)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var grad := TextureRect.new()
	grad.name = "Vignette"
	grad.texture = _make_vignette()
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# 顶部标题
	_title_box = VBoxContainer.new()
	_title_box.name = "TitleBox"
	_title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_box.add_theme_constant_override("separation", 2)
	_title_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
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
	_menu_box = VBoxContainer.new()
	_menu_box.name = "MenuBox"
	_menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_box.add_theme_constant_override("separation", 14)
	_menu_box.set_anchors_preset(Control.PRESET_CENTER)
	_menu_box.custom_minimum_size = Vector2(340.0, 0.0)
	root.add_child(_menu_box)

	# 左下角版本号 / 右下角提示
	_ver_label = Label.new()
	_ver_label.text = "v0.3 · Godot 4.7"
	_ver_label.add_theme_font_size_override("font_size", 15)
	_ver_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.75))
	_ver_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
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
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_top = -84.0
	_toast.offset_bottom = -52.0
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)

	# 子面板
	_panels["main"] = _menu_box
	_build_slots_panel(root)
	_build_settings_panel(root)

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
	elif name == "slots":
		_refresh_slots()
	elif name == "settings":
		_refresh_settings()


func _rebuild_main_menu() -> void:
	for c in _menu_box.get_children():
		c.queue_free()

	var has_any := false
	for i in range(SaveS.SLOTS):
		if _has_save(i):
			has_any = true
			break

	_add_menu_button("开始新游戏", func(): _start_new())
	_add_menu_button("读取存档", func(): _show_panel("slots"), not has_any)
	_add_menu_button("设置", func(): _show_panel("settings"))
	_add_menu_button("退出游戏", func(): _quit())


func _add_menu_button(text: String, cb: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.custom_minimum_size = Vector2(340.0, 54.0)
	b.add_theme_font_size_override("font_size", 24)

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


# ——————————————— 存档面板 ———————————————
func _build_slots_panel(root: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "SlotsPanel"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(560.0, 0.0)
	box.visible = false
	root.add_child(box)

	var h := Label.new()
	h.text = "选择存档"
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_font_size_override("font_size", 34)
	h.add_theme_color_override("font_color", C_TITLE)
	h.add_theme_color_override("font_shadow_color", C_TITLE_SHADOW)
	h.add_theme_constant_override("shadow_offset_y", 3)
	box.add_child(h)

	var tip := Label.new()
	tip.text = "当前版本存档：新游戏会覆盖所选槽位"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 15)
	tip.add_theme_color_override("font_color", Color(0.9, 0.88, 0.82, 0.75))
	box.add_child(tip)

	for i in range(SaveS.SLOTS):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var b := Button.new()
		b.custom_minimum_size = Vector2(430.0, 58.0)
		b.add_theme_font_size_override("font_size", 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", C_SUB)
		b.add_theme_color_override("font_hover_color", Color(0.14, 0.10, 0.05))
		b.add_theme_stylebox_override("normal", _btn_style(C_BTN))
		b.add_theme_stylebox_override("hover", _btn_style(C_BTN_HOVER))
		b.add_theme_stylebox_override("pressed", _btn_style(Color(0.62, 0.42, 0.16, 0.9)))
		b.add_theme_stylebox_override("disabled", _disabled_style())
		b.add_theme_color_override("font_disabled_color", Color(0.72, 0.72, 0.72, 0.34))
		var slot_idx := i
		b.pressed.connect(func(): _load_slot(slot_idx))
		row.add_child(b)
		_slot_buttons.append(b)

		var del := Button.new()
		del.text = "删除"
		del.custom_minimum_size = Vector2(96.0, 58.0)
		del.add_theme_font_size_override("font_size", 16)
		del.add_theme_color_override("font_color", Color(1.0, 0.72, 0.66))
		del.add_theme_color_override("font_hover_color", Color(0.14, 0.10, 0.05))
		del.add_theme_stylebox_override("normal", _btn_style(Color(0.32, 0.12, 0.10, 0.62)))
		del.add_theme_stylebox_override("hover", _btn_style(Color(0.90, 0.42, 0.34, 0.90)))
		del.add_theme_stylebox_override("pressed", _btn_style(Color(0.62, 0.20, 0.16, 0.9)))
		del.add_theme_stylebox_override("disabled", _disabled_style())
		del.add_theme_color_override("font_disabled_color", Color(0.72, 0.72, 0.72, 0.30))
		del.pressed.connect(func(): _delete_slot(slot_idx))
		row.add_child(del)
		_slot_del_buttons.append(del)

		box.add_child(row)

	var back := _add_menu_button_to(box, "返回", func(): _show_panel("main"))
	back.custom_minimum_size = Vector2(240.0, 46.0)

	_panels["slots"] = box


func _has_save(slot: int) -> bool:
	var p := "%s/slot_%d.save" % [SaveS.SAVE_DIR, slot]
	return FileAccess.file_exists(p)


func _slot_label(slot: int) -> String:
	if not _has_save(slot):
		return "槽位 %d  ·  空" % (slot + 1)
	# 直接复用 SaveSystem 的展示逻辑（它会读 __meta 里的天数/季节/时间）
	var probe := _save
	if probe != null:
		var txt := probe.slot_text(slot)
		if txt != "":
			return txt
	return "槽位 %d  ·  有存档" % (slot + 1)


func _refresh_slots() -> void:
	if _slot_buttons.is_empty():
		return
	for i in range(_slot_buttons.size()):
		var b: Button = _slot_buttons[i]
		b.text = _slot_label(i)
		var has := _has_save(i)
		b.disabled = not has
		var d: Button = _slot_del_buttons[i]
		d.disabled = not has


func _delete_slot(slot: int) -> void:
	if _save == null:
		return
	_save.delete_save(slot)
	_refresh_slots()
	_toast_msg("已删除槽位 %d" % (slot + 1))


# ——————————————— 设置面板 ———————————————
func _build_settings_panel(root: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "SettingsPanel"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(520.0, 0.0)
	box.visible = false
	root.add_child(box)

	var h := Label.new()
	h.text = "设置"
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_font_size_override("font_size", 34)
	h.add_theme_color_override("font_color", C_TITLE)
	h.add_theme_color_override("font_shadow_color", C_TITLE_SHADOW)
	h.add_theme_constant_override("shadow_offset_y", 3)
	box.add_child(h)

	# 主音量
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 12)
	var l1 := Label.new()
	l1.text = "主音量"
	l1.custom_minimum_size = Vector2(140.0, 0.0)
	l1.add_theme_font_size_override("font_size", 19)
	l1.add_theme_color_override("font_color", C_SUB)
	row1.add_child(l1)
	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0.0
	_vol_slider.max_value = 1.0
	_vol_slider.step = 0.05
	_vol_slider.value = 1.0
	_vol_slider.custom_minimum_size = Vector2(260.0, 32.0)
	_vol_slider.value_changed.connect(_on_vol)
	row1.add_child(_vol_slider)
	_vol_value = Label.new()
	_vol_value.custom_minimum_size = Vector2(64.0, 0.0)
	_vol_value.add_theme_font_size_override("font_size", 18)
	_vol_value.add_theme_color_override("font_color", C_SUB)
	row1.add_child(_vol_value)
	box.add_child(row1)

	# 画质
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	var l2 := Label.new()
	l2.text = "画质"
	l2.custom_minimum_size = Vector2(140.0, 0.0)
	l2.add_theme_font_size_override("font_size", 19)
	l2.add_theme_color_override("font_color", C_SUB)
	row2.add_child(l2)
	_quality_option = OptionButton.new()
	_quality_option.add_item("低（省电）", 0)
	_quality_option.add_item("中（默认）", 1)
	_quality_option.add_item("高（清晰）", 2)
	_quality_option.custom_minimum_size = Vector2(260.0, 36.0)
	_quality_option.item_selected.connect(_on_quality)
	row2.add_child(_quality_option)
	box.add_child(row2)

	# 全屏
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 12)
	var l3 := Label.new()
	l3.text = "全屏显示"
	l3.custom_minimum_size = Vector2(140.0, 0.0)
	l3.add_theme_font_size_override("font_size", 19)
	l3.add_theme_color_override("font_color", C_SUB)
	row3.add_child(l3)
	_fs_check = CheckBox.new()
	_fs_check.text = "开启"
	_fs_check.add_theme_font_size_override("font_size", 18)
	_fs_check.add_theme_color_override("font_color", C_SUB)
	_fs_check.toggled.connect(_on_fullscreen)
	row3.add_child(_fs_check)
	box.add_child(row3)

	# 摇杆位置提示（自定义入口在游戏内触控层，这里只做说明 + 重置）
	var note := Label.new()
	note.text = "提示：手机版进入游戏后可长按左下角摇杆拖动位置，\n松手即保存为该设备的习惯位置。"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(0.88, 0.86, 0.78, 0.78))
	box.add_child(note)

	var row4 := HBoxContainer.new()
	row4.alignment = BoxContainer.ALIGNMENT_CENTER
	row4.add_theme_constant_override("separation", 12)
	var reset := _add_menu_button_to(row4, "重置摇杆位置", func(): _reset_joystick())
	reset.custom_minimum_size = Vector2(240.0, 46.0)
	box.add_child(row4)

	var back := _add_menu_button_to(box, "返回", func(): _show_panel("main"))
	back.custom_minimum_size = Vector2(240.0, 46.0)

	_panels["settings"] = box


func _add_menu_button_to(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340.0, 54.0)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_stylebox_override("normal", _btn_style(C_BTN))
	b.add_theme_stylebox_override("hover", _btn_style(C_BTN_HOVER))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.62, 0.42, 0.16, 0.9)))
	b.add_theme_color_override("font_color", C_SUB)
	b.add_theme_color_override("font_hover_color", Color(0.14, 0.10, 0.05))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _refresh_settings() -> void:
	if _vol_slider != null:
		_vol_slider.value = _vol_master
	if _quality_option != null:
		_quality_option.select(_quality)
	if _fs_check != null:
		_fs_check.button_pressed = _fullscreen


func _on_vol(v: float) -> void:
	_vol_master = v
	if _vol_value != null:
		_vol_value.text = "%d%%" % int(round(v * 100.0))
	_apply_audio_volume()
	_save_settings()


func _apply_audio_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, _vol_master <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(clampf(_vol_master, 0.001, 1.0)))


func _on_quality(idx: int) -> void:
	_quality = idx
	var vp := get_viewport()
	match idx:
		0:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.positional_shadow_atlas_size = 1024
		1:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.positional_shadow_atlas_size = 2048
		2:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.positional_shadow_atlas_size = 4096
	_save_settings()


func _on_fullscreen(on: bool) -> void:
	_fullscreen = on
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	)
	_save_settings()


func _reset_joystick() -> void:
	_joystick_offset = Vector2(-1.0, -1.0)
	_save_settings()
	_toast_msg("摇杆位置已重置为默认")


# ——————————————— 设置持久化 ———————————————
func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(_settings_path) != OK:
		_on_vol(_vol_master)
		return
	_vol_master = float(cf.get_value("audio", "master", 1.0))
	_quality = int(cf.get_value("video", "quality", 1))
	_fullscreen = bool(cf.get_value("video", "fullscreen", false))
	_joystick_offset = Vector2(
		float(cf.get_value("touch", "joy_x", -1.0)),
		float(cf.get_value("touch", "joy_y", -1.0))
	)
	_apply_audio_volume()
	if _vol_value != null:
		_vol_value.text = "%d%%" % int(round(_vol_master * 100.0))
	_on_quality(_quality)
	if _fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", _vol_master)
	cf.set_value("video", "quality", _quality)
	cf.set_value("video", "fullscreen", _fullscreen)
	cf.set_value("touch", "joy_x", _joystick_offset.x)
	cf.set_value("touch", "joy_y", _joystick_offset.y)
	cf.save(_settings_path)


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
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(fade)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func(): get_tree().change_scene_to_file(GAME_SCENE))


func _quit() -> void:
	_save_settings()
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
