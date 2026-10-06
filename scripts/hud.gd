extends CanvasLayer
class_name GameHUD
const U := preload("res://scripts/ui_layout.gd")
## 界面：资源 / 时钟 / 交互提示 / 建造菜单 / 帮助

var res_label: Label
var clock_label: Label
var season_label: Label
var prompt_label: Label
var build_label: Label
var help_label: Label
var help_panel: Panel
var toast_label: Label
var weapon_label: Label
var toast_t := 0.0
var _touch_mode := false
var _layout_args := Vector4.ZERO
var _last_bottom := -1.0
signal layout_changed(bottom: float)

## —— 水域 ——
## 水下遮罩：相机没入水面时压一层青绿，不用 Environment 雾是因为雾会影响
## 整个场景的着色，而出水的那一帧要立刻恢复，遮罩的开关是瞬时的、可控的。
var uw_overlay: ColorRect
## 憋气条（只在憋气时显示）
var breath_panel: Panel
## 【为什么填充用 ColorRect 而不是 Panel】Panel 的颜色只能靠 modulate 乘，
## 而默认主题的 Panel StyleBox 本身就是深灰——乘 1.0 还是深灰，填充根本看不出来。
## ColorRect 的 color 是直接赋值，白色就是白色。
var breath_fill: ColorRect
var _breath_shown := false
## 憋气条满格宽度。缩放后要用它算填充比例——不能拿面板宽度减边距，
## 面板和填充的边距也随 k 缩放，两边各算一次必然对不上。
var _breath_full_w := 312.0

## 右侧竖列（时钟 / 季节 / 武器）的面板引用，触控模式下要整体上移避让
var _right_panels: Array = []
## 资源面板引用（触控模式下按 k 重排）
var res_panel: Panel

## 供自检脚本取触控布局占位矩形用（返回面板层，不含内部标签）
func touch_reserved_rects() -> Array:
	var out: Array = []
	if res_panel != null:
		out.append(Rect2(res_panel.position, res_panel.size))
	for p in _right_panels:
		if p != null:
			out.append(Rect2(p.position, p.size))
	# 隐藏的面板不算占位：建造菜单在触控模式的非建造态是空文本，
	# 把它的矩形算进去会误报压住了左上的「菜单」按钮。
	if prompt_label != null and prompt_label.visible:
		out.append(Rect2(prompt_label.position, prompt_label.size))
	if build_label != null and build_label.visible:
		out.append(Rect2(build_label.position, build_label.size))
	if breath_panel != null and breath_panel.visible:
		out.append(Rect2(breath_panel.position, breath_panel.size))
	return out

const RES_NAME := {
	"wood": "木材", "stone": "石头", "fiber": "纤维", "ore": "铁矿石", "food": "食物"
}

## 触控左侧竖排按钮（菜单/背包/建造）右边缘之后再留一点间隙，k 为基准。
## 【跨文件约定】对应 touch_controls.gd 里的 sx = 58k、sw = 84k。
## 改那边的位置或宽度必须同步改这里，否则 HUD 的建造菜单会压住按钮
## （tools/touch_layout_check.gd 有断言兜底）。
const TOUCH_LEFT_COL_RIGHT := 154.0


func _ready() -> void:
	layer = 10
	_build()
	# 水下遮罩默认关闭；它铺满全屏，所以必须绝对不接鼠标事件
	uw_overlay = ColorRect.new()
	uw_overlay.name = "Underwater"
	uw_overlay.color = Color(0.10, 0.34, 0.42, 0.42)
	uw_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	uw_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	uw_overlay.visible = false
	add_child(uw_overlay)
	U.bind(self, _resize)


func _resize() -> void:
	if _touch_mode:
		return # 触控层会提供自己的几何尺寸和真实占位。
	var vs := get_viewport().get_visible_rect().size
	if vs.x < 8 or vs.y < 8:
		return
	var k := clampf(minf(vs.x / 1440.0, vs.y / 810.0), 0.5, 3.2)
	_arrange(vs.x, vs.y, k, U.text_scale(vs), false)


## 相机是否在水面以下 —— 只负责开关那一层青绿遮罩
func set_underwater(on: bool) -> void:
	if uw_overlay != null:
		uw_overlay.visible = on


