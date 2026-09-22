extends CanvasLayer
class_name TouchControls
## 移动端触控层
##
## 组成：
##   1. 左下虚拟摇杆 —— 移动；推到边缘自动奔跑
##   2. 空白处单指拖拽 —— 转视角 / 俯仰（对应桌面右键拖拽）
##   3. 双指捏合 —— 拉近拉远（对应桌面滚轮）
##   4. 右侧 / 中下的功能按钮 —— 与桌面键盘动作一一对应
##
## 输出走 GameBus.touch_* 通道，player / main 把它当作「额外输入源」消费，
## 所以桌面端（不挂本节点）行为完全不变。
##
## 桌面验证：启动时加 --touch-ui，会强制挂载并开启鼠标模拟触摸。

const REF := Vector2(1440.0, 810.0)   # 布局参考分辨率（= 桌面视口）

const BTN_SYS := [
	{"t": "存", "a": "save"},
	{"t": "读", "a": "load"},
	{"t": "作物", "a": "crop"},
	{"t": "加速", "a": "time"},
	{"t": "静音", "a": "mute"},
	{"t": "帮助", "a": "help"},
]

const BTN_PICK := [
	{"t": "篝火", "a": "pick1"},
	{"t": "帐篷", "a": "pick2"},
	{"t": "栅栏", "a": "pick3"},
	{"t": "路灯", "a": "pick4"},
]

var _joy: JoyPad
var _joy_r := 92.0
var _joy_id := -1
var _active := {}          ## index -> Vector2，参与「视角 / 捏合」的手指
var _pinch_prev := 0.0

var _btn_rects: Array = []
var _k := 1.0
var _vs := REF


func _ready() -> void:
	layer = 20
	name = "TouchControls"
	GameBus.touch_enabled = true
	_joy = JoyPad.new()
	_joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_joy)
	get_viewport().size_changed.connect(_rebuild)
	_rebuild()


func _exit_tree() -> void:
	GameBus.touch_enabled = false
	GameBus.touch_move = Vector2.ZERO
	GameBus.touch_look = Vector2.ZERO
	GameBus.touch_zoom = 0.0
	GameBus.touch_run = false


# ——————————————— 布局（锚点式） ———————————————
## 规则：尺寸与偏移一律按 k 缩放；位置由「贴哪条边」决定。
## 这样无论宽高比怎么变，元素只会随边缘移动，不会互相漂移。
func _rebuild() -> void:
	_vs = get_viewport().get_visible_rect().size
	if _vs.x < 8.0 or _vs.y < 8.0:
		return
	_k = clampf(minf(_vs.x / REF.x, _vs.y / REF.y), 0.60, 2.2)
	var W := _vs.x
	var H := _vs.y
	var k := _k

	_btn_rects.clear()
	for c in get_children():
		if c != _joy:
			c.queue_free()

	# —— 虚拟摇杆：锚左下 ——
	_joy_r = 92.0 * k
	_joy.size = Vector2(_joy_r * 2.6, _joy_r * 2.6)
	_joy.position = Vector2(46.0 * k, H - _joy_r * 2.6 - 40.0 * k)
	_joy.set_center_radius(_joy_r)
	_joy.queue_redraw()

	# —— 顶部系统小钮：锚左上，起点让过资源面板（面板固定像素宽 268，小屏 k 缩不放它）——
	# 资源面板是 HUD 的固定像素宽(34+230)；这里约束的是按钮「左边界」而非中心
	var sys_w := 76.0 * k
	var sys_x0 := maxf(306.0 * k, 286.0) + sys_w * 0.5
	var i := 0
	for d in BTN_SYS:
		_btn_at(d.t, d.a, sys_x0 + i * 90.0 * k, 46.0 * k, sys_w, 56.0 * k, 19)
		i += 1

	# —— 建筑选择 1-4：锚中下 ——
	var bw := 140.0 * k
	var gap := 12.0 * k
	var bx := (W - (4.0 * bw + 3.0 * gap)) * 0.5
	i = 0
	for d in BTN_PICK:
		_btn_at(d.t, d.a, bx + (i + 0.5) * bw + i * gap, H - 87.0 * k, bw, 54.0 * k, 19)
		i += 1

	# —— 右侧建造控制列：锚右 ——
	var colw := 148.0 * k
	var colx := W - 74.0 * k - colw * 0.5
	_btn_at("放置", "place", colx, 196.0 * k, colw, 64.0 * k, 21)
	_btn_at("建造", "build", colx, 266.0 * k, colw, 64.0 * k, 21)
	_btn_at("旋转", "rotate", colx, 336.0 * k, colw, 64.0 * k, 21)

	# —— 右下主动作圆钮：锚右下 ——
	_btn_at("采集", "harvest", W - 130.0 * k, H - 150.0 * k, 132.0 * k, 132.0 * k, 23)
	_btn_at("农事", "farm", W - 300.0 * k, H - 110.0 * k, 116.0 * k, 116.0 * k, 21)
	_btn_at("跳", "jump", W - 90.0 * k, H - 330.0 * k, 104.0 * k, 104.0 * k, 21)

	GameBus.touch_layout_changed.emit(W, H, k)


