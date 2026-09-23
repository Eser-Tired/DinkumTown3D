extends Node3D
## 澳洲内陆地形：红土丘陵 + 中央水潭(billabong) + 小镇平地
## 全部程序化生成，height_at() 供角色/道具贴地使用

const SIZE := 260.0
const GRID := 130
const HALF := SIZE * 0.5

## —— 地形基准高度 ——
## 【为什么要有这一项，以及为什么它是负数湖的根因】
## 噪声的均值是 0，所以"地形低于水位"的区域天然占全图一半。原实现的水位是 0，
## 于是湖盆以外成片低地全都低于水位——水面要么被裁成硬边，要么一路蔓延到地图边缘。
## 实测：24 个方位里 16 个的岸线半径超出湖盆外缘，正东 50 米处水深还有 3.3 米，
## 根本不存在"岸"。所以必须把地面整体抬到水位之上，湖才是湖。
## 抬升量 6.0 > 噪声最大振幅 4.4，保证湖盆以外处处高于水位，岸线永远闭合。
const BASE_LIFT := 6.0
const AMP_BASE := 3.4      # 低频大起伏（波长约 139 米）
const AMP_DETAIL := 1.0    # 高频碎起伏（波长约 24 米）

const TOWN_CENTER := Vector2(-14.0, -10.0)
const TOWN_R := 30.0
## 小镇平台比周围平原略高一点：排水、视野都好，也不至于变成一座土丘
const TOWN_H := BASE_LIFT + 1.4

const LAKE_C := Vector2(48.0, 22.0)
const LAKE_R := 27.0
const SHORE := 17.0
const WATER_Y := 0.0

## 湖心最深处的参考深度（米），只用来把水深归一化给 shader 上色
const DEEP_REF := 5.6

## —— 河流 ——
## 河道半宽（米）。整条河宽 2*RIVER_W = 14 米。
const RIVER_W := 7.0
## 河岸过渡带宽度：从"水面以下"平滑抬到原地形，形成河谷
const RIVER_BANK := 13.0
## 河床最低点（米）。负值 = 水面以下
const RIVER_BED_Y := -2.6
## 河道边缘的水深。必须 > 0：这是"河流不断流"的底线——
## 河道内任何一点的地面都被 min() 削到这个高度以下，所以一定有水。
const RIVER_EDGE_Y := WATER_Y - 0.30
## 河道路径的折线段数。段数越多河道越顺，但 height_at 每次都要扫一遍，
## 而 height_at 在生成地形时会调用几万次，所以这里要克制。
const RIVER_SEGS := 20

## 地图种子 —— 整张地图由它派生（起伏 / 河流走向 / 植被分布）。
## 【为什么必须存在】存档只需要记住这一个整数，就能在任何时候重建出同一张地图；
## 反过来，同一个种子必须是同一张图，否则读档会回到另一片大陆。
var map_seed := 20260921

## 河道路径（折线顶点，世界 XZ 坐标）
var river_pts: PackedVector2Array = PackedVector2Array()
## 路径的粗包围盒（含河宽余量）。river_dist 先拿它做快速剔除——
## 地图上大部分点离河很远，没必要逐段算距离。
var _river_box := Rect2()

var n_base: FastNoiseLite
var n_detail: FastNoiseLite
var n_tint: FastNoiseLite
var water_mat: ShaderMaterial
var water_mi: MeshInstance3D

# —— 季节染色 ——
var ground_mi: MeshInstance3D
var tintables: Array = []          # 会跟着季节变色的材质（干草地被等）
var season_tint := Color(1.0, 1.0, 1.0)
var season_amt := 0.0


func _ready() -> void:
	_init_noise()
	ground_mi = _build_ground()
	add_child(ground_mi)
	water_mi = _build_water()
	add_child(water_mi)


## 三个噪声层各自用「地图种子 + 一个固定盐值」派生，互不相关又都确定。
## 加盐值是为了避免三层噪声的图案相互叠加出可见的重复纹理。
func _init_noise() -> void:
	n_base = FastNoiseLite.new()
	n_base.seed = map_seed
	n_base.frequency = 0.0072
	n_base.fractal_octaves = 3

	n_detail = FastNoiseLite.new()
	n_detail.seed = map_seed + 5150
	n_detail.frequency = 0.042
	n_detail.fractal_octaves = 2

	n_tint = FastNoiseLite.new()
	n_tint.seed = map_seed + 31415
	n_tint.frequency = 0.02

	_build_river_path()


