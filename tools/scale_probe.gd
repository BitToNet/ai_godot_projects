## =============================================================================
##  scale_probe —— 规模与热点探针（**不参与游戏运行**，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/scale_probe.gd
##    # 有意改变了规模 / 优化了热点之后更新基线：
##    ...--script res://tools/scale_probe.gd -- --write-baseline
##
##  测什么（ROADMAP 第六轮 C 节的三条主线，全部在**真实生成的世界**上测，不用合成数据）：
##    1) 植被：完整 build() 耗时 + 实例发射段单独耗时 + 实例数 / 区块数 / 逐类计数 +
##             **实例变换指纹**（第六轮要改发射方式与筛选遍数，必须证明"实例数据有没有被改"）
##    2) 地形：单个 Chunk 在 4 个 LOD 下的建块耗时（中位 / 最大 / 合计）+ 代表块的
##             顶点位置与索引指纹 + height_at / normal_at 两个采样原语的单次耗时
##    3) A*：固定 12 对定居点之间的寻路（游戏里真在用的 path_fine 与 path_coarse），
##             每对的耗时 / 展开节点数 / 路径点数
##
##  【实证】与【推断】的界线：
##    · 结构量（实例数 / 区块数 / 逐类计数 / 顶点数 / 指纹 / 每对路径点数与展开节点数）
##      逐项与基线**精确比对** —— 这些是确定性量，差一个就是错，没有容差
##    · 耗时只做**上界**比对（基线 × 1.6 记 WARN，× 2.5 判 FAIL），与 perf_probe 同一思路：
##      机器抖动不该误报，但"悄悄变慢 60%"必须留痕
##    · 【未解】headless 下没有渲染：GPU 绘制 / draw call / 视锥剔除 / MultiMesh 上传
##      的收益**测不到**；这里量到的全是 CPU 侧脚本开销（探针建的节点不进场景树）
##
##  退出码：0 与基线一致 / 1 结构量不符或耗时超硬容差 / 2 超时或基线不可读
## =============================================================================
extends SceneTree

const SCENE := "res://scenes/Main.tscn"
const BASELINE := "res://tools/scale_baseline.json"
const WAIT_LIMIT := 6000        ## 等生成的帧上限（--fixed-fps 下 6000 帧 = 100 秒）
const TOL := 1.6                ## 耗时上界：超了记 WARN
const TOL_HARD := 2.5           ## 耗时硬上界：超了判 FAIL
const PAIRS := 12               ## 固定 12 对起终点
const PRIM_N := 20000           ## 采样原语的调用次数
const TERRAIN_SAMPLE := 16      ## 非 LOD0 的抽样块数（LOD0 全量 64 块）

var main: Node
var cfg: MapConfig
var cur: Dictionary = {}
var warn: Array = []
var fail: Array = []

func _initialize() -> void:
	_run()

