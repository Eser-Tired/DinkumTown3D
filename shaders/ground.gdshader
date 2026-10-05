shader_type spatial;

uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float water_level = 0.0;
uniform bool use_asset_ground = false;
uniform sampler2D grass_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_pos;
varying float slope;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	slope = 1.0 - abs((MODEL_NORMAL_MATRIX * NORMAL).y);
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float micro_height(vec2 p, float fade) {
	// 不同旋转与频率打散 value noise 的方格方向；单层噪声求梯度会像一块块地砖。
	vec2 rotated = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
	vec2 coarse = mat2(vec2(0.6, -0.8), vec2(0.8, 0.6)) * p;
	return ((noise(p * 13.0) - 0.5) * 0.0012
		+ (noise(rotated * 29.0 + vec2(5.3, 8.7)) - 0.5) * 0.0008
		+ (noise(coarse * 4.9) - 0.5) * 0.0028) * fade;
}

void fragment() {
	vec2 p = world_pos.xz;
	float patches = noise(p * 0.32);
	// 按屏幕像素覆盖的米数淡出砂粒，远景不能闪成一层白色噪点。
	float detail_fade = 1.0 - smoothstep(0.035, 0.15, length(fwidth(p)));
	float grit = mix(0.5, noise(p * 18.0), detail_fade);
	float pores = noise(p * 3.5);
	float flecks = smoothstep(0.73, 0.87, grit);
	float shore = 1.0 - smoothstep(water_level - 0.1, water_level + 0.8, world_pos.y);
	float grass = smoothstep(0.02, 0.09, COLOR.g - COLOR.r * 0.72) * (1.0 - shore);
	float rock = smoothstep(0.045, 0.16, slope) * (1.0 - shore * 0.7);
	vec3 base = COLOR.rgb;
	// 沿用顶点色的季节与生态区域，细节只连续混合，不另造一套地形分类真值。
	base = mix(base, vec3(0.42, 0.27, 0.14), smoothstep(0.50, 0.80, patches) * (0.16 + grass * 0.14));
	base = mix(base, vec3(0.39, 0.35, 0.29), rock * 0.45);
	base *= 0.83 + grit * 0.22 + pores * 0.08;
	base += vec3(0.026, 0.022, 0.017) * flecks;
	if (use_asset_ground) {
		// 贴图只替换外观，顶点色仍决定季节/坡地/岸边；不修改水域与高度真值。
		vec3 ground_tex = mix(texture(earth_map, p / 4.0).rgb, texture(grass_map, p / 4.0).rgb, grass * (1.0 - rock));
		base = ground_tex * mix(vec3(1.0), COLOR.rgb * 1.8, 0.35);
	}
	float damp = max(shore * 0.8, wetness * (0.55 + patches * 0.45));
	// 积水优先出现在较平的裸土；湿草仍保持较粗糙，不能整张草原变成镜面。
	float puddle = wetness * smoothstep(0.60, 0.80, pores) * (1.0 - grass) * (1.0 - rock);
	ALBEDO = base * (1.0 - damp * 0.28);
	float dry_roughness = clamp(0.88 + grit * 0.12 - rock * 0.10, 0.0, 1.0);
	ROUGHNESS = mix(dry_roughness, mix(0.46, 0.76, grass), damp);
	ROUGHNESS = mix(ROUGHNESS, 0.24, puddle);
	SPECULAR = 0.5;
	// 用世界坐标的固定一厘米差分，不能在低多边形边缘用 dFdx(VERTEX) 求逆：
	// helper 像素跨三角形时行列式不稳定，会沿每条网格边冒出亮线。
	float height = micro_height(p, detail_fade);
	vec3 gradient = vec3((micro_height(p + vec2(0.01, 0.0), detail_fade) - height) / 0.01,
		0.0, (micro_height(p + vec2(0.0, 0.01), detail_fade) - height) / 0.01);
	vec3 original = normalize(world_normal);
	if (use_asset_ground) {
		vec3 tex_normal = texture(grass_normal, p / 4.0).rgb * 2.0 - 1.0;
		gradient += vec3(tex_normal.x, 0.0, tex_normal.y) * grass * 0.18 * detail_fade;
	}
	gradient -= original * dot(gradient, original);
	vec3 bumped = normalize(original - gradient);
	NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);
}
