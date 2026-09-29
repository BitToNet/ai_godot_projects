## =============================================================================
##  MapTextureBaker —— 把生成结果烘焙成贴图
##   1. splat_texture  (512² RGBA8)  R=道路 G=沙漠 B=岩石 A=湿度  → 地形 Shader
##   2. height_texture (512² RF)     R=世界高度(米)                → 水面 Shader 求水深
##   3. minimap_texture(256² RGBA8)  生物群系 + 势力领地 + 道路     → 右上角小地图
##   4. territory      (128² byte)   领地归属，供 UI / 提示 / 势力着色
##  全部用 create_from_data 一次性写入（比 set_pixel 快一个数量级）。
## =============================================================================
class_name MapTextureBaker
extends RefCounted

const SPLAT_RES := 512
const MINIMAP_RES := 256
const HEIGHT_RES := 512

var cfg: MapConfig
var data: MapData

func _init(p_cfg: MapConfig, p_data: MapData) -> void:
	cfg = p_cfg
	data = p_data

func bake_all() -> void:
	compute_territory()
	bake_splat()
	bake_height()
	bake_minimap()

# ---------------------------------------------------------------- 领地
func compute_territory() -> void:
	var res := MapData.TERR_RES
	data.territory_cell = cfg.map_size / float(res - 1)
	var terr := PackedByteArray()
	terr.resize(res * res)
	for z in res:
		for x in res:
			var p := Vector2(float(x) * data.territory_cell, float(z) * data.territory_cell)
			var i := z * res + x
			if data.is_water(p.x, p.y):
				terr[i] = 255
				continue
			var best_f := 255
			var best_d := 1e18
			for f in data.factions:
				var dmin := 1e18
				for s in data.settlements:
					if s.faction_id != f.id:
						continue
					var d := s.pos.distance_to(p) / maxf(0.35, s.importance())
					if d < dmin:
						dmin = d
				if dmin < best_d:
					best_d = dmin
					best_f = f.id
			terr[i] = best_f if best_d < 460.0 else 255
	# 中值滤波两遍，去掉飞地/噪点
	for _p in 2:
		var cp := terr.duplicate()
		for z in range(1, res - 1):
			for x in range(1, res - 1):
				var counts := {}
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var v := cp[(z + dz) * res + (x + dx)]
						counts[v] = int(counts.get(v, 0)) + 1
				var best_v := cp[z * res + x]
				var best_c := -1
				for k in counts.keys():
					if int(counts[k]) > best_c:
						best_c = int(counts[k])
						best_v = k
				terr[z * res + x] = best_v
	data.territory = terr

# ---------------------------------------------------------------- splat
func bake_splat() -> void:
	var res := SPLAT_RES
	var bytes := PackedByteArray()
	bytes.resize(res * res * 4)
	var scale := float(res - 1) / cfg.map_size
	var hres := data.hm.res
	var hcell := data.hm.cell
	for y in res:
		for x in res:
			var wx := float(x) / scale
			var wz := float(y) / scale
			var hx := clampi(int(wx / hcell), 0, hres - 1)
			var hz := clampi(int(wz / hcell), 0, hres - 1)
			var i := hz * hres + hx
			var desert: float = data.gen.biome_desert[i]
			var moist: float = data.gen.biome_moist[i]
			var rock: float = data.gen.biome_rock[i]
			var h := data.hm.data[i]
			# 水下：湿度拉满、干旱归零，让岸边呈现湿沙
			if h <= cfg.sea_level + 1.0:
				moist = 1.0
				desert *= 0.35
			var o := (y * res + x) * 4
			bytes[o + 0] = 0
			bytes[o + 1] = int(clampf(desert, 0.0, 1.0) * 255.0)
			bytes[o + 2] = int(clampf(rock, 0.0, 1.0) * 255.0)
			bytes[o + 3] = int(clampf(moist, 0.0, 1.0) * 255.0)
	# 道路（R 通道）带软边，Shader 里再做一次 smoothstep 打碎边缘
	var px_per_m := float(res - 1) / cfg.map_size
	var r_px := maxf(1.0, cfg.road_width * 0.72 * px_per_m)
	var soft := maxf(1.0, r_px * 0.9)
	for poly in data.roads:
		for k in poly.size():
			var p: Vector2 = poly[k]
			var cx := int(p.x * px_per_m)
			var cy := int(p.y * px_per_m)
			var cr := int(ceil(r_px + soft))
			for dy in range(-cr, cr + 1):
				for dx in range(-cr, cr + 1):
					var x := cx + dx
					var y := cy + dy
					if x < 0 or y < 0 or x >= res or y >= res:
						continue
					var d := sqrt(float(dx * dx + dy * dy))
					var w := 1.0 - smoothstep(r_px, r_px + soft, d)
					if w <= 0.0:
						continue
					var o := (y * res + x) * 4
					if bytes[o] < int(w * 255.0):
						bytes[o] = int(w * 255.0)
	var img := Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, bytes)
	data.splat_image = img
	data.splat_texture = ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- 高度