## 换一张地图。
## 【为什么必须在 add_child 之前调用】它会重算噪声与河道，然后重建地面与水面网格；
## 已经挂进场景树之后再换，场上那些按 height_at 摆好的树、石头、动物不会跟着动。
func set_map_seed(s: int) -> void:
	if s == map_seed and not river_pts.is_empty():
		return
	map_seed = s
	_init_noise()
	if ground_mi != null:
		ground_mi.mesh = _ground_mesh()
	if water_mi != null:
		water_mi.queue_free()
		water_mi = null
		water_mi = _build_water()
		add_child(water_mi)


## 季节系统回调：换季时重算顶点色并刷新可染色材质
func apply_season_tint(tint: Color, amount: float) -> void:
	season_tint = tint
	season_amt = clampf(amount, 0.0, 1.0)
	if ground_mi != null:
		ground_mi.mesh = _ground_mesh()
	for m in tintables:
		if m is StandardMaterial3D:
			m.albedo_color = Color(1.0, 1.0, 1.0).lerp(season_tint, season_amt * 0.65)


## 注册一个随季节变色的材质（main 里给干草地被用）
func register_tintable(m: Material) -> void:
	if m != null and not tintables.has(m):
		tintables.append(m)
		m.set("albedo_color", Color(1.0, 1.0, 1.0).lerp(season_tint, season_amt * 0.65))


# ——————————————— 河道路径 ———————————————
## 生成河道中心线。
## 【设计约束】上游必须从"远离小镇的那半边"进图——河穿过小镇会把镇子切成两半，
## 而游戏里没有桥的机制。所以起点方位以「湖指向小镇的反方向」为中心，只在那附近抖动。
func _build_river_path() -> void:
	# 河道形状单独派生一条随机流，不和噪声种子混用，
	# 这样"改河道"和"改地形起伏"互不牵连，调一个不会把另一个搅乱。
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed * 7919 + 13

	# 起点落在地图的南边缘或东边缘（种子决定哪一边 + 具体位置）。
	# 【为什么不是"从湖向远离小镇的方向射出去"】湖本身偏东南，那个方向离地图边界
	# 只有 80 米出头，河短得像湖的一条尾巴。而南边与东边的边缘同样远离小镇，
	# 又能给出 100 米以上的河道，形状才像一条河。
	var edge := HALF - 6.0
	var start: Vector2
	if rng.randf() < 0.5:
		start = Vector2(rng.randf_range(-44.0, 116.0), edge)   # 南边缘
	else:
		start = Vector2(edge, rng.randf_range(-56.0, 116.0))   # 东边缘

	var to_lake := LAKE_C - start
	var span := to_lake.length()
	var dir := to_lake / span
	var perp := Vector2(-dir.y, dir.x)

	var c1 := start + dir * (span * 0.66) + perp * rng.randf_range(-30.0, 30.0)
	var c2 := start + dir * (span * 0.33) + perp * rng.randf_range(-26.0, 26.0)

	# Catmull-Rom 采样成折线：首尾各加一个镜像虚拟点，让曲线真正穿过两个端点
	var ctrl: Array = [
		start + (start - c1) * 0.5, start, c1, c2, LAKE_C, LAKE_C + (LAKE_C - c2) * 0.5
	]
	river_pts = PackedVector2Array()
	for i in range(RIVER_SEGS + 1):
		var t := float(i) / float(RIVER_SEGS) * float(ctrl.size() - 3)
		var seg := clampi(int(floor(t)), 0, ctrl.size() - 4)
		river_pts.append(_catmull(ctrl[seg], ctrl[seg + 1], ctrl[seg + 2], ctrl[seg + 3],
			t - float(seg)))

	# 粗包围盒（含河宽与河岸余量）。river_dist 靠它一步剔除地图上大部分点。
	var mn := river_pts[0]
	var mx := river_pts[0]
	for p in river_pts:
		mn.x = minf(mn.x, p.x)
		mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x)
		mx.y = maxf(mx.y, p.y)
	var pad := RIVER_W + RIVER_BANK + 2.0
	_river_box = Rect2(mn - Vector2(pad, pad), (mx - mn) + Vector2(pad * 2.0, pad * 2.0))


