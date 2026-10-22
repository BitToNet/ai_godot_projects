// =============================================================================
//  settlement_model.gdshader —— NPR 真模型建筑（GLB 图集）
//
//  为什么仍然自己写材质（而不是用 GLB 自带 PBR）：昼夜 / 迷雾 / 势力染色三条接线
//  都在这里（旧版注释已详述），换回 StandardMaterial3D 就是同时丢掉这三件。
//
//  NPR 改造：
//   · 图集颜色先**色阶化**（posterize，默认 5 档），把写实贴图的连续明暗压成色块 ——
//     这是"拒绝写实油贴图"最省事、又不丢图集信息的一步；
//   · 3 阶阶梯光（gradient_map），建筑与地形吃到同一套硬光影；
//   · 描边由 MaterialFactory 挂 next_pass（0.16 m），线稿把建筑从背景里"剪"出来。
//  材质 uniform 契约（tools/asset_check.gd 会逐条断言）：
//    albedo_tex / tint / tint_strength / night_glow / map_size / fog_enabled
// =============================================================================
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D gradient_map : filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_strength = 0.22;
uniform float posterize = 5.0;   // 色阶数：5 ≈ 明显的手绘平涂，1 = 原图
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
	// 色阶化：把连续明暗压成 posterize 个台阶（图集本身是手绘风，压完就是平涂）
	float levels = max(posterize, 1.0);
	base = floor(base * levels + 0.5) / levels;
	// 势力染色：向势力色轻度偏移（0.22），保留图集本身的明暗层次
	base *= mix(vec3(1.0), tint.rgb, tint_strength);
	// 昼夜：与程序化建筑同一条曲线，否则夜里村庄会像灯塔
	base *= 1.0 - 0.50 * night_glow;
	// 迷雾：与 terrain / vegetation / settlement 完全同一套语义
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
