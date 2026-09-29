## =============================================================================
##  SettlementBuilder —— 定居点选址 + 程序化建筑生成
##
##  【选址算法】
##  1. 以 12 米网格扫描全图候选点，对每个候选点计算「势力契合度」评分：
##       生物群系契合（中央草原 / 北境雪山 / 东部沙漠）
##     - 与理想高度(约 35m)的偏差
##     - 坡度惩罚（陡坡不能建城）
##     - 与势力领地中心的距离
##     - 森林惩罚
##     同时硬性排除：水域 / 河道 / 湖 / 高程越界 / 离已有定居点太近
##  2. 每个势力按 王都 → 城镇 → 村庄 的顺序贪心取分数最高者，
##     村庄额外约束「必须在其所属城镇 70~190 米范围内」。
##  3. 选址完成后把地基用 Heightmap.flatten 压平（平滑过渡），
##     这样建筑不会插进斜坡里。
##
##  【建筑生成】全部由 MeshKit 用方块 / 棱柱 / 圆柱 / 圆锥拼装，
##  顶点 alpha 约定：0=普通建材，1=窗户(夜间自发光)，0.5=旗帜(顶点风动)。
## =============================================================================
class_name SettlementBuilder
extends RefCounted

var cfg: MapConfig
var data: MapData
var rng: RandomNumberGenerator
var names: NameForge
var kit: MeshKit

const STONE := Color(0.58, 0.56, 0.53)
const STONE_DARK := Color(0.42, 0.41, 0.40)
const WOOD := Color(0.42, 0.30, 0.19)
const WOOD_DARK := Color(0.30, 0.21, 0.13)
const THATCH := Color(0.72, 0.60, 0.32)
const ROOF_TILE := Color(0.52, 0.24, 0.20)
const ROOF_SLATE := Color(0.30, 0.33, 0.40)
const WINDOW_COL := Color(1.0, 0.78, 0.35)
const WHEAT := Color(0.78, 0.68, 0.34)
const PLOW := Color(0.42, 0.32, 0.22)
const GRASS_PLOT := Color(0.35, 0.45, 0.20)
const CANVAS := Color(0.80, 0.76, 0.66)

var _water_flags: PackedByteArray
var _flag_res: int = 256
var _flag_cell: float = 4.0
var _taken: Array[Vector2] = []

func _init(p_cfg: MapConfig, p_data: MapData) -> void:
	cfg = p_cfg
	data = p_data
	rng = cfg.make_rng("settlements")
	names = NameForge.new(cfg.map_seed)
	kit = MeshKit.new()

# =============================================================== 选址
func place_all() -> void:
	_water_flags = data.gen.make_water_flags(_flag_res)
	_flag_cell = cfg.map_size / float(_flag_res - 1)

	# 为每个势力确定领地中心（吸附到陆地上）
	var homes: Array[Vector2] = []
	for f in data.factions:
		homes.append(_snap_to_land(Vector2(f.home_dir.x, f.home_dir.y) * cfg.map_size))

	var cands := _scan_candidates()

	for fi in data.factions.size():
		var f := data.factions[fi]
		var home := homes[fi]
		var min_d := cfg.min_settlement_distance
		# 王都
		var castle := _do_pick(cands, f, home, 0.0, 265.0, min_d)
		if castle == Vector2.INF:
			continue
		var cs := _make_settlement(castle, Settlement.Kind.CASTLE, f.id)
		# 城镇
		var towns: Array[Settlement] = []
		for t in cfg.towns_per_faction:
			var p := _do_pick(cands, f, castle, 130.0, 430.0, min_d)
			if p == Vector2.INF:
				p = _do_pick(cands, f, castle, 90.0, 520.0, min_d * 0.75)
			if p == Vector2.INF:
				continue
			towns.append(_make_settlement(p, Settlement.Kind.TOWN, f.id))
		# 村庄：挂靠到最近的城镇
		for v in cfg.villages_per_faction:
			var host: Settlement = null
			if towns.size() > 0:
				host = towns[v % towns.size()]
			var anchor: Vector2 = host.pos if host != null else castle
			var p2 := _do_pick(cands, f, anchor, 62.0, 190.0, min_d * 0.62)
			if p2 == Vector2.INF:
				p2 = _do_pick(cands, f, anchor, 45.0, 260.0, min_d * 0.45)
			if p2 == Vector2.INF:
				continue
			var vs := _make_settlement(p2, Settlement.Kind.VILLAGE, f.id)
			if host != null:
				vs.parent_town = host.id
				host.neighbors.append(vs.id)
				vs.neighbors.append(host.id)

	# 平整地基（在生成网格之前完成，网格与寻路都会读到平整后的高度）
	_flatten_all()
	# 面向：让村庄朝向所属城镇
	_assign_garrisons()

