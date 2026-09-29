// =============================================================================
//  地形 Shader —— 按「高度 + 坡度 + 生物群系 splat 图」自动混合：
//  沙滩 / 草地 / 干草 / 泥土 / 岩石 / 雪 / 土路
//  全部为程序化着色：没有使用任何贴图资源，细节由 GLSL 内的值噪声生成。
//
//  splat_map 通道约定（由 GDScript 在运行时生成 ImageTexture）：
//    R = 道路遮罩       (0..1)
//    G = 沙漠/干旱因子  (0..1)
//    B = 裸岩/碎石因子  (0..1)
//    A = 湿度（草地浓密程度）(0..1)
//
//  height_map：R 通道 = 世界高度（米），用于相邻像素级的细节判断
// =============================================================================
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D splat_map : filter_linear, repeat_disable;
uniform sampler2D fog_map : filter_linear, repeat_disable;
uniform float fog_enabled = 0.0;
uniform float fog_darkness = 0.62;

uniform float map_size = 1024.0;
uniform float sea_level = 0.0;
uniform float snow_line = 118.0;      // 雪线高度（米）
uniform float mountain_line = 88.0;   // 岩石开始占主导的高度
uniform float slope_rock = 0.42;      // 坡度阈值（0 = 平地, 1 = 垂直）
uniform float beach_width = 6.0;      // 沙滩带宽（米）
uniform float detail_strength = 0.55; // 法线细节强度
uniform float night_amount = 0.0;     // 0 = 白天, 1 = 深夜（由昼夜循环写入）

uniform vec3 color_sand : source_color = vec3(0.84, 0.78, 0.58);
uniform vec3 color_grass : source_color = vec3(0.26, 0.38, 0.15);
uniform vec3 color_grass_dry : source_color = vec3(0.55, 0.51, 0.26);
uniform vec3 color_dirt : source_color = vec3(0.38, 0.30, 0.21);
uniform vec3 color_rock : source_color = vec3(0.44, 0.42, 0.40);
uniform vec3 color_rock_dark : source_color = vec3(0.27, 0.26, 0.26);
uniform vec3 color_snow : source_color = vec3(0.94, 0.96, 1.0);
uniform vec3 color_road : source_color = vec3(0.47, 0.38, 0.26);

varying vec3 w_pos;
varying vec3 w_norm;

