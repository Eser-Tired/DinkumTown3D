extends Node
class_name SaveSystem
## 存档 / 读档系统（GameBus 的消费者）
##
## 保存时调用 GameBus.serialize_all() 收集各模块数据，
## 读取时调用 GameBus.deserialize_all(rest) 分发回去。
##
## 【重要约定】各模块 register_module() 时使用的 id 必须等于存档 JSON 里的顶层 key
## （"main" / "season" / "farm" / "audio"），否则读档时该模块数据会被整块丢弃且不报错。
## 本系统自身【不】注册进 GameBus.modules，避免自引用递归。
##
## 存档文件：user://saves/slot_0.save / slot_1.save / slot_2.save
## 顶层结构：{ "__meta": {version, saved_at, day, season_name}, "main": {...}, ... }

const SLOTS := 3
const VERSION := 1
const SAVE_DIR := "user://saves"

var _world: Node3D = null
var _autosave: bool = true
var _last_info: Dictionary = {}
var _warned: Dictionary = {}


# ——————————————— 初始化 ———————————————
func setup(world: Node3D) -> void:
	_world = world
	_ensure_dir()
	slots_info()  # 预热：让首次打开 HUD 时已能拿到槽位信息


# ——————————————— 路径 / 目录 ———————————————
func save_path(slot: int) -> String:
	return "%s/slot_%d.save" % [SAVE_DIR, slot]


func _valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < SLOTS


func _ensure_dir() -> void:
	var real: String = ProjectSettings.globalize_path(SAVE_DIR)
	var e1: int = DirAccess.make_dir_recursive_absolute(real)
	if e1 == OK or e1 == ERR_ALREADY_EXISTS:
		return
	# 退路：某些版本对 user:// 相对形式处理不同，两种都试
	var e2: int = DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if e2 == OK or e2 == ERR_ALREADY_EXISTS:
		return
	push_warning("[SaveSystem] 无法创建存档目录 %s (err=%d / %d)" % [real, e1, e2])


# ——————————————— 元数据 ———————————————
## 从已注册模块里尽力抓取展示用信息，取不到就用兜底值（模块可能还没落地）
func _build_meta() -> Dictionary:
	var day: int = 1
	var season_name: String = ""
	if GameBus == null:
		return _meta_dict(day, season_name)

	var mods: Dictionary = GameBus.modules
	var found_day: bool = false

	# day 来源 1：main 模块的 dn.day_count
	if mods.has("main"):
		var m: Variant = mods["main"]
		if m is Object and is_instance_valid(m):
			if "dn" in m:
				var dn: Variant = m.dn
				if dn is Object and is_instance_valid(dn):
					if "day_count" in dn:
						day = int(dn.day_count)
						found_day = true

	# day 来源 2：season 模块的 total_day
	if not found_day and mods.has("season"):
		var s: Variant = mods["season"]
		if s is Object and is_instance_valid(s):
			if "total_day" in s:
				day = int(s.total_day)

	# season_name：season 模块（可能尚未实现）
	if mods.has("season"):
		var s2: Variant = mods["season"]
		if s2 is Object and is_instance_valid(s2):
			if "season_name" in s2:
				season_name = str(s2.season_name)

	return _meta_dict(day, season_name)


func _meta_dict(day: int, season_name: String) -> Dictionary:
	return {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"day": day,
		"season_name": season_name,
	}


# ——————————————— 保存 ———————————————
func save_game(slot: int) -> bool:
	if GameBus == null:
		return false
	if not _valid_slot(slot):
		_safe_toast("保存失败 · 槽位越界 %d" % slot)
		return false

	_ensure_dir()

	# 1) 收集
	var raw: Variant = GameBus.serialize_all()
	var data: Dictionary = {}
	if raw is Dictionary:
		data = (raw as Dictionary).duplicate(true)
	else:
		push_warning("[SaveSystem] GameBus.serialize_all() 返回非 Dictionary（%s），本次仅写 __meta" % str(raw))

	# 2) 清洗掉 JSON 无法序列化的类型（其它模块由并行开发，容错优先）
	data = _sanitize(data)

	# 3) 元数据
	var meta: Dictionary = _build_meta()
	data["__meta"] = meta

	# 4) 落盘
	var path: String = save_path(slot)
	var text: String = JSON.stringify(data)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[SaveSystem] 写入失败，无法打开 %s" % path)
		_safe_toast("保存失败")
		return false
	f.store_string(text)
	f.close()

	_last_info = {
		"slot": slot,
		"day": int(meta["day"]),
		"season_name": str(meta["season_name"]),
		"saved_at": str(meta["saved_at"]),
	}

	GameBus.game_saved.emit(slot)
	GameBus.toast.emit("已保存 · 槽位 %d" % slot)
	return true


# ——————————————— 读取 ———————————————
func load_game(slot: int) -> bool:
	if GameBus == null:
		return false
	if not _valid_slot(slot):
		_safe_toast("读取失败 · 槽位越界 %d" % slot)
		return false
	return _do_load(slot)


