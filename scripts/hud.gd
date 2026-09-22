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
var toast_t := 0.0

const RES_NAME := {
	"wood": "木材", "stone": "石头", "fiber": "纤维", "ore": "铁矿石", "food": "食物"
}


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
	# 资源栏
	add_child(_panel(Vector2(18, 16), Vector2(250, 108)))
	res_label = _label(19, Vector2(34, 26), 230)
	res_label.size = Vector2(230, 96)
	res_label.text = "资源"
	add_child(res_label)

	# 时钟
	add_child(_panel(Vector2(1150, 16), Vector2(226, 62)))
	clock_label = _label(20, Vector2(1166, 28), 210)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(clock_label)

	# 季节 / 天气
	add_child(_panel(Vector2(1150, 84), Vector2(226, 40), 0.42))
	season_label = _label(17, Vector2(1166, 90), 210)
	season_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	season_label.text = "—"
	add_child(season_label)

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
	help_label.text = "WASD/方向键 移动 · Shift 奔跑 · 空格 跳跃\n鼠标右键拖拽 转视角 · 滚轮 缩放\nE 采集 · B 建造模式 · 1-4 选建筑 · 左键放置\nF 农事 · G 换作物 · T 加速时间 · H 隐藏帮助\nF2 保存 · F3 读取 · M 静音"
	add_child(help_label)

	# 浮动提示
	toast_label = _label(20, Vector2(560, 130), 400)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.modulate = Color(1, 1, 1, 0)
	add_child(toast_label)


## 触控模式重排：左下让给摇杆、右侧让给按钮列、说明改写成触控说法
## W/H 为当前视口尺寸，k 为触控层缩放系数（由 TouchControls 发出）
func set_touch_mode(w: float, h: float, k: float) -> void:
	help_label.text = (
		"左手摇杆贴左下角，向外推满自动奔跑\n"
		+ "屏幕空白处拖动转视角，双指捏合缩放\n"
		+ "右下大钮：采集 / 农事 / 跳\n"
		+ "右侧：放建筑 · 建造开关 · 旋转\n"
		+ "顶部：存 / 读 / 作物 / 加速 / 静音 / 帮助"
	)
	show_help_panel(false)
	prompt_label.position = Vector2(w * 0.5 - 280.0 * k, h - 175.0 * k)
	prompt_label.size = Vector2(560.0 * k, 56.0 * k)
	build_label.position = Vector2(18.0 * k, 142.0 * k)
	build_label.size = Vector2(330.0 * k, 140.0 * k)
	build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


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


func set_prompt(text: String) -> void:
	prompt_label.text = text


func set_build(text: String) -> void:
	build_label.text = text


func toast(text: String) -> void:
	toast_label.text = text
	toast_t = 1.8


func _process(dt: float) -> void:
	if toast_t > 0.0:
		toast_t -= dt
		toast_label.modulate.a = clampf(toast_t / 0.6, 0.0, 1.0)
	else:
		toast_label.modulate.a = 0.0
