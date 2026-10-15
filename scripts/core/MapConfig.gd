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
## 第七轮 ①：默认世界 **4096 → 2048 → 1024 m**（用户本轮选定：地图规模前期不用特别大）。
## 三档都实测过，退到 1024 m 不是"保守"，而是三条硬理由（tools/perf_probe.gd / tmp 探针）：
##  1) **运行期**：4096 m 下 100 支部队 + 513² 粗栅格 ⇒ 单次粗栅格 A* 0.2~1.5 s，队列契约
##     「每帧至少完成一个」把帧时间钉在一次 A* 上（idle p95 1070 ms / max 1495 ms）。
##     机制已修（见 AIParty / PathQueue），修后 idle 1.3 ms，但**单次搜索**仍要 0.2~1.5 s：
##     4096 m 行军期还有 11 帧 >100 ms（max 1480 ms）—— 那要改粗栅格格距或分层寻路，
##     属于会改路径结果的改动，不在本批里。
##  2) **世界设计**：2048 m（同一种子）下两条河缩在北边一条带里，18 个定居点离河最近 113 m、
##     中位 743 m ⇒ **道路完全不碰水面**（1935 个道路采样点 0 个在水里）、**桥梁 0 座**、
##     渡口形同虚设；1024 m 下河与定居点交织（最近 8 m、中位 161 m）⇒ 7 座桥，渡口/桥梁都是玩法元素。
##     「把地图放大」本身会稀释水系与聚落的关系，这属于地图设计（Round B）的课题。
##  3) **守护范围**：出货世界此前与门禁世界（`WARBAND_MAP_SIZE=1024`）**不是同一个世界**，
##     所以出货配置零确定性守护（PLAN §D.3 重要发现 A）。默认回到 1024 m 之后，
##     出货世界**就是**生成指纹 / 规模基线 / 一键门禁覆盖的那个世界。
## 尺寸推导的定式（SIZE_REF / size_scale）一个字都没删：`WARBAND_MAP_SIZE=2048 / 4096`
## 仍可显式跑大图，`tools/map_size_check.gd` 里两套口径（默认 1024 / TARGET 4096）都在门禁里。
@export var map_size: float = 1024.0
## 高度图分辨率（采样点数，必须为奇数）；间距 = map_size / (res-1)
## 默认值按「与地形网格同分辨率」推导（`scaled_heightmap_res`）：1024 m → 513（2 m 间距）、
## 2048 m → 1025（2 m 间距）、4096 m → 1025（4 m 间距，块边长到顶 256 m）。
## 改 `map_size` 时必须同步改这里（编译期默认值不会自动跟着推导函数走；走环境变量
## `WARBAND_MAP_SIZE` 时 `_init()` 会自动同步）。
## 上限 2049 是留给「4 倍图仍按 2 m 间距」的选项（内存 16.8 MB），
## 但那相对地形网格是 2× 过采样，高度场阶段实测要多花 4 倍时间（ROADMAP §16.6），所以不取。
@export_range(129, 2049, 2) var heightmap_res: int = 513

