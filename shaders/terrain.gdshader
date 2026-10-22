// =============================================================================
//  terrain.gdshader —— NPR 低多边形地形（微缩手办风）
//
//  ---- 这一版和旧版的三点不同（旧的写实混合已经全部退场）----
//  1. **面着色（Faceted）**：法线不再用顶点平滑法线，而是在片元里用屏幕空间导数
//     把每个三角形拍成一块平面 —— 这就是 three.js 里 `geometry.toNonIndexed()` +
//     `computeVertexNormals()` 的等价效果，但**不动几何体**：顶点位置、索引、LOD 分块
//     与探针指纹全部保持原样（scale_probe 的 terrain_pos_hash / idx_hash 不变）。
//     为什么不用真的去索引：那会让 LOD0 每块从 1089 顶点涨到 6144，建块耗时与
//     显存一起翻几倍，而画面上一个像素都不差。
//  2. **三阶阶梯光照**：不用内置 lambert，改用 `light()` + gradient_map 把 N·L 量化成
//     暗 / 中 / 亮三档（见 ToonStyle.RAMP_BANDS）。阴影仍然走引擎的 shadow map，
//     所以 ATTENUATION 是硬的、边缘干脆。
//  3. **高饱和纯色带**：海滨浅滩柠檬黄 → 低地苹果绿 → 高山松石青 → 雪顶纯白。
//     没有任何贴图与法线细节（旧版的 detail_map / detail_normal 已删除）：
//     微缩沙盒的质感来自**大色块 + 硬光影 + 干净轮廓**，颗粒贴图只会把它拉回写实。
//
//  splat_map 通道约定（由 MapTextureBaker 烘焙，未改动）：
//    R = 道路遮罩  G = 沙漠/干旱  B = 裸岩/碎石  A = 湿度（未使用）
//
//  ---- 为什么地形没有反向外壳描边 ----
//  反向外壳依赖"背面"：它把网格沿法线膨胀后只画背面。地形是一张**开放的**高度场曲面，
//  从上方看根本没有背面可画，膨胀只会得到一片什么都不剩的壳。
//  所以地形的"线稿感"用另外两件事表达：面着色的硬转折 + 海岸线的深色湿沙带
//  （h ∈ [-0.7, 0.7] 的一圈深柠檬）。植被 / 建筑 / 部队这些闭合几何体才挂 next_pass 描边。
// =============================================================================
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D splat_map : filter_linear, repeat_disable;
uniform sampler2D fog_map : filter_linear, repeat_disable;
uniform sampler2D gradient_map : filter_nearest, repeat_disable;
uniform float fog_enabled = 0.0;
uniform float fog_darkness = 0.62;

uniform float map_size = 1024.0;
uniform float sea_level = 0.0;
uniform float snow_line = 118.0;       // 雪线（米，由高度场分位数推导）
uniform float mountain_line = 88.0;    // 岩石/松石青开始占主导的高度
uniform float slope_rock = 0.42;       // 坡度阈值（1 = 垂直）：陡坡强制算岩石
uniform float beach_width = 6.0;       // 沙滩带宽（米）
uniform float night_amount = 0.0;      // 0 = 白天, 1 = 深夜
uniform float day_amount = 1.0;        // 1 = 白天, 0 = 天黑

// ---- 调色板（默认值与 ToonStyle.gd 的常量逐位一致，门禁会比对）----
uniform vec3 color_seabed : source_color = vec3(0.42, 0.82, 0.72);
uniform vec3 color_sand : source_color = vec3(0.96, 0.88, 0.44);
uniform vec3 color_grass : source_color = vec3(0.45, 0.77, 0.29);
uniform vec3 color_grass_dark : source_color = vec3(0.30, 0.60, 0.25);
uniform vec3 color_rock : source_color = vec3(0.30, 0.72, 0.66);
uniform vec3 color_rock_dark : source_color = vec3(0.18, 0.53, 0.55);
uniform vec3 color_snow : source_color = vec3(0.97, 0.99, 1.00);
uniform vec3 color_road : source_color = vec3(0.93, 0.82, 0.60);
uniform vec3 color_desert : source_color = vec3(0.98, 0.86, 0.48);
// 湿沙 / 海岸线的深色圈：柠檬黄压暗一档，勾出「水与陆」的分界
uniform vec3 color_tide : source_color = vec3(0.72, 0.58, 0.22);

