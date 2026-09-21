extends Node
class_name SeasonManager
## 季节循环 + 天气系统
## main.gd 中：var sm := SeasonManager.new(); add_child(sm); sm.setup(dn, terrain)
## process_priority = 10 → 排在 DayNight(prio 0) 之后执行，环境参数以本模块的叠加结果为准

# ============================== 季节 ==============================
const DAYS_PER_SEASON := 8
const SEASON_COUNT := 4
const SEASON_NAMES := ["春", "夏", "秋", "冬"]
const GROWTH_MULT := [1.25, 1.0, 0.85, 0.45]

# 地面着色（通过 terrain.apply_season_tint 下发）
const TINT_COL := [
	Color(0.44, 0.68, 0.30),  # 春：嫩绿
	Color(0.76, 0.66, 0.26),  # 夏：枯黄
	Color(0.68, 0.40, 0.16),  # 秋：橙褐
	Color(0.82, 0.86, 0.90),  # 冬：灰白
]
const TINT_AMOUNT := [0.40, 0.44, 0.56, 0.62]

# 天空 / 雾 / 环境光的季节目标色
const SKY_TOP := [
	Color(0.16, 0.34, 0.64),
	Color(0.30, 0.38, 0.54),
	Color(0.26, 0.26, 0.46),
	Color(0.22, 0.28, 0.44),
]
const SKY_HOR := [
	Color(0.72, 0.86, 0.95),
	Color(0.94, 0.87, 0.62),
	Color(0.95, 0.68, 0.42),
	Color(0.80, 0.84, 0.91),
]
const FOG_COL := [
	Color(0.74, 0.84, 0.90),
	Color(0.88, 0.81, 0.60),
	Color(0.84, 0.64, 0.44),
	Color(0.78, 0.82, 0.88),
]
const AMB_COL := [
	Color(0.80, 0.92, 1.00),
	Color(1.00, 0.94, 0.78),
	Color(0.98, 0.84, 0.70),
	Color(0.86, 0.90, 0.98),
]
const AMB_MULT := [1.05, 1.10, 1.00, 0.92]
const ENV_MIX := 0.55

# ============================== 天气 ==============================
const W_NAMES := ["clear", "rain", "heat"]
const W_CLEAR := [0.42, 0.50, 0.64, 0.62]
const W_RAIN := [0.46, 0.14, 0.28, 0.36]
const W_HEAT := [0.12, 0.36, 0.08, 0.02]
const W_MIN := 0.30
const W_MAX := 0.80
const W_FADE_DAYS := 0.06

const RAIN_TOP := Color(0.30, 0.33, 0.39)
const RAIN_HOR := Color(0.46, 0.49, 0.54)
const RAIN_FOG := Color(0.50, 0.53, 0.58)
const HEAT_TOP := Color(0.36, 0.34, 0.28)
const HEAT_HOR := Color(0.96, 0.87, 0.66)
const HEAT_FOG := Color(0.88, 0.80, 0.60)

const RAIN_COUNT := 720
const RAIN_RADIUS := 24.0
const RAIN_SPAN := 26.0

# ============================== 运行时状态 ==============================
var daynight: Node
var terrain: Node

var season := 0                 # 0 春 1 夏 2 秋 3 冬
var day_in_season := 0          # 当季已过天数
var growth_mult := 1.25
var weather: String = "clear"
var weather_left := 0.5         # 当前天气剩余时长（单位：游戏日）

var rng := RandomNumberGenerator.new()

var _last_day := -1
var _tint: Color = Color(0.44, 0.68, 0.30)
var _tint_amount := 0.40
var _i_rain := 0.0              # 雨天视觉强度 0..1（淡入淡出）
var _i_heat := 0.0

var rain_root: Node3D
var rain_mmi: MultiMeshInstance3D
var _rx := PackedFloat32Array()
var _ry := PackedFloat32Array()
var _rz := PackedFloat32Array()
var _rs := PackedFloat32Array()
var _rain_basis := Basis().rotated(Vector3(0.0, 0.0, 1.0), -0.10)


# ============================== 生命周期 ==============================
func setup(p_daynight: Node, p_terrain: Node) -> void:
	daynight = p_daynight
	terrain = p_terrain
	process_priority = 10
	set_process(true)
	_last_day = -1
	rng.randomize()
	if weather_left < 0.05:
		weather_left = 0.5

	GameBus.register_module("season", self)

	_commit_season(true)
	_emit_weather()
	_apply_now()


