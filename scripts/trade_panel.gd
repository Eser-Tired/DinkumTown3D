extends CanvasLayer
## 窗口只显示报价和请求交易；金币、资源、库存的真值均在 main，不能在按钮回调里分头扣账。
const U := preload("res://scripts/ui_layout.gd")
const GOODS := ["wood", "stone", "fiber", "ore", "food"]
const PRICES := {"wood": [4, 2], "stone": [4, 2], "fiber": [3, 1], "ore": [12, 6], "food": [8, 4]}
const DAILY_STOCK := 20
var world: Node3D
var speaker: CharacterBody3D
var panel: Panel
var shade: ColorRect
var title: Label
var greeting: Label
var balance: Label
var notice: Label
var close_button: Button
var batch_button: Button
var rows: Array = []
var quantity := 1
signal closed()

func _ready() -> void:
	layer = 35
	visible = false
	shade = ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.8)
	add_child(shade)
	panel = Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.12, 0.16, 0.98)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	title = _label("")
	greeting = _label("")
	greeting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	balance = _label("")
	notice = _label("")
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.max_lines_visible = 2
	close_button = _button("关闭", close)
	batch_button = _button("每次 1 个", func():
		quantity = 10 if quantity == 1 else 1
		refresh())
	for kind in GOODS:
		var row := {"kind": kind, "label": _label(""),
			"buy": _button("", func(): _request(kind, true)),
			"sell": _button("", func(): _request(kind, false))}
		rows.append(row)
	U.bind(self, _layout)

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.95, 0.97, 1))
	add_child(label)
	return label
func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	add_child(button)
	return button
func _place(control: Control, rect: Rect2, scale: float, font_size := 18) -> void:
	var desired := rect.size * scale
	# 必须先换小字体，再缩控件；反过来会被上一分辨率的最小尺寸卡住，横竖旋转后按钮重叠。
	control.add_theme_font_size_override("font_size", U.text_size(font_size, scale))
	if control is Button or (control is Label and control.autowrap_mode == TextServer.AUTOWRAP_OFF):
		control.add_theme_font_size_override("font_size", U.fit_text(control.text, font_size, scale, desired))
	control.position = panel.position + rect.position * scale
	control.size = desired

func _layout() -> void:
	if panel == null: return
	var viewport := get_viewport().get_visible_rect().size
	var shopping: bool = speaker == null or speaker.merchant
	var height := 600.0 if shopping else 180.0
	var k := U.menu_scale(viewport, Vector2(660, height))
	shade.position = Vector2.ZERO
	shade.size = viewport
	panel.size = Vector2(660, height) * k
	panel.position = (viewport - panel.size) * 0.5
	_place(title, Rect2(24, 18, 450, 42), k, 26)
	_place(close_button, Rect2(532, 18, 104, 44), k)
	_place(greeting, Rect2(24, 78, 612, 72), k)
	if shopping:
		_place(balance, Rect2(24, 156, 400, 38), k)
		_place(batch_button, Rect2(474, 152, 162, 44), k)
		for i in rows.size():
			var row: Dictionary = rows[i]
			var y := 210 + i * 62
			_place(row.label, Rect2(24, y, 278, 58), k)
			_place(row.buy, Rect2(314, y + 4, 150, 48), k)
			_place(row.sell, Rect2(478, y + 4, 158, 48), k)
		_place(notice, Rect2(24, 526, 612, 62), k, 17)

func is_open() -> bool: return visible
func open(main: Node3D, npc: CharacterBody3D) -> void:
	world = main
	speaker = npc
	speaker.engaged = true
	quantity = 1
	notice.text = "先卖出采集物赚金币；库存每天补至20。" if npc.merchant else ""
	visible = true
	GameBus.ui_blocking = true
	GameBus.touch_move = Vector2.ZERO
	GameBus.touch_run = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
func close() -> void:
	if is_instance_valid(speaker): speaker.engaged = false
	visible = false
	GameBus.ui_blocking = false
	closed.emit()
func refresh() -> void:
	if world == null or not is_instance_valid(speaker): return
	world.restock_shop()
	title.text = speaker.display_name
	greeting.text = "欢迎来杂货铺！木材、石料和野外收获都能换金币。选好数量后直接买入或卖出。" if speaker.merchant else "我住在附近，平时在家门前散步。采集物可以拿到杂货铺卖给老板，也可以留着建造。"
	if speaker.merchant and world.is_creative(): greeting.text = "创造模式资源无限，无需采购或出售。切回生存模式后，恢复原有资源和金币。"
	balance.text = "金币：%d" % world.coins
	balance.visible = speaker.merchant
	notice.visible = speaker.merchant
	batch_button.visible = speaker.merchant
	batch_button.text = "每次 %d 个" % quantity
	for row: Dictionary in rows:
		row.label.visible = speaker.merchant
		row.buy.visible = speaker.merchant
		row.sell.visible = speaker.merchant
		var kind: String = row.kind
		row.label.text = "%s　持有 %d\n店内库存 %d" % [GameHUD.RES_NAME[kind], int(world.inv.get(kind, 0)), int(world.shop_stock.get(kind, 0))]
		row.buy.text = "买入 %d 金" % (int(PRICES[kind][0]) * quantity)
		row.sell.text = "卖出 %d 金" % (int(PRICES[kind][1]) * quantity)
		row.buy.disabled = world.coins < int(PRICES[kind][0]) * quantity or int(world.shop_stock.get(kind, 0)) < quantity
		row.sell.disabled = int(world.inv.get(kind, 0)) < quantity
		if world.is_creative():
			row.buy.disabled = true
			row.sell.disabled = true
	_layout()
func _request(kind: String, buying: bool) -> void:
	notice.text = world.trade(kind, buying, quantity)
	refresh()

func _process(_dt: float) -> void:
	if visible and (not is_instance_valid(speaker) or not world.can_talk(speaker)): close()
	elif visible and world.shop_stock_day != world.dn.day_count: refresh()
