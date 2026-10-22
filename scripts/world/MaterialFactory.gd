## =============================================================================
##  MaterialFactory —— 4 个世界着色器材质的唯一构造点
##
##  从 Main.gd 的 _make_materials() 原样搬出，至今仍是「大地图长什么样」的全部开关：
##  昼夜把 night_amount / night_glow 注册进去、迷雾往里塞 fog_map。
##
##  ---- 第十五轮：全盘迁移到 NPR（卡通渲染 / 微缩手办）----
##  这一版删掉了旧版的**两张无缝细节贴图**（灰度细节 + 法线凹凸）与地面自发光地板：
##  它们的作用是「把大色块打碎成写实质感」，与目标风格正好相反。现在地形靠
##  高饱和色带 + 面着色 + 三阶硬光影成立，一片 1.4 m 的颗粒贴图只会把它拉回塑料感。
##  删除的同时也带走了 3 个常量与 1 个 4 倍频噪声生成器 —— 开局少一次 256² 的
##  GDScript 逐像素循环（实测 ~120 ms）。
##
##  三条统一约定（与 scripts/world/ToonStyle.gd 一致）：
##   1. 所有世界材质都吃同一张 3 阶阶梯贴图 gradient_map；
##   2. 闭合几何体（建筑 / 部队 / 植被 / 真模型）挂反向外壳描边 next_pass；
##      地形是开放曲面，没有背面可膨胀，它的轮廓靠面着色与海岸带色彩（见 terrain.gdshader）；
##   3. 参数一律**显式赋初值**：Godot 里没赋过的 uniform，get_shader_parameter() 返回 null，
##      shader 会静默用默认值 —— tools/visual_check.gd 的整节断言就是为这条服务的。
##
##  纯函数式：只读 cfg 与 data.splat_texture，不碰任何 RNG，所以搬动不影响生成指纹。
## =============================================================================
class_name MaterialFactory
extends RefCounted

## 沙滩带宽（米）：水陆交界的柠檬黄带子。6 m 在默认视距下约 50 像素，是一条清楚的边。
const BEACH_WIDTH := 6.0
## 陡坡转岩石的坡度阈值（1 - N.y）：0.42 ≈ 32.5°
const SLOPE_ROCK := 0.42

## 势力染色强度：mix(vec3(1.0), tint, k) 里的 k。乘色只改色相、不改明暗，
## 调 0.0 就等于完全不染 —— 是个可以放心拧的旋钮，不是结构。
## 与 shaders/settlement_model.gdshader 的默认值写同一个数：万一忘了赋值，
## 退化成 shader 默认值也不会突变。tools/asset_check.gd 会断言这个 uniform 被赋过值。
const MODEL_TINT_STRENGTH := 0.22
## 真模型图集的色阶数：5 档刚好把写实明暗压成手绘平涂，又保留窗框/木纹的层次
const MODEL_POSTERIZE := 5.0

## 真模型材质：**每种势力一个**，该势力所有建筑的 MeshInstance3D 共用。
## 为什么能共用：KayKit 这批模型内嵌同一张图集（asset_check 用内容哈希钉住这条前提），
## 所以材质只有「势力染色」一个变量 —— 3 个势力 = 3 个 ShaderMaterial。
static var _model_mats: Dictionary = {}
## 图集贴图（4 个模型内嵌的是同一张，取第一个能拿到的即可；拿不到就是 null）
static var _model_atlas: Texture2D = null

## 地形（色带 + 面着色 + 昼夜 + 迷雾）
var terrain: ShaderMaterial
## 建筑（城堡 / 城镇 / 村庄 / 桥梁共用）
var settlement: ShaderMaterial
## 部队模型（与建筑同 shader，但独立材质：昼夜亮度要分别调）
var party: ShaderMaterial
## 植被（MultiMesh 批量实例用）
var vegetation: ShaderMaterial

