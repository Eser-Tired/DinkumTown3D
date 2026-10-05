extends Huntable
## 三种 CC0 动物复用原来的狩猎槽位；旧存档按索引记录血量，数量、顺序和掉落不变。
var species := "Deer"
var small := false
var rig := preload("res://scripts/rigged_visual.gd").new()
const NAMES := {"Deer": "鹿", "Stag": "雄鹿", "Fox": "狐狸"}

func _build_model() -> Node3D:
	var root := Node3D.new()
	var height := 0.82 if small else (2.0 if species == "Stag" else 1.65)
	rig.attach(root, "res://assets/animals/" + species + ".scn", height)
	set_meta("species_name", NAMES[species])
	# 缩放后自然步速约0.84~0.97，普通走路只略快放；逃跑保持明确速度差。
	walk_speed = 1.4 if small else 1.15
	flee_speed = 5.4 if small else 6.6
	flee_dist = 16.0 if small else 12.0
	wander_r = 34.0 if small else 26.0
	hop_height = 0.0
	continuous_gait = true
	hop_interval = 0.42 if small else 0.74
	_configure(22 if small else 30, {"food": [2, 3] if small else [2, 4], "fiber": [1, 3] if small else [0, 2]}, 1.05 if small else 1.0)
	return root

func _process(dt: float) -> void:
	var before := global_position
	super._process(dt)
	if rig.root == null:
		return
	if dead:
		rig.play("Death", 0.06)
	elif stun > 0:
		rig.play("Idle_HitReact1", 0.05)
	else:
		var speed := Vector2(global_position.x - before.x, global_position.z - before.z).length() / maxf(dt, 0.001)
		if speed > 0.15:
			rig.locomote("Gallop" if speed > float(rig.gait_speeds["Walk"]) * 1.8 else "Walk", speed)
		else:
			rig.play("Idle")
		# 四足动物已有完整步态，不叠加袋鼠式的整身起伏。
		model.rotation.x = 0.0
		model.position.y = 0.0
	rig.animation.advance(dt)

func _pose_dead() -> void:
	if rig.root == null:
		super._pose_dead()
	else:
		model.rotation.z = 0.0
		model.position.y = 0.0
		model.scale = Vector3.ONE
