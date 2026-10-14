extends Node
## 每个世界的模式、生命与永久死亡状态。全局 settings.cfg 不承载这些存档属性。
const U := preload("res://scripts/ui_layout.gd")
const NORMAL := "normal"
const HARDCORE := "hardcore"
const CREATIVE := "creative"
const MODES := [NORMAL, HARDCORE, CREATIVE]
const NAMES := {NORMAL: "普通生存", HARDCORE: "真实生存", CREATIVE: "创造模式"}
const MAX_HEALTH := 100.0
const DEATH_DIR := "user://ended_worlds"
var world: Node3D
var mode := NORMAL
var world_id := ""
var health := MAX_HEALTH
var ended := false
var dying := false
var damage_grace := 0.0
var death_reason := ""
var death_loot := {}
var death_position := Vector3.ZERO
var _animal_timers := {}
var _overlay: CanvasLayer
var _panel: Panel
var _title: Label
var _message: Label
var _back: Button
var _drop: Node3D

static func new_id() -> String: return Crypto.new().generate_random_bytes(16).hex_encode()
static func valid_id(id: String) -> bool: return id.length() == 32 and id.is_valid_hex_number(false)
static func is_locked(id: String) -> bool:
	return valid_id(id) and FileAccess.file_exists(DEATH_DIR.path_join(id + ".ended"))
static func name_of(value: String) -> String: return NAMES.get(value, NAMES[NORMAL])

func _ready() -> void:
	# 结束画面必须在暂停时仍能返回菜单；生命逻辑另行拒绝暂停期间推进。
	process_mode = Node.PROCESS_MODE_ALWAYS
	world_id = new_id()
	mode = GameBus.new_game_mode if GameBus.new_game_mode in MODES else NORMAL
	GameBus.new_game_mode = NORMAL
	_build_end_ui()
	_sync_hud()

func creative() -> bool: return mode == CREATIVE and not ended
func playable() -> bool: return not ended and not dying
func set_mode(value: String) -> bool:
	if value not in MODES or not playable() or is_locked(world_id): return false
	mode = value
	if creative(): heal()
	for beast in world.critters: beast.retaliate_time = 0
	_animal_timers.clear()
	_sync_hud()
	# 修改的是当前槽位的存档，不是全局偏好；失败必须反馈，不能假装已持久化。
	if world.save_sys != null and not world.save_sys.save(world.save_sys.active_slot):
		GameBus.toast.emit("模式已切换，但保存失败，请检查存档目录")
	return true
func heal() -> void:
	if not playable(): return
	health = MAX_HEALTH
	_sync_hud()

func damage(amount: float, reason: String, use_grace := true) -> void:
	if not playable() or creative() or amount <= 0 or (use_grace and damage_grace > 0): return
	health = maxf(0, health - amount)
	if use_grace: damage_grace = 0.7
	_sync_hud()
	if health <= 0:
		dying = true
		death_reason = reason
		# 环境伤害会在玩家物理帧内调用；延后处理，避免复位后同一帧又推进旧移动。
		_resolve_death.call_deferred()
	elif amount >= 1: world.hud.toast("%s · 生命 %.0f/100" % [reason, health])

func land(impact_speed: float) -> void:
	# 起跳速度7.4，正常跳跃不受伤。11m/s约对应2.9米落差，超出部分每m/s扣5点。
	if impact_speed > 11.0: damage((impact_speed - 11.0) * 5.0, "摔伤")

func provoke(beast: Node3D) -> void:
	if not playable() or creative() or beast.dead: return
	# 再次激怒时重置上一场战斗遗留的计时，不能沿用负数冷却立即伤人。
	if beast.retaliate_time <= 0: _animal_timers[beast.get_instance_id()] = 0.8
	beast.retaliate_time = 5.0

