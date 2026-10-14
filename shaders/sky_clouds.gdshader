// =============================================================================
//  天空 Shader —— 蓝天 + 白云（shader_type sky）
//
//  来源：参考项目 F:\aigc_code\godot_ai_test\assets\world\sky_clouds.gdshader
//  （第七轮 ② 观感补齐）。参数默认值取那边的 assets/world/world_map.json
//  atmosphere.sky 一节（cloud_scale 5.0 / coverage 0.46 / softness 0.16 …）。
//
//  ---- 为什么不用 ProceduralSkyMaterial ----
//  它只有上下渐变，**没有云**；Godot 也不带任何内置的云材质（PhysicalSkyMaterial
//  同样没有）。云只能自己做：要么一张全景贴图，要么着色器。这里的着色器方案省掉了
//  「生成 + 导入一张 1024×512 贴图」的成本，参数直接就是可调 uniform。
//
//  云的投影方式：把视线方向投影到一块「云的高度」平面上（EYEDIR.xz / EYEDIR.y）。
//  这是标准做法，近地平线的云会被自然拉长、有天顶方向的距离感；代价是 EYEDIR.y → 0
//  时除法会爆炸成条纹，所以必须用 band 在地平线附近淡出。
//
//  ---- 与本项目的两处刻意不同（照搬会坏，别改回去）----
//  1) **天黑由 GDScript 给最终色**：那边天空内部用 day_factor 在 night_* 与 day_*
//     两组颜色间插值；本项目 DayNightCycle 已经逐时算好了包含橙色晚霞的四段配色，
//     若再把逐时算出的色交给「会按 day_factor 往夜色拉」的天空，等于把夜色乘两遍。
//     所以这里删掉 night_sky_top / night_sky_horizon，天空只收最终的 sky_top /
//     sky_horizon；day_factor 只留给**云与太阳辉光的白昼权重**。
//  2) **地平线以下（ground_horizon / ground_bottom）逐时更新**：本项目相机俯角
//     26°~72°、fov 52°，「画面顶端」在地平线上 0°~-29°，也就是**看向天空的像素
//     几乎为零**，真正露在背景里的是地图切边之外的那条带（EYEDIR.y < 0 的那半边）。
//     那边的地面色是常量，这里改成由昼夜写入，夜里那条带跟着变暗。
//
//  ---- 两个调参关键（那边的实测结论，别按直觉改）----
//  · sky_curve：相机俯角最低时可见天空只有地平线上方约 9°（h ≤ 0.155）那一条窄带，
//    指数越大蓝色越到不了低空，整条带就全是接近 sky_horizon 的灰白。0.55 → 0.30
//    让蓝色提前出现。
//  · cloud_band_start / end：原来 (0.02, 0.20) 会把云全压在窄带之上，结果天空一片
//    纯蓝、看不到云。改成 (0.004, 0.070) 让云从仰角约 0.2° 就开始出现。
//
//  ---- cloud_speed 必须是 0（默认值就是 0，别随手调大）----
//  云一动就得每帧重算天空辐照度，而环境光现在是 AMBIENT_SOURCE_SKY：天空一抖，
//  整个场景的漫反射跟着抖。想让云飘，先确认能接受这份抖动再开。
// =============================================================================
shader_type sky;