func _make_settlement(p: Vector2, kind: int, faction_id: int) -> Settlement:
	var s := Settlement.new()
	s.id = data.settlements.size()
	s.kind = kind
	s.faction_id = faction_id
	s.pos = p
	match kind:
		Settlement.Kind.CASTLE:
			s.radius = 27.0
			s.name = names.make_name("castle", faction_id)
		Settlement.Kind.TOWN:
			s.radius = 22.0
			s.name = names.make_name("town", faction_id)
		_:
			s.radius = 13.0
			s.name = names.make_name("village", faction_id)
	data.settlements.append(s)
	_taken.append(p)
	return s

func _scan_candidates() -> Array:
	var out: Array = []
	var step := 12.0
	var n := int(cfg.map_size / step)
	for iz in n:
		for ix in n:
			var p := Vector2(float(ix) * step + rng.randf_range(-4, 4), float(iz) * step + rng.randf_range(-4, 4))
			if p.x < 24.0 or p.y < 24.0 or p.x > cfg.map_size - 24.0 or p.y > cfg.map_size - 24.0:
				continue
			var h := data.hm.height_at(p.x, p.y)
			if h < 5.0 or h > 104.0:
				continue
			if _flags_at(p) != 0:
				continue
			var slope := data.hm.slope_at(p.x, p.y)
			if slope > 0.26:
				continue
			var d := _biome_at(p)
			out.append({
				"p": p, "h": h, "slope": slope, "desert": d.x, "moist": d.y, "forest": d.z,
			})
	return out

func _biome_at(p: Vector2) -> Vector3:
	var i := clampi(int(p.y / data.hm.cell), 0, data.hm.res - 1) * data.hm.res + clampi(int(p.x / data.hm.cell), 0, data.hm.res - 1)
	if i >= data.gen.biome_desert.size():
		return Vector3.ZERO
	return Vector3(data.gen.biome_desert[i], data.gen.biome_moist[i], data.gen.forest_mask[i])

func _flags_at(p: Vector2) -> int:
	var x := clampi(int(p.x / _flag_cell), 0, _flag_res - 1)
	var z := clampi(int(p.y / _flag_cell), 0, _flag_res - 1)
	return _water_flags[z * _flag_res + x]

## 评分：越高越适合建城
func _score(c: Dictionary, f: Faction, anchor: Vector2) -> float:
	var p: Vector2 = c.p
	var h: float = c.h
	var s := 0.0
	match f.biome_pref:
		0:  # 中央王国：湿润草原
			s += float(c.moist) * 45.0 - float(c.desert) * 70.0
		1:  # 北境：靠北、海拔较高、少沙漠
			s += (1.0 - p.y / cfg.map_size) * 55.0 + clampf(h - 20.0, 0.0, 70.0) * 0.45 - float(c.desert) * 55.0
		2:  # 沙漠苏丹国：干旱、靠东
			s += float(c.desert) * 78.0 - float(c.moist) * 32.0 + (p.x / cfg.map_size) * 25.0
	s -= absf(h - 34.0) * 0.55
	s -= float(c.slope) * 150.0
	s -= float(c.forest) * 26.0
	s -= p.distance_to(anchor) * 0.16
	# 避免紧贴地图边缘
	var edge := minf(minf(p.x, p.y), minf(cfg.map_size - p.x, cfg.map_size - p.y))
	s -= maxf(0.0, 60.0 - edge) * 1.2
	return s

