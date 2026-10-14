## =============================================================================
##  big_map_probe —— 「4096 m 世界实测」：换世界之前先量一遍（**默认不进一键门禁**）
##
##  用法：
##    & "G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe" --headless --path . `
##        --fixed-fps 60 --script res://tools/big_map_probe.gd
##    换成当前世界的尺寸做「同口径对照」：… --script res://tools/big_map_probe.gd -- --size=1024
##    （--size=1024 时高度图自动取 513，与现网世界逐项可比，跑一次约 12 秒）
##    想让它跟着一键门禁跑：$env:WARBAND_BIG_MAP = '1' 后再跑 tools\run_checks.ps1
##    （默认跳过：它要跑一次 4096 m 的完整世界生成，是分钟级，不适合塞进 70 秒的门禁）
##
##  【它是什么】用**生产代码**（Main.tscn + WorldGenPipeline，只把 cfg.map_size / heightmap_res
##    换成 4096 / 2049）跑一次完整世界生成，然后复测三件重活：
##      · 寻路栅格 build_from（细 1025² / 粗 513²）
##      · 植被筛选重建（实例数、区块数、耗时）
##      · A* 实跑（细 / 粗各几条定居点之间的路径，含展开节点数）
##    并把结果与 tools/scale_baseline.json 里 1024 m 的存档并排打印。
##
##  【它不是什么】不下任何断言、不写任何基线、不参与游戏运行。它的产出是**数字** —— 用来决定
##    第 ③b 批「真的换世界」时哪些参数必须跟着改（植被的 CELL / 分块 / 栅格预算）。
##    这与 §12.6 的双信号探针同一个态度：先量，再改；量不出来就先别改。
##
##  退出码：0 测量完成 / 2 世界没建起来（超时或场景加载失败）
## =============================================================================
extends SceneTree

const SCENE := "res://scenes/Main.tscn"
const BASELINE := "res://tools/scale_baseline.json"
const SIZE_DEFAULT := 4096.0
const WAIT_LIMIT := 400000   ## 帧上限；--fixed-fps 下帧与墙钟无关，真正的上限是门禁的 TimeoutSec
const PAIRS := 4             ## A* 取样对数（取前几对相邻定居点）

var map_size := SIZE_DEFAULT ## 可用 -- --size=1024 换成现网尺寸做同口径对照
var hm_res := 0              ## 跟随尺寸：每 2 m 一个高度采样点（1024 → 513，4096 → 2049）
var main: Node
var cfg: MapConfig
var cur: Dictionary = {}