func _process(dt: float) -> void:
	if daynight == null or not is_instance_valid(daynight):
		return

	var cur: int = int(_dn_num("day_count", 1.0))
	if _last_day < 0:
		_last_day = cur
	var diff := cur - _last_day
	if diff > 0:
		_last_day = cur
		var n := 0
		while n < diff and n < 64:
			_step_day()
			n += 1

	# 天气按「游戏日的几分之一」推进
	weather_left -= dt * _day_frac_per_sec()
	var guard := 0
	while weather_left <= 0.0 and guard < 8:
		_pick_weather()
		guard += 1
	if weather_left < 0.0:
		weather_left = 0.0

	_update_rain(dt)
	_apply_env(dt)


# ============================== 公共接口 ==============================
func season_name() -> String:
	var nm: String = SEASON_NAMES[clampi(season, 0, SEASON_COUNT - 1)]
	return nm


func days_left_in_season() -> int:
	return DAYS_PER_SEASON - day_in_season


func weather_name() -> String:
	var w: String = weather
	return w


## 调试：直接推进 n 个游戏日（同时同步昼夜计数器，避免 _process 重复计日）
func advance_days(n: int) -> void:
	if n <= 0:
		return
	for i in n:
		_step_day()
	if daynight != null and is_instance_valid(daynight):
		var cur2: int = int(_dn_num("day_count", 1.0)) + n
		daynight.set("day_count", cur2)
		_last_day = cur2
	_apply_now()


# ============================== 序列化 ==============================
func serialize() -> Dictionary:
	return {
		"season": season,
		"season_name": season_name(),
		"day_in_season": day_in_season,
		"growth_mult": growth_mult,
		"weather": weather,
		"weather_left": weather_left,
		"tint": [_tint.r, _tint.g, _tint.b, _tint.a],
		"tint_amount": _tint_amount,
		"intensity_rain": _i_rain,
		"intensity_heat": _i_heat,
		"last_day": _last_day,
		"rng_state": rng.state,
	}


