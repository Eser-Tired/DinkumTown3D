extends Control
class_name SettingsPanel
## 设置面板 —— 主界面与游戏内暂停菜单共用同一份
##
## 【为什么要抽成独立类】设置项要落盘到 user://settings.cfg。两个菜单如果各写一份
## 读写逻辑，将来加一个设置项就得改两处，漏一处就是"主界面改了、进游戏又变回去"。
## 持久化只能有一个持有者，所以这里是唯一读写 settings.cfg 的地方。
##
## 【为什么是 Control 而不是 CanvasLayer】面板要挂进不同的宿主
## （主界面挂在自己的 UiLayer 下，暂停菜单挂在 CanvasLayer 下）。
## 自带一层会多一层多余的变换，而且显示层级必须由宿主决定，不该由面板自己拍。
##
## 【为什么用 GameBus.toast 而不是自带提示条】两个宿主的 toast 位置不同
## （主界面在底部，游戏内是 HUD 的浮动提示）。它们都已经监听 GameBus.toast，
## 这里只管发信号，显示交给宿主。

signal back_requested()

const SETTINGS_PATH := "user://settings.cfg"

const C_TITLE := Color(0.98, 0.84, 0.60)
const C_SHADOW := Color(0.16, 0.09, 0.03, 0.85)
const C_TEXT := Color(0.92, 0.88, 0.78)
const C_TEXT_DIM := Color(0.88, 0.86, 0.78, 0.78)
const C_BTN := Color(0.14, 0.13, 0.12, 0.72)
const C_BTN_HOVER := Color(0.85, 0.62, 0.26, 0.88)
const C_BTN_PRESSED := Color(0.62, 0.42, 0.16, 0.92)

## 布局基准（k = 1 时的像素值），set_ui_scale 按分辨率重算
const BASE_ROW_LABEL_W := 140.0
const BASE_SLIDER_W := Vector2(260.0, 32.0)
const BASE_OPTION_W := Vector2(260.0, 36.0)
const BASE_BTN := Vector2(340.0, 54.0)
const BASE_BTN_SMALL := Vector2(240.0, 46.0)
const BASE_BOX_W := 520.0
const BASE_TITLE_FONT := 34
const BASE_ROW_FONT := 19
const BASE_BTN_FONT := 22
const BASE_SMALL_FONT := 18
const BASE_TIP_FONT := 15
const BASE_SEP := 14.0

var _vol_master := 1.0
var _quality := 1
var _fullscreen := false
var _joy_offset := Vector2(-1.0, -1.0)   ## -1 = 未自定义，用默认贴边位置

var _center: CenterContainer
var _box: VBoxContainer
var _title: Label
var _note: Label
var _reset_btn: Button
var _back_btn: Button
var _row_labels: Array = []
var _vol_slider: HSlider
var _vol_value: Label
var _quality_option: OptionButton
var _fs_check: CheckBox


## 【两个必须一起踩的坑，都别重犯】
## 1) 用 set_anchors_preset(PRESET_CENTER) 居中：它在内容还没添加时就把 offsets
##    按"当前尺寸"（0）写死，之后内容撑开只会往右下长，面板永远贴在中心右下角。
## 2) 用 set_anchors_preset(PRESET_FULL_RECT) 铺满：它【只改锚点、不清 offsets】，
##    新建控件 offsets 是 (0,0,-W,-H) 这种"保持原尺寸"的值，结果 size 还是 0，
##    CenterContainer 自己就是 0 大，"居中"等于原地不动。
## 正确写法是 set_anchors_and_offsets_preset()：锚点和偏移一起设，size 立刻等于父级。
## 这样尺寸怎么变都会重新居中，set_ui_scale 之后也不需要手动补偏移。
func _ready() -> void:
	name = "SettingsPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_center = CenterContainer.new()
	_center.name = "Center"
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 容器不吃输入：点击要么落在按钮上，要么穿透到宿主的遮罩，由它决定是否吞掉
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	_build()
	load_settings()