## 在 [dmin, dmax] 环带内挑分数最高、且离已有定居点足够远的候选点
func _do_pick(cands: Array, f: Faction, anchor: Vector2, dmin: float, dmax: float, min_dist: float) -> Vector2:
	var best := Vector2.INF
	var best_s := -1e18
	for c in cands:
		var p: Vector2 = c.p
		var d := p.distance_to(anchor)
		if d < dmin or d > dmax:
			continue
		var ok := true
		for t in _taken:
			if p.distance_to(t) < min_dist:
				ok = false
				break
		if not ok:
			continue
		var sc := _score(c, f, anchor)
		if sc > best_s:
			best_s = sc
			best = p
	return best

func _snap_to_land(p: Vector2) -> Vector2:
	if not data.is_water(p.x, p.y):
		return p
	for r in range(1, 40):
		for k in 16:
			var a := TAU * float(k) / 16.0
			var q := p + Vector2(cos(a), sin(a)) * float(r) * 16.0
			if q.x < 0.0 or q.y < 0.0 or q.x > cfg.map_size or q.y > cfg.map_size:
				continue
			if not data.is_water(q.x, q.y) and data.hm.slope_at(q.x, q.y) < 0.3:
				return q
	return p

func _flatten_all() -> void:
	for s in data.settlements:
		var r := s.radius + 6.0
		# 地基高度 = 半径内采样点均值
		var sum := 0.0
		var cnt := 0
		for k in 24:
			var a := TAU * float(k) / 24.0
			var p := s.pos + Vector2(cos(a), sin(a)) * r * 0.6
			sum += data.hm.height_at(p.x, p.y)
			cnt += 1
		sum += data.hm.height_at(s.pos.x, s.pos.y) * 2.0
		cnt += 2
		s.ground_h = sum / float(cnt)
		data.hm.flatten(s.pos.x, s.pos.y, s.radius * 0.85, s.ground_h, s.radius * 0.9)

func _assign_garrisons() -> void:
	for s in data.settlements:
		match s.kind:
			Settlement.Kind.CASTLE:
				s.garrison = rng.randi_range(180, 320)
			Settlement.Kind.TOWN:
				s.garrison = rng.randi_range(80, 170)
			_:
				s.garrison = rng.randi_range(12, 45)

# =============================================================== 建筑
func build_all(parent: Node3D, mat: Material, light_mat: Material) -> void:
	for s in data.settlements:
		var root := Node3D.new()
		root.name = "Settlement_%d_%s" % [s.id, s.name]
		root.position = Vector3(s.pos.x, s.ground_h, s.pos.y)
		parent.add_child(root)
		kit.clear()
		match s.kind:
			Settlement.Kind.CASTLE:
				_build_castle(s)
			Settlement.Kind.TOWN:
				_build_town(s)
			_:
				_build_village(s)
		var mesh := kit.build()
		if mesh != null:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			root.add_child(mi)
		s.node = root
		_add_label(s, root)

func _add_label(s: Settlement, root: Node3D) -> void:
	var lab := Label3D.new()
	var f := data.faction(s.faction_id)
	lab.text = "%s\n%s" % [s.name, f.name]
	lab.position = Vector3(0, s.radius * 0.55 + 16.0, 0)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.fixed_size = false
	lab.pixel_size = 0.028
	lab.font_size = 96
	lab.outline_size = 26
	lab.outline_modulate = Color(0.03, 0.03, 0.05, 0.95)
	lab.modulate = f.color.lightened(0.25)
	lab.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	lab.render_priority = 10
	lab.visibility_range_end = 0.0
	root.add_child(lab)
	s.label = lab

