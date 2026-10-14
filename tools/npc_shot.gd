extends Node
## 用运行中的骨骼和物理位移拍摄待机、迈步、停步，以及实际柜台和交易窗口。
var m: Node3D
var output := "res://npc_shots/"
var camera: Camera3D
func frames(count: int) -> void:
	for i in count: await get_tree().physics_frame
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--dir")
	if index >= 0 and index + 1 < args.size(): output = args[index + 1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	get_window().size = Vector2i(1600,900)
	m = load("res://scripts/main.gd").new()
	m.forced_map_seed = 20260921
	add_child(m)
	m.dn.time = 0.42
	m.dn.speed_scale = 0
	m.hud.show_help_panel(false)
	await frames(20)
	var npc: CharacterBody3D = m.npcs[2]
	camera = Camera3D.new()
	camera.near = 0.08
	add_child(camera)
	camera.make_current()
	npc.engaged = true
	await frames(16)
	frame_npc(npc)
	await shot("npc_idle")
	npc.engaged = false
	for i in 900:
		await frames(1)
		if npc.actual_speed > 1.1: break
	for i in 3:
		await frames(12)
		frame_npc(npc)
		await shot("npc_walk_%d" % i)
	npc.engaged = true
	await frames(20)
	frame_npc(npc)
	await shot("npc_stopped")
	m.player.restore_motion(npc.global_position + Vector3(0,0,-1.2))
	await frames(8)
	m._on_touch_action("use")
	await frames(5)
	await shot("npc_dialogue")
	m._back_requested()
	npc.engaged = false
	var room: Dictionary = m.interior.space_of("shop_0")
	m.player.restore_motion(room.frame.to_global(Vector3(0.8,0.22,-1.25)))
	m.player.yaw = float(room.frame.rotation.y) + 0.6
	m.player.pitch = -0.1
	m.player._indoor_cam_dist = 2.2
	m.player.cam.make_current()
	await frames(45)
	await shot("npc_shopkeeper")
	m.inv.wood = 25
	m._interact()
	m.trade_panel.rows[0].sell.emit_signal("pressed")
	await frames(5)
	await shot("npc_trade_desktop")
	get_window().size = Vector2i(720,1280)
	get_viewport().size = Vector2i(720,1280)
	await frames(15)
	await shot("npc_trade_portrait")
	m._back_requested()
	print("==== NPC SHOT DONE ====")
	get_tree().quit()
func frame_npc(npc: CharacterBody3D) -> void:
	camera.position = npc.global_position + Vector3(2.3,1.75,4.3).rotated(Vector3.UP, npc.rotation.y)
	camera.look_at(npc.global_position + Vector3.UP)
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))
	print("SHOT ", name, " error=", error, " npc=", m.npcs[2].position, " gait=", m.npcs[2].rig.current, " speed=", m.npcs[2].actual_speed)
