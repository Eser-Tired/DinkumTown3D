shader_type spatial;

uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float water_level = 0.0;
varying vec3 world_pos;
varying float slope;

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
}

void fragment() {
	vec2 p = world_pos.xz;
	float patches = noise(p * 0.32);
	float grit = noise(p * 12.0);
	float flecks = smoothstep(0.76, 0.91, grit);
	vec3 base = COLOR.rgb;
	base = mix(base, vec3(0.52, 0.31, 0.18), smoothstep(0.50, 0.85, patches) * 0.25);
	base = mix(base, vec3(0.47, 0.43, 0.36), clamp(slope * 2.0, 0.0, 0.55));
	base *= 0.91 + grit * 0.14;
	base += vec3(0.035, 0.024, 0.015) * flecks;
	float shore = 1.0 - smoothstep(water_level - 0.1, water_level + 0.8, world_pos.y);
	float damp = max(shore * 0.8, wetness);
	ALBEDO = base * (1.0 - damp * 0.24);
	ROUGHNESS = mix(0.97, 0.48, damp);
	SPECULAR = mix(0.2, 0.5, damp);
}
