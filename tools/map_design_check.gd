## =============================================================================
##  map_design_check —— 「地图设计」的量化守门（第七轮 ②）
##
##  【为什么必须有这一步】
##    用户原话是「地图设计很不好」。这类判断平时只能靠眼睛，于是每次改动都变成
##    「看起来好点了吗」—— 而下一次改动又会把它弄回去。参考项目
##    （F:\aigc_code\godot_ai_test\docs\大地图设计.md §14.1）的教训是同一句话：
##    **先把「陡」「碎」「空」变成数字，否则改完不知道是好了还是坏了。**
##    所以这里把「设计」里**可计算**的那部分钉成断言，剩下的（配色、模型）留给眼睛。
##
##  【量什么 · 为什么是这些】
##    1. 竖向比例  relief / map_size  —— 参考项目实测「起伏占横向 30%」= 整张图都是峭壁；
##       改法是把底噪压到 ±9（468 m 图的 1.9%）。这条是「像不像悬崖」的总开关。
##    2. 坡度分布  平均 / <5° 占比 / ≥40° 占比 —— 参考项目 47.4° → 12.5°、悬崖格 54.2% → 1.4%。
##    3. 海岸线复杂度  IC = 4πA / P²（等周商）—— 圆形大陆 = 1.0，越破碎越小。
##       旧世界是一个**圆盘**（IC 接近 1），所以「一眼假」。
##    4. 山脉连贯性  取陆地高度的 P90 当「高处」，数 4 连通块的**最大块占比**。
##       噪声堆出来的山 = 满地小碎块（占比低）；显式线段山脉带 = 少数长条（占比高）。
##       这条专门用来区分「噪声撒盐」和「山脉成带」，是 ② 批改高度场的判据。
##    5. 水系与聚落的关系  河流是否入海/入湖、聚落到最近水面的距离分位数。
##       旧世界（2048 m）实测「1935 个道路采样点 0 个落在水里、桥梁 0 座」—— 河成了装饰。
##    6. 阈值是否还成立  cfg.mountain_line / snow_line 之上到底占陆地多少。
##       高度场一改，着色用的绝对高度阈值就会失效（着色会整体变成岩石或雪）。
##    7. 生物群系 / 植被 / 部队密度  —— 「空不空」的数字版：每平方公里的植被与部队数。
##
##  【口径】默认跑**出货默认尺寸**（cfg 的 @export 默认值，与门禁第 7 步同图）；
##    `--size=N` 可换图，`--report` 只打印不断言（甲：先看数，再定阈值）。
## =============================================================================
extends SceneTree

const SLOPE_BINS := [5.0, 15.0, 30.0, 40.0]
## 断言上限/下限（第七轮 ② 重做后的实测值 + 安全边界，见 docs/PLAN.md §16.11）
const RELIEF_RATIO_MAX := 0.10       ## 竖向起伏 / 地图跨度（**不是**越低越好：
                                     ## 显式山脉带天然抬高极差，压死它等于把山铲平；
                                     ## 判「像不像悬崖」看的是下面的坡度分布与高地连贯性）
const SLOPE_AVG_MAX := 16.0          ## 平均坡度（度）
const CLIFF_SHARE_MAX := 0.06        ## 坡度 ≥ 40° 的格占比
const FLAT_SHARE_MIN := 0.45         ## 坡度 < 5° 的格占比（"平原真的平"）
const COAST_IC_MAX := 0.72           ## 等周商上限（1.0 = 完美圆盘）
const COAST_IC_MIN := 0.12           ## 下限（太碎 = 一堆孤岛）
const HIGH_COHERENCE_MIN := 0.45     ## 高地区域最大连通块占比
const WATER_SHARE_MIN := 0.10
const WATER_SHARE_MAX := 0.55
const RIVER_REACH_SHARE_MIN := 0.95  ## 入海/入湖/出图的河流占比
const SETTLE_WATER_MEDIAN_MAX := 0.30 ## 聚落→最近水面距离中位数 / 地图跨度
const BIOME_DOMINANCE_MAX := 0.80    ## 单一生物群系占陆地比例上限
const VEG_DENSITY_MIN := 3000.0      ## 每平方公里植被实例数
const VEG_DENSITY_MAX := 60000.0
const PARTY_DENSITY_MIN := 8.0       ## 每平方公里 AI 部队数