func _initialize() -> void:
	_run()

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			map_size = float(a.split("=")[1])
	hm_res = int(map_size / 2.0) + 1
	var scene: PackedScene = load(SCENE)
	if scene == null:
		print("[大图] FAIL：加载不了 %s" % SCENE)
		quit(2)
		return
	cfg = MapConfig.new()
	cfg.map_size = map_size
	cfg.heightmap_res = hm_res
	main = scene.instantiate()
	var ac := AudioConfig.new()
	ac.enabled = false
	main.audio = ac
	main.config = cfg
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)

	print("[大图] 用生产代码生成 %.0f m / 高度图 %d² 的世界…" % [map_size, hm_res])
	var guard := 0
	var t0 := Time.get_ticks_msec()
	while guard < WAIT_LIMIT:
		guard += 1
		await process_frame
		if main.gen_done:
			break
	var wall := Time.get_ticks_msec() - t0
	if not main.gen_done:
		print("[大图] FAIL：等待世界生成超时（%d 帧 / 墙钟 %d ms）—— 这本身就是本批要量出来的第一件事" % [guard, wall])
		quit(2)
		return

	var d = main.data
	var veg = main.vegetation
	print("[大图] 世界就绪：管线内 %d ms / 墙钟 %d ms / 等待 %d 帧" % [int(main._gen_ms), wall, guard])
	print("[大图] 结构：定居点 %d / 桥梁 %d / 植被实例 %d / 植被区块 %d" % [
		d.settlements.size(), d.bridges.size(), veg.total(), _veg_chunks(veg.root)])
	print("[大图] 栅格：细 %d（%.2f m/格）/ 粗 %d / 道路 %d；高度图 %d（%.2f m/格）" % [
		d.nav_fine.res, d.nav_fine.cell, d.nav_coarse.res, d.nav_road.res, d.hm.res, d.hm.cell])
	var cs := TerrainManager.chunk_size_for(map_size)
	var nb := int(ceil(map_size / cs))
	print("[大图] 地形：分块 %.0f m × %d×%d = %d 块 / 每级四边 %s / LOD0 单块顶点 %d（含裙边）" % [
		cs, nb, nb, nb * nb, str(TerrainManager.lod_quads_for(map_size)), _lod0_verts(map_size)])

	cur["map_size"] = int(map_size)
	cur["gen_wall_ms"] = wall
	cur["veg_instances"] = veg.total()
	cur["veg_chunks"] = _veg_chunks(veg.root)

	# 高度场分件放在**最前面**：它是对「管线刚跑过的那件事」的复测，
	# 越早做越接近管线自己的环境（纳秒级复测放在最后会被后续大量分配/CPU 降频带偏）。
	# 判定绝对值时以管线自己的阶段计时为准，分件只用来定比例。
	_p_height()
	_report_settlements()
	_report_nav()
	_p_nav()
	_p_veg(veg)
	_p_path()
	_p_bridge_diag()

	print("[大图] ================ 4096 m 实测 ================")
	print("[大图] 生成墙钟 %d ms（管线内 %d ms）" % [wall, int(main._gen_ms)])
	for line in _lines():
		print("[大图] " + line)
	print("[大图] PASS：测量完成（%d 项数字，不下断言）" % cur.size())
	main.free()
	quit(0)

# ---------------------------------------------------------------- 0) 定居点铺开程度
## A* 的「相邻定居点只隔 99~244 米」暴露了一件事：18 个定居点在 4096 m 图上可能全挤在一角。
## 那会让「换大图」失去意义（战场还是一小块），所以把包围盒与最近邻距离数出来。
func _report_settlements() -> void:
	var ss: Array = main.data.settlements
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var nn := PackedFloat32Array()
	for i in ss.size():
		var p: Vector2 = ss[i].pos
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		var best := INF
		for j in ss.size():
			if i == j:
				continue
			best = minf(best, p.distance_to(ss[j].pos))
		nn.append(best)
	var sorted := Array(nn)
	sorted.sort()
	var med := 0.0
	if sorted.size() > 0:
		med = float(sorted[sorted.size() / 2])
	var span := hi - lo
	cur["settle_bbox"] = snappedf(maxf(span.x, span.y), 0.1)
	cur["settle_nn_median"] = snappedf(med, 0.1)
	print("[大图] 定居点铺开：包围盒 %.0f × %.0f m（占图 %.0f%%）/ 最近邻 最小 %.0f 中位 %.0f 最大 %.0f m" % [
		span.x, span.y, 100.0 * maxf(span.x, span.y) / map_size, sorted[0] if sorted.size() > 0 else 0.0,
		med, sorted[sorted.size() - 1] if sorted.size() > 0 else 0.0])

