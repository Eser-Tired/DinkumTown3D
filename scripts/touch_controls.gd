extends CanvasLayer
class_name TouchControls
## 移动端触控层 —— 左摇杆（位置可拖）/ 底部物品栏 / 右侧动作键 / 点击交互
##
## 【布局分区】
##   左下  虚拟摇杆 —— 移动，推满自动奔跑。**长按 0.35 秒可拖动重新定位**，
##         位置按屏幕比例持久化到 user://settings.cfg
##   底部  4 格快捷物品栏 + 背包按钮 + 建造按钮
##   右侧  跳跃键 + 使用键（攻击/工具，随当前手持物变化）+ 农事键
##   空白  单指拖拽转视角、双指捏合缩放、轻点（位移小于阈值的点按）触发交互
##
## 【为什么把「采集」并入点击】用户要求"人物靠近直接触屏点击采集"。
## 独立按钮会占掉右下最宝贵的大拇指热区，而且采集/攻击在操作语义上是同一件事
## （对最近的可交互目标出手）。所以合并成"点屏幕"一个手势，由 main 侧判断
## 打到的是资源还是动物。
##
## 【为什么不与拖拽转视角冲突】看 _on_touch/_on_drag 的距离阈值判定：
## 按下到抬起位移 < TAP_SLOP 才算"点击"，否则一律当作视角拖拽。
##
## 输出走 GameBus.touch_* 通道，player / main 当作额外输入源消费，
## 所以桌面端（不挂本节点）行为完全不变。
##
## 桌面验证：启动加 --touch-ui，会强制挂载并开启鼠标模拟触摸。

const REF := Vector2(1440.0, 810.0)   # 布局参考分辨率
const SETTINGS_PATH := "user://settings.cfg"

## 轻点判定阈值（像素，按 k 缩放）：按下到抬起的位移小于它算点击
const TAP_SLOP := 18.0
## 长按进入「拖动摇杆」所需的时长
const LONG_PRESS := 0.35

var _joy: JoyPad
var _joy_r := 92.0
var _joy_id := -1
var _active := {}              ## index -> Vector2，参与「视角 / 捏合」的手指
var _pinch_prev := 0.0

## 摇杆自定义位置（屏幕比例 0..1，左上为原点；-1 表示用默认贴边位置）
var _joy_pos_ratio := Vector2(-1.0, -1.0)
var _dragging_joy := false
var _joy_press_t := 0.0
var _joy_press_at := Vector2.ZERO

## 轻点检测：记录按下位置
var _tap_id := -1
var _tap_from := Vector2.ZERO

var _btn_rects: Array = []
var _hold_btns: Array = []      ## 按住型按钮，release_all 时要复位
var _k := 1.0
var _vs := REF

## HUD 右侧竖列（时钟/季节/武器）的底边，随文字缩放 k_text 变化。
## 【为什么要让 HUD 直接报数】这列的高度 = Σ(面板高) + 间距，而面板高同时受
## 字号（kt）和实测文字宽度影响——在触控层里重算一遍必然对不上，
## 改一次 HUD 就得同步改一次这里，早晚会撞。所以改成 hud 回调告知实际底边，
## 触控层只负责"从它下面开始排"。拿不到时退回一个保守值。
var _hud_col_bottom := 0.0
var _k_text_geo := 1.0

## 快捷物品栏格子状态（由 main 通过 set_hotbar() 同步）
var _hotbar: Array = []
var _hotbar_sel := 0
var _hotbar_btns: Array = []


func _ready() -> void:
	layer = 20
	name = "TouchControls"
	GameBus.touch_enabled = true
	_load_settings()

	_joy = JoyPad.new()
	_joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_joy)

	get_viewport().size_changed.connect(_rebuild)
	GameBus.hotbar_changed.connect(_on_hotbar_changed)
	_rebuild()


func _exit_tree() -> void:
	GameBus.touch_enabled = false
	GameBus.touch_move = Vector2.ZERO
	GameBus.touch_look = Vector2.ZERO
	GameBus.touch_zoom = 0.0
	GameBus.touch_run = false