func _xc(c: Color) -> Color:
	return MeshKit.to_color(c)

func _wc(c: Color) -> Color:
	return MeshKit.to_window(c)

func _fc(c: Color) -> Color:
	return MeshKit.to_flag(c)

func _window(pos: Vector3, dir: Vector3, w: float, h: float) -> void:
	## 在墙面上贴一块自发光小方片（夜间亮起）
	var d := dir.normalized()
	var right := Vector3(-d.z, 0, d.x)
	var a := pos - right * (w * 0.5) - Vector3(0, h * 0.5, 0)
	var b := pos + right * (w * 0.5) - Vector3(0, h * 0.5, 0)
	var c := pos + right * (w * 0.5) + Vector3(0, h * 0.5, 0)
	var dd := pos - right * (w * 0.5) + Vector3(0, h * 0.5, 0)
	kit.add_flat_quad(a, b, c, dd, _wc(WINDOW_COL))

# --------------------------------------------------------------- 城堡
func _build_castle(s: Settlement) -> void:
	var f := data.faction(s.faction_id)
	var y := 0.0
	var R := 19.0
	var segs := 8
	var hwall := 8.0
	var th := 2.6
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := Vector3(cos(a0) * R, 0, sin(a0) * R)
		var p1 := Vector3(cos(a1) * R, 0, sin(a1) * R)
		if i == 0:
			# 大门：矮墙 + 门楼
			var mid := (p0 + p1) * 0.5
			var dir := (p1 - p0).normalized()
			var ang := atan2(dir.x, dir.z)
			kit.add_box_xf(Transform3D(Basis(Vector3.UP, ang), mid + Vector3(0, 4.6, 0)),
				Vector3(1.6, 2.4, (p1 - p0).length()), _xc(STONE_DARK))
			# 门楼两侧塔
			kit.add_cylinder(p0 + Vector3(0, 0, 0), 4.0, 3.6, 13.0, 8, _xc(STONE))
			kit.add_cone(p0 + Vector3(0, 13.0, 0), 4.8, 5.0, 8, _xc(ROOF_TILE))
			kit.add_cylinder(p1, 4.0, 3.6, 13.0, 8, _xc(STONE))
			kit.add_cone(p1 + Vector3(0, 13.0, 0), 4.8, 5.0, 8, _xc(ROOF_TILE))
			continue
		var mid2 := (p0 + p1) * 0.5
		var dir2 := (p1 - p0).normalized()
		var ang2 := atan2(dir2.x, dir2.z)
		var L := (p1 - p0).length()
		# 墙体（上沿加一圈城垛）
		kit.add_box_xf(Transform3D(Basis(Vector3.UP, ang2), mid2 + Vector3(0, hwall * 0.5, 0)),
			Vector3(th, hwall, L), _xc(STONE), _xc(STONE.lightened(0.06)))
		var mcount := int(L / 1.5)
		for m in mcount:
			var t := (float(m) + 0.5) / float(mcount)
			var mp := p0.lerp(p1, t)
			kit.add_box_xf(Transform3D(Basis(Vector3.UP, ang2), mp + Vector3(0, hwall + 0.45, 0)),
				Vector3(th * 0.7, 0.9, 0.85), _xc(STONE))
		# 角楼
		if i % 2 == 1:
			var tp := p0
			kit.add_cylinder(tp, 4.2, 3.9, 12.5, 8, _xc(STONE))
			kit.add_cone(tp + Vector3(0, 12.5, 0), 5.2, 5.4, 8, _xc(ROOF_SLATE))
			kit.add_flag(tp + Vector3(0, 17.5, 0), 5.0, 3.0, 1.7, f.color)
			_window(tp + Vector3(0, 8.0, 0) + Vector3(sin(i) * 4.3, 0, cos(i) * 4.3), Vector3(sin(i), 0, cos(i)), 1.1, 1.6)

	# 主楼（Keep）
	var keep_pos := Vector3(0, 0, 0)
	kit.add_box(keep_pos + Vector3(0, 5.5, 0), Vector3(15.0, 11.0, 12.0), _xc(STONE.lightened(0.05)), _xc(STONE_DARK))
	kit.add_prism(keep_pos + Vector3(0, 11.0, 0), 8.4, 6.2, 6.6, _xc(ROOF_SLATE))
	# 塔楼 + 旗帜
	kit.add_cylinder(keep_pos + Vector3(5.4, 0, 4.2), 3.4, 3.1, 16.0, 8, _xc(STONE_DARK))
	kit.add_cone(keep_pos + Vector3(5.4, 16.0, 4.2), 4.2, 5.6, 8, _xc(ROOF_TILE))
	kit.add_flag(keep_pos + Vector3(5.4, 21.6, 4.2), 7.0, 4.4, 2.6, f.color)
	# 主楼窗户
	for i in 3:
		var wx := -4.5 + float(i) * 4.5
		_window(keep_pos + Vector3(wx, 6.5, 6.05), Vector3(0, 0, 1), 1.4, 2.0)
		_window(keep_pos + Vector3(wx, 6.5, -6.05), Vector3(0, 0, -1), 1.4, 2.0)
	for i in 3:
		_window(keep_pos + Vector3(7.55, 6.5, -4.0 + float(i) * 4.0), Vector3(1, 0, 0), 1.4, 2.0)
	# 院内附属建筑 + 校场
	kit.add_box(Vector3(-9.5, 2.6, 8.5), Vector3(6.0, 5.2, 4.6), _xc(WOOD), _xc(ROOF_TILE))
	kit.add_prism(Vector3(-9.5, 5.2, 8.5), 3.2, 2.4, 2.5, _xc(ROOF_TILE))
	kit.add_box(Vector3(9.0, 2.2, -9.0), Vector3(5.2, 4.4, 4.0), _xc(WOOD_DARK), _xc(THATCH))
	kit.add_prism(Vector3(9.0, 4.4, -9.0), 2.8, 2.0, 2.2, _xc(THATCH))
	_window(Vector3(-9.5, 2.6, 10.85), Vector3(0, 0, 1), 1.1, 1.4)

