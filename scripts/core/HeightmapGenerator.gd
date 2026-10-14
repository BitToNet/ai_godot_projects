## =============================================================================
##  HeightmapGenerator —— 程序化地形高度场
##
##  【噪声叠加方式】
##  高度 = lerp(深海剖面, 陆地剖面, 大陆遮罩 land)
##    陆地剖面 = 大陆基底(低频 base) + 丘陵(中频 hill) + 北部山脉(ridged)
##             + 东部沙丘(中频 dune) + 高频细节(detail)
##  · base   : FBM 5 octave，频率 0.0016 —— 决定大陆的大尺度起伏
##  · hill   : FBM 4 octave + domain warp，频率 0.0075 —— 中部丘陵
##  · ridge  : FRACTAL_RIDGED，频率 0.0035 —— 山脊线；取 pow(v, ridge_sharpness)
##             让山脊更峭拔（ridged 噪声天然在脊线处接近 1）
##  · dune   : FBM，频率 0.012 —— 东部低矮沙丘
##  · detail : FBM，频率 0.035，振幅很小 —— 破碎感
##  大陆遮罩 land 由椭圆距离 + 噪声扰动得到：中心偏向东北，
##  因此「西部 + 南部」自然是海岸线与海洋。
##
##  【湖泊生成算法】
##  在高程 18~95、坡度平缓处采样候选点 → 用 smoothstep 盆地形下挖
##  （中心最深、边缘平滑过渡到原地形）→ 记录水面高度（取环形边缘均高 - 1）。
##
##  【河流生成算法】
##  1. 源头：在北部山脉带（归一化 v ∈ [0.05,0.32]）随机撒点，取高程最高者；
##     多条河流的源头互相排斥，保证分散。
##  2. 河道推进（steepest-descent + 动量）：
##     每步在当前方向 ±75° 的扇区里取 16 个候选点，评分
##        score = 候选点高程 + 方向偏转角 * 方向惩罚 + 噪声抖动
##     取 score 最小者前进。方向项提供「动量」，让河道蜿蜒而不是贴着等高线乱走；
##     噪声项打破对称，避免笔直的河道。若全部候选都高于当前点，仍走最低者
##     （允许小幅爬升以跳出局部洼地），但连续上坡超过 uphill_limit 步就终止。
##  3. 入海：高程 <= 海平面即结束。
##  4. 河床剖面：对沿途河床高程做滑动平均 → 强制单调递减（水往低处流）
##     → 水面 = 河床 + 水深。然后按该剖面「下切」地形（取 min 保证只削不填）。
##  5. 浅滩：在河道上挑若干处把河床抬到水面下方一点点，标记为可通行 ford。
## =============================================================================
class_name HeightmapGenerator
extends RefCounted

const NOISE_TAU := TAU

var cfg: MapConfig
var hm: Heightmap
var rng: RandomNumberGenerator

# --- 噪声源 ---
var n_base := FastNoiseLite.new()
var n_ridge := FastNoiseLite.new()
var n_hill := FastNoiseLite.new()
var n_dune := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()
var n_forest := FastNoiseLite.new()
var n_rock := FastNoiseLite.new()
var n_moist := FastNoiseLite.new()

# --- 生成结果 ---
var biome_desert: PackedFloat32Array   ## 0..1 干旱度
var biome_moist: PackedFloat32Array    ## 0..1 湿度（草地浓密）
var biome_rock: PackedFloat32Array     ## 0..1 碎石/裸岩
var forest_mask: PackedFloat32Array    ## 0..1 森林成片遮罩
var rivers: Array[Dictionary] = []     ## {points: PackedVector3Array(水面), widths, fords: PackedInt32Array, dirs}
var lakes: Array[Dictionary] = []      ## {center: Vector2, radius: float, water_level: float}

func _init(p_cfg: MapConfig) -> void:
	cfg = p_cfg
	rng = cfg.make_rng("heightmap")
	_setup_noise()

