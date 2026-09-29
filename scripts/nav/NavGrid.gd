## =============================================================================
##  NavGrid —— 寻路栅格：可通行性 + 地形移动速度
##
##  【移动速度（骑砍式地形影响）】
##    道路  1.2x   （平整官道）
##    草地  1.0x
##    森林  0.7x
##    山地  0.5x   （高度 >= mountain_line）
##    雪地  0.4x   （高度 >= snow_line，优先级最高）
##  优先级：道路 > 雪地 > 山地 > 森林 > 草地
##
##  【不可通行】海洋 / 湖泊 / 河流（渡口 ford 与桥梁 bridge 除外）
##  寻路代价函数 cost = 距离 / 速度，见 Pathfinder。
## =============================================================================
class_name NavGrid
extends RefCounted

var res: int = 257
var cell: float = 4.0
var size: float = 1024.0

var blocked: PackedByteArray   ## 1 = 不可通行
var speed: PackedFloat32Array  ## 移动速度倍率
var road: PackedByteArray      ## 1 = 道路
var forest: PackedByteArray    ## 1 = 森林
var water: PackedByteArray     ## 1 = 水（海/湖/河）
var river: PackedByteArray     ## 1 = 河流（架桥可通行；海洋/湖泊不行）
var ford: PackedByteArray      ## 1 = 浅滩
var bridge: PackedByteArray    ## 1 = 桥

func _init(p_res: int, p_size: float) -> void:
	res = p_res
	size = p_size
	cell = size / float(res - 1)
	var n := res * res
	blocked.resize(n)
	speed.resize(n)
	road.resize(n)
	forest.resize(n)
	water.resize(n)
	river.resize(n)
	ford.resize(n)
	bridge.resize(n)

func ci(world: float) -> int:
	return clampi(int(round(world / cell)), 0, res - 1)

func at(cx: int, cz: int) -> int:
	return clampi(cz, 0, res - 1) * res + clampi(cx, 0, res - 1)

func world_of(cx: int, cz: int) -> Vector2:
	return Vector2(float(cx) * cell, float(cz) * cell)

func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(ci(p.x), ci(p.y))

func is_blocked(cx: int, cz: int) -> bool:
	if cx < 0 or cz < 0 or cx >= res or cz >= res:
		return true
	return blocked[cz * res + cx] == 1

func speed_at(cx: int, cz: int) -> float:
	if cx < 0 or cz < 0 or cx >= res or cz >= res:
		return 1.0
	return speed[cz * res + cx]

func speed_at_world(p: Vector2) -> float:
	return speed_at(ci(p.x), ci(p.y))

## 依据高度场生成通行性与速度
## road_mode = true 时：河流可通行但代价极高（让道路自己找到过河点去架桥）
func build_from(cfg: MapConfig, hm: Heightmap, gen: HeightmapGenerator, road_mode: bool = false) -> void:
	for z in res:
		for x in res:
			var w := Vector2(float(x) * cell, float(z) * cell)
			var h := hm.height_at(w.x, w.y)
			var i := z * res + x
			var is_w := h <= cfg.sea_level + 0.35
			water[i] = 1 if is_w else 0
			# 森林标记（用于速度）
			var fi := clampi(int(w.y / hm.cell), 0, hm.res - 1) * hm.res + clampi(int(w.x / hm.cell), 0, hm.res - 1)
			var f := gen.forest_mask[fi] if fi < gen.forest_mask.size() else 0.0
			forest[i] = 1 if f >= 0.35 else 0
			# 湖泊
			for l in gen.lakes:
				if w.distance_to(l.center) <= l.radius * 1.02:
					var lw: float = l.water_level
					if h <= lw - 0.15:
						water[i] = 1
						is_w = true
			blocked[i] = 1 if is_w else 0
			# 速度分级
			var s := 1.0
			if h >= cfg.snow_line:
				s = 0.4
			elif h >= cfg.mountain_line:
				s = 0.5
			elif forest[i] == 1:
				s = 0.7
			speed[i] = s
	_stamp_rivers(cfg, hm, gen)
	if road_mode:
		for i in blocked.size():
			if river[i] == 1:
				# 修路时可以「过河」（代价很高，于是会自然选择最窄处）
				blocked[i] = 0
				speed[i] = 0.18
			elif water[i] == 1:
				blocked[i] = 1