// ---------- 程序化噪声（无贴图） ----------
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm4(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_norm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = clamp(w_pos.xz / map_size, vec2(0.0), vec2(1.0));
	vec4 sp = texture(splat_map, uv);
	float road = sp.r;
	float desert = sp.g;
	float rocky = sp.b;
	float moist = sp.a;

	vec3 wn = normalize(w_norm);
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	float h = w_pos.y;

	// 远处衰减高频细节：否则 1m 级噪声在远景会变成摩尔纹/噪点
	float cam_dist = distance(CAMERA_POSITION_WORLD, w_pos);
	float lod_fade = 1.0 - smoothstep(170.0, 760.0, cam_dist);

	// 宏观色斑 + 微观颗粒
	float macro = fbm4(w_pos.xz * 0.010);
	float meso = vnoise(w_pos.xz * 0.09);
	float micro = mix(0.55, vnoise(w_pos.xz * 0.85), lod_fade);
	float micro2 = mix(0.5, vnoise(w_pos.xz * 2.7), lod_fade);

	// ---------- 各材质权重 ----------
	// 沙滩：低海拔平坦处 + 沙漠生物群系
	float beach = 1.0 - smoothstep(1.0, beach_width, h - sea_level);
	beach *= 1.0 - smoothstep(0.12, 0.34, slope);
	float w_sand = clamp(desert * 1.2 + beach * 0.9, 0.0, 1.0);

	// 雪：高度 + 宏观噪声扰动，陡壁挂不住雪
	float snow_jitter = (macro - 0.5) * 26.0 + (meso - 0.5) * 8.0;
	float w_snow = smoothstep(snow_line - 16.0, snow_line + 26.0, h + snow_jitter);
	w_snow *= 1.0 - smoothstep(0.52, 0.86, slope);

	// 岩石：坡度主导，高海拔裸岩，以及 splat 的碎石因子
	float w_rock = smoothstep(slope_rock - 0.10, slope_rock + 0.16, slope);
	w_rock = max(w_rock, smoothstep(mountain_line, mountain_line + 48.0, h) * 0.85 * (1.0 - w_snow));
	w_rock = max(w_rock, rocky * 0.6 * (1.0 - w_snow));
	w_rock = clamp(w_rock, 0.0, 1.0);

	// 草地：其余低地，湿度越高越浓绿
	float w_grass = clamp((1.0 - w_snow) * (1.0 - w_rock) * (1.0 - w_sand) * (0.35 + 0.9 * moist), 0.0, 1.0);

	// 泥土：兜底 / 过渡材质，让混合更平滑
	float w_dirt = clamp((1.0 - w_snow) * (1.0 - w_rock) * (1.0 - w_sand) * (1.0 - w_grass) + 0.10, 0.0, 1.0);

	float sum = w_sand + w_snow + w_rock + w_grass + w_dirt + 0.0001;
	w_sand /= sum;
	w_snow /= sum;
	w_rock /= sum;
	w_grass /= sum;
	w_dirt /= sum;

	// ---------- 各材质颜色（用噪声做色斑变化） ----------
	vec3 c_sand = color_sand * (0.88 + 0.24 * micro2);
	vec3 c_grass = mix(color_grass_dry, color_grass, clamp(moist + (macro - 0.5) * 0.8, 0.0, 1.0));
	c_grass *= 0.82 + 0.36 * micro;
	vec3 c_rock = mix(color_rock_dark, color_rock, micro2 * 0.7 + meso * 0.3);
	vec3 c_snow = color_snow * (0.96 + 0.08 * micro);
	vec3 c_dirt = mix(color_dirt, color_sand, 0.3 * micro2);

	vec3 albedo = c_sand * w_sand + c_grass * w_grass + c_rock * w_rock + c_snow * w_snow + c_dirt * w_dirt;

	// 近岸潮湿 —— 略微压暗，模拟湿沙
	float wet = 1.0 - smoothstep(0.5, 4.0, h - sea_level);
	albedo *= 1.0 - wet * 0.18 * (1.0 - w_snow);

	// ---------- 土路 ----------
	float redge = road + (micro2 - 0.5) * 0.30 + (meso - 0.5) * 0.12;
	float rmask = smoothstep(0.35, 0.70, redge);
	vec3 c_road = color_road * (0.86 + 0.28 * mix(0.5, vnoise(w_pos.xz * 1.3), lod_fade));
	albedo = mix(albedo, c_road, rmask * 0.92);

	ALBEDO = albedo * (1.0 - 0.55 * night_amount);
	// 战争迷雾：未探索区域压暗
	float fog_v = texture(fog_map, uv).r;
	ALBEDO *= mix(1.0, 1.0 - fog_darkness * (1.0 - fog_v), fog_enabled);
	ROUGHNESS = mix(0.92, 0.42, w_snow);
	SPECULAR = mix(0.08, 0.25, w_snow * 0.6 + rmask * 0.2);
	METALLIC = 0.0;

	// ---------- 法线细节（程序化凹凸，只扰动视觉，不影响寻路） ----------
	float d1 = (vnoise(w_pos.xz * 0.55) - 0.5) * lod_fade;
	float d2 = (vnoise(w_pos.xz * 0.19) - 0.5) * lod_fade;
	vec3 bump_w = vec3(d1 * 0.7 + d2 * 0.5, 0.0, d1 * 0.35 + d2 * 0.8);
	bump_w *= detail_strength * (0.35 + 0.9 * w_rock) * (1.0 - rmask * 0.7);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bump_w, 0.0)).xyz);
}