func _do_load(slot: int) -> bool:
	var path: String = save_path(slot)
	if not FileAccess.file_exists(path):
		return false

	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[SaveSystem] 读取失败，无法打开 %s" % path)
		_safe_toast("读取失败")
		return false
	var text: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_warning("[SaveSystem] 存档解析失败：%s" % path)
		_safe_toast("读取失败 · 存档损坏")
		return false
	var data: Dictionary = parsed

	var meta_v: Variant = data.get("__meta", {})
	var version: int = 0
	if meta_v is Dictionary:
		version = int((meta_v as Dictionary).get("version", 0))
	if version != VERSION:
		_safe_toast("存档版本不兼容")
		return false

	var rest: Dictionary = data.duplicate(true)
	rest.erase("__meta")
	GameBus.deserialize_all(rest)

	if meta_v is Dictionary:
		var md: Dictionary = meta_v as Dictionary
		_last_info = {
			"slot": slot,
			"day": int(md.get("day", 1)),
			"season_name": str(md.get("season_name", "")),
			"saved_at": str(md.get("saved_at", "")),
		}

	GameBus.game_loaded.emit(slot)
	GameBus.toast.emit("已读取 · 槽位 %d" % slot)
	return true


# ——————————————— 槽位管理 ———————————————
func has_save(slot: int) -> bool:
	if not _valid_slot(slot):
		return false
	return FileAccess.file_exists(save_path(slot))


func delete_save(slot: int) -> void:
	if not _valid_slot(slot):
		return
	var path: String = save_path(slot)
	if not FileAccess.file_exists(path):
		return
	var real: String = ProjectSettings.globalize_path(path)
	var err: int = DirAccess.remove_absolute(real)
	if err != OK:
		# 退路：用 DirAccess 相对形式再试一次
		var d: DirAccess = DirAccess.open(SAVE_DIR)
		if d != null:
			d.remove("slot_%d.save" % slot)
	if FileAccess.file_exists(path):
		push_warning("[SaveSystem] 删除失败：%s" % path)
	if int(_last_info.get("slot", -1)) == slot:
		_last_info = {}


func slot_text(slot: int) -> String:
	var label: String = "槽位%d" % (slot + 1)
	if not has_save(slot):
		return "%s · 空" % label

	var m: Dictionary = _read_meta(slot)
	var day: int = int(m.get("day", 1))
	var season_name: String = str(m.get("season_name", ""))
	var stamp: String = _short_time(str(m.get("saved_at", "")))

	var s: String = "%s · 第%d天" % [label, day]
	if season_name != "":
		s += " · " + season_name
	if stamp != "":
		s += " · " + stamp
	return s


func slots_info() -> Array:
	var out: Array = []
	for i in range(SLOTS):
		out.append(slot_text(i))
	return out


# ——————————————— 内部工具 ———————————————
func _read_meta(slot: int) -> Dictionary:
	var path: String = save_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return {}
	var m: Variant = (parsed as Dictionary).get("__meta", {})
	if not (m is Dictionary):
		return {}
	return m as Dictionary


## "2026-09-21T20:10:00" -> "09-21 20:10"
func _short_time(saved_at: String) -> String:
	if saved_at.length() < 16:
		return saved_at
	return saved_at.substr(5, 5) + " " + saved_at.substr(11, 5)


func _safe_toast(msg: String) -> void:
	if GameBus == null:
		return
	GameBus.toast.emit(msg)


## 递归清洗：JSON 原生类型原样保留，其余转成字符串或置空（并只警告一次）
func _sanitize(v: Variant) -> Variant:
	var t: int = typeof(v)
	match t:
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return v
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var out: Dictionary = {}
			for k in d.keys():
				var kk: Variant = k
				if typeof(kk) != TYPE_STRING and typeof(kk) != TYPE_INT and typeof(kk) != TYPE_FLOAT:
					_warn(kk, "字典键")
					kk = str(kk)
				out[kk] = _sanitize(d[k])
			return out
		TYPE_ARRAY:
			var a: Array = v
			var out2: Array = []
			for it in a:
				out2.append(_sanitize(it))
			return out2
		TYPE_OBJECT:
			# Node / Resource 等：无法序列化，跳过
			_warn(v, "Object")
			return null
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			_warn(v, "Callable/Signal/RID")
			return null
		_:
			# Vector2/3/4、Color、Transform、Basis、NodePath 等：降级为字符串
			_warn(v, "非 JSON 原生类型")
			return str(v)


func _warn(v: Variant, what: String) -> void:
	var key: String = "%s:%s" % [what, str(typeof(v))]
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("[SaveSystem] 存档数据含%s（type=%d），已降级处理：%s" % [what, typeof(v), str(v)])


# ——————————————— 兼容别名（旧命名，转发到新 API） ———————————————
## 注意：类内任何地方都不要写 load(...)，那会被解析成引擎内置全局 load()
func save(slot: int) -> bool:
	return save_game(slot)


func load(slot: int) -> bool:
	return _do_load(slot)


func delete(slot: int) -> void:
	delete_save(slot)


## 返回有存档的槽位摘要数组：[{slot, day, season_name, saved_at}, ...]
func list_slots() -> Array:
	var out: Array = []
	for i in range(SLOTS):
		if not has_save(i):
			continue
		var m: Dictionary = _read_meta(i)
		out.append({
			"slot": i,
			"day": int(m.get("day", 1)),
			"season_name": str(m.get("season_name", "")),
			"saved_at": str(m.get("saved_at", "")),
		})
	return out


func autosave_enabled(on: bool) -> void:
	_autosave = on


func get_last_save_info() -> Dictionary:
	return _last_info.duplicate(true)
