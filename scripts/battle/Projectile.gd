## =============================================================================
##  Projectile —— 剑气 / 飞斧 / 冲击波 / 地面裂隙（全部程序化绘制）
##   · 用 Area2D(Hitbox) 检测对方 Hurtbox，与近战完全共用一套判定流程
##   · 可弹反的投射物（飞斧、剑气类）被弹反后会掉头攻击原主
## =============================================================================
class_name Projectile
extends Node2D

var battle: Node = null
var kind: String = "wave"
var vel: Vector2 = Vector2.ZERO
var damage: float = 20.0
var poise_damage: float = 6.0
var knockback: float = 120.0
var lift: float = 0.0
var hitstop: float = 0.05
var parryable: bool = true
var pierce: bool = false
var life: float = 3.0
var from_player: bool = false
var owner_fighter: Fighter = null
var hit_ids: Dictionary = {}
var rehit_cd: float = 0.0
var box_size: Vector2 = Vector2(60, 50)
var color: Color = Color(0.6, 0.85, 1.0)
var trail: Array = []
var t: float = 0.0
var spin: float = 0.0
var hitbox: Hitbox
var hit_shape: RectangleShape2D
var dead: bool = false
var ground_y: float = 0.0
var rise_left: float = 0.0          ## fissure：剩余要喷出的尖刺数
var spawn_t: float = 0.0

func setup(p_battle: Node, p_kind: String, p_pos: Vector2, p_facing: float, from_p: bool) -> void:
	battle = p_battle
	kind = p_kind
	global_position = p_pos
	from_player = from_p
	ground_y = p_battle.ground_y
	z_index = 3
	match kind:
		"wave":
			color = Color(0.62, 0.88, 1.0) if not from_p else Color(0.75, 0.95, 1.0)
		"axe":
			color = Color(0.85, 0.85, 0.9)
		"shockwave":
			color = Color(1.0, 0.55, 0.35)
		"fissure":
			color = Color(1.0, 0.42, 0.28)
	# 判定盒
	hitbox = Hitbox.new()
	hitbox.owner_fighter = owner_fighter
	hitbox.collision_layer = 0
	hitbox.collision_mask = Fighter.LAYER_PLAYER_HURT if not from_p else Fighter.LAYER_BOSS_HURT
	hitbox.monitoring = true
	hit_shape = RectangleShape2D.new()
	hit_shape.size = box_size
	var cs := CollisionShape2D.new()
	cs.shape = hit_shape
	hitbox.add_child(cs)
	add_child(hitbox)

func fire_wave(facing: float, power: float) -> void:
	power = clampf(power, 0.0, 1.0)
	var s := lerpf(560.0, 1080.0, power)
	vel = Vector2(facing * s, 0)
	damage = lerpf(26.0, 68.0, power)
	poise_damage = lerpf(10.0, 30.0, power)
	pierce = power >= 0.985
	box_size = Vector2(lerpf(40.0, 74.0, power), lerpf(44.0, 84.0, power))
	hit_shape.size = box_size
	life = lerpf(0.62, 1.05, power)
	scale = Vector2(lerpf(0.75, 1.5, power), lerpf(0.75, 1.5, power))
	rehit_cd = 0.0 if pierce else 999.0

func fire_axe(facing: float) -> void:
	vel = Vector2(facing * 460.0, -40.0)
	damage = 22.0
	poise_damage = 8.0
	box_size = Vector2(52, 52)
	hit_shape.size = box_size
	life = 3.2

func fire_shockwave(facing: float) -> void:
	vel = Vector2(facing * 330.0, 0.0)
	damage = 20.0
	knockback = 200.0
	lift = -230.0
	pierce = true
	rehit_cd = 0.4
	box_size = Vector2(56, 26)
	hit_shape.size = box_size
	life = 2.2

func fire_fissure(facing: float) -> void:
	vel = Vector2(facing * 620.0, 0.0)
	damage = 16.0
	pierce = true
	rehit_cd = 0.16
	box_size = Vector2(46, 96)
	hit_shape.size = box_size
	life = 0.95
	rise_left = 5.0

# ---------------------------------------------------------------- 每帧
func tick(delta: float) -> void:
	if dead:
		return
	t += delta
	life -= delta
	if rehit_cd > 0.0 and rehit_cd < 900.0:
		rehit_cd -= delta
	if life <= 0.0:
		_die(true)
		return
	position += vel * delta
	spin += delta * 14.0
	# 空中/地面处理
	match kind:
		"axe":
			vel.y += 240.0 * delta
		"fissure":
			if absf(position.y - (ground_y - 46.0)) > 2.0:
				position.y = lerpf(position.y, ground_y - 46.0, 12.0 * delta)
			spawn_t -= delta
			if spawn_t <= 0.0 and rise_left > 0.0:
				spawn_t = 0.10
				rise_left -= 1.0
				if battle != null:
					battle.spawn_fissure_spike(Vector2(position.x, ground_y))
		"wave":
			pass
		"shockwave":
			position.y = ground_y - 13.0
	# 拖尾
	trail.append(global_position)
	if trail.size() > 8:
		trail.pop_front()
	if kind == "axe":
		hitbox.get_child(0).position = Vector2.ZERO
	else:
		hitbox.get_child(0).position = Vector2.ZERO
	# 命中检测
	if rehit_cd <= 0.0:
		for a in hitbox.get_overlapping_areas():
			if a is Hurtbox and a.owner_fighter != null and a.owner_fighter != owner_fighter:
				var id: int = a.owner_fighter.get_instance_id()
				if not hit_ids.has(id):
					hit_ids[id] = true
					if battle != null:
						battle.resolve_projectile_hit(self, a.owner_fighter)
					if not pierce:
						_die(false)
						return
					rehit_cd = 0.18
	# 出界
	if battle != null:
		if global_position.x < battle.arena_left - 60.0 or global_position.x > battle.arena_right + 60.0:
			_die(true)
			return
	if kind == "shockwave" and not pierce:
		pass
	queue_redraw()