func build(cfg: MapConfig, data: MapData) -> void:
	var ramp := ToonStyle.gradient_map()

	terrain = ShaderMaterial.new()
	terrain.shader = load("res://shaders/terrain.gdshader")
	terrain.set_shader_parameter("gradient_map", ramp)
	terrain.set_shader_parameter("splat_map", data.splat_texture)
	terrain.set_shader_parameter("map_size", cfg.map_size)
	terrain.set_shader_parameter("sea_level", cfg.sea_level)
	# 岩石线 / 雪线是**高度场实测分位数**（岩石带 = 最高的 12% 陆地、雪 = 最高的 4%），
	# 而不是绝对高度：分位数口径换 1024/2048/4096 都成立（第七轮 ②）。
	terrain.set_shader_parameter("snow_line", cfg.snow_line_of(data.gen))
	terrain.set_shader_parameter("mountain_line", cfg.rock_line_of(data.gen))
	terrain.set_shader_parameter("beach_width", BEACH_WIDTH)
	terrain.set_shader_parameter("slope_rock", SLOPE_ROCK)
	terrain.set_shader_parameter("night_amount", 0.0)
	terrain.set_shader_parameter("day_amount", 1.0)
	# 调色板：**逐条**显式赋值（默认值只是兜底，门禁会比对两处是否一致）
	_apply_terrain_palette(terrain)

	settlement = ShaderMaterial.new()
	settlement.shader = load("res://shaders/settlement.gdshader")
	settlement.set_shader_parameter("gradient_map", ramp)
	settlement.set_shader_parameter("map_size", cfg.map_size)
	settlement.set_shader_parameter("night_glow", 0.0)
	ToonStyle.attach_outline(settlement, ToonStyle.OUTLINE_W_SETTLEMENT)

	party = ShaderMaterial.new()
	party.shader = load("res://shaders/settlement.gdshader")
	party.set_shader_parameter("gradient_map", ramp)
	party.set_shader_parameter("map_size", cfg.map_size)
	party.set_shader_parameter("night_glow", 0.0)
	ToonStyle.attach_outline(party, ToonStyle.OUTLINE_W_PARTY)

	vegetation = ShaderMaterial.new()
	vegetation.shader = load("res://shaders/vegetation.gdshader")
	vegetation.set_shader_parameter("gradient_map", ramp)
	vegetation.set_shader_parameter("map_size", cfg.map_size)
	vegetation.set_shader_parameter("night_amount", 0.0)
	ToonStyle.attach_outline(vegetation, ToonStyle.OUTLINE_W_VEGETATION)

## 地形调色板（与 shaders/terrain.gdshader 的同名 uniform 默认值逐位一致）
static func _apply_terrain_palette(m: ShaderMaterial) -> void:
	m.set_shader_parameter("color_seabed", ToonStyle.C_SEABED)
	m.set_shader_parameter("color_sand", ToonStyle.C_SAND)
	m.set_shader_parameter("color_grass", ToonStyle.C_GRASS)
	m.set_shader_parameter("color_grass_dark", ToonStyle.C_GRASS_DARK)
	m.set_shader_parameter("color_rock", ToonStyle.C_ROCK)
	m.set_shader_parameter("color_rock_dark", ToonStyle.C_ROCK_DARK)
	m.set_shader_parameter("color_snow", ToonStyle.C_SNOW)
	m.set_shader_parameter("color_road", ToonStyle.C_ROAD)
	m.set_shader_parameter("color_desert", ToonStyle.C_DESERT)

# =========================================================
#  真模型材质（第③批-2）
# =========================================================

## 取模型图集贴图。清单里所有模型内嵌同一张（由 asset_check 比对内容哈希保证），
## 所以这里「取第一个能拿到的」是安全的；一个都拿不到就是 null（门禁会拦下来）。
static func model_atlas() -> Texture2D:
	if _model_atlas != null:
		return _model_atlas
	for k in AssetManifest.model_keys():
		var t := ModelLibrary.albedo_texture(k)
		if t != null:
			_model_atlas = t
			return _model_atlas
	return null

## 势力染色材质（按颜色缓存）。map_size / fog_enabled / night_glow / gradient_map
## 都**显式赋初值**（理由见文件头）。asset_check 会逐条断言这里赋过值。
static func model_material(cfg: MapConfig, tint: Color) -> ShaderMaterial:
	var key := tint.to_html(false)
	if _model_mats.has(key):
		return _model_mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/settlement_model.gdshader")
	m.set_shader_parameter("albedo_tex", model_atlas())
	m.set_shader_parameter("gradient_map", ToonStyle.gradient_map())
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("tint_strength", MODEL_TINT_STRENGTH)
	m.set_shader_parameter("posterize", MODEL_POSTERIZE)
	m.set_shader_parameter("night_glow", 0.0)
	m.set_shader_parameter("map_size", cfg.map_size)
	m.set_shader_parameter("fog_enabled", 0.0)
	ToonStyle.attach_outline(m, ToonStyle.OUTLINE_W_SETTLEMENT)
	_model_mats[key] = m
	return m

## 流水线要遍历它们把 night_glow（昼夜）与 fog_map / fog_enabled（迷雾）注册进去。
## 顺序 = 首次创建顺序（势力顺序，稳定），不依赖字典哈希。
static func model_materials() -> Array:
	return _model_mats.values()

## 自检清场：把真模型材质也清掉，避免一个进程里跑两个世界时串味
static func clear_model_materials() -> void:
	_model_mats.clear()
	_model_atlas = null
