extends Node
## 全局事件总线 + 模块注册表（autoload: GameBus）
## 各子系统通过信号解耦，避免互相直接引用；存档系统通过注册表统一序列化

signal res_harvested(kind: String, amount: int, pos: Vector3)
signal item_built(kind: String, pos: Vector3)
signal player_step(speed: float, pos: Vector3)
signal tool_used(tool_name: String, pos: Vector3)
signal tool_changed(tool_name: String)
signal season_changed(season: int, season_name: String, growth_mult: float)
signal new_day(day: int, season: int)
signal weather_changed(weather: String)
signal game_saved(slot: int)
signal game_loaded(slot: int)
signal toast(msg: String)

var modules := {}


func register_module(id: String, node: Node) -> void:
	modules[id] = node


func unregister_module(id: String) -> void:
	modules.erase(id)


func serialize_all() -> Dictionary:
	var d := {}
	for k in modules.keys():
		var m = modules[k]
		if is_instance_valid(m) and m.has_method("serialize"):
			d[k] = m.serialize()
	return d


func deserialize_all(d: Dictionary) -> void:
	for k in d.keys():
		if not modules.has(k):
			continue
		var m = modules[k]
		if is_instance_valid(m) and m.has_method("deserialize"):
			m.deserialize(d[k])
