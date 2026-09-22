extends RefCounted
class_name Weapons
## 近战武器数据层 —— 纯数据 + 静态查询，不持有任何节点
##
## 【设计约定】
## 1. 武器只描述"挥砍时发生什么"，不负责动画和判定，那两件事分别由 player.gd 与
##    main.gd 的 _try_attack() 做。数据与表现分离，改数值不用碰逻辑。
## 2. dmg 为单次命中伤害；cd 为冷却（秒）；reach 为从玩家中心算起的前方命中距离；
##    arc 为半角（弧度）——目标必须落在玩家朝向 ±arc 的扇形内才算命中。
## 3. 工具（锄头/水壶）不在此表内，它们走 farm 通道，避免两套系统互相污染。
##
## 【平衡意图】斧头是"高伤近距"，长矛是"低伤远距"，两者 DPS 接近但手感相反：
## 斧头适合贴脸快速解决，长矛适合边退边戳。袋鼠血量 30，即斧头 2 刀 / 长矛 3 刀。

const LIST := [
	{
		"id": "axe",
		"name": "斧头",
		"dmg": 18,
		"cd": 0.62,
		"reach": 2.6,
		"arc": 0.62,          # ≈35°
		"desc": "高伤害近距劈砍",
	},
	{
		"id": "spear",
		"name": "长矛",
		"dmg": 11,
		"cd": 0.46,
		"reach": 4.0,
		"arc": 0.38,          # ≈22°，更窄但更长
		"desc": "低伤害长距离突刺",
	},
]


static func count() -> int:
	return LIST.size()


static func get_at(i: int) -> Dictionary:
	if i < 0 or i >= LIST.size():
		return {}
	return LIST[i]


## 按 id 查表；找不到返回空字典（调用方自行兜底）
static func find(id: String) -> Dictionary:
	for w in LIST:
		if str(w.get("id", "")) == id:
			return w
	return {}


static func name_of(id: String) -> String:
	var w := find(id)
	return str(w.get("name", id)) if not w.is_empty() else id


## 循环切武器，返回新的索引（dir 为 +1/-1）
static func cycle(idx: int, dir: int) -> int:
	var n := LIST.size()
	if n == 0:
		return 0
	return posmod(idx + dir, n)
