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
//
//  第七轮 ② 起多了一张**无缝细节贴图**（detail_map，灰度，均值 ~1.0）与它的法线图：
//  参考项目的原话是「大片单色地形看着像色纸」—— 程序化噪声负责的是大色斑，
//  高频颗粒交给贴图更便宜也更清楚（一趟 texture() 换掉两次 vnoise 的四次哈希）。
//  铺法用 UV2 那种「按世界尺寸平铺」的做法（这里没有网格 UV，直接拿 w_pos.xz 当 UV）。
// =============================================================================
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D splat_map : filter_linear, repeat_disable;
uniform sampler2D fog_map : filter_linear, repeat_disable;
// 细节贴图与法线图必须 repeat + mipmap：前者要平铺，后者在远处靠 mipmap 抗摩尔纹
uniform sampler2D detail_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : filter_linear_mipmap, repeat_enable;
uniform float fog_enabled = 0.0;
uniform float fog_darkness = 0.62;

uniform float map_size = 1024.0;
uniform float sea_level = 0.0;
uniform float snow_line = 118.0;      // 雪线高度（米）
uniform float mountain_line = 88.0;   // 岩石开始占主导的高度
uniform float slope_rock = 0.42;      // 坡度阈值（0 = 平地, 1 = 垂直）
uniform float beach_width = 6.0;      // 沙滩带宽（米）
uniform float detail_strength = 0.55; // 法线细节强度（程序化那一层）
uniform float night_amount = 0.0;     // 0 = 白天, 1 = 深夜（由昼夜循环写入）
uniform float day_amount = 1.0;       // 1 = 白天, 0 = 天黑（由昼夜循环写入，见 register_shader）
// 细节贴图的平铺尺寸（米/份）与混合强度：推导见 MaterialFactory 顶部注释
uniform float detail_tile_a = 9.0;
uniform float detail_tile_b = 13.0;
uniform float detail_tile_macro = 70.0;     // 第三层：同一张贴图放大成大色斑
uniform float detail_lo = 0.60;             // 细节值域映射：贴图里存的是 0~1 原始高度
uniform float detail_hi = 1.40;             // （8 位通道存不下 >1.0，映射必须放在这里）
uniform float detail_strength_tex = 0.95;   // 贴图法线的强度
uniform float detail_albedo = 0.70;         // 细节贴图混进底色的比例（0 = 关）
uniform float normal_strength = 1.0;
// 地面自发光的「地板」：不进光照计算，所以阴影/坡向明暗全保留
uniform vec3 ground_emission_color : source_color = vec3(0.13, 0.15, 0.12);
uniform float ground_emission_energy = 0.60;
uniform float albedo_saturation = 1.10;

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

	// ---------- 细节贴图（取值域映射后均值 ~1.0，MUL 混合）----------
	// 两份贴图取不同的平铺尺寸（9 m / 13 m，互相不整除），错开之后不会叠出规则图案
	vec2 duv_b = w_pos.xz / detail_tile_b;
	vec2 duv_a = w_pos.xz / detail_tile_a;
	vec3 detail_rgb = mix(vec3(detail_lo), vec3(detail_hi), texture(detail_map, duv_b).rgb);
	albedo *= mix(vec3(1.0), detail_rgb, detail_albedo * lod_fade);
	// 第三层：同一张贴图按 ~70 m 平铺，给大片单色地形一点大尺度色斑。
	// 省一张贴图 —— 放大到 70 m 后 mipmap 正好只留低频内容；同样过一遍值域映射，
	// 否则均值 0.5 的原始高度会把整张图压暗 17%。
	float macro_detail = mix(detail_lo, detail_hi, texture(detail_map, w_pos.xz / detail_tile_macro).r);
	albedo *= mix(1.0, macro_detail, 0.35);

	// 底色饱和度补偿（天空环境光偏蓝会把地表洗灰，见 MaterialFactory 注释）。
	// 只动 albedo：光照、阴影、昼夜亮度都不受影响。
	float lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	albedo = clamp(mix(vec3(lum), albedo, albedo_saturation), vec3(0.0), vec3(1.0));

	ALBEDO = albedo * (1.0 - 0.55 * night_amount);
	// 战争迷雾：未探索区域压暗
	float fog_v = texture(fog_map, uv).r;
	ALBEDO *= mix(1.0, 1.0 - fog_darkness * (1.0 - fog_v), fog_enabled);
	// 地面自发光地板：把最暗处从死黑抬到「微微透光」。它跟**白昼权重**走 ——
	// 夜里归零，否则整张地图会自己发亮；清晨如果按「1 - night_amount」算会几乎是满值，
	// 天光的层次会整个糊掉（实测黎明近黑像素 31.6% → 3.2%）。
	EMISSION = ground_emission_color * ground_emission_energy * day_amount;
	ROUGHNESS = mix(0.92, 0.42, w_snow);
	SPECULAR = mix(0.08, 0.25, w_snow * 0.6 + rmask * 0.2);
	METALLIC = 0.0;

	// ---------- 法线细节 ----------
	// 两层：程序化低频（大地形起伏感）+ 贴图高频（颗粒感）。
	// 两者都只扰动视觉，不影响寻路。
	float d1 = (vnoise(w_pos.xz * 0.55) - 0.5) * lod_fade;
	float d2 = (vnoise(w_pos.xz * 0.19) - 0.5) * lod_fade;
	vec3 bump_w = vec3(d1 * 0.7 + d2 * 0.5, 0.0, d1 * 0.35 + d2 * 0.8);
	bump_w *= detail_strength * (0.35 + 0.9 * w_rock) * (1.0 - rmask * 0.7);
	// 贴图法线解回 [-1,1]，直接当世界空间的水平扰动（这片地形是高度场，切线近似 XZ 平面）
	vec3 ntex = texture(detail_normal, duv_a).rgb * 2.0 - 1.0;
	bump_w += vec3(ntex.x, 0.0, ntex.y) * detail_strength_tex * normal_strength
			* lod_fade * (0.35 + 0.9 * w_rock) * (1.0 - rmask * 0.5);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bump_w, 0.0)).xyz);
}
