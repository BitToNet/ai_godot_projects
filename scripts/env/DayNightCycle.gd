## =============================================================================
##  DayNightCycle —— 昼夜循环 + 大气/雾 + 夜间灯火
##  · 游戏内 1 天 = 现实 2 分钟（cfg.day_length_seconds = 120）
##  · 太阳（DirectionalLight3D）绕世界旋转，天色（shaders/sky_clouds.gdshader）
##    按太阳高度角在「黎明/白天/黄昏/夜晚」四套配色间平滑插值
##  · 环境光来自**天空**（0.6 天空辐照度 + 0.4 逐时调过的颜色）：固定灰环境光会让
##    山坡、树根、城墙内侧收到一模一样的光，整张图是「平」的（第七轮 ② 改）
##  · 距离雾 + 空气透视，拉远时海天连成一片，看不到地图切边
##  · 夜晚点亮各定居点的暖色 OmniLight3D，并把 night_amount 推给所有 Shader
## =============================================================================
class_name DayNightCycle
extends Node3D

signal day_changed(day: int)

## 天空着色器（程序化蓝天 + 白云，来源与调参说明见该文件头部）
const SKY_SHADER := "res://shaders/sky_clouds.gdshader"

## 环境光：天空占 0.6，剩下 0.4 是下面逐时插值的那三个颜色。
## 能量取值照参考项目（那边 1.20 / 0.22）但都压低了：环境光抬的是**均匀光**，
## 抬过头地形就发灰发白（实测 1.05 时正午均亮度比旧版高 8%、饱和度反而低 12%）；
## 而方向光的对比度才是「不飘」的来源，所以这里把环境光让出来的部分给了太阳。
const AMBIENT_SKY_CONTRIBUTION := 0.60
const AMBIENT_ENERGY_DAY := 0.90
## 夜里给一点点底：环境光取自天光，深夜天空几乎全黑，纯物理的话地面一片死黑玩不了
const AMBIENT_ENERGY_NIGHT := 0.36
## 白天太阳光强的斜率和上限（旧值是 1.25 / 1.25）
const SUN_SLOPE := 1.35
const SUN_MAX := 1.35

## 天空里与时刻无关的常量参数。集中在一处、由 GDScript 显式设一遍（理由同
## MaterialFactory）：shader 里的默认值只当兜底 —— get_shader_parameter 对
## 「从未被赋值过」的 uniform 返回 null，自检读回来会以为参数丢了。
## cloud_speed 必须是 0：云一动就每帧重算天空辐照度，而环境光取自天空，
## 一抖就是整个场景的漫反射在抖（参考项目为此专门写了一行备注）。
const SKY_CONSTANTS := {
	"cloud_light": Color(1.0, 1.0, 1.0),
	"cloud_dark": Color(0.60, 0.66, 0.76),
	"cloud_scale": 5.0,
	"cloud_coverage": 0.46,
	"cloud_softness": 0.16,
	"cloud_amount": 1.0,
	"cloud_speed": 0.0,
	"cloud_top_fade": 0.88,
	"cloud_projection_bias": 0.35,
	"cloud_band_start": 0.004,
	"cloud_band_end": 0.070,
	"sun_glow": 0.35,
}

var cfg: MapConfig
var data: MapData
var sun: DirectionalLight3D
var env_node: WorldEnvironment
var env: Environment
var sky: Sky
var sky_mat: ShaderMaterial

var time_of_day: float = 8.0 / 24.0
var day: int = 1
var paused: bool = false
var speed: float = 1.0
var night_amount: float = 0.0
## 白昼权重（白天 1、天黑后 0），与 night_amount 是两条独立曲线，见 register_shader()
var day_amount: float = 1.0

var _night_lights: Array[OmniLight3D] = []
var _shader_mats: Array = []       ## [{mat, param, kind}]
var _night_pushed: float = -1.0    ## 上次推给灯光/材质的 night_amount（已量化，-1 = 尚未推送）
var _day_pushed: float = -1.0      ## 同上，day_amount。两条曲线各自变化，必须分别记账：
                                   ## 白天 night_amount 一直是 0，只看它的话 day_amount 涨起来也推不出去

