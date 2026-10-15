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
##    每种植被按 4x4 个区块拆成多个 MultiMeshInstance3D（边长按尺寸推导，见 VEG_CHUNKS_PER_AXIS）：
##      · 每个区块有独立 AABB → 视锥剔除真正生效（整张图的植被不会全画）
##      · 每块设置 visibility_range_end → 远处整块消失
##      · 全部 cast_shadow = OFF（阴影 pass 只留给地形与建筑）
##      · 拉远到战略视图时整个植被根节点直接隐藏
##    合计约 9k 实例，但同屏通常只有几百到一两千个实例参与绘制。
## =============================================================================
class_name VegetationScatter
extends RefCounted

## 植被区块边长：按尺寸推导 —— 每类分 VEG_CHUNKS_PER_AXIS × VEG_CHUNKS_PER_AXIS 块，节点数不随地图膨胀。
## 1024 m → 256 m（与 6b 之前一致，1024 m 的节点数不变）；4096 m → 1024 m。
## 代价是剔除粒度变粗（大块「只要一角在视锥里」就整块画），但战略视图也一起拉远了。
const VEG_CHUNKS_PER_AXIS := 4
## 候选格边长（米）：**绝对米数**，不随地图变。它的含义是「每 7 m 抽一个候选点」——
## 只有保持绝对值，「每平方公里多少棵」这个密度属性才会在 4 倍图上不变（ROADMAP §16.8）。
## 第七轮 ②：7.0 → 5.0。稀疏是「地图看起来空」的直接原因（实测 4.6k 个/km²，
## 而参考项目是 12.6 万个/km² 的量级）。候选点密度 = 1/CELL²，所以这一条改动
## **等价于把整张图的装饰物密度乘 1.96**，而「绝对米数、不随尺寸变」这条性质不变
## （ROADMAP §16.8 的口径：换 4 倍图后每平方公里棵数不变）。
const CELL := 5.0
## 各类（针叶/阔叶/仙人掌/枯木/岩石）的绘制距离，基准 = 1024 m 世界，使用时按 size_scale 放大
const RANGE_END := [380.0, 340.0, 260.0, 260.0, 340.0]
const RANGE_STRATEGIC := [260.0, 250.0, 180.0, 200.0, 220.0]

var cfg: MapConfig
var data: MapData
var rng: RandomNumberGenerator
var root: Node3D
var counts: Dictionary = {}

func chunk_size() -> float:
	return cfg.map_size / float(VEG_CHUNKS_PER_AXIS)

## 每类植被的预算：基准值是 1024 m 世界的棵数，按**面积**倍率放大。
## 密度是世界的属性、不是预算：旧世界 4096 m 实测 8420 棵 = 五个上限之和，正好说明
## 约束已经从「密度」变成了「写死的预算」—— 那才是换世界后植被看起来变稀的原因。
func budget(base: int) -> int:
	return int(round(float(base) * cfg.area_scale()))

func build(parent: Node3D, mat: ShaderMaterial) -> void:
	root = Node3D.new()
	root.name = "Vegetation"
	parent.add_child(root)
	rng = cfg.make_rng("vegetation")
	if not cfg.vegetation_enabled:
		return

	# ---- 第六轮 6b：单遍筛选 ----
	# 以前五类各自扫一遍 7 m 网格（5 × n² 次），每遍都把完全相同的空间排除重算一次
	# （水面/道路/渡口/桥、height_at、slope_at、18 个定居点距离，后者原本每个点都 distance_to 带 sqrt）。
	# 现在一遍网格扫过：排除只算一次，五类密度在同一次遍历里判定 → 5×(排除+密度) 降到 1×排除 + 5×密度。
	# 候选点从「每类各自抖动」改成「五类共用格点」，rng 抽取顺序随之改变：布局与旧世界不同是
	# **有意**的改动，随第六轮一起重基线（ROADMAP §16.8），不是回归。
	var kinds: Array = ["conifer", "broadleaf", "cactus", "deadtree", "rock"]
	var meshes: Array = [_make_conifer(), _make_broadleaf(), _make_cactus(), _make_deadtree(), _make_rock()]
	var caps: Array = [budget(cfg.conifer_count), budget(cfg.broadleaf_count), budget(cfg.cactus_count), budget(cfg.deadtree_count), budget(cfg.rock_count)]
	var lists: Array = [[], [], [], [], []]
	_sweep(kinds, lists)
	var sc := cfg.size_scale()
	for ki in kinds.size():
		var list: Array = lists[ki]
		var cap: int = caps[ki]
		if list.size() > cap:
			_shuffle(list)
			list.resize(cap)
		var kind: String = kinds[ki]
		counts[kind] = list.size()
		if list.is_empty():
			continue
		var re: float = RANGE_END[ki]
		var rs: float = RANGE_STRATEGIC[ki]
		_emit_chunks(kind, meshes[ki], list, mat, re * sc, rs * sc)

