## =============================================================================
##  Afterimage —— 闪避残影：冻结一份骨骼姿势快照并淡出（复用 FighterRig 的绘制）
## =============================================================================
class_name Afterimage
extends Node2D

var prof: Dictionary = {}
var pal: Dictionary = {}
var pose: Dictionary = {}
var facing: float = 1.0
var life: float = 0.3
var max_life: float = 0.3
var tintc := Color(0.6, 0.85, 1.0, 0.55)
## 被 BattleScene._reg() 收编后置为 true；漏登记时由 _process 自己推进，避免定格在屏幕上
var fx_managed := false

func _process(delta: float) -> void:
	if not fx_managed:
		tick(delta)

func setup(p: Vector2, p_pose: Dictionary, p_prof: Dictionary, p_pal: Dictionary, p_facing: float, dur: float) -> void:
	global_position = p
	pose = p_pose
	prof = p_prof
	pal = p_pal
	facing = p_facing
	life = dur
	max_life = dur
	z_index = 3
	scale.x = facing

func tick(delta: float) -> void:
	life -= delta
	queue_redraw()
	if life <= 0.0:
		queue_free()

func _draw() -> void:
	var f := clampf(life / max_life, 0.0, 1.0)
	var ghost := {}
	for k in pal.keys():
		var v = pal[k]
		if v is Color:
			ghost[k] = Color(tintc.r, tintc.g, tintc.b, float(v.a) * f * 0.65)
		else:
			ghost[k] = v
	FighterRig.draw_rig(self, prof, pose, ghost, 0.0, 0.0)
