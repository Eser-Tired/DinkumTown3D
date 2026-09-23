extends CanvasLayer
class_name PauseMenu
## 游戏内暂停菜单 —— Esc / 系统返回键唤起，含：继续游戏、读取存档、设置、退出游戏
##
## 【为什么 layer = 40】必须盖住背包(30)、触控层(20)、HUD(10)。
## 差一层就会出现"点菜单按钮的同时角色也挥了一刀"。
##
## 【为什么 process_mode = ALWAYS】本菜单靠 get_tree().paused = true 真正暂停游戏。
## 而 paused 会让所有 INHERIT 节点的 _process / _input 一起停——包括本菜单自己，
## 结果就是菜单弹出来却点不动、关不掉。所以这一层必须显式声明"暂停也照常处理"。
##
## 【为什么不复用 main_menu.gd】主界面自带一个 SubViewport 3D 背景世界，
## 游戏内菜单要的是"当前这一局的画面"被压暗，背景不能另起一个世界。
## 两者骨架不同，共用会塞进一堆 if is_in_game 分支。但设置面板与存档列表
## 是与宿主无关的纯控件，抽成了 SettingsPanel / SaveSlotsPanel 共用。

signal closed()
signal quit_requested()
signal load_requested(slot: int)

const C_TITLE := Color(1.0, 0.86, 0.62)
const C_SHADOW := Color(0.16, 0.09, 0.03, 0.85)
const C_SUB := Color(0.92, 0.88, 0.78)
const C_BTN := Color(0.14, 0.13, 0.12, 0.72)
const C_BTN_HOVER := Color(0.85, 0.62, 0.26, 0.88)
const C_BTN_PRESSED := Color(0.62, 0.42, 0.16, 0.92)
const C_QUIT := Color(0.32, 0.12, 0.10, 0.72)
const C_QUIT_HOVER := Color(0.90, 0.42, 0.34, 0.92)
const C_QUIT_PRESSED := Color(0.62, 0.20, 0.16, 0.92)

var _root: Control
var _main_box: VBoxContainer
var _slots: SaveSlotsPanel
var _settings: SettingsPanel
var _panels: Dictionary = {}
var _pending_sv: SaveSystem = null      ## _ready 之前注入的存档系统，_build 里补挂

## 布局基准（对应 k = 1 时的像素值），_apply_scale 按分辨率重算
const BASE_BTN := Vector2(340.0, 54.0)
const BASE_BTN_FONT := 24
const BASE_TITLE_FONT := 46
const BASE_TIP_FONT := 15
const BASE_SEP := 14.0

var _main_btns: Array = []
var _title_label: Label
var _tip_label: Label


func _ready() -> void:
	name = "PauseMenu"
	layer = 40
	# 关键：见文件头注释。少了这行菜单会变成一张点不动的死图。
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