@export_group("地形 · 地貌")
@export var sea_level: float = 0.0
## 大陆遮罩中心（归一化 UV）—— 偏向东北，使西/南多海岸线
@export var continent_center: Vector2 = Vector2(0.60, 0.36)
## 大陆半径（归一化 UV），越大陆地越大
@export var continent_radius: Vector2 = Vector2(0.70, 0.64)
@export var mountain_amplitude: float = 62.0    ## 显式山脉带的最高抬升（第七轮 ②：168 → 62）
@export var hill_amplitude: float = 17.0        ## 中部丘陵起伏（26 → 17，"底噪只负责质感"）
@export var base_amplitude: float = 13.0        ## 大陆缓坡基底（17 → 13）
@export var desert_amplitude: float = 8.0       ## 东部沙丘高度（11 → 8）
@export var detail_amplitude: float = 2.0       ## 高频细节（2.6 → 2.0）
## 雪线 / 岩石线：**由高度场实测分位数覆盖**（HeightmapGenerator 生成后写回，见下面的
## `rock_line_of()` / `snow_line_of()`）。这里保留的是「拿不到实测值时的兜底」，
## 也就是参考项目那套绝对高度常数的位置 —— 但它的图是固定 468 m，
## 我们要跑 1024/2048/4096 三种尺寸且不能重配阈值，所以只能用分位数：
## 绝对高度阈值一换图就会整体变成岩石或整体不变成岩石（旧值 88/118 m 在 1024 m 图上
## 只覆盖 5.5% / 1.1% 陆地 —— 等于雪和裸岩几乎看不见，这是 ② 批要修的观感问题之一）。
@export var snow_line: float = 118.0            ## 雪线兜底值
@export var mountain_line: float = 88.0         ## 岩石线兜底值
@export var ridge_sharpness: float = 1.55       ## 山脊锐度（对 ridged 噪声取幂，只做山体内部质感）
## 高度场平滑：分隔式盒式模糊，横一遍 + 纵一遍算一遍，叠 smooth_passes 遍 ≈ 高斯。
## 参考项目 6 遍 × 半径 2 把平均坡度从 47.4° 压到 12.5°、≥45° 悬崖格 54.2% → 1.4%。
## **必须在聚落压平之前做**，否则平台会被糊掉（本工程聚落压平在 generate() 之后，天然满足）。
@export var smooth_passes: int = 3
@export var smooth_radius_m: float = 5.0        ## 单遍模糊半径（米），按尺寸不缩放

## 显式山脉带：线段 + 宽度 + 高度倍数。取代"噪声堆山"。
## 参考项目 docs/大地图设计.md §14.3-14.4 的实测结论：**噪声天生到处都有高频起伏**，
## 无论怎么配比都会在整张图撒满尖峰，不可能出现「大片平原 + 几条山脉」这种结构 ——
## 这不是参数问题，是方法问题。它的改法是把山脉写成显式线段带：
## 点到线段距离 < width 时按 smoothstep(width, width*0.30, dist) 抬升，
## **宽 = 缓坡、高 = 山高，两个旋钮独立** —— 这是噪声做不到的。
## 坐标用归一化 UV（0~1），换图不用重配；表是常量、不使用 RNG，
## 所以不改变随机数抽取顺序（高度场本身变化 → 指纹变化，属第七轮 ② 的刻意重基线）。
func mountain_ranges() -> Array:
	var s := map_size
	return [
		{"from": Vector2(0.04, 0.22), "to": Vector2(0.46, 0.08), "width": 0.145 * s, "height": 0.85},
		{"from": Vector2(0.26, 0.05), "to": Vector2(0.88, 0.24), "width": 0.175 * s, "height": 1.00},
		{"from": Vector2(0.08, 0.46), "to": Vector2(0.44, 0.60), "width": 0.105 * s, "height": 0.52},
		{"from": Vector2(0.70, 0.50), "to": Vector2(0.97, 0.78), "width": 0.095 * s, "height": 0.58},
	]

## 内海 / 海湾：显式圆形盆地（inner 半径内是水，outer 外无影响，之间 smoothstep）。
## 参考项目用 3 个 sea_basins 把「圆盘大陆 + 分形噪声海岸」变成有海湾、半岛的形状。
func sea_basins() -> Array:
	var s := map_size
	return [
		{"center": Vector2(0.155, 0.120), "inner": 0.085 * s, "outer": 0.235 * s},
		{"center": Vector2(0.905, 0.415), "inner": 0.075 * s, "outer": 0.215 * s},
		{"center": Vector2(0.330, 0.945), "inner": 0.065 * s, "outer": 0.195 * s},
	]

## 岩石线：优先用高度场实测分位数（生成后写回），拿不到才用 @export 兜底
func rock_line_of(gen) -> float:
	if gen != null and gen.h_rock_line > -1e8:
		return gen.h_rock_line
	return mountain_line

