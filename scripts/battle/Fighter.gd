## =============================================================================
##  Fighter —— 战斗角色基类（CharacterBody2D）
##   · 负责：重力/移动、受伤盒与攻击盒(Area2D)、HP、无敌帧、受击闪白、绘制挂点
##   · 具体行为（状态机）在 PlayerFighter / BossFighter 里
##   · 伤害结算统一由 BattleScene.resolve_hit() 负责（顿帧/震屏/粒子/伤害数字）
## =============================================================================
class_name Fighter
extends CharacterBody2D

signal hp_changed(hp: float, max_hp: float)
signal died

const LAYER_WORLD := 1
const LAYER_PLAYER_HURT := 2
const LAYER_BOSS_HURT := 4
const LAYER_PLAYER_HIT := 8
const LAYER_BOSS_HIT := 16

var cfg: BattleConfig
var battle: Node = null
var rig: FighterRig
var body_shape: CollisionShape2D
var hurtbox: Hurtbox
var hurt_shape: RectangleShape2D
var hitbox: Hitbox
var hit_shape: RectangleShape2D

var prof: Dictionary = {}
var pal: Dictionary = {}
var max_hp: float = 100.0
var hp: float = 100.0
var body_size := Vector2(20, 58)

var facing: float = 1.0
var invuln: float = 0.0
var hurt_lock: float = 0.0
var flash: float = 0.0
var attack_serial: int = 0
var hit_this_attack: Dictionary = {}
var alive: bool = true
var state_label: String = ""
var is_player: bool = false
var is_boss: bool = false
var last_parryable: bool = true      ## 最近一次对我方生效的攻击是否可弹反（调试/HUD用）
var tint: Color = Color(1, 1, 1)
## 判定盒纵向缩放（Boss 体型越小，招式的判定盒越往下压，保证贴住身体）
var box_y_scale: float = 1.0     ## 颜色叠加：红光/白光预警用

func build_fighter(p_battle: Node, p_cfg: BattleConfig, p_prof: Dictionary, p_pal: Dictionary,
		p_body: Vector2, p_hp: float, player: bool) -> void:
	battle = p_battle
	cfg = p_cfg
	prof = p_prof
	pal = p_pal
	body_size = p_body
	max_hp = p_hp
	hp = p_hp
	is_player = player
	is_boss = not player

	collision_layer = LAYER_WORLD
	collision_mask = LAYER_WORLD
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	up_direction = Vector2.UP
	floor_snap_length = 6.0

	# 身体碰撞
	body_shape = CollisionShape2D.new()
	var bs := RectangleShape2D.new()
	bs.size = body_size
	body_shape.shape = bs
	body_shape.position = Vector2(0, -body_size.y * 0.5)
	add_child(body_shape)

	# 受伤盒
	hurtbox = Hurtbox.new()
	hurtbox.owner_fighter = self
	hurtbox.collision_layer = LAYER_BOSS_HURT if is_boss else LAYER_PLAYER_HURT
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	hurt_shape = RectangleShape2D.new()
	hurt_shape.size = body_size * Vector2(0.95, 0.92)
	var hcs := CollisionShape2D.new()
	hcs.shape = hurt_shape
	hcs.position = Vector2(0, -body_size.y * 0.5)
	hurtbox.add_child(hcs)
	add_child(hurtbox)

	# 攻击盒（默认关闭）
	hitbox = Hitbox.new()
	hitbox.owner_fighter = self
	hitbox.collision_layer = LAYER_BOSS_HIT if is_boss else LAYER_PLAYER_HIT
	hitbox.collision_mask = LAYER_PLAYER_HURT if is_boss else LAYER_BOSS_HURT
	hitbox.monitoring = false
	hit_shape = RectangleShape2D.new()
	var acs := CollisionShape2D.new()
	acs.shape = hit_shape
	hitbox.add_child(acs)
	add_child(hitbox)

	# 绘制挂点
	rig = FighterRig.new()
	rig.z_index = 5
	rig.setup(prof, pal)
	add_child(rig)

func set_draw_order(z: int) -> void:
	rig.z_index = z

# ---------------------------------------------------------------- 攻击盒
## 起手：记录本次攻击序号（同一次攻击对同一目标只结算一次），但先不开判定
func arm_attack(move: BattleMove) -> void:
	attack_serial += 1
	hit_this_attack.clear()
	hitbox.move = move
	hitbox.attack_id = attack_serial
	place_hitbox(move.box_offset, move.box_size)
	hitbox.monitoring = false

func place_hitbox(off: Vector2, size: Vector2) -> void:
	hit_shape.size = size
	var cs := hitbox.get_child(0) as CollisionShape2D
	# box_y_scale：小体型敌人的判定盒整体上移比例（Boss 三档体型共用同一套招式数据）
	cs.position = Vector2(off.x * facing, off.y * box_y_scale)

func open_hitbox() -> void:
	hitbox.monitoring = true

func close_hitbox() -> void:
	hitbox.monitoring = false

func end_attack() -> void:
	hitbox.monitoring = false
	hitbox.move = null

## 取回本帧命中的「非自己」受伤盒
func poll_hits() -> Array:
	var out: Array = []
	if not hitbox.monitoring:
		return out
	for a in hitbox.get_overlapping_areas():
		if a is Hurtbox and a.owner_fighter != null and a.owner_fighter != self:
			var id: int = a.owner_fighter.get_instance_id()
			if not hit_this_attack.has(id):
				hit_this_attack[id] = true
				out.append(a.owner_fighter)
	return out

# ---------------------------------------------------------------- 受伤
func can_be_hit() -> bool:
	return alive and invuln <= 0.0

func receive_damage(dmg: float, from_x: float, knock: float, lift: float, stun: float) -> void:
	hp = maxf(0.0, hp - dmg)
	hp_changed.emit(hp, max_hp)
	flash = 1.0
	invuln = cfg.hurt_invuln
	hurt_lock = maxf(hurt_lock, stun)
	var dir := signf(global_position.x - from_x)
	if dir == 0.0:
		dir = -facing
	velocity.x = dir * knock
	if lift < 0.0:
		velocity.y = lift
	if hp <= 0.0:
		alive = false
		died.emit()

func heal_full() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)

# ---------------------------------------------------------------- 每帧通用
func base_tick(delta: float) -> void:
	if invuln > 0.0:
		invuln -= delta
	if hurt_lock > 0.0:
		hurt_lock -= delta
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 6.0)
	rig.set_flash(flash)
	# 无敌帧闪烁（与预警染色相乘叠加）
	var a := 1.0
	if invuln > 0.0 and alive:
		a = 0.42 + 0.58 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.035))
	rig.modulate = Color(tint.r, tint.g, tint.b, a)

func apply_gravity(delta: float, scale: float = 1.0) -> void:
	if not is_on_floor():
		velocity.y += cfg.gravity * scale * delta
		velocity.y = minf(velocity.y, cfg.max_fall_speed)

func ground_y() -> float:
	return global_position.y

## 当前武器尖端世界坐标（刀光拖尾用）
func weapon_tip() -> Vector2:
	if rig == null:
		return global_position
	var j := FighterRig.joints(prof, rig.pose)
	var tip: Vector2 = j["wpn_tip"]
	tip.x *= facing
	return global_position + tip
