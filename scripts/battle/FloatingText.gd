## =============================================================================
##  FloatingText —— 伤害数字 / 提示文字：从命中点弹出并飘散
##  普通伤害白字；暴击橙字更大；反击斩金色最大；另有「弹反!」「破防!」等提示
## =============================================================================
class_name FloatingText
extends Node2D

var label: Label
var vel := Vector2(0, -46)
var life := 0.9
var max_life := 0.9
var pop := 1.0

static func spawn(parent: Node, pos: Vector2, text: String, col: Color, big: bool) -> FloatingText:
	var f := FloatingText.new()
	parent.add_child(f)
	f.global_position = pos + Vector2(randf_range(-9, 9), randf_range(-6, 6))
	f.z_index = 40
	f.label = Label.new()
	f.label.text = text
	f.label.add_theme_font_override("font", UiTheme.font())
	f.label.add_theme_font_size_override("font_size", 30 if big else 21)
	f.label.add_theme_color_override("font_color", col)
	f.label.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.03, 0.95))
	f.label.add_theme_constant_override("outline_size", 6 if big else 4)
	f.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	f.label.position = Vector2(-60, -20)
	f.label.size = Vector2(120, 40)
	f.add_child(f.label)
	f.vel = Vector2(randf_range(-16, 16), -94.0 if big else -62.0)
	f.max_life = 1.15 if big else 0.85
	f.life = f.max_life
	return f

func tick(delta: float) -> void:
	life -= delta
	vel.y += 150.0 * delta
	position += vel * delta
	pop = maxf(1.0, pop - delta * 7.0)
	var sc := pop
	scale = Vector2(sc, sc)
	modulate.a = clampf(life / (max_life * 0.45), 0.0, 1.0)
	if life <= 0.0:
		queue_free()
