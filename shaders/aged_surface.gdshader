shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.54, 0.38, 0.25, 1.0);
uniform int surface_kind = 0;
uniform int grain_axis = 1;
uniform float base_roughness = 0.9;
uniform float base_metallic = 0.0;
uniform sampler2D detail_map : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_map : repeat_enable, filter_linear_mipmap_anisotropic;
varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 view_x;
varying vec3 view_y;
varying vec3 view_z;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	// 顶点阶段保存逆转置法线基，非均匀缩放后也能正确把细节法线送到视空间。
	mat3 basis = mat3(VIEW_MATRIX) * MODEL_NORMAL_MATRIX;
	view_x = basis[0]; view_y = basis[1]; view_z = basis[2];
}

vec3 project_map(sampler2D image, vec3 p, vec3 weights) {
	return texture(image, p.zy).rgb * weights.x
		+ texture(image, p.xz).rgb * weights.y
		+ texture(image, p.xy).rgb * weights.z;
}

void fragment() {
	vec3 p = local_pos * 1.4;
	vec3 n = normalize(local_normal);
	// 将木材最长边变换为 Y 轴；顶面和侧面才会沿同一个构件方向排列木纹。
	if (surface_kind == 0 && grain_axis == 0) { p = p.yxz; n = n.yxz; }
	if (surface_kind == 0 && grain_axis == 2) { p = p.xzy; n = n.xzy; }
	vec3 weights = pow(abs(n), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.0001);
	vec3 detail = project_map(detail_map, p, weights);
	vec3 orm = project_map(orm_map, p, weights);
	vec3 nx = texture(normal_map, p.zy).rgb * 2.0 - 1.0;
	vec3 ny = texture(normal_map, p.xz).rgb * 2.0 - 1.0;
	vec3 nz = texture(normal_map, p.xy).rgb * 2.0 - 1.0;
	// OpenGL 法线的绿通道按 UV 切线约定编码，直接投到本地坐标时须反转 V 方向。
	nx.y = -nx.y; ny.y = -ny.y; nz.y = -nz.y;
	vec3 perturbation = vec3(0.0, nx.y, nx.x) * weights.x
		+ vec3(ny.x, 0.0, ny.y) * weights.y + vec3(nz.x, nz.y, 0.0) * weights.z;
	vec3 final_normal = normalize(n + perturbation * (surface_kind == 1 ? 0.55 : 0.42));
	if (surface_kind == 0) {
		// 端面使用年轮，纵向木纹不能穿过截面；按米定义尺度，不随盒子尺寸拉伸。
		float rings = sin(length(p.xz) * 55.0 + sin(p.x * 7.0) * 0.5);
		float end_grain = 0.80 + rings * 0.08;
		ALBEDO = base_color.rgb * mix(detail.r, end_grain, weights.y);
		ROUGHNESS = clamp(base_roughness * orm.g, 0.55, 1.0);
		METALLIC = base_metallic;
		if (grain_axis == 0) { final_normal = final_normal.yxz; }
		if (grain_axis == 2) { final_normal = final_normal.xzy; }
	} else {
		vec3 paint = base_color.rgb * detail.b;
		vec3 steel = vec3(0.42, 0.45, 0.47) * (0.85 + detail.b * 0.15);
		vec3 rust = mix(vec3(0.07, 0.018, 0.004), vec3(0.22, 0.065, 0.018), detail.b);
		ALBEDO = mix(mix(paint, steel, detail.r), rust, detail.g);
		// 旧铁皮露出的金属仍有细划痕，不能按抛光钢的低粗糙度反射成亮蓝斑。
		float substrate_roughness = mix(clamp(base_roughness * orm.g, 0.30, 0.65), 0.48, orm.b);
		ROUGHNESS = mix(substrate_roughness, 0.92, detail.g);
		METALLIC = mix(orm.b, 0.0, detail.g);
	}
	AO = orm.r;
	NORMAL = normalize(view_x * final_normal.x + view_y * final_normal.y + view_z * final_normal.z);
}
