extends Control
class_name SaveSlotsPanel
## 存档槽位列表 —— 主界面与游戏内暂停菜单共用
##
## 【为什么只发信号不自己读档】同一个面板在两个宿主里语义不同：
##   主界面点槽位 = 带着 pending_load_slot 切场景进游戏
##   暂停菜单点槽位 = 就地读档，回到刚才那个世界
## 面板不该知道宿主是谁，所以只报"玩家选了槽位 N"，动作交给宿主。
##
## 【为什么要能注入 SaveSystem】宿主通常已经有一个 setup 过的实例
## （主界面为了签名合法传的是背景世界，游戏内是真正的世界）。
## 再 new 一个是浪费，也可能和正在用的那份状态不一致。

signal slot_picked(slot: int)
signal back_requested()

const SaveS := preload("res://scripts/save_system.gd")

const C_TITLE := Color(0.98, 0.84, 0.60)
const C_SHADOW := Color(0.16, 0.09, 0.03, 0.85)
const C_TEXT := Color(0.92, 0.88, 0.78)
const C_TEXT_DIM := Color(0.90, 0.88, 0.82, 0.75)
const C_BTN := Color(0.14, 0.13, 0.12, 0.72)
const C_BTN_HOVER := Color(0.85, 0.62, 0.26, 0.88)
const C_BTN_PRESSED := Color(0.62, 0.42, 0.16, 0.92)
const C_DEL := Color(0.32, 0.12, 0.10, 0.72)
const C_DEL_HOVER := Color(0.90, 0.42, 0.34, 0.92)
const C_DEL_PRESSED := Color(0.62, 0.20, 0.16, 0.92)

## 布局基准（k = 1 时的像素值）
const BASE_SLOT := Vector2(430.0, 58.0)
const BASE_DEL := Vector2(96.0, 58.0)
const BASE_BACK := Vector2(240.0, 46.0)
const BASE_SLOT_FONT := 18
const BASE_DEL_FONT := 16
const BASE_BACK_FONT := 22
const BASE_TITLE_FONT := 34
const BASE_TIP_FONT := 15
const BASE_SEP := 12.0
const BASE_BOX_W := 560.0

var _sv: SaveSystem = null
var _own_sv: SaveSystem = null      ## 没注入时才自己造一个，退出时不用管（宿主会释放）
var _slot_btns: Array = []
var _del_btns: Array = []

var _center: CenterContainer
var _box: VBoxContainer
var _back_btn: Button
var _title: Label
var _tip: Label


## 【别再用 set_anchors_preset 做布局】它只改锚点、不动 offsets：
## 新建控件的 offsets 是 (0,0,-W,-H) 这类"保持原尺寸"的值，于是 size 还是 0，
## CenterContainer 自己就 0 大、"居中"等于原地；PRESET_CENTER 同理会贴到中心右下。
## 必须用 set_anchors_and_offsets_preset()，锚点与偏移一起设。
func _ready() -> void:
	name = "SaveSlotsPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_center = CenterContainer.new()
	_center.name = "Center"
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	_build()
	refresh()


## 宿主有就用宿主的，没有就自己造（只读展示类 API，不需要世界引用）
func set_save_system(sv: SaveSystem) -> void:
	_sv = sv
	refresh()


func set_header(title: String, tip: String) -> void:
	if _title != null:
		_title.text = title
	if _tip != null:
		_tip.text = tip