func _run() -> void:
	var ua := OS.get_cmdline_user_args()
	var writeb := ua.has("--write-baseline")

	var scene: PackedScene = load(SCENE)
	if scene == null:
		print("[规模] FAIL：加载不了 %s" % SCENE)
		quit(2)
		return
	main = scene.instantiate()
	var ac := AudioConfig.new()
	ac.enabled = false
	main.audio = ac
	cfg = MapConfig.new()
	main.config = cfg
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)

	var guard := 0
	var t0 := Time.get_ticks_msec()
	while guard < WAIT_LIMIT:
		guard += 1
		await process_frame
		if main.gen_done:
			break
	if not main.gen_done:
		print("[规模] FAIL：等待地图生成超时（%d 帧）" % guard)
		quit(2)
		return
	print("[规模] 世界就绪：种子 %d / %d 米见方 / 生成 %d ms / 等待 %d 帧（%d ms）" % [
		cfg.map_seed, int(cfg.map_size), int(main._gen_ms), guard, Time.get_ticks_msec() - t0])
	cur["seed"] = cfg.map_seed
	cur["map_size"] = int(cfg.map_size)

	_p_veg()
	_p_terrain()
	_p_path()

	print("[规模] 本次实测：")
	for line in _table():
		print("      " + line)

	if writeb:
		_write_baseline()
		print("[规模] 已写入基线：%s" % BASELINE)
		main.free()
		quit(0)
		return

	var want := _read_baseline()
	if want.is_empty():
		print("[规模] FAIL：基线缺失或不可读 -> %s" % BASELINE)
		print("       先跑一次：--script res://tools/scale_probe.gd -- --write-baseline")
		main.free()
		quit(2)
		return

	for k in ["seed", "map_size", "veg_instances", "veg_chunks", "veg_xform_hash",
			"terrain_chunks", "terrain_lod0_verts", "terrain_pos_hash", "terrain_idx_hash",
			"path_pairs", "path_fine_expanded", "path_coarse_expanded"]:
		_exact(k, want)
	for k in ["veg_total_ms", "veg_emit_ms", "terrain_lod0_median_ms", "terrain_lod1_median_ms",
			"terrain_lod2_median_ms", "terrain_lod3_median_ms", "prim_height_at_us",
			"prim_normal_at_us", "path_fine_total_ms", "path_coarse_total_ms"]:
		_bound(k, want)

	var kinds_ok := _exact_kinds(want)
	if fail.is_empty() and warn.is_empty():
		print("[规模] PASS：结构与耗时都与基线一致（种子 %d）" % int(want.get("seed", -1)))
		main.free()
		quit(0)
		return
	if fail.is_empty():
		for w in warn:
			print("[规模] WARN %s" % w)
		print("[规模] PASS：结构一致；耗时漂移 %d 条（未超硬容差 %.1f×）" % [warn.size(), TOL_HARD])
		main.free()
		quit(0)
		return
	for w in warn:
		print("[规模] WARN %s" % w)
	for f in fail:
		print("[规模] 差异 %s" % f)
	print("[规模] FAIL：%d 项不符（结构量必须精确一致；耗时硬容差 %.1f×）" % [fail.size(), TOL_HARD])
	main.free()
	quit(1)

# ---------------------------------------------------------------- 1) 植被
func _p_veg() -> void:
	var live: VegetationScatter = main.vegetation
	if live == null or live.root == null:
		print("[规模] FAIL：主场景里没有植被根节点（vegetation_enabled=false？）")
		fail.append("vegetation 缺失")
		return
	var mat := _veg_mat(live)
	var holder := Node3D.new()

	# ---- 完整重跑：同一个 cfg/data + 同一支 rng 派生 → 必须与主场景逐项一致
	var v := VegetationScatter.new()
	v.cfg = cfg
	v.data = main.data
	v.rng = cfg.make_rng("vegetation")
	var t0 := Time.get_ticks_usec()
	v.build(holder, mat)
	var total_ms := _ms(t0)

	cur["veg_instances"] = v.total()
	cur["veg_chunks"] = _veg_chunks(v.root)
	var kinds := {}
	for k in v.counts.keys():
		kinds[String(k)] = int(v.counts[k])
	cur["veg_kinds"] = kinds
	cur["veg_total_ms"] = _r3(total_ms)
	cur["veg_emit_ms"] = _r3(_veg_emit_ms(v, mat))
	cur["veg_xform_hash"] = _veg_hash(v.root)

	# 重跑与主场景的一致性 —— 探针自己不可信的话，后面的数一个都不能用
	if v.total() != live.total():
		fail.append("植被重跑实例数 %d ≠ 主场景 %d" % [v.total(), live.total()])
	if kinds != _kinds_of(live):
		fail.append("植被重跑逐类计数与主场景不一致")
	holder.free()

func _veg_mat(live: VegetationScatter) -> ShaderMaterial:
	for c in live.root.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi != null and mmi.material_override is ShaderMaterial:
			return mmi.material_override
	return null

func _veg_chunks(root: Node3D) -> int:
	var n := 0
	for c in root.get_children():
		if c is MultiMeshInstance3D:
			n += 1
	return n

func _kinds_of(v: VegetationScatter) -> Dictionary:
	var d := {}
	for k in v.counts.keys():
		d[String(k)] = int(v.counts[k])
	return d

