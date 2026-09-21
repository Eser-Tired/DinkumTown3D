extends Node
class_name AudioDirector
## 程序化音效系统 —— 全部音色在运行时合成 PCM，不依赖任何外部音频文件。
## 用法：var a := AudioDirector.new(); a.setup(self, player)
## 可选：a.register_ambient_source("campfire", pos) / ("water", pos)

const SR := 22050          # 环境层采样率（循环音体积较大，用低采样率）
const SR_HI := 44100       # 短音效采样率
const VOICE_COUNT := 14    # 一次性音效的播放器池大小

var world: Node
var player: Node3D
var dn: Node = null        # DayNight 节点（可能不存在，全部判空）
var _bus: Node = null      # GameBus autoload
var rng := RandomNumberGenerator.new()

var _bank: Dictionary = {}      # String -> AudioStreamWAV（一次性音效）
var _loops: Dictionary = {}     # String -> AudioStreamWAV（循环音效）
var _steps: Array = []          # AudioStreamWAV（脚步变体）
var _birds: Array = []          # AudioStreamWAV（鸟鸣变体）
var _voices: Array = []         # AudioStreamPlayer（一次性音效池）
var _voice_i := 0
var _amb: Dictionary = {}       # String -> AudioStreamPlayer（常驻 2D 环境层）
var _amb3d: Array = []          # AudioStreamPlayer3D（篝火 / 水声）

var _day_f := 1.0               # 白昼系数 0..1
var _night_f := 0.0             # 夜晚系数 0..1
var _rain_f := 0.0              # 雨声淡入淡出当前值
var _rain_target := 0.0
var _bird_t := 3.0
var _season_pitch := 1.0
var _fire_count := 0


# ————————————————————————————— 生命周期 —————————————————————————————
func setup(world: Node, player: Node3D) -> void:
	self.world = world
	self.player = player
	name = "AudioDirector"
	rng.seed = 20260921

	if get_parent() != world:
		if get_parent() != null:
			get_parent().remove_child(self)
		world.add_child(self)

	dn = world.get_node_or_null("DayNight")

	_build_bank()
	_build_voices()
	_build_ambient()
	_scan_campfires(world)
	_connect_bus()


## 取得事件总线 autoload（/root/GameBus）。用动态查找而不是全局标识符，
## 这样即便在没有注册 autoload 的上下文（如 --script 工具脚本）里也不会报错。
func _find_bus() -> Node:
	if _bus != null and is_instance_valid(_bus):
		return _bus
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		var tree: SceneTree = ml
		_bus = tree.root.get_node_or_null("GameBus")
	if _bus == null and is_inside_tree():
		_bus = get_node_or_null("/root/GameBus")
	return _bus


func _connect_bus() -> void:
	var bus := _find_bus()
	if bus == null:
		push_warning("[AudioDirector] 未找到 GameBus，跳过事件接线")
		return
	bus.register_module("audio", self)
	bus.connect("res_harvested", Callable(self, "_on_res_harvested"))
	bus.connect("item_built", Callable(self, "_on_item_built"))
	bus.connect("player_step", Callable(self, "_on_player_step"))
	bus.connect("tool_used", Callable(self, "_on_tool_used"))
	bus.connect("toast", Callable(self, "_on_toast"))
	bus.connect("weather_changed", Callable(self, "_on_weather_changed"))
	bus.connect("season_changed", Callable(self, "_on_season_changed"))
	bus.connect("new_day", Callable(self, "_on_new_day"))


func _process(dt: float) -> void:
	_update_day_night(dt)
	_update_birds(dt)


