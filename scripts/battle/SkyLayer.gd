## =============================================================================
##  SkyLayer —— 屏幕空间的渐变天空 + 太阳/月亮 + 云（放在最底层 CanvasLayer）
## =============================================================================
class_name SkyLayer
extends Node2D

var terrain: String = "grass"
var top := Color(0.28, 0.48, 0.76)
var bottom := Color(0.74, 0.85, 0.90)
var sun := Color(1.0, 0.95, 0.8)
var clouds: Array = []
var t: float = 0.0

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99117
	for i in 9:
		clouds.append({
			"x": rng.randf_range(0.0, 1.0), "y": rng.randf_range(0.06, 0.42),
			"w": rng.randf_range(90.0, 260.0), "sp": rng.randf_range(0.004, 0.014),
			"a": rng.randf_range(0.10, 0.26)})
	queue_redraw()

func tick(delta: float) -> void:
	t += delta
	queue_redraw()

func _draw() -> void:
	var vs := get_viewport_rect().size
	var bands := 40
	for i in bands:
		var f := float(i) / float(bands - 1)
		var c := top.lerp(bottom, pow(f, 0.85))
		draw_rect(Rect2(-4000.0, vs.y * float(i) / float(bands) - 1.0, 8000.0, vs.y / float(bands) + 2.0), c)
	# 云
	for cl in clouds:
		var x := fmod(cl["x"] * vs.x + t * cl["sp"] * 600.0, vs.x + 600.0) - 300.0
		var y: float = cl["y"] * vs.y
		var w: float = cl["w"]
		var a: float = cl["a"]
		for k in 3:
			var rr := w * (0.32 - 0.05 * float(k))
			draw_circle(Vector2(x + rr * 1.2 * float(k), y), rr, Color(1, 1, 1, a))
	# 太阳（挂在右上，随战斗不动，提供背光轮廓）
	var sp := Vector2(vs.x * 0.76, vs.y * 0.20)
	draw_circle(sp, 108.0, Color(sun.r, sun.g, sun.b, 0.12))
	draw_circle(sp, 62.0, Color(sun.r, sun.g, sun.b, 0.22))
	draw_circle(sp, 34.0, Color(sun.r, sun.g, sun.b, 0.85))
