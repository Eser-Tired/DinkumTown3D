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

# —— 触控输入通道 ——
# 移动端由 TouchControls 写入，player / main 作为额外输入源消费。
# 桌面端恒为初始值，因此所有读它的逻辑在桌面行为不变。
signal touch_action(action: String)   ## 触控按钮触发的逻辑动作名，与键盘动作一一对应
signal touch_layout_changed(w: float, h: float, k: float)   ## 视口尺寸变化，HUD 需同步避让

var touch_enabled := false      ## TouchControls 是否已挂载
var touch_move := Vector2.ZERO  ## 虚拟摇杆向量，y 为负表示向前
var touch_look := Vector2.ZERO  ## 本帧视角位移，由 player 消费后清零
var touch_zoom := 0.0           ## 本帧缩放增量，正值拉远，消费后清零
var touch_run := false          ## 摇杆推满即奔跑
var touch_jump_edge := false    ## 跳跃边沿，由 player 消费后清零

var modules := {}


func request_touch_action(action: String) -> void:
	touch_action.emit(action)


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
