## =============================================================================
##  ParallaxBackdrop —— 程序化多层视差背景（远山 / 中景树林或废墟 / 近景灌木 / 前景草丛）
##   · 全部由代码生成多边形，没有任何贴图
##   · 配色与造型取决于遭遇发生的地形：草原 / 雪山 / 沙漠
##   · update(cam_x) 时按 parallax 系数平移各层，形成视差滚动
## =============================================================================
class_name ParallaxBackdrop
extends Node

const SPAN_MIN := -1400.0
const SPAN_MAX := 3400.0

class PLayer extends Node2D:
	var polys: Array = []
	func _draw() -> void:
		for p in polys:
			draw_colored_polygon(p["pts"], p["col"])
			if p.has("line"):
				var pts: PackedVector2Array = p["pts"]
				var closed := pts.duplicate()
				closed.append(pts[0])
				draw_polyline(closed, p["line"], 1.5, true)

var layers: Array = []           ## [{node:PLayer, k:float}]
var ground_col := Color(0.28, 0.42, 0.22)
var ground_dark := Color(0.18, 0.28, 0.15)
var accents: Array = []          ## 地面装饰（草叶/石块），世界坐标

func setup(terrain: String, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var pal := _palette(terrain)
	ground_col = pal["ground"]
	ground_dark = pal["ground_dark"]
	# 远山 / 中景 / 近景 / 前景
	_add_layer(0.12, _make_far(pal, rng), -60)
	_add_layer(0.30, _make_mid(pal, rng), -50)
	_add_layer(0.55, _make_near(pal, rng), -40)
	_add_layer(1.35, _make_fore(pal, rng), 30)
	_make_accents(pal, rng)

func _add_layer(k: float, polys: Array, z: int) -> void:
	var l := PLayer.new()
	l.polys = polys
	l.z_index = z
	add_child(l)
	layers.append({"node": l, "k": k})

## 相机移动时调用：图层按 (1-k) 反向偏移 → k=1 与世界同步，k 越小越慢
func update(cam_pos: Vector2, anchor_x: float) -> void:
	for it in layers:
		var n: PLayer = it["node"]
		var k: float = it["k"]
		n.position = Vector2((cam_pos.x - anchor_x) * (1.0 - k), (cam_pos.y + 60.0) * (1.0 - k))

# ---------------------------------------------------------------- 配色
static func _palette(terrain: String) -> Dictionary:
	match terrain:
		"snow":
			return {
				"sky_top": Color(0.30, 0.40, 0.60), "sky_bot": Color(0.80, 0.86, 0.93),
				"far": Color(0.60, 0.66, 0.76), "far2": Color(0.70, 0.76, 0.85), "cap": Color(0.96, 0.98, 1.0),
				"mid": Color(0.20, 0.27, 0.35), "mid2": Color(0.26, 0.33, 0.42),
				"near": Color(0.13, 0.18, 0.25), "fore": Color(0.09, 0.13, 0.19),
				"ground": Color(0.86, 0.90, 0.96), "ground_dark": Color(0.55, 0.62, 0.72),
				"tree": "pine", "sky_sun": Color(0.95, 0.95, 1.0),
			}
		"desert":
			return {
				"sky_top": Color(0.38, 0.42, 0.66), "sky_bot": Color(0.96, 0.79, 0.55),
				"far": Color(0.74, 0.60, 0.42), "far2": Color(0.66, 0.52, 0.38), "cap": Color(0.88, 0.76, 0.55),
				"mid": Color(0.62, 0.46, 0.31), "mid2": Color(0.68, 0.51, 0.35),
				"near": Color(0.49, 0.34, 0.21), "fore": Color(0.38, 0.27, 0.17),
				"ground": Color(0.84, 0.70, 0.44), "ground_dark": Color(0.55, 0.43, 0.27),
				"tree": "cactus", "sky_sun": Color(1.0, 0.85, 0.6),
			}
		_:
			return {
				"sky_top": Color(0.28, 0.48, 0.76), "sky_bot": Color(0.74, 0.85, 0.90),
				"far": Color(0.42, 0.50, 0.60), "far2": Color(0.50, 0.57, 0.66), "cap": Color(0.92, 0.94, 0.97),
				"mid": Color(0.15, 0.29, 0.19), "mid2": Color(0.19, 0.34, 0.23),
				"near": Color(0.10, 0.21, 0.13), "fore": Color(0.06, 0.13, 0.08),
				"ground": Color(0.30, 0.44, 0.22), "ground_dark": Color(0.18, 0.28, 0.14),
				"tree": "round", "sky_sun": Color(1.0, 0.95, 0.8),
			}

# ---------------------------------------------------------------- 各层生成
func _make_far(pal: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var step := 90.0
	var pts := PackedVector2Array()
	var caps: Array = []
	var x := SPAN_MIN
	var h := 210.0
	pts.append(Vector2(x, 900.0))
	while x <= SPAN_MAX:
		h = clampf(h + rng.randf_range(-52.0, 52.0), 90.0, 330.0)
		pts.append(Vector2(x, -h))
		if h > 235.0:
			caps.append({"x": x, "h": h})
		x += step
	pts.append(Vector2(SPAN_MAX, 900.0))
	out.append({"pts": pts, "col": pal["far"]})
	# 雪顶 / 亮面
	for c in caps:
		var cx: float = c["x"]
		var ch: float = c["h"]
		out.append({"pts": PackedVector2Array([
			Vector2(cx - 40.0, -ch + 44.0), Vector2(cx, -ch), Vector2(cx + 40.0, -ch + 44.0)]),
			"col": pal["cap"]})
	# 第二层远山（更近一点，增加纵深）
	var pts2 := PackedVector2Array()
	var x2 := SPAN_MIN
	var h2 := 150.0
	pts2.append(Vector2(x2, 900.0))
	while x2 <= SPAN_MAX:
		h2 = clampf(h2 + rng.randf_range(-46.0, 46.0), 60.0, 230.0)
		pts2.append(Vector2(x2, -h2))
		x2 += 110.0
	pts2.append(Vector2(SPAN_MAX, 900.0))
	out.append({"pts": pts2, "col": pal["far2"]})
	return out

func _make_mid(pal: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var style: String = pal["tree"]
	# 中景地面带
	out.append({"pts": PackedVector2Array([
		Vector2(SPAN_MIN, -70.0), Vector2(SPAN_MAX, -70.0),
		Vector2(SPAN_MAX, 900.0), Vector2(SPAN_MIN, 900.0)]), "col": pal["mid2"]})
	var x := SPAN_MIN + 40.0
	while x < SPAN_MAX:
		var sc := rng.randf_range(0.75, 1.35)
		var base := -70.0
		match style:
			"pine":
				out.append_array(_pine(Vector2(x, base), sc, pal["mid"]))
			"cactus":
				out.append_array(_cactus(Vector2(x, base), sc, pal["mid"]))
			_:
				if rng.randf() < 0.18:
					out.append_array(_ruin(Vector2(x, base), sc, pal["mid"]))
				else:
					out.append_array(_round_tree(Vector2(x, base), sc, pal["mid"]))
		x += rng.randf_range(90.0, 170.0)
	return out

func _make_near(pal: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	out.append({"pts": PackedVector2Array([
		Vector2(SPAN_MIN, -34.0), Vector2(SPAN_MAX, -34.0),
		Vector2(SPAN_MAX, 900.0), Vector2(SPAN_MIN, 900.0)]), "col": pal["near"]})
	var x := SPAN_MIN + 80.0
	while x < SPAN_MAX:
		var sc := rng.randf_range(1.1, 2.0)
		var r := rng.randf()
		if r < 0.55:
			out.append_array(_bush(Vector2(x, -34.0), sc, pal["near"]))
		elif r < 0.8:
			out.append(_rock(Vector2(x, -34.0), sc, pal["near"]))
		else:
			out.append_array(_dead_tree(Vector2(x, -34.0), sc, pal["near"]))
		x += rng.randf_range(150.0, 320.0)
	return out

func _make_fore(pal: Dictionary, rng: RandomNumberGenerator) -> Array:
	# 前景草丛：只在画面最底部露出一小截，且半透明，避免遮挡战斗
	var out: Array = []
	var fc: Color = pal["fore"]
	fc.a = 0.72
	var x := SPAN_MIN
	while x < SPAN_MAX:
		var h := rng.randf_range(5.0, 14.0)
		var w := rng.randf_range(7.0, 14.0)
		out.append({"pts": PackedVector2Array([
			Vector2(x, 34.0), Vector2(x + w * 0.5, 34.0 - h), Vector2(x + w, 34.0)]), "col": fc})
		x += rng.randf_range(22.0, 52.0)
	return out

func _make_accents(pal: Dictionary, rng: RandomNumberGenerator) -> void:
	accents.clear()
	for i in 90:
		var x := rng.randf_range(0.0, 1500.0)
		accents.append({"x": x, "h": rng.randf_range(5.0, 13.0), "w": rng.randf_range(3.0, 7.0),
			"c": pal["ground_dark"].lerp(pal["ground"], rng.randf_range(0.2, 0.8))})

# ---------------------------------------------------------------- 造型
func _round_tree(b: Vector2, s: float, col: Color) -> Array:
	var out: Array = []
	out.append({"pts": PackedVector2Array([
		b + Vector2(-3, 0) * s, b + Vector2(3, 0) * s,
		b + Vector2(2, -26) * s, b + Vector2(-2, -26) * s]), "col": col.darkened(0.25)})
	for i in 3:
		var c := b + Vector2(-14.0 + 14.0 * float(i), -30.0 - 6.0 * cos(float(i))) * s
		var r := (13.0 - 1.5 * absf(float(i) - 1.0)) * s
		out.append({"pts": _circle_pts(c, r), "col": col})
	return out

func _pine(b: Vector2, s: float, col: Color) -> Array:
	var out: Array = []
	out.append({"pts": PackedVector2Array([
		b + Vector2(-3, 0) * s, b + Vector2(3, 0) * s,
		b + Vector2(2, -18) * s, b + Vector2(-2, -18) * s]), "col": col.darkened(0.3)})
	for i in 3:
		var y := -14.0 - 16.0 * float(i)
		var w := (20.0 - 4.5 * float(i)) * s
		out.append({"pts": PackedVector2Array([
			b + Vector2(-w, y * s), b + Vector2(w, y * s), b + Vector2(0, (y - 22.0) * s)]), "col": col})
	return out

func _cactus(b: Vector2, s: float, col: Color) -> Array:
	var out: Array = []
	out.append({"pts": PackedVector2Array([
		b + Vector2(-6, 0) * s, b + Vector2(6, 0) * s,
		b + Vector2(6, -46) * s, b + Vector2(-6, -46) * s]), "col": col})
	out.append({"pts": PackedVector2Array([
		b + Vector2(6, -26) * s, b + Vector2(22, -30) * s,
		b + Vector2(22, -22) * s, b + Vector2(6, -18) * s]), "col": col})
	return out

func _dead_tree(b: Vector2, s: float, col: Color) -> Array:
	var out: Array = []
	out.append({"pts": PackedVector2Array([
		b + Vector2(-3, 0) * s, b + Vector2(3, 0) * s,
		b + Vector2(1, -40) * s, b + Vector2(-1, -40) * s]), "col": col})
	out.append({"pts": PackedVector2Array([
		b + Vector2(0, -26) * s, b + Vector2(18, -40) * s,
		b + Vector2(20, -36) * s, b + Vector2(2, -24) * s]), "col": col})
	out.append({"pts": PackedVector2Array([
		b + Vector2(0, -32) * s, b + Vector2(-16, -46) * s,
		b + Vector2(-18, -42) * s, b + Vector2(-1, -30) * s]), "col": col})
	return out

func _bush(b: Vector2, s: float, col: Color) -> Array:
	var out: Array = []
	for i in 3:
		out.append({"pts": _circle_pts(b + Vector2(-12.0 + 12.0 * float(i), -8.0) * s, (11.0 + 2.0 * float(i % 2)) * s), "col": col})
	return out

func _rock(b: Vector2, s: float, col: Color) -> Dictionary:
	return {"pts": PackedVector2Array([
		b + Vector2(-16, 2) * s, b + Vector2(-9, -16) * s, b + Vector2(4, -22) * s,
		b + Vector2(15, -10) * s, b + Vector2(13, 2) * s]), "col": col}

func _ruin(b: Vector2, s: float, col: Color) -> Array:
	var out: Array = []
	out.append({"pts": PackedVector2Array([
		b + Vector2(-9, 0) * s, b + Vector2(9, 0) * s,
		b + Vector2(9, -52) * s, b + Vector2(-9, -52) * s]), "col": col.lightened(0.06)})
	out.append({"pts": PackedVector2Array([
		b + Vector2(-9, -52) * s, b + Vector2(9, -52) * s,
		b + Vector2(12, -62) * s, b + Vector2(-6, -58) * s]), "col": col.lightened(0.14)})
	out.append({"pts": PackedVector2Array([
		b + Vector2(14, 0) * s, b + Vector2(30, 0) * s,
		b + Vector2(30, -34) * s, b + Vector2(14, -30) * s]), "col": col})
	return out

static func _circle_pts(c: Vector2, r: float, seg: int = 9) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in seg:
		var a := TAU * float(i) / float(seg)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts

# ---------------------------------------------------------------- 天空（屏幕空间，放在最底层的 CanvasLayer）
static func make_sky(terrain: String) -> Node2D:
	var pal := _palette(terrain)
	var n := Node2D.new()
	n.set_script(preload("res://scripts/battle/SkyLayer.gd"))
	n.terrain = terrain
	n.top = pal["sky_top"]
	n.bottom = pal["sky_bot"]
	n.sun = pal["sky_sun"]
	n.z_index = -100
	return n
