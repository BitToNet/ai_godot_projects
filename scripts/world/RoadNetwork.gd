## =============================================================================
##  RoadNetwork —— 道路网生成
##
##  【道路生成算法】
##  1. 连接关系：
##       同势力：王都 → 每座城镇；城镇 → 其属下村庄；城镇 → 城镇
##       跨势力：王都 ↔ 王都（形成贯穿大陆的官道主干）
##  2. 逐条用 A* 在「道路寻路栅格」上求路径。该栅格比战术栅格更粗（8 米/格），
##     并且把河流设为「可通行但代价极高」，因此道路会自己找到最窄的过河点，
##     在那个位置生成桥梁（bridge），而海洋与湖泊依然不可通行。
##  3. 路径按 3 米步长重采样 → 写入 MapData.roads，供：
##       · 地形 splat 图（R 通道 → 地形 Shader 画成土路）
##       · NavGrid（道路格速度 1.2x，桥格解除阻挡）
##       · 商队 AI 的寻路偏好（道路代价低，自然走官道）
## =============================================================================
class_name RoadNetwork
extends RefCounted

var cfg: MapConfig
var data: MapData
var rng: RandomNumberGenerator
var finder: Pathfinder

func _init(p_cfg: MapConfig, p_data: MapData) -> void:
	cfg = p_cfg
	data = p_data
	rng = cfg.make_rng("roads")

func build() -> void:
	# ---- 1) 建立连接关系 ----
	var pairs := {}
	for f in data.factions:
		var castles := data.settlements_of_kind(f.id, Settlement.Kind.CASTLE)
		var towns := data.settlements_of_kind(f.id, Settlement.Kind.TOWN)
		var villages := data.settlements_of_kind(f.id, Settlement.Kind.VILLAGE)
		if castles.size() == 0:
			continue
		var cap := castles[0]
		for t in towns:
			_add_pair(pairs, cap, t)
		for i in towns.size():
			for j in range(i + 1, towns.size()):
				_add_pair(pairs, towns[i], towns[j])
		for v in villages:
			var host: Settlement = null
			if v.parent_town >= 0:
				host = data.settlements[v.parent_town]
			elif towns.size() > 0:
				host = towns[0]
			if host != null:
				_add_pair(pairs, host, v)
	# 跨势力官道
	var capitals: Array[Settlement] = []
	for f in data.factions:
		var cs := data.settlements_of_kind(f.id, Settlement.Kind.CASTLE)
		if cs.size() > 0:
			capitals.append(cs[0])
	for i in capitals.size():
		for j in range(i + 1, capitals.size()):
			_add_pair(pairs, capitals[i], capitals[j])

	# ---- 2) 逐条寻路 ----
	finder = Pathfinder.new(data.nav_road)
	finder.heuristic_weight = 1.6
	var all_bridges: Array[Vector2i] = []
	for key in pairs.keys():
		var s: Settlement = data.settlements[pairs[key].x]
		var t: Settlement = data.settlements[pairs[key].y]
		var pts := finder.find_path(s.pos, t.pos)
		if pts.size() < 2:
			continue
		var poly := PackedVector2Array()
		for p in pts:
			poly.append(Vector2(p.x, p.z))
		poly = _resample(poly, 3.0)
		data.roads.append(poly)
		s.neighbors.append(t.id)
		t.neighbors.append(s.id)
		_collect_bridges(poly, all_bridges)

	# ---- 3) 写回寻路栅格 ----
	data.nav_fine.apply_roads(data.roads)
	data.nav_fine.apply_bridges(all_bridges)
	data.nav_coarse.apply_roads(data.roads)
	data.nav_coarse.apply_bridges(all_bridges)

	# ---- 4) 栅格至此定型，重建连通分量（供 Pathfinder 做 O(1) 可达性预判） ----
	# 必须放在 apply_roads / apply_bridges 之后：它们会改变 blocked[]。
	data.nav_fine.rebuild_components()
	data.nav_coarse.rebuild_components()

func _add_pair(pairs: Dictionary, a: Settlement, b: Settlement) -> void:
	if a == null or b == null or a.id == b.id:
		return
	var k := "%d_%d" % [mini(a.id, b.id), maxi(a.id, b.id)]
	if pairs.has(k):
		return
	pairs[k] = Vector2i(a.id, b.id)

