extends CanvasLayer
class_name GameHUD
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

	# 交互提示（屏幕中下）
	prompt_label = _label(22, Vector2(390, 690), 660)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(prompt_label)

	# 建造菜单
	build_label = _label(18, Vector2(1050, 300), 320)
	build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(build_label)

	# 帮助
	help_panel = _panel(Vector2(18, 640), Vector2(560, 150), 0.45)
	add_child(help_panel)
	help_label = _label(16, Vector2(34, 650), 540)
	help_label.size = Vector2(540, 140)
	help_label.text = "WASD/方向键 移动 · Shift 奔跑 · 空格 跳跃\n鼠标右键拖拽 转视角 · 滚轮 缩放\nE 采集 · 左键 攻击 · Q 换武器 · 1-4 切物品栏\nB 建造模式 · 建造中 1-4 选建筑 · 左键放置\nI 背包 · F 农事 · G 换作物 · T 加速时间 · H 隐藏帮助\nF2 保存 · F3 读取 · M 静音 · Esc 暂停菜单"
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
	var f: Font = ThemeDB.fallback_font
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
	if k_text < 0.0:
		k_text = k
	help_label.text = (
		"左下摇杆移动，推满自动奔跑（长按可拖动重新定位）\n"
		+ "屏幕空白处拖动转视角，双指捏合缩放\n"
		+ "点击画面：采集附近的资源 / 攻击动物\n"
		+ "底栏 4 格：点一下切换武器或建筑\n"
		+ "右侧：使用（攻击/放置）· 跳 · 农事 · 旋转\n"
		+ "左上：菜单 · 背包 · 建造　　右上：存 / 读 / 加速 / 静音"
		+ "\n背包里可点武器直接装备，再点背包键或 Esc 关闭\n"
		+ "系统返回键 / 左上「菜单」唤出暂停菜单（会停下时间与天气）"
	)
	show_help_panel(false)

	# —— 右侧竖列：整体缩放到 k，贴右上 ——
	# 三块高度 62 / 40 / 40，块间距 6；文字标签比面板再多探出约 12k。
	# 整列底部（含标签）≈ 16 + 62+6 + 40+6 + 40+12 = 182k。
	# 触控层的系统按钮从 210k 起，两边不许越界——这个数字是跨文件的约定，
	# 改动右边任何一处都要同步检查 touch_controls.gd 的 SYS_ROW_Y。
	const PAD_TOP := 16.0
	const PAD_X := 18.0
	const PANEL_W := 226.0
	const GAP := 6.0
	# 【kt = 文字缩放，k = 几何缩放】几何可以缩得很小（留出操作空间），
	# 但文字小于 ~14px 就没法读了。所以面板尺寸/坐标用 kt，字号用 kt ≥ k。
	var kt := k_text
	# 【宽度为什么要跟 k 走】右侧竖列上方是触控层从 248k 起的系统小钮。
	# 竖屏下 kt（短边/810 = 1.33）远大于 k（0.75），宽度跟 kt 会让面板变胖、
	# 整列下探把系统小钮压住。所以宽度用 k 锚定右边缘，避免漂移。
	# 但字号用 kt 后文字会变宽（横屏实测「武器：斧头」超出 226k 面板约 12%），
	# 所以再按最长文字实测兜一个下限，保证不溢出不越屏。
	var sizes := [62.0, 40.0, 40.0]
	var pw := PANEL_W * k
	for s in ["第 88 天  88:88", "秋 · 第 88 天 · 雷雨", "武器：长矛"]:
		var need := _text_width(s, maxi(13, int((20 if s.begins_with("第") else 17) * kt))) + 28.0 * k
		pw = maxf(pw, need)
	pw = minf(pw, w * 0.5)
	var px := w - PAD_X * k - pw
	var labs := [clock_label, season_label, weapon_label]
	var cy := PAD_TOP * kt
	for i in _right_panels.size():
		var p: Panel = _right_panels[i]
		p.position = Vector2(px, cy)
		# 面板高 = 几何高 + 字号增量，保证字号涨上去后文字不会顶出面板
		var ph := maxf(sizes[i] * k, sizes[i] * kt - 6.0 * kt)
		p.size = Vector2(pw, ph)
		var l: Label = labs[i]
		l.position = Vector2(px + 12.0 * k, cy + 6.0 * k)
		l.size = Vector2(pw - 24.0 * k, ph - 10.0 * k)
		var fs := maxi(13, int((20 if i == 0 else 17) * kt))
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_constant_override("outline_size", 0)
		l.clip_text = false
		cy += ph + GAP * k

	# —— 资源栏：按 kt 缩放，贴左上。高度必须放得下 5 行 ——
	# 字号 19kt，Label 默认行高约 1.35 倍，5 行 ≈ 128kt；再加 20kt 上下边距。
	var rh := 150.0 * kt
	res_panel.position = Vector2(18.0 * kt, 16.0 * kt)
	res_panel.size = Vector2(250.0 * kt, rh)
	res_label.position = Vector2(34.0 * kt, 26.0 * kt)
	res_label.size = Vector2(230.0 * kt, rh - 20.0 * kt)
	res_label.add_theme_font_size_override("font_size", maxi(13, int(19.0 * kt)))

	# —— 提示与建造菜单 ——
	# 【为什么要抬到 232k】触控模式下底部物品栏顶边在 h-106k，格子高 88k；
	# 提示行高 56k 落在 h-175k 时正好把第 3/4 格盖住（竖屏下实测）。
	# 232k = 106k + 88k + 38k，留够间隔，同时仍在半屏以下不挡视野。
	# 宽度用 560k（不是 kt）：右侧「跳 / 农事 / 使用」竖列在竖屏下会横向侵入，
	# 用 kt 算宽度会把提示行撑到按钮底下。文字仍用 kt，靠水平居中和面板留白兜住。
	prompt_label.position = Vector2(w * 0.5 - 280.0 * k, h - 232.0 * k)
	prompt_label.size = Vector2(560.0 * k, 56.0 * kt)
	prompt_label.add_theme_font_size_override("font_size", maxi(13, int(20.0 * kt)))
	var by := 16.0 * kt + rh + 12.0 * k
	# 【为什么 x 不从 18k 起】左上角那一列现在是触控按钮的地盘：
	# touch_controls.gd 的左侧竖排（菜单/背包/建造）占 x ∈ [58k, 142k]。
	# 建造菜单贴着 18k 起会正好压在「菜单」按钮上，所以让它从竖排右侧开始。
	# 154k = 58k(左距) + 84k(钮宽) + 12k(间隙)，改那边的 sx/sw 要同步改这里。
	# 【为什么宽度用 330k 而不是 330kt】竖屏下 kt=1.33 会把宽度撑到 440，
	# 直接钻进右上系统小钮的地盘；用 k 算（竖屏 810 宽 -> 330*0.6=198）刚好够。
	build_label.position = Vector2(TOUCH_LEFT_COL_RIGHT * k, by)
	build_label.size = Vector2(330.0 * k, 170.0 * kt)
	build_label.add_theme_font_size_override("font_size", maxi(12, int(18.0 * kt)))
	build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	return cy