# ------------------------------------------------------------------ 噪声初始化
func _setup_noise() -> void:
	var s := cfg.map_seed
	n_base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_base.seed = s
	n_base.frequency = 0.0016
	n_base.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_base.fractal_octaves = 5
	n_base.fractal_lacunarity = 2.0
	n_base.fractal_gain = 0.5
	n_base.domain_warp_enabled = true
	n_base.domain_warp_amplitude = 70.0
	n_base.domain_warp_frequency = 0.0012
	n_base.domain_warp_fractal_octaves = 2

	n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_ridge.seed = s + 101
	n_ridge.frequency = 0.0034
	n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n_ridge.fractal_octaves = 5
	n_ridge.fractal_lacunarity = 2.1
	n_ridge.fractal_gain = 0.48

	n_hill.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_hill.seed = s + 202
	n_hill.frequency = 0.0072
	n_hill.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_hill.fractal_octaves = 4
	n_hill.fractal_gain = 0.5
	n_hill.domain_warp_enabled = true
	n_hill.domain_warp_amplitude = 28.0
	n_hill.domain_warp_frequency = 0.004

	n_dune.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_dune.seed = s + 303
	n_dune.frequency = 0.0125
	n_dune.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_dune.fractal_octaves = 3
	n_dune.fractal_gain = 0.45

	n_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_detail.seed = s + 404
	n_detail.frequency = 0.034
	n_detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_detail.fractal_octaves = 3
	n_detail.fractal_gain = 0.5

	n_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_forest.seed = s + 505
	n_forest.frequency = cfg.forest_noise_freq
	n_forest.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_forest.fractal_octaves = 3
	n_forest.fractal_gain = 0.55

	n_rock.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_rock.seed = s + 606
	n_rock.frequency = 0.019
	n_rock.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_rock.fractal_octaves = 3

	n_moist.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_moist.seed = s + 707
	n_moist.frequency = 0.0042
	n_moist.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_moist.fractal_octaves = 3

# ------------------------------------------------------------------ 主流程
## timing = true 时把 6 件分件的耗时打到 stdout（默认 false，一个字都不多打）。
## 为什么把分件做进 generate() 而不是在探针里重写一遍这段顺序：
##   重写出来的顺序**不是**「管线刚刚跑过的那一次」，实测里复测值能比管线自己的阶段值高 1.8 倍
##   （`_build_biomes` 换掉 slope_at 之后更明显）—— 于是「占比」就变成了跨两条路径的数字游戏。
##   分件与阶段计时同源同位置，加起来就等于那一阶段，没有对不上的余地。
func generate(timing: bool = false) -> Heightmap:
	hm = Heightmap.new(cfg.heightmap_res, cfg.map_size)
	var t0 := Time.get_ticks_msec()
	_build_heights()
	var t_h := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	hm.blur(1)             # 去掉单点毛刺，让寻路/落地更稳
	var t_b1 := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_build_biomes()
	var t_bio := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_make_lakes()
	var t_lake := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_make_rivers()
	var t_riv := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	hm.blur(1)             # 柔化河道与湖岸边缘
	var t_b2 := Time.get_ticks_msec() - t0
	if timing:
		print("[高度场] 噪声 %d / 模糊① %d / 生物群系 %d / 湖 %d / 河 %d / 模糊② %d ms"
			% [t_h, t_b1, t_bio, t_lake, t_riv, t_b2])
	return hm

## 大陆遮罩：椭圆距离 + 噪声扰动海岸线
func land_mask(u: float, v: float) -> float:
	var dx := (u - cfg.continent_center.x) / cfg.continent_radius.x
	var dz := (v - cfg.continent_center.y) / cfg.continent_radius.y
	var d := sqrt(dx * dx + dz * dz)
	# 低幅度噪声扰动，让海岸线不是光滑椭圆
	var wob := n_detail.get_noise_2d(u * 700.0, v * 700.0) * 0.10
	return clampf(1.0 - smoothstep(0.50, 1.00, d + wob), 0.0, 1.0)

func desert_mask(u: float, v: float, land: float, mountain: float) -> float:
	# 东部（u 大）+ 中部纬度 → 沙漠；山脉区域削弱
	var e := smoothstep(0.50, 0.84, u)
	var band := smoothstep(0.02, 0.22, v) * (1.0 - smoothstep(0.72, 0.95, v))
	return clampf(e * band * land * (1.0 - mountain * 0.9), 0.0, 1.0)

