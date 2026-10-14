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
## 第六轮 ③：默认世界从 1024 m 换成 4096 m（4 倍边长 / 16 倍面积）。凡是**绝对米数**的世界生成
## 参数都不再写死，一律以 `SIZE_REF`（1024 m，旧世界）为 1× 参照按尺寸推导（见文件末尾的推导函数）。
## 一键门禁靠环境变量把尺寸压回小图（`WARBAND_MAP_SIZE=1024`），不必为测试另存一份配置。
@export var map_size: float = 4096.0
## 高度图分辨率（采样点数，必须为奇数）；间距 = map_size / (res-1)
## 默认值按「与地形网格同分辨率」推导（`scaled_heightmap_res`）：1024 m → 513（2 m 间距）、
## 4096 m → 1025（4 m 间距）。上限 2049 是留给「4 倍图仍按 2 m 间距」的选项（内存 16.8 MB），
## 但那相对地形网格是 2× 过采样，高度场阶段实测要多花 4 倍时间（ROADMAP §16.6），所以不取。
@export_range(129, 2049, 2) var heightmap_res: int = 1025

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


# =============================================================== 尺寸推导
## 第六轮「尺寸适配」的**唯一参照**：1024 m 是换世界之前的世界，倍率 1.0。
## 规矩：凡是绝对米数的量（河道宽度、渡口数量、植被预算……）都要问一句
## 「它在 4 倍图上还成比例吗」，然后按下面的倍率推导；不要再往代码里塞字面量。
const SIZE_REF := 1024.0

func _init() -> void:
	# 一键门禁必须继续跑得动：允许用环境变量把世界压回小图（WARBAND_MAP_SIZE=1024），
	# 场景 / 资源都不必为「测试尺寸」另存一份。显式给 WARBAND_HM_RES 时以它为准。
	var ms := OS.get_environment("WARBAND_MAP_SIZE")
	if ms != "" and ms.is_valid_float() and ms.to_float() > 0.0:
		map_size = ms.to_float()
		heightmap_res = scaled_heightmap_res()
	var hr := OS.get_environment("WARBAND_HM_RES")
	if hr != "" and hr.is_valid_int():
		heightmap_res = int(hr)

## 尺寸倍率（1.0 = 1024 m 旧世界；4096 m → 4.0）。线性量的放大倍数。
func size_scale() -> float:
	return map_size / SIZE_REF

## 面积倍率（1.0 = 旧世界；4096 m → 16.0）。密度型预算（植被棵数）用它。
func area_scale() -> float:
	var s := size_scale()
	return s * s

## 高度图分辨率：与**地形网格同分辨率**。地形分块 = max(128, map_size/16) 米、每块 64 格
## （§16.2 的推导），所以格距 = max(128, map_size/16)/64；高度图间距取同一个值：
## 1024 m → 2 m → 513 点；4096 m → 4 m → 1025 点。夹到 [129, 2049] 的奇数。
func scaled_heightmap_res() -> int:
	var chunk := maxf(128.0, map_size / 16.0)
	var quad := chunk / 64.0
	var n := int(round(map_size / quad)) + 1
	n = clampi(n, 129, 2049)
	if n % 2 == 0:
		n += 1
	return n

## 河道半宽（米）：基准 11 m（全宽 22 m）按尺寸线性放大 —— 4 倍图上 22 m 宽的河只占地图宽度的
## 0.5%，会退化成「地图上的细线」，道路不再需要桥（ROADMAP §16.7 实测：4096 m 下桥梁 7 → 0）。
func river_half_width() -> float:
	return river_width * size_scale()

## 渡口数量：河道长度随尺寸线性增长，渡口按同倍率增加才能保持**渡口间距**不变
## （渡口间距是玩法尺度：它决定「绕过去」要付多少代价）。
func fords_per_river() -> int:
	return maxi(1, int(round(float(ford_count_per_river) * size_scale())))

## 湖泊半径（米）：半径按尺寸线性放大 ⇒ 湖泊占地图的**面积比例**不变
## （面积 ∝ r² 长 16 倍、地图面积也长 16 倍，所以 lake_count 不必跟着变）。
func lake_radius_m() -> float:
	return lake_radius * size_scale()

## 定居点最小间距（米）：这是**玩法尺度**的量（两个村子走多久），不是地图比例，
## 所以按尺寸线性放大，让 4 倍图上的定居点铺开得像旧世界一样。
func min_settlement_distance_m() -> float:
	return min_settlement_distance * size_scale()

## 定居点地基平整半径（米）：同上，按尺寸线性放大，否则 4 倍图上的地基会变成小坑。
func flatten_radius_m() -> float:
	return flatten_radius * size_scale()