func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## 点到河道中心线的最短距离（米）。超出影响范围时返回一个很大的值。
func river_dist(x: float, z: float) -> float:
	if river_pts.size() < 2:
		return 1e9
	var p := Vector2(x, z)
	# 粗剔除放在最前面：地图上大部分点离河很远，逐段算距离是纯浪费，
	# 而 height_at 在生成地形时会被调用几万次，这里的常数很值钱。
	if not _river_box.has_point(p):
		return 1e9
	var best := 1e9
	for i in river_pts.size() - 1:
		var d := _point_seg_dist(p, river_pts[i], river_pts[i + 1])
		if d < best:
			best = d
	return best


func _point_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-6:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


## 任意点的地面高度 —— 地形、玩家、道具、动物共用
func height_at(x: float, z: float) -> float:
	var h := n_base.get_noise_2d(x, z) * AMP_BASE
	h += n_detail.get_noise_2d(x, z) * AMP_DETAIL
	# 整体抬升：见 BASE_LIFT 的说明。不抬的话全图一半在地面以下，湖没有岸。
	h += BASE_LIFT

	# 湖盆：越靠近湖心越深越平
	var d := Vector2(x, z).distance_to(LAKE_C)
	if d < LAKE_R + SHORE:
		var t := clampf((d - LAKE_R) / SHORE, 0.0, 1.0)
		# 【为什么是 t*t 而不是 t】岸线形状由这个过渡带决定：噪声压制得越早放开，
		# 岸线就越碎（水-陆-水的小碎块）。t*t 让噪声紧贴湖心的部分压得更狠，
		# 到 t=1 仍然精确归 1，保证 d = LAKE_R+SHORE 处与湖外公式无缝衔接。
		h *= lerpf(0.10, 1.0, t * t)
		h += lerpf(-5.6, 0.0, t * t)

	# 河流：把河道削到水面以下，再向两侧平滑抬回原地形，形成河谷。
	# 【为什么是 min 而不是"减去一个下凹量"】减法会被高地形顶回去——河一经过
	# 高地就断成两截。min 强制河道任何一点都低于水位，这就是"河流覆盖稳定"的
	# 全部来源：不管随机地形长成什么样，河永远有水。
	var rd := river_dist(x, z)
	if rd < RIVER_W + RIVER_BANK:
		if rd < RIVER_W:
			var k := rd / RIVER_W
			h = minf(h, lerpf(RIVER_BED_Y, RIVER_EDGE_Y, k * k))
		else:
			var t3 := (rd - RIVER_W) / RIVER_BANK
			h = lerpf(minf(h, RIVER_EDGE_Y), h, t3 * t3)

	# 小镇：中心压平，方便摆建筑
	var td := Vector2(x, z).distance_to(TOWN_CENTER)
	if td < TOWN_R + 12.0:
		var t2 := clampf((td - TOWN_R) / 12.0, 0.0, 1.0)
		var k := (1.0 - t2) * (1.0 - t2)
		h = lerpf(h, TOWN_H, k)

	return h


# ——————————————— 水体查询（玩法与渲染共用同一套真值）———————————————
## 水面高度。玩家游泳时要拿它做漂浮基准，所以对外暴露一个方法，
## 免得别处直接读常量名，将来改成"分级水位"时只需要改这里。
func water_level() -> float:
	return WATER_Y


## 该点是否属于水体范围（湖 + 河）
func in_water(x: float, z: float) -> bool:
	if Vector2(x, z).distance_to(LAKE_C) < LAKE_R + SHORE:
		return true
	return river_dist(x, z) < RIVER_W + RIVER_BANK


## 水深（米）。0 表示这里没有水。湖与河流共用这一个入口。
## 【为什么要有这个函数】玩家游泳/潜水、建造避水、撒点避水全都需要它，
## 各自去写 `height_at < 0.9` 这种魔法阈值迟早会各说各话。
## 【为什么不先用 in_water 短路】height_at 只有在水体范围内才会低于水位，
## 结果天然正确；而 in_water 自己也要扫一遍河道，前置判断等于白算两遍。
func water_depth_at(x: float, z: float) -> float:
	return maxf(0.0, WATER_Y - height_at(x, z))