# --------------------------------------------------------------- 城镇
func _build_town(s: Settlement) -> void:
	var f := data.faction(s.faction_id)
	var R := 18.0
	# 木栅栏一圈（留一个门）
	var n := 26
	var gate0 := 0
	for i in n:
		if i >= gate0 and i <= gate0 + 1:
			continue
		var a := TAU * float(i) / float(n)
		var p := Vector3(cos(a) * R, 0, sin(a) * R)
		var pn := Vector3(cos(a), 0, sin(a))
		var ang := atan2(pn.x, pn.z)
		kit.add_box_xf(Transform3D(Basis(Vector3.UP, ang), p + Vector3(0, 2.3, 0)),
			Vector3(0.5, 4.6, 1.5), _xc(WOOD_DARK))
	# 横向木梁
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var p0 := Vector3(cos(a0) * R, 3.4, sin(a0) * R)
		var p1 := Vector3(cos(a1) * R, 3.4, sin(a1) * R)
		var mid := (p0 + p1) * 0.5
		var d := (p1 - p0)
		kit.add_box_xf(Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), mid),
			Vector3(0.25, 0.4, d.length()), _xc(WOOD))
	# 门柱 + 旗帜
	var ga := TAU * float(gate0 + 1) / float(n)
	var gp0 := Vector3(cos(ga) * R, 0, sin(ga) * R)
	kit.add_box(gp0 + Vector3(0, 3.4, 0), Vector3(1.0, 6.8, 1.0), _xc(WOOD_DARK))
	kit.add_box(gp0 + Vector3(0, 6.9, 0), Vector3(4.4, 0.7, 1.2), _xc(WOOD_DARK))
	kit.add_flag(gp0 + Vector3(0, 4.0, 0), 6.5, 4.0, 2.4, f.color)

	# 房屋
	var houses := rng.randi_range(6, 9)
	var placed: Array[Vector3] = []
	for i in houses:
		var pos := Vector3.ZERO
		var ok := false
		for _try in 40:
			var a := rng.randf_range(0, TAU)
			var r := rng.randf_range(4.0, R - 4.5)
			pos = Vector3(cos(a) * r, 0, sin(a) * r)
			ok = true
			for q in placed:
				if pos.distance_to(q) < 6.2:
					ok = false
					break
			if ok:
				break
		if not ok:
			continue
		placed.append(pos)
		_house(pos, rng.randf_range(0, TAU), rng.randf_range(4.2, 6.4), rng.randf_range(4.0, 5.6), rng.randf_range(3.0, 4.2),
			WOOD if rng.randf() < 0.6 else STONE, ROOF_TILE if rng.randf() < 0.6 else THATCH, true)
	# 水井
	var well := Vector3(0, 0, 0)
	kit.add_cylinder(well, 1.7, 1.6, 1.3, 8, _xc(STONE_DARK))
	kit.add_box(well + Vector3(0, 3.2, 0), Vector3(4.0, 0.4, 0.4), _xc(WOOD))
	kit.add_prism(well + Vector3(0, 1.3, 0), 2.2, 1.8, 2.2, _xc(THATCH))
	# 市集摊位
	for i in 3:
		var a2 := rng.randf_range(0, TAU)
		var pp := Vector3(cos(a2), 0, sin(a2)) * rng.randf_range(6.0, 11.0)
		kit.add_box(pp + Vector3(0, 1.3, 0), Vector3(2.6, 0.3, 1.8), _xc(WOOD))
		for k in 4:
			var sx := -1.2 + 2.4 * float(k % 2)
			var sz := -0.9 + 1.8 * float(k / 2)
			kit.add_cylinder(pp + Vector3(sx, 0, sz), 0.12, 0.1, 2.6, 4, _xc(WOOD_DARK), false, false)
		kit.add_flat_quad(pp + Vector3(-1.4, 2.6, -1.0), pp + Vector3(1.4, 2.6, -1.0),
			pp + Vector3(1.4, 2.6, 1.0), pp + Vector3(-1.4, 2.6, 1.0), _xc(CANVAS).lightened(0.05))
	# 几处农田紧贴城外
	for i in 2:
		var a3 := rng.randf_range(0, TAU)
		var r3 := R + rng.randf_range(5.0, 9.0)
		_farm_plot(s, cos(a3) * r3, sin(a3) * r3, rng.randf_range(0, TAU), rng.randf_range(8.0, 12.0), rng.randf_range(6.0, 9.0))