## 雪线：同上
func snow_line_of(gen) -> float:
	if gen != null and gen.h_snow_line > -1e8:
		return gen.h_snow_line
	return snow_line

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
@export var conifer_count: int = 8000     ## 第七轮 ②：2600 → 8000（参考项目"细节信息量靠装饰物撑"）
@export var broadleaf_count: int = 10000    ## 3200 → 10000
@export var cactus_count: int = 1600
@export var deadtree_count: int = 1000
@export var rock_count: int = 3200
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
@export var ai_party_count: int = 14            ## **1024 m 基准值**（旧世界 14 支）；4096 m 由 party_count() 推到 100
@export var player_speed: float = 46.0          ## 基准速度（米/秒，战略地图尺度；**不按尺寸推导**，见下）
@export var ai_speed: float = 34.0
@export var bandit_vision: float = 92.0         ## 强盗发现玩家的距离（1024 m 基准值，按尺寸推导）
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


# ============================================== 尺寸推导：玩法「视觉尺度」与遭遇率
## 第六轮决定（用户选定）：**看得见的尺度跟着地图走，节奏（速度）不跟着走**。
## - 视觉尺度（相机高度/平移速度/战略视图阈值/雾半径/视野半径）按 size_scale 线性放大：
##   它们是「能看多远」，缩了就等于把 4 倍图当成 1/16 的窗口在看。
## - 速度（player_speed / ai_speed）**故意不放大**：横穿 4096 m 要 89 s（旧世界 22 s），
##   这是「地图更大」的手感，而不是「人更快」；要改也是独立的节奏调参，不是尺寸推导。
## - encounter_distance 同样不放大：它是**模型接触距离**，模型本身没有放大。
## 老规矩：1024 m 下全部逐位回落到旧常量，所以小图（门禁）行为不变。
func cam_min_height_m() -> float:
	return cam_min_height * size_scale()

func cam_max_height_m() -> float:
	return cam_max_height * size_scale()

func cam_default_height_m() -> float:
	return cam_default_height * size_scale()

## 平移速度：倍率跟着缩放走（相机高度 ×4 → 按屏速度相同的平移量也要 ×4）
func cam_pan_speed_m() -> float:
	return cam_pan_speed * size_scale()

func strategic_view_height_m() -> float:
	return strategic_view_height * size_scale()

## 战争迷雾揭示半径（米）：按尺寸推导，`MinimapView` 里的「半径/地图」比值因此保持不变
func fog_reveal_radius_m() -> float:
	return fog_reveal_radius * size_scale()

## AI 部队视野（米）：同上，视野是「看得见多远」，按尺寸推导
func bandit_vision_m() -> float:
	return bandit_vision * size_scale()

## AI 部队总数：**不是几何量，是遭遇率曲线**。三个锚点都有依据 —— 1024 m 出厂世界 14 支（可玩，
## 第七轮 ① 起也是出货默认）、2048 m 37 支、4096 m 100 支（第六轮验收值）。
## 中间按幂律插值，指数 = ln(100/14)/ln(4) ≈ 1.42，落在「线性 56 支」与「面积 224 支」之间：
## 4 倍图按面积补会过密，不补又太空。
## ⚠ 密度课题（Round B/C）：参考项目 `godot_ai_test` 是 468 m / 43 支 / 90 定居点 ≈ 196 支/km²，
## 本工程 1024 m / 14 支 = 14 支/km² —— 观感上「地图空不空」取决于**密度**而不是尺寸，
## 真要贴近参考项目就得改这条曲线的锚点（或缩小地图同时提高支数），不能在尺寸推导里偷偷改。
## 基准值就是上面的 @export ai_party_count（1024 m 口径），与其他尺寸推导同一套写法。
const PARTY_COUNT_EXP := 1.42

func party_count() -> int:
	return maxi(1, int(round(float(ai_party_count) * pow(size_scale(), PARTY_COUNT_EXP))))
