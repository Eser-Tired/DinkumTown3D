extends CanvasLayer
class_name InventoryUI
## 背包界面 —— 资源概览 / 武器装备 / 进度统计
##
## 【为什么 layer = 30】
## 要盖住 HUD（layer 10）和触控层（layer 20）。否则手机上点背包格子时，
## 事件会先被下面的虚拟摇杆或动作键接着走一遍。
##
## 【为什么 resource 格子承载的是"计数"而不是"物品实体"】
## 当前物品模型是 main.inv 的计数字典（wood/stone/fiber/ore/food），
## 采集直接 +N，没有独立物品实例。改成实体制要动存档格式、所有采集点、
## 掉落表和建造扣费，收益不抵风险。所以这里做成"格子"的外观，
## 格子里的数字是资源计数——按钮名副其实，又不引入大规模重构。
##
## 【为什么不暂停游戏】
## 项目没有暂停概念（DayNight 一直在走）。背包做成非模态遮罩，
## 打开时通过 GameBus.ui_blocking 屏蔽世界输入，但时间照常流逝。

const WeaponsS := preload("res://scripts/weapons.gd")

const RES_ORDER := ["wood", "stone", "fiber", "ore", "food"]

## 布局基准（对应 k=1，即 1440x810）
const PANEL_W := 640.0
const PANEL_H := 452.0
const CELL_W := 176.0
const CELL_H := 66.0
const CELL_GAP := 12.0
const COLS := 3

var _bg: Panel
var _box: Panel
var _title: Label
var _stat: Label
var _cells: Array = []          ## 资源格子的 Label（只显示，不可点）
var _weapon_btns: Array = []    ## 武器按钮（可点，装备）
var _close: Button
var _k := 1.0
var _vs := Vector2.ZERO

var _get_inv: Callable
var _get_stat: Callable
var _on_equip: Callable
var _equipped_id := ""

signal closed()


func _ready() -> void:
	layer = 30
	name = "InventoryUI"
	visible = false
	_build()


## 由 main 注入数据源，避免背包反向依赖 main 的内部结构
##   get_inv()  -> Dictionary，资源计数
##   get_stat() -> String，底部统计行
##   on_equip(id) -> void，装备某把武器
func setup(get_inv: Callable, get_stat: Callable, on_equip: Callable) -> void:
	_get_inv = get_inv
	_get_stat = get_stat
	_on_equip = on_equip


# ——————————————— 构建 ———————————————
func _build() -> void:
	# 全屏遮罩：负责吃掉点击，防止穿透到下面的世界 / 触控层
	_bg = Panel.new()
	_bg.modulate = Color(0.02, 0.03, 0.05, 0.62)
	add_child(_bg)

	_box = _panel(Color(0.07, 0.10, 0.14, 0.94))
	add_child(_box)

	_title = _label(26, Color(1, 1, 1, 0.98))
	_title.text = "背包"
	add_child(_title)

	# 资源格子：5 种资源排成 3 列
	for kind in RES_ORDER:
		var cell := _panel(Color(0.12, 0.17, 0.24, 0.85))
		add_child(cell)
		var lb := _label(19, Color(1, 1, 1, 0.95))
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(lb)
		_cells.append({"panel": cell, "label": lb, "kind": kind})

	_stat = _label(16, Color(0.78, 0.84, 0.92, 0.92))
	add_child(_stat)

	_close = _button("关闭")
	_close.pressed.connect(func(): close())
	add_child(_close)

	# 武器格子数量由 WeaponsS 决定，建表时就定好
	var n: int = WeaponsS.count()
	for i in n:
		var w: Dictionary = WeaponsS.get_at(i)
		var b := _button("")
		var wid: String = str(w.get("id", ""))
		b.pressed.connect(func(): _equip(wid))
		add_child(b)
		_weapon_btns.append({"btn": b, "id": wid})


func _panel(c: Color) -> Panel:
	var p := Panel.new()
	p.modulate = c
	return p