func setup(p_cfg: MapConfig, p_data: MapData) -> void:
	cfg = p_cfg
	data = p_data
	time_of_day = cfg.start_hour / 24.0

	# ---------------- 环境 ----------------
	env_node = WorldEnvironment.new()
	env = Environment.new()
	sky = Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load(SKY_SHADER)
	for k in SKY_CONSTANTS:
		sky_mat.set_shader_parameter(k, SKY_CONSTANTS[k])
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# 环境光：0.6 来自天空（有方向感、随天色变），0.4 用逐时调过的颜色兜底。
	# 天空那部分自带「上蓝下暖」的空间变化，这是固定灰环境光给不了的。
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = AMBIENT_SKY_CONTRIBUTION
	env.ambient_light_color = Color(0.55, 0.56, 0.60)
	env.ambient_light_energy = AMBIENT_ENERGY_DAY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 4.0
	# 环境光遮蔽：树根 / 墙脚 / 山坳的接触阴影全靠它。没有它，模型与地面之间没有
	# 过渡，整片地形看着「飘」在半空 —— 参考项目那边同样按这个理由开着
	env.ssao_enabled = true
	env.ssao_radius = 3.0
	env.ssao_intensity = 1.35
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.25
	# 轻微辉光：让水面高光和天空过渡柔和一点（不开高，否则整体发灰）
	env.glow_enabled = true
	env.glow_intensity = 0.24
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.15
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 420.0
	env.fog_depth_end = 2600.0
	env.fog_density = 1.0
	# 雾对天空的影响从 0.6 降到 0.10：可见天空只有地平线上一条窄带，
	# 0.6 会把那条带整个洗成雾色，蓝天和云都看不见了
	env.fog_sky_affect = 0.10
	# 空气透视：远处的雾带一点天空色，山看起来「在空气里」而不是被一层灰罩住
	env.fog_aerial_perspective = 0.35
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
	_night_pushed = -1.0      # 让下一次 _apply() 重新推送一次（保证新灯与统一公式一致）