## 发射段单独计时：把真实实例表读回来，再走一次真的 _emit_chunks（发射到游离节点上）
func _veg_emit_ms(v: VegetationScatter, mat: ShaderMaterial) -> float:
	var per := {}
	for c in v.root.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi == null:
			continue
		var kind := String(mmi.name).get_slice("_", 0)
		if not per.has(kind):
			var arr: Array[Transform3D] = []
			per[kind] = arr
		var mm := mmi.multimesh
		for i in mm.instance_count:
			per[kind].append(mm.get_instance_transform(i))
	var meshes := {
		"conifer": v._make_conifer(),
		"broadleaf": v._make_broadleaf(),
		"cactus": v._make_cactus(),
		"deadtree": v._make_deadtree(),
		"rock": v._make_rock(),
	}
	var v2 := VegetationScatter.new()
	v2.cfg = cfg
	var root2 := Node3D.new()
	v2.root = root2
	var t0 := Time.get_ticks_usec()
	for kind in per.keys():
		v2._emit_chunks(String(kind), meshes[kind], per[kind], mat, 380.0, 260.0)
	var ms := _ms(t0)
	root2.free()
	return ms

## 实例变换指纹：按「类名排序 → 区块名排序 → 实例序号」喂进 SHA-256。
## 第六轮要动筛选遍数（会改布局）与发射方式（不该改数据），这个哈希会当场说话：
## 发射方式改了而哈希不变 = 只换了写法；筛选改了而哈希变了 = 布局真的变了。
func _veg_hash(root: Node3D) -> String:
	var nodes := []
	for c in root.get_children():
		if c is MultiMeshInstance3D:
			nodes.append(c)
	nodes.sort_custom(func(a, b): return String(a.name) < String(b.name))
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	for c in nodes:
		var mmi := c as MultiMeshInstance3D
		var mm := mmi.multimesh
		var f := PackedFloat32Array()
		f.append(float(mm.instance_count))
		for i in mm.instance_count:
			var t := mm.get_instance_transform(i)
			f.append_array(PackedFloat32Array([t.origin.x, t.origin.y, t.origin.z]))
			f.append_array(PackedFloat32Array([t.basis.x.x, t.basis.y.y, t.basis.z.z]))
		f.append(float(String(mmi.name).hash()))
		_h_feed(h, f)
	return _h_done(h)

# ---------------------------------------------------------------- 2) 地形
func _p_terrain() -> void:
	var tm := TerrainManager.new()
	tm.cfg = cfg
	tm.data = main.data
	var n := int(ceil(cfg.map_size / TerrainManager.CHUNK_SIZE))
	cur["terrain_chunks"] = n * n
	var quads0: int = TerrainManager.LOD_QUADS[0]
	cur["terrain_lod0_verts"] = (quads0 + 1) * (quads0 + 1) + quads0 * 4 * 4

	for lod in 4:
		var quads: int = TerrainManager.LOD_QUADS[lod]
		var nchunks: int = int(cur["terrain_chunks"])
		var limit: int = nchunks if lod == 0 else mini(TERRAIN_SAMPLE, nchunks)
		var times := PackedFloat32Array()
		var done := 0
		for cz in n:
			for cx in n:
				if done >= limit:
					break
				done += 1
				var t0 := Time.get_ticks_usec()
				tm._build_chunk_mesh(cx, cz, quads)
				times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		cur["terrain_lod%d_median_ms" % lod] = _r3(_median(times))
		cur["terrain_lod%d_max_ms" % lod] = _r3(_maxf(times))
		cur["terrain_lod%d_sum_ms" % lod] = _r3(_sumf(times))
		cur["terrain_lod%d_n" % lod] = limit

	# 代表块（正中间那块）的顶点位置与索引指纹：第六轮改法线算法时，几何形状与拓扑不该变
	var mid := int(n * 0.5)
	var m: ArrayMesh = tm._build_chunk_mesh(mid, mid, quads0)
	var arrays := m.surface_get_arrays(0)
	cur["terrain_pos_hash"] = _pack_hash(arrays[Mesh.ARRAY_VERTEX])
	cur["terrain_idx_hash"] = _pack_hash(arrays[Mesh.ARRAY_INDEX])

	# 采样原语：建块目前每顶点 1 次 height_at + 1 次 normal_at(= 4 次 height_at)
	var hm: Heightmap = main.data.hm
	var acc := 0.0
	var t1 := Time.get_ticks_usec()
	for i in PRIM_N:
		acc += hm.height_at(float(i % 512) * 2.0, float((i * 7) % 512) * 2.0)
	cur["prim_height_at_us"] = _r3(_ms(t1) * 1000.0 / float(PRIM_N))
	t1 = Time.get_ticks_usec()
	for i in PRIM_N:
		acc += hm.normal_at(float(i % 512) * 2.0, float((i * 7) % 512) * 2.0).y
	cur["prim_normal_at_us"] = _r3(_ms(t1) * 1000.0 / float(PRIM_N))
	cur["prim_acc"] = _r3(acc)      # 防止上面的循环被优化掉
	tm.free()

