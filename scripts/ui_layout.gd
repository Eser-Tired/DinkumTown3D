extends RefCounted
## 字号独立于触控几何缩放；使用系统粗体，无需随项目分发外部字体文件。

static var _font: SystemFont


static func font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Noto Sans", "Arial"])
		_font.font_weight = 700
	return _font


static func bold(node: Control) -> void:
	node.add_theme_font_override("font", font())


static func apply_tree(node: Node) -> void:
	if node is Label or node is BaseButton:
		bold(node)
		if node is OptionButton:
			node.get_popup().add_theme_font_override("font", font())
	for child in node.get_children():
		apply_tree(child)


static func bind(owner: Node, layout: Callable) -> void:
	apply_tree(owner)
	owner.get_viewport().size_changed.connect(layout)
	layout.call_deferred()


static func text_scale(size: Vector2) -> float:
	return clampf(minf(size.x, size.y) / 810.0, 0.65, 3.2)


static func menu_scale(size: Vector2, footprint := Vector2(700, 650)) -> float:
	# 先按短边放大，再用可用宽高限制整块面板，避免大字把窄屏挤出屏幕。
	return maxf(0.3, minf(text_scale(size),
		minf((size.x - 40.0) / footprint.x, (size.y - 40.0) / footprint.y)))


static func text_size(base: float, scale: float, minimum := 16) -> int:
	return maxi(maxi(minimum, 16), int(roundf(base * scale * 1.15)))


static func fit_text(text: String, base: float, scale: float, size: Vector2, padding := 10.0) -> int:
	var fs := text_size(base, scale)
	var lines := text.split("\n")
	# 量真实粗体的宽高，按钮留白也参与计算；不是靠缩小整个控件换取不溢出。
	while fs > 11:
		var width := 0.0
		for line in lines:
			width = maxf(width, font().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if width <= size.x - padding and font().get_height(fs) * lines.size() <= size.y - padding:
			break
		fs -= 1
	return fs
