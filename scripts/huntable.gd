extends Critter
class_name Huntable
## 可狩猎动物基类：在 Critter 的游走/逃跑 AI 之上，叠加血量、受击、死亡、掉落
##
## 【为什么单独一层而不改 Critter】
## Critter 是纯移动 AI，将来可能还有不可猎杀的动物（宠物、剧情 NPC 动物）。
## 把战斗塞进基类会让"不可猎杀"变成要给一堆方法打桩的特例；分成两层则各自干净。
##
## 【对外契约】
## - take_hit(dmg, from_pos, knockback) -> Dictionary  返回 {dead:bool, drop:{kind:amt}}
## - is_dead() -> bool
## - 死亡后本节点不 queue_free，而是播放倒地动画 + 隐藏，然后回 home 重生。
##   这样 main.gd 里的 colliders / 引用不会变成悬空指针。

signal hurt(amount: int, remain: int)
signal died(drop: Dictionary, pos: Vector3)
signal respawned()

## 血量：子类在 _build_model 里可覆盖
var max_hp := 30
var hp := 30

## 受击硬直：这段时间内不移动，只播受击反馈
var stun := 0.0
## 死亡状态与计时
var dead := false
var _dead_t := 0.0
## 重生等待（秒）——玩家清完一片区域后，过一阵动物会回来，避免草原变空
var respawn_delay := 42.0
## 掉落表：{kind: [min, max]}，子类覆盖
var drop_table := {}

## 受击时把模型整体短暂染红（用 modulate 影响所有子 MeshInstance3D）
var _hurt_flash := 0.0

## 命中盒半径（供 main 的射线/近邻判定用，比模型尺寸略宽松）
var hit_radius := 1.0


func _build_model() -> Node3D:
	return Node3D.new()


## 子类在 _build_model 末尾调用一次，设置血量与掉落
func _configure(p_hp: int, p_drop: Dictionary, p_hit_r := 1.0) -> void:
	max_hp = p_hp
	hp = p_hp
	drop_table = p_drop
	hit_radius = p_hit_r


func setup(terr: Node3D, pos2: Vector2, pl: Node3D) -> void:
	super.setup(terr, pos2, pl)
	hp = max_hp


func take_hit(dmg: int, from_pos: Vector3, knockback := 6.0) -> Dictionary:
	if dead:
		return {"dead": false, "drop": {}}

	hp -= dmg
	_hurt_flash = 1.0
	stun = 0.34
	hurt.emit(dmg, maxi(hp, 0))

	# 击退：沿"攻击者→自己"的方向推开，并强制进入逃跑目标
	var away := Vector2(global_position.x - from_pos.x, global_position.z - from_pos.z)
	if away.length() < 0.01:
		away = Vector2(1.0, 0.0)
	away = away.normalized()
	target = Vector2(global_position.x, global_position.z) + away * (knockback + flee_dist)
	timer = 0.0                 # 立刻放弃当前游走目标
	hop_t = 0.0                 # 起跳，让受击有动作反馈

	if hp <= 0:
		_die()
		return {"dead": true, "drop": drop_table}
	return {"dead": false, "drop": {}}


func is_dead() -> bool:
	return dead


func _die() -> void:
	dead = true
	hp = 0
	_dead_t = 0.0
	# 倒地：侧翻 + 下沉一点
	if model != null:
		model.rotation.z = 1.35
		model.position.y = -0.15
	died.emit(drop_table, global_position)


func _process(dt: float) -> void:
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(0.0, _hurt_flash - dt * 3.4)

	if dead:
		_dead_t += dt
		_pose_dead()
		if _dead_t >= respawn_delay:
			_respawn()
		return

	if stun > 0.0:
		stun -= dt
		_pose_hurt()
		return

	super._process(dt)
	# super 每帧会重设 model.position.y（跳跃/呼吸），所以脉冲缩放要在它之后叠加
	_pose_hurt()


func _respawn() -> void:
	dead = false
	_dead_t = 0.0
	hp = max_hp
	stun = 0.0
	_hurt_flash = 0.0
	if model != null:
		model.rotation.z = 0.0
		model.position.y = 0.0
		model.scale = Vector3.ONE
	# 回出生点附近随机一点，避免和玩家原地重叠
	var a := rng.randf() * TAU
	var r := rng.randf_range(0.0, minf(wander_r, 8.0))
	var p := home + Vector2(cos(a), sin(a)) * r
	global_position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
	target = p
	respawned.emit()


## 倒地姿态：侧翻 + 略微下沉
func _pose_dead() -> void:
	if model == null:
		return
	model.rotation.z = 1.35
	model.position.y = -0.15
	model.scale = Vector3.ONE


## 受击脉冲：把整只动物弹一下（放大 + 上抬）。
##
## 【为什么不用染红】MeshInstance3D 没有 modulate（那是 CanvasItem 的属性），
## 而动物材质来自 props.gd 的全局材质缓存、被多个物体共享——直接改 albedo_color
## 会把整个世界同色的东西一起染红。低多边形风格下，"被击退时弹一下"同样清晰，
## 且零副作用。
func _pose_hurt() -> void:
	if model == null:
		return
	var pop := _hurt_flash * 0.16
	model.scale = Vector3.ONE * (1.0 + pop)
	# super._process 已经把跳跃高度写进 position.y，这里只叠加脉冲抬升
	model.position.y += pop * 0.35


## 死亡掉落：把 drop_table 展开成实际数量，返回 [{kind, amount}]
func roll_drops() -> Array:
	var out: Array = []
	for kind in drop_table.keys():
		var rng_pair: Array = drop_table[kind]
		if rng_pair.size() < 2:
			continue
		var lo := int(rng_pair[0])
		var hi := int(rng_pair[1])
		if hi < lo:
			hi = lo
		var amt := rng.randi_range(lo, hi)
		if amt > 0:
			out.append({"kind": str(kind), "amount": amt})
	return out
