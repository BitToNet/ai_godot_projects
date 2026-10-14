## =============================================================================
##  VegetationScatter —— MultiMesh 批量植被
##
##  【投放规则（拒绝采样）】
##    1. 7 米网格 + 随机抖动得到候选点（避免规则排列）
##    2. 硬性排除：水面 / 河道 / 湖泊 / 道路 / 陡坡 / 定居点范围内
##    3. 类型专属密度：
##         针叶林 = 森林遮罩^1.5 × 北部权重（山麓地带）
##         阔叶林 = 森林遮罩^1.5 × 中部权重 × (1 - 干旱度)
##         仙人掌 = 干旱度 > 0.45，很稀疏
##         枯木   = 干旱度或碎石度高
##         岩石   = 碎石噪声或陡坡
##       森林遮罩本身是低频噪声阈值化的结果 → 成片林地，而不是均匀撒点。
##    4. 候选过多时用种子随机的洗牌截断到目标数量
##
##  【性能方案】
##    每种植被按 8x8 = 64 个 128 米区块拆成多个 MultiMeshInstance3D：
##      · 每个区块有独立 AABB → 视锥剔除真正生效（整张图的植被不会全画）
##      · 每块设置 visibility_range_end → 远处整块消失
##      · 全部 cast_shadow = OFF（阴影 pass 只留给地形与建筑）
##      · 拉远到战略视图时整个植被根节点直接隐藏
##    合计约 9k 实例，但同屏通常只有几百到一两千个实例参与绘制。
## =============================================================================
class_name VegetationScatter
extends RefCounted

## 植被区块边长：第六轮 6b 从 128 m 提到 256 m —— 节点/对象数减到约 1/3（1024 m 地图上 4×4=16 桶/类），
## 代价是剔除粒度变粗（256 m 的块「只要一角在视锥里」就整块画）。headless 测不到剔除这一项，
## 所以只能说「节点数一定下降」，剔除效率未测（perf_probe 的 draw_calls/nodes 能看到前者）。
const CHUNK := 256.0
const CELL := 7.0

var cfg: MapConfig
var data: MapData
var rng: RandomNumberGenerator
var root: Node3D
var counts: Dictionary = {}

func build(parent: Node3D, mat: ShaderMaterial) -> void:
	root = Node3D.new()
	root.name = "Vegetation"
	parent.add_child(root)
	rng = cfg.make_rng("vegetation")
	if not cfg.vegetation_enabled:
		return

	_scatter("conifer", _make_conifer(), cfg.conifer_count, mat, 380.0, 260.0)
	_scatter("broadleaf", _make_broadleaf(), cfg.broadleaf_count, mat, 340.0, 250.0)
	_scatter("cactus", _make_cactus(), cfg.cactus_count, mat, 260.0, 180.0)
	_scatter("deadtree", _make_deadtree(), cfg.deadtree_count, mat, 260.0, 200.0)
	_scatter("rock", _make_rock(), cfg.rock_count, mat, 340.0, 220.0)

func total() -> int:
	var s := 0
	for k in counts.keys():
		s += int(counts[k])
	return s

