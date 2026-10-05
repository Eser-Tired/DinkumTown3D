extends CanvasLayer
class_name SleepPanel
const U := preload("res://scripts/ui_layout.gd")
## 睡觉面板 —— 选睡到几点起床
##
## 【为什么 layer = 35】要在背包(30)之上、暂停菜单(40)之下：
## 睡觉时再叠一个暂停菜单说不通，但面板必须盖住背包。
##
## 【为什么 process_mode = ALWAYS】面板靠 get_tree().paused 把时间停住
## （选起床时刻的这几秒不该让太阳继续走），而 paused 会让所有 INHERIT 节点的
## 输入一起停——包括面板自己，结果就是弹出来点不动、关不掉。
## 所以这一层必须声明 ALWAYS，并自己接 Esc：那时 main 收不到任何输入。
##
## 【为什么只给四个预设时刻，不做"睡到任意点"的滑块】触屏拖滑块又慢又难点准，
## 四个预设一次点中；而且睡觉本来就是"睡到早上/睡到中午"这种粗粒度选择。

signal picked(hour: float)
signal closed()

const C_TITLE := Color(1.0, 0.86, 0.62)
const C_SUB := Color(0.90, 0.88, 0.80)
const C_BTN := Color(0.14, 0.13, 0.12, 0.74)
const C_BTN_HOVER := Color(0.85, 0.62, 0.26, 0.90)
const C_BTN_PRESSED := Color(0.62, 0.42, 0.16, 0.94)

## 可选的起床时刻（小时）：清晨 / 上午 / 正午 / 傍晚
const WAKE_HOURS := [6.0, 8.0, 12.0, 18.0]

const BASE_BTN := Vector2(380.0, 58.0)
const BASE_BTN_FONT := 23
const BASE_TITLE_FONT := 44
const BASE_SUB_FONT := 17
const BASE_SEP := 12.0

## 宿主注入：返回当前游戏时刻（0..24 的小时数）
var _hour_fn: Callable = Callable()

var _title: Label
var _sub: Label
var _main_box: VBoxContainer
var _wake_btns: Array = []
var _all_btns: Array = []


func _ready() -> void:
	name = "SleepPanel"
	layer = 35
	# 关键：见文件头注释。少了这行面板会变成一张点不动的死图。
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	U.bind(self, _apply_scale)


func _build() -> void:
	# 全屏压暗 + 吃掉点击，防止穿透到下面的 HUD / 触控层
	var bg := ColorRect.new()
	bg.name = "Dim"
	bg.color = Color(0.03, 0.04, 0.07, 0.80)
	# 锚点和 offsets 必须一起设：只设锚点会留下 offset_right = -W，size 仍是 0
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 铺满 + 内套 CenterContainer，内容撑开后会重新居中
	# （PRESET_CENTER 会在内容添加前按 size=0 把 offsets 算死）
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	_main_box = VBoxContainer.new()
	_main_box.name = "MainBox"
	_main_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_box.add_theme_constant_override("separation", int(BASE_SEP))
	_main_box.custom_minimum_size = Vector2(BASE_BTN.x, 0.0)
	center.add_child(_main_box)

	_title = Label.new()
	_title.text = "睡觉"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", BASE_TITLE_FONT)
	_title.add_theme_color_override("font_color", C_TITLE)
	_main_box.add_child(_title)

	_sub = Label.new()
	_sub.text = "现在是 00:00"
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", BASE_SUB_FONT)
	_sub.add_theme_color_override("font_color", C_SUB)
	_main_box.add_child(_sub)

	# 回调统一走 meta 里的 hour，而不是闭包捕获固定值：
	# 列表要按"还要等多久"重排，按钮与时刻的对应关系每次 open 都可能变。
	# 【为什么用 bind 而不是 lambda】lambda 捕获局部变量是"创建那一刻的值"，
	# 而这里 b 要等 _add_button 返回才有值，写成 func(): _pick(b) 捕获到的是 null。
	for i in WAKE_HOURS.size():
		var b := _add_button("", Callable())
		b.pressed.connect(_on_wake_btn.bind(b))
		_wake_btns.append(b)

	_add_button("再想想", func(): close())