# ——————————————— 设置持久化 ———————————————
func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	_joy_pos_ratio = Vector2(
		float(cf.get_value("touch", "joy_x", -1.0)),
		float(cf.get_value("touch", "joy_y", -1.0))
	)


func _save_joy_pos() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)              # 保留主界面写入的音量/画质等
	cf.set_value("touch", "joy_x", _joy_pos_ratio.x)
	cf.set_value("touch", "joy_y", _joy_pos_ratio.y)
	cf.save(SETTINGS_PATH)


## 供设置界面调用：恢复默认贴边位置
func reset_joy_position() -> void:
	_joy_pos_ratio = Vector2(-1.0, -1.0)
	_save_joy_pos()
	_rebuild()


## 由 main 告知 HUD 实际使用的"文字缩放"（可能大于 k），系统小钮据此让位。
## 必须在首次 _rebuild 之前调用，否则第一次布局会按默认值算、瞬间压住 HUD。
func set_text_scale(k_text: float) -> void:
	if is_equal_approx(k_text, _k_text_geo):
		return
	_k_text_geo = k_text
	_rebuild()


## 由 main 在 hud.set_touch_mode() 之后告知右侧竖列的真实底边（像素）。
## 系统小钮从这条线下面 30 像素起排——用实测值而不是常量，HUD 改高度这边自动跟上。
func set_hud_column_bottom(y: float) -> void:
	if is_equal_approx(y, _hud_col_bottom):
		return
	_hud_col_bottom = y
	_rebuild()


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
	_hotbar_btns.clear()
	_hold_btns.clear()
	for c in get_children():
		if c != _joy:
			c.queue_free()

	# —— 虚拟摇杆：默认锚左下；有自定义比例则按比例定位 ——
	_joy_r = 92.0 * k
	_joy.size = Vector2(_joy_r * 2.6, _joy_r * 2.6)
	if _joy_pos_ratio.x >= 0.0 and _joy_pos_ratio.y >= 0.0:
		# 自定义位置存的是「摇杆中心」的屏幕比例，转成左上角坐标
		var ctr := Vector2(_joy_pos_ratio.x * W, _joy_pos_ratio.y * H)
		_joy.position = ctr - _joy.size * 0.5
	else:
		_joy.position = Vector2(46.0 * k, H - _joy_r * 2.6 - 40.0 * k)
	_joy.set_center_radius(_joy_r)
	_joy.queue_redraw()

	# —— 左侧竖排小钮：菜单 / 背包 / 建造 ——
	# 必须整块避开摇杆命中圆（_joy_r*1.2），否则测试和手感上都会被摇杆吃掉。
	# 摇杆默认中心 y ≈ H - joy_r*1.3 - 40k，命中半径 joy_r*1.2，
	# 所以小钮的底部要落到「摇杆中心 - 摇杆命中半径」以上。
	# 「菜单」放在最上面：它是导航键，和下面的面板类按钮同类但更靠外，
	# 拇指从边缘滑进来第一个碰到它，不会误开背包。
	var sw := 84.0 * k
	var sx := 58.0 * k
	var jc_y := H - _joy_r * 1.3 - 40.0 * k        # 摇杆中心（默认贴边时）
	var col_bottom := jc_y - _joy_r * 1.2 - 14.0 * k
	_btn_at("菜单", "pause", sx, col_bottom - 156.0 * k, sw, 62.0 * k, 18)
	_btn_at("背包", "bag", sx, col_bottom - 78.0 * k, sw, 62.0 * k, 18)
	_btn_at("建造", "build", sx, col_bottom, sw, 62.0 * k, 18)

	# —— 底部快捷物品栏：4 格 + 居中 ——
	var cell := 88.0 * k
	var gap := 8.0 * k
	var total_w := 4.0 * cell + 3.0 * gap
	var hx := (W - total_w) * 0.5
	var hy := H - 106.0 * k
	for i in 4:
		_make_hotbar_cell(i, hx + i * (cell + gap), hy, cell, cell)
	_refresh_hotbar()

	# —— 右上：系统小钮 ——
	# 【为什么不用常量】HUD 右侧竖列的高度受字号和实测文字宽度双重影响，
	# 在那边算死了这边重算必然对不上。改为读 hud 报来的真实底边，
	# 拿不到时退回 248k（桌面/未挂 HUD 的测试场景）。
	var sys_y1 := maxf(248.0 * k, _hud_col_bottom + 30.0)
	var sys_y2 := sys_y1 + 58.0 * k
	var SYS_ROW1 := sys_y1 / k
	var SYS_ROW2 := sys_y2 / k
	_make_sys_button("存", "save", W - 200.0 * k, SYS_ROW1 * k, 84.0 * k, 52.0 * k)
	_make_sys_button("读", "load", W - 108.0 * k, SYS_ROW1 * k, 84.0 * k, 52.0 * k)
	_make_sys_button("加速", "time", W - 200.0 * k, SYS_ROW2 * k, 84.0 * k, 52.0 * k)
	_make_sys_button("静音", "mute", W - 108.0 * k, SYS_ROW2 * k, 84.0 * k, 52.0 * k)

	# —— 右侧动作区：跳 / 使用 / 农事 ——
	# 「使用」是最大最靠拇指的主键；跳在它上方；农事在它左侧。
	_btn_at("使用", "use", W - 128.0 * k, H - 168.0 * k, 140.0 * k, 140.0 * k, 24)
	_btn_at("跳", "jump", W - 264.0 * k, H - 246.0 * k, 108.0 * k, 108.0 * k, 21)
	_btn_at("农事", "farm", W - 300.0 * k, H - 112.0 * k, 104.0 * k, 104.0 * k, 19)
	# 下潜键：按【住】才往下，所以不能用 pressed（那是抬手才触发的一次性信号）。
	# 放在「跳」正上方——两个都是垂直方向的键，位置一致好形成肌肉记忆；
	# 陆地上它不起作用，没必要藏起来。
	_make_hold_button("潜", "dive", W - 264.0 * k, H - 372.0 * k, 108.0 * k, 74.0 * k, 20)
	# 建造模式专用：旋转 / 放置。放在系统钮下方，与 HUD 竖列彻底分离。
	var rot_y := sys_y2 + 82.0 * k
	_btn_at("旋转", "rotate", W - 128.0 * k, rot_y, 118.0 * k, 58.0 * k, 19)
	_btn_at("放置", "place", W - 128.0 * k, rot_y + 66.0 * k, 118.0 * k, 58.0 * k, 19)

	GameBus.touch_layout_changed.emit(W, H, k)


