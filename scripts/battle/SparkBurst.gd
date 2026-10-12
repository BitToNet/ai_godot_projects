## =============================================================================
##  SparkBurst —— 命中火花粒子（纯代码粒子，无外部贴图）
## =============================================================================
class_name SparkBurst
extends Node2D

class P:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.3
	var max_life := 0.3
	var size := 2.0
	var col := Color(1, 1, 1)
	var grav := 900.0
	var kind := 0     ## 0=火花线段 1=圆点 2=灰尘

var parts: Array = []
var done := false
## 被 BattleScene._reg() 收编后置为 true；漏登记时由 _process 自己推进，避免定格在屏幕上
var fx_managed := false

func _process(delta: float) -> void:
	if not fx_managed:
		tick(delta)

static func burst(parent: Node, pos: Vector2, count: int, col: Color, power: float = 1.0,
		spread: float = TAU, dir_deg: float = 0.0, kind: int = 0) -> SparkBurst:
	var s := SparkBurst.new()
	parent.add_child(s)
	s.global_position = pos
	s.z_index = 20
	var base := deg_to_rad(dir_deg)
	for i in count:
		var p := P.new()
		var a := base + randf_range(-spread * 0.5, spread * 0.5)
		var sp := randf_range(90.0, 420.0) * power
		p.pos = Vector2.ZERO
		p.vel = Vector2(cos(a), sin(a)) * sp
		p.max_life = randf_range(0.16, 0.42) * (0.7 + 0.6 * power)
		p.life = p.max_life
		p.size = randf_range(1.4, 3.6) * power
		p.col = col
		p.grav = randf_range(400.0, 1200.0) if kind == 0 else 260.0
		p.kind = kind
		s.parts.append(p)
	return s

func tick(delta: float) -> void:
	var alive := 0
	for p in parts:
		if p.life <= 0.0:
			continue
		alive += 1
		p.life -= delta
		p.vel.y += p.grav * delta
		p.vel *= 1.0 - 2.2 * delta
		p.pos += p.vel * delta
	queue_redraw()
	if alive == 0:
		done = true
		queue_free()

func _draw() -> void:
	for p in parts:
		if p.life <= 0.0:
			continue
		var f: float = clampf(p.life / p.max_life, 0.0, 1.0)
		var c := Color(p.col.r, p.col.g, p.col.b, p.col.a * f)
		if p.kind == 0:
			draw_line(p.pos, p.pos - p.vel.normalized() * (6.0 + 14.0 * f), c, p.size * f + 0.6, true)
		else:
			draw_circle(p.pos, p.size * (0.4 + 0.9 * f), c)
