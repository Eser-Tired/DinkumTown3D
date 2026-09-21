extends Node3D
class_name DayNight
## 昼夜循环：太阳轨迹 + 天空/雾/环境光渐变 + 夜间灯光自动开关

var sun: DirectionalLight3D
var fill: DirectionalLight3D
var env: WorldEnvironment
var sky_mat: ProceduralSkyMaterial
var night_lights: Array = []

var time := 0.30          # 0=午夜 0.25=日出 0.5=正午 0.75=日落
var day_length := 420.0   # 一个游戏日 = 7 分钟
var day_count := 1
var speed_scale := 1.0


func setup(root: Node) -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.shadow_bias = 0.07
	sun.shadow_normal_bias = 1.2
	root.add_child(sun)

	fill = DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.shadow_enabled = false
	fill.light_color = Color(0.55, 0.68, 0.95)
	fill.light_energy = 0.28
	root.add_child(fill)
	fill.position = Vector3(-30, 40, -20)
	fill.look_at(Vector3.ZERO)

	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_cover_modulate = Color(0.75, 0.85, 1.0)
	sky_mat.sun_angle_max = 7.0
	sky_mat.sun_curve = 0.14

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.3
	e.fog_enabled = true
	e.fog_aerial_perspective = 0.35
	e.fog_sky_affect = 0.10
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_hdr_threshold = 0.95
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.1

	env = WorldEnvironment.new()
	env.name = "WorldEnvironment"
	env.environment = e
	root.add_child(env)

	_update(0.0)


func collect_night_lights(root: Node) -> void:
	night_lights.clear()
	_scan(root)


func _scan(n: Node) -> void:
	if n is OmniLight3D and n.has_meta("night_light"):
		n.set_meta("base_energy", n.light_energy)
		night_lights.append(n)
	for c in n.get_children():
		_scan(c)


func toggle_speed() -> void:
	speed_scale = 8.0 if speed_scale == 1.0 else 1.0


func clock_string() -> String:
	var h := int(time * 24.0)
	var m := int((time * 24.0 - float(h)) * 60.0)
	return "%02d:%02d" % [h, m]


func _process(dt: float) -> void:
	time += dt * speed_scale / day_length
	while time >= 1.0:
		time -= 1.0
		day_count += 1
	_update(dt)


func _update(_dt: float) -> void:
	if sun == null:
		return

	# —— 太阳轨迹 ——
	var a := (time - 0.25) * TAU
	var dir := Vector3(cos(a), sin(a), 0.32).normalized()
	sun.position = dir * 90.0
	sun.look_at(Vector3.ZERO, Vector3.UP)

	var elev := sin(a)
	var day_f := clampf(elev * 2.2, 0.0, 1.0)
	var dusk_f := clampf(1.0 - absf(elev) * 3.2, 0.0, 1.0)

	var col := Color(0.40, 0.50, 0.85).lerp(Color(1.0, 0.95, 0.84), day_f)
	col = col.lerp(Color(1.0, 0.52, 0.26), dusk_f * 0.80)
	sun.light_color = col
	sun.light_energy = lerpf(0.14, 1.30, day_f) + dusk_f * 0.40
	sun.visible = elev > -0.22
	fill.light_energy = lerpf(0.10, 0.30, day_f)

	# —— 天空 ——
	var top := Color(0.045, 0.070, 0.170).lerp(Color(0.33, 0.60, 0.92), day_f)
	top = top.lerp(Color(0.14, 0.20, 0.42), dusk_f * 0.55)
	var hor := Color(0.09, 0.13, 0.27).lerp(Color(0.80, 0.90, 0.98), day_f)
	hor = hor.lerp(Color(0.96, 0.52, 0.28), dusk_f * 0.75)
	var gr := Color(0.05, 0.06, 0.11).lerp(Color(0.62, 0.55, 0.42), day_f)
	gr = gr.lerp(Color(0.34, 0.19, 0.13), dusk_f * 0.50)

	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = gr
	sky_mat.ground_bottom_color = gr * 0.92
	sky_mat.sky_energy_multiplier = lerpf(0.30, 1.10, day_f)
	sky_mat.ground_energy_multiplier = lerpf(0.24, 1.00, day_f)

	var e := env.environment
	e.fog_light_color = hor
	e.fog_density = lerpf(0.0060, 0.0012, day_f)
	e.ambient_light_energy = lerpf(0.26, 0.40, day_f)
	e.ambient_light_color = hor.lerp(Color(0.85, 0.90, 1.0), day_f * 0.65)
	e.adjustment_enabled = true
	e.adjustment_contrast = lerpf(0.95, 1.10, day_f)
	e.adjustment_saturation = lerpf(0.85, 1.20, day_f)
	e.adjustment_brightness = lerpf(0.92, 0.99, day_f)

	# —— 夜间灯光 ——
	var night := clampf(1.0 - day_f * 3.2, 0.0, 1.0)
	for l in night_lights:
		var base: float = l.get_meta("base_energy", 5.0)
		l.visible = night > 0.02
		l.light_energy = base * lerpf(0.05, 1.0, night)