## 这一格（地形网格单元）是否需要生成水面。
## 判定用四角最低点：只要有一角低于水位就盖水。
## 【为什么不是"四角都低于水位"】水面是平的、地形是斜的，岸边的格子必然与地形交叉；
## 取最低角保证不会漏掉任何一处洼地（漏掉就是"那里明明该有水却没有"）。
## 多盖出去的部分会被地形本身挡住（地形不透明），代价为零。
func _quad_wet(i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= GRID or j >= GRID:
		return false
	var step := SIZE / float(GRID)
	var x0 := -HALF + i * step
	var z0 := -HALF + j * step
	var lo := minf(minf(height_at(x0, z0), height_at(x0 + step, z0)),
		minf(height_at(x0, z0 + step), height_at(x0 + step, z0 + step)))
	return lo < WATER_Y


## 该点是否被水面覆盖 —— 与 _build_water() 走同一套判定，供自检使用
func water_surface_at(x: float, z: float) -> bool:
	var step := SIZE / float(GRID)
	return _quad_wet(floori((x + HALF) / step), floori((z + HALF) / step))


func _slope_at(x: float, z: float) -> float:
	var d := 1.6
	var hx := height_at(x + d, z) - height_at(x - d, z)
	var hz := height_at(x, z + d) - height_at(x, z - d)
	return Vector2(hx, hz).length() / (2.0 * d)


## 季节染色包装：水线以下保持原色，陆地按季节色调混合
func _color_at(x: float, z: float, h: float) -> Color:
	var c := _raw_color_at(x, z, h)
	if h < WATER_Y + 0.75:
		return c
	return c.lerp(c * season_tint, season_amt)


func _raw_color_at(x: float, z: float, h: float) -> Color:
	var slope := _slope_at(x, z)
	var tint := n_tint.get_noise_2d(x, z) * 0.5 + 0.5

	# 水下淤泥 / 湿沙
	if h < WATER_Y - 0.9:
		return Color(0.28, 0.30, 0.22)
	if h < WATER_Y + 0.75:
		return Color(0.80, 0.72, 0.52).lerp(Color(0.86, 0.79, 0.58), tint)

	# 陡坡露岩。阈值跟着 BASE_LIFT 上移，并按幅度压缩等比调小：
	# 地形整体抬了 6 米、振幅压到原来的一半左右，沿用旧阈值会让整张图都算"高地"。
	if slope > 0.34 and h > BASE_LIFT + 1.6:
		return Color(0.55, 0.29, 0.19).lerp(Color(0.66, 0.35, 0.23), tint)

	# 干草原
	var grass := Color(0.28, 0.35, 0.14).lerp(Color(0.44, 0.42, 0.19), tint)
	# 高地红土（澳洲内陆标志）
	var dirt := Color(0.62, 0.32, 0.18).lerp(Color(0.75, 0.42, 0.25), tint)
	var c := grass.lerp(dirt, clampf((h - (BASE_LIFT + 1.0)) / 3.5, 0.0, 0.85))
	return c


func _build_ground() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _ground_mesh()
	mi.material_override = _ground_material()
	mi.name = "Ground"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


func _ground_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.97
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.uv1_scale = Vector3(1, 1, 1)
	return mat


func _ground_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var step := SIZE / float(GRID)
	for j in range(GRID + 1):
		for i in range(GRID + 1):
			var x := -HALF + i * step
			var z := -HALF + j * step
			var y := height_at(x, z)
			st.set_color(_color_at(x, z, y))
			st.set_uv(Vector2(float(i) / GRID, float(j) / GRID))
			st.add_vertex(Vector3(x, y, z))

	for j in range(GRID):
		for i in range(GRID):
			var a := j * (GRID + 1) + i
			var b := a + 1
			var c := a + (GRID + 1)
			var d := c + 1
			# Godot 正面 = 屏幕顺时针，从上往下看必须按此顺序
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)

	st.generate_normals()
	return st.commit()