# ——————————————— 构建 ———————————————
func _build() -> void:
	_box = VBoxContainer.new()
	var box := _box
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(BASE_SEP))
	box.custom_minimum_size = Vector2(BASE_BOX_W, 0.0)
	_center.add_child(box)

	_title = Label.new()
	_title.text = "选择存档"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", BASE_TITLE_FONT)
	_title.add_theme_color_override("font_color", C_TITLE)
	_title.add_theme_color_override("font_shadow_color", C_SHADOW)
	_title.add_theme_constant_override("shadow_offset_y", 3)
	box.add_child(_title)

	_tip = Label.new()
	_tip.text = "当前版本存档：新游戏会覆盖所选槽位"
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.add_theme_font_size_override("font_size", BASE_TIP_FONT)
	_tip.add_theme_color_override("font_color", C_TEXT_DIM)
	box.add_child(_tip)

	for i in range(SaveS.SLOTS):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var b := Button.new()
		b.custom_minimum_size = BASE_SLOT
		b.add_theme_font_size_override("font_size", BASE_SLOT_FONT)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", C_TEXT)
		b.add_theme_color_override("font_hover_color", Color(0.14, 0.10, 0.05))
		b.add_theme_color_override("font_disabled_color", Color(0.72, 0.72, 0.72, 0.34))
		b.add_theme_stylebox_override("normal", _btn_style(C_BTN))
		b.add_theme_stylebox_override("hover", _btn_style(C_BTN_HOVER))
		b.add_theme_stylebox_override("pressed", _btn_style(C_BTN_PRESSED))
		b.add_theme_stylebox_override("disabled", _btn_style(Color(0.08, 0.08, 0.09, 0.28)))
		var idx := i
		b.pressed.connect(func(): slot_picked.emit(idx))
		row.add_child(b)
		_slot_btns.append(b)

		var del := Button.new()
		del.text = "删除"
		del.custom_minimum_size = BASE_DEL
		del.add_theme_font_size_override("font_size", BASE_DEL_FONT)
		del.add_theme_color_override("font_color", Color(1.0, 0.72, 0.66))
		del.add_theme_color_override("font_hover_color", Color(0.14, 0.10, 0.05))
		del.add_theme_color_override("font_disabled_color", Color(0.72, 0.72, 0.72, 0.30))
		del.add_theme_stylebox_override("normal", _btn_style(C_DEL))
		del.add_theme_stylebox_override("hover", _btn_style(C_DEL_HOVER))
		del.add_theme_stylebox_override("pressed", _btn_style(C_DEL_PRESSED))
		del.add_theme_stylebox_override("disabled", _btn_style(Color(0.08, 0.08, 0.09, 0.28)))
		del.pressed.connect(func(): _delete_slot(idx))
		row.add_child(del)
		_del_btns.append(del)

		box.add_child(row)

	_back_btn = Button.new()
	_back_btn.text = "返回"
	_back_btn.custom_minimum_size = BASE_BACK
	_back_btn.add_theme_font_size_override("font_size", BASE_BACK_FONT)
	_back_btn.add_theme_stylebox_override("normal", _btn_style(C_BTN))
	_back_btn.add_theme_stylebox_override("hover", _btn_style(C_BTN_HOVER))
	_back_btn.add_theme_stylebox_override("pressed", _btn_style(C_BTN_PRESSED))
	_back_btn.add_theme_color_override("font_color", C_TEXT)
	_back_btn.add_theme_color_override("font_hover_color", Color(0.14, 0.10, 0.05))
	_back_btn.pressed.connect(func(): back_requested.emit())
	box.add_child(_back_btn)


## 按分辨率缩放。宿主（主界面 / 暂停菜单）在显示前调用。
## 不缩放的话手机上 58px 高的槽位按钮只有屏高的 2.5%，点不准。
func set_ui_scale(k: float) -> void:
	if k <= 0.0:
		return
	if _box != null:
		_box.add_theme_constant_override("separation", int(BASE_SEP * k))
		_box.custom_minimum_size = Vector2(BASE_BOX_W * k, 0.0)
	if _title != null:
		_title.add_theme_font_size_override("font_size", maxi(18, int(BASE_TITLE_FONT * k)))
	if _tip != null:
		_tip.add_theme_font_size_override("font_size", maxi(11, int(BASE_TIP_FONT * k)))
	if _back_btn != null:
		_back_btn.custom_minimum_size = BASE_BACK * k
		_back_btn.add_theme_font_size_override("font_size", maxi(13, int(BASE_BACK_FONT * k)))
	for i in _slot_btns.size():
		var b: Button = _slot_btns[i]
		b.custom_minimum_size = BASE_SLOT * k
		b.add_theme_font_size_override("font_size", maxi(12, int(BASE_SLOT_FONT * k)))
		var d: Button = _del_btns[i]
		d.custom_minimum_size = BASE_DEL * k
		d.add_theme_font_size_override("font_size", maxi(11, int(BASE_DEL_FONT * k)))


func _btn_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.86, 0.68, 0.38, 0.55)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	return sb


# ——————————————— 数据 ———————————————
func _sys() -> SaveSystem:
	if _sv != null and is_instance_valid(_sv):
		return _sv
	if _own_sv == null:
		_own_sv = SaveS.new()
		_own_sv.name = "SlotsProbeSaveSystem"
		add_child(_own_sv)
	return _own_sv


func has_save(slot: int) -> bool:
	return _sys().has_save(slot)


func refresh() -> void:
	var sv := _sys()
	for i in _slot_btns.size():
		var b: Button = _slot_btns[i]
		var has := sv.has_save(i)
		b.text = sv.slot_text(i)
		b.disabled = not has
		var d: Button = _del_btns[i]
		d.disabled = not has


func _delete_slot(slot: int) -> void:
	_sys().delete_save(slot)
	refresh()
	if GameBus != null:
		GameBus.toast.emit("已删除槽位 %d" % (slot + 1))