func _build_heights() -> void:
	var res := hm.res
	var inv := 1.0 / cfg.map_size
	for z in res:
		var wz := float(z) * hm.cell
		var v := wz * inv
		for x in res:
			var wx := float(x) * hm.cell
			var u := wx * inv

			var land := land_mask(u, v)

			# --- 北部山脉遮罩：v 越小越北；东部稍作限制避免山脉贴到沙漠 ---
			var north := smoothstep(0.46, 0.02, v)
			var east_limit := smoothstep(0.05, 0.45, u)
			var m_mask := north * east_limit
			var ridge_v := n_ridge.get_noise_2d(wx, wz) * 0.5 + 0.5
			var ridge_v2 := n_ridge.get_noise_2d(wx * 2.3 + 999.0, wz * 2.3 - 555.0) * 0.5 + 0.5
			var ridge := pow(clampf(ridge_v * 0.72 + ridge_v2 * 0.38, 0.0, 1.0), cfg.ridge_sharpness)
			var mountain := m_mask * ridge * land

			# --- 其他地貌分量 ---
			var base := n_base.get_noise_2d(wx, wz) * 0.5 + 0.5        # 0..1
			var hill := n_hill.get_noise_2d(wx, wz) * 0.5 + 0.5        # 0..1
			var dune := n_dune.get_noise_2d(wx, wz) * 0.5 + 0.5
			var detail := n_detail.get_noise_2d(wx, wz)
			var desert := desert_mask(u, v, land, mountain)

			# --- 陆地剖面（米） ---
			var land_h := 3.0
			land_h += base * 17.0                                        # 大陆缓坡
			land_h += hill * cfg.hill_amplitude * (1.0 - desert * 0.8)   # 丘陵
			land_h += mountain * cfg.mountain_amplitude                  # 雪山
			land_h += desert * (dune * cfg.desert_amplitude + 4.0)       # 沙丘
			land_h += detail * cfg.detail_amplitude * (1.0 - land * 0.2)

			# --- 深海剖面：离岸越远越深 ---
			var shelf := smoothstep(0.0, 0.45, land)
			var sea_h := -7.0 - 30.0 * (1.0 - shelf)

			# 山脚过渡：山体边缘不要直接插进平原
			if mountain > 0.02:
				land_h += mountain * mountain * 22.0

			var h := lerpf(sea_h, land_h, land)
			hm.set_h(x, z, h)

## 生物群系 / 森林遮罩（与高度同分辨率，供 splat 图与植被投放使用）
func _build_biomes() -> void:
	var res := hm.res
	var n := res * res
	biome_desert.resize(n)
	biome_moist.resize(n)
	biome_rock.resize(n)
	forest_mask.resize(n)
	var inv := 1.0 / cfg.map_size
	for z in res:
		var wz := float(z) * hm.cell
		var v := wz * inv
		for x in res:
			var wx := float(x) * hm.cell
			var u := wx * inv
			var i := z * res + x
			var h := hm.data[i]
			var slope := hm.grid_slope(x, z)
			var mountain := 0.0
			if h > cfg.mountain_line:
				mountain = clampf((h - cfg.mountain_line) / 60.0, 0.0, 1.0)

			var d := desert_mask(u, v, land_mask(u, v), mountain)
			# 沙漠内部再叠一层噪声，让边界不是硬边
			d = clampf(d + n_rock.get_noise_2d(wx * 0.6, wz * 0.6) * 0.18, 0.0, 1.0)
			# 高海拔也偏干旱
			d = clampf(d + smoothstep(cfg.snow_line - 40.0, cfg.snow_line + 30.0, h) * 0.5, 0.0, 1.0)

			var moist := n_moist.get_noise_2d(wx, wz) * 0.5 + 0.5
			# 近水（低海拔）更湿润；沙漠更干
			moist = clampf(moist * 1.15 - d * 0.75 + (1.0 - smoothstep(4.0, 46.0, h)) * 0.35, 0.0, 1.0)

			var rock := clampf(n_rock.get_noise_2d(wx, wz) * 0.5 + 0.5, 0.0, 1.0)
			rock = clampf((rock - 0.45) * 1.8 + slope * 1.4 + smoothstep(cfg.mountain_line - 10.0, cfg.mountain_line + 50.0, h) * 0.7, 0.0, 1.0)

			# 森林成片遮罩：低频噪声阈值化 → 大片、非均匀的林地
			var f := n_forest.get_noise_2d(wx, wz) * 0.5 + 0.5
			f += n_forest.get_noise_2d(wx * 2.7 + 31.0, wz * 2.7 - 17.0) * 0.12
			f = smoothstep(cfg.forest_threshold - 0.12, cfg.forest_threshold + 0.20, f)
			# 太干、太高、太陡的地方没有森林
			f *= (1.0 - d * 0.92)
			f *= 1.0 - smoothstep(cfg.snow_line - 45.0, cfg.snow_line, h)
			f *= 1.0 - smoothstep(cfg.max_slope_veg, cfg.max_slope_veg + 0.25, slope)
			f *= smoothstep(1.0, 8.0, h)
			forest_mask[i] = clampf(f, 0.0, 1.0)
			biome_desert[i] = d
			biome_moist[i] = moist
			biome_rock[i] = rock

