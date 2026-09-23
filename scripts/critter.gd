extends Node3D
class_name Critter
## 野生动物基类：随机游走 + 跳跃步态 + 靠近玩家时逃跑

var terrain: Node3D
var player_ref: Node3D
var rng := RandomNumberGenerator.new()

var walk_speed := 3.0
var flee_speed := 9.0
var hop_height := 0.9
var hop_interval := 0.75
var flee_dist := 11.0
var wander_r := 20.0

var home := Vector2.ZERO
var target := Vector2.ZERO
var timer := 0.0
var hop_t := -1.0
var model: Node3D


func setup(terr: Node3D, pos2: Vector2, pl: Node3D) -> void:
	terrain = terr
	player_ref = pl
	home = pos2
	target = pos2
	global_position = Vector3(pos2.x, terr.height_at(pos2.x, pos2.y), pos2.y)
	model = _build_model()
	add_child(model)


func _build_model() -> Node3D:
	return Node3D.new()


func _process(dt: float) -> void:
	if terrain == null or model == null or player_ref == null:
		return

	var p := global_position
	var pp := player_ref.global_position
	var to_p := Vector2(p.x - pp.x, p.z - pp.z)
	var fleeing := to_p.length() < flee_dist
	timer -= dt

	if fleeing:
		target = Vector2(p.x, p.z) + to_p.normalized() * 20.0
	elif timer <= 0.0:
		var a := rng.randf() * TAU
		var r := rng.randf() * wander_r
		target = home + Vector2(cos(a), sin(a)) * r
		timer = rng.randf_range(2.5, 6.5)

	var interval := hop_interval * (0.62 if fleeing else 1.0)
	var sp := flee_speed if fleeing else walk_speed
	var d2 := target - Vector2(p.x, p.z)

	if d2.length() > 0.7:
		var dir := d2.normalized()
		if hop_t < 0.0:
			hop_t = 0.0
		hop_t += dt
		if hop_t > interval:
			hop_t -= interval
		var boost := 1.0 + sin(hop_t / interval * PI) * 1.7
		p.x += dir.x * sp * boost * dt
		p.z += dir.y * sp * boost * dt
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.y), 0.16)
	else:
		hop_t = -1.0

	var lim := 108.0
	p.x = clampf(p.x, -lim, lim)
	p.z = clampf(p.z, -lim, lim)
	p.y = terrain.height_at(p.x, p.z)
	# 不进水：动物是贴地走的（p.y 直接取地形高度），一旦走进湖里就会一路沉到湖底，
	# 变成"水下袋鼠"。这里直接作废这一步移动——比给动物写一套游泳逻辑便宜得多，
	# 观感上也对：袋鼠本来就绕开水走。
	if terrain != null and terrain.has_method("water_depth_at") \
			and terrain.water_depth_at(p.x, p.z) > 0.0:
		p = global_position
	global_position = p

	if hop_t >= 0.0:
		var k := sin(hop_t / interval * PI)
		model.position.y = k * hop_height
		model.rotation.x = -k * 0.24
	else:
		model.rotation.x = 0.0
		model.position.y = sin(Time.get_ticks_msec() * 0.0018 + home.x) * 0.025