func _label(fs: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", maxi(10, int(fs * _k)))
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", maxi(10, int(17 * _k)))
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	return b


# ——————————————— 布局 ———————————————
## 每次打开都重算：分辨率可能在游戏中途变（旋转 / 分屏）
func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	_vs = vs
	# 【为什么这里不用 0.60 下限】背包是纯阅读界面，没有"按钮太小按不准"的问题，
	# 面板缩到 384x271（竖屏 0.60 时）文字只剩 10~12px，完全没法看。
	# 这里改用短边独立算：竖屏 1080x2340 -> k = 1080/810 = 1.33，面板够大够读；
	# 横屏 1440x810 -> k = 1.0，与桌面观感一致。再宽也不超过 1.6，避免占满屏。
	_k = clampf(minf(vs.x / 1440.0, vs.y / 810.0), 0.60, 2.2)
	var kd := clampf(minf(vs.x / 900.0, vs.y / 700.0), 0.0, 1.6)
	var k := maxf(_k, kd * 0.75)

	_bg.position = Vector2.ZERO
	_bg.size = vs

	var bw := PANEL_W * k
	var bh := PANEL_H * k
	var bx := (vs.x - bw) * 0.5
	var by := (vs.y - bh) * 0.5
	_box.position = Vector2(bx, by)
	_box.size = Vector2(bw, bh)

	var px := bx + 22.0 * k
	var py := by + 16.0 * k
	var inner := bw - 44.0 * k

	_title.position = Vector2(px, py)
	_title.size = Vector2(inner * 0.6, 34.0 * k)
	_title.add_theme_font_size_override("font_size", maxi(12, int(26 * k)))

	_close.size = Vector2(96.0 * k, 38.0 * k)
	_close.position = Vector2(bx + bw - 22.0 * k - _close.size.x, py - 2.0 * k)
	_close.add_theme_font_size_override("font_size", maxi(10, int(17 * k)))

	# —— 资源格子 ——
	var gy := py + 48.0 * k
	for i in _cells.size():
		var c: Dictionary = _cells[i]
		var col: int = i % COLS
		var row: int = i / COLS
		var cx := px + col * (CELL_W + CELL_GAP) * k
		var cy := gy + row * (CELL_H + CELL_GAP) * k
		var p: Panel = c.panel
		p.position = Vector2(cx, cy)
		p.size = Vector2(CELL_W * k, CELL_H * k)
		var l: Label = c.label
		l.position = Vector2(cx, cy + 14.0 * k)
		l.size = Vector2(CELL_W * k, CELL_H * k - 20.0 * k)
		l.add_theme_font_size_override("font_size", maxi(11, int(19 * k)))

	# —— 武器区 ——
	var wy := gy + 2.0 * (CELL_H + CELL_GAP) * k + 18.0 * k
	var wrow := Vector2(px, wy)
	for i in _weapon_btns.size():
		var e: Dictionary = _weapon_btns[i]
		var b: Button = e.btn
		b.size = Vector2(inner, 46.0 * k)
		b.position = Vector2(wrow.x, wrow.y + i * (46.0 + 10.0) * k)
		b.add_theme_font_size_override("font_size", maxi(11, int(17 * k)))

	# —— 统计 ——
	var sy := by + bh - 44.0 * k
	_stat.position = Vector2(px, sy)
	_stat.size = Vector2(inner, 30.0 * k)
	_stat.add_theme_font_size_override("font_size", maxi(10, int(16 * k)))


# ——————————————— 开关 ———————————————
func is_open() -> bool:
	return visible


func open() -> void:
	_layout()
	refresh()
	visible = true
	# 屏蔽世界输入：触控层的 _input 在 GUI 之前触发，光靠遮罩挡不住
	GameBus.ui_blocking = true


func close() -> void:
	visible = false
	GameBus.ui_blocking = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


# ——————————————— 刷新 ———————————————
## 重新读取数据源并刷新文字。开背包时资源可能刚变动（采集/建造扣费），
## 所以必须在 open() 里调，不能只在构建时填一次。
func refresh() -> void:
	if _get_inv.is_valid():
		var inv: Dictionary = _get_inv.call()
		for i in _cells.size():
			var c: Dictionary = _cells[i]
			var kind: String = str(c.kind)
			var n: int = int(inv.get(kind, 0))
			var lb: Label = c.label
			lb.text = "%s\n%d" % [GameHUD.RES_NAME.get(kind, kind), n]

	if _get_stat.is_valid():
		_stat.text = str(_get_stat.call())

	# 武器按钮：显示数值，并标出当前装备的那把
	for i in _weapon_btns.size():
		var e: Dictionary = _weapon_btns[i]
		var w: Dictionary = WeaponsS.get_at(i)
		var b: Button = e.btn
		var mark := "▶ " if str(e.id) == _equipped_id else "    "
		b.text = "%s%s   伤害 %d · 距离 %.1f · 冷却 %.2fs" % [
			mark, str(w.get("name", "?")),
			int(w.get("dmg", 0)), float(w.get("reach", 0.0)), float(w.get("cd", 0.0))]
		_style_weapon(b, str(e.id) == _equipped_id)


func set_equipped(id: String) -> void:
	_equipped_id = id
	if visible:
		refresh()


func _equip(id: String) -> void:
	if _on_equip.is_valid():
		_on_equip.call(id)
	_equipped_id = id
	refresh()


func _style_weapon(b: Button, on: bool) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.62, 0.44, 0.16, 0.90) if on else Color(0.12, 0.17, 0.24, 0.85)
	s.set_corner_radius_all(int(10 * _k))
	s.border_color = Color(0.85, 0.70, 0.35, 0.9) if on else Color(1, 1, 1, 0.14)
	s.set_border_width_all(maxi(1, int(2 * _k)))
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("hover", s)