var fails: Array = []
var checks := 0        ## 真正执行过的断言条数（打印里写死数字迟早会和代码对不上）
var notes: Array = []
var report_only := false
var size := 0.0

func _initialize() -> void:
	_run()

func _fail(msg: String) -> void:
	fails.append(msg)

func _ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		_fail(msg)

func _p(k: String, v) -> void:
	print("[设计] %-22s %s" % [k, str(v)])

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s == "--report":
			report_only = true
		elif s.begins_with("--size="):
			size = float(s.substr(7))
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = scene.instantiate()
	var ac := AudioConfig.new()
	ac.enabled = false
	main.audio = ac
	if size > 0.0:
		var c := MapConfig.new()
		c.map_size = size
		c.heightmap_res = c.scaled_heightmap_res()
		main.config = c
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	var guard := 0
	while guard < 20000:
		guard += 1
		await process_frame
		if main.gen_done:
			break
	if not main.gen_done:
		print("[设计] FAIL：世界生成超时")
		quit(2)
		return
	var cfg: MapConfig = main.config
	var d: MapData = main.data
	var ms := cfg.map_size
	_p("世界", "%.0f m / 高度图 %d（%.2f m 间距）/ 种子 %d" % [ms, cfg.heightmap_res, ms / float(cfg.heightmap_res - 1), cfg.map_seed])

	# ---------------------------------------------------------------- 高度与坡度
	var hm: Heightmap = d.hm
	var land_hs := PackedFloat32Array()
	var land_n := 0
	var slope_sum := 0.0
	var slope_n := 0
	var slope_bins := [0, 0, 0, 0, 0]   # <5 / 5-15 / 15-30 / 30-40 / >=40
	for z in hm.res:
		for x in hm.res:
			var h := hm.get_h(x, z)
			if h <= cfg.sea_level:
				continue
			land_n += 1
			land_hs.append(h)
			if (x % 2) == 0 and (z % 2) == 0:
				var sl := rad_to_deg(atan(hm.grid_slope(x, z) / hm.cell * hm.cell / hm.cell))
				sl = rad_to_deg(atan(hm.grid_slope(x, z)))
				slope_sum += sl
				slope_n += 1
				if sl < SLOPE_BINS[0]:
					slope_bins[0] += 1
				elif sl < SLOPE_BINS[1]:
					slope_bins[1] += 1
				elif sl < SLOPE_BINS[2]:
					slope_bins[2] += 1
				elif sl < SLOPE_BINS[3]:
					slope_bins[3] += 1
				else:
					slope_bins[4] += 1
	land_hs.sort()
	var total_cells := hm.res * hm.res
	var q := func(f: float) -> float:
		if land_hs.is_empty():
			return 0.0
		return land_hs[clampi(int(f * float(land_hs.size() - 1)), 0, land_hs.size() - 1)]
	var p10: float = q.call(0.10)
	var p50: float = q.call(0.50)
	var p90: float = q.call(0.90)
	var p99: float = q.call(0.99)
	var relief: float = p99 - p10
	var relief_ratio := relief / ms
	var land_share := float(land_n) / float(total_cells)
	var water_share := 1.0 - land_share
	var slope_avg := slope_sum / float(maxi(1, slope_n))
	var flat_share := float(slope_bins[0]) / float(maxi(1, slope_n))
	var cliff_share := float(slope_bins[4]) / float(maxi(1, slope_n))
	_p("陆地占比", "%.1f%%（水域 %.1f%%）" % [land_share * 100.0, water_share * 100.0])
	_p("陆地高度分位", "P10 %.1f / P50 %.1f / P90 %.1f / P99 %.1f m（极差 %.1f m）" % [p10, p50, p90, p99, relief])
	_p("竖向比例", "极差 / 跨度 = %.2f%%" % (relief_ratio * 100.0))
	_p("坡度", "平均 %.1f° / <5° %.1f%% / 5-15° %.1f%% / 15-30° %.1f%% / 30-40° %.1f%% / ≥40° %.1f%%"
		% [slope_avg, flat_share * 100.0,
			float(slope_bins[1]) / float(maxi(1, slope_n)) * 100.0,
			float(slope_bins[2]) / float(maxi(1, slope_n)) * 100.0,
			float(slope_bins[3]) / float(maxi(1, slope_n)) * 100.0,
			cliff_share * 100.0])
	# 着色真正读的是**实测分位阈值**（MapConfig.rock_line_of / snow_line_of），
	# 不是 @export 兜底常数 —— 这里必须量同一个口径，否则量的东西和看到的东西不是一回事。
	var rock_line: float = cfg.rock_line_of(d.gen)
	var snow_line: float = cfg.snow_line_of(d.gen)
	var above_mtn := 0
	var above_snow := 0
	for h in land_hs:
		if h >= rock_line:
			above_mtn += 1
		if h >= snow_line:
			above_snow += 1
	_p("阈值占陆地", "岩石线 %.1f m → %.1f%% / 雪线 %.1f m → %.1f%% / 陆地中位 %.1f m"
		% [rock_line, float(above_mtn) / float(maxi(1, land_n)) * 100.0,
			snow_line, float(above_snow) / float(maxi(1, land_n)) * 100.0, d.gen.h_land_p50])
	_ok(above_mtn > land_n * 0.06, "岩石线只覆盖 %.1f%% 陆地（山几乎不变色）" % (float(above_mtn) / float(maxi(1, land_n)) * 100.0))
	_ok(above_snow > land_n * 0.015, "雪线只覆盖 %.1f%% 陆地（雪几乎看不见）" % (float(above_snow) / float(maxi(1, land_n)) * 100.0))

	# ---------------------------------------------------------------- 海岸线
	var n2 := 256
	var land2 := PackedByteArray()
	land2.resize(n2 * n2)
	for z in n2:
		for x in n2:
			var hx := int(float(x) / float(n2) * float(hm.res - 1))
			var hz := int(float(z) / float(n2) * float(hm.res - 1))
			land2[z * n2 + x] = 1 if hm.get_h(hx, hz) > cfg.sea_level else 0
	var area := 0
	var perim := 0
	for z in n2:
		for x in n2:
			var i := z * n2 + x
			if land2[i] == 0:
				continue
			area += 1
			for k in 4:
				var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
				var nz := z + (1 if k == 2 else (-1 if k == 3 else 0))
				if nx < 0 or nz < 0 or nx >= n2 or nz >= n2 or land2[nz * n2 + nx] == 0:
					perim += 1
	var ic := 4.0 * PI * float(area) / float(maxi(1, perim * perim))
	_p("海岸线", "等周商 IC = %.3f（1.0 = 完美圆盘；< 0.6 = 有海湾半岛）" % ic)

	# ---------------------------------------------------------------- 山脉连贯性
	var hi_th := p90
	var hi := PackedByteArray()
	hi.resize(n2 * n2)
	for z in n2:
		for x in n2:
			var hx := int(float(x) / float(n2) * float(hm.res - 1))
			var hz := int(float(z) / float(n2) * float(hm.res - 1))
			hi[z * n2 + x] = 1 if hm.get_h(hx, hz) >= hi_th else 0
	var label := PackedInt32Array()
	label.resize(n2 * n2)
	var largest := 0
	var hi_total := 0
	var cur := 0
	var stack := PackedInt32Array()
	for i in n2 * n2:
		if hi[i] == 0:
			continue
		hi_total += 1
		if label[i] != 0:
			continue
		cur += 1
		var cnt := 0
		stack.clear()
		stack.append(i)
		label[i] = cur
		while not stack.is_empty():
			var j: int = stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			cnt += 1
			var jx := j % n2
			var jz := j / n2
			for k in 4:
				var nx := jx + (1 if k == 0 else (-1 if k == 1 else 0))
				var nz := jz + (1 if k == 2 else (-1 if k == 3 else 0))
				if nx < 0 or nz < 0 or nx >= n2 or nz >= n2:
					continue
				var ni := nz * n2 + nx
				if hi[ni] == 1 and label[ni] == 0:
					label[ni] = cur
					stack.append(ni)
		largest = maxi(largest, cnt)
	var coherence := float(largest) / float(maxi(1, hi_total))
	_p("高地区域", "共 %d 块 / P90 以上 %d 格（%.1f%% 陆地）/ 最大块占比 %.1f%%"
		% [cur, hi_total, float(hi_total) / float(maxi(1, area)) * 100.0, coherence * 100.0])

	# ---------------------------------------------------------------- 水系
	var gen: HeightmapGenerator = d.gen
	var river_reach := 0
	var river_len := 0.0
	var river_widths := PackedFloat32Array()
	var river_to_settle := PackedFloat32Array()
	var lake_n := gen.lakes.size()
	for r in gen.rivers:
		var pts: PackedVector3Array = r["points"]
		var ws: PackedFloat32Array = r["widths"]
		var last: Vector3 = pts[pts.size() - 1]
		var reach := false
		# 判据是「河末点已经在水里」：**地面**（下切后的河道）或**水面**任一到达海平面即可。
		# 只比水面会误判 —— 河口的水面 = 河床 + 1.7 m 水深，天生比海面高一截。
		if minf(last.y, hm.height_at(last.x, last.z)) <= cfg.sea_level + 1.0:
			reach = true
		for l in gen.lakes:
			if Vector2(last.x, last.z).distance_to(l["center"]) < float(l["radius"]) * 1.1:
				reach = true
		if last.x < 6.0 or last.z < 6.0 or last.x > ms - 6.0 or last.z > ms - 6.0:
			reach = true
		if reach:
			river_reach += 1
		for k in pts.size():
			if k > 0:
				river_len += Vector2(pts[k].x, pts[k].z).distance_to(Vector2(pts[k - 1].x, pts[k - 1].z))
			river_widths.append(ws[k])
		# 每个河点到最近聚落的距离（取最小值 = 该河的贴近程度）
		var best := 1e9
		for s in d.settlements:
			for k in range(0, pts.size(), 3):
				best = minf(best, Vector2(pts[k].x, pts[k].z).distance_to(s.pos))
		river_to_settle.append(best)
	var wsum := 0.0
	for w in river_widths:
		wsum += w
	# 逐条河诊断：断头河在地图上看就是「一条断掉的蓝线」，必须能定位到是哪条、断在哪
	for ri in gen.rivers.size():
		var rp: PackedVector3Array = gen.rivers[ri]["points"]
		var lp: Vector3 = rp[rp.size() - 1]
		_p("  河%d" % (ri + 1), "%d 点 / 末点 (%.0f, %.0f) 水面 %.1f m / 该处地面 %.1f m"
			% [rp.size(), lp.x, lp.z, lp.y, hm.height_at(lp.x, lp.z)])
	_p("河流", "%d 条 / 总长 %.0f m / 平均半宽 %.1f m / 入海入湖或出图 %d 条 / 湖泊 %d 个"
		% [gen.rivers.size(), river_len, wsum / float(maxi(1, river_widths.size())), river_reach, lake_n])
	var settle_water := PackedFloat32Array()
	var settle_drowned := 0
	for s in d.settlements:
		var best := 1e9
		for r in gen.rivers:
			var pts: PackedVector3Array = r["points"]
			for k in range(0, pts.size(), 2):
				best = minf(best, Vector2(pts[k].x, pts[k].z).distance_to(s.pos))
		for l in gen.lakes:
			best = minf(best, maxf(0.0, s.pos.distance_to(l["center"]) - float(l["radius"])))
		if best >= 1e8:
			best = s.pos.distance_to(Vector2(ms * 0.5, ms * 0.5))
		settle_water.append(best)
		if hm.height_at(s.pos.x, s.pos.y) <= cfg.sea_level + 0.5:
			settle_drowned += 1
	settle_water.sort()
	var sw_med := settle_water[settle_water.size() / 2] if settle_water.size() > 0 else 0.0
	var sw_min := settle_water[0] if settle_water.size() > 0 else 0.0
	_p("聚落→最近水面", "min %.0f / 中位 %.0f / 最大 %.0f m（%.0f 个聚落，占地图 %.1f%%）"
		% [sw_min, sw_med, settle_water[settle_water.size() - 1] if settle_water.size() > 0 else 0.0,
			float(d.settlements.size()), sw_med / ms * 100.0])
	_ok(settle_drowned == 0, "有 %d 个聚落落在水下" % settle_drowned)

	# ---------------------------------------------------------------- 道路 / 桥 / 渡口
	var nf: NavGrid = d.nav_fine
	var road_cells := 0
	var road_in_water := 0
	var road_on_bridge := 0
	var road_on_ford := 0
	var walk := 0
	var largest_comp := {}
	for cz in nf.res:
		for cx in nf.res:
			if nf.road[nf.at(cx, cz)] == 1:
				road_cells += 1
				if nf.water[nf.at(cx, cz)] == 1:
					road_in_water += 1
				if nf.bridge[nf.at(cx, cz)] == 1:
					road_on_bridge += 1
				if nf.ford[nf.at(cx, cz)] == 1:
					road_on_ford += 1
			if not nf.is_blocked(cx, cz):
				walk += 1
				var c := nf.component[nf.at(cx, cz)]
				largest_comp[c] = int(largest_comp.get(c, 0)) + 1
	var comp_max := 0
	for k in largest_comp.keys():
		comp_max = maxi(comp_max, int(largest_comp[k]))
	_p("可通行", "%d 格（%.1f%%）/ 最大连通块 %.1f%% / 道路 %d 格（水中 %d、桥上 %d、渡口 %d）"
		% [walk, float(walk) / float(nf.res * nf.res) * 100.0,
			float(comp_max) / float(maxi(1, walk)) * 100.0, road_cells, road_in_water, road_on_bridge, road_on_ford])
	_p("桥", "%d 座" % d.bridges.size())
	# 道路格 ∧ 水格 只允许出现在**桥或渡口**上：桥面本来就在水面上方，
	# 旧断言写「一个都不许有」是错的（实测 86 个道路水格 = 86 个桥格）。
	_ok(road_in_water <= road_on_bridge + road_on_ford,
		"有 %d 个道路格落在水里，但只有 %d 个在桥/渡口上（道路直接铺进水里了）"
		% [road_in_water, road_on_bridge + road_on_ford])
	_ok(road_on_ford > 0 or road_on_bridge > 0, "道路既不过桥也不过渡口 —— 水系与道路完全脱节")
	_ok(d.bridges.size() > 0, "地图上一座桥都没有（河流成了装饰）")

	# ---------------------------------------------------------------- 生物群系
	var desert_share := 0
	var forest_share := 0
	var moist_sum := 0.0
	for i in gen.biome_desert.size():
		var hx := i % hm.res
		var hz := i / hm.res
		if hm.get_h(hx, hz) <= cfg.sea_level:
			continue
		if gen.biome_desert[i] > 0.45:
			desert_share += 1
		if gen.forest_mask[i] > 0.5:
			forest_share += 1
		moist_sum += gen.biome_moist[i]
	var land_n2 := maxi(1, land_n)
	_p("生物群系", "沙漠 %.1f%% / 森林 %.1f%% / 平均湿度 %.2f（均按陆地计）"
		% [float(desert_share) / float(land_n2) * 100.0, float(forest_share) / float(land_n2) * 100.0, moist_sum / float(land_n2)])

	# ---------------------------------------------------------------- 植被 / 部队密度
	var veg_total := 0
	var veg_kinds := 0
	var veg: VegetationScatter = main.vegetation
	if veg != null:
		for k in veg.counts.keys():
			if int(veg.counts[k]) > 0:
				veg_kinds += 1
		veg_total = veg.total()
	var km2 := (ms / 1000.0) * (ms / 1000.0)
	var veg_density := float(veg_total) / km2
	var parties: int = main.ai_parties.size()
	var party_density := float(parties) / km2
	_p("植被", "%d 实例 / %d 类 / %.0f 个每平方公里" % [veg_total, veg_kinds, veg_density])
	_p("部队", "%d 支 / %.1f 支每平方公里" % [parties, party_density])

	# ---------------------------------------------------------------- 断言
	_ok(relief_ratio <= RELIEF_RATIO_MAX, "竖向比例 %.2f%% 超过 %.2f%%（地图会像悬崖）" % [relief_ratio * 100.0, RELIEF_RATIO_MAX * 100.0])
	_ok(slope_avg <= SLOPE_AVG_MAX, "平均坡度 %.1f° 超过 %.1f°" % [slope_avg, SLOPE_AVG_MAX])
	_ok(cliff_share <= CLIFF_SHARE_MAX, "≥40° 悬崖格 %.1f%% 超过 %.1f%%" % [cliff_share * 100.0, CLIFF_SHARE_MAX * 100.0])
	_ok(flat_share >= FLAT_SHARE_MIN, "平地（<5°）只有 %.1f%%，低于 %.1f%%" % [flat_share * 100.0, FLAT_SHARE_MIN * 100.0])
	_ok(ic <= COAST_IC_MAX, "海岸线等周商 %.3f 超过 %.2f（太像圆盘）" % [ic, COAST_IC_MAX])
	_ok(ic >= COAST_IC_MIN, "海岸线等周商 %.3f 低于 %.2f（太碎）" % [ic, COAST_IC_MIN])
	_ok(coherence >= HIGH_COHERENCE_MIN, "高地区域最大连通块只占 %.1f%%，低于 %.0f%%（山是噪声撒盐，不是山脉带）"
		% [coherence * 100.0, HIGH_COHERENCE_MIN * 100.0])
	_ok(water_share >= WATER_SHARE_MIN, "水域只有 %.1f%%（地图像一块整陆地）" % (water_share * 100.0))
	_ok(water_share <= WATER_SHARE_MAX, "水域高达 %.1f%%" % (water_share * 100.0))
	if gen.rivers.size() > 0:
		var reach_share := float(river_reach) / float(gen.rivers.size())
		_ok(reach_share >= RIVER_REACH_SHARE_MIN, "只有 %.0f%% 的河流入海/入湖/出图" % (reach_share * 100.0))
	_ok(sw_med / ms <= SETTLE_WATER_MEDIAN_MAX, "聚落离最近水面中位数 %.0f m（图跨度 %.1f%%）超过 %.0f%%"
		% [sw_med, sw_med / ms * 100.0, SETTLE_WATER_MEDIAN_MAX * 100.0])
	var d_share := float(desert_share) / float(land_n2)
	var f_share := float(forest_share) / float(land_n2)
	_ok(d_share <= BIOME_DOMINANCE_MAX and f_share <= BIOME_DOMINANCE_MAX, "单一生物群系占比过高（沙漠 %.0f%% / 森林 %.0f%%）"
		% [d_share * 100.0, f_share * 100.0])
	_ok(veg_density >= VEG_DENSITY_MIN, "植被密度 %.0f 个/km² 低于 %.0f（地图空）" % [veg_density, VEG_DENSITY_MIN])
	_ok(veg_density <= VEG_DENSITY_MAX, "植被密度 %.0f 个/km² 超过 %.0f" % [veg_density, VEG_DENSITY_MAX])
	_ok(veg_kinds >= 4, "只有 %d 类植被" % veg_kinds)
	_ok(party_density >= PARTY_DENSITY_MIN, "部队密度 %.1f 支/km² 低于 %.1f（大地图没人）" % [party_density, PARTY_DENSITY_MIN])

	for n in notes:
		print("[设计] 注意 %s" % n)
	if report_only:
		print("[设计] 报告模式：只打印，不判定（%d 条断言本会失败）" % fails.size())
		quit(0)
		return
	if fails.is_empty():
		print("[设计] PASS：地图设计 %d 项断言全过（竖向比例 %.2f%% / 平均坡度 %.1f° / IC %.3f / 山脉连贯性 %.1f%% / 植被 %.0f 个每平方公里）"
			% [checks, relief_ratio * 100.0, slope_avg, ic, coherence * 100.0, veg_density])
		quit(0)
	else:
		for f in fails:
			print("[设计] FAIL %s" % f)
		print("[设计] FAIL：%d / %d 项不达标" % [fails.size(), checks])
		quit(1)