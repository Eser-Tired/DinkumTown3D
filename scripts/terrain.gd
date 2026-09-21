extends Node3D
## 澳洲内陆地形：红土丘陵 + 中央水潭(billabong) + 小镇平地
## 全部程序化生成，height_at() 供角色/道具贴地使用

const SIZE := 260.0
const GRID := 130
const HALF := SIZE * 0.5

const TOWN_CENTER := Vector2(-14.0, -10.0)
const TOWN_R := 30.0
const TOWN_H := 2.6

const LAKE_C := Vector2(48.0, 22.0)
const LAKE_R := 27.0
const SHORE := 17.0
const WATER_Y := 0.0

var n_base: FastNoiseLite
var n_detail: FastNoiseLite
var n_tint: FastNoiseLite
var water_mat: ShaderMaterial


func _ready() -> void:
	n_base = FastNoiseLite.new()
	n_base.seed = 20260921
	n_base.frequency = 0.0072
	n_base.fractal_octaves = 3

	n_detail = FastNoiseLite.new()
	n_detail.seed = 5150
	n_detail.frequency = 0.042
	n_detail.fractal_octaves = 2

	n_tint = FastNoiseLite.new()
	n_tint.seed = 31415
	n_tint.frequency = 0.02

	add_child(_build_ground())
	add_child(_build_water())


## 任意点的地面高度 —— 地形、玩家、道具、动物共用
func height_at(x: float, z: float) -> float:
	var h := n_base.get_noise_2d(x, z) * 7.2
	h += n_detail.get_noise_2d(x, z) * 1.25

	# 湖盆：越靠近湖心越深越平
	var d := Vector2(x, z).distance_to(LAKE_C)
	if d < LAKE_R + SHORE:
		var t := clampf((d - LAKE_R) / SHORE, 0.0, 1.0)
		h *= lerpf(0.10, 1.0, t)
		h += lerpf(-5.6, 0.0, t * t)

	# 小镇：中心压平，方便摆建筑
	var td := Vector2(x, z).distance_to(TOWN_CENTER)
	if td < TOWN_R + 12.0:
		var t2 := clampf((td - TOWN_R) / 12.0, 0.0, 1.0)
		var k := (1.0 - t2) * (1.0 - t2)
		h = lerpf(h, TOWN_H, k)

	return h


func _slope_at(x: float, z: float) -> float:
	var d := 1.6
	var hx := height_at(x + d, z) - height_at(x - d, z)
	var hz := height_at(x, z + d) - height_at(x, z - d)
	return Vector2(hx, hz).length() / (2.0 * d)


func _color_at(x: float, z: float, h: float) -> Color:
	var slope := _slope_at(x, z)
	var tint := n_tint.get_noise_2d(x, z) * 0.5 + 0.5

	# 水下淤泥 / 湿沙
	if h < WATER_Y - 0.9:
		return Color(0.28, 0.30, 0.22)
	if h < WATER_Y + 0.75:
		return Color(0.80, 0.72, 0.52).lerp(Color(0.86, 0.79, 0.58), tint)

	# 陡坡露岩
	if slope > 0.52 and h > 3.0:
		return Color(0.55, 0.29, 0.19).lerp(Color(0.66, 0.35, 0.23), tint)

	# 干草原
	var grass := Color(0.28, 0.35, 0.14).lerp(Color(0.44, 0.42, 0.19), tint)
	# 高地红土（澳洲内陆标志）
	var dirt := Color(0.62, 0.32, 0.18).lerp(Color(0.75, 0.42, 0.25), tint)
	var c := grass.lerp(dirt, clampf((h - 3.5) / 5.0, 0.0, 0.85))
	return c


func _build_ground() -> MeshInstance3D:
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

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.97
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.uv1_scale = Vector3(1, 1, 1)

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.name = "Ground"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


func _build_water() -> MeshInstance3D:
	# Godot 4.7 已移除 CircleMesh：用平面网格 + 片元着色器裁成圆形
	var span := (LAKE_R + SHORE + 4.0) * 2.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(span, span)
	plane.subdivide_width = 40
	plane.subdivide_depth = 40

	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform float u_time = 0.0;
uniform vec3 u_deep = vec3(0.09, 0.32, 0.38);
uniform vec3 u_shallow = vec3(0.42, 0.74, 0.68);
uniform float u_wave = 0.055;

void vertex() {
	// PlaneMesh 局部平面为 XZ，高度方向是局部 Y
	VERTEX.y += sin(VERTEX.x * 0.55 + u_time * 1.35) * u_wave
	          + cos(VERTEX.z * 0.47 + u_time * 1.05) * u_wave;
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	if (r > 1.0) { discard; }
	float ripple = sin((UV.x + UV.y) * 46.0 + u_time * 2.1) * 0.5 + 0.5;
	float crest = smoothstep(0.75, 1.0, ripple);
	vec3 col = mix(u_deep, u_shallow, clamp(r * 1.25 - 0.15, 0.0, 1.0));
	col += crest * 0.16;
	ALBEDO = col;
	ALPHA = mix(0.94, 0.72, clamp(r * 1.1, 0.0, 1.0));
	ROUGHNESS = mix(0.08, 0.22, r);
	SPECULAR = 0.85;
	METALLIC = 0.0;
	NORMAL = normalize(vec3(
		sin(UV.x * 30.0 + u_time * 1.7) * 0.12, 1.0,
		cos(UV.y * 27.0 + u_time * 1.3) * 0.12));
}
"""
	water_mat = ShaderMaterial.new()
	water_mat.shader = sh

	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = water_mat
	mi.name = "Billabong"
	mi.position = Vector3(LAKE_C.x, WATER_Y, LAKE_C.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _process(_dt: float) -> void:
	if water_mat:
		water_mat.set_shader_parameter("u_time", Time.get_ticks_msec() * 0.001)