func show_help_panel(on: bool) -> void:
	help_panel.visible = on
	help_label.visible = on


func set_resources(res: Dictionary) -> void:
	var t := ""
	for k in ["wood", "stone", "fiber", "ore", "food"]:
		t += "%s  %d\n" % [RES_NAME[k], int(res.get(k, 0))]
	res_label.text = t


func set_clock(day: int, clock: String, speed: float) -> void:
	clock_label.text = "第 %d 天   %s%s" % [day, clock, "   >>" if speed > 1.0 else ""]


func set_season(text: String) -> void:
	if season_label != null:
		season_label.text = text


func set_weapon(text: String) -> void:
	if weapon_label != null:
		weapon_label.text = text


func set_prompt(text: String) -> void:
	prompt_label.text = text
	# 空文本不该占地方：留着一个透明矩形会挡住下面的触控按钮（有布局自检兜底）
	prompt_label.visible = (text != "")


func set_build(text: String) -> void:
	build_label.text = text
	build_label.visible = (text != "")


func toast(text: String) -> void:
	toast_label.text = text
	toast_t = 1.8


func _process(dt: float) -> void:
	if toast_t > 0.0:
		toast_t -= dt
		toast_label.modulate.a = clampf(toast_t / 0.6, 0.0, 1.0)
	else:
		toast_label.modulate.a = 0.0