# ————————————————————————————— 公开接口 —————————————————————————————
## 注册一个 3D 环境音源。kind 支持：campfire / fire / water / lake / river
func register_ambient_source(kind: String, pos: Vector3) -> void:
	var k := kind.to_lower()
	var key := ""
	if k == "campfire" or k == "fire":
		key = "fire"
	elif k == "water" or k == "lake" or k == "river":
		key = "water"
	else:
		return
	if key == "fire":
		_fire_count += 1
		if _fire_count > 10:
			return

	var host: Node = world
	if not (world is Node3D):
		host = self
	var p := AudioStreamPlayer3D.new()
	p.name = "Amb3D_" + key
	p.stream = _loop(key)
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = 5.0
	p.max_distance = 40.0
	p.max_db = 3.0
	p.panning_strength = 1.0
	p.volume_db = -6.0 if key == "fire" else -10.0
	p.autoplay = true          # 进树后自动开始播放
	host.add_child(p)
	p.position = pos
	_amb3d.append(p)


## 手动播放某个一次性音效（bank 里的名字），返回是否成功
func play(name_: String, volume_db := 0.0, pitch := 1.0) -> bool:
	if not _bank.has(name_):
		return false
	var st: AudioStreamWAV = _bank[name_]
	var v := _next_voice()
	v.stream = st
	v.volume_db = volume_db
	v.pitch_scale = pitch
	if v.is_inside_tree():
		v.play()
	return true


## 手动切换天气（weather_changed 信号之外也能调用）
func set_weather(weather: String) -> void:
	_rain_target = 1.0 if weather.to_lower() == "rain" else 0.0


## 设置总音量分层：master / sfx / ambient（dB）
func set_layer_volume(layer: String, db: float) -> void:
	if layer == "ambient":
		_ambient_base_db = db
	elif layer == "sfx":
		_sfx_base_db = db


var _sfx_base_db := 0.0
var _ambient_base_db := 0.0


# ————————————————————————————— 事件处理 —————————————————————————————
func _on_res_harvested(kind: String, _amount: int, pos: Vector3) -> void:
	var nm := "wood"
	if kind == "stone":
		nm = "stone"
	elif kind == "fiber":
		nm = "fiber"
	elif kind == "ore":
		nm = "ore"
	var v: AudioStreamWAV = _bank[nm]
	_shot(v, _dist_db(pos) - 1.0, rng.randf_range(0.92, 1.10))


func _on_item_built(_kind: String, pos: Vector3) -> void:
	var v: AudioStreamWAV = _bank["build"]
	_shot(v, _dist_db(pos), rng.randf_range(0.94, 1.08))


func _on_player_step(speed: float, pos: Vector3) -> void:
	if _steps.is_empty():
		return
	var i: int = rng.randi() % _steps.size()
	var v: AudioStreamWAV = _steps[i]
	var s: float = clampf(speed / 6.0, 0.15, 1.0)
	_shot(v, _sfx_base_db - 12.0 + s * 8.0, rng.randf_range(0.90, 1.15))


func _on_tool_used(tool_name: String, pos: Vector3) -> void:
	var v: AudioStreamWAV = _bank["whoosh"]
	var pc := 1.0
	if tool_name == "hoe":
		pc = 0.82
	elif tool_name == "watercan":
		pc = 1.18
	elif tool_name == "pick":
		pc = 1.10
	_shot(v, _dist_db(pos) - 3.0, pc * rng.randf_range(0.95, 1.05))


func _on_toast(_msg: String) -> void:
	var v: AudioStreamWAV = _bank["blip"]
	_shot(v, _sfx_base_db - 12.0, rng.randf_range(0.98, 1.02))


func _on_weather_changed(weather: String) -> void:
	set_weather(weather)


func _on_season_changed(season: int, _season_name: String, _growth_mult: float) -> void:
	# 四季给风声一点点音色与音高差异
	var tbl: Array = [0.94, 1.00, 1.06, 0.90]
	_season_pitch = float(tbl[season % 4])
	var w: AudioStreamPlayer = _amb.get("wind", null)
	if w != null:
		w.pitch_scale = _season_pitch


func _on_new_day(_day: int, _season: int) -> void:
	_bird_t = 0.6   # 清晨鸟鸣


# ————————————————————————————— 播放辅助 —————————————————————————————
func _shot(st: AudioStreamWAV, db: float, pitch: float) -> void:
	var v := _next_voice()
	v.stream = st
	v.volume_db = db
	v.pitch_scale = pitch
	if v.is_inside_tree():
		v.play()


