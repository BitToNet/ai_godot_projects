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
## =============================================================================
class_name MaterialFactory
extends RefCounted

## 地形（splat 混合 + 昼夜 + 迷雾）
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