## 重采样：把稀疏的 A* 折线变成 3 米间隔的密集折线（贴地 + splat 描绘更准确）
func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2:
		return pts
	out.append(pts[0])
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var d := a.distance_to(b)
		var n := int(ceil(d / step))
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) / float(n)))
	return out

## 找出道路上的过河点（细栅格中 water=1 的格子）→ 桥梁
## all_cells: 供 NavGrid.apply_bridges 打通通行
## bridges:   合并后的桥（几何体：中心点 / 方向 / 长度）
func _collect_bridges(poly: PackedVector2Array, all_cells: Array[Vector2i]) -> void:
	var nav := data.nav_fine
	var run: Array[Vector2] = []
	for i in range(1, poly.size()):
		var a := poly[i - 1]
		var b := poly[i]
		var n := int(ceil(a.distance_to(b) / 2.0))
		for k in range(0, n + 1):
			var p := a.lerp(b, float(k) / float(maxi(1, n)))
			var c := nav.cell_of(p)
			var idx := nav.at(c.x, c.y)
			var is_water := nav.water[idx] == 1 and nav.river[idx] == 1
			if is_water:
				var dup := false
				for e in all_cells:
					if e == c:
						dup = true
						break
				if not dup:
					all_cells.append(c)
				run.append(p)
			else:
				if run.size() >= 2:
					_flush_bridge(run)
				run.clear()
	if run.size() >= 2:
		_flush_bridge(run)

func _flush_bridge(run: Array[Vector2]) -> void:
	var a: Vector2 = run[0]
	var b: Vector2 = run[run.size() - 1]
	var c := a.lerp(b, 0.5)
	var d := b - a
	if d.length() < 0.5:
		return
	d = d.normalized()
	for e in data.bridges:
		if Vector2(e["pos"]).distance_to(c) < 14.0:
			return
	data.bridges.append({"pos": c, "dir": d, "len": a.distance_to(b) + 9.0})

## 生成桥的可见网格（在材质就绪后由 Main 调用）
func build_bridges(parent: Node3D, mat: Material) -> void:
	if data.bridges.is_empty():
		return
	var root := Node3D.new()
	root.name = "Bridges"
	parent.add_child(root)
	var wood := Color(0.40, 0.28, 0.17)
	var wood_d := Color(0.28, 0.19, 0.12)
	var stone := Color(0.55, 0.53, 0.50)
	for b in data.bridges:
		var pos: Vector2 = b["pos"]
		var dir: Vector2 = b["dir"]
		var ln: float = b["len"]
		var kit := MeshKit.new()
		var ang := atan2(dir.x, dir.y)
		var base_y := data.hm.height_at(pos.x, pos.y) + 2.5
		kit.push_transform(Transform3D(Basis(Vector3.UP, ang), Vector3(pos.x, base_y, pos.y)))
		# 桥面
		kit.add_box(Vector3(0, 0, 0), Vector3(6.0, 0.55, ln), MeshKit.to_color(wood), MeshKit.to_color(wood_d))
		# 桥墩
		var piers := maxi(2, int(ln / 6.0))
		for i in piers:
			var t := (float(i) + 0.5) / float(piers)
			var z := -ln * 0.5 + ln * t
			kit.add_box(Vector3(-2.6, -1.9, z), Vector3(0.9, 3.4, 0.9), MeshKit.to_color(stone))
			kit.add_box(Vector3(2.6, -1.9, z), Vector3(0.9, 3.4, 0.9), MeshKit.to_color(stone))
		# 栏杆
		for sgn in [-1.0, 1.0]:
			kit.add_box(Vector3(2.9 * sgn, 1.0, 0), Vector3(0.32, 0.32, ln), MeshKit.to_color(wood))
			var posts := maxi(2, int(ln / 3.0))
			for i in posts:
				var t2 := (float(i) + 0.5) / float(posts)
				var z2 := -ln * 0.5 + ln * t2
				kit.add_box(Vector3(2.9 * sgn, 0.8, z2), Vector3(0.28, 1.7, 0.28), MeshKit.to_color(wood_d))
		kit.pop_transform()
		var mesh := kit.build()
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Bridge_%d" % root.get_child_count()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mi)