# ------------------------------------------------------------------ 水系掩码
## 生成低分辨率水系掩码（位标志），用于定居点选点 / 植被投放等早期判断
##   1 = 海洋   2 = 河流   4 = 湖泊
func make_water_flags(res: int) -> PackedByteArray:
	var flags := PackedByteArray()
	flags.resize(res * res)
	var cell := cfg.map_size / float(res - 1)
	for z in res:
		for x in res:
			var wx := float(x) * cell
			var wz := float(z) * cell
			if hm.height_at(wx, wz) <= cfg.sea_level + 0.7:
				flags[z * res + x] |= 1
	# 湖泊
	for l in lakes:
		var rad: float = l.radius
		var cr := int(ceil(rad / cell))
		var cx := int(l.center.x / cell)
		var cz := int(l.center.y / cell)
		for dz in range(-cr, cr + 1):
			for dx in range(-cr, cr + 1):
				var x := cx + dx
				var z := cz + dz
				if x < 0 or z < 0 or x >= res or z >= res:
					continue
				var p := Vector2(float(x) * cell, float(z) * cell)
				if p.distance_to(l.center) <= rad:
					flags[z * res + x] |= 4
	# 河流
	for r in rivers:
		var pts: PackedVector3Array = r.points
		var widths: PackedFloat32Array = r.widths
		for k in pts.size():
			var p := Vector2(pts[k].x, pts[k].z)
			var rad: float = widths[k] * 0.9
			var cr := int(ceil(rad / cell)) + 1
			var cx := int(p.x / cell)
			var cz := int(p.y / cell)
			for dz in range(-cr, cr + 1):
				for dx in range(-cr, cr + 1):
					var x := cx + dx
					var z := cz + dz
					if x < 0 or z < 0 or x >= res or z >= res:
						continue
					var q := Vector2(float(x) * cell, float(z) * cell)
					if q.distance_to(p) <= rad:
						flags[z * res + x] |= 2
	return flags

# ------------------------------------------------------------------ 湖泊
func _make_lakes() -> void:
	var tries := 0
	while lakes.size() < cfg.lake_count and tries < 4000:
		tries += 1
		var u := rng.randf_range(0.18, 0.86)
		var v := rng.randf_range(0.30, 0.80)
		var wx := u * cfg.map_size
		var wz := v * cfg.map_size
		var h := hm.height_at(wx, wz)
		if h < 14.0 or h > 105.0:
			continue
		if hm.slope_at(wx, wz) > 0.16:
			continue
		# 不要离别的湖太近
		var ok := true
		for l in lakes:
			if Vector2(wx, wz).distance_to(l.center) < cfg.lake_radius * 3.0:
				ok = false
				break
		if not ok:
			continue
		_carve_lake(Vector2(wx, wz), cfg.lake_radius * rng.randf_range(0.8, 1.25))

func _carve_lake(c: Vector2, radius: float) -> void:
	var depth := cfg.lake_depth * rng.randf_range(0.8, 1.4)
	var h_center := hm.height_at(c.x, c.y)
	var r := radius * 1.35
	var x0 := maxi(0, int((c.x - r) / hm.cell))
	var x1 := mini(hm.res - 1, int((c.x + r) / hm.cell))
	var z0 := maxi(0, int((c.y - r) / hm.cell))
	var z1 := mini(hm.res - 1, int((c.y + r) / hm.cell))
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := float(x) * hm.cell
			var wz := float(z) * hm.cell
			var d := Vector2(wx, wz).distance_to(c)
			if d > r:
				continue
			# 盆地形：0 -> 最深处，radius 处回到 0
			var w := 1.0 - smoothstep(radius * 0.25, radius, d)
			var i := z * hm.res + x
			hm.data[i] -= depth * w
	# 环形岸边平均高度 → 水面高度
	var ring_h := 0.0
	var ring_n := 0
	for k in 24:
		var a := TAU * float(k) / 24.0
		var p := c + Vector2(cos(a), sin(a)) * radius * 1.06
		ring_h += hm.height_at(p.x, p.y)
		ring_n += 1
	var water_level := ring_h / float(maxi(1, ring_n)) - 1.1
	var bed := hm.height_at(c.x, c.y)
	if bed > water_level - 2.0:
		# 保证湖心确实在水下
		water_level = bed + 2.0
	lakes.append({"center": c, "radius": radius, "water_level": water_level})