# ——————————————— 构建 ———————————————
func _build() -> void:
	_box = VBoxContainer.new()
	var box := _box
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(BASE_SEP))
	box.custom_minimum_size = Vector2(BASE_BOX_W, 0.0)
	_center.add_child(box)

	_title = Label.new()
	_title.text = "设置"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", BASE_TITLE_FONT)
	_title.add_theme_color_override("font_color", C_TITLE)
	_title.add_theme_color_override("font_shadow_color", C_SHADOW)
	_title.add_theme_constant_override("shadow_offset_y", 3)
	box.add_child(_title)

	# —— 主音量 ——
	box.add_child(_row_volume())

	# —— 画质 ——
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	row2.add_child(_label("画质", 140.0))
	_quality_option = OptionButton.new()
	_quality_option.add_item("低（省电）", 0)
	_quality_option.add_item("中（默认）", 1)
	_quality_option.add_item("高（清晰）", 2)
	_quality_option.custom_minimum_size = BASE_OPTION_W
	_quality_option.item_selected.connect(_on_quality)
	row2.add_child(_quality_option)
	box.add_child(row2)

	# —— 全屏 ——
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 12)
	row3.add_child(_label("全屏显示", 140.0))
	_fs_check = CheckBox.new()
	_fs_check.text = "开启"
	_fs_check.add_theme_font_size_override("font_size", BASE_SMALL_FONT)
	_fs_check.add_theme_color_override("font_color", C_TEXT)
	_fs_check.toggled.connect(_on_fullscreen)
	row3.add_child(_fs_check)
	box.add_child(row3)

	_note = Label.new()
	_note.text = "提示：手机版进入游戏后可长按左下角摇杆拖动位置，\n松手即保存为该设备的习惯位置。"
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", BASE_TIP_FONT)
	_note.add_theme_color_override("font_color", C_TEXT_DIM)
	box.add_child(_note)

	var row4 := HBoxContainer.new()
	row4.alignment = BoxContainer.ALIGNMENT_CENTER
	row4.add_theme_constant_override("separation", 12)
	_reset_btn = _button("重置摇杆位置", func(): _reset_joystick())
	_reset_btn.custom_minimum_size = BASE_BTN_SMALL
	row4.add_child(_reset_btn)
	box.add_child(row4)

	_back_btn = _button("返回", func(): back_requested.emit())
	_back_btn.custom_minimum_size = BASE_BTN_SMALL
	box.add_child(_back_btn)


func _row_volume() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_label("主音量", 140.0))
	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0.0
	_vol_slider.max_value = 1.0
	_vol_slider.step = 0.05
	_vol_slider.value = 1.0
	_vol_slider.custom_minimum_size = BASE_SLIDER_W
	_vol_slider.value_changed.connect(_on_vol)
	row.add_child(_vol_slider)
	_vol_value = Label.new()
	_vol_value.custom_minimum_size = Vector2(64.0, 0.0)
	_vol_value.add_theme_font_size_override("font_size", BASE_SMALL_FONT)
	_vol_value.add_theme_color_override("font_color", C_TEXT)
	row.add_child(_vol_value)
	return row


func _label(text: String, w: float) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(w, 0.0)
	l.add_theme_font_size_override("font_size", BASE_ROW_FONT)
	l.add_theme_color_override("font_color", C_TEXT)
	_row_labels.append(l)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BASE_BTN
	b.add_theme_font_size_override("font_size", BASE_BTN_FONT)
	b.add_theme_stylebox_override("normal", _btn_style(C_BTN))
	b.add_theme_stylebox_override("hover", _btn_style(C_BTN_HOVER))
	b.add_theme_stylebox_override("pressed", _btn_style(C_BTN_PRESSED))
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", Color(0.14, 0.10, 0.05))
	b.pressed.connect(cb)
	return b


func _btn_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.96, 0.82, 0.52, 0.75)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	return sb


# ——————————————— 回调 ———————————————
func _on_vol(v: float) -> void:
	_vol_master = v
	if _vol_value != null:
		_vol_value.text = "%d%%" % int(round(v * 100.0))
	_apply_vol()
	save_settings()


func _on_quality(idx: int) -> void:
	_quality = idx
	_apply_quality()
	save_settings()


func _on_fullscreen(on: bool) -> void:
	_fullscreen = on
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	)
	save_settings()


