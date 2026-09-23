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

# —— 跨场景握手 ——
# 主界面在主场景加载【之前】写入，main.gd 在 _ready 末尾读取并清零。
# 取值：-2 = 新游戏（跳过读档）；-1 = 未指定（等同新游戏）；0..SLOTS-1 = 读取对应槽位。
var pending_load_slot := -1

# —— 触控输入通道 ——
# 移动端由 TouchControls 写入，player / main 作为额外输入源消费。
# 桌面端恒为初始值，因此所有读它的逻辑在桌面行为不变。
signal touch_action(action: String)   ## 触控按钮触发的逻辑动作名，与键盘动作一一对应
signal touch_layout_changed(w: float, h: float, k: float)   ## 视口尺寸变化，HUD 需同步避让
signal touch_tap(pos: Vector2)        ## 屏幕轻点（位移小于阈值），main 侧就近判定采集 / 攻击
signal touch_build_drag(rel: Vector2) ## 建造模式下的单指拖动位移，main 侧换算成预览前后移动
signal hotbar_changed(slots: Array, sel: int)   ## 物品栏内容或选中项变化，TouchControls 据此刷新

var touch_enabled := false      ## TouchControls 是否已挂载
var touch_move := Vector2.ZERO  ## 虚拟摇杆向量，y 为负表示向前
var touch_look := Vector2.ZERO  ## 本帧视角位移，由 player 消费后清零
var touch_zoom := 0.0           ## 本帧缩放增量，正值拉远，消费后清零
var touch_run := false          ## 摇杆推满即奔跑
var touch_jump_edge := false    ## 跳跃边沿，由 player 消费后清零
var touch_dive := false         ## 触控「潜」键的按住状态（不是边沿：要一直按着才往下）
var build_mode := false         ## 建造模式镜像，由 main 同步；触控层据此决定拖动语义
var ui_blocking := false        ## 有模态 UI（背包等）打开，触控层应停止处理世界输入

var modules := {}


func request_touch_action(action: String) -> void:
	touch_action.emit(action)


## main 侧下发物品栏内容：slots 为字典数组，sel 为选中下标
func sync_hotbar(slots: Array, sel: int) -> void:
	hotbar_changed.emit(slots, sel)


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