# ---------------------------------------------------------------- 0b) 连通性诊断
## 第一跑量的两件事都很可疑：桥梁 0（1024 m 是 7）、A* 每对只给 2 个路径点、展开节点只有几十。
## 这两件事都指向「定居点之间根本走不通」—— 所以这里把水/河/渡口/桥的格数、道路条数、
## 以及 18 个定居点各自落在哪个连通分量里，全部数出来。数不出来就不知道 ③b 该先修哪个。
func _report_nav() -> void:
	var d = main.data
	var nav = d.nav_fine
	nav.rebuild_components()
	var res: int = nav.res
	var nwater := 0
	var nriver := 0
	var nford := 0
	var nbridge := 0
	var nblocked := 0
	for i in res * res:
		if nav.water[i] == 1:
			nwater += 1
		if nav.river[i] == 1:
			nriver += 1
		if nav.ford[i] == 1:
			nford += 1
		if nav.bridge[i] == 1:
			nbridge += 1
		if nav.blocked[i] == 1:
			nblocked += 1
	var total := res * res
	print("[大图] 细栅格构成：水 %d / 河 %d / 渡口 %d / 桥 %d / 不可通行 %d（总 %d = %.1f%%）" % [
		nwater, nriver, nford, nbridge, nblocked, total, 100.0 * float(nblocked) / float(total)])
	cur["nav_fine_water"] = nwater
	cur["nav_fine_river"] = nriver
	cur["nav_fine_ford"] = nford
	cur["nav_fine_bridge"] = nbridge

	var roads: Array = d.roads
	var bridges: Array = d.bridges
	cur["roads"] = roads.size()
	cur["bridges"] = bridges.size()
	print("[大图] 道路 %d 条 / 桥梁 %d 座" % [roads.size(), bridges.size()])

	# 定居点各自的分量 id：两两同号的才算「走得到」
	var ids := {}
	var groups := {}
	var ss: Array = d.settlements
	for i in ss.size():
		var c: Vector2i = nav.cell_of(ss[i].pos)
		var id: int = nav.component[c.y * res + c.x]
		ids[i] = id
		if not groups.has(id):
			groups[id] = 0
		groups[id] = int(groups[id]) + 1
	var biggest := 0
	for k in groups.keys():
		biggest = maxi(biggest, int(groups[k]))
	cur["settlement_components"] = groups.size()
	cur["settlement_in_biggest"] = biggest
	print("[大图] 定居点连通性：%d 个定居点落在 %d 个连通分量里（最大分量 %d 个；全图分量总数另计）" % [
		ss.size(), groups.size(), biggest])
	# 分量 id 的分布（每个 id 里有哪些定居点）—— 一眼看出「是不是被河切成两半」
	var dist := {}
	for i in ids.keys():
		var k: int = ids[i]
		if not dist.has(k):
			dist[k] = []
		dist[k].append(i)
	print("[大图] 分量分布：%s" % str(dist))

# ---------------------------------------------------------------- 1) 寻路栅格
func _p_nav() -> void:
	var d = main.data
	for spec in [["nav_fine", NavGrid.res_for(map_size, 4.0)], ["nav_coarse", NavGrid.res_for(map_size, 8.0)]]:
		var which: String = spec[0]
		var res: int = spec[1]
		var ng := NavGrid.new(res, map_size)
		var t0 := Time.get_ticks_usec()
		ng.build_from(cfg, d.hm, d.gen)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		cur["%s_res" % which] = res
		cur["%s_ms" % which] = snappedf(ms, 0.01)
		print("[大图] 栅格重建 %s（%d² = %d 节点）：%.1f ms" % [which, res, res * res, ms])

# ---------------------------------------------------------------- 2) 植被筛选
func _p_veg(live) -> void:
	var mat := _veg_mat(live)
	if mat == null:
		print("[大图] 植被重建：拿不到材质，跳过（不影响总耗时结论）")
		return
	var holder := Node3D.new()
	root.add_child(holder)
	var v := VegetationScatter.new()
	v.cfg = cfg
	v.data = main.data
	v.rng = cfg.make_rng("vegetation")
	var t0 := Time.get_ticks_usec()
	v.build(holder, mat)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var kinds := {}
	for k in v.counts.keys():
		kinds[String(k)] = int(v.counts[k])
	cur["veg_rebuild_ms"] = snappedf(ms, 0.01)
	cur["veg_rebuild_instances"] = v.total()
	print("[大图] 植被重建：%.0f ms / 实例 %d（主场景 %d）/ 区块 %d / 逐类 %s" % [
		ms, v.total(), live.total(), _veg_chunks(v.root), str(kinds)])
	holder.free()

