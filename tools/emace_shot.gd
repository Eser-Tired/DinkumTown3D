extends Node
## 固定种子、机位与光照，--no-emace 用同一脚本拍替换前。

var m: Node3D
var camera: Camera3D
var output := "res://asset_shots/"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--dir")
	if at >= 0 and at + 1 < args.size():
		output = args[at + 1].trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	seed(20260921)
	get_window().size = Vector2i(1440, 810)
	get_viewport().size = Vector2i(1440, 810)
	m = load("res://scripts/main.gd").new()
	m.forced_map_seed = 20260921
	add_child(m)
	for child in m.get_children():
		if child is CanvasLayer:
			child.visible = false
	m.dn.time = 0.39
	m.dn.speed_scale = 0.0
	for body in m.physics_props:
		body.freeze = true
	camera = Camera3D.new()
	camera.fov = 58.0
	m.add_child(camera)
	camera.make_current()
	var hut: Node3D = m.get_node("SampleHut")
	camera.global_position = hut.to_global(Vector3(-9, 6.5, 12))
	camera.look_at(hut.to_global(Vector3(0, 2.0, 0)))
	await _shot("hut")
	var entry := hut.to_global(Vector3(-0.65, 0, 6.08775))
	m.player.restore_motion(Vector3(entry.x, float(m.terrain.height_at(entry.x, entry.z)) + 0.05, entry.z))
	camera.global_position = hut.to_global(Vector3(-6, 3.5, 10))
	camera.look_at(hut.to_global(Vector3(-1.0, 1.8, 2.0)))
	await _shot("entrance")
	var crate: Node3D = m.physics_props[0]
	camera.global_position = crate.global_position + Vector3(1.9, 1.7, 2.3)
	camera.look_at(crate.global_position)
	await _shot("crate")
	var c: Vector2 = m.TOWN
	var ground: float = m.terrain.height_at(c.x, c.y)
	camera.global_position = Vector3(c.x + 21, ground + 15, c.y + 25)
	camera.look_at(Vector3(c.x - 2, ground + 1.0, c.y - 5))
	await _shot("town")
	print("==== EMACE SHOT DONE ====")
	get_tree().quit()


func _shot(name: String) -> void:
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output + name + ".png")
	if error != OK:
		push_error("截图失败 %s: %d" % [name, error])
