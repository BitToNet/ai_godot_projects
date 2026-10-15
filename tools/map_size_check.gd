## =============================================================================
##  map_size_check —— 「地图尺寸适配」定式自检（**不参与游戏运行**）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/map_size_check.gd
##
##  为什么需要它：ROADMAP §12.5 把「换一张更大的地图」清点成一张表，其中 #3（相机远裁剪）
##  与 #4（heightmap_res 的导出上限）是纯数值型假设 —— 它们的失败方式**不是报错，而是**
##  在 4096 m 图上「地形被裁掉 / 编辑器里调不上去」，而 1024 m 图上一切正常，
##  所以门禁里那 25 项一条都抓不到。这一条把「按尺寸推导」这层关系本身钉住。
##
##  它断言的是**数值关系**，不建世界、不建相机、不渲染：
##    1) **出货默认**（无环境变量覆盖时的 `MapConfig`）必须钉死：1024 m / 高度图 513 / 2 m 间距，
##       且与门禁口径（`WARBAND_MAP_SIZE=1024`）是**同一个世界**（否则「出货配置零守护」会回来）；
##    2) 1024 m 图的推导结果必须**逐位等于**改造前的旧常量（行为不变）；
##    3) 4096 m 图（目标世界，仍可显式跑）的推导结果必须覆盖对角线（地形不被裁掉）；
##    4) heightmap_res 的 @export_range 上限必须放得下 2049，且步进仍只产生奇数分辨率。
##  它**不**证明渲染效果、也不证明拾取在地形上真的命中 —— 那些属于实机观察，见 §12.5 的说明。
##
##  退出码：0 = 全部通过；1 = 有断言失败
## =============================================================================
extends SceneTree

const TARGET_SIZE := 4096.0   ## ROADMAP §12.5 的目标地图尺寸
const LEGACY_FAR := 5000.0    ## 改造前 CameraRig 的 cam.far（1024 m 时代）
const LEGACY_RAY := 4000.0    ## 改造前 ray_to_terrain 的最远推进距离

var _fails: Array[String] = []
var _total: int = 0

func _initialize() -> void:
	_run()

func _ok(cond: bool, what: String) -> void:
	_total += 1
	if not cond:
		_fails.append(what)

## 与 ROADMAP 同口径：对角线 = sqrt(2) * 边长
func _diagonal(size: float) -> float:
	return sqrt(2.0) * size

## 拿到「不带 WARBAND_MAP_SIZE 覆盖」的**出货默认**配置：一键门禁带着覆盖跑小图，
## 但那不是出货值 —— 默认世界是 1024 m（第七轮 ① 起，与门禁口径**同一个世界**），这个区别必须显式测。
func _cfg_no_env() -> MapConfig:
	var saved_ms := OS.get_environment("WARBAND_MAP_SIZE")
	var saved_hr := OS.get_environment("WARBAND_HM_RES")
	OS.set_environment("WARBAND_MAP_SIZE", "")
	OS.set_environment("WARBAND_HM_RES", "")
	var c := MapConfig.new()
	OS.set_environment("WARBAND_MAP_SIZE", saved_ms)
	OS.set_environment("WARBAND_HM_RES", saved_hr)
	return c

