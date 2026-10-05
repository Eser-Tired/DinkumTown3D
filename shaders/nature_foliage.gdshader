shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float alpha_cutoff = 0.3;
uniform float wind_strength = 0.02;
void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 根部不动；世界坐标错开摆动相位，避免整片植被像同一块板。
	float bend = clamp(VERTEX.y, 0.0, 2.0);
	VERTEX.x += sin(TIME * 1.7 + world.x * 0.6 + world.z * 0.4) * wind_strength * bend;
}
void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb * base_color.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