func _add_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _btn_style(C_BTN))
	b.add_theme_stylebox_override("hover", _btn_style(C_BTN_HOVER))
	b.add_theme_stylebox_override("pressed", _btn_style(C_BTN_PRESSED))
	b.add_theme_color_override("font_color", C_SUB)
	b.add_theme_color_override("font_hover_color", Color(0.14, 0.10, 0.05))
	if cb.is_valid():
		b.pressed.connect(cb)
	_main_box.add_child(b)
	_all_btns.append(b)
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


## 按分辨率重算尺寸：基准是 1440x810，放到手机上 58px 高的按钮点不准
func _apply_scale() -> void:
	var vs := get_viewport().get_visible_rect().size
	if vs.x < 8.0 or vs.y < 8.0:
		return
	var k := U.menu_scale(vs)
	_main_box.add_theme_constant_override("separation", int(BASE_SEP * k))
	_title.add_theme_font_size_override("font_size", U.text_size(BASE_TITLE_FONT, k, 20))
	_sub.add_theme_font_size_override("font_size", U.text_size(BASE_SUB_FONT, k, 11))
	for b in _all_btns:
		if not is_instance_valid(b):
			continue
		(b as Button).custom_minimum_size = BASE_BTN * k
		(b as Button).add_theme_font_size_override("font_size", U.text_size(BASE_BTN_FONT, k, 13))


## hour_fn 由宿主注入：返回当前时刻（小时）。每次 open 都重新注入，
## 因为面板是常驻实例，而"现在几点"每睡一次都会变。
func open(hour_fn: Callable) -> void:
	_hour_fn = hour_fn
	_apply_scale()
	_refresh()
	visible = true
	# 真暂停：选时刻的这几秒里太阳、天气、动物都别动
	get_tree().paused = true
	if GameBus != null:
		GameBus.ui_blocking = true


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	if GameBus != null:
		GameBus.ui_blocking = false
	closed.emit()


## Esc / 返回键由面板自己接（见文件头说明：暂停时 main 收不到输入）
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and event.pressed and not event.echo
				and event.keycode == KEY_ESCAPE):
		close()
		get_viewport().set_input_as_handled()


## 起床按钮的点击入口。按钮本身不记时刻，时刻由 _refresh 写进 meta——
## 列表顺序每次都可能变，按钮和时刻的对应关系不能写死。
func _on_wake_btn(b: Button) -> void:
	_pick(float(b.get_meta("hour", 6.0)))


func _pick(hour: float) -> void:
	# 先关（解除暂停）再发信号：宿主会在回调里播黑屏过场，
	# 而 Tween 默认跟随节点暂停状态，带着 paused 启动会一动不动。
	close()
	picked.emit(hour)


# ——————————————— 文案 ———————————————
func _refresh() -> void:
	var cur := 0.0
	if _hour_fn.is_valid():
		cur = float(_hour_fn.call())
	_sub.text = "现在是 %s　·　睡一觉会跳过这段时间" % _clock(cur)

	# 【必须按"还要等多久"重排】固定顺序 06/08/12/18 在上午打开会显示成
	# "明天 06:00 / 明天 08:00 / 12:00 / 18:00"——时间倒着排，
	# 玩家会以为时刻算错了（这是实测截图里一眼看出来的）。
	var items: Array = []
	for h in WAKE_HOURS:
		# 目标时刻已经过去（或就是现在）→ 那就是明天早上
		var next_day: bool = h <= cur + 0.02
		var dur: float = h + (24.0 if next_day else 0.0) - cur
		items.append({"h": h, "next": next_day, "dur": dur})
	items.sort_custom(func(a, b): return float(a["dur"]) < float(b["dur"]))

	for i in _wake_btns.size():
		var b: Button = _wake_btns[i]
		if i >= items.size():
			b.visible = false
			continue
		b.visible = true
		var it: Dictionary = items[i]
		b.set_meta("hour", float(it["h"]))
		b.text = "%s%s 起床　睡 %s" % [
			"明天 " if bool(it["next"]) else "",
			_clock(float(it["h"])), _dur_text(float(it["dur"]))]


func _clock(h: float) -> String:
	var hh := int(h) % 24
	var mm := int(roundf((h - floorf(h)) * 60.0))
	return "%02d:%02d" % [hh, mm]


func _dur_text(hours: float) -> String:
	var total := int(roundf(hours * 60.0))
	var h := total / 60
	var m := total % 60
	if h <= 0:
		return "%d 分钟" % m
	if m == 0:
		return "%d 小时" % h
	return "%d 小时 %d 分" % [h, m]