func _run() -> void:
	# 门禁会带 WARBAND_MAP_SIZE=1024 跑小图；这里先拿「不带覆盖」的出货默认值，再单独造 1024 m 实例。
	var ship := _cfg_no_env()                      # 出货默认世界（第七轮 ① 起 = 1024 m）
	var cfg := _cfg_no_env()                       # 本检查谈的是**尺寸推导定式**，参照固定为 4096 m
	cfg.map_size = TARGET_SIZE
	cfg.heightmap_res = cfg.scaled_heightmap_res()
	var cfg_small := MapConfig.new()
	cfg_small.map_size = 1024.0
	cfg_small.heightmap_res = 513

	# ---- 1) 出货默认世界：第七轮 ① 从 4096 m 收到 **1024 m** ----
	# 收口的三条理由在 MapConfig.map_size 的注释里（寻路单次搜索地板 / 水系与聚落的关系被稀释 /
	# 出货世界必须落进门禁与指纹的守护范围），这里只钉数值：
	# 1024 m 的块边长 = max(128, 1024/16) = 128 m、四边形边长 2 m ⇒ 高度图 513 点（与地形网格同分辨率）。
	_ok(is_equal_approx(ship.map_size, 1024.0), "默认地图尺寸是 1024 m（%.1f）" % ship.map_size)
	_ok(ship.heightmap_res == 513, "默认高度图分辨率是 513（%d）" % ship.heightmap_res)
	var spacing_now := ship.map_size / float(ship.heightmap_res - 1)
	_ok(absf(spacing_now - 2.0) < 0.0001, "默认高度图间距是 2.0 m（%.4f）" % spacing_now)
	_ok(ship.scaled_heightmap_res() == 513, "按尺寸推导在 1024 m 给出 513（%d）" % ship.scaled_heightmap_res())
	_ok(absf(ship.size_scale() - 1.0) < 0.0001 and absf(ship.area_scale() - 1.0) < 0.0001,
		"出货默认是 1× 边长 / 1× 面积（%.1f / %.1f）—— 即 SIZE_REF 本身" % [ship.size_scale(), ship.area_scale()])
	# 出货默认与门禁口径必须是同一个世界：否则「出货配置零守护」的老问题会回来
	_ok(is_equal_approx(ship.map_size, cfg_small.map_size)
			and ship.heightmap_res == cfg_small.heightmap_res,
		"出货默认世界 == 门禁小图世界（%.0f m / %d 点）" % [cfg_small.map_size, cfg_small.heightmap_res])
	# 目标尺寸 4096 m 的定式一条都不能松：它仍然是「尺寸推导是否推得上去」的参照
	_ok(cfg.scaled_heightmap_res() == 1025, "按尺寸推导在 4096 m 给出 1025（%d）" % cfg.scaled_heightmap_res())
	_ok(cfg_small.scaled_heightmap_res() == 513, "按尺寸推导在 1024 m 给出 513（%d）" % cfg_small.scaled_heightmap_res())
	_ok(absf(cfg.size_scale() - 4.0) < 0.0001 and absf(cfg.area_scale() - 16.0) < 0.0001,
		"目标尺寸 4× / 面积倍率 16×（%.1f / %.1f）" % [cfg.size_scale(), cfg.area_scale()])

	# ---- 1b) 尺寸推导的量：在 1024 m 上必须回落到旧常量本身（旧世界行为不变的正式证据）----
	_ok(cfg_small.river_half_width() == 11.0 and cfg.river_half_width() == 44.0,
		"河道半宽 1024 → 11 m、4096 → 44 m（%.1f / %.1f）" % [cfg_small.river_half_width(), cfg.river_half_width()])
	_ok(cfg_small.fords_per_river() == 2 and cfg.fords_per_river() == 8,
		"渡口数 1024 → 2、4096 → 8（%d / %d）" % [cfg_small.fords_per_river(), cfg.fords_per_river()])
	_ok(cfg_small.lake_radius_m() == 46.0 and cfg.lake_radius_m() == 184.0,
		"湖泊半径 1024 → 46 m、4096 → 184 m（%.1f / %.1f）" % [cfg_small.lake_radius_m(), cfg.lake_radius_m()])
	_ok(cfg_small.min_settlement_distance_m() == 96.0 and cfg.min_settlement_distance_m() == 384.0,
		"定居点最小间距 1024 → 96 m、4096 → 384 m（%.1f / %.1f）" % [cfg_small.min_settlement_distance_m(), cfg.min_settlement_distance_m()])
	# 植被候选格是**绝对米数**（密度属性），区块边长按尺寸推导（节点数不随地图膨胀）
	_ok(VegetationScatter.CELL == 7.0, "植被候选格恒为 7 m（%.1f）" % VegetationScatter.CELL)
	_ok(absf(cfg_small.map_size / float(VegetationScatter.VEG_CHUNKS_PER_AXIS) - 256.0) < 0.0001
		and absf(cfg.map_size / float(VegetationScatter.VEG_CHUNKS_PER_AXIS) - 1024.0) < 0.0001,
		"植被区块边长 1024 → 256 m、4096 → 1024 m")

	# ---- 1c) 玩法尺度：视觉量按尺寸推导，节奏量**故意不动**（第六轮的取舍，见 ROADMAP §16.9）----
	_ok(cfg_small.cam_min_height_m() == 20.0 and cfg.cam_min_height_m() == 80.0,
		"相机最近高度 1024 → 20 m、4096 → 80 m（%.1f / %.1f）" % [cfg_small.cam_min_height_m(), cfg.cam_min_height_m()])
	_ok(cfg_small.cam_max_height_m() == 400.0 and cfg.cam_max_height_m() == 1600.0,
		"相机最高高度 1024 → 400 m、4096 → 1600 m（%.1f / %.1f）" % [cfg_small.cam_max_height_m(), cfg.cam_max_height_m()])
	_ok(cfg_small.cam_default_height_m() == 90.0 and cfg.cam_default_height_m() == 360.0,
		"相机默认高度 1024 → 90 m、4096 → 360 m（%.1f / %.1f）" % [cfg_small.cam_default_height_m(), cfg.cam_default_height_m()])
	_ok(cfg_small.strategic_view_height_m() == 275.0 and cfg.strategic_view_height_m() == 1100.0,
		"战略视图阈值 1024 → 275 m、4096 → 1100 m（%.1f / %.1f）" % [cfg_small.strategic_view_height_m(), cfg.strategic_view_height_m()])
	_ok(cfg_small.cam_pan_speed_m() == 190.0 and cfg.cam_pan_speed_m() == 760.0,
		"相机平移速度 1024 → 190 m/s、4096 → 760 m/s（%.1f / %.1f）" % [cfg_small.cam_pan_speed_m(), cfg.cam_pan_speed_m()])
	_ok(cfg_small.fog_reveal_radius_m() == 118.0 and cfg.fog_reveal_radius_m() == 472.0,
		"迷雾揭示半径 1024 → 118 m、4096 → 472 m（%.1f / %.1f）" % [cfg_small.fog_reveal_radius_m(), cfg.fog_reveal_radius_m()])
	_ok(cfg_small.bandit_vision_m() == 92.0 and cfg.bandit_vision_m() == 368.0,
		"AI 部队视野 1024 → 92 m、4096 → 368 m（%.1f / %.1f）" % [cfg_small.bandit_vision_m(), cfg.bandit_vision_m()])
	# 迷雾半径 / 地图 的比值不变 ⇒ 小地图上的雾圈看起来一样大（这是推导自洽的旁证）
	_ok(absf(cfg_small.fog_reveal_radius_m() / cfg_small.map_size
			- cfg.fog_reveal_radius_m() / cfg.map_size) < 0.0001,
		"迷雾半径 / 地图边长 的比值不随尺寸变（小地图雾圈同大）")

	# 遭遇率曲线：三端锚点必须分别落在出货默认（= 旧世界 1024 m）/ 中间档 / 第六轮目标世界
	_ok(cfg_small.party_count() == 14, "1024 m 的 AI 部队数是 14 支（%d，也是第七轮出货默认）" % cfg_small.party_count())
	_ok(ship.party_count() == 14, "出货默认（1024 m）的 AI 部队数是 14 支（%d）" % ship.party_count())
	var cfg_mid := MapConfig.new()
	cfg_mid.map_size = 2048.0
	_ok(cfg_mid.party_count() == 37, "2048 m 的 AI 部队数是 37 支（%d）" % cfg_mid.party_count())
	_ok(cfg.party_count() == 100, "4096 m 目标世界的 AI 部队数是 100 支（%d）" % cfg.party_count())

	# 节奏量不推导：速度与接触距离保持绝对值（横穿出货默认的 1024 m 要 22 s）—— 这是决定，不是遗漏
	_ok(ship.player_speed == 46.0 and ship.ai_speed == 34.0 and ship.encounter_distance == 7.0,
		"移动速度与接触距离保持绝对值（%.0f / %.0f / %.1f m）" % [ship.player_speed, ship.ai_speed, ship.encounter_distance])
	_ok(cfg_small.party_count() < cfg_mid.party_count() and cfg_mid.party_count() < cfg.party_count(),
		"部队数随尺寸单调增（%d < %d < %d）" % [cfg_small.party_count(), cfg_mid.party_count(), cfg.party_count()])

	# 这两条是「行为不变」的正式证据：推导函数在 1024 m 下必须回落到旧常量本身
	_ok(CameraRig.far_for(cfg_small.map_size) == LEGACY_FAR,
		"1024 m 图的远裁剪面仍是旧值 %.1f（%.1f）" % [LEGACY_FAR, CameraRig.far_for(cfg_small.map_size)])
	_ok(CameraRig.ray_max_distance(cfg_small.map_size) == LEGACY_RAY,
		"1024 m 图的拾取最远距离仍是旧值 %.1f（%.1f）" % [LEGACY_RAY, CameraRig.ray_max_distance(cfg_small.map_size)])

	# ---- 2) heightmap_res 的导出范围必须放得下 4096 m 的 2 m 间距 ----
	# 注意：这里问的是「上限够不够」（留给想按 2 m 铺满 4 倍图的选项），与默认间距（4 m）无关
	var want_res := int(TARGET_SIZE / 2.0) + 1      # 4096 m / 2 m + 1 = 2049
	_ok(want_res == 2049, "4096 m 保持 2 m 间距需要 2049 个采样点（%d）" % want_res)
	var rng := _range_of(cfg, "heightmap_res")
	_ok(not rng.is_empty(), "从 MapConfig 读到了 heightmap_res 的 @export_range")
	if not rng.is_empty():
		var lo: int = rng[0]
		var hi: int = rng[1]
		var st: int = rng[2]
		_ok(lo == 129, "@export_range 下限仍是 129（%d）" % lo)
		_ok(st == 2, "@export_range 步进仍是 2（只产生奇数分辨率）（%d）" % st)
		_ok(hi >= want_res, "@export_range 上限放得下 2049（当前上限 %d）" % hi)
		# 上限本身也必须落在步进的格点上，否则编辑器里最后能选到的值不是上限
		_ok((hi - lo) % st == 0, "上限落在步进格点上（(%d-%d) %% %d == %d）" % [hi, lo, st, (hi - lo) % st])
		_ok((want_res - lo) % st == 0, "2049 本身落在步进格点上（(%d-%d) %% %d == %d）" % [want_res, lo, st, (want_res - lo) % st])
	_ok(want_res % 2 == 1, "2049 是奇数（高度图分辨率必须为奇数）")

	# ---- 3) 4096 m 图：推导值必须覆盖对角线 ----
	var far_target := CameraRig.far_for(TARGET_SIZE)
	var ray_target := CameraRig.ray_max_distance(TARGET_SIZE)
	var diag := _diagonal(TARGET_SIZE)
	_ok(far_target >= diag,
		"4096 m 图的远裁剪面 %.0f ≥ 对角线 %.0f（否则站在一角看对角会看不到地形）" % [far_target, diag])
	_ok(ray_target >= diag,
		"4096 m 图的拾取最远距离 %.0f ≥ 对角线 %.0f（否则点不中远端的落点）" % [ray_target, diag])
	# 1024 m 图同样要成立（验收口径统一，不搞特例）
	for s in [1024.0, 2048.0, TARGET_SIZE]:
		_ok(CameraRig.far_for(s) >= _diagonal(s), "%.0f m 图的远裁剪面覆盖对角线（%.0f ≥ %.0f）"
			% [s, CameraRig.far_for(s), _diagonal(s)])

	# ---- 4) 单调性：地图变大，两个推导值都不许变小 ----
	var sizes := [512.0, 1024.0, 2048.0, TARGET_SIZE, 8192.0]
	var mono_far := true
	var mono_ray := true
	for i in range(1, sizes.size()):
		if CameraRig.far_for(sizes[i]) < CameraRig.far_for(sizes[i - 1]):
			mono_far = false
		if CameraRig.ray_max_distance(sizes[i]) < CameraRig.ray_max_distance(sizes[i - 1]):
			mono_ray = false
	_ok(mono_far, "远裁剪面对地图尺寸单调不减")
	_ok(mono_ray, "拾取最远距离对地图尺寸单调不减")

	# ---- 5) 拾取循环的迭代上限必须够走完推导出来的距离 ----
	# 步进是「每步 ×1.06、上限 RAY_STEP_MAX」，这里用最坏情况（全程按上限步进）估算。
	var need := int(ceil(CameraRig.ray_max_distance(TARGET_SIZE) / CameraRig.RAY_STEP_MAX)) + 64
	_ok(CameraRig.RAY_GUARD >= need,
		"RAY_GUARD %d 够走完 4096 m 的拾取距离（估算需要 %d 步）" % [CameraRig.RAY_GUARD, need])

	# ---- 6) 地形分块：块数受控，且网格顶点间距不随地图尺寸变化 ----
	# 1024 m 下必须**逐位**等于旧常量（8×8 = 64 块、每级 32/16/8/4 四边形、间距 4 m）
	_ok(TerrainManager.chunk_size_for(1024.0) == TerrainManager.CHUNK_SIZE,
		"1024 m 图的分块边长仍是旧常量 %.0f（%.0f）" % [TerrainManager.CHUNK_SIZE, TerrainManager.chunk_size_for(1024.0)])
	_ok(TerrainManager.lod_quads_for(1024.0) == TerrainManager.LOD_QUADS,
		"1024 m 图的每级四边形数仍是旧常量（%s）" % str(TerrainManager.lod_quads_for(1024.0)))
	var n1024 := int(ceil(1024.0 / TerrainManager.chunk_size_for(1024.0)))
	_ok(n1024 * n1024 == 64, "1024 m 图仍是 8×8 = 64 块（%d）" % (n1024 * n1024))

	# 4096 m：256 m 分块 / 16×16 = 256 块（§12.5 #5 的目标），且块数有预算上限
	var cs_target := TerrainManager.chunk_size_for(TARGET_SIZE)
	var n_target := int(ceil(TARGET_SIZE / cs_target))
	_ok(cs_target == 256.0, "4096 m 图的分块边长是 256 m（%.0f）" % cs_target)
	_ok(n_target * n_target == 256, "4096 m 图是 16×16 = 256 块（%d）" % (n_target * n_target))
	_ok(n_target * n_target <= 256, "4096 m 图的块数不超过预算 256（%d）" % (n_target * n_target))
	_ok(TerrainManager.lod_quads_for(TARGET_SIZE) == [64, 32, 16, 8],
		"4096 m 图每级四边形数翻倍（%s）" % str(TerrainManager.lod_quads_for(TARGET_SIZE)))

	# 顶点间距恒定 —— 这是「只换装桶方式」的关键：SKIRT 与 LOD_DIST 都是按这个间距调出来的
	for s in [512.0, 1024.0, 2048.0, TARGET_SIZE, 8192.0]:
		var q: Array = TerrainManager.lod_quads_for(s)
		var sp := TerrainManager.chunk_size_for(s) / float(q[0])
		_ok(is_equal_approx(sp, TerrainManager.MESH_SPACING),
			"%.0f m 图的 LOD0 顶点间距仍是 %.1f m（%.4f）" % [s, TerrainManager.MESH_SPACING, sp])
		# 四级各自「分块 / 四边形数」也应等于 4 / 8 / 16 / 32 m —— 相邻级正好差 2 倍
		var ok_lv := true
		for i in 4:
			if not is_equal_approx(TerrainManager.chunk_size_for(s) / float(q[i]), TerrainManager.MESH_SPACING * pow(2.0, i)):
				ok_lv = false
		_ok(ok_lv, "%.0f m 图的四级间距依次是 4/8/16/32 m" % s)
	var mono_q := true
	var sizes2 := [512.0, 1024.0, 2048.0, TARGET_SIZE, 8192.0]
	for i in range(1, sizes2.size()):
		if TerrainManager.chunk_size_for(sizes2[i]) < TerrainManager.chunk_size_for(sizes2[i - 1]):
			mono_q = false
	_ok(mono_q, "分块边长对地图尺寸单调不减")

	# LOD 距离阈值本批**不动**：它按「米」算，与地图尺寸无关（改的只是分块的粒度）
	_ok(TerrainManager.LOD_DIST[0] == 220.0 and TerrainManager.LOD_DIST[1] == 400.0
		and TerrainManager.LOD_DIST[2] == 660.0 and TerrainManager.LOD_DIST[3] == 1e9,
		"LOD 距离阈值仍是 220 / 400 / 660 / 无限（%s）" % str(TerrainManager.LOD_DIST))
	# LOD0 单块顶点数（只报告）：4096 m 下 65² = 4225 = 1024 m 图 33² 的 4 倍，
	# 但块数是 1/4，所以「全图 LOD0 顶点总数」不变 —— 这正是间距不变的含义
	var q1024: Array = TerrainManager.lod_quads_for(1024.0)
	var q4096: Array = TerrainManager.lod_quads_for(TARGET_SIZE)
	var v4096: int = (int(q4096[0]) + 1) * (int(q4096[0]) + 1)
	# 单块三角形数翻 4 倍（四边形数翻倍）；而「每平方米的三角形数」不随尺寸变 ——
	# 后者才是「顶点间距不变」的可检验含义。注意**别拿顶点数当不变量**：
	# 顶点数是 (q+1)²，33² → 65² 是 3.88 倍而不是 4 倍（第一版就是这么写错的，门禁报了 2 项失败）。
	var tri1024: int = int(q1024[0]) * int(q1024[0]) * 2
	var tri4096: int = int(q4096[0]) * int(q4096[0]) * 2
	_ok(tri4096 == tri1024 * 4, "4096 m 图单块 LOD0 三角形数是 1024 m 图的 4 倍（%d vs %d）" % [tri4096, tri1024])
	var dens1024 := float(n1024 * n1024 * tri1024) / (1024.0 * 1024.0)
	var dens4096 := float(n_target * n_target * tri4096) / (TARGET_SIZE * TARGET_SIZE)
	_ok(is_equal_approx(dens1024, dens4096),
		"全图 LOD0 三角形密度不随尺寸变（%.4f vs %.4f 个/m²）" % [dens1024, dens4096])
	# 间距 4 m ⇒ 每个四边形 16 m² ⇒ 每个三角形 8 m² ⇒ 密度 0.125
	_ok(is_equal_approx(dens1024, 1.0 / (TerrainManager.MESH_SPACING * TerrainManager.MESH_SPACING * 0.5)),
		"三角形密度与 %.0f m 间距自洽（%.4f 个/m² = 8 m²/个）" % [TerrainManager.MESH_SPACING, dens1024])

	# ---- 7) 寻路栅格：分辨率按目标格距推导（#1），格距本身不随尺寸变 ----
	# 1024 m 下必须逐位回到旧常量 257 / 129（它们是「4 m 格距」与「8 m 格距」的来历）
	_ok(NavGrid.res_for(1024.0, 4.0) == 257, "1024 m 细栅格仍是 257（%d）" % NavGrid.res_for(1024.0, 4.0))
	_ok(NavGrid.res_for(1024.0, 8.0) == 129, "1024 m 粗/道路栅格仍是 129（%d）" % NavGrid.res_for(1024.0, 8.0))
	_ok(NavGrid.res_for(TARGET_SIZE, 4.0) == 1025, "4096 m 细栅格是 1025（%d）" % NavGrid.res_for(TARGET_SIZE, 4.0))
	_ok(NavGrid.res_for(TARGET_SIZE, 8.0) == 513, "4096 m 粗/道路栅格是 513（%d）" % NavGrid.res_for(TARGET_SIZE, 8.0))
	# 格距恒定（分辨率变化只是「同样 4 m / 8 m 精度铺满更大的地图」）
	for s in [1024.0, 2048.0, TARGET_SIZE]:
		for sp in [4.0, 8.0]:
			var r := NavGrid.res_for(s, sp)
			var actual: float = float(s) / float(r - 1)
			_ok(is_equal_approx(actual, sp), "%.0f m 图的 %.0f m 栅格格距自洽（%.4f）" % [s, sp, actual])
	# 节点数：细栅格 4× 边长 ⇒ 16× 节点（4096 m 下 105 万 —— #1 的性能压力就来自这里）
	var nodes_now := 257 * 257
	var nodes_target := NavGrid.res_for(TARGET_SIZE, 4.0) * NavGrid.res_for(TARGET_SIZE, 4.0)
	_ok(nodes_target == 1050625, "4096 m 细栅格是 105 万节点（%d）" % nodes_target)
	_ok(nodes_target > 1000000, "4096 m 细栅格超过 100 万节点（%d）—— 这是 #1 需要正视的量" % nodes_target)
	# Pathfinder 的展开上限 = res²（按尺寸推导，不会截断合法路径）
	var pf_now := Pathfinder.new(NavGrid.new(257, 1024.0))
	_ok(pf_now.max_expand == nodes_now, "展开上限 = 栅格节点总数（%d）" % pf_now.max_expand)
	var pf_big := Pathfinder.new(NavGrid.new(NavGrid.res_for(TARGET_SIZE, 4.0), TARGET_SIZE))
	_ok(pf_big.max_expand == nodes_target, "4096 m 图展开上限跟着放大到 %d（不截断）" % pf_big.max_expand)

	# ---- 8) grid_slope 与 slope_at 的逐位等价（③b-1 高度场提速的前提）----
	# ③b-1 要砍的第一刀是 `_build_biomes` 里**每点一次**的 `slope_at`（它走 normal_at → 4 次双线性
	# height_at，2049² 上是 36 秒里的一大半），换成直接用网格邻居做中心差分。这条替换**必须逐位相同**：
	# 坡度喂给 forest_mask / biome_rock → 植被密度与岩石掩码 → 世界布局。差 1 个 ULP 就要重基线，
	# 而这一批的全部价值就在「不用重基线」。
	# 等价性只在**采样正好落在网格点上**时成立（双线性权重 tx = tz = 0，返回的就是该点自身的数据），
	# 所以先钉前提（间距按生产推导，且正好是整数米：1024 m → 2 m、4096 m → 4 m），再拿一张同 cell 的
	# 小图把所有点（含 x/z = 0 与 res-1 的夹取边界）逐位比一遍。真实世界那一侧由「生成指纹不变」兜着
	# —— 那是最强的端到端证据。注意 grid_slope 的等价性本身与 cell 取值无关（只要采样落在网格点上）。
	for s in [cfg_small.map_size, cfg.map_size]:
		var s_f: float = s
		var probe := MapConfig.new()
		probe.map_size = s_f
		probe.heightmap_res = probe.scaled_heightmap_res()
		var rr: int = probe.heightmap_res
		var c: float = s_f / float(rr - 1)
		var want_c := 2.0 if s_f < 2000.0 else 4.0
		_ok(c == want_c, "%.0f m 图的采样间距按尺寸推导为 %.1f m（%.17f）—— grid_slope 的前提" % [s_f, want_c, c])
		var h := Heightmap.new(65, c * 64.0)      # 同 cell 的小图：65² 点便宜，且覆盖全部边界
		var gen := RandomNumberGenerator.new()
		gen.seed = 20261014
		for i in h.res * h.res:
			h.data[i] = gen.randf_range(-40.0, 90.0)
		var bad := 0
		var first_bad := Vector2i(-1, -1)
		for z in h.res:
			for x in h.res:
				if h.grid_slope(x, z) != h.slope_at(float(x) * c, float(z) * c):
					bad += 1
					if first_bad.x < 0:
						first_bad = Vector2i(x, z)
		_ok(bad == 0, "%.0f m 图（cell %.0f m）：grid_slope 与 slope_at 逐位相同（%d/%d 处不同，首个 %s）"
			% [s_f, c, bad, h.res * h.res, str(first_bad)])

	# ---- 9) 内存量级（只报告，不判定）：高度图与寻路栅格 ----
	# 用十进制 MB，跟 ROADMAP §12.5 #4 写的「≈16.8 MB」同口径（MiB 会显示成 16.0，容易被当成不一致）。
	# 注意这里报的是**2 m 间距铺满 4 倍图那个选项**的内存（2049²）；出货默认是 1024 m / 513²。
	var bytes := want_res * want_res * 4
	print("[地图尺寸] 4096 m / 2 m 间距（非默认）⇒ 高度图 %d² × 4 B = %.1f MB；1024 m 默认 513² 约 %.1f MB"
		% [want_res, float(bytes) / 1000000.0, 513.0 * 513.0 * 4.0 / 1000000.0])
	print("[地图尺寸] 出货默认 1024 m ⇒ 高度图 513²（2 m 间距）× 4 B ≈ %.1f MB" % [513.0 * 513.0 * 4.0 / 1000000.0])
	print("[地图尺寸] 4096 m ⇒ 地形 %d×%d = %d 块 × %d 四边（LOD0 顶点 %d/块，间距 %.1f m）"
		% [n_target, n_target, n_target * n_target, TerrainManager.lod_quads_for(TARGET_SIZE)[0],
			v4096, TerrainManager.MESH_SPACING])
	# 细栅格每节点 15 B：blocked/speed(4)/road/forest/water/river/ford/bridge = 11 B + component(4) B
	var nav_bytes := nodes_target * 15
	print("[地图尺寸] 4096 m ⇒ 细栅格 %d² 节点 × 15 B ≈ %.1f MB（粗/道路栅格 513² 各 %.1f MB）"
		% [NavGrid.res_for(TARGET_SIZE, 4.0), float(nav_bytes) / 1000000.0,
			float(513 * 513 * 15) / 1000000.0])

	if _fails.is_empty():
		print("PASS：地图尺寸推导定式全部正常（%d 项断言）" % _total)
		quit(0)
	else:
		print("FAIL：%d/%d 项断言未通过 —— %s" % [_fails.size(), _total, "; ".join(_fails)])
		quit(1)

## 读一个 @export_range 变量的 [下限, 上限, 步进]；不是 range 导出就返回空数组。
## 注意：引擎给的 hint_string 是**小数**形式（如 "129.0,2049.0,2.0"），
## 用 is_valid_int() 判会全部落空（第一次就是这么写错的，门禁当场报了 1 项失败）。
func _range_of(res: Resource, prop: String) -> Array:
	for p in res.get_property_list():
		if String(p.get("name", "")) != prop:
			continue
		if int(p.get("hint", 0)) != PROPERTY_HINT_RANGE:
			return []
		var parts := String(p.get("hint_string", "")).split(",")
		if parts.size() < 2:
			return []
		if not (parts[0].is_valid_float() and parts[1].is_valid_float()):
			return []
		var step := 1
		if parts.size() >= 3 and parts[2].is_valid_float():
			step = int(parts[2].to_float())
		return [int(parts[0].to_float()), int(parts[1].to_float()), step]
	return []