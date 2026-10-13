extends Node2D
## 窗口模式拍摄真实进出：门扇半开、跨门槛、室内看向户外；所有进出都由实际走动完成。
const InteriorS := preload("res://scripts/interior.gd")
var m: Node3D
var output := "res://interior_shots_seamless/"
var samples := 0
var max_step := 0.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--dir")
	if at >= 0 and at + 1 < args.size(): output = args[at + 1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	get_window().size = Vector2i(1600, 900)
	m = load("res://scripts/main.gd").new()
	m.forced_map_seed = 20260921
	add_child(m)
	m.dn.time = 0.42
	m.dn.speed_scale = 0
	m.hud.show_help_panel(false)
	await _frames(45)
	var house: Dictionary = m.houses[1]
	var frame: Node3D = house.node
	var spec: Dictionary = InteriorS.spec_of(str(house.kind))
	m.player.restore_motion(frame.to_global(Vector3(0, 0.23, float(spec.door_z) + 1.45)))
	m.player.yaw = float(house.rot)
	m.player.pitch = -0.15
	m.player.cam_dist = 9
	await _frames(45)
	await _shot("house_closed")
	var before: Vector3 = m.player.global_position
	m._interact()
	await _frames(7)
	print("DOOR opening angle=", m.interior.space_of(str(house.id)).door.rotation.y, " player_delta=", before.distance_to(m.player.global_position))
	await _shot("door_opening")
	await _frames(25)
	await _shot("door_open")
	await _walk(frame.to_global(Vector3(0, 0.23, float(spec.door_z) - 0.4)))
	await _frames(25)
	await _shot("threshold")
	await _walk(frame.to_global(Vector3(0, 0.23, 0)))
	m.player.pitch = -0.18
	m.player._indoor_cam_dist = 3.2
	await _frames(45)
	await _shot("hut_inside")
	m.player.yaw = float(house.rot) + PI
	await _frames(45)
	await _shot("hut_view_outside")
	m.player.yaw = float(house.rot)
	await _walk(frame.to_global(Vector3(0, 0.23, float(spec.door_z) + 1.45)))
	await _frames(30)
	await _shot("walk_outside")
	await _room(m.houses[0], "shop_inside")
	await _room(m.houses[4], "tent_inside")
	print("==== INTERIOR SHOT DONE samples=%d max_step=%.4f ====" % [samples, max_step])
	get_tree().quit()

func _room(house: Dictionary, name: String) -> void:
	var frame: Node3D = house.node
	var spec: Dictionary = InteriorS.spec_of(str(house.kind))
	m.player.restore_motion(frame.to_global(Vector3(0, 0.23, float(spec.door_z) + 1.45)))
	m.player.yaw = float(house.rot)
	m.player.pitch = -0.2
	await _frames(20)
	await _walk(frame.to_global(Vector3(0, 0.23, 0)))
	await _frames(45)
	await _shot(name)
	await _walk(frame.to_global(Vector3(0, 0.23, float(spec.door_z) + 1.45)))

func _walk(target: Vector3) -> void:
	var yaw: float = m.player.yaw
	for i in 480:
		var pos: Vector3 = m.player.global_position
		var offset := Vector3(target.x - pos.x, 0, target.z - pos.z)
		if offset.length() < 0.12: break
		var direction := offset.normalized().rotated(Vector3.UP, -yaw)
		GameBus.touch_move = Vector2(direction.x, direction.z)
		await get_tree().physics_frame
		var moved: Vector3 = m.player.global_position - pos
		max_step = maxf(max_step, Vector2(moved.x, moved.z).length())
		samples += 1
	GameBus.touch_move = Vector2.ZERO
	print("SHOT_WALK target=", target, " actual=", m.player.global_position, " house=", m.house_id)

func _frames(count: int) -> void:
	for i in count: await get_tree().physics_frame
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))
	if error != OK: push_error("截图失败：" + name)
	print("SHOT ", name, " cam_distance=", m.player.cam.position.z, " camera=", m.player.cam.global_position)