func _next_voice() -> AudioStreamPlayer:
	var v: AudioStreamPlayer = _voices[_voice_i]
	_voice_i = (_voice_i + 1) % _voices.size()
	if v.playing:
		v.stop()
	return v


## 依据事件位置到玩家的距离做一点手动衰减（一次性音效是 2D 的）
func _dist_db(pos: Vector3) -> float:
	if player == null or not is_instance_valid(player):
		return _sfx_base_db
	var d: float = player.global_position.distance_to(pos)
	var f: float = clampf(d / 40.0, 0.0, 1.0)
	return _sfx_base_db - f * 16.0


# ————————————————————————————— 昼夜 / 鸟鸣 —————————————————————————————
func _update_day_night(dt: float) -> void:
	var t := 0.5
	if dn != null and is_instance_valid(dn):
		var tv: Variant = dn.get("time")
		if tv is float or tv is int:
			t = float(tv)
	var elev: float = sin((t - 0.25) * TAU)
	_day_f = clampf(elev * 2.2, 0.0, 1.0)
	_night_f = 1.0 - _day_f

	var k: float = clampf(dt * 0.8, 0.0, 1.0)
	_rain_f = lerpf(_rain_f, _rain_target, k)

	var wind: AudioStreamPlayer = _amb.get("wind", null)
	if wind != null:
		wind.volume_db = _ambient_base_db + lerpf(-11.0, -18.0, _night_f)
	var crick: AudioStreamPlayer = _amb.get("crickets", null)
	if crick != null:
		# 白天彻底静音，入夜后淡入
		crick.volume_db = _ambient_base_db + lerpf(-70.0, -22.0, clampf(_night_f * 1.15, 0.0, 1.0))
	var rain: AudioStreamPlayer = _amb.get("rain", null)
	if rain != null:
		rain.volume_db = _ambient_base_db + lerpf(-70.0, -12.0, _rain_f)


func _update_birds(dt: float) -> void:
	_bird_t -= dt
	if _bird_t > 0.0:
		return
	_bird_t = rng.randf_range(2.0, 6.0)
	if _day_f < 0.32 or _birds.is_empty():
		return
	var i: int = rng.randi() % _birds.size()
	var v: AudioStreamWAV = _birds[i]
	_shot(v, _ambient_base_db - 20.0, rng.randf_range(0.85, 1.25) * _season_pitch)


# ————————————————————————————— 构建播放器 —————————————————————————————
func _build_voices() -> void:
	for i in VOICE_COUNT:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		p.volume_db = 0.0
		add_child(p)
		_voices.append(p)


func _build_ambient() -> void:
	_add_ambient("wind", _loop("wind"), -11.0)
	_add_ambient("crickets", _loop("crickets"), -70.0)
	_add_ambient("rain", _loop("rain"), -70.0)


func _add_ambient(key: String, st: AudioStreamWAV, db: float) -> void:
	var p := AudioStreamPlayer.new()
	p.name = "Amb_" + key
	p.stream = st
	p.volume_db = db
	p.autoplay = true          # 进树后自动开始播放
	add_child(p)
	_amb[key] = p


## 循环音源按需生成并缓存
func _loop(key: String) -> AudioStreamWAV:
	if _loops.has(key):
		var s: AudioStreamWAV = _loops[key]
		return s
	var data := PackedFloat32Array()
	if key == "wind":
		data = _amb_wind()
	elif key == "crickets":
		data = _amb_crickets()
	elif key == "rain":
		data = _amb_rain()
	elif key == "fire":
		data = _amb_fire()
	elif key == "water":
		data = _amb_water()
	var st: AudioStreamWAV = _make_stream(data, SR, true, true)
	_loops[key] = st
	return st