func reflect(new_owner: Fighter) -> void:
	owner_fighter = new_owner
	from_player = new_owner.is_player
	vel.x = -vel.x * 1.35
	vel.y = -80.0
	damage *= 1.6
	poise_damage = 24.0
	parryable = false
	hit_ids.clear()
	rehit_cd = 0.0
	hitbox.collision_mask = Fighter.LAYER_PLAYER_HURT if not from_player else Fighter.LAYER_BOSS_HURT
	color = Color(1.0, 0.95, 0.6)

func _die(with_fx: bool) -> void:
	dead = true
	if with_fx and battle != null:
		battle.spawn_dissipate(global_position, color)
	queue_redraw()
	if battle != null:
		battle.remove_projectile(self)

# ---------------------------------------------------------------- 绘制
func _draw() -> void:
	match kind:
		"wave":
			_draw_wave()
		"axe":
			_draw_axe()
		"shockwave":
			_draw_shockwave()
		"fissure":
			_draw_fissure()

func _draw_wave() -> void:
	# 新月形剑气：外弧 + 内弧（尖端朝行进方向），带拖尾
	var alpha := clampf(life / 0.5, 0.0, 1.0)
	var lw := box_size.y * 0.5
	var bulge := box_size.x * 0.42
	var n := 16
	var outer := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(-1.15, 1.15, float(i) / float(n))
		outer.append(Vector2(bulge * cos(a) - bulge * 0.15, sin(a) * lw))
	var inner := PackedVector2Array()
	for i in range(n, -1, -1):
		var a := lerpf(-0.80, 0.80, float(i) / float(n))
		inner.append(Vector2(bulge * 0.42 * cos(a) - bulge * 0.30, sin(a) * lw * 0.60))
	var crescent := PackedVector2Array()
	crescent.append_array(outer)
	crescent.append_array(inner)
	draw_colored_polygon(crescent, Color(color.r, color.g, color.b, 0.34 * alpha))
	var glow := PackedVector2Array()
	for v in crescent:
		glow.append(v * 1.22)
	draw_colored_polygon(glow, Color(color.r, color.g, color.b, 0.16 * alpha))
	var core := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(-0.95, 0.95, float(i) / float(n))
		core.append(Vector2(bulge * 0.88 * cos(a) - bulge * 0.15, sin(a) * lw * 0.86))
	draw_polyline(core, Color(1, 1, 1, 0.9 * alpha), 3.4, true)
	# 拖尾
	for i in trail.size():
		var tp: Vector2 = trail[i] - global_position
		var f := float(i) / float(maxf(1.0, float(trail.size())))
		draw_circle(tp, lw * (0.2 + 0.28 * f), Color(color.r, color.g, color.b, 0.10 * f * alpha))

func _draw_axe() -> void:
	var s := 1.0
	draw_set_transform(Vector2.ZERO, spin, Vector2(s, s))
	var bl := PackedVector2Array([Vector2(-4, -4), Vector2(26, -20), Vector2(34, 2), Vector2(8, 16)])
	draw_colored_polygon(bl, Color(0.72, 0.74, 0.8))
	draw_polyline(PackedVector2Array([bl[0], bl[1], bl[2], bl[3], bl[0]]), Color(0.15, 0.15, 0.2), 2.0)
	draw_rect(Rect2(-24, -3, 48, 6), Color(0.32, 0.24, 0.16))
	if parryable:
		draw_circle(Vector2.ZERO, 26.0, Color(1, 1, 1, 0.10))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_shockwave() -> void:
	var a := clampf(life / 0.6, 0.0, 1.0)
	for i in 3:
		var r := 14.0 + float(i) * 9.0
		var pts := PackedVector2Array()
		for k in 12:
			var ang := lerpf(-1.2, 0.2, float(k) / 11.0)
			pts.append(Vector2(cos(ang) * r * 0.7, -sin(ang) * r))
		draw_polyline(pts, Color(color.r, color.g, color.b, (0.75 - 0.2 * float(i)) * a), 4.0 - float(i), true)
	draw_colored_polygon(PackedVector2Array([Vector2(-22, 6), Vector2(22, 6), Vector2(14, -14), Vector2(-14, -14)]),
		Color(color.r, color.g, color.b, 0.4 * a))

func _draw_fissure() -> void:
	var a := clampf(life / 0.35, 0.0, 1.0)
	var pts := PackedVector2Array()
	var n := 9
	for i in n + 1:
		var f := float(i) / float(n)
		pts.append(Vector2(lerpf(-26.0, 26.0, f), sin(f * 9.0 + t * 12.0) * 7.0 - 46.0))
	draw_polyline(pts, Color(1.0, 0.45, 0.25, 0.9 * a), 5.0, true)
	draw_polyline(pts, Color(1.0, 0.95, 0.8, 0.8 * a), 1.8, true)
	for i in 4:
		var x := lerpf(-20.0, 20.0, float(i) / 3.0)
		var h := 26.0 + 22.0 * sin(t * 16.0 + float(i))
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - 7, -46 + h * 0.5), Vector2(x, -46 - h * 0.7), Vector2(x + 6, -46 + h * 0.5)]),
			Color(0.75, 0.25, 0.15, 0.85 * a))