varying vec3 w_pos;
varying vec3 w_norm;

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
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 平滑法线先算好：它只用来判坡度（片元里再用导数拍平）
	w_norm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// ---------- 面着色：把三角形拍平 ----------
	// VERTEX 在片元里是**视图空间**位置，对 x / y 求导的叉积就是面法线（视图空间）。
	// 背面要反过来，否则从下面看地形会全黑。
	vec3 face_n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (!FRONT_FACING) {
		face_n = -face_n;
	}
	NORMAL = face_n;

	// ---------- 分类：高度 + 坡度 + splat ----------
	vec2 suv = clamp(w_pos.xz / map_size, vec2(0.0), vec2(1.0));
	vec4 splat = texture(splat_map, suv);
	float rmask = splat.r;          // 道路
	float dmask = splat.g;          // 干旱
	float bmask = splat.b;          // 裸岩
	float slope = 1.0 - clamp(w_norm.y, 0.0, 1.0);
	float h = w_pos.y - sea_level;

	vec3 col = color_grass;
	// 低地：苹果绿，用一条硬边界分成「向阳 / 背阴」两档（不是渐变）
	float low = clamp((h - beach_width) / max(1.0, mountain_line * 0.55), 0.0, 1.0);
	col = mix(color_grass, color_grass_dark, step(0.55, low));
	// ---- 大尺度草色斑块（两色硬切）----
	// 只在 90 m 战略视角看得出来的问题：整片低地都是同一个苹果绿，地形起伏
	// 被"平涂"吃掉了。参考风格里草地本身就有深浅两种色块，所以这里用一层
	// 约 40 m 尺度的程序噪声在两种绿之间硬切 —— 不加贴图、不改几何、
	// 不碰任何 RNG，纯粹是片元着色。阈值取 0.5（噪声中位数）保证任何一块
	// 视野里都有深浅两种斑块，不会整片落在同一个值上。
	float patch = vnoise(w_pos.xz * 0.025) * 0.65 + vnoise(w_pos.xz * 0.08) * 0.35;
	float lowland = 1.0 - step(0.90, low);
	col = mix(col, color_grass_dark, step(0.50, patch) * lowland * 0.90);
	// 干旱带：奶油黄（只在低地出现，高山上不该有沙漠色）
	col = mix(col, color_desert, step(0.5, dmask) * (1.0 - step(mountain_line * 0.75, h)));
	// 岩石 / 高山：松石青。高度线以上或陡坡都算（陡坡用更深的青）
	float rocky = max(step(mountain_line, h), step(slope_rock, slope));
	float steep = step(0.62, slope);
	col = mix(col, mix(color_rock, color_rock_dark, steep), rocky);
	// 裸岩遮罩再压一层，让山脊碎石更明显
	col = mix(col, color_rock_dark, step(0.55, bmask) * 0.65);
	// 雪：雪线以上纯白；雪线附近用一条硬边界，不要羽化
	col = mix(col, color_snow, step(snow_line, h));
	// 沙滩：海滨一圈柠檬黄（水下也铺沙子，水面会透过它）
	col = mix(col, color_sand, 1.0 - step(beach_width, h));
	// 水下：越深越偏青绿（水本身是半透明的，这里只是给水底一个干净的底色）
	float depth = clamp(-h / 9.0, 0.0, 1.0);
	col = mix(col, color_seabed, step(h, 0.0) * (1.0 - depth * 0.55));
	// 海岸线：水陆交界的一条深柠檬，代替地形的描边
	float tide = 1.0 - step(0.7, abs(h));
	col = mix(col, color_tide, tide * 0.85);
	// 土路：暖奶黄（旧版是棕色土路，在这套配色里会显脏）
	col = mix(col, color_road, rmask * 0.92);

	// ---------- 昼夜 + 战争迷雾（语义与旧版逐字一致）----------
	col *= 1.0 - 0.55 * night_amount;
	float fog_v = texture(fog_map, suv).r;
	col *= mix(1.0, 1.0 - fog_darkness * (1.0 - fog_v), fog_enabled);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	EMISSION = vec3(0.0);
}

// ---------- 三阶阶梯光 ----------
// Godot 每个光源调用一次：DIRECTIONAL 的 LIGHT 是「指向光源」的方向（视图空间）。
// ATTENUATION 里含 shadow map 的结果，所以硬阴影 = 亮部直接掉到暗部，正是要的效果。
void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float lit = clamp(ndl, 0.0, 1.0);
	// 阶梯查表：x = N·L，y 随便（1 像素高的图）
	float band = texture(gradient_map, vec2(lit, 0.5)).r;
	DIFFUSE_LIGHT += band * ATTENUATION * LIGHT_COLOR;
}