## 憋气条。v < 0 表示不憋气（隐藏）；0..1 是剩余量。
func set_breath(v: float) -> void:
	var show := v >= 0.0
	if breath_panel == null or breath_fill == null:
		return
	if breath_panel.visible != show:
		breath_panel.visible = show
		breath_fill.visible = show
		_breath_shown = show
		_refresh_layout()
	if not show:
		return
	breath_fill.size = Vector2(maxf(0.0, _breath_full_w * clampf(v, 0.0, 1.0)),
		breath_fill.size.y)
	# 快没气时转红，给一个不用读数字的警告
	breath_fill.color = Color(0.96, 0.97, 1.0) if v > 0.28 else Color(1.0, 0.42, 0.34)


func _panel(pos: Vector2, size: Vector2, alpha := 0.55) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.modulate = Color(0.05, 0.07, 0.09, alpha)
	return p


func _label(size: int, pos: Vector2, width: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(width, 40)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _build() -> void:
	# 资源栏（5 行：木材/石头/纤维/铁矿石/食物）
	# 高度要够 5 行：行高约 = 字号 * 1.35，再留上下各 10 的内边距。
	res_panel = _panel(Vector2(18, 16), Vector2(250, 108))
	add_child(res_panel)
	res_label = _label(19, Vector2(34, 26), 230)
	res_label.size = Vector2(230, 96)
	res_label.text = "资源"
	add_child(res_label)

	# 时钟
	var p_clock := _panel(Vector2(1150, 16), Vector2(226, 62))
	add_child(p_clock)
	clock_label = _label(20, Vector2(1166, 28), 210)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(clock_label)

	# 季节 / 天气
	var p_season := _panel(Vector2(1150, 84), Vector2(226, 40), 0.42)
	add_child(p_season)
	season_label = _label(17, Vector2(1166, 90), 210)
	season_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	season_label.text = "—"
	add_child(season_label)

	# 当前武器（与时钟面板对齐成一列）
	var p_weapon := _panel(Vector2(1150, 128), Vector2(226, 40), 0.42)
	add_child(p_weapon)
	weapon_label = _label(17, Vector2(1166, 134), 210)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.text = "—"
	add_child(weapon_label)

	_right_panels = [p_clock, p_season, p_weapon]

	# 憋气条：沉在水下时才出现，放在屏幕正上方偏中，不挡视野也不跟资源栏打架
	breath_panel = _panel(Vector2(560, 26), Vector2(320, 22), 0.62)
	breath_panel.visible = false
	add_child(breath_panel)
	breath_fill = ColorRect.new()
	breath_fill.color = Color(0.96, 0.97, 1.0)
	breath_fill.position = Vector2(564, 30)
	breath_fill.size = Vector2(312, 14)
	breath_fill.visible = false
	add_child(breath_fill)
	_breath_full_w = 312.0

	# 交互提示（屏幕中下）
	# 【必须显式隐藏】Label 默认 visible=true，而这两行在开局是空文本。
	# 空文本框照样会被 touch_reserved_rects() 当成保留区算进去，
	# 于是触控层的「农事」按钮被判定"压住了 HUD"——竖屏下必报 bad=1。
	# 后续的显隐由 set_prompt / set_build 按文本是否为空接管。
	prompt_label = _label(22, Vector2(390, 690), 660)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.visible = false
	add_child(prompt_label)

	# 建造菜单
	build_label = _label(18, Vector2(1050, 300), 320)
	build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	build_label.visible = false
	add_child(build_label)

	# 帮助
	help_panel = _panel(Vector2(18, 640), Vector2(560, 150), 0.45)
	add_child(help_panel)
	help_label = _label(16, Vector2(34, 650), 540)
	help_label.size = Vector2(540, 140)
	help_label.text = "WASD/方向键 移动 · Shift 奔跑 · 空格 跳跃\n鼠标右键拖拽 转视角 · 滚轮 缩放\nE 采集 · 左键 攻击 · Q 换武器 · 1-4 切物品栏\nB 建造模式 · 建造中 1-4 选建筑 · 左键放置\n进水里自动游泳 · Ctrl 下潜、松开上浮（憋气有限）\nI 背包 · F 交互（进屋 / 床边睡觉 / 农事）· G 换作物 · T 加速时间 · H 隐藏帮助\nF2 保存 · F3 读取 · M 静音 · Esc 暂停菜单"
	add_child(help_label)

	# 浮动提示
	toast_label = _label(20, Vector2(560, 130), 400)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.modulate = Color(1, 1, 1, 0)
	add_child(toast_label)


## 量一段文字在某字号下的实际像素宽度。
## 【为什么要显式量】面板宽度如果只按常量算，换字体/换文案就会溢出；
## 实测宽度才是唯一可靠依据。没字体时返回一个保守估计，保证自检不崩。
func _text_width(s: String, fs: int) -> float:
	var f: Font = U.font()
	if f == null:
		return float(s.length()) * float(fs) * 1.05
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


## 触控模式重排：左下让给摇杆、右侧让给按钮列、说明改写成触控说法
## W/H 为当前视口尺寸，k 为触控层缩放系数（由 TouchControls 发出）
##
## 【关键约束】桌面的"右侧竖列"是按 1440 宽写死的像素坐标（x=1150），
## 在别的分辨率下会跑到屏幕外或者压住触控按钮。所以这里必须把整列
## 按 k 重新贴到右上角，并且只占顶部这一条，把 y > 200k 全让出来。
##
## k      —— 几何缩放（面板尺寸、坐标），跟随触控层保持一致
## k_text —— 文字缩放，主调方会给一个不低于 k 的下界，防止竖屏下字小到读不了
## 返回值 —— 右侧竖列（时钟/季节/武器）的真实底边 y，触控层据此排系统小钮
func set_touch_mode(w: float, h: float, k: float, k_text: float = -1.0) -> float:
	_touch_mode = true
	if k_text < 0.0:
		k_text = U.text_scale(Vector2(w, h))
	help_label.text = (
		"左半屏任意处按下即出摇杆移动，推满自动奔跑\n"
		+ "右半屏拖动转视角，双指捏合缩放\n"
		+ "点击右半屏：采集附近的资源 / 攻击动物\n"
		+ "底栏 4 格：点一下切换武器或建筑\n"
		+ "右侧：使用（进屋 / 床边睡觉 / 攻击 / 放置）· 跳 · 潜 · 农事 · 旋转\n"
		+ "进水里自动游泳，按住「潜」下潜、松开上浮\n"
		+ "左上：菜单 · 背包 · 建造　　右上：存 / 读 / 加速 / 静音"
		+ "\n背包里可点武器直接装备，再点背包键或 Esc 关闭\n"
		+ "系统返回键 / 左上「菜单」唤出暂停菜单（会停下时间与天气）"
	)
	help_panel.visible = false
	help_label.visible = false
	return _arrange(w, h, k, k_text, true)


func _arrange(w: float, h: float, k: float, kt: float, touch: bool) -> float:
	_layout_args = Vector4(w, h, k, kt)

	# 粗体的实际宽高决定右侧保留区；触控层收到 layout_changed 后自动下移系统键。
	# 几何比例 k 与文字比例 kt 分开，窄屏可以保留操作空间，同时维持可读字号。
	const PAD_TOP := 16.0
	const PAD_X := 18.0
	const PANEL_W := 226.0
	const GAP := 6.0
	var sizes := [62.0, 40.0, 40.0]
	var pw := PANEL_W * k
	var labs := [clock_label, season_label, weapon_label]
	for s in ["第 88 天  88:88", "秋 · 第 88 天 · 雷雨", "武器：长矛"]:
		var need := _text_width(s, U.text_size(20 if s.begins_with("第") else 17, kt)) + 28.0 * k
		pw = maxf(pw, need)
	for i in labs.size():
		pw = maxf(pw, _text_width(labs[i].text, U.text_size(20 if i == 0 else 17, kt)) + 28.0 * k)
	pw = minf(pw, w * 0.5)
	var px := w - PAD_X * k - pw
	var cy := PAD_TOP * kt
	for i in _right_panels.size():
		var p: Panel = _right_panels[i]
		p.position = Vector2(px, cy)
		# 面板高 = 几何高 + 字号增量，保证字号涨上去后文字不会顶出面板
		var fs := U.text_size(20 if i == 0 else 17, kt)
		var l: Label = labs[i]
		# 必须先更新字体再设置尺寸，旧字号的 minimum_size 会把缩小后的标签撑出屏幕。
		l.add_theme_font_size_override("font_size", fs)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var text_h := U.font().get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, pw - 24.0 * k, fs).y
		var ph := maxf(sizes[i] * k, maxf(text_h, U.font().get_height(fs)) + 16.0 * k)
		p.size = Vector2(pw, ph)
		l.position = Vector2(px + 12.0 * k, cy + 6.0 * k)
		l.size = Vector2(pw - 24.0 * k, ph - 10.0 * k)
		l.add_theme_constant_override("outline_size", 0)
		l.clip_text = false
		cy += ph + GAP * k

	# Label 的主题行间距也占高度；只用 Font 行高会让第五行掉到面板外。
	var res_fs := U.text_size(19.0, kt)
	res_label.add_theme_font_size_override("font_size", res_fs)
	var rh := maxf(U.font().get_height(res_fs) * 5.0, res_label.get_minimum_size().y) + 10.0 * kt + 12.0 * k
	res_panel.position = Vector2(18.0 * kt, 16.0 * kt)
	res_panel.size = Vector2(minf(250.0 * kt, w * 0.45), rh)
	res_label.position = Vector2(34.0 * kt, 26.0 * kt)
	# 标签偏移随 kt 放大，左右留白也必须用 kt，不能拿触控的较小 k 去扣。
	res_label.size = Vector2(res_panel.size.x - 32.0 * kt, rh - 10.0 * kt - 12.0 * k)

	# 提示宽度扣除动作按钮占位，按真实文字高度上移，避免压住快捷栏。
	prompt_label.add_theme_font_size_override("font_size", U.text_size(20.0, kt, 13))
	prompt_label.position = Vector2(w * 0.5 - 280.0 * k, h - 232.0 * k)
	prompt_label.size = Vector2(560.0 * k, 56.0 * kt)
	# 窄屏提示允许换行；按可用宽度和最大三行高度居中，避开动作键与底栏。
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if touch:
		prompt_label.position.x = 154.0 * k
		prompt_label.size.x = maxf(120.0, w - 484.0 * k)
	else:
		prompt_label.size.x = minf(w - 40.0 * k, 680.0 * kt)
		prompt_label.position = Vector2((w - prompt_label.size.x) * 0.5, h - 120.0 * kt)
	var prompt_fs := U.text_size(20, kt)
	prompt_label.size.y = maxf(U.font().get_height(prompt_fs),
		U.font().get_multiline_string_size(prompt_label.text, HORIZONTAL_ALIGNMENT_LEFT, prompt_label.size.x, prompt_fs).y)
	if touch:
		prompt_label.position.y = h - 180.0 * k - prompt_label.size.y
	var by := 16.0 * kt + rh + 12.0 * k
	# 【为什么 x 不从 18k 起】左上角那一列现在是触控按钮的地盘：
	# touch_controls.gd 的左侧竖排（菜单/背包/建造）占 x ∈ [58k, 142k]。
	# 建造菜单贴着 18k 起会正好压在「菜单」按钮上，所以让它从竖排右侧开始。
	# 154k = 58k(左距) + 84k(钮宽) + 12k(间隙)，改那边的 sx/sw 要同步改这里。
	# 字号随 kt 放大，但列表宽度必须扣除两侧触控按钮的几何占位。
	build_label.add_theme_font_size_override("font_size", U.text_size(18.0, kt, 12))
	build_label.position = Vector2(TOUCH_LEFT_COL_RIGHT * k, by)
	build_label.size = Vector2(minf(420.0 * kt, w - 514.0 * k), 170.0 * kt)
	build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not touch:
		build_label.size.x = minf(340.0 * kt, w * 0.45)
		build_label.position = Vector2(w - build_label.size.x - 18.0 * k, cy + 24.0 * k)
	build_label.size.y = maxf(U.font().get_height(U.text_size(18, kt)),
		U.font().get_multiline_string_size(build_label.text, HORIZONTAL_ALIGNMENT_LEFT, build_label.size.x, U.text_size(18, kt)).y)

	# —— 憋气条：贴屏幕顶部正中 ——
	# 【为什么是顶部正中】左上被资源栏占着、右上被系统小钮占着、下方全是操作键，
	# 顶部中间是整块屏幕上唯一空着的地方。
	if breath_panel != null:
		breath_panel.position = Vector2(w * 0.5 - 160.0 * kt, 24.0 * k)
		breath_panel.size = Vector2(320.0 * kt, 22.0 * kt)
	if breath_fill != null:
		var pad := 4.0 * kt
		breath_fill.position = breath_panel.position + Vector2(pad, pad)
		breath_fill.size = Vector2(312.0 * kt, 14.0 * kt)
		# 满格宽度必须跟着缩放走：set_breath 用它算填充比例，
		# 面板位置改了而这里没改的话，条子会一直按旧宽度画。
		_breath_full_w = 312.0 * kt
		# 顶部窄屏已被资源和时钟占用，将憋气条放到两列下方。
		if w < 1000.0 * kt:
			breath_panel.position.y = maxf(res_panel.position.y + rh, cy) + 16.0 * k
			breath_fill.position = breath_panel.position + Vector2(pad, pad)
			if breath_panel.visible:
				build_label.position.y = maxf(build_label.position.y,
					breath_panel.position.y + breath_panel.size.y + 12.0 * k)

	var toast_fs := U.text_size(20, kt)
	toast_label.add_theme_font_size_override("font_size", toast_fs)
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.size = Vector2(minf(w - 36.0 * k, 560.0 * kt), U.font().get_height(toast_fs) * 2.0)
	toast_label.position = Vector2((w - toast_label.size.x) * 0.5, maxf(cy, res_panel.position.y + rh) + 20.0 * k)
	if touch:
		toast_label.position.x = 154.0 * k
		toast_label.size.x = maxf(120.0, w - 484.0 * k)
		if build_label.visible:
			toast_label.position.y = maxf(toast_label.position.y, build_label.position.y + build_label.size.y + 18.0 * k)
	var help_fs := U.text_size(16, kt)
	help_label.add_theme_font_size_override("font_size", help_fs)
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var hw := minf(680.0 * kt, w * 0.44)
	# Label 自身还有主题行间距；先设置换行宽度，再读真实最小高度，不能只量 Font。
	help_label.size.x = hw - 24.0 * k
	var hh := minf(help_label.get_minimum_size().y + 24.0 * k, h * 0.65)
	help_panel.size = Vector2(hw, hh)
	help_panel.position = Vector2(18.0 * k, h - hh - 18.0 * k)
	help_label.position = help_panel.position + Vector2(12, 10) * k
	help_label.size = help_panel.size - Vector2(24, 20) * k
	if not touch and help_panel.visible:
		prompt_label.position.x = help_panel.position.x + hw + 12.0 * k
		prompt_label.size.x = w - prompt_label.position.x - 18.0 * k
	if not is_equal_approx(cy, _last_bottom):
		_last_bottom = cy
		layout_changed.emit(cy)

	return cy