## 中心点 + 尺寸创建按钮（区别于 Godot 的左上角定位）
func _btn_at(text: String, action: String, cx: float, cy: float, w: float, h: float, fs: int) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", maxi(10, int(fs * _k)))
	var sz := Vector2(w, h)
	b.size = sz
	b.position = Vector2(cx - sz.x * 0.5, cy - sz.y * 0.5)
	b.focus_mode = Control.FOCUS_NONE
	_style(b, Color(0.10, 0.14, 0.20, 0.52), Color(0.18, 0.27, 0.38, 0.80))
	var act := action
	b.pressed.connect(func(): GameBus.request_touch_action(act))
	add_child(b)
	_btn_rects.append(Rect2(b.position, sz))


func _style(b: Button, normal: Color, pressed: Color) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = normal
	n.set_corner_radius_all(int(16 * _k))
	n.border_color = Color(1, 1, 1, 0.22)
	n.set_border_width_all(maxi(1, int(2 * _k)))
	var p := StyleBoxFlat.new()
	p.bg_color = pressed
	p.set_corner_radius_all(int(16 * _k))
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", n)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1.0))


# ——————————————— 输入 ———————————————
func _joy_center() -> Vector2:
	return _joy.position + _joy.size * 0.5


func _in_button(p: Vector2) -> bool:
	for r in _btn_rects:
		var rr: Rect2 = r
		if rr.has_point(p):
			return true
	return false


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position, event.relative)


func _on_touch(idx: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if _in_button(pos):
			return
		# 摇杆命中圆形区域（略大于视觉半径，手感友好）；按钮已在前面判定过，优先级更高
		if pos.distance_to(_joy_center()) < _joy_r * 1.2:
			_joy_id = idx
			_update_joy(pos)
			return
		_active[idx] = pos
		if _active.size() >= 2:
			_pinch_prev = _pair_distance()
		return

	# 抬起
	if idx == _joy_id:
		_joy_id = -1
		_joy.set_knob(Vector2.ZERO)
		GameBus.touch_move = Vector2.ZERO
		GameBus.touch_run = false
		return
	if _active.has(idx):
		_active.erase(idx)
		if _active.size() < 2:
			_pinch_prev = 0.0


func _on_drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if idx == _joy_id:
		_update_joy(pos)
		return
	if not _active.has(idx):
		return
	_active[idx] = pos

	if _active.size() >= 2:
		# 双指捏合：距离变大 = 拉近（cam_dist 变小）
		var d := _pair_distance()
		if _pinch_prev > 0.0:
			GameBus.touch_zoom += (_pinch_prev - d) * 0.035
		_pinch_prev = d
		return

	GameBus.touch_look += rel


## 参与捏合的两指间距；不足两指时返回 0
func _pair_distance() -> float:
	if _active.size() < 2:
		return 0.0
	var pts: Array = _active.values()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	return a.distance_to(b)


func _update_joy(pos: Vector2) -> void:
	var d := pos - _joy_center()
	if d.length() > _joy_r:
		d = d.normalized() * _joy_r
	_joy.set_knob(d)
	var v := d / _joy_r
	GameBus.touch_move = v
	GameBus.touch_run = v.length() > 0.82


# ——————————————— 摇杆绘制 ———————————————
class JoyPad extends Control:
	var _knob := Vector2.ZERO
	var _r := 92.0

	func set_center_radius(r: float) -> void:
		_r = r
		queue_redraw()

	func set_knob(k: Vector2) -> void:
		_knob = k
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, _r, Color(0.85, 0.92, 1.0, 0.13))
		draw_circle(c, _r, Color(0.85, 0.92, 1.0, 0.26), false, 3.0, true)
		draw_circle(c, _r * 0.42, Color(0.85, 0.92, 1.0, 0.06))
		draw_circle(c + _knob, _r * 0.40, Color(1.0, 1.0, 1.0, 0.34))
		draw_circle(c + _knob, _r * 0.40, Color(1.0, 1.0, 1.0, 0.55), false, 3.0, true)