# ——————————————— 构建 ———————————————
func _build() -> void:
	# 全屏压暗 + 吃掉点击，防止穿透到下面的世界 / 触控层
	# 【为什么用 set_anchors_and_offsets_preset】set_anchors_preset 只改锚点、
	# 不清 offsets，对刚 new 出来 size=0 的控件会留下 offset_right=-W 这种值，
	# 结果 size 还是 0、什么都盖不住。锚点和偏移必须一起设。
	var bg := ColorRect.new()
	bg.name = "Dim"
	# 0.82 而不是 0.6 左右：下面的 HUD 与触控按钮仍然可见，压得太浅会和菜单按钮
	# 挤在一起分不清哪层是活的。再深一点又会让玩家认不出自己站在哪。
	bg.color = Color(0.03, 0.04, 0.07, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# 【为什么套 CenterContainer 而不是给 _main_box 设 PRESET_CENTER】
	# PRESET_CENTER 在内容添加之前就把 offsets 按"当时的最小尺寸"（0）算死了，
	# 之后按钮撑开只会往右下长，整块菜单会贴在中心偏右下——主界面一直有这个问题。
	# CenterContainer 在每次尺寸变化后都会重新居中，_apply_scale 之后也不用补偿。
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_main_box = VBoxContainer.new()
	_main_box.name = "MainBox"
	_main_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_box.add_theme_constant_override("separation", int(BASE_SEP))
	_main_box.custom_minimum_size = Vector2(BASE_BTN.x, 0.0)
	center.add_child(_main_box)

	_title_label = Label.new()
	_title_label.text = "暂停"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", BASE_TITLE_FONT)
	_title_label.add_theme_color_override("font_color", C_TITLE)
	_title_label.add_theme_color_override("font_shadow_color", C_SHADOW)
	_title_label.add_theme_constant_override("shadow_offset_y", 4)
	_main_box.add_child(_title_label)

	_tip_label = Label.new()
	_tip_label.text = "时间与天气已暂停"
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.add_theme_font_size_override("font_size", BASE_TIP_FONT)
	_tip_label.add_theme_color_override("font_color", Color(0.88, 0.86, 0.78, 0.75))
	_main_box.add_child(_tip_label)

	_main_btns.append(_add_button("继续游戏", func(): close()))
	_main_btns.append(_add_button("读取存档", func(): _show_panel("slots")))
	_main_btns.append(_add_button("设置", func(): _show_panel("settings")))
	_main_btns.append(_add_button("退出游戏", func(): _quit(), true))

	# —— 子面板 ——
	_slots = SaveSlotsPanel.new()
	_slots.set_header("读取存档", "读取会丢弃当前未保存的进度")
	_slots.visible = false
	_slots.slot_picked.connect(func(slot: int): load_requested.emit(slot))
	_slots.back_requested.connect(func(): _show_panel("main"))
	_root.add_child(_slots)

	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.back_requested.connect(func(): _show_panel("main"))
	_root.add_child(_settings)

	_panels["main"] = _main_box
	_panels["slots"] = _slots
	_panels["settings"] = _settings

	if _pending_sv != null:
		_slots.set_save_system(_pending_sv)
		_pending_sv = null


func _add_button(text: String, cb: Callable, danger := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BASE_BTN
	b.add_theme_font_size_override("font_size", BASE_BTN_FONT)
	if danger:
		b.add_theme_stylebox_override("normal", _btn_style(C_QUIT))
		b.add_theme_stylebox_override("hover", _btn_style(C_QUIT_HOVER))
		b.add_theme_stylebox_override("pressed", _btn_style(C_QUIT_PRESSED))
	else:
		b.add_theme_stylebox_override("normal", _btn_style(C_BTN))
		b.add_theme_stylebox_override("hover", _btn_style(C_BTN_HOVER))
		b.add_theme_stylebox_override("pressed", _btn_style(C_BTN_PRESSED))
	b.add_theme_color_override("font_color", C_SUB)
	b.add_theme_color_override("font_hover_color", Color(0.14, 0.10, 0.05))
	b.pressed.connect(cb)
	_main_box.add_child(b)
	return b


func _btn_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.86, 0.68, 0.38, 0.55)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	return sb


# ——————————————— 开关 ———————————————
func is_open() -> bool:
	return visible


## 按分辨率重算尺寸。
## 【为什么必须做】基准尺寸是按 1440x810 定的，放到 2340x1080 的手机上
## 54px 高的按钮只有屏高的 5%，手指点不准。这是移动端 UI 的通用要求，
## 每次 open 都算一遍是因为分辨率可能中途变（旋转、分屏）。
func _apply_scale() -> void:
	var vs := get_viewport().get_visible_rect().size
	if vs.x < 8.0 or vs.y < 8.0:
		return
	# 取短边：横竖屏都能得到同一套观感，且不会让窄边塞不下
	var k := clampf(minf(vs.x, vs.y) / 810.0, 0.85, 1.8)
	_main_box.add_theme_constant_override("separation", int(BASE_SEP * k))
	if _title_label != null:
		_title_label.add_theme_font_size_override("font_size", maxi(20, int(BASE_TITLE_FONT * k)))
	if _tip_label != null:
		_tip_label.add_theme_font_size_override("font_size", maxi(11, int(BASE_TIP_FONT * k)))
	for b in _main_btns:
		if not is_instance_valid(b):
			continue
		var btn: Button = b
		btn.custom_minimum_size = BASE_BTN * k
		btn.add_theme_font_size_override("font_size", maxi(13, int(BASE_BTN_FONT * k)))
	# 子面板与主菜单共用，缩放要一起传下去，否则点进设置会突然变小
	if _slots != null:
		_slots.set_ui_scale(k)
	if _settings != null:
		_settings.set_ui_scale(k)


func open() -> void:
	_apply_scale()
	_show_panel("main")
	visible = true
	# 真暂停：玩家、动物、昼夜、天气一起停。这是"暂停菜单"该有的语义，
	# 也是移动端切后台回来不至于发现过了三天的原因。
	get_tree().paused = true
	if GameBus != null:
		GameBus.ui_blocking = true


func close() -> void:
	if not visible:
		return
	visible = false
	# 必须先解除暂停再发信号：宿主可能在 closed 里切场景，
	# 带着 paused 切过去会让新场景整个卡死。
	get_tree().paused = false
	if GameBus != null:
		GameBus.ui_blocking = false
	closed.emit()


## 【为什么 Esc 必须由菜单自己接】菜单靠 get_tree().paused = true 暂停游戏，
## 而 main.gd 是默认的 INHERIT 模式，暂停时它的 _unhandled_input 根本不会被调用——
## 指望 main 处理 Esc 就会"打开得了、关不掉"。本层声明了 ALWAYS，只有它收得到。
## Android 的系统返回键仍然走 main._notification（那个不受 paused 影响），
## 两处最终都汇到 go_back()。
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# ui_cancel 覆盖手柄 B 与部分平台的返回键；keycode 判断兜住合成事件
	if event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and event.pressed and not event.echo
				and event.keycode == KEY_ESCAPE):
		go_back()
		get_viewport().set_input_as_handled()


## "退出这一层"：在子面板就回首页，在首页就关菜单继续游戏。
## 返回 true 表示这一下被菜单吃掉了，宿主不要再往下派发。
func go_back() -> bool:
	if not visible:
		return false
	if _slots != null and _slots.visible:
		_show_panel("main")
		return true
	if _settings != null and _settings.visible:
		_show_panel("main")
		return true
	close()
	return true


func _show_panel(name: String) -> void:
	for k in _panels.keys():
		var c: Control = _panels[k]
		if c != null:
			c.visible = (k == name)
	if name == "slots" and _slots != null:
		_slots.refresh()
	elif name == "settings" and _settings != null:
		_settings.refresh()


func _quit() -> void:
	# 切场景前必须解除暂停，否则主界面会以 paused 状态启动，一动不动
	visible = false
	get_tree().paused = false
	if GameBus != null:
		GameBus.ui_blocking = false
	quit_requested.emit()


## 供宿主注入正在使用的存档系统，避免面板自己又造一个实例。
## 在 add_child 之前调用也有效：那时 _ready 还没跑，先记下来，_build 里补挂。
func set_save_system(sv: SaveSystem) -> void:
	if _slots != null:
		_slots.set_save_system(sv)
	else:
		_pending_sv = sv
