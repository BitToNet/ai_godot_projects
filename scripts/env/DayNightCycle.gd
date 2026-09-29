## =============================================================================
##  DayNightCycle —— 昼夜循环 + 大气/雾 + 夜间灯火
##  · 游戏内 1 天 = 现实 2 分钟（cfg.day_length_seconds = 120）
##  · 太阳（DirectionalLight3D）绕世界旋转，天色（ProceduralSkyMaterial）
##    按太阳高度角在「黎明/白天/黄昏/夜晚」四套配色间平滑插值
##  · 距离雾 + 雾色随天色变化，拉远时海天连成一片，看不到地图切边
##  · 夜晚点亮各定居点的暖色 OmniLight3D，并把 night_amount 推给所有 Shader
## =============================================================================
class_name DayNightCycle
extends Node3D

signal day_changed(day: int)

var cfg: MapConfig
var data: MapData
var sun: DirectionalLight3D
var env_node: WorldEnvironment
var env: Environment
var sky: Sky
var sky_mat: ProceduralSkyMaterial

var time_of_day: float = 8.0 / 24.0
var day: int = 1
var paused: bool = false
var speed: float = 1.0
var night_amount: float = 0.0

var _night_lights: Array[OmniLight3D] = []
var _shader_mats: Array = []       ## [{mat, param}]

func setup(p_cfg: MapConfig, p_data: MapData) -> void:
	cfg = p_cfg
	data = p_data
	time_of_day = cfg.start_hour / 24.0

	# ---------------- 环境 ----------------
	env_node = WorldEnvironment.new()
	env = Environment.new()
	sky = Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.12
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.ground_energy_multiplier = 0.4
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# 环境光用固定色而非天空采样：避免阴影里被天空染成饱和蓝
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_sky_contribution = 0.0
	env.ambient_light_color = Color(0.55, 0.56, 0.60)
	env.ambient_light_energy = 0.52
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 4.0
	env.ssao_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 420.0
	env.fog_depth_end = 2600.0
	env.fog_density = 1.0
	env.fog_sky_affect = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.04
	env_node.environment = env
	add_child(env_node)

	# ---------------- 太阳 ----------------
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 340.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.42
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.4
	sun.light_angular_distance = 1.2
	sun.shadow_blur = 1.2
	add_child(sun)
	_apply()

func register_night_light(l: OmniLight3D) -> void:
	_night_lights.append(l)
	if l.light_energy > 0.0:
		l.visible = night_amount > 0.25
		l.light_energy = maxf(0.001, night_amount * 1.6)

## 注册需要跟随昼夜变化的 Shader 材质（参数名不同：地形/水面用 night_amount，建筑/植被用 night_glow）
func register_shader(mat: ShaderMaterial, param: String) -> void:
	_shader_mats.append({"mat": mat, "param": param})
	var v := night_amount if param == "night_amount" else night_amount
	mat.set_shader_parameter(param, v)

func _process(delta: float) -> void:
	if paused:
		return
	var prev_day := day
	time_of_day += delta * speed / maxf(1.0, cfg.day_length_seconds)
	while time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1
	if day != prev_day:
		day_changed.emit(day)
	_apply()

func hour() -> float:
	return time_of_day * 24.0

func time_string() -> String:
	var h := hour()
	var hh := int(floor(h))
	var mm := int((h - float(hh)) * 60.0)
	return "%02d:%02d" % [hh, mm]

func is_night() -> bool:
	return night_amount > 0.5

func _apply() -> void:
	var ang := (time_of_day - 0.25) * TAU
	var elev := sin(ang)
	night_amount = clampf(-elev * 1.5 + 0.12, 0.0, 1.0)

	# 太阳方向：东方升起 → 西方落下
	var elev_deg := rad_to_deg(asin(clampf(elev, -1.0, 1.0)))
	# 东升 → 南中天 → 西落（北半球）：yaw 在白天扫过 180°
	var yaw_deg := 90.0 - (time_of_day - 0.25) * 360.0
	sun.rotation = Vector3(-deg_to_rad(maxf(elev_deg, -8.0)), deg_to_rad(yaw_deg), 0.0)

	var day_f := clampf(elev * 3.2, 0.0, 1.0)
	var dusk_f := clampf(1.0 - absf(elev - 0.02) * 5.0, 0.0, 1.0)
	var night_f := clampf(-elev * 3.0 + 0.1, 0.0, 1.0)

	var night_top := Color(0.020, 0.028, 0.070)
	var night_hor := Color(0.050, 0.065, 0.130)
	var day_top := Color(0.190, 0.380, 0.800)
	var day_hor := Color(0.640, 0.760, 0.930)
	var dusk_top := Color(0.300, 0.230, 0.380)
	var dusk_hor := Color(0.960, 0.480, 0.220)

	var top := night_top.lerp(day_top, day_f).lerp(dusk_top, dusk_f * 0.55)
	var hor := night_hor.lerp(day_hor, day_f).lerp(dusk_hor, dusk_f * 0.75)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.sky_curve = 0.12 + 0.1 * dusk_f
	sky_mat.ground_bottom_color = night_top.lerp(Color(0.12, 0.13, 0.15), day_f)
	sky_mat.ground_horizon_color = hor.lerp(Color(0.12, 0.13, 0.15), 0.4)

	# 太阳光强 / 颜色
	sun.light_energy = clampf(elev * 1.25 + 0.05, 0.0, 1.25)
	sun.light_color = Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.60, 0.34), dusk_f * 0.8)
	if night_f > 0.55:
		# 夜晚用冷色微光当月光
		sun.light_energy = 0.16
		sun.light_color = Color(0.58, 0.68, 0.96)
		sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(210.0), 0.0)

	var amb_day := Color(0.55, 0.56, 0.60)
	var amb_dusk := Color(0.55, 0.42, 0.36)
	var amb_night := Color(0.17, 0.21, 0.36)
	env.ambient_light_color = amb_night.lerp(amb_day, day_f).lerp(amb_dusk, dusk_f * 0.55)
	env.ambient_light_energy = lerpf(0.40, 0.52, day_f)
	env.background_energy_multiplier = lerpf(0.35, 1.0, day_f)
	env.fog_light_color = hor.lerp(Color(0.6, 0.7, 0.85), 0.25)
	env.fog_light_energy = lerpf(0.5, 1.0, day_f)
	env.fog_density = lerpf(1.35, 0.85, day_f)
	env.fog_depth_end = lerpf(1500.0, 2900.0, day_f)
	env.tonemap_exposure = lerpf(1.05, 0.95, day_f)

	# 夜间灯火
	var lights_on := night_amount > 0.28
	for l in _night_lights:
		if l == null:
			continue
		l.visible = lights_on
		l.light_energy = maxf(0.0, night_amount * 1.8)
	# Shader
	for e in _shader_mats:
		e.mat.set_shader_parameter(e.param, night_amount)