# =============================================================== 通用投放
func _scatter(kind: String, mesh: Mesh, target: int, mat: ShaderMaterial, range_end: float, range_end_strategic: float) -> void:
	if mesh == null or target <= 0:
		return
	var n := int(cfg.map_size / CELL)
	var list: Array[Transform3D] = []
	var nav := data.nav_fine
	var hm := data.hm
	# ---- 第六轮 6b：把判定里的脚本层开销摊平（**不改判定结果，也不动 rng 调用序列**）----
	# 这段筛选每次生成要跑 5 遍（5 个植被类型各扫一遍 7 m 网格 = 5 × 85800 格）。原来每格都要付：
	# nav.ci() ×2 + nav.at()（3 次方法调用 + 各自的 clampi/round）、4 个 PackedByteArray 的属性取用、
	# 以及「把 18 个定居点全算一遍 p.distance_to()（含 sqrt）」。全部换成局部变量与平方比较。
	# 注意：两个 rng 抽点必须留在原位、原顺序、原次数 —— 只要 rng 序列不变，植被布局就逐位不变，
	# 探针的 veg_instances / veg_kinds / veg_xform_hash 是这条承诺的硬断言（见 ROADMAP §12.4）。
	var nav_res := nav.res
	var nav_cell := nav.cell
	var water := nav.water
	var road := nav.road
	var ford := nav.ford
	var bridge := nav.bridge
	var sea_lim := cfg.sea_level + 1.6
	var max_slope := cfg.max_slope_veg
	var edge_hi := cfg.map_size - 2.0
	# 定居点摊平成三个并行数组，半径先 +7 再平方：原来是 p.distance_to(s.pos) < s.radius + 7.0
	# （sqrt 与平方比较在数学上等价；用 float64 存，避免 float32 截断在边界上翻转判定）
	var sn := data.settlements.size()
	var sx := PackedFloat64Array()
	var sz := PackedFloat64Array()
	var sr2 := PackedFloat64Array()
	sx.resize(sn); sz.resize(sn); sr2.resize(sn)
	for i in sn:
		var s = data.settlements[i]
		var pos: Vector2 = s.pos
		var rr: float = s.radius + 7.0
		sx[i] = pos.x
		sz[i] = pos.y
		sr2[i] = rr * rr
	for iz in n:
		for ix in n:
			var p := Vector2(float(ix) * CELL + rng.randf_range(0.0, CELL), float(iz) * CELL + rng.randf_range(0.0, CELL))
			if p.x < 2.0 or p.y < 2.0 or p.x > edge_hi or p.y > edge_hi:
				continue
			# nav.ci() = clampi(int(round(w / cell)), 0, res - 1)；nav.at() = z * res + x
			var cix := clampi(int(round(p.x / nav_cell)), 0, nav_res - 1)
			var ciz := clampi(int(round(p.y / nav_cell)), 0, nav_res - 1)
			var ci := ciz * nav_res + cix
			if water[ci] == 1 or road[ci] == 1 or ford[ci] == 1 or bridge[ci] == 1:
				continue
			var h := hm.height_at(p.x, p.y)
			if h < sea_lim:
				continue
			var slope := hm.slope_at(p.x, p.y)
			if slope > max_slope:
				continue
			var blocked := false
			for k in sn:
				var dx := p.x - sx[k]
				var dz := p.y - sz[k]
				if dx * dx + dz * dz < sr2[k]:
					blocked = true
					break
			if blocked:
				continue
			var dens := _density(kind, p, h, slope)
			if dens <= 0.0:
				continue
			if rng.randf() > dens:
				continue
			list.append(_make_transform(kind, p, h, slope))
	if list.size() > target:
		_shuffle(list)
		list.resize(target)
	counts[kind] = list.size()
	if list.is_empty():
		return
	_emit_chunks(kind, mesh, list, mat, range_end, range_end_strategic)

func _density(kind: String, p: Vector2, h: float, slope: float) -> float:
	var i := clampi(int(p.y / data.hm.cell), 0, data.hm.res - 1) * data.hm.res + clampi(int(p.x / data.hm.cell), 0, data.hm.res - 1)
	if i >= data.gen.forest_mask.size():
		return 0.0
	var forest: float = data.gen.forest_mask[i]
	var desert: float = data.gen.biome_desert[i]
	var rock: float = data.gen.biome_rock[i]
	var v := p.y / cfg.map_size   # 0 = 北
	# pow() 是这里唯一的"贵函数"，而 forest == 0（地图上大片无林区）时 pow(0, 1.4) 恒为 0：
	# 先判掉，结果逐位不变（0 * 系数 = 0，后面照样走 dens <= 0 分支）
	if forest <= 0.0 and (kind == "conifer" or kind == "broadleaf"):
		return 0.0
	match kind:
		"conifer":
			# 北部山麓针叶林
			var north := 1.0 - smoothstep(0.30, 0.72, v)
			return pow(forest, 1.4) * (0.25 + 0.95 * north)
		"broadleaf":
			var mid := smoothstep(0.22, 0.42, v) * (1.0 - smoothstep(0.86, 1.0, v))
			return pow(forest, 1.4) * (0.55 + 0.55 * mid) * (1.0 - desert * 0.85)
		"cactus":
			return clampf((desert - 0.42) * 1.6, 0.0, 1.0) * 0.11 * (1.0 - smoothstep(60.0, 90.0, h))
		"deadtree":
			return clampf(maxf((desert - 0.30) * 1.1, (rock - 0.62) * 1.2), 0.0, 1.0) * 0.075
		_:
			return clampf(maxf((rock - 0.50) * 1.5, (slope - 0.26) * 2.2), 0.0, 1.0) * 0.42