func deserialize(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return

	season = clampi(int(d.get("season", 0)), 0, SEASON_COUNT - 1)
	day_in_season = clampi(int(d.get("day_in_season", 0)), 0, DAYS_PER_SEASON - 1)
	growth_mult = float(d.get("growth_mult", float(GROWTH_MULT[season])))

	var w := String(d.get("weather", "clear"))
	weather = w if W_NAMES.has(w) else "clear"
	weather_left = maxf(float(d.get("weather_left", 0.5)), 0.02)

	_tint = _read_color(d, "tint", Color(TINT_COL[season]))
	_tint_amount = clampf(float(d.get("tint_amount", float(TINT_AMOUNT[season]))), 0.0, 1.0)
	_i_rain = clampf(float(d.get("intensity_rain", 0.0)), 0.0, 1.0)
	_i_heat = clampf(float(d.get("intensity_heat", 0.0)), 0.0, 1.0)
	_last_day = int(d.get("last_day", -1))

	var st = d.get("rng_state", null)
	if st is int:
		rng.state = int(st)

	_apply_now()


# ============================== 日 / 季推进 ==============================
func _step_day() -> void:
	day_in_season += 1
	var new_season := false
	while day_in_season >= DAYS_PER_SEASON:
		day_in_season -= DAYS_PER_SEASON
		season = (season + 1) % SEASON_COUNT
		new_season = true
	if new_season:
		_commit_season(true)

	var day_id: int = int(_dn_num("day_count", 1.0))
	GameBus.new_day.emit(day_id, season)

	# 把这一「天」切碎推进天气，保证不足一天的天气也能正确轮转
	var budget := 1.0
	var guard := 0
	while budget > 0.0001 and guard < 64:
		if weather_left <= 0.0001:
			_pick_weather()
		var chunk: float = minf(budget, maxf(weather_left, 0.0001))
		budget -= chunk
		weather_left -= chunk
		guard += 1


func _commit_season(notify: bool) -> void:
	season = posmod(season, SEASON_COUNT)
	growth_mult = float(GROWTH_MULT[season])
	var tc: Color = TINT_COL[season]
	_tint = tc
	_tint_amount = float(TINT_AMOUNT[season])
	_apply_terrain_tint()
	if notify:
		GameBus.season_changed.emit(season, season_name(), growth_mult)
		GameBus.toast.emit("入" + season_name() + "了")


func _pick_weather() -> void:
	var wc: float = float(W_CLEAR[season])
	var wr: float = float(W_RAIN[season])
	var wh: float = float(W_HEAT[season])
	var total := maxf(wc + wr + wh, 0.0001)
	var roll := rng.randf() * total
	var pick := "clear"
	if roll >= wc:
		pick = "rain" if roll < wc + wr else "heat"
	_set_weather(pick)
	weather_left += rng.randf_range(W_MIN, W_MAX)


func _set_weather(w: String) -> void:
	if w == weather:
		return
	weather = w
	GameBus.weather_changed.emit(weather)
	if weather == "rain":
		GameBus.toast.emit("下雨了")
	elif weather == "heat":
		GameBus.toast.emit("热浪来袭")
	else:
		GameBus.toast.emit("天气转晴")


func _emit_weather() -> void:
	GameBus.weather_changed.emit(weather)


# ============================== 视觉 ==============================
func _apply_now() -> void:
	_i_rain = 1.0 if weather == "rain" else 0.0
	_i_heat = 1.0 if weather == "heat" else 0.0
	_apply_terrain_tint()
	_apply_env(0.0)
	if weather == "rain":
		_ensure_rain()
		_update_rain(0.0)


func _apply_terrain_tint() -> void:
	if terrain == null or not is_instance_valid(terrain):
		return
	if not terrain.has_method("apply_season_tint"):
		return
	terrain.apply_season_tint(_tint, _tint_amount)


func _apply_env(dt: float) -> void:
	if daynight == null or not is_instance_valid(daynight):
		return

	# 天气强度淡入淡出（按游戏日计）
	var step: float = dt * _day_frac_per_sec() / maxf(W_FADE_DAYS, 0.0001)
	_i_rain = move_toward(_i_rain, 1.0 if weather == "rain" else 0.0, step)
	_i_heat = move_toward(_i_heat, 1.0 if weather == "heat" else 0.0, step)

	var we = daynight.get("env")
	if not (we is WorldEnvironment):
		return
	var e: Environment = (we as WorldEnvironment).environment
	if e == null:
		return

	var sun: DirectionalLight3D = daynight.get("sun") as DirectionalLight3D
	var sky: ProceduralSkyMaterial = daynight.get("sky_mat") as ProceduralSkyMaterial

	var mix := ENV_MIX
	var s_top: Color = SKY_TOP[season]
	var s_hor: Color = SKY_HOR[season]
	var s_fog: Color = FOG_COL[season]
	var s_amb: Color = AMB_COL[season]
	var s_mult: float = float(AMB_MULT[season])

	# —— 天空 ——
	if sky != null:
		var top: Color = sky.sky_top_color.lerp(s_top, mix)
		var hor: Color = sky.sky_horizon_color.lerp(s_hor, mix)
		var grd: Color = sky.ground_horizon_color.lerp(_tint * 0.62, mix * 0.7)
		if _i_rain > 0.001:
			top = top.lerp(RAIN_TOP, _i_rain * 0.85)
			hor = hor.lerp(RAIN_HOR, _i_rain * 0.85)
			grd = grd.lerp(RAIN_TOP, _i_rain * 0.80)
		if _i_heat > 0.001:
			top = top.lerp(HEAT_TOP, _i_heat * 0.60)
			hor = hor.lerp(HEAT_HOR, _i_heat * 0.60)
			grd = grd.lerp(HEAT_HOR, _i_heat * 0.40)
		sky.sky_top_color = top
		sky.sky_horizon_color = hor
		sky.ground_horizon_color = grd
		sky.ground_bottom_color = grd * 0.92
		sky.sky_energy_multiplier *= lerpf(1.0, 0.45, _i_rain) * lerpf(1.0, 1.06, _i_heat)
		sky.ground_energy_multiplier *= lerpf(1.0, 0.52, _i_rain)

	# —— 雾 ——
	var fog: Color = e.fog_light_color.lerp(s_fog, mix)
	fog = fog.lerp(RAIN_FOG, _i_rain * 0.85)
	fog = fog.lerp(HEAT_FOG, _i_heat * 0.60)
	e.fog_light_color = fog
	e.fog_density *= lerpf(1.0, 2.70, _i_rain) * lerpf(1.0, 1.30, _i_heat)

	# —— 环境光 ——
	var amb: Color = e.ambient_light_color.lerp(s_amb, mix)
	amb = amb.lerp(Color(0.60, 0.64, 0.72), _i_rain * 0.80)
	amb = amb.lerp(Color(1.00, 0.86, 0.66), _i_heat * 0.70)
	e.ambient_light_color = amb
	e.ambient_light_energy *= s_mult * lerpf(1.0, 0.66, _i_rain) * lerpf(1.0, 1.18, _i_heat)
	e.adjustment_enabled = true
	e.adjustment_saturation *= lerpf(1.0, 0.72, _i_rain) * lerpf(1.0, 1.06, _i_heat)

	# —— 太阳 ——
	if sun != null:
		var sc: Color = sun.light_color
		sc = sc.lerp(RAIN_HOR, _i_rain * 0.55)
		sc = sc.lerp(Color(1.00, 0.88, 0.66), _i_heat * 0.50)
		sun.light_color = sc
		sun.light_energy *= lerpf(1.0, 0.40, _i_rain) * lerpf(1.0, 1.04, _i_heat)


# ============================== 雨 ==============================
func _ensure_rain() -> void:
	if rain_root != null and is_instance_valid(rain_root):
		return
	if not is_inside_tree():
		return

	rain_root = Node3D.new()
	rain_root.name = "RainArea"
	rain_root.top_level = true
	add_child(rain_root)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.62, 0.018)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.74, 0.82, 0.94, 0.50)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_receive_shadows = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = RAIN_COUNT

	_rx.resize(RAIN_COUNT)
	_ry.resize(RAIN_COUNT)
	_rz.resize(RAIN_COUNT)
	_rs.resize(RAIN_COUNT)
	for i in RAIN_COUNT:
		var x := rng.randf_range(-RAIN_RADIUS, RAIN_RADIUS)
		var z := rng.randf_range(-RAIN_RADIUS, RAIN_RADIUS)
		var y := rng.randf_range(0.0, RAIN_SPAN)
		_rx[i] = x
		_ry[i] = y
		_rz[i] = z
		_rs[i] = rng.randf_range(21.0, 29.0)
		mm.set_instance_transform(i, Transform3D(_rain_basis, Vector3(x, y, z)))

	rain_mmi = MultiMeshInstance3D.new()
	rain_mmi.name = "RainStreaks"
	rain_mmi.multimesh = mm
	rain_mmi.material_override = mat
	rain_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain_root.add_child(rain_mmi)
	rain_root.visible = false