## setup 后自动扫一遍世界，把篝火（带 flicker 子节点的道具）挂上 3D 噼啪声
func _scan_campfires(root: Node) -> void:
	var found: Array = []
	_scan_fire_r(root, found, 0)
	for item in found:
		if _fire_count >= 8:
			break
		var n: Node3D = item
		if is_instance_valid(n):
			var gp: Vector3 = n.global_position if n.is_inside_tree() else n.position
			register_ambient_source("campfire", gp)


func _scan_fire_r(n: Node, out: Array, depth: int) -> void:
	if depth > 4 or out.size() > 12:
		return
	var is_fire := false
	for c in n.get_children():
		var ch: Node = c
		if ch.has_meta("flicker"):
			is_fire = true
			break
	if is_fire:
		out.append(n)
	for c in n.get_children():
		var ch2: Node = c
		_scan_fire_r(ch2, out, depth + 1)


# ————————————————————————————— 音色库 —————————————————————————————
func _build_bank() -> void:
	_bank["wood"] = _syn_wood()
	_bank["stone"] = _syn_stone()
	_bank["fiber"] = _syn_fiber()
	_bank["ore"] = _syn_ore()
	_bank["build"] = _syn_build()
	_bank["whoosh"] = _syn_whoosh()
	_bank["blip"] = _syn_blip()

	_steps.clear()
	for i in 4:
		_steps.append(_syn_step())
	_birds.clear()
	for i in 4:
		_birds.append(_syn_bird())


# ——————————————————— PCM 工具 ———————————————————
func _to_pcm(samples: PackedFloat32Array) -> PackedByteArray:
	var n: int = samples.size()
	var out := PackedByteArray()
	out.resize(n * 2)
	var i := 0
	while i < n:
		var s: float = clampf(samples[i], -1.0, 1.0)
		out.encode_s16(i * 2, int(roundf(s * 32767.0)))
		i += 1
	return out


func _make_stream(samples: PackedFloat32Array, mix_rate: int, stereo: bool, loop: bool) -> AudioStreamWAV:
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = mix_rate
	st.stereo = stereo
	st.data = _to_pcm(samples)
	if loop:
		var frames: int = samples.size()
		if stereo:
			frames = samples.size() / 2
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = frames
	else:
		st.loop_mode = AudioStreamWAV.LOOP_DISABLED
		st.loop_begin = 0
		st.loop_end = 0
	return st


## 一阶低通（coef 越小截止越低）
func _lp(buf: PackedFloat32Array, coef: float) -> PackedFloat32Array:
	var y := 0.0
	var i := 0
	var n: int = buf.size()
	while i < n:
		y += coef * (buf[i] - y)
		buf[i] = y
		i += 1
	return buf