func _physics_process(dt: float) -> void:
	if get_tree().paused or not playable(): return
	damage_grace = maxf(0, damage_grace - dt)
	var player: CharacterBody3D = world.player
	# 氧气耗尽后仍淹着才受伤；自动上浮仍保留，但被地形困在深处会真的溺亡。
	if player.breath <= 0.001 and player.head_underwater(): damage(12.0 * dt, "溺水", false)
	if creative() or not playable(): return
	for beast in world.critters:
		if not is_instance_valid(beast) or beast.dead or beast.retaliate_time <= 0: continue
		var id: int = beast.get_instance_id()
		# 0.8秒给首次反击留出反应时间；后续1.6秒一击，100生命需要十次才会耗尽。
		var timer: float = float(_animal_timers.get(id, 0.8)) - dt
		_animal_timers[id] = timer
		if timer > 0 or beast.stun > 0: continue
		if world.player.indoor or world.player.swimming: continue
		var direction: Vector3 = player.global_position - beast.global_position
		if direction.length() > 2.0 or Vector2(sin(beast.rotation.y), cos(beast.rotation.y)).dot(Vector2(direction.x, direction.z).normalized()) < 0.5: continue
		var ray := PhysicsRayQueryParameters3D.create(beast.global_position + Vector3.UP * 0.6,
			player.global_position + Vector3.UP * 0.6, 17)
		if not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		_animal_timers[id] = 1.6
		damage(10, "动物反击")

func _resolve_death() -> void:
	if not dying: return
	for beast in world.critters: beast.retaliate_time = 0
	_animal_timers.clear()
	if mode == NORMAL:
		dying = false
		health = MAX_HEALTH
		# 重生后三秒保护，避免出生点附近的碰撞或动物造成连续死亡。
		damage_grace = 3.0
		if world.house_id != "": world._apply_exit(true)
		var point: Vector2 = world.TOWN + Vector2(0, 17)
		world.player.restore_motion(Vector3(point.x, world.terrain.height_at(point.x, point.y) + 0.05, point.y))
		world.player.breath = 1
		world.player.diving = false
		world.hud.toast("死亡后回到镇上 · 背包保留")
		_sync_hud()
		return
	ended = true
	dying = false
	if world.player.rig.root != null and world.player.rig.animation.has_animation("Death"):
		world.player.rig.play("Death", 0)
		world.player.rig.animation.advance(world.player.rig.animation.get_animation("Death").length)
	else:
		world.player.model.rotation.z = 1.35
		world.player.model.position.y = 0.05
	death_position = world.player.global_position
	death_loot = world.inv.duplicate()
	for kind in world.inv: world.inv[kind] = 0
	# 独立世界标记先落盘：旧槽位快照也不能在死亡后回滚复活，标记不随删槽位移除。
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEATH_DIR))
	var marker := FileAccess.open(DEATH_DIR.path_join(world_id + ".ended"), FileAccess.WRITE)
	if marker != null:
		marker.store_string(JSON.stringify({"reason": death_reason, "loot": death_loot}))
		marker.close()
	else: push_error("永久死亡标记保存失败")
	world._release_touch()
	if world.trade_panel.is_open(): world.trade_panel.close()
	if world.inv_ui.is_open(): world.inv_ui.close()
	_show_drop()
	_sync_hud()
	if not world.save_sys.save(world.save_sys.active_slot): world.hud.toast("死亡存档保存失败")
	_show_end()

func snapshot() -> Dictionary:
	return {"mode": mode, "world_id": world_id, "health": health, "ended": ended,
		"reason": death_reason, "loot": death_loot.duplicate(), "death_pos": [death_position.x, death_position.y, death_position.z]}
func can_restore(data: Variant) -> bool:
	return not (data is Dictionary and (bool(data.get("ended", false)) or is_locked(str(data.get("world_id", "")))))