// ---- 天空渐变（由 DayNightCycle 逐时写入最终色）----
uniform vec3 sky_top : source_color = vec3(0.16, 0.40, 0.85);
uniform vec3 sky_horizon : source_color = vec3(0.42, 0.66, 0.94);
// ---- 地平线以下（地图边界之外会看到这一侧）----
uniform vec3 ground_horizon : source_color = vec3(0.50, 0.52, 0.52);
uniform vec3 ground_bottom : source_color = vec3(0.20, 0.22, 0.24);
// ---- 云 ----
uniform vec3 cloud_light : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_dark : source_color = vec3(0.60, 0.66, 0.76);
uniform float cloud_scale = 5.0;
// 软化平面投影的偏移量。纯 EYEDIR.xz/EYEDIR.y 在 h→0 时除法爆炸，而且云的大小
// 在整个天球上会差几十倍；加一个正偏移把压缩比限制住，云尺寸才可控。
uniform float cloud_projection_bias = 0.35;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.46;
uniform float cloud_softness : hint_range(0.01, 0.6) = 0.16;
uniform float cloud_amount : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_speed = 0.0;
uniform float cloud_top_fade : hint_range(0.3, 1.0) = 0.88;
uniform float sky_curve = 0.30;
// 云的可见仰角带（单位是 EYEDIR.y = sin(仰角)）
uniform float cloud_band_start = 0.004;
uniform float cloud_band_end = 0.070;
// ---- 昼夜与太阳 ----
// 只当「云 / 太阳辉光的白昼权重」用（天色本身由 sky_top / sky_horizon 直接给出，见文件头）
uniform float day_factor : hint_range(0.0, 1.0) = 1.0;
uniform float dusk_factor : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform float sun_glow = 0.35;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// 值噪声：双线性插值 + smoothstep，比 simplex 便宜，云这种低频内容够用
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		// 乘 2.03 而不是 2.0：每层稍微错开，避免各层极值对齐成规则网格
		p = p * 2.03 + vec2(11.7, 5.3);
		amp *= 0.5;
	}
	return v;
}

void sky() {
	float h = EYEDIR.y;
	float day = clamp(day_factor, 0.0, 1.0);
	float dusk = clamp(dusk_factor, 0.0, 1.0);

	// 天空渐变
	float t = pow(clamp(h, 0.0, 1.0), max(sky_curve, 0.01));
	vec3 col = mix(sky_horizon, sky_top, t);

	// 太阳附近的暖色辉光。权重取 max(day, dusk)：日落那一刻 day 刚好归零，
	// 而辉光正该是全天最强的时候 —— 只看 day 的话晚霞永远是灭的。
	// 辉光颜色比云更暖、更集中（指数 26），日落时它就是地平线上那个亮点。
	float glow_w = max(day, dusk);
	float sd = max(dot(normalize(EYEDIR), normalize(sun_direction)), 0.0);
	col += vec3(1.0, 0.84, 0.56) * pow(sd, 26.0) * sun_glow * glow_w;
	// 低空整体再染一层暖色：只有辉光点的话，日落看着像「天上挂了一盏灯」。
	// 系数别贪大 —— 0.65 时整片天连地形都偏橙，像火星；0.45 刚好是「霞光」。
	col += mix(vec3(0.0), vec3(0.55, 0.22, 0.06), dusk)
			* (1.0 - smoothstep(0.0, 0.35, h)) * 0.45;

	// ---- 云 ----
	float up = max(h, 0.0) + cloud_projection_bias;
	vec2 cp = (EYEDIR.xz / up) * cloud_scale;
	if (cloud_speed != 0.0) {
		cp += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.6);
	}
	float n = fbm(cp);
	float cov = smoothstep(cloud_coverage - cloud_softness,
			cloud_coverage + cloud_softness, n);
	// band：地平线附近淡出（否则除法把云拉成条纹），天顶附近也淡出（否则云铺满头顶像天花板）
	float band = smoothstep(cloud_band_start, cloud_band_end, h)
			* (1.0 - smoothstep(cloud_top_fade, 1.0, h));
	float a = cov * band * cloud_amount * day;
	vec3 ccol = mix(cloud_dark, cloud_light,
			smoothstep(cloud_coverage, cloud_coverage + cloud_softness * 1.8, n));
	col = mix(col, ccol, a);

	// 地平线以下换成地面色；用 smoothstep 过渡，避免出现一条硬边
	vec3 gcol = mix(ground_horizon, ground_bottom, pow(clamp(-h, 0.0, 1.0), 0.5));
	col = mix(gcol, col, smoothstep(-0.035, 0.020, h));

	COLOR = col;
	ALPHA = 1.0;
}