# ---------------------------------------------------------------- 3) A*
func _p_path() -> void:
	var ss: Array = main.data.settlements
	var pairs: Array = []
	for i in mini(PAIRS, maxi(0, ss.size() - 1)):
		var a: Vector2 = ss[i].pos
		var b: Vector2 = ss[i + 1].pos
		pairs.append([a, b])
	cur["path_n"] = pairs.size()
	for which in ["fine", "coarse"]:
		var pf: Pathfinder = main.data.path_fine if which == "fine" else main.data.path_coarse
		if pf == null:
			fail.append("path_%s 为空" % which)
			continue
		var total := 0.0
		var maxms := 0.0
		var total_exp := 0
		var detail := []
		for pr in pairs:
			var t0 := Time.get_ticks_usec()
			var pts := pf.find_path(pr[0], pr[1])
			var ms := _ms(t0)
			total += ms
			maxms = maxf(maxms, ms)
			total_exp += pf.last_expanded
			detail.append({"ms": _r3(ms), "expanded": pf.last_expanded, "pts": pts.size()})
		cur["path_%s_total_ms" % which] = _r3(total)
		cur["path_%s_max_ms" % which] = _r3(maxms)
		cur["path_%s_expanded" % which] = total_exp
		cur["path_%s_detail" % which] = detail
		if which == "fine":
			cur["path_pairs"] = _pairs_json(pairs)

func _pairs_json(pairs: Array) -> Array:
	var out := []
	for pr in pairs:
		var a: Vector2 = pr[0]
		var b: Vector2 = pr[1]
		out.append([_r3(a.x), _r3(a.y), _r3(b.x), _r3(b.y)])
	return out

# ---------------------------------------------------------------- 报告
func _table() -> Array:
	var lines := []
	lines.append("植被 实例 %d / 区块 %d / 变换指纹 %s" % [
		int(cur["veg_instances"]), int(cur["veg_chunks"]), String(cur["veg_xform_hash"])])
	lines.append("植被 build 合计 %.1f ms（其中发射段 %.1f ms，筛选段≈%.1f ms）" % [
		float(cur["veg_total_ms"]), float(cur["veg_emit_ms"]),
		float(cur["veg_total_ms"]) - float(cur["veg_emit_ms"])])
	lines.append("地形 块数 %d / LOD0 顶点 %d / 位置指纹 %s" % [
		int(cur["terrain_chunks"]), int(cur["terrain_lod0_verts"]), String(cur["terrain_pos_hash"])])
	for lod in 4:
		lines.append("地形 LOD%d（%d 块 × %d 四边）中位 %.2f ms / 最大 %.2f ms / 合计 %.1f ms" % [
			lod, int(cur["terrain_lod%d_n" % lod]), int(TerrainManager.LOD_QUADS[lod]),
			float(cur["terrain_lod%d_median_ms" % lod]), float(cur["terrain_lod%d_max_ms" % lod]),
			float(cur["terrain_lod%d_sum_ms" % lod])])
	lines.append("采样原语 单次 height_at %.2f µs / normal_at %.2f µs（法线 = 4 次采样）" % [
		float(cur["prim_height_at_us"]), float(cur["prim_normal_at_us"])])
	for which in ["fine", "coarse"]:
		lines.append("A* %s（%d 对）合计 %.1f ms / 最大 %.1f ms / 展开节点合计 %d" % [
			which, int(cur.get("path_n", 0)), float(cur.get("path_%s_total_ms" % which, 0.0)),
			float(cur.get("path_%s_max_ms" % which, 0.0)), int(cur.get("path_%s_expanded" % which, 0))])
	return lines