func total() -> int:
	var s := 0
	for k in counts.keys():
		s += int(counts[k])
	return s

# =============================================================== 单遍筛选
func _sweep(kinds: Array, lists: Array) -> void:
	var nav := data.nav_fine
	var hm := data.hm
	var hm_cell := hm.cell
	var hm_res := hm.res
	var nav_res := nav.res
	var nav_cell := nav.cell
	var water := nav.water
	var road := nav.road
	var ford := nav.ford
	var bridge := nav.bridge
	var forest_mask := data.gen.forest_mask
	var biome_desert := data.gen.biome_desert
	var biome_rock := data.gen.biome_rock
	var mask_n := forest_mask.size()
	var sea_lim := cfg.sea_level + 1.6
	var max_slope := cfg.max_slope_veg
	var edge_hi := cfg.map_size - 2.0
	var inv_size := 1.0 / cfg.map_size
	# 定居点摊平成三个并行数组，半径先 +7 再平方：原来是 p.distance_to(s.pos) < s.radius + 7.0
	# （sqrt 与平方比较数学等价；用 float64 存，避免 float32 截断在边界上翻转判定）
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
	var n := int(cfg.map_size / CELL)
	var nk := kinds.size()
	for iz in n:
		for ix in n:
			var p := Vector2(float(ix) * CELL + rng.randf_range(0.0, CELL), float(iz) * CELL + rng.randf_range(0.0, CELL))
			if p.x < 2.0 or p.y < 2.0 or p.x > edge_hi or p.y > edge_hi:
				continue
			# ---- 空间排除：与植被类型无关，所以整格只算一次（6b 省下来的就是这四遍）----
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
			# 生物群系遮罩索引与纬度权重也是整格一次
			var mi := clampi(int(p.y / hm_cell), 0, hm_res - 1) * hm_res + clampi(int(p.x / hm_cell), 0, hm_res - 1)
			if mi >= mask_n:
				continue
			var forest: float = forest_mask[mi]
			var desert: float = biome_desert[mi]
			var rock: float = biome_rock[mi]
			var v := p.y * inv_size   # 0 = 北
			# ---- 五类各自的密度判定 ----
			for ki in nk:
				var kind: String = kinds[ki]
				var dens := _density(kind, forest, desert, rock, v, h, slope)
				if dens <= 0.0:
					continue
				if rng.randf() > dens:
					continue
				var list: Array = lists[ki]
				list.append(_make_transform(kind, p, h, slope))

func _density(kind: String, forest: float, desert: float, rock: float, v: float, h: float, slope: float) -> float:
	# pow() 是这里唯一的"贵函数"，而 forest == 0（地图上大片无林区）时 pow(0, 1.4) 恒为 0：
	# 先判掉，结果不变（0 * 系数 = 0，后面照样走 dens <= 0 分支）
	if forest <= 0.0 and (kind == "conifer" or kind == "broadleaf"):
		return 0.0
	match kind:
		"conifer":
			# 北部山麓针叶林
			var north := 1.0 - smoothstep(0.30, 0.72, v)
			return pow(forest, 1.4) * (0.35 + 1.05 * north)
		"broadleaf":
			var mid := smoothstep(0.22, 0.42, v) * (1.0 - smoothstep(0.86, 1.0, v))
			return pow(forest, 1.4) * (0.70 + 0.70 * mid) * (1.0 - desert * 0.85)
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
func _emit_chunks(kind: String, mesh: Mesh, list: Array, mat: ShaderMaterial, range_end: float, range_end_strategic: float) -> void:
	var chunk := chunk_size()
	var nchunks := int(ceil(cfg.map_size / chunk))
	var buckets: Dictionary = {}
	for t in list:
		var cx := clampi(int(t.origin.x / chunk), 0, nchunks - 1)
		var cz := clampi(int(t.origin.z / chunk), 0, nchunks - 1)
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