# ------------------------------------------------------------------ 河流
func _make_rivers() -> void:
	var sources: Array[Vector2] = []
	for i in cfg.river_count:
		var src := _find_river_source(sources)
		if src == Vector2.INF:
			continue
		sources.append(src)
		var pts := _trace_river(src)
		if pts.size() < 10:
			continue
		var width := cfg.river_width * rng.randf_range(0.85, 1.25)
		var prof := _carve_river(pts, width)
		var fords := _make_fords(pts, prof, width)
		var dirs := PackedVector2Array()
		for k in pts.size():
			var a := pts[maxi(0, k - 1)]
			var b := pts[mini(pts.size() - 1, k + 1)]
			var d := b - a
			dirs.append(d.normalized() if d.length_squared() > 1e-6 else Vector2(0, 1))
		rivers.append({
			"points": prof.points,      # PackedVector3Array，y = 水面高度
			"beds": prof.beds,          # PackedFloat32Array
			"widths": prof.widths,      # PackedFloat32Array（半宽）
			"dirs": dirs,
			"fords": fords,
		})

## 源头：北部山脉带中高程最高的采样点（多条河互相排斥）
func _find_river_source(existing: Array[Vector2]) -> Vector2:
	var best := Vector2.INF
	var best_h := -1e9
	for attempt in 900:
		var u := rng.randf_range(0.10, 0.86)
		var v := rng.randf_range(0.03, 0.34)
		var p := Vector2(u * cfg.map_size, v * cfg.map_size)
		var h := hm.height_at(p.x, p.y)
		if h < 95.0:
			continue
		var ok := true
		for e in existing:
			if p.distance_to(e) < cfg.map_size * 0.22:
				ok = false
				break
		if not ok:
			continue
		if h > best_h:
			best_h = h
			best = p
	return best

## 河道推进：steepest descent + 方向动量 + 噪声抖动
func _trace_river(src: Vector2) -> Array[Vector2]:
	var pts: Array[Vector2] = [src]
	var pos := src
	var dir := Vector2(0.0, 1.0)   # 初始向南（-Z 为北，+Z 为南）
	var uphill := 0
	var step := cfg.river_step
	var max_steps := int(cfg.map_size / step)
	for _s in max_steps:
		var cur_h := hm.height_at(pos.x, pos.y)
		var base_ang := atan2(dir.y, dir.x)
		var best_pos := pos
		var best_h := 1e9
		var best_score := 1e18
		var best_ang := base_ang
		for k in 17:
			var off := deg_to_rad(lerpf(-72.0, 72.0, float(k) / 16.0))
			var ang := base_ang + off
			var nd := Vector2(cos(ang), sin(ang))
			var np := pos + nd * step
			if np.x < 4.0 or np.x > cfg.map_size - 4.0 or np.y < 4.0 or np.y > cfg.map_size - 4.0:
				continue
			var nh := hm.height_at(np.x, np.y)
			# 评分：高程 + 方向惩罚（动量）+ 噪声（蜿蜒）
			var noise := n_detail.get_noise_2d(np.x * 1.9 + 77.0, np.y * 1.9 - 13.0) * 2.4
			var score := nh + absf(off) * 9.0 + noise
			if score < best_score:
				best_score = score
				best_pos = np
				best_h = nh
				best_ang = ang
		if best_pos == pos:
			break
		if best_h > cur_h + 0.2:
			uphill += 1
			if uphill > 10:
				break
		else:
			uphill = 0
		pos = best_pos
		dir = Vector2(cos(best_ang), sin(best_ang))
		pts.append(pos)
		if hm.height_at(pos.x, pos.y) <= cfg.sea_level + 0.6:
			break
		# 也允许汇入湖泊
		for l in lakes:
			if pos.distance_to(l.center) < l.radius * 0.9:
				return pts
	return pts

