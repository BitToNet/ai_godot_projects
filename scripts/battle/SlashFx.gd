## =============================================================================
##  SlashFx —— 刀光 / 冲击环 / 尘土 / 蓄力聚气环 / 弹反白光（全部程序化绘制）
## =============================================================================
class_name SlashFx
extends Node2D

var mode := "slash"
var life := 0.18
var max_life := 0.18
var col := Color(1, 1, 1)
var ang := 0.0
var radius := 40.0
var width := 10.0
var arc := 2.0
var flip := 1.0
var spin := 0.0

static func slash(parent: Node, pos: Vector2, ang_rad: float, r: float, colr: Color, arc_rad: float = 2.2, wid: float = 12.0) -> SlashFx:
	var s := SlashFx.new()
	parent.add_child(s)
	s.global_position = pos
	s.z_index = 18
	s.mode = "slash"
	s.ang = ang_rad
	s.radius = r
	s.col = colr
	s.arc = arc_rad
	s.width = wid
	s.life = 0.16
	s.max_life = 0.16
	return s

static func ring(parent: Node, pos: Vector2, r: float, colr: Color, dur: float = 0.28) -> SlashFx:
	var s := SlashFx.new()
	parent.add_child(s)
	s.global_position = pos
	s.z_index = 19
	s.mode = "ring"
	s.radius = r
	s.col = colr
	s.life = dur
	s.max_life = dur
	return s

static func charge_ring(parent: Node, dur: float = 0.6) -> SlashFx:
	var s := SlashFx.new()
	parent.add_child(s)
	s.mode = "charge"
	s.col = Color(0.6, 0.85, 1.0)
	s.life = dur
	s.max_life = dur
	s.z_index = 8
	return s

func tick(delta: float) -> void:
	life -= delta
	if mode == "charge":
		if not is_instance_valid(get_parent()):
			queue_free()
	queue_redraw()
	if life <= 0.0:
		queue_free()

func _draw() -> void:
	var f := clampf(life / max_life, 0.0, 1.0)
	var grow := 1.0 - f
	match mode:
		"slash":
			var pts := PackedVector2Array()
			var n := 14
			for i in n + 1:
				var t := lerpf(-arc * 0.5, arc * 0.5, float(i) / float(n))
				var rr := radius * (1.0 - 0.28 * grow)
				pts.append(Vector2(cos(ang + t), sin(ang + t)) * rr)
			draw_polyline(pts, Color(col.r, col.g, col.b, 0.85 * f), width * (0.4 + 0.9 * f), true)
			draw_polyline(pts, Color(1, 1, 1, 0.9 * f), width * 0.35 * f, true)
		"ring":
			draw_arc(Vector2.ZERO, radius * (0.35 + 1.1 * grow), 0.0, TAU, 44,
				Color(col.r, col.g, col.b, 0.85 * f), 5.0 * f + 1.0, true)
			draw_arc(Vector2.ZERO, radius * (0.2 + 1.4 * grow), 0.0, TAU, 44,
				Color(1, 1, 1, 0.5 * f), 2.0, true)
		"charge":
			var aa := Time.get_ticks_msec() * 0.006
			for i in 10:
				var t2 := TAU * float(i) / 10.0 + aa
				var rr2 := 26.0 + 34.0 * (1.0 - f)
				var r0 := 90.0 + 120.0 * (1.0 - f)
				var p0 := Vector2(cos(t2), sin(t2)) * r0
				var p1 := Vector2(cos(t2), sin(t2)) * rr2
				draw_line(p0, p1, Color(col.r, col.g, col.b, 0.55 * f), 2.4, true)
			draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 32, Color(0.8, 0.95, 1.0, 0.5 * f), 2.0, true)