## 中心点 + 尺寸创建按钮（区别于 Godot 的左上角定位）
func _btn_at(text: String, action: String, cx: float, cy: float, w: float, h: float, fs: int) -> Button:
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
	return b


## 系统小钮样式（更暗，与动作键区分层级）
func _make_sys_button(text: String, action: String, cx: float, cy: float, w: float, h: float) -> Button:
	var b := _btn_at(text, action, cx, cy, w, h, 17)
	_style(b, Color(0.08, 0.10, 0.14, 0.46), Color(0.14, 0.20, 0.28, 0.72))
	return b


## 「按住」型按钮：按下即生效、松手即结束（下潜用）。
## 【为什么不能复用 _btn_at】那是靠 pressed 信号的一次性动作，
## 而 Button.pressed 是【抬手】时才发的——用按下潜会变成"松手才潜一下"，
## 而且没法持续下潜。这里改用 button_down / button_up 维护一个状态位。
func _make_hold_button(text: String, action: String, cx: float, cy: float,
		w: float, h: float, fs: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", maxi(10, int(fs * _k)))
	var sz := Vector2(w, h)
	b.size = sz
	b.position = Vector2(cx - sz.x * 0.5, cy - sz.y * 0.5)
	b.focus_mode = Control.FOCUS_NONE
	_style(b, Color(0.12, 0.20, 0.30, 0.54), Color(0.24, 0.44, 0.60, 0.86))
	var act := action
	b.button_down.connect(func(): _set_hold(act, true))
	b.button_up.connect(func(): _set_hold(act, false))
	# 手指按住后滑出按钮范围也会收到 button_up，但为保险再挂一个
	b.mouse_exited.connect(func():
		if not b.button_pressed:
			_set_hold(act, false))
	add_child(b)
	_btn_rects.append(Rect2(b.position, sz))
	_hold_btns.append(b)
	return b


func _set_hold(action: String, on: bool) -> void:
	if action == "dive":
		GameBus.touch_dive = on


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


# ——————————————— 快捷物品栏 ———————————————
## main 侧通过 GameBus.sync_hotbar(slots, sel) 同步：
##   slots = [{kind:"weapon"/"empty", id:"axe", name:"斧头", label:"斧"}, ...]
##   sel   = 当前选中格下标
func _on_hotbar_changed(slots: Array, sel: int) -> void:
	_hotbar = slots
	_hotbar_sel = sel
	_refresh_hotbar()


func _make_hotbar_cell(i: int, x: float, y: float, w: float, h: float) -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(w, h)
	b.position = Vector2(x, y)
	b.add_theme_font_size_override("font_size", maxi(10, int(16 * _k)))
	var idx := i
	b.pressed.connect(func(): GameBus.request_touch_action("hot%d" % (idx + 1)))
	add_child(b)
	_hotbar_btns.append(b)
	_btn_rects.append(Rect2(b.position, b.size))


func _refresh_hotbar() -> void:
	for i in _hotbar_btns.size():
		var b: Button = _hotbar_btns[i]
		var sel := (i == _hotbar_sel)
		var slot: Dictionary = _hotbar[i] if i < _hotbar.size() else {}

		if slot.is_empty() or str(slot.get("kind", "empty")) == "empty":
			b.text = "%d\n—" % (i + 1)
			_style(b, Color(0.08, 0.10, 0.14, 0.34), Color(0.12, 0.16, 0.22, 0.5))
		else:
			b.text = "%d\n%s" % [i + 1, str(slot.get("label", slot.get("name", "?")))]
			if sel:
				_style(b, Color(0.62, 0.44, 0.16, 0.86), Color(0.78, 0.58, 0.24, 0.95))
			else:
				_style(b, Color(0.10, 0.14, 0.20, 0.58), Color(0.18, 0.27, 0.38, 0.82))


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
	# 模态 UI（背包）打开时整层停止响应。
	# 【为什么必须显式判断】_input 在 GUI 处理【之前】触发，所以背包的全屏遮罩
	# 挡不住这里——不判断的话，点背包里的武器按钮会同时推摇杆、抬手还发出
	# touch_tap，导致关背包的同一帧又去采集/攻击一次。
	if GameBus.ui_blocking:
		return
	if event is InputEventScreenTouch:
		_on_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position, event.relative)