## 河床剖面 → 下切地形；返回水面折线
func _carve_river(raw: Array[Vector2], width: float) -> Dictionary:
	var n := raw.size()
	var beds := PackedFloat32Array()
	beds.resize(n)
	for i in n:
		beds[i] = hm.height_at(raw[i].x, raw[i].y)
	# 滑动平均，去掉剖面锯齿
	var sm := beds.duplicate()
	var win := 3
	for i in n:
		var s := 0.0
		var c := 0
		for k in range(maxi(0, i - win), mini(n, i + win + 1)):
			s += beds[k]
			c += 1
		sm[i] = s / float(maxi(1, c))
	# 强制单调递减（水只能往低处流）
	for i in range(1, n):
		if sm[i] > sm[i - 1] - 0.12:
			sm[i] = sm[i - 1] - 0.12
	# 入海处不要低于海床太多
	for i in n:
		if sm[i] < cfg.sea_level - 6.0:
			sm[i] = cfg.sea_level - 6.0
	var widths := PackedFloat32Array()
	widths.resize(n)
	var points := PackedVector3Array()
	points.resize(n)
	for i in n:
		# 下游逐渐变宽
		var t := float(i) / float(maxi(1, n - 1))
		var w := width * (0.55 + 0.75 * t)
		widths[i] = w
		var depth := 1.15 + 0.55 * t
		points[i] = Vector3(raw[i].x, sm[i] + depth, raw[i].y)
		_carve_channel(raw[i], w, sm[i])
	return {"points": points, "beds": sm, "widths": widths}

## 把地形削到 target_h（只削不填），边缘用 smoothstep 过渡
func _carve_channel(c: Vector2, radius: float, target_h: float, strength: float = 1.0) -> void:
	var r := radius * 1.5
	var x0 := maxi(0, int((c.x - r) / hm.cell))
	var x1 := mini(hm.res - 1, int((c.x + r) / hm.cell))
	var z0 := maxi(0, int((c.y - r) / hm.cell))
	var z1 := mini(hm.res - 1, int((c.y + r) / hm.cell))
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := float(x) * hm.cell
			var wz := float(z) * hm.cell
			var d := Vector2(wx, wz).distance_to(c)
			if d > r:
				continue
			var w := (1.0 - smoothstep(radius * 0.35, r, d)) * strength
			var i := z * hm.res + x
			var target := target_h
			if target > hm.data[i]:
				target = hm.data[i]
			hm.data[i] = lerpf(hm.data[i], target, w)

## 浅滩：把河床抬高到水面下一点点，成为可通行的渡口
func _make_fords(raw: Array[Vector2], prof: Dictionary, width: float) -> PackedInt32Array:
	var fords := PackedInt32Array()
	var n := raw.size()
	var count := cfg.ford_count_per_river
	for k in count:
		var t := (float(k) + 1.0) / (float(count) + 1.0)
		var i := int(t * float(n - 1))
		if i < 4 or i > n - 5:
			continue
		# 找到该处水面高度，把河床抬到水面 - 0.35
		var wl: float = prof.points[i].y
		_carve_channel_up(raw[i], prof.widths[i] * 0.75, wl - 0.35)
		fords.append(i)
	return fords

func _carve_channel_up(c: Vector2, radius: float, target_h: float) -> void:
	var r := radius * 1.5
	var x0 := maxi(0, int((c.x - r) / hm.cell))
	var x1 := mini(hm.res - 1, int((c.x + r) / hm.cell))
	var z0 := maxi(0, int((c.y - r) / hm.cell))
	var z1 := mini(hm.res - 1, int((c.y + r) / hm.cell))
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := float(x) * hm.cell
			var wz := float(z) * hm.cell
			var d := Vector2(wx, wz).distance_to(c)
			if d > r:
				continue
			# 只在河道范围内把河床「抬/压」到水面下方一点点（w 在边缘衰减到 0）
			var w := 1.0 - smoothstep(radius * 0.3, r, d)
			var i := z * hm.res + x
			hm.data[i] = lerpf(hm.data[i], target_h, w)