func _refresh_layout() -> void:
	if _layout_args.x > 0:
		_arrange(_layout_args.x, _layout_args.y, _layout_args.z, _layout_args.w, _touch_mode)


func show_help_panel(on: bool) -> void:
	help_panel.visible = on
	help_label.visible = on
	_refresh_layout()


func set_resources(res: Dictionary) -> void:
	var t := ""
	for k in ["wood", "stone", "fiber", "ore", "food"]:
		t += "%s  %d\n" % [RES_NAME[k], int(res.get(k, 0))]
	t = t.trim_suffix("\n")
	if res_label.text == t:
		return
	res_label.text = t
	_refresh_layout()


func set_clock(day: int, clock: String, speed: float) -> void:
	var text := "第 %d 天   %s%s" % [day, clock, "   >>" if speed > 1.0 else ""]
	if clock_label.text == text:
		return
	clock_label.text = text
	_refresh_layout()


func set_season(text: String) -> void:
	if season_label != null and season_label.text != text:
		season_label.text = text
		_refresh_layout()


func set_weapon(text: String) -> void:
	if weapon_label != null and weapon_label.text != text:
		weapon_label.text = text
		_refresh_layout()


func set_prompt(text: String) -> void:
	if prompt_label.text == text:
		return
	prompt_label.text = text
	# 空文本不该占地方：留着一个透明矩形会挡住下面的触控按钮（有布局自检兜底）
	prompt_label.visible = (text != "")
	_refresh_layout()


func set_build(text: String) -> void:
	if build_label.text == text:
		return
	build_label.text = text
	build_label.visible = (text != "")
	_refresh_layout()


func toast(text: String) -> void:
	toast_label.text = text
	toast_t = 1.8
	_refresh_layout()


func _process(dt: float) -> void:
	if toast_t > 0.0:
		toast_t -= dt
		toast_label.modulate.a = clampf(toast_t / 0.6, 0.0, 1.0)
	else:
		toast_label.modulate.a = 0.0
