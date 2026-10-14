## =============================================================================
##  MapConfig —— 全部生成参数集中在这里（@export 暴露，可在检查器里调）
##  换一个 map_seed 会得到完全不同、但依然合理的地图。
## =============================================================================
class_name MapConfig
extends Resource

@export_group("通用")
## 统一随机种子：所有子系统的随机数都由它派生（保证可复现）
@export var map_seed: int = 20250929
## 地图尺寸（世界单位，米）；地图范围 = [0, map_size] x [0, map_size]
@export var map_size: float = 1024.0
## 高度图分辨率（采样点数，必须为奇数）；间距 = map_size / (res-1)
## 上限 2049 是为 4096 m 图留的：4096 m 想保持 2 m 间距就需要 2049 个采样点
## （内存 2049² × 4 B ≈ 16.8 MB）。1024 m 图仍用 513（2 m 间距），换尺寸之前行为不变。
@export_range(129, 2049, 2) var heightmap_res: int = 513

@export_group("地形 · 地貌")
@export var sea_level: float = 0.0
## 大陆遮罩中心（归一化 UV）—— 偏向东北，使西/南多海岸线
@export var continent_center: Vector2 = Vector2(0.60, 0.36)
## 大陆半径（归一化 UV），越大陆地越大
@export var continent_radius: Vector2 = Vector2(0.70, 0.64)
@export var mountain_amplitude: float = 168.0   ## 北部雪山最大高度
@export var hill_amplitude: float = 26.0        ## 中部丘陵起伏
@export var desert_amplitude: float = 11.0      ## 东部沙丘高度
@export var detail_amplitude: float = 2.6       ## 高频细节
@export var snow_line: float = 118.0            ## 雪线
@export var mountain_line: float = 88.0         ## 岩石线
@export var ridge_sharpness: float = 1.55       ## 山脊锐度（对 ridged 噪声取幂）

@export_group("地形 · 水系")
@export var river_count: int = 2
@export var river_width: float = 11.0           ## 河道半宽（米）
@export var river_depth: float = 7.0            ## 下切深度（米）
@export var river_step: float = 7.0             ## 河道推进步长
@export var lake_count: int = 1
@export var lake_radius: float = 46.0
@export var lake_depth: float = 9.0
@export var ford_count_per_river: int = 2       ## 每条河上的浅滩数量

@export_group("植被 · 森林")
@export var vegetation_enabled: bool = true
@export var conifer_count: int = 2600
@export var broadleaf_count: int = 3200
@export var cactus_count: int = 700
@export var deadtree_count: int = 420
@export var rock_count: int = 1500
@export var forest_noise_freq: float = 0.0075   ## 森林成片噪声频率（越低林子越大片）
@export var forest_threshold: float = 0.52      ## 高于该值才长树
@export var max_slope_veg: float = 0.46         ## 植被可生长的最大坡度

@export_group("定居点")
@export var faction_count: int = 3
@export var towns_per_faction: int = 2
@export var villages_per_faction: int = 3
@export var min_settlement_distance: float = 96.0
@export var road_width: float = 4.5             ## 道路半宽（米）
@export var flatten_radius: float = 26.0        ## 定居点地基平整半径

@export_group("部队")
@export var ai_party_count: int = 14
@export var player_speed: float = 46.0          ## 基准速度（米/秒，战略地图尺度）
@export var ai_speed: float = 34.0
@export var bandit_vision: float = 92.0         ## 强盗发现玩家的距离
@export var encounter_distance: float = 7.0

@export_group("相机")
@export var cam_min_height: float = 20.0
@export var cam_max_height: float = 400.0
@export var cam_default_height: float = 90.0
@export var cam_pitch_near: float = 26.0        ## 最近时的俯角（更平视）
@export var cam_pitch_far: float = 72.0         ## 最远时的俯角（更俯瞰）
@export var cam_pan_speed: float = 190.0        ## WASD 平移速度（随高度缩放）
@export var cam_rotate_speed: float = 0.006
@export var strategic_view_height: float = 275.0 ## 超过该高度进入战略视图

@export_group("时间与氛围")
@export var day_length_seconds: float = 120.0   ## 游戏内 1 天 = 现实 2 分钟
@export var start_hour: float = 8.0
@export var fog_of_war: bool = true
@export var fog_reveal_radius: float = 118.0


func make_rng(tag: String) -> RandomNumberGenerator:
	## 用 (种子, 标签) 派生独立随机流：子系统互不干扰，但整体可复现
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	rng.state = hash(str(map_seed) + "|" + tag) | 1
	return rng