## 归一化到指定峰值
func _norm(buf: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0
	var i := 0
	var n: int = buf.size()
	while i < n:
		var a: float = absf(buf[i])
		if a > m:
			m = a
		i += 1
	if m > 0.0001:
		var g: float = peak / m
		i = 0
		while i < n:
			buf[i] *= g
			i += 1
	return buf


## 交叉淡化尾部到头部，让循环点无缝
func _loopify(raw: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n: int = raw.size() - fade
	var out := PackedFloat32Array()
	out.resize(n)
	var i := 0
	while i < n:
		out[i] = raw[i]
		i += 1
	i = 0
	while i < fade:
		var t: float = float(i) / float(fade)
		out[i] = raw[i] * t + raw[n + i] * (1.0 - t)
		i += 1
	return out


func _stereo(l: PackedFloat32Array, r: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = mini(l.size(), r.size())
	var out := PackedFloat32Array()
	out.resize(n * 2)
	var i := 0
	while i < n:
		out[i * 2] = l[i]
		out[i * 2 + 1] = r[i]
		i += 1
	return out


# ——————————————————— 一次性音效合成 ———————————————————
## 脚步：滤波噪声爆 + 低频 thud
func _syn_step() -> AudioStreamWAV:
	var sr := SR_HI
	var n: int = int(float(sr) * 0.11)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var ph := 0.0
	var i := 0
	while i < n:
		var t: float = float(i) / float(sr)
		var w: float = rng.randf_range(-1.0, 1.0)
		lp += 0.22 * (w - lp)
		var grit: float = w - lp                      # 高通留下的“沙砾”
		ph += TAU * (78.0 + 26.0 * exp(-t * 30.0)) / float(sr)
		var thud: float = sin(ph) * exp(-t * 30.0) * 0.75
		var env: float = exp(-t * 22.0)
		buf[i] = (grit * 0.55 + thud) * env
		i += 1
	return _make_stream(_norm(buf, 0.80), sr, false, false)


## 采集木头：低沉 thud + 短噪声
func _syn_wood() -> AudioStreamWAV:
	var sr := SR
	var n: int = int(float(sr) * 0.42)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var i := 0
	while i < n:
		var t: float = float(i) / float(sr)
		var f: float = 62.0 + 118.0 * exp(-t * 15.0)
		ph += TAU * f / float(sr)
		var body: float = sin(ph) * exp(-t * 8.5) * 0.95
		var click: float = rng.randf_range(-1.0, 1.0) * exp(-t * 110.0) * 0.55
		var rasp: float = rng.randf_range(-1.0, 1.0) * exp(-t * 26.0) * 0.16
		buf[i] = body + click + rasp
		i += 1
	return _make_stream(_norm(buf, 0.90), sr, false, false)


## 采集石头：清脆高频 click
func _syn_stone() -> AudioStreamWAV:
	var sr := SR_HI
	var n: int = int(float(sr) * 0.13)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var i := 0
	while i < n:
		var t: float = float(i) / float(sr)
		var w: float = rng.randf_range(-1.0, 1.0)
		lp += 0.55 * (w - lp)
		var hp: float = w - lp
		var f1: float = 2350.0 * exp(-t * 4.0)
		var tone: float = sin(TAU * f1 * t) * exp(-t * 52.0) * 0.75
		var tone2: float = sin(TAU * 3560.0 * t) * exp(-t * 78.0) * 0.35
		buf[i] = tone + tone2 + hp * exp(-t * 90.0) * 0.85
		i += 1
	return _make_stream(_norm(buf, 0.85), sr, false, false)


## 采集纤维：沙沙声（噪声包络）
func _syn_fiber() -> AudioStreamWAV:
	var sr := SR
	var n: int = int(float(sr) * 0.36)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var i := 0
	while i < n:
		var t: float = float(i) / float(sr)
		var w: float = rng.randf_range(-1.0, 1.0)
		lp += 0.62 * (w - lp)
		lp2 += 0.05 * (lp - lp2)
		var band: float = lp - lp2                    # 带通：低频 + 去掉极低频
		var env: float = 0.0
		if t < 0.045:
			env = t / 0.045
		else:
			env = exp(-(t - 0.045) * 8.5)
		var ripple: float = 0.72 + 0.28 * sin(TAU * 62.0 * t + 0.7)
		buf[i] = band * env * ripple * 2.6
		i += 1
	return _make_stream(_norm(buf, 0.80), sr, false, false)


## 采集矿石：两个正弦叠加的金属感 + 快衰减
func _syn_ore() -> AudioStreamWAV:
	var sr := SR_HI
	var n: int = int(float(sr) * 0.55)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var i := 0
	while i < n:
		var t: float = float(i) / float(sr)
		var a: float = sin(TAU * 1183.0 * t) * exp(-t * 9.0)
		var b: float = sin(TAU * 1791.0 * t) * exp(-t * 6.5) * 0.80
		var c: float = sin(TAU * 2637.0 * t) * exp(-t * 14.0) * 0.42
		var strike: float = rng.randf_range(-1.0, 1.0) * exp(-t * 160.0) * 0.7
		var shimmer: float = sin(TAU * 1183.0 * t) * sin(TAU * 7.0 * t) * exp(-t * 5.0) * 0.25
		buf[i] = (a + b + c + shimmer) * 0.55 + strike
		i += 1
	return _make_stream(_norm(buf, 0.85), sr, false, false)


## 建造放置：木质 knock（两下）
func _syn_build() -> AudioStreamWAV:
	var sr := SR
	var n: int = int(float(sr) * 0.34)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var ph2 := 0.0
	var i := 0
	while i < n:
		var t: float = float(i) / float(sr)
		var t2: float = t - 0.085
		var v := 0.0
		if t2 > 0.0:
			ph2 += TAU * (78.0 + 92.0 * exp(-t2 * 26.0)) / float(sr)
			v += sin(ph2) * exp(-t2 * 21.0) * 0.55
		ph += TAU * (96.0 + 150.0 * exp(-t * 22.0)) / float(sr)
		v += sin(ph) * exp(-t * 17.0) * 0.90
		var knock: float = rng.randf_range(-1.0, 1.0) * exp(-t * 150.0) * 0.35
		if t2 > 0.0:
			knock += rng.randf_range(-1.0, 1.0) * exp(-t2 * 170.0) * 0.20
		buf[i] = v + knock
		i += 1
	return _make_stream(_norm(buf, 0.88), sr, false, false)


## 使用工具：短促 whoosh（扫频带通噪声）
func _syn_whoosh() -> AudioStreamWAV:
	var sr := SR
	var dur := 0.30
	var n: int = int(float(sr) * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var low := 0.0
	var band := 0.0
	var i := 0
	while i < n:
		var u: float = float(i) / float(n)
		var t: float = float(i) / float(sr)
		var fc: float = 0.05 + 0.26 * sin(PI * u)
		var x: float = rng.randf_range(-1.0, 1.0)
		var high: float = x - low - 1.35 * band
		band += fc * high
		low += fc * band
		var env: float = sin(PI * u)
		env = env * env
		buf[i] = band * env * 3.0
		i += 1
	return _make_stream(_norm(buf, 0.75), sr, false, false)


## UI 提示音：轻快的两音符 blip
func _syn_blip() -> AudioStreamWAV:
	var sr := SR_HI
	var n: int = int(float(sr) * 0.26)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var i := 0
	while i < n:
		var t: float = float(i) / float(sr)
		var v := 0.0
		if t < 0.11:
			var e1: float = minf(t / 0.006, 1.0) * exp(-t * 12.0)
			v += sin(TAU * 880.0 * t) * e1 * 0.6
		var t2: float = t - 0.115
		if t2 > 0.0:
			var e2: float = minf(t2 / 0.006, 1.0) * exp(-t2 * 9.0)
			v += sin(TAU * 1318.5 * t2) * e2 * 0.6
			v += sin(TAU * 2637.0 * t2) * e2 * 0.12
		buf[i] = v
		i += 1
	return _make_stream(_norm(buf, 0.55), sr, false, false)


## 鸟鸣：频率扫描的啁啾（2~4 声）
func _syn_bird() -> AudioStreamWAV:
	var sr := SR_HI
	var chirps: int = 2 + rng.randi() % 3
	var dur := 0.0
	var specs: Array = []
	for i in chirps:
		var f0: float = rng.randf_range(1900.0, 3200.0)
		var ln: float = rng.randf_range(0.07, 0.13)
		var gap: float = rng.randf_range(0.03, 0.09)
		specs.append({"f0": f0, "f1": f0 * rng.randf_range(1.25, 1.75), "len": ln, "gap": gap})
		dur += ln + gap
	var n: int = int(float(sr) * (dur + 0.05))
	var buf := PackedFloat32Array()
	buf.resize(n)
	var t0 := 0.0
	for s in specs:
		var d: Dictionary = s
		var f0: float = float(d["f0"])
		var f1: float = float(d["f1"])
		var ln: float = float(d["len"])
		var gap: float = float(d["gap"])
		var start: int = int(t0 * float(sr))
		var count: int = int(ln * float(sr))
		var ph := 0.0
		var jitter: float = rng.randf_range(0.85, 1.15)
		for j in count:
			var u: float = float(j) / float(count)
			var f: float = lerpf(f0, f1, sin(PI * u * 0.5)) * jitter
			f += sin(TAU * 34.0 * u * ln) * 90.0     # 轻微颤音
			ph += TAU * f / float(sr)
			var env: float = sin(PI * u)
			env = env * env
			var idx: int = start + j
			if idx < n:
				buf[idx] += sin(ph) * env * 0.8
		t0 += ln + gap
	return _make_stream(_norm(buf, 0.62), sr, false, false)


# ——————————————————— 循环环境层合成 ———————————————————
## 风声：低频调制滤波白噪声（立体声，6 秒无缝循环）
func _amb_wind() -> PackedFloat32Array:
	var dur := 6.0
	var n: int = int(SR * dur)
	var fade: int = int(SR * 0.5)
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(n + fade)
	r.resize(n + fade)
	var lp_l := 0.0
	var lp_r := 0.0
	var md_l := 0.0
	var md_r := 0.0
	var i := 0
	while i < n + fade:
		var t: float = float(i) / float(SR)
		var g: float = 0.55 + 0.30 * sin(TAU * (1.0 / dur) * t) + 0.18 * sin(TAU * (2.0 / dur) * t + 1.1) + 0.10 * sin(TAU * (5.0 / dur) * t + 2.3)
		var wl: float = rng.randf_range(-1.0, 1.0)
		var wr: float = rng.randf_range(-1.0, 1.0)
		lp_l += 0.018 * (wl - lp_l)
		lp_r += 0.018 * (wr - lp_r)
		md_l += 0.150 * (wl - md_l)
		md_r += 0.150 * (wr - md_r)
		l[i] = (lp_l * 3.4 + md_l * 0.50) * g
		r[i] = (lp_r * 3.4 + md_r * 0.50) * g
		i += 1
	return _norm(_stereo(_loopify(l, fade), _loopify(r, fade)), 0.72)


## 虫鸣：夜晚高频颤音（2 秒循环）
func _amb_crickets() -> PackedFloat32Array:
	var dur := 2.0
	var n: int = int(SR * dur)
	var fade: int = int(SR * 0.08)
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(n + fade)
	r.resize(n + fade)
	var i := 0
	while i < n + fade:
		var t: float = float(i) / float(SR)
		var tr1: float = maxf(0.0, sin(TAU * 11.0 * t))
		tr1 = tr1 * tr1 * tr1
		var tr2: float = maxf(0.0, sin(TAU * 17.0 * t + 1.7))
		tr2 = tr2 * tr2 * tr2
		var c1: float = sin(TAU * 4600.0 * t) * tr1 * 0.60
		var c2: float = sin(TAU * 3700.0 * t + 0.9) * tr2 * 0.45
		var c3: float = sin(TAU * 5200.0 * t + 2.4) * tr1 * 0.18
		var hiss: float = rng.randf_range(-1.0, 1.0) * 0.035
		l[i] = c1 + c2 * 0.75 + c3 + hiss
		r[i] = c1 * 0.75 + c2 + c3 + hiss
		i += 1
	return _norm(_stereo(_loopify(l, fade), _loopify(r, fade)), 0.65)


## 雨声：持续噪声层 + 随机雨滴（3 秒循环）
func _amb_rain() -> PackedFloat32Array:
	var dur := 3.0
	var n: int = int(SR * dur)
	var fade: int = int(SR * 0.25)
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(n + fade)
	r.resize(n + fade)
	var lp_l := 0.0
	var lp_r := 0.0
	var rm_l := 0.0
	var rm_r := 0.0
	var ph := 0.0
	var pop_t := 1.0
	var pop_f := 1400.0
	var pop_l := 0.0
	var pop_r := 0.0
	var i := 0
	while i < n + fade:
		var t: float = float(i) / float(SR)
		var g: float = 0.85 + 0.15 * sin(TAU * (1.0 / dur) * t)
		var wl: float = rng.randf_range(-1.0, 1.0)
		var wr: float = rng.randf_range(-1.0, 1.0)
		lp_l += 0.45 * (wl - lp_l)
		lp_r += 0.45 * (wr - lp_r)
		rm_l += 0.05 * (wl - rm_l)
		rm_r += 0.05 * (wr - rm_r)
		var hiss_l: float = wl - lp_l
		var hiss_r: float = wr - lp_r

		if rng.randf() < 0.0014:
			pop_t = 0.0
			pop_f = rng.randf_range(900.0, 2300.0)
			ph = 0.0
			if rng.randf() < 0.5:
				pop_l = 1.0
				pop_r = 0.30
			else:
				pop_l = 0.30
				pop_r = 1.0
		var pop := 0.0
		if pop_t < 0.05:
			ph += TAU * pop_f / float(SR)
			pop = sin(ph) * exp(-pop_t * 150.0) * 0.35
		pop_t += 1.0 / float(SR)

		l[i] = (hiss_l * 1.15 + rm_l * 0.9) * g + pop * pop_l
		r[i] = (hiss_r * 1.15 + rm_r * 0.9) * g + pop * pop_r
		i += 1
	return _norm(_stereo(_loopify(l, fade), _loopify(r, fade)), 0.70)


## 篝火：低频轰鸣 + 随机噼啪（2.6 秒循环）
func _amb_fire() -> PackedFloat32Array:
	var dur := 2.6
	var n: int = int(SR * dur)
	var fade: int = int(SR * 0.20)
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(n + fade)
	r.resize(n + fade)
	var rm_l := 0.0
	var rm_r := 0.0
	var crack_t := 1.0
	var crack_a := 0.0
	var crack_l := 1.0
	var crack_r := 1.0
	var i := 0
	while i < n + fade:
		var t: float = float(i) / float(SR)
		var breath: float = 0.80 + 0.20 * sin(TAU * (1.0 / dur) * t + 0.6)
		var wl: float = rng.randf_range(-1.0, 1.0)
		var wr: float = rng.randf_range(-1.0, 1.0)
		rm_l += 0.030 * (wl - rm_l)
		rm_r += 0.030 * (wr - rm_r)

		if rng.randf() < 0.0022:
			crack_t = 0.0
			crack_a = rng.randf_range(0.35, 1.0)
			crack_l = rng.randf_range(0.4, 1.0)
			crack_r = rng.randf_range(0.4, 1.0)
		var crack := 0.0
		if crack_t < 0.045:
			crack = rng.randf_range(-1.0, 1.0) * exp(-crack_t * 190.0) * crack_a
		crack_t += 1.0 / float(SR)

		l[i] = rm_l * 2.6 * breath + crack * crack_l * 0.9
		r[i] = rm_r * 2.6 * breath + crack * crack_r * 0.9
		i += 1
	return _norm(_stereo(_loopify(l, fade), _loopify(r, fade)), 0.68)


## 水声：缓慢起伏的拍岸滤波噪声（4 秒循环）
func _amb_water() -> PackedFloat32Array:
	var dur := 4.0
	var n: int = int(SR * dur)
	var fade: int = int(SR * 0.35)
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(n + fade)
	r.resize(n + fade)
	var lo_l := 0.0
	var bd_l := 0.0
	var lo_r := 0.0
	var bd_r := 0.0
	var i := 0
	while i < n + fade:
		var t: float = float(i) / float(SR)
		var swell: float = 0.62 + 0.38 * sin(TAU * (1.0 / dur) * t - 1.2)
		var fc: float = 0.09 + 0.07 * sin(TAU * (2.0 / dur) * t)
		var wl: float = rng.randf_range(-1.0, 1.0)
		var wr: float = rng.randf_range(-1.0, 1.0)
		var hl: float = wl - lo_l - 1.15 * bd_l
		bd_l += fc * hl
		lo_l += fc * bd_l
		var hr: float = wr - lo_r - 1.15 * bd_r
		bd_r += fc * hr
		lo_r += fc * bd_r
		l[i] = bd_l * 2.2 * swell
		r[i] = bd_r * 2.2 * swell
		i += 1
	return _norm(_stereo(_loopify(l, fade), _loopify(r, fade)), 0.66)