func restore(data: Variant) -> bool:
	if not can_restore(data): return false
	var state: Dictionary = data if data is Dictionary else {}
	mode = str(state.get("mode", NORMAL))
	if mode not in MODES: mode = NORMAL
	var id := str(state.get("world_id", ""))
	world_id = id if valid_id(id) else new_id()
	health = clampf(float(state.get("health", MAX_HEALTH)), 1, MAX_HEALTH)
	ended = false
	dying = false
	damage_grace = 0
	death_loot.clear()
	_animal_timers.clear()
	for beast in world.critters: beast.retaliate_time = 0
	if is_instance_valid(_drop): _drop.queue_free()
	_sync_hud()
	return true

func _sync_hud() -> void:
	if world.hud != null:
		world.hud.set_survival_status(name_of(mode), health, creative())
		world.hud.set_resources(world.inv)
	if world.inv_ui != null and world.inv_ui.is_open(): world.inv_ui.refresh()

func _show_drop() -> void:
	_drop = Node3D.new()
	var visual: Node3D = preload("res://scripts/optional_assets.gd").fitted("crate", Vector3(0.7,0.7,0.7), Vector3(0,0.35,0))
	if visual == null:
		# 美术回退不能打断死亡结算，否则已扣背包却没有结束画面。
		visual = preload("res://scripts/props.gd").make_crates()
		visual.scale = Vector3.ONE * 0.6
	# fitted 已将箱底对齐局部地面；世界位置要给包装节点，不能覆盖模型的归一化偏移。
	_drop.add_child(visual)
	_drop.name = "DeathResourceDrop"
	_drop.set_meta("death_loot", death_loot.duplicate())
	_drop.position = death_position
	var room: Dictionary = world.interior.space_at(death_position)
	_drop.position.y = float(room.floor_y) if not room.is_empty() else world.terrain.height_at(death_position.x, death_position.z)
	world.add_child(_drop)

func _build_end_ui() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	_overlay.visible = false
	add_child(_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.03, 0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(shade)
	_panel = Panel.new()
	_overlay.add_child(_panel)
	_title = Label.new()
	_title.text = "这个世界已经结束"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.add_child(_title)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay.add_child(_message)
	_back = Button.new()
	_back.text = "返回主菜单"
	_back.pressed.connect(world.return_to_menu)
	_overlay.add_child(_back)
	U.bind(self, _layout_end)
func _layout_end() -> void:
	if _panel == null: return
	var viewport := get_viewport().get_visible_rect().size
	var k := U.menu_scale(viewport, Vector2(700,640))
	_panel.size = Vector2(700,640) * k
	_panel.position = (viewport - _panel.size) * 0.5
	for entry in [[_title, Rect2(24,22,652,52),28], [_message, Rect2(30,98,640,440),19], [_back, Rect2(180,564,340,52),20]]:
		var node: Control = entry[0]
		node.add_theme_font_size_override("font_size", U.text_size(entry[2], k))
		node.position = _panel.position + entry[1].position * k
		node.size = entry[1].size * k
	# 换行Label的最小高度在宽度/字体变动后一帧才稳定，需二次收回旧分辨率撑大的高度。
	_fit_end_message.call_deferred()
func _fit_end_message() -> void:
	var k := U.menu_scale(get_viewport().get_visible_rect().size, Vector2(700,640))
	_message.size = Vector2(640,440) * k
func _show_end() -> void:
	_message.text = "真实生存 · %s\n生命已耗尽，无法复活或切换模式。\n背包资源已掉落在死亡位置：\n" % death_reason
	for kind in death_loot: _message.text += "%s ×%d\n" % [GameHUD.RES_NAME.get(kind,kind), int(death_loot[kind])]
	_message.text += "\n这个世界的旧槽位也已锁定。可以开始另一个新世界。"
	_overlay.visible = true
	GameBus.ui_blocking = true
	get_tree().paused = true
	_layout_end()
func _unhandled_input(event: InputEvent) -> void:
	if ended and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		world.return_to_menu()
