// =============================================================================
//  定居点建筑 Shader
//  顶点色约定（MeshBuilder 写入）：
//    rgb   = 固有色
//    a = 0.0  普通建材
//    a = 1.0  窗户（夜间自发光，暖色）
//    a = 0.5  旗帜（顶点风动）
//  材质统一为一个，因此每座定居点只有 1 个 draw call。
// =============================================================================
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float night_glow = 0.0;   // 由 DayNightCycle 写入：夜晚为 1
uniform float flag_wind = 1.0;
uniform sampler2D fog_map : filter_linear, repeat_disable;
uniform float fog_enabled = 0.0;
uniform float fog_darkness = 0.62;
uniform float map_size = 1024.0;

varying vec3 w_pos;

void vertex() {
	// 旗帜飘动
	if (COLOR.a > 0.25 && COLOR.a < 0.75) {
		float ph = MODEL_MATRIX[3].x * 0.35 + MODEL_MATRIX[3].z * 0.27;
		// 注意：amplitude 必须是「与位置无关」的常量，否则旗面会被撕成细条
		float s = sin(TIME * 3.2 + ph + VERTEX.z * 2.5 + VERTEX.y * 2.0);
		float q = sin(TIME * 2.1 + ph + VERTEX.y * 1.4 + VERTEX.z * 1.8);
		VERTEX.x += s * 0.20 * flag_wind;
		VERTEX.z += q * 0.10 * flag_wind;
	}
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float glow = step(0.75, COLOR.a);
	vec3 base = COLOR.rgb * (1.0 - 0.50 * night_glow);
	vec2 fuv = clamp(w_pos.xz / map_size, vec2(0.0), vec2(1.0));
	float fog_v = texture(fog_map, fuv).r;
	base *= mix(1.0, 1.0 - fog_darkness * (1.0 - fog_v), fog_enabled);
	ALBEDO = base;
	ROUGHNESS = mix(0.90, 0.65, glow);
	SPECULAR = 0.12;
	METALLIC = 0.0;
	// 夜间窗户发光（暖色），并在强光周围叠加一点自发光溢色
	EMISSION = COLOR.rgb * glow * night_glow * 3.2;
}