func _exact(k: String, want: Dictionary) -> void:
	if not want.has(k):
		return
	var a = want[k]
	var b = cur.get(k)
	if not _same(a, b):
		fail.append("%s：基线 %s → 本次 %s" % [k, _short(a), _short(b)])

## 基线要落成 JSON 再读回来：整数会变成浮点（5163 -> 5163.0），字典键序也可能变，
## 所以结构量比对必须**按数值 / 递归**比，不能拿 str() 直接对
func _same(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return absf(float(a) - float(b)) <= 0.0005
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for kk in a.keys():
			if not b.has(kk) or not _same(a[kk], b[kk]):
				return false
		return true
	return str(a) == str(b)

func _exact_kinds(want: Dictionary) -> bool:
	var a: Dictionary = want.get("veg_kinds", {})
	var b: Dictionary = cur.get("veg_kinds", {})
	if _same(a, b):
		return true
	fail.append("veg_kinds：基线 %s → 本次 %s" % [str(a), str(b)])
	return false

func _bound(k: String, want: Dictionary) -> void:
	if not want.has(k) or not cur.has(k):
		return
	var w := float(want[k])
	var g := float(cur[k])
	if w <= 0.0:
		return
	var r := g / w
	if r > TOL_HARD:
		fail.append("%s 超硬容差：基线 %.3f → 本次 %.3f（%.2f×）" % [k, w, g, r])
	elif r > TOL:
		warn.append("%s 变慢：基线 %.3f → 本次 %.3f（%.2f×）" % [k, w, g, r])

func _short(v) -> String:
	var s := str(v)
	return s if s.length() <= 40 else s.substr(0, 40) + "…"

# ---------------------------------------------------------------- 基线读写
func _write_baseline() -> void:
	var obj := {
		"note": "由 tools/scale_probe.gd --write-baseline 生成；结构量必须精确一致，耗时只做上界比对",
		"seed": cfg.map_seed,
	}
	for k in cur.keys():
		if String(k).begins_with("prim_acc"):
			continue
		obj[k] = cur[k]
	var f := FileAccess.open(BASELINE, FileAccess.WRITE)
	if f == null:
		print("[规模] FAIL：无法写入 %s（错误码 %d）" % [BASELINE, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(obj, "\t") + "\n")
	f.close()

func _read_baseline() -> Dictionary:
	if not FileAccess.file_exists(BASELINE):
		return {}
	var f := FileAccess.open(BASELINE, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK:
		print("[规模] FAIL：基线不是合法 JSON（第 %d 行：%s）" % [j.get_error_line(), j.get_error_message()])
		return {}
	if j.data is Dictionary:
		return j.data
	return {}

# ---------------------------------------------------------------- 小工具
func _ms(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0

func _r3(v: float) -> float:
	return snappedf(v, 0.001)

func _median(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var b := Array(a)
	b.sort()
	return float(b[b.size() / 2])

func _maxf(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m

func _sumf(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s

func _pack_hash(p) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	if p is PackedVector3Array:
		var f := PackedFloat32Array()
		for v in p:
			f.append_array(PackedFloat32Array([v.x, v.y, v.z]))
		_h_feed(h, f)
	elif p is PackedInt32Array:
		var f2 := PackedFloat32Array()
		for i in p:
			f2.append(float(i))
		_h_feed(h, f2)
	return _h_done(h)

func _h_feed(h: HashingContext, f: PackedFloat32Array) -> void:
	if f.is_empty():
		return      # 5c 的教训：空数组喂给 update() 会打 ERROR
	h.update(f.to_byte_array())

func _h_done(h: HashingContext) -> String:
	return h.finish().hex_encode().substr(0, 16)