## 通用房屋：墙体 + 人字屋顶 + 窗户 + 烟囱
func _house(pos: Vector3, rot: float, w: float, d: float, h: float, wall: Color, roof: Color, windows: bool) -> void:
	var xf := Transform3D(Basis(Vector3.UP, rot), pos)
	kit.push_transform(xf)
	kit.add_box(Vector3(0, h * 0.5, 0), Vector3(w, h, d), _xc(wall), _xc(wall.darkened(0.15)))
	kit.add_prism(Vector3(0, h, 0), w * 0.62, maxf(1.6, d * 0.55), d * 0.56, _xc(roof))
	# 烟囱
	kit.add_box(Vector3(w * 0.28, h + d * 0.28, d * 0.25), Vector3(0.7, 1.8, 0.7), _xc(STONE))
	if windows:
		_window(Vector3(0, h * 0.55, d * 0.5 + 0.02), Vector3(0, 0, 1), 1.0, 1.3)
		_window(Vector3(w * 0.25, h * 0.55, -d * 0.5 - 0.02), Vector3(0, 0, -1), 1.0, 1.3)
	kit.pop_transform()

# --------------------------------------------------------------- 村庄
func _build_village(s: Settlement) -> void:
	var f := data.faction(s.faction_id)
	var huts := rng.randi_range(3, 6)
	var placed: Array[Vector3] = []
	for i in huts:
		var pos := Vector3.ZERO
		var ok := false
		for _try in 40:
			var a := rng.randf_range(0, TAU)
			var r := rng.randf_range(3.5, 10.5)
			pos = Vector3(cos(a) * r, 0, sin(a) * r)
			ok = true
			for q in placed:
				if pos.distance_to(q) < 5.2:
					ok = false
					break
			if ok:
				break
		if not ok:
			continue
		placed.append(pos)
		var w := rng.randf_range(3.4, 4.8)
		var d := rng.randf_range(3.0, 4.2)
		var h := rng.randf_range(2.2, 3.0)
		_house(pos, rng.randf_range(0, TAU), w, d, h, WOOD_DARK if rng.randf() < 0.5 else WOOD, THATCH, rng.randf() < 0.6)
	# 农田色块
	var plots := rng.randi_range(2, 4)
	for i in plots:
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(11.0, 17.0)
		_farm_plot(s, cos(a) * r, sin(a) * r, rng.randf_range(0, TAU), rng.randf_range(7.0, 11.0), rng.randf_range(5.0, 8.0))
	# 干草堆 + 木车
	var hs := Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
	kit.add_cone(hs, 2.0, 3.0, 7, _xc(THATCH.darkened(0.1)))
	var cart := Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
	kit.add_box(cart + Vector3(0, 1.2, 0), Vector3(3.2, 0.5, 1.6), _xc(WOOD))
	kit.add_cylinder(cart + Vector3(-1.2, 0.7, 0.9), 0.7, 0.7, 0.25, 8, _xc(WOOD_DARK), true, true)
	kit.add_cylinder(cart + Vector3(-1.2, 0.35, -0.9), 0.7, 0.7, 0.25, 8, _xc(WOOD_DARK), true, true)
	# 势力小旗
	kit.add_flag(Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)), 5.0, 3.0, 1.8, f.color)