## 重置摇杆只写配置是不够的：已经挂着的 TouchControls 不会重读文件。
## 所以额外发一个动作，让 main 转交给触控层立刻恢复默认位置。
func _reset_joystick() -> void:
	_joy_offset = Vector2(-1.0, -1.0)
	save_settings()
	if GameBus != null:
		GameBus.touch_action.emit("reset_joy")
		GameBus.toast.emit("摇杆位置已重置为默认")


# ——————————————— 应用 ———————————————
func _apply_vol() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, _vol_master <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(clampf(_vol_master, 0.001, 1.0)))


func _apply_quality() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	match _quality:
		0:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.positional_shadow_atlas_size = 1024
		1:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.positional_shadow_atlas_size = 2048
		2:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.positional_shadow_atlas_size = 4096


# ——————————————— 持久化 ———————————————
func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		_apply_vol()
		_sync_widgets()
		return
	_vol_master = float(cf.get_value("audio", "master", 1.0))
	_quality = int(cf.get_value("video", "quality", 1))
	_fullscreen = bool(cf.get_value("video", "fullscreen", false))
	_joy_offset = Vector2(
		float(cf.get_value("touch", "joy_x", -1.0)),
		float(cf.get_value("touch", "joy_y", -1.0))
	)
	_apply_vol()
	_sync_widgets()
	_apply_quality()
	if _fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## 只把内存里的值刷到控件上，不触发回调（否则会反过来触发保存）
func _sync_widgets() -> void:
	if _vol_slider != null:
		_vol_slider.set_value_no_signal(_vol_master)
	if _vol_value != null:
		_vol_value.text = "%d%%" % int(round(_vol_master * 100.0))
	if _quality_option != null:
		_quality_option.select(_quality)
	if _fs_check != null:
		_fs_check.set_pressed_no_signal(_fullscreen)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", _vol_master)
	cf.set_value("video", "quality", _quality)
	cf.set_value("video", "fullscreen", _fullscreen)
	cf.set_value("touch", "joy_x", _joy_offset.x)
	cf.set_value("touch", "joy_y", _joy_offset.y)
	cf.save(SETTINGS_PATH)


## 供宿主在显示面板前调用：控件可能被别的入口改过（如游戏内改了音量）
func refresh() -> void:
	_sync_widgets()


## 按分辨率缩放。宿主（主界面 / 暂停菜单）在显示前调用。
## 不缩放的话手机上 19px 的说明文字和 54px 高的按钮都太小，读不清也点不准。
func set_ui_scale(k: float) -> void:
	if k <= 0.0:
		return
	if _box != null:
		_box.add_theme_constant_override("separation", int(BASE_SEP * k))
		_box.custom_minimum_size = Vector2(BASE_BOX_W * k, 0.0)
	if _title != null:
		_title.add_theme_font_size_override("font_size", maxi(18, int(BASE_TITLE_FONT * k)))
	if _note != null:
		_note.add_theme_font_size_override("font_size", maxi(11, int(BASE_TIP_FONT * k)))
	if _vol_slider != null:
		_vol_slider.custom_minimum_size = BASE_SLIDER_W * k
	if _quality_option != null:
		_quality_option.custom_minimum_size = BASE_OPTION_W * k
		_quality_option.add_theme_font_size_override("font_size", maxi(12, int(BASE_ROW_FONT * k)))
	if _vol_value != null:
		_vol_value.add_theme_font_size_override("font_size", maxi(12, int(BASE_SMALL_FONT * k)))
	if _fs_check != null:
		_fs_check.add_theme_font_size_override("font_size", maxi(12, int(BASE_SMALL_FONT * k)))
	for l in _row_labels:
		if is_instance_valid(l):
			var lb: Label = l
			lb.custom_minimum_size = Vector2(BASE_ROW_LABEL_W * k, 0.0)
			lb.add_theme_font_size_override("font_size", maxi(12, int(BASE_ROW_FONT * k)))
	if _reset_btn != null:
		_reset_btn.custom_minimum_size = BASE_BTN_SMALL * k
		_reset_btn.add_theme_font_size_override("font_size", maxi(13, int(BASE_BTN_FONT * k)))
	if _back_btn != null:
		_back_btn.custom_minimum_size = BASE_BTN_SMALL * k
		_back_btn.add_theme_font_size_override("font_size", maxi(13, int(BASE_BTN_FONT * k)))