func _make_transform(kind: String, p: Vector2, h: float, slope: float) -> Transform3D:
	var s := 1.0
	var sy := 1.0
	match kind:
		"conifer":
			s = rng.randf_range(0.75, 1.45)
			sy = rng.randf_range(0.85, 1.5)
		"broadleaf":
			s = rng.randf_range(0.8, 1.4)
			sy = rng.randf_range(0.85, 1.3)
		"cactus":
			s = rng.randf_range(0.6, 1.2)
			sy = rng.randf_range(0.7, 1.4)
		"deadtree":
			s = rng.randf_range(0.7, 1.2)
			sy = rng.randf_range(0.8, 1.3)
		_:
			s = rng.randf_range(0.5, 1.9)
			sy = rng.randf_range(0.5, 1.4)
	var tilt := 0.0
	if kind == "rock":
		tilt = rng.randf_range(-0.25, 0.25)
	var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
	if tilt != 0.0:
		b = b.rotated(Vector3.RIGHT, tilt)
	b = b.scaled(Vector3(s, sy, s * rng.randf_range(0.85, 1.15)))
	return Transform3D(b, Vector3(p.x, h - 0.25, p.y))

func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

## 把实例按 8x8 区块拆分，每块一个 MultiMeshInstance3D（获得真正的视锥剔除）
func _emit_chunks(kind: String, mesh: Mesh, list: Array[Transform3D], mat: ShaderMaterial, range_end: float, range_end_strategic: float) -> void:
	var nchunks := int(ceil(cfg.map_size / CHUNK))
	var buckets: Dictionary = {}
	for t in list:
		var cx := clampi(int(t.origin.x / CHUNK), 0, nchunks - 1)
		var cz := clampi(int(t.origin.z / CHUNK), 0, nchunks - 1)
		var key := cz * nchunks + cx
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(t)
	for key in buckets.keys():
		var arr: Array = buckets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		# 6b 试过 RenderingServer.multimesh_set_buffer 批量写（每实例 12 个 float，3 行 × 4 列行主序）：
		# 正确性没问题（探针能从场景读回同一批 Transform3D），但**反而更慢** —— 发射段 2.6 → 5.4 ms；
		# 在 GDScript 里逐实例填 12 个 float 的开销，大于 5163 次 set_instance_transform 的调用开销。
		# 每桶只有约 80 个实例，这个规模不值得批量写，改回逐实例写（数据见 ROADMAP §12.7）。
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [kind, key]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = range_end
		mmi.visibility_range_end_margin = 40.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.set_meta("strategic_range", range_end_strategic)
		root.add_child(mmi)

# =============================================================== 网格
func _make_conifer() -> Mesh:
	var k := MeshKit.new()
	var trunk := Color(0.28, 0.19, 0.12)
	k.add_cylinder(Vector3(0, 0, 0), 0.28, 0.17, 2.2, 6, MeshKit.to_color(trunk))
	var g1 := Color(0.13, 0.28, 0.14)
	var g2 := Color(0.16, 0.33, 0.16)
	var g3 := Color(0.20, 0.38, 0.19)
	k.add_cone(Vector3(0, 1.5, 0), 2.05, 3.4, 7, MeshKit.to_color(g1))
	k.add_cone(Vector3(0, 3.4, 0), 1.55, 3.2, 7, MeshKit.to_color(g2))
	k.add_cone(Vector3(0, 5.3, 0), 1.02, 2.9, 7, MeshKit.to_color(g3))
	return k.build()