# ---------------------------------------------------------------- 3) A* 实跑
func _p_path() -> void:
	var ss: Array = main.data.settlements
	var pairs: Array = []
	for i in mini(PAIRS, maxi(0, ss.size() - 1)):
		pairs.append([ss[i].pos, ss[i + 1].pos])
	for which in ["fine", "coarse"]:
		var pf: Pathfinder = main.data.path_fine if which == "fine" else main.data.path_coarse
		if pf == null:
			continue
		cur["path_pairs_n"] = pairs.size()
		var total := 0.0
		var maxms := 0.0
		var exp_total := 0
		var npts := 0
		var detail := []
		for pr in pairs:
			var t0 := Time.get_ticks_usec()
			var pts: PackedVector3Array = pf.find_path(pr[0], pr[1])
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			total += ms
			maxms = maxf(maxms, ms)
			exp_total += pf.last_expanded
			npts += pts.size()
			# 起点/终点直线距离 vs 路径长度：路径长度≈直线（只有 2 个点）通常意味着**没找到路**。
			# 注意 find_path 返回的是 PackedVector3Array（x, 高度, z），不是二维点。
			var a0: Vector2 = pr[0]
			var b0: Vector2 = pr[1]
			var straight := a0.distance_to(b0)
			var walked := 0.0
			for k in range(1, pts.size()):
				var p1 := Vector2(pts[k - 1].x, pts[k - 1].z)
				var p2 := Vector2(pts[k].x, pts[k].z)
				walked += p1.distance_to(p2)
			detail.append("%dms/%d点/直%.0fm/走%.0fm" % [int(ms), pts.size(), straight, walked])
		cur["path_%s_total_ms" % which] = snappedf(total, 0.01)
		cur["path_%s_max_ms" % which] = snappedf(maxms, 0.01)
		cur["path_%s_expanded" % which] = exp_total
		cur["path_%s_points" % which] = npts
		print("[大图] A* %s（%d 对定居点）：合计 %.1f ms / 最大 %.1f ms / 展开节点 %d / 路径点 %d" % [
			which, pairs.size(), total, maxms, exp_total, npts])
		print("[大图] A* %s 逐对：%s" % [which, " | ".join(detail)])

# ---------------------------------------------------------------- 4) 高度场复测
## 阶段计时（配合 `[高度场]` 分件行）已经把 83 秒里的 57 秒钉在「生成地形高度场」上，分件由
## `HeightmapGenerator.generate(true)` 自己在原地打 —— 这里只复测一遍总时长。
## 注意：**别拿这里的复测值去跟管线自己的阶段值比**。实测里复测会偏高（同样一次 generate()，
## 复测 2707 ms vs 管线阶段 1512 ms，1024 m），因为复测发生在世界建好之后；占比与前后对比
## 一律看管线自己那两行（`[阶段]` 与 `[高度场]`），它们同源同位置。
func _p_height() -> void:
	var hg := HeightmapGenerator.new(cfg)
	var t := Time.get_ticks_usec()
	hg.generate(true)
	var ms := _ms_us(t)
	cur["height_total_ms"] = snappedf(ms, 0.1)
	print("[大图] 高度场复测（进程内第二次 generate，仅供量级参考）：%.0f ms（%.1f 万采样点 → %.2f µs/点）" % [
		ms, float(cfg.heightmap_res * cfg.heightmap_res) / 10000.0,
		ms * 1000.0 / float(cfg.heightmap_res * cfg.heightmap_res)])

