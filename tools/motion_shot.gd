extends Node3D
## 同一机位拍初始站立、停步和完整周期；HTML 可逐帧查看，不能用一张正常帧替代验收。
var rigs := []
var output := "res://asset_shots_motion/"

func _ready() -> void:
	get_window().size = Vector2i(1440, 1000)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.16, 0.20, 0.26)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.82, 0.87, 0.97)
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.shadow_enabled = true
	add_child(light)
	var plane := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(20, 20)
	plane.mesh = floor_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.30, 0.34, 0.38)
	plane.material_override = material
	add_child(plane)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16.0
	camera.position = Vector3(11, 15, 22)
	add_child(camera)
	camera.look_at(Vector3(0, 0.5, 0))
	var args := OS.get_cmdline_user_args()
	# --before 需先从对应旧提交导出适配器到这个临时路径，临时脚本不随项目提交。
	var rig_script := load("res://tools/_motion_before.gd") if args.has("--before") else load("res://scripts/rigged_visual.gd")
	for i in 4:
		var kind: String = ["Adventurer", "Deer", "Stag", "Fox"][i]
		for j in 3:
			var parent := Node3D.new()
			parent.position = Vector3((j - 1) * 4.2, 0, (i - 1.5) * 3.7)
			add_child(parent)
			var rig: RefCounted = rig_script.new()
			rig.attach(parent, "res://assets/" + ("characters/" if i == 0 else "animals/") + kind + ".scn", [1.82, 1.65, 2.0, 0.82][i])
			var gait: String = "Walk" if j == 1 else ("Run" if i == 0 else "Gallop")
			if j == 0:
				rig.play("Walk", 0.0)
				rig.animation.advance(0.63)
				rig.play("Idle_Neutral" if i == 0 and not args.has("--before") else "Idle", 0.12)
				for k in 120: rig.animation.advance(1.0 / 60)
			else:
				rig.play(gait, 0.0)
				rig.animation.advance(0.0)
			rigs.append({"rig": rig, "gait": gait, "column": j})
			var label := Label3D.new()
			label.text = kind + " / " + ["停步", "Walk", "Run" if i == 0 else "Gallop"][j]
			label.font_size = 40
			label.pixel_size = 0.009
			label.position = parent.position + Vector3(0, 0.06, 1.2)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			add_child(label)
	for frame in 12:
		for entry in rigs:
			if entry.column == 0: continue
			var ap: AnimationPlayer = entry.rig.animation
			ap.seek(ap.get_animation(entry.gait).length * frame / 12.0, true)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(output + ("before_" if args.has("--before") else "after_") + str(frame).pad_zeros(2) + ".png")
		assert(error == OK)
	print("==== MOTION SHOT DONE ====")
	get_tree().quit()
