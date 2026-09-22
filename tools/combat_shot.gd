extends Node3D
## 战斗场景截图（仅调试）——把玩家摆到动物旁边并挥砍，抓几个关键瞬间
## 运行：Godot --path <项目> res://tools/combat_shot.tscn -- --shot-dir <目录>

var m: Node3D
var base := "res://"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var di: int = args.find("--shot-dir")
	if di >= 0 and di + 1 < args.size():
		base = args[di + 1]
		if not base.ends_with("/"):
			base += "/"

	var MS = load("res://scripts/main.gd")
	m = MS.new()
	add_child(m)
	for i in 12:
		await get_tree().process_frame

	# 白天，光线好
	m.dn.time = 0.42
	if m.season != null:
		m.season.weather = "clear"
		m.season._apply_now()

	# 找一只活着的袋鼠当模特
	var beast: Huntable = null
	for c in m.critters:
		if not is_instance_valid(c):
			continue
		var sp: String = c.get_script().resource_path if c.get_script() != null else ""
		if sp.ends_with("kangaroo.gd") and not (c as Huntable).is_dead():
			beast = c
			break
	if beast == null:
		for c in m.critters:
			if is_instance_valid(c) and not (c as Huntable).is_dead():
				beast = c
				break
	if beast == null:
		get_tree().quit(0)
		return

	# 相机拉到侧面看，别用背后视角挡住动物
	m.player.yaw = PI * 0.75
	m.player.pitch = -0.30
	m.player.cam_dist = 8.0

	# 【关键】袋鼠 flee_dist 12 米，玩家一靠近它就跑，截图必然拍空。
	# 调试脚本里把它按住：flee_dist 归零 + 每帧锁回原位。
	beast.flee_dist = 0.0
	beast.walk_speed = 0.0
	beast.hop_height = 0.0
	var anchor := Vector2(beast.global_position.x, beast.global_position.z)

	# —— 1) 靠近并挥砍的瞬间 ——
	m.player.global_position = Vector3(
		anchor.x, m.terrain.height_at(anchor.x, anchor.y - 1.6), anchor.y - 1.6)
	m.player.model.rotation.y = 0.0
	await get_tree().create_timer(0.4).timeout
	beast.global_position = Vector3(
		anchor.x, m.terrain.height_at(anchor.x, anchor.y), anchor.y)

	m.player.attack_cd = 0.0
	m._attack()
	# 挥砍动画进行到 30% 时抓帧，正好是下劈最用力的位置
	await get_tree().create_timer(0.09).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "combat1_swing.png")

	# —— 2) 受击脉冲（伤害刚结算） ——
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "combat2_hit.png")

	# —— 3) 击杀倒地 ——
	var swings := 0
	while not beast.is_dead() and swings < 30:
		swings += 1
		beast.global_position = Vector3(
			anchor.x, m.terrain.height_at(anchor.x, anchor.y), anchor.y)
		m.player.attack_cd = 0.0
		m._attack()
		await get_tree().create_timer(0.05).timeout
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "combat3_down.png")

	# —— 4) 掉落与库存（toast 会显示 +N 食物） ——
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + "combat4_loot.png")

	print("[combat_shot] done, dead=%s swings=%d food=%d" % [
		str(beast.is_dead()), swings, int(m.inv.get("food", 0))])
	get_tree().quit(0)