# ---------------------------------------------------------------- 6) 桥梁诊断
## ③b-3 前置：4 倍尺度下为什么一座桥都不落？
## 落桥条件（`RoadNetwork._collect_bridges`）：道路折线上出现**连续 ≥2 个**「细栅格
## water=1 且 river=1」的采样点（采样步长 2 m，与地图尺寸无关）。所以先把两种情况分开：
##   A) 道路根本没踩到河道 → 问题在上游（寻路 / 道路走向 / 定居点铺开）；
##   B) 踩到了却不落桥       → 问题在落桥判定本身（run 长度 / 14 m 去重 / 端点距离）。
func _p_bridge_diag() -> void:
	var nav: NavGrid = main.data.nav_fine
	var roads: Array = main.data.roads
	var samples := 0
	var on_water := 0
	var on_river := 0
	var on_lake := 0
	var on_road := 0
	var runs: Array[int] = []          # 每条道路的最长「连续河道」run（单位：2 m 采样点数）
	for poly in roads:
		var pts: PackedVector2Array = poly
		var run := 0
		var best := 0
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1]
			var b: Vector2 = pts[i]
			var n := int(ceil(a.distance_to(b) / 2.0))
			for k in range(0, n + 1):
				var p := a.lerp(b, float(k) / float(maxi(1, n)))
				var c := nav.cell_of(p)
				var idx := nav.at(c.x, c.y)
				samples += 1
				var w := nav.water[idx] == 1
				var r := w and nav.river[idx] == 1
				if w:
					on_water += 1
				if r:
					on_river += 1
					run += 1
					best = maxi(best, run)
				else:
					if w:
						on_lake += 1
					run = 0
				if nav.road[idx] == 1:
					on_road += 1
		runs.append(best)
	runs.sort()
	var longest := 0
	if not runs.is_empty():
		longest = runs[runs.size() - 1]
	cur["bridge_river_samples"] = on_river
	cur["bridge_max_run"] = longest
	cur["bridge_roads"] = roads.size()
	print("[大图] 桥梁诊断：道路 %d 条 / 采样点 %d（踩到水 %d：河道 %d、湖海 %d；落在道路格 %d）" % [
		roads.size(), samples, on_water, on_river, on_lake, on_road])
	print("[大图] 桥梁诊断：单条道路最长连续河道 run = %d（落桥要求 ≥2）；桥 %d 座 / 桥格 %d" % [
		longest, main.data.bridges.size(), _count_flag(nav.bridge)])
	# 道路是在 nav_road 上寻路的，而 nav_road 的 res 是**固定 513**：1024 m → 2 m/格，4096 m → 8 m/格。
	# 河流宽度是绝对米数，所以它在道路栅格上占几格会随尺寸变 —— 这正是「同一条判定、两种结果」的嫌疑点。
	var nroad: NavGrid = main.data.nav_road
	var n_river := 0
	var n_river_blocked := 0
	var n_water := 0
	for i in nroad.river.size():
		if nroad.river[i] == 1:
			n_river += 1
			if nroad.blocked[i] == 1:
				n_river_blocked += 1
		if nroad.water[i] == 1:
			n_water += 1
	print("[大图] 桥梁诊断：nav_road %d²（%.1f m/格）水 %d / 河 %d（其中不可通行 %d）；nav_fine %.1f m/格、河 %d" % [
		nroad.res, nroad.cell, n_water, n_river, n_river_blocked, nav.cell, _count_flag(nav.river)])

func _count_flag(arr: PackedByteArray) -> int:
	var n := 0
	for v in arr:
		if v == 1:
			n += 1
	return n