## 注册需要跟随昼夜变化的 Shader 材质。
##   kind = "night" —— 推 night_amount（夜间压暗 / 夜间辉光，越夜越大）
##   kind = "day"   —— 推 day_amount（白昼权重，白天 1、天黑后 0）
## 两种曲线不能混用：地面自发光地板要的是 day_amount —— 用 night_amount 反推
## （1 - night_amount）在清晨永远是 1（那时 night_amount 才 0.04），
## 实测会把黎明整片刷亮、近黑像素从 31.6% 掉到 3.2%，天光的层次全没了。
func register_shader(mat: ShaderMaterial, param: String, kind: String = "night") -> void:
	_shader_mats.append({"mat": mat, "param": param, "kind": kind})
	mat.set_shader_parameter(param, night_amount if kind == "night" else day_amount)
	_night_pushed = -1.0
	_day_pushed = -1.0

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
	day_amount = day_f
	# 霞光权重（黄昏 / 黎明共用：太阳高度角在 0.02 附近那一段，日出日落是对称的）。
	# 斜率从 5.0 放宽到 2.2（第七轮 ②）：按 5.0 算，霞光只剩 ±0.14 的高度角窗口 ≈
	# 游戏内 32 分钟 ≈ 现实 2.5 秒，玩家根本看不到晚霞 —— 天空改成着色器之后，
	# 这段时间正是夕阳辉光和暖色地平线最出效果的时候。放宽到 ±0.45 后约 1.7 小时。
	var dusk_f := clampf(1.0 - absf(elev - 0.02) * 2.2, 0.0, 1.0)
	var night_f := clampf(-elev * 3.0 + 0.1, 0.0, 1.0)

	var night_top := Color(0.020, 0.028, 0.070)
	var night_hor := Color(0.050, 0.065, 0.130)
	var day_top := Color(0.190, 0.380, 0.800)
	var day_hor := Color(0.640, 0.760, 0.930)
	var dusk_top := Color(0.300, 0.230, 0.380)
	var dusk_hor := Color(0.960, 0.480, 0.220)

	var top := night_top.lerp(day_top, day_f).lerp(dusk_top, dusk_f * 0.55)
	var hor := night_hor.lerp(day_hor, day_f).lerp(dusk_hor, dusk_f * 0.75)
	var ground_bottom := night_top.lerp(Color(0.12, 0.13, 0.15), day_f)
	var ground_horizon := hor.lerp(Color(0.12, 0.13, 0.15), 0.4)
	# 天空只收**最终色**（本文件已经把昼夜/黄昏插值算完了，见 sky_clouds.gdshader 头部），
	# day_factor 是「云与太阳辉光的白昼权重」，不参与天色本身。
	# 云的可见度用 day_f 而不是「非夜间」：黄昏时云先退场，夜里就不会挂着一片白云。
	sky_mat.set_shader_parameter("sky_top", top)
	sky_mat.set_shader_parameter("sky_horizon", hor)
	sky_mat.set_shader_parameter("ground_horizon", ground_horizon)
	sky_mat.set_shader_parameter("ground_bottom", ground_bottom)
	sky_mat.set_shader_parameter("sky_curve", 0.30 + 0.10 * dusk_f)
	sky_mat.set_shader_parameter("day_factor", day_f)
	sky_mat.set_shader_parameter("dusk_factor", dusk_f)
	# 天空里的太阳方位必须用**天文太阳**算，不能读 sun.global_transform：
	# 天黑了以后 sun.rotation 会被下面那行「当月光用」的覆盖改写成月亮的位置，
	# 照抄的话夕阳辉光会画到月亮上（而且那时 day/dusk 权重已经归零，白算一遍）
	var sun_dir := Vector3(
		cos(deg_to_rad(elev_deg)) * sin(deg_to_rad(yaw_deg)),
		sin(deg_to_rad(elev_deg)),
		cos(deg_to_rad(elev_deg)) * cos(deg_to_rad(yaw_deg)))
	sky_mat.set_shader_parameter("sun_direction", sun_dir)

	# 太阳光强 / 颜色
	sun.light_energy = clampf(elev * SUN_SLOPE + 0.05, 0.0, SUN_MAX)
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
	env.ambient_light_energy = lerpf(AMBIENT_ENERGY_NIGHT, AMBIENT_ENERGY_DAY, day_f)
	env.background_energy_multiplier = lerpf(0.35, 1.0, day_f)
	env.fog_light_color = hor.lerp(Color(0.6, 0.7, 0.85), 0.25)
	env.fog_light_energy = lerpf(0.5, 1.0, day_f)
	env.fog_density = lerpf(1.35, 0.85, day_f)
	env.fog_depth_end = lerpf(1500.0, 2900.0, day_f)
	env.tonemap_exposure = lerpf(1.05, 0.95, day_f)

	# 夜间灯火 + Shader：只依赖 night_amount / day_amount，量化到 1/512 后仅在跨档时
	# 推送。night_amount 一个昼夜的跨度是 0~1，量化后每档约 0.2% —— 肉眼无差，
	# 但省掉了每帧对 18 盏灯和全部材质的 RenderingServer 写入（而且写的都是同一个值）。
	var q := snappedf(night_amount, 1.0 / 512.0)
	var q_day := snappedf(day_amount, 1.0 / 512.0)
	var night_changed := not is_equal_approx(q, _night_pushed)
	var day_changed := not is_equal_approx(q_day, _day_pushed)
	if night_changed:
		_night_pushed = q
		var lights_on := q > 0.28
		for l in _night_lights:
			if l == null:
				continue
			l.visible = lights_on
			l.light_energy = maxf(0.0, q * 1.8)
	if night_changed or day_changed:
		_day_pushed = q_day
		for e in _shader_mats:
			e.mat.set_shader_parameter(e.param, q if e.kind == "night" else q_day)
