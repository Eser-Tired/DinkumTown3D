extends Node
var m: Node3D
var output := "res://modes_shots/"
func frames(count: int) -> void:
	for i in count: await get_tree().physics_frame
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var at := args.find("--dir")
	if at >= 0 and at + 1 < args.size(): output = args[at+1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	get_window().size = Vector2i(1600,900)
	m = load("res://scripts/main.gd").new()
	m.forced_map_seed=20260921
	add_child(m)
	m.dn.time=0.42
	m.dn.speed_scale=0
	m.hud.show_help_panel(false)
	await frames(30)
	m.pause_menu.open()
	m.pause_menu._show_panel("settings")
	await frames(12)
	await shot("modes_settings_normal")
	m.pause_menu._settings._mode_option.emit_signal("item_selected",2)
	await frames(12)
	await shot("modes_settings_creative")
	m.pause_menu.close()
	m.inv_ui.open()
	await frames(12)
	await shot("modes_creative_inventory")
	m.inv_ui.close()
	m.survival.set_mode("hardcore")
	m.pause_menu.open()
	m.pause_menu._show_panel("settings")
	get_window().size = Vector2i(720,1280)
	get_viewport().size = Vector2i(720,1280)
	await frames(15)
	await shot("modes_settings_portrait")
	m.pause_menu.close()
	get_window().size=Vector2i(1600,900)
	get_viewport().size=Vector2i(1600,900)
	await frames(15)
	m.inv.wood=12
	m.inv.stone=5
	m.inv.food=3
	m.survival.damage_grace=0
	m.survival.damage(500,"动物反击")
	await frames(15)
	await shot("modes_world_ended")
	m.survival._overlay.visible=false
	var camera := Camera3D.new()
	camera.position = m.player.position + Vector3(3,3,4)
	add_child(camera)
	camera.look_at(m.player.position + Vector3(-0.4,0.25,0))
	camera.make_current()
	await frames(4)
	await shot("modes_death_drop")
	m.survival._overlay.visible=true
	get_window().size=Vector2i(720,1280)
	get_viewport().size=Vector2i(720,1280)
	await frames(15)
	await shot("modes_ended_portrait")
	get_tree().paused=false
	GameBus.ui_blocking=false
	print("==== MODES SHOT DONE ====")
	get_tree().quit()
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output.path_join(name+".png"))
	print("SHOT ",name," error=",error)