func _ms_us(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0

## LOD0 单块顶点数：与 scale_probe 的口径一致（含 4 面各 4 圈的裙边），否则「4225 vs 1601」是假对照
func _lod0_verts(size: float) -> int:
	var q: int = int(TerrainManager.lod_quads_for(size)[0])
	return (q + 1) * (q + 1) + q * 4 * 4

# ---------------------------------------------------------------- 报告
func _lines() -> Array:
	var out := []
	var want := _baseline()
	var pairs_n := int(cur.get("path_pairs_n", PAIRS))
	out.append("植被 实例 %d（1024 m 基线 %s）/ 区块 %d（基线 %s）" % [
		int(cur.get("veg_instances", 0)), str(want.get("veg_instances", "n/a")),
		int(cur.get("veg_chunks", 0)), str(want.get("veg_chunks", "n/a"))])
	out.append("植被 重建耗时 %.0f ms（1024 m 基线 %s ms）—— 这一项决定 CELL 要不要跟着地图放大" % [
		float(cur.get("veg_rebuild_ms", 0.0)), str(want.get("veg_total_ms", "n/a"))])
	out.append("栅格 细 %d² %.0f ms / 粗 %d² %.0f ms" % [
		int(cur.get("nav_fine_res", 0)), float(cur.get("nav_fine_ms", 0.0)),
		int(cur.get("nav_coarse_res", 0)), float(cur.get("nav_coarse_ms", 0.0))])
	for which in ["fine", "coarse"]:
		var per := float(cur.get("path_%s_total_ms" % which, 0.0)) / float(maxi(1, pairs_n))
		var base_total := float(want.get("path_%s_total_ms" % which, 0.0))
		# 基线的 path_n 是「对数」，而 path_pairs 是那 12 对坐标本身（Array）—— 别拿后者去 int()
		var base_pairs := 12
		var bn: Variant = want.get("path_n", 12)
		if bn is int or bn is float:
			base_pairs = int(bn)
		out.append("A* %s 单对 %.1f ms（1024 m 基线 %.1f ms/对，基线共 %d 对）/ 展开 %d（基线 %s）" % [
			which, per, base_total / float(maxi(1, base_pairs)), base_pairs,
			int(cur.get("path_%s_expanded" % which, 0)),
			str(want.get("path_%s_expanded" % which, "n/a"))])
	out.append("地形 分块 %.0f m / %d 块（1024 m 基线 %s 块）/ LOD0 单块顶点 %d（基线 %s）" % [
		TerrainManager.chunk_size_for(map_size), int(ceil(map_size / TerrainManager.chunk_size_for(map_size))) ** 2,
		str(want.get("terrain_chunks", "n/a")), _lod0_verts(map_size),
		str(want.get("terrain_lod0_verts", "n/a"))])
	out.append("桥梁诊断 过河采样点 %d / 单路最长 run %d（≥2 才会落桥）—— run=0 说明是「道路没过河」，不是落桥判定坏了" % [
		int(cur.get("bridge_river_samples", 0)), int(cur.get("bridge_max_run", 0))])
	out.append("高度场 本进程复测 %.0f ms（占比与前后对比请看上面的 [阶段] / [高度场] 两行，同源同位置）" % [
		float(cur.get("height_total_ms", 0.0))])
	out.append("定居点 包围盒 %.0f m（占图 %.0f%%）/ 最近邻中位 %.0f m —— 太小说明定居点没铺开" % [
		float(cur.get("settle_bbox", 0.0)),
		100.0 * float(cur.get("settle_bbox", 0.0)) / map_size, float(cur.get("settle_nn_median", 0.0))])
	out.append("道路 %s 条 / 桥梁 %s 座 / 水格占 %.1f%%（对照跑 --size=1024 就看得出桥梁是不是被尺寸弄丢了）" % [
		str(cur.get("roads", "n/a")), str(cur.get("bridges", "n/a")),
		100.0 * float(cur.get("nav_fine_water", 0))
			/ float(maxi(1, int(cur.get("nav_fine_res", 1)) * int(cur.get("nav_fine_res", 1))))])
	out.append("提醒：A* 的「基线/对」与本次取对方式不同（基线用 12 对固定定居点，本探针取前 %d 对），" % pairs_n)
	out.append("      只能看量级；真正的判定要等 ③b 换世界后用 scale_probe 的固定 12 对重跑。")
	return out

func _baseline() -> Dictionary:
	if not FileAccess.file_exists(BASELINE):
		return {}
	var f := FileAccess.open(BASELINE, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

func _veg_chunks(root: Node3D) -> int:
	var n := 0
	for c in root.get_children():
		if c is MultiMeshInstance3D:
			n += 1
	return n

func _veg_mat(live) -> ShaderMaterial:
	for c in live.root.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi != null and mmi.material_override is ShaderMaterial:
			return mmi.material_override
	return null