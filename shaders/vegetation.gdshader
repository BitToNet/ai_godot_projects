// =============================================================================
//  植被 Shader —— 针叶林 / 阔叶林 / 仙人掌 / 枯木 / 岩石 共用
//  · 顶点色给出树干/树冠等固有色
//  · 用实例世界原点的哈希做每棵树的色调扰动（无需 MultiMesh instance color）
//  · 顶点风动：按局部高度加权，树干不动树梢摆动
//  · 支持季节性/夜间整体压暗
// =============================================================================
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float wind_strength = 1.0;
uniform float wind_speed = 1.1;
uniform float sway_height = 7.0;    // 达到最大摆幅的局部高度
uniform float tint_range = 0.22;    // 每实例色调扰动幅度
uniform float night_amount = 0.0;
uniform float fade_start = 0.0;     // 战略视图淡出用（0 = 不淡出）
uniform sampler2D fog_map : filter_linear, repeat_disable;
uniform float fog_enabled = 0.0;
uniform float fog_darkness = 0.62;
uniform float map_size = 1024.0;

varying vec3 w_pos;
varying float v_tint;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz;
	float h = hash21(inst.xz * 0.37);
	v_tint = 1.0 - tint_range * 0.5 + h * tint_range;

	// 风：相位取决于实例位置，幅度取决于局部高度
	float ph = inst.x * 0.11 + inst.z * 0.09;
	float amp = clamp(VERTEX.y, 0.0, sway_height) / max(sway_height, 0.001);
	float s = sin(TIME * wind_speed + ph);
	float s2 = sin(TIME * wind_speed * 1.7 + ph * 1.3);
	VERTEX.x += s * amp * 0.30 * wind_strength;
	VERTEX.z += s2 * amp * 0.18 * wind_strength;

	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = COLOR.rgb * v_tint * (1.0 - 0.55 * night_amount);
	vec2 fuv = clamp(w_pos.xz / map_size, vec2(0.0), vec2(1.0));
	float fog_v = texture(fog_map, fuv).r;
	base *= mix(1.0, 1.0 - fog_darkness * (1.0 - fog_v), fog_enabled);
	ALBEDO = base;
	ROUGHNESS = 0.92;
	SPECULAR = 0.05;
	METALLIC = 0.0;
}