func _make_broadleaf() -> Mesh:
	var k := MeshKit.new()
	k.add_cylinder(Vector3(0, 0, 0), 0.34, 0.24, 3.4, 6, MeshKit.to_color(Color(0.31, 0.22, 0.14)))
	var l1 := Color(0.24, 0.38, 0.15)
	var l2 := Color(0.29, 0.44, 0.18)
	var l3 := Color(0.21, 0.34, 0.14)
	k.add_sphere(Vector3(0, 4.6, 0), 2.45, 7, 5, MeshKit.to_color(l1))
	k.add_sphere(Vector3(1.7, 3.9, 0.5), 1.55, 6, 4, MeshKit.to_color(l2))
	k.add_sphere(Vector3(-1.5, 4.2, -0.7), 1.35, 6, 4, MeshKit.to_color(l3))
	return k.build()

func _make_cactus() -> Mesh:
	var k := MeshKit.new()
	var c := Color(0.30, 0.47, 0.26)
	var c2 := Color(0.36, 0.54, 0.30)
	k.add_cylinder(Vector3(0, 0, 0), 0.52, 0.44, 3.4, 7, MeshKit.to_color(c))
	k.add_sphere(Vector3(0, 3.4, 0), 0.44, 6, 4, MeshKit.to_color(c2))
	# 手臂
	k.push_transform(Transform3D(Basis(Vector3.BACK, deg_to_rad(-90.0)), Vector3(0.5, 1.7, 0)))
	k.add_cylinder(Vector3.ZERO, 0.3, 0.26, 1.0, 6, MeshKit.to_color(c2))
	k.pop_transform()
	k.push_transform(Transform3D(Basis(Vector3.FORWARD, deg_to_rad(90.0)), Vector3(0.5, 2.7, 0)))
	k.add_cylinder(Vector3.ZERO, 0.28, 0.24, 1.1, 6, MeshKit.to_color(c2))
	k.pop_transform()
	k.push_transform(Transform3D(Basis(Vector3.BACK, deg_to_rad(-90.0)), Vector3(-0.5, 1.2, 0)))
	k.add_cylinder(Vector3.ZERO, 0.26, 0.22, 0.8, 6, MeshKit.to_color(c2))
	k.pop_transform()
	return k.build()

func _make_deadtree() -> Mesh:
	var k := MeshKit.new()
	var c := Color(0.33, 0.28, 0.22)
	k.add_cylinder(Vector3(0, 0, 0), 0.32, 0.2, 3.2, 5, MeshKit.to_color(c))
	for i in 4:
		var a := rng.randf_range(0, TAU)
		var hh := rng.randf_range(2.0, 3.2)
		var len := rng.randf_range(1.2, 2.2)
		var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(35.0, 60.0)))
		k.push_transform(Transform3D(b, Vector3(0, hh, 0)))
		k.add_cylinder(Vector3.ZERO, 0.15, 0.06, len, 4, MeshKit.to_color(c))
		k.pop_transform()
	return k.build()

func _make_rock() -> Mesh:
	var k := MeshKit.new()
	var c := Color(0.42, 0.41, 0.39)
	var c2 := Color(0.34, 0.33, 0.32)
	k.add_sphere(Vector3(0, 0.55, 0), 1.0, 6, 4, MeshKit.to_color(c))
	k.add_sphere(Vector3(0.75, 0.35, 0.35), 0.62, 5, 3, MeshKit.to_color(c2))
	k.add_sphere(Vector3(-0.6, 0.3, -0.45), 0.5, 5, 3, MeshKit.to_color(c2))
	return k.build()