## 农田：贴合地形高度的四边形色块 + 垄沟线
## 注意：kit 的顶点是「相对定居点节点」的局部坐标，
## 因此这里把世界高度换算成 local_y = height_at(world) - ground_h。
func _farm_plot(s: Settlement, ox: float, oz: float, rot: float, w: float, d: float) -> void:
	var col := WHEAT if rng.randf() < 0.6 else GRASS_PLOT
	var lx := [-w * 0.5, w * 0.5, w * 0.5, -w * 0.5]
	var lz := [-d * 0.5, -d * 0.5, d * 0.5, d * 0.5]
	var quad: Array[Vector3] = []
	for i in 4:
		var lv := Vector2(lx[i], lz[i]).rotated(rot)
		var wx := s.pos.x + ox + lv.x
		var wz := s.pos.y + oz + lv.y
		var ly := data.hm.height_at(wx, wz) - s.ground_h + 0.12
		quad.append(Vector3(ox + lv.x, ly, oz + lv.y))
	kit.add_ground_quad(quad, _xc(col))
	# 垄沟（细分条带，贴着农田色块）
	for k in 5:
		var t := (float(k) + 0.5) / 5.0
		var a := quad[0].lerp(quad[3], t)
		var b := quad[1].lerp(quad[2], t)
		a.y += 0.03
		b.y += 0.03
		var nrm := (b - a).normalized()
		var a2 := a + nrm * 0.28
		var b2 := b - nrm * 0.28
		kit.add_ground_quad([a, b, b2, a2], _xc(PLOW))