## 外部（背包等）接管输入时调用：清掉所有在途手指状态，
## 否则会出现"按下时没被屏蔽、抬起时被屏蔽"导致摇杆卡住推到底的残留。
func release_all() -> void:
	_joy_id = -1
	_dragging_joy = false
	_joy_press_t = 0.0
	_tap_id = -1
	_active.clear()
	_pinch_prev = 0.0
	_joy.set_knob(Vector2.ZERO)
	_joy.set_drag_hint(false)
	GameBus.touch_move = Vector2.ZERO
	GameBus.touch_look = Vector2.ZERO
	GameBus.touch_zoom = 0.0
	GameBus.touch_run = false
	# 「潜」是按住型状态位：不清的话关掉菜单后玩家会一直往下沉
	GameBus.touch_dive = false
	for hb in _hold_btns:
		if is_instance_valid(hb):
			(hb as Button).button_pressed = false


func _on_touch(idx: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if _in_button(pos):
			return
		# 摇杆命中圆（略大于视觉半径，手感友好）；按钮已在前面判定过，优先级更高
		if pos.distance_to(_joy_center()) < _joy_r * 1.2:
			_joy_id = idx
			_joy_press_t = 0.0
			_joy_press_at = pos
			_dragging_joy = false
			# 按住不动算"长按"→ 进入拖动定位；一动就算推摇杆，看 _on_drag
			_update_joy(pos)
			return
		# 其余按下：先记下落点，抬起时再判定是「轻点」还是「拖视角」
		_active[idx] = pos
		if _tap_id < 0:
			_tap_id = idx
			_tap_from = pos
		if _active.size() >= 2:
			_pinch_prev = _pair_distance()
		return

	# —— 抬起 ——
	if idx == _joy_id:
		_joy_id = -1
		_joy_press_t = 0.0
		_joy.set_knob(Vector2.ZERO)
		GameBus.touch_move = Vector2.ZERO
		GameBus.touch_run = false
		# 松手落位：拖动定位模式下把新位置持久化，否则退出拖动模式还原到原中心
		if _dragging_joy:
			_commit_joy_pos()
		_dragging_joy = false
		_joy.set_drag_hint(false)
		return

	if _active.has(idx):
		_active.erase(idx)
		if _active.size() < 2:
			_pinch_prev = 0.0

	# 轻点判定：主触点、总位移小于阈值、没有发生双指操作
	if idx == _tap_id:
		_tap_id = -1
		if _active.is_empty() and pos.distance_to(_tap_from) < TAP_SLOP * _k:
			GameBus.touch_tap.emit(pos)


func _on_drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if idx == _joy_id:
		_joy_press_t += 0.0     # 时间在 _process 里累加
		# 长按后进入拖动定位：摇杆中心跟随手指
		if _dragging_joy:
			_move_joy_to(pos)
			return
		# 未进入长按前：正常推摇杆
		if _joy_press_at.distance_to(pos) > 24.0 * _k:
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

	# 建造模式：单指拖动改为挪动建造预览，而不是转视角
	# （为什么这样分：建造时玩家最想微调的是落点，转视角的诉求可以靠点空白慢慢转）
	if GameBus.build_mode:
		GameBus.touch_build_drag.emit(rel)
		return

	GameBus.touch_look += rel


func _process(dt: float) -> void:
	# 摇杆长按计时：按住不动超过 LONG_PRESS 就切换到「拖动定位」模式
	if _joy_id >= 0 and not _dragging_joy:
		_joy_press_t += dt
		if _joy_press_t >= LONG_PRESS:
			_dragging_joy = true
			_joy.set_drag_hint(true)
	if _joy_id < 0 and _joy.is_drag_hint():
		_joy.set_drag_hint(false)


## 拖动定位：把摇杆中心挪到手指位置，并夹在屏幕内侧（避免半个摇杆跑出屏外）
func _move_joy_to(pos: Vector2) -> void:
	var margin := _joy_r * 1.1
	var c := Vector2(
		clampf(pos.x, margin, _vs.x - margin),
		clampf(pos.y, margin, _vs.y - margin)
	)
	_joy.position = c - _joy.size * 0.5
	_joy.queue_redraw()


## 松手落位：把当前中心换算成屏幕比例并持久化
func _commit_joy_pos() -> void:
	if _vs.x < 8.0 or _vs.y < 8.0:
		return
	var c := _joy_center()
	_joy_pos_ratio = Vector2(c.x / _vs.x, c.y / _vs.y)
	_save_joy_pos()


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
	var _drag_hint := false

	func set_center_radius(r: float) -> void:
		_r = r
		queue_redraw()

	func set_knob(k: Vector2) -> void:
		_knob = k
		queue_redraw()

	func set_drag_hint(on: bool) -> void:
		_drag_hint = on
		queue_redraw()

	func is_drag_hint() -> bool:
		return _drag_hint

	func _draw() -> void:
		var c := size * 0.5
		# 进入拖动定位模式时整体变亮 + 加一圈虚线感，提示"可以挪了"
		var base_a := 0.13
		var ring_a := 0.26
		if _drag_hint:
			base_a = 0.24
			ring_a = 0.62
		draw_circle(c, _r, Color(0.85, 0.92, 1.0, base_a))
		draw_circle(c, _r, Color(0.98, 0.84, 0.52, ring_a), false, 3.0, true)
		draw_circle(c, _r * 0.42, Color(0.85, 0.92, 1.0, base_a * 0.5))
		draw_circle(c + _knob, _r * 0.40, Color(1.0, 1.0, 1.0, 0.34))
		draw_circle(c + _knob, _r * 0.40, Color(1.0, 1.0, 1.0, 0.55), false, 3.0, true)
