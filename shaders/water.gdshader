// =============================================================================
//  water.gdshader —— NPR 清透水体（海 / 湖 / 河共用）
//
//  这套水体要的是「一眼见底的动画水面」，不是写实反射：
//   · 深浅按**三档硬边带**切开（浅 / 中 / 深），不做连续插值；
//   · 岸边浪花是一条**阶梯化的白边**（深度阈值 + 噪声打碎），不是柔和的泡沫渐变；
//   · 天空反射用一个**量化过的菲涅尔台阶**（step），只在很斜的视角突然出现一条亮带；
//   · 波形仍然靠顶点位移（低多边形海面的起伏），近处再用导数把三角形拍平 ——
//     和地形同一套面着色手法，于是海面和陆地是同一种"低多边形"语言。
//
//  保留的接口（WaterBuilder / DayNightCycle 在写，改名会静默丢参数）：
//   height_map / map_size / water_level / wave_scale / wave_height / wave_speed /
//   flow_dir / foam_strength / foam_near / foam_far / transparency / shallow_alpha /
//   shallow_color / deep_color / sky_tint / foam_color / night_amount
// =============================================================================
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D height_map : filter_linear, repeat_disable;
uniform sampler2D gradient_map : filter_nearest, repeat_disable;
uniform float map_size = 1024.0;
uniform float water_level = 0.0;

uniform vec3 shallow_color : source_color = vec3(0.40, 0.88, 0.78);
uniform vec3 deep_color : source_color = vec3(0.10, 0.55, 0.72);
uniform vec3 sky_tint : source_color = vec3(0.55, 0.82, 0.98);
uniform vec3 foam_color : source_color = vec3(0.97, 1.00, 0.98);

uniform float wave_height = 0.35;
uniform float wave_speed = 1.0;
uniform float wave_scale = 1.0;
uniform float transparency = 0.80;   // 深水不透明度
uniform float shallow_alpha = 0.42;  // 浅水不透明度（更透）
uniform float foam_strength = 1.0;
uniform float foam_near = 0.12;      // 泡沫从多浅开始
uniform float foam_far = 2.6;        // 泡沫在多深处消失
uniform vec2 flow_dir = vec2(0.0, 1.0);
uniform float night_amount = 0.0;

varying vec3 w_pos;

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

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float s = 1.0 / max(wave_scale, 0.05);
	// 多重正弦波叠加：大浪 + 中浪 + 涟漪
	float w = sin(wp.x * 0.045 * s + t * 0.75) * 0.55
			+ sin(wp.z * 0.061 * s - t * 1.05) * 0.42
			+ sin((wp.x + wp.z) * 0.022 * s + t * 0.45) * 0.70
			+ sin((wp.x - wp.z) * 0.14 * s + t * 1.9) * 0.16;
	VERTEX.y += w * wave_height;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// ---------- 低多边形水面：近处拍平三角形，远处回到平滑 ----------
	vec3 face_n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (!FRONT_FACING) {
		face_n = -face_n;
	}
	vec3 smooth_n = NORMAL;
	float dist = distance(CAMERA_POSITION_WORLD, w_pos);
	float facet = 1.0 - smoothstep(220.0, 620.0, dist);
	NORMAL = normalize(mix(smooth_n, face_n, facet));

	// ---------- 水深 ----------
	vec2 uv = clamp(w_pos.xz / map_size, vec2(0.0), vec2(1.0));
	float bed = texture(height_map, uv).r;
	float depth = max(w_pos.y - bed, 0.0);

	// ---------- 三档色带（硬边，不插值）----------
	// 分界按**这张地图的水深分布**定：近岸 0~1.5 m 是大片浅滩，1.5~6 m 才是常见的
	// 近海，6 m 以上才算深水。旧版 3 / 11 m 的分界让整个可见近海都落在"浅"档，
	// 海面于是是一整片均匀的淡色，看不出"由浅入深"的三档。
	vec3 col = shallow_color;
	float mid = step(1.5, depth);
	float deep = step(6.0, depth);
	col = mix(col, mix(shallow_color, deep_color, 0.55), mid);
	col = mix(col, deep_color, deep);

	// ---------- 天空反射：量化菲涅尔，只留一条硬亮带 ----------
	// 阈值必须"很掠射"：0.62 对应离水面 38°，那几乎是整片远海 —— 实测会把浅滩
	// 整块染成灰白，沙子透不出来。0.88（约 17°）才是真正的水天线。
	vec3 vdir = normalize(VIEW);
	float fres = 1.0 - clamp(dot(normalize(NORMAL), vdir), 0.0, 1.0);
	float sky_band = step(0.88, fres) * 0.45;
	col = mix(col, sky_tint, clamp(sky_band, 0.0, 0.45));

	// ---------- 岸边浪花：阶梯白边 + 噪声打碎 ----------
	// 浪花必须由**岸坡**驱动，而不是"浅水就算浪"。这片地图有几个巨大的平坦浅滩
	// （水深 0~0.2 m 铺出去上百米）—— 只按深度判断的话整片浅滩都被当成水线刷成
	// 白板，实测连海底的沙纹都看不见。这里补一个海底坡度：平坦浅滩 slope≈0.02，
	// 真正的沙滩坡 > 0.15，于是只有"紧贴沙滩、并且坡在往上走"的那一圈才出白边。
	vec2 duv = vec2(0.5 / map_size, 0.0);
	vec2 dvv = vec2(0.0, 0.5 / map_size);
	float bx = texture(height_map, uv + duv).r - texture(height_map, uv - duv).r;
	float bz = texture(height_map, uv + dvv).r - texture(height_map, uv - dvv).r;
	float bed_slope = length(vec2(bx, bz));
	float shore = (1.0 - step(0.35, depth)) * step(0.10, bed_slope);
	// 河流用 flow_dir 让浪花沿水流方向滚动（海/湖传的是默认值，等于不动）
	vec2 flow = normalize(flow_dir + vec2(1e-4));
	float chop = vnoise(w_pos.xz * 0.9 + flow * TIME * 0.7);
	float foam = step(0.45, shore * (0.55 + 0.55 * chop) * foam_strength);
	col = mix(col, foam_color, foam * 0.95);

	// ---------- 昼夜 ----------
	col *= 1.0 - 0.60 * night_amount;

	ALBEDO = col;
	// 浅滩要"一眼见底"：alpha 低到能看清沙纹；泡沫只额外加一点，否则白边会把沙滩盖住
	ALPHA = clamp(mix(shallow_alpha, transparency, step(1.5, depth)) + foam * 0.30, 0.0, 1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	EMISSION = vec3(0.0);
}

// 三阶阶梯光：水面也吃同一套 ramp，于是浪峰的明暗是三档而不是渐变。
// **水面不吃投影**（不乘 ATTENUATION）：树影 / 屋影落在水面上会变成一块块深色
// "油斑"——水面本来就在动，硬阴影投上去既不物理也不好看；参考风格里的水面
// 只有色带 + 白边，没有花的影子。地形 / 建筑仍然照常接收阴影。
void light() {
	float lit = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	float band = texture(gradient_map, vec2(lit, 0.5)).r;
	DIFFUSE_LIGHT += band * LIGHT_COLOR;
}
