// =============================================================================
//  水面 Shader —— 海面 / 湖泊 / 河流共用
//  · 顶点波动（多重正弦叠加，无需贴图）
//  · 菲涅尔反射（视角越斜越像天空的镜子）
//  · 用 height_map 采样水底高度 → 浅水偏亮偏透明，岸边泛白泡沫
//  · flow_dir 用于河流：让波形沿水流方向滚动
// =============================================================================
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_map : filter_linear, repeat_disable;
uniform float map_size = 1024.0;
uniform float water_level = 0.0;

uniform vec3 shallow_color : source_color = vec3(0.34, 0.60, 0.60);
uniform vec3 deep_color : source_color = vec3(0.02, 0.11, 0.22);
uniform vec3 sky_tint : source_color = vec3(0.55, 0.72, 0.95);
uniform vec3 foam_color : source_color = vec3(0.93, 0.97, 0.99);

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
	vec2 uv = clamp(w_pos.xz / map_size, vec2(0.0), vec2(1.0));
	float bed = texture(height_map, uv).r;
	float depth = max(w_pos.y - bed, 0.0);

	float t = TIME * wave_speed;
	// 远处衰减程序噪声细节：否则高频噪声在远景会变成摩尔纹/白点
	float cam_dist = distance(CAMERA_POSITION_WORLD, w_pos);
	float det = 1.0 - smoothstep(150.0, 640.0, cam_dist);

	// 波浪法线（双频噪声 + 行波）
	vec2 p = w_pos.xz * 0.35;
	float n1 = vnoise(p + vec2(t * 0.35, t * 0.22));
	float n2 = vnoise(p * 2.3 - vec2(t * 0.5, t * 0.3));
	float nx = ((n1 - 0.5) + (n2 - 0.5) * 0.5) * det;
	float nz = (vnoise(p + vec2(13.7, 4.2) + vec2(-t * 0.28, t * 0.4)) - 0.5) * 1.5 * det;
	vec3 n = normalize(vec3(nx * 0.55, 1.0, nz * 0.55));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// 菲涅尔
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);

	// 深浅颜色
	vec3 col = mix(shallow_color, deep_color, smoothstep(0.8, 16.0, depth));
	col = mix(col, sky_tint * 1.02, fres * 0.34);

	// 岸边泡沫：浅水 + 噪声破碎的白边
	float band = 1.0 - smoothstep(foam_near, foam_far, depth);
	float chop = mix(0.62, vnoise(w_pos.xz * 0.55 + vec2(t * 0.6, -t * 0.4)), det);
	float foam = clamp(band * (0.45 + 0.85 * chop) * foam_strength, 0.0, 1.0);
	col = mix(col, foam_color, foam * 0.85);

	ALBEDO = col * (1.0 - 0.60 * night_amount);
	ALPHA = mix(shallow_alpha, transparency, smoothstep(0.0, 9.0, depth));
	ALPHA = clamp(ALPHA + foam * 0.5, 0.0, 1.0);
	ROUGHNESS = mix(0.09, 0.40, foam * 0.6);
	SPECULAR = 0.45 - foam * 0.3;
	METALLIC = 0.0;
	// 水体自发光极弱，仅让夜间不显得死黑
	EMISSION = col * 0.11 * night_amount;
}
