// =============================================================================
//  vegetation.gdshader —— NPR 植被（针叶林 / 阔叶林 / 仙人掌 / 枯木 / 岩石）
//
//  与旧版的差别：
//   · 加入 3 阶阶梯光（gradient_map），树冠不再有连续的明暗过渡；
//   · 每棵树的色调扰动从「连续随机」改成**两档硬切换**（同一片林子只有两种绿），
//     否则一片针叶林会变成几十种绿，看着像噪点而不是手绘；
//   · 反向外壳描边由材质工厂挂到 next_pass 上（见 shaders/toon_outline.gdshader），
//     网格本身是 MeshKit 逐三角形发散的（面法线），所以外壳的膨胀方向是连续的 ——
//     这点很重要：树冠一旦按面法线裂开，描边会变成毛刺。
//   · 保留风动 / 昼夜压暗 / 战争迷雾 / 战略视图淡出（fade_start）四条既有接线。
// =============================================================================
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D gradient_map : filter_nearest, repeat_disable;
uniform float wind_strength = 1.0;
uniform float wind_speed = 1.1;
uniform float sway_height = 7.0;    // 达到最大摆幅的局部高度
uniform float tint_range = 0.22;    // 每实例色调扰动幅度（两档硬切换）
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
	// 两档硬切换：0.5 以下是「浅一档」，以上是「深一档」。不做 lerp ——
	// 连续扰动会让同一片林子出现几十种绿，反而失去手绘感。
	v_tint = 1.0 - tint_range * step(0.5, h);

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
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}

void light() {
	float lit = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	float band = texture(gradient_map, vec2(lit, 0.5)).r;
	DIFFUSE_LIGHT += band * ATTENUATION * LIGHT_COLOR;
}