## 水面网格 —— 形状完全由地形决定（地形低于水位的地方才有水）
##
## 【为什么不能再是一块圆形平面】原来是一块半径 LAKE_R+SHORE+4 的圆盘，
## 和地形毫无关系：地形高的地方把水面切成硬直的边，地形低的地方水面悬空在地表之上。
## 俯视就是"一块一块断续的水"。改成按地形网格逐格判断之后，
## 岸线 = 水位等值线，天然连续，也不会再有悬空的水面。
##
## 【为什么步长必须和地形一致】水面如果比地形网格细，两者在格子内部对不上，
## 岸线会出现水面插进土里 / 地表露出一条缝。用同一套网格 + 同一套 _quad_wet 判定，
## 水陆交界精确吻合。
func _build_water() -> MeshInstance3D:
	var step := SIZE / float(GRID)
	# 扫描范围 = 湖的包围盒 ∪ 河流的包围盒。河可能横跨半张地图，所以这个并集
	# 会明显变大；但 _quad_wet 的判定本身很便宜（一次粗剔除 + 必要时的几段距离），
	# 多扫几千个格子的代价远低于漏掉一段河。
	var reach := LAKE_R + SHORE + step * 1.5
	var lo := LAKE_C - Vector2(reach, reach)
	var hi := LAKE_C + Vector2(reach, reach)
	if not river_pts.is_empty():
		lo.x = minf(lo.x, _river_box.position.x)
		lo.y = minf(lo.y, _river_box.position.y)
		hi.x = maxf(hi.x, _river_box.end.x)
		hi.y = maxf(hi.y, _river_box.end.y)
	var i0 := maxi(0, floori((lo.x + HALF) / step))
	var i1 := mini(GRID, ceili((hi.x + HALF) / step))
	var j0 := maxi(0, floori((lo.y + HALF) / step))
	var j1 := mini(GRID, ceili((hi.y + HALF) / step))
	var nw := i1 - i0 + 1
	var nh := j1 - j0 + 1

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nh:
		for i in nw:
			var x := -HALF + (i0 + i) * step
			var z := -HALF + (j0 + j) * step
			# 顶点色 r 通道 = 水深归一化，shader 靠它决定颜色与透明度
			# （岸边清浅透明、湖心深蓝不透明）
			var depth := maxf(0.0, WATER_Y - height_at(x, z))
			st.set_color(Color(clampf(depth / DEEP_REF, 0.0, 1.0), 0.0, 0.0, 1.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(x - LAKE_C.x, 0.0, z - LAKE_C.y))

	for j in nh - 1:
		for i in nw - 1:
			if not _quad_wet(i0 + i, j0 + j):
				continue
			# 与地形网格相同的三角形划分，保证交界处一一对应
			var a := j * nw + i
			var b := a + 1
			var c := a + nw
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)

	water_mat = ShaderMaterial.new()
	water_mat.shader = _water_shader()

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = water_mat
	mi.name = "Billabong"
	mi.position = Vector3(LAKE_C.x, WATER_Y, LAKE_C.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _water_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform float u_time = 0.0;
uniform vec3 u_deep = vec3(0.05, 0.26, 0.36);
uniform vec3 u_shallow = vec3(0.47, 0.79, 0.71);
uniform float u_wave = 0.045;

varying float v_depth;   // CPU 烘的水深（0 = 岸边，1 = 湖心）
varying vec3 v_world;

void vertex() {
	v_depth = COLOR.r;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(VERTEX.x * 0.55 + u_time * 1.35) * u_wave
	          + cos(VERTEX.z * 0.47 + u_time * 1.05) * u_wave;
}

void fragment() {
	float d = v_depth;
	// 用世界坐标算波纹，不能用 VERTEX：片元阶段的 VERTEX 是视空间坐标
	float ripple = sin(v_world.x * 0.9 + v_world.z * 0.8 + u_time * 2.1) * 0.5 + 0.5;
	float crest = smoothstep(0.78, 1.0, ripple);
	vec3 col = mix(u_shallow, u_deep, clamp(d * 1.5, 0.0, 1.0));
	col += crest * 0.14;
	ALBEDO = col;
	// 浅水透（看得见水底的泥沙），深水几乎不透
	ALPHA = mix(0.40, 0.95, clamp(d * 1.8, 0.0, 1.0));
	ROUGHNESS = mix(0.06, 0.20, d);
	SPECULAR = 0.85;
	METALLIC = 0.0;
	NORMAL = normalize(vec3(
		sin(v_world.x * 0.8 + u_time * 1.7) * 0.12, 1.0,
		cos(v_world.z * 0.75 + u_time * 1.3) * 0.12));
}
"""
	return sh


func _process(_dt: float) -> void:
	if water_mat:
		water_mat.set_shader_parameter("u_time", Time.get_ticks_msec() * 0.001)
