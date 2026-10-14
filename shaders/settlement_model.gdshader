// =============================================================================
//  定居点真模型 Shader（第③批-2）
//
//  为什么要自己写一个，而不是直接用 GLB 自带的 StandardMaterial3D：
//  GLB 一进来就会带自己的材质（KayKit 图集 + 默认 PBR），而本工程的建筑材质不是
//  「一个颜色」那么简单 —— settlement.gdshader 同时承担三件事：
//    · 昼夜：DayNightCycle 往材质里写 night_glow，夜里整体压暗一档；
//    · 迷雾：FogOfWar 往材质里塞 fog_map / fog_enabled，未探索区压暗 38%；
//    · 顶点 alpha 语义：窗户自发光 / 旗帜风动（真模型没有顶点色，本轮记为债务）。
//  直接用 GLB 材质 = 同时丢掉前两件 —— 表现是「迷雾里亮着一个村子」「夜里村子
//  比周围地形亮」。这不是审美问题，是接线问题，所以必须换掉材质，
//  并把 fog / night 两条语义**逐字对齐** settlement.gdshader（口径不一致会更难查）。
//
//  势力染色：图集自带蓝系配色，4 种建筑共用同一张图集，所以「一个材质喂所有建筑」
//  成立（前提由 tools/asset_check.gd 用贴图哈希钉住）。势力区分在标签 + 小旗之外，
//  这里再补一层很轻的乘色（tint_strength 0.22）：乘色只改色相不改明暗，
//  调 0.0 就等于完全不染 —— 这是个可以放心拧的旋钮，不是结构。
// =============================================================================
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_strength = 0.22;
uniform float night_glow = 0.0;   // 由 DayNightCycle 写入：夜晚为 1
uniform sampler2D fog_map : filter_linear, repeat_disable;
uniform float fog_enabled = 0.0;
uniform float fog_darkness = 0.62;
uniform float map_size = 1024.0;

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	// 势力染色：向势力色轻度偏移（0.22），保留图集本身的明暗与材质感
	base *= mix(vec3(1.0), tint.rgb, tint_strength);
	// 昼夜：与程序化建筑同一条曲线，否则夜里村庄会像灯塔
	base *= 1.0 - 0.50 * night_glow;
	// 迷雾：与 terrain / vegetation / settlement 完全同一套语义
	vec2 fuv = clamp(w_pos.xz / map_size, vec2(0.0), vec2(1.0));
	float fog_v = texture(fog_map, fuv).r;
	base *= mix(1.0, 1.0 - fog_darkness * (1.0 - fog_v), fog_enabled);
	ALBEDO = base;
	ROUGHNESS = 0.88;
	SPECULAR = 0.12;
	METALLIC = 0.0;
}