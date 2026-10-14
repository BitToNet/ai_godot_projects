## =============================================================================
##  MaterialFactory —— 4 个世界着色器材质的唯一构造点
##
##  从 Main.gd 的 _make_materials() 原样搬出：材质、shader 路径、参数名与
##  **设置顺序**都保持一致。它是纯函数式的（只读 cfg 与 data.splat_texture，
##  不碰任何 RNG），所以搬动它不可能改变生成指纹。
##
##  为什么值得单独一个类：这四个材质是「大地图长什么样」的全部开关
##  （昼夜把 night_amount / night_glow 注册进去、迷雾往里塞 fog_map），
##  以前和造城堡、播种植被混在一个 850 行的文件里。
##
##  第七轮 ② 起，地形的两张**无缝细节贴图**也在这里生成（见文件末）：
##  它们是「地形长什么样」的一部分，而且与地图尺寸、种子完全无关，所以整局只做一次。
## =============================================================================
class_name MaterialFactory
extends RefCounted

# ---------- 地形细节贴图参数（照参考项目 world_map.gd 的推导，别凭感觉改）----------
# 那边的尺度推导：默认视距下一个屏幕像素约覆盖 0.10 世界单位。本项目实测同为
# 0.119 世界单位/像素（1600×900、相机高 90 m、俯角 55°、fov 52），所以参数可以照搬：
#   贴图 256px 的环面周长 = 256，特征数 ≈ 256 × freq，
#   特征世界尺寸 = TILE / 特征数。
# 细节特征要占 6~14 像素才看得见 —— 也就是 0.7~1.7 世界单位：
#   detail: freq 0.035 → 9 个特征 / 13 m 的一份 → 每个 1.44 m ≈ 12 像素
#   normal: freq 0.055 → 14 个特征 / 9 m 的一份 → 每个 0.64 m ≈ 5 像素
const DETAIL_TILE_A := 9.0          ## 法线（凹凸）用：一份贴图覆盖 9 m
const DETAIL_TILE_B := 13.0         ## 细节反照率用：13 m。与 A 取不整除，避免叠出规则图案
const DETAIL_TILE_MACRO := 70.0     ## 同一张贴图放大成大色斑的那一层（~70 m 一份）
const DETAIL_TEX_SIZE := 256
const DETAIL_FREQ := 0.035
const DETAIL_SEED := 4421
## 灰度细节的取值区间：均值 ~1.0，MUL 混合不会整体压暗。
## **区间映射在做 shader 里**（detail_lo / detail_hi 两个 uniform），贴图里存的是
## 原始高度 0~1 —— 8 位无符号通道存不下 1.0 以上的值，直接存 [0.60, 1.40] 会被
## 静默钳到 1.0：提亮那一半全丢，整张图反而整体压暗 4%
## （tools/visual_check.gd 的值域断言就是这么把这个坑挖出来的）。
const DETAIL_LO := 0.60
const DETAIL_HI := 1.40
const NORMAL_FREQ := 0.055
const NORMAL_SEED := 9137
const NORMAL_STRENGTH := 1.0

## 地面自发光的「地板」能量（参考项目 atmosphere.ground_emission）。
## 它不进光照计算，所以阴影 / 坡向明暗全保留，只是把最暗处从死黑抬到微微透光；
## 夜里由 shader 用 night_amount 自动归零，否则整张地图会自己发亮。
const GROUND_EMISSION_COLOR := Color(0.13, 0.15, 0.12)
const GROUND_EMISSION_ENERGY := 0.60

## 底色饱和度补偿：天空环境光偏蓝，会把地表底色洗掉一档（实测正午整屏
## 平均饱和度从 0.40 掉到 0.35）。只补 albedo，不动光照，夜里不会跟着变艳。
const ALBEDO_SATURATION := 1.10

## 无缝贴图的进程内缓存：内容与地图尺寸 / 种子完全无关，整局只生成一次。
## （settlement_check 之类一次建多个世界的自检也只付一次生成成本。）
static var _tex_cache: Dictionary = {}

## 地形（splat 混合 + 细节贴图 + 昼夜 + 迷雾）
var terrain: ShaderMaterial
## 建筑（城堡 / 城镇 / 村庄 / 桥梁共用）
var settlement: ShaderMaterial
## 部队模型（与建筑同 shader，但独立材质：昼夜亮度要分别调）
var party: ShaderMaterial
## 植被（MultiMesh 批量实例用）
var vegetation: ShaderMaterial