func _update_rain(dt: float) -> void:
	if rain_root == null or not is_instance_valid(rain_root):
		return
	if rain_mmi == null or rain_mmi.multimesh == null:
		return

	var on := (weather == "rain" or _i_rain > 0.02) and is_inside_tree()
	rain_root.visible = on
	if not on:
		return

	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_3d()
		if cam != null:
			rain_root.global_position = cam.global_position + Vector3(0.0, -RAIN_SPAN * 0.30, 0.0)

	var mm := rain_mmi.multimesh
	for i in RAIN_COUNT:
		var y: float = _ry[i] - _rs[i] * dt
		while y < 0.0:
			y += RAIN_SPAN
		_ry[i] = y
		mm.set_instance_transform(i, Transform3D(_rain_basis, Vector3(_rx[i], y, _rz[i])))


# ============================== 工具 ==============================
func _dn_num(key: String, fallback: float) -> float:
	if daynight == null or not is_instance_valid(daynight):
		return fallback
	var v = daynight.get(key)
	if v == null:
		return fallback
	if v is int or v is float:
		return float(v)
	return fallback


func _day_frac_per_sec() -> float:
	var day_len: float = _dn_num("day_length", 420.0)
	if day_len < 0.0001:
		day_len = 420.0
	var spd: float = _dn_num("speed_scale", 1.0)
	return maxf(spd, 0.0) / day_len


func _read_color(d: Dictionary, key: String, fb: Color) -> Color:
	var v = d.get(key, null)
	if v is Color:
		return v
	if v is Array or v is PackedFloat32Array or v is PackedFloat64Array:
		var arr: Array = []
		if v is Array:
			arr = v
		else:
			arr = Array(v)
		if arr.size() >= 3:
			var r: float = float(arr[0])
			var g: float = float(arr[1])
			var b: float = float(arr[2])
			var a: float = fb.a
			if arr.size() >= 4:
				a = float(arr[3])
			return Color(r, g, b, a)
	return fb