## 河道：沿折线按宽度盖格子；浅滩（ford）不封路
func _stamp_rivers(cfg: MapConfig, hm: Heightmap, gen: HeightmapGenerator) -> void:
	for r in gen.rivers:
		var pts: PackedVector3Array = r.points
		var widths: PackedFloat32Array = r.widths
		var fords: PackedInt32Array = r.fords
		var ford_idx := {}
		for fi in fords:
			ford_idx[fi] = true
		for k in pts.size():
			var p := Vector2(pts[k].x, pts[k].z)
			var wl := pts[k].y
			var rad: float = widths[k]
			var is_ford: bool = ford_idx.has(k)
			var cr := int(ceil(rad / cell)) + 1
			var cx := ci(p.x)
			var cz := ci(p.y)
			for dz in range(-cr, cr + 1):
				for dx in range(-cr, cr + 1):
					var x := cx + dx
					var z := cz + dz
					if x < 0 or z < 0 or x >= res or z >= res:
						continue
					var cw := Vector2(float(x) * cell, float(z) * cell)
					var d := cw.distance_to(p)
					if d > rad * 1.05:
						continue
					var i := z * res + x
					water[i] = 1
					river[i] = 1
					if is_ford:
						# 渡口：可通行，但速度打折（涉水）
						ford[i] = 1
						blocked[i] = 0
						speed[i] = minf(speed[i], 0.6)
					else:
						blocked[i] = 1

## 道路：铺路后速度 1.2x（不解除阻挡，桥由 apply_bridges 单独处理）
func apply_roads(roads: Array) -> void:
	for pts in roads:
		for k in pts.size():
			var p: Vector2 = pts[k]
			_stamp_road_point(p, 1.0)

func _stamp_road_point(p: Vector2, w_mul: float) -> void:
	var rad := 3.2 * w_mul
	var cr := int(ceil(rad / cell)) + 1
	var cx := ci(p.x)
	var cz := ci(p.y)
	for dz in range(-cr, cr + 1):
		for dx in range(-cr, cr + 1):
			var x := cx + dx
			var z := cz + dz
			if x < 0 or z < 0 or x >= res or z >= res:
				continue
			var cw := Vector2(float(x) * cell, float(z) * cell)
			if cw.distance_to(p) > rad:
				continue
			var i := z * res + x
			road[i] = 1
			if blocked[i] == 0:
				speed[i] = 1.2

## 桥梁：把道路跨过的水面格子变成可通行的桥（含 1 格邻域，保证 A* 能穿过）
func apply_bridges(cells: Array[Vector2i]) -> void:
	for c in cells:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var x := c.x + dx
				var z := c.y + dz
				if x < 0 or z < 0 or x >= res or z >= res:
					continue
				var i := z * res + x
				if water[i] == 1:
					bridge[i] = 1
					blocked[i] = 0
					road[i] = 1
					speed[i] = 1.2

## 供小地图/提示使用
func describe_at_world(p: Vector2) -> String:
	var cx := ci(p.x)
	var cz := ci(p.y)
	var i := at(cx, cz)
	if blocked[i] == 1:
		return "水域" if water[i] == 1 else "不可通行"
	if bridge[i] == 1:
		return "桥梁"
	if ford[i] == 1:
		return "浅滩"
	if road[i] == 1:
		return "道路 (1.2x)"
	if forest[i] == 1:
		return "森林 (0.7x)"
	var s := speed[i]
	if is_equal_approx(s, 0.4):
		return "雪地 (0.4x)"
	if is_equal_approx(s, 0.5):
		return "山地 (0.5x)"
	return "草原 (1.0x)"