func build(cfg: MapConfig, data: MapData) -> void:
	terrain = ShaderMaterial.new()
	terrain.shader = load("res://shaders/terrain.gdshader")
	terrain.set_shader_parameter("splat_map", data.splat_texture)
	terrain.set_shader_parameter("map_size", cfg.map_size)
	terrain.set_shader_parameter("sea_level", cfg.sea_level)
	terrain.set_shader_parameter("snow_line", cfg.snow_line)
	terrain.set_shader_parameter("mountain_line", cfg.mountain_line)
	terrain.set_shader_parameter("night_amount", 0.0)
	# 第七轮 ②：细节贴图 + 自发光地板 + 底色饱和度
	terrain.set_shader_parameter("detail_map", seamless_detail_texture())
	terrain.set_shader_parameter("detail_normal", seamless_normal_texture())
	terrain.set_shader_parameter("detail_tile_a", DETAIL_TILE_A)
	terrain.set_shader_parameter("detail_tile_b", DETAIL_TILE_B)
	terrain.set_shader_parameter("detail_tile_macro", DETAIL_TILE_MACRO)
	terrain.set_shader_parameter("detail_lo", DETAIL_LO)
	terrain.set_shader_parameter("detail_hi", DETAIL_HI)
	terrain.set_shader_parameter("normal_strength", NORMAL_STRENGTH)
	terrain.set_shader_parameter("ground_emission_color", GROUND_EMISSION_COLOR)
	terrain.set_shader_parameter("ground_emission_energy", GROUND_EMISSION_ENERGY)
	terrain.set_shader_parameter("albedo_saturation", ALBEDO_SATURATION)

	settlement = ShaderMaterial.new()
	settlement.shader = load("res://shaders/settlement.gdshader")
	settlement.set_shader_parameter("map_size", cfg.map_size)
	settlement.set_shader_parameter("night_glow", 0.0)

	party = ShaderMaterial.new()
	party.shader = load("res://shaders/settlement.gdshader")
	party.set_shader_parameter("map_size", cfg.map_size)
	party.set_shader_parameter("night_glow", 0.0)

	vegetation = ShaderMaterial.new()
	vegetation.shader = load("res://shaders/vegetation.gdshader")
	vegetation.set_shader_parameter("map_size", cfg.map_size)
	vegetation.set_shader_parameter("night_amount", 0.0)

# =========================================================
#  无缝细节贴图（灰度细节 + 法线）
# =========================================================

## 灰度细节图：贴图里存的是**原始高度 0~1**，[DETAIL_LO, DETAIL_HI] 的映射在 shader 里做。
## 为什么不直接把 [0.60, 1.40] 烘进 8 位贴图：8 位无符号通道存不下 1.0 以上的值，
## `lerpf(0.60, 1.40, h)` 一旦超过 1.0 就被钳成 1.0 —— 提亮那一半全丢，均值从 1.0 掉到 0.958，
## 整张地图被悄悄压暗一档（这是 tools/visual_check.gd 的值域断言抓出来的真事故）。
static func seamless_detail_texture() -> ImageTexture:
	if _tex_cache.has("detail"):
		return _tex_cache["detail"]
	var h := _seamless_height(DETAIL_TEX_SIZE, DETAIL_SEED, DETAIL_FREQ)
	var img := Image.create(DETAIL_TEX_SIZE, DETAIL_TEX_SIZE, true, Image.FORMAT_RGB8)
	for y in DETAIL_TEX_SIZE:
		for x in DETAIL_TEX_SIZE:
			var g := h[y * DETAIL_TEX_SIZE + x]
			img.set_pixel(x, y, Color(g, g, g))
	# 必须生成 mipmap：这份贴图在世界里 1.4 m 一份，拉到几百米外就是一片摩纹，
	# 没有 mipmap 只能靠 shader 里的 lod_fade 一刀切掉（中距离仍然会闪）
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["detail"] = tex
	return tex

## 由无缝高度场中心差分生成法线贴图（切线空间，+Z 朝外）
static func seamless_normal_texture() -> ImageTexture:
	if _tex_cache.has("normal"):
		return _tex_cache["normal"]
	var size := DETAIL_TEX_SIZE
	var h := _seamless_height(size, NORMAL_SEED, NORMAL_FREQ)
	var img := Image.create(size, size, true, Image.FORMAT_RGB8)
	for y in size:
		var yp := (y + 1) % size
		var ym := (y + size - 1) % size
		for x in size:
			var xp := (x + 1) % size
			var xm := (x + size - 1) % size
			var nrm := Vector3(
				(h[y * size + xm] - h[y * size + xp]) * NORMAL_STRENGTH,
				(h[ym * size + x] - h[yp * size + x]) * NORMAL_STRENGTH,
				1.0).normalized()
			img.set_pixel(x, y, Color(nrm.x * 0.5 + 0.5, nrm.y * 0.5 + 0.5, nrm.z * 0.5 + 0.5))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["normal"] = tex
	return tex

## 在 3D 环面上采样噪声，得到 u/v 两个方向都无缝的二维高度场。
##
## 为什么不直接用 FastNoiseLite 的 2D 噪声：它铺开会看到网格状接缝，而接缝本身
## 又是一圈规则线条 —— 等于把刚消掉的「方块感」换个形式加回来。把采样点映射到
## 环面（两个方向都首尾相接）就天然无缝了。
static func _seamless_height(size: int, noise_seed: int, freq: float) -> PackedFloat32Array:
	var fn := FastNoiseLite.new()
	fn.seed = noise_seed
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq
	fn.fractal_octaves = 4
	fn.fractal_lacunarity = 2.1

	var out := PackedFloat32Array()
	out.resize(size * size)
	var big_r := float(size) / TAU
	var small_r := big_r * 0.62
	for y in size:
		var v := TAU * float(y) / float(size)
		var cv := cos(v)
		var sv := sin(v)
		for x in size:
			var u := TAU * float(x) / float(size)
			var rr := big_r + small_r * cv
			var nz := fn.get_noise_3d(rr * cos(u), rr * sin(u), small_r * sv)
			out[y * size + x] = 0.5 + 0.5 * nz
	return out