func bake_height() -> void:
	var res := HEIGHT_RES
	var f := PackedFloat32Array()
	f.resize(res * res)
	var scale := float(res - 1) / cfg.map_size
	for y in res:
		for x in res:
			f[y * res + x] = data.hm.height_at(float(x) / scale, float(y) / scale)
	var img := Image.create_from_data(res, res, false, Image.FORMAT_RF, f.to_byte_array())
	data.height_image = img
	data.height_texture = ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- 小地图
func bake_minimap() -> void:
	var res := MINIMAP_RES
	var bytes := PackedByteArray()
	bytes.resize(res * res * 4)
	var scale := float(res - 1) / cfg.map_size
	for y in res:
		for x in res:
			var wx := float(x) / scale
			var wz := float(y) / scale
			var h := data.hm.height_at(wx, wz)
			var slope := data.hm.slope_at(wx, wz)
			var hx := clampi(int(wx / data.hm.cell), 0, data.hm.res - 1)
			var hz := clampi(int(wz / data.hm.cell), 0, data.hm.res - 1)
			var i := hz * data.hm.res + hx
			var desert: float = data.gen.biome_desert[i]
			var moist: float = data.gen.biome_moist[i]
			var c := _minimap_color(h, slope, desert, moist)
			# 势力领地着色
			var fid := data.faction_at(wx, wz)
			if fid != 255 and h > cfg.sea_level:
				c = c.lerp(data.faction(fid).color, 0.30)
			var o := (y * res + x) * 4
			bytes[o + 0] = int(clampf(c.r, 0.0, 1.0) * 255.0)
			bytes[o + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
			bytes[o + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)
			bytes[o + 3] = 255
	# 道路
	var px_per_m := float(res - 1) / cfg.map_size
	for poly in data.roads:
		for k in poly.size():
			var p: Vector2 = poly[k]
			var cx := int(p.x * px_per_m)
			var cy := int(p.y * px_per_m)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var x := cx + dx
					var y := cy + dy
					if x < 0 or y < 0 or x >= res or y >= res:
						continue
					var o := (y * res + x) * 4
					var road := Color(0.62, 0.50, 0.33)
					bytes[o + 0] = int(((road.r + bytes[o + 0] / 255.0) * 0.5) * 255.0)
					bytes[o + 1] = int(((road.g + bytes[o + 1] / 255.0) * 0.5) * 255.0)
					bytes[o + 2] = int(((road.b + bytes[o + 2] / 255.0) * 0.5) * 255.0)
	var img := Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, bytes)
	data.minimap_image = img
	data.minimap_texture = ImageTexture.create_from_image(img)

func _minimap_color(h: float, slope: float, desert: float, moist: float) -> Color:
	if h <= cfg.sea_level + 0.5:
		# 海洋：越深越暗
		var d := clampf((cfg.sea_level - h) / 26.0, 0.0, 1.0)
		return Color(0.18, 0.42, 0.56).lerp(Color(0.03, 0.10, 0.22), d)
	var snow := smoothstep(cfg.snow_line - 18.0, cfg.snow_line + 22.0, h)
	if snow > 0.02:
		return Color(0.35, 0.40, 0.34).lerp(Color(0.94, 0.96, 1.0), snow)
	var rock := clampf(smoothstep(0.34, 0.62, slope) * 0.85 + smoothstep(70.0, 110.0, h) * 0.6, 0.0, 1.0)
	var sand := clampf(desert * 1.1 + (1.0 - smoothstep(1.0, 8.0, h - cfg.sea_level)), 0.0, 1.0)
	var grass := Color(0.28, 0.40, 0.19)
	var dry := Color(0.56, 0.52, 0.27)
	var g := dry.lerp(grass, clampf(moist, 0.0, 1.0))
	var c := g.lerp(Color(0.84, 0.78, 0.56), sand)
	c = c.lerp(Color(0.48, 0.46, 0.44), rock)
	return c * (0.9 + 0.2 * slope)
