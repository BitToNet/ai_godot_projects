## =============================================================================
##  PlayerFighter —— 玩家骑士（单人）状态机
##  状态：Idle / Run / Jump / Fall / Attack1~3 / AirAttack / Dodge / Parry /
##        ParrySuccess / Charge / ChargeRelease / Hurt / Dead
##
##  要点：
##   · 输入缓冲 0.15s（连招/取消衔接顺手），土狼时间 + 落地缓冲
##   · 三段普攻：前摇/判定/后摇，只有后摇的「连段窗口」里再按攻击才接下一段
##   · 后摇可被闪避/弹反取消（可配置表 cancel_into），跳跃不能取消普攻
##   · 可变跳跃高度、空中微调、空中闪避限 1 次、空中斩限 1 次
##   · 闪避前 0.25s 无敌帧 + 残影；判定帧内闪避 = 精准闪避（慢动作）
##   · 弹反窗口 0.15s，成功后 Boss 破防大增 + 硬直，接下来 1.3s 内下一刀是「反击斩」(×2)
##   · 蓄力 0.5s 进入、1.2s 蓄满，松开射出剑气（SwordWave）
## =============================================================================
class_name PlayerFighter
extends Fighter

enum S { IDLE, RUN, JUMP, FALL, ATTACK1, ATTACK2, ATTACK3, AIR_ATTACK, DODGE,
	PARRY, PARRY_SUCCESS, CHARGE, CHARGE_RELEASE, HURT, DEAD }

const STATE_NAME := {
	S.IDLE: "Idle", S.RUN: "Run", S.JUMP: "Jump", S.FALL: "Fall",
	S.ATTACK1: "Attack1", S.ATTACK2: "Attack2", S.ATTACK3: "Attack3",
	S.AIR_ATTACK: "AirAttack", S.DODGE: "Dodge", S.PARRY: "Parry",
	S.PARRY_SUCCESS: "ParrySuccess", S.CHARGE: "Charge", S.CHARGE_RELEASE: "ChargeRelease",
	S.HURT: "Hurt", S.DEAD: "Dead",
}

var state: int = S.IDLE
var state_t: float = 0.0
var poses: Dictionary = {}
var move: BattleMove = null
var move_index: int = 0
var combo_index: int = 0
var combo_open: bool = false

var stamina: float = 100.0
var stamina_delay: float = 0.0
var hold_t: float = 0.0
var charge_flash: float = 0.0
var glow: float = 0.0

var buf: Dictionary = {"attack": 0.0, "jump": 0.0, "dodge": 0.0, "parry": 0.0}
var in_attack_held: bool = false
var in_jump_held: bool = false
var in_mx: float = 0.0

var coyote: float = 0.0
var jump_buffer_t: float = 0.0
var air_dodges: int = 0
var air_attack_used: bool = false
var dodge_cd: float = 0.0
var counter_t: float = 0.0
var afterimage_t: float = 0.0
var target: Fighter = null
var stat_stamina_blocked: bool = false

func setup_player(p_battle: Node, p_cfg: BattleConfig, p_pal: Dictionary, p_hp: float) -> void:
	build_fighter(p_battle, p_cfg, RigPoses.player_profile(), p_pal, p_cfg.body_size, p_hp, true)
	poses = RigPoses.player_poses()
	stamina = p_cfg.player_max_stamina
	set_draw_order(6)
	_enter(S.IDLE)

# =============================================================== 输入
func feed_input(d: Dictionary) -> void:
	in_mx = d.get("mx", 0.0)
	in_attack_held = d.get("attack_held", false)
	in_jump_held = d.get("jump_held", false)
	if d.get("attack", false):
		_press("attack")
	if d.get("jump", false):
		_press("jump")
	if d.get("dodge", false):
		_press("dodge")
	if d.get("parry", false):
		_press("parry")

func _press(k: String) -> void:
	buf[k] = cfg.input_buffer

func _consume(k: String) -> bool:
	if float(buf[k]) > 0.0:
		buf[k] = 0.0
		return true
	return false

func _peek(k: String) -> bool:
	return float(buf[k]) > 0.0

# =============================================================== 状态切换
func _enter(s: int) -> void:
	state = s
	state_t = 0.0
	state_label = STATE_NAME[s]

func set_target(f: Fighter) -> void:
	target = f

func is_invulnerable() -> bool:
	return invuln > 0.0 or (state == S.DODGE and state_t <= cfg.dodge_iframe)

func is_dodging_with_iframe() -> bool:
	return state == S.DODGE and state_t <= cfg.dodge_iframe

# =============================================================== 主循环
func tick(delta: float) -> void:
	base_tick(delta)
	state_t += delta
	for k in buf.keys():
		buf[k] = maxf(0.0, float(buf[k]) - delta)
	if dodge_cd > 0.0:
		dodge_cd -= delta
	if counter_t > 0.0:
		counter_t -= delta
	if charge_flash > 0.0:
		charge_flash -= delta
	_regen_stamina(delta)
	_face_logic()

	# 持刀计时（用于蓄力）
	if in_attack_held:
		hold_t += delta
	else:
		if state == S.CHARGE:
			_start_release()
		hold_t = 0.0

	var was_floor := is_on_floor()
	match state:
		S.IDLE, S.RUN:
			_tick_ground(delta)
		S.JUMP, S.FALL:
			_tick_air(delta)
		S.ATTACK1, S.ATTACK2, S.ATTACK3, S.AIR_ATTACK:
			_tick_attack(delta)
		S.DODGE:
			_tick_dodge(delta)
		S.PARRY:
			_tick_parry(delta)
		S.PARRY_SUCCESS:
			_tick_parry_success(delta)
		S.CHARGE:
			_tick_charge(delta)
		S.CHARGE_RELEASE:
			_tick_release(delta)
		S.HURT:
			_tick_hurt(delta)
		S.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			apply_gravity(delta)
			rig.set_pose(poses["dead"])
			rig.set_glow(0.0)
			rig.set_flash(flash)

	if state != S.DEAD:
		if state != S.DODGE:
			apply_gravity(delta)
		else:
			velocity.y = 0.0
		if state != S.DODGE and state != S.CHARGE:
			velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
		move_and_slide()
		rig.scale.x = facing
		rig.position = Vector2.ZERO

	# 落地 / 离地
	if is_on_floor():
		if not was_floor:
			_on_land()
		coyote = cfg.coyote_time
		air_dodges = 0
		air_attack_used = false
	else:
		coyote = maxf(0.0, coyote - delta)
		if state == S.IDLE or state == S.RUN:
			_enter(S.FALL)
		elif state == S.JUMP and velocity.y > 0.0:
			_enter(S.FALL)

# ---------------------------------------------------------------- 体力
func _regen_stamina(delta: float) -> void:
	if stamina_delay > 0.0:
		stamina_delay -= delta
		return
	stamina = minf(cfg.player_max_stamina, stamina + cfg.stamina_regen * delta)

func _spend(v: float) -> bool:
	if stamina < v:
		stat_stamina_blocked = true
		return false
	stamina -= v
	stamina_delay = cfg.stamina_regen_delay
	return true

# ---------------------------------------------------------------- 朝向
func _face_logic() -> void:
	if state == S.DODGE or state == S.DEAD:
		return
	if absf(in_mx) > 0.1:
		facing = signf(in_mx)
	elif target != null and is_instance_valid(target) and state in [S.IDLE, S.RUN, S.PARRY]:
		var dx := target.global_position.x - global_position.x
		if absf(dx) > 6.0:
			facing = signf(dx)

# ---------------------------------------------------------------- 地面
func _tick_ground(delta: float) -> void:
	velocity.x = in_mx * cfg.move_speed
	var mv := absf(in_mx) > 0.05 or absf(velocity.x) > 6.0
	rig.set_pose(_locomotion_pose(mv))
	rig.set_glow(0.0)

	# 蓄力
	if in_attack_held and hold_t >= cfg.charge_start:
		_enter(S.CHARGE)
		return
	# 跳跃
	if _consume("jump") or (jump_buffer_t > 0.0 and coyote > 0.0):
		jump_buffer_t = 0.0
		_do_jump()
		return
	if _peek("jump"):
		jump_buffer_t = cfg.jump_buffer
	# 闪避
	if _consume("dodge"):
		if dodge_cd <= 0.0 and _spend(cfg.dodge_stamina):
			_start_dodge()
			return
	# 弹反
	if _consume("parry") and _spend(cfg.parry_stamina):
		_enter(S.PARRY)
		return
	# 普攻
	if _consume("attack"):
		_start_attack(0)
		return
	if mv:
		if state != S.RUN:
			_enter(S.RUN)
	else:
		if state != S.IDLE:
			_enter(S.IDLE)

func _do_jump() -> void:
	velocity.y = cfg.jump_velocity
	_enter(S.JUMP)

func _on_land() -> void:
	if state == S.JUMP or state == S.FALL or state == S.AIR_ATTACK:
		end_attack()
		_enter(S.IDLE)
		if battle != null:
			battle.spawn_land_puff(global_position)

func _locomotion_pose(walking: bool) -> Dictionary:
	if not walking:
		var b := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0032)
		return RigPoses.mix(poses["idle_a"], poses["idle_b"], b)
	var ph := fmod(Time.get_ticks_msec() * 0.0075, 4.0)
	var i := int(floor(ph))
	var f := ph - float(i)
	var a: Dictionary = poses["run_%d" % i]
	var b2: Dictionary = poses["run_%d" % ((i + 1) % 4)]
	return RigPoses.mix(a, b2, f)

# ---------------------------------------------------------------- 空中
func _tick_air(delta: float) -> void:
	var ctrl := cfg.air_control if state == S.FALL else 0.85
	if absf(in_mx) > 0.05:
		velocity.x = lerpf(velocity.x, in_mx * cfg.move_speed, ctrl * 8.0 * delta)
	rig.set_pose(poses["jump"] if velocity.y < 0.0 else poses["fall"])
	rig.set_glow(0.0)
	# 可变跳跃高度
	if velocity.y < 0.0 and not in_jump_held:
		velocity.y *= 1.0 - (1.0 - cfg.jump_cut) * 10.0 * delta
	# 土狼时间起跳
	if coyote > 0.0 and _consume("jump"):
		_do_jump()
		return
	if _peek("jump"):
		jump_buffer_t = cfg.jump_buffer
	# 空中闪避
	if _consume("dodge") and air_dodges < cfg.dodge_air_limit and dodge_cd <= 0.0 and _spend(cfg.dodge_stamina):
		air_dodges += 1
		_start_dodge()
		return
	# 空中斩（每次落地前 1 次）
	if _consume("attack") and not air_attack_used:
		air_attack_used = true
		move = cfg.player_move("air_attack")
		move_index = 3
		arm_attack(move)
		_enter(S.AIR_ATTACK)
		return
	# 空中弹反
	if _consume("parry") and _spend(cfg.parry_stamina):
		_enter(S.PARRY)
		return

# ---------------------------------------------------------------- 普攻
func _start_attack(idx: int) -> void:
	var m := cfg.player_attacks[idx] if idx < cfg.player_attacks.size() else null
	if m == null:
		return
	if not _spend(m.stamina):
		return
	move = m
	move_index = idx
	arm_attack(m)
	combo_open = false
	_enter(S.ATTACK1 + idx)

func _active_dur(m: BattleMove) -> float:
	return m.active + maxf(0.0, float(m.hits - 1)) * m.hit_interval

func _tick_attack(delta: float) -> void:
	var m := move
	if m == null:
		_enter(S.IDLE)
		return
	var t := state_t
	var ad := _active_dur(m)
	var in_air := not is_on_floor() and state == S.AIR_ATTACK
	# 前冲位移（在判定帧开始时给一个瞬时速度，后摇摩擦减速）
	if state_t >= m.startup and state_t - delta < m.startup:
		velocity.x = facing * (m.move_dist / maxf(0.06, m.active))
		if not in_air:
			velocity.x *= 1.0
		# 判定帧
		open_hitbox()
	if in_air:
		velocity.y = 0.0
		velocity.x = lerpf(velocity.x, in_mx * cfg.move_speed * 0.6, 4.0 * delta)
	# 多段判定（普攻都是 1 段，这里留出扩展）
	if m.hits > 1 and m.hit_interval > 0.0 and t >= m.startup:
		var k := int(floor((t - m.startup) / m.hit_interval))
		if k != hitbox.attack_id % 1000:
			pass
	# 关闭判定
	if t >= m.startup + m.active:
		if hitbox.monitoring:
			close_hitbox()

	# 姿势
	if t < m.startup:
		rig.set_pose(RigPoses.mix(poses[_ready_key(m)], poses[_wind_key(m)], t / maxf(0.001, m.startup)))
	elif t < m.startup + ad:
		rig.set_pose(poses[_hit_key(m)])
	elif t < m.startup + ad + m.recovery:
		var k2 := (t - m.startup - ad) / maxf(0.001, m.recovery)
		rig.set_pose(RigPoses.mix(poses[_hit_key(m)], poses["idle_a"], minf(1.0, k2 * 1.15)))
		combo_open = k2 <= cfg.combo_window_ratio
		_attack_cancel(m, k2)
	else:
		end_attack()
		combo_index = 0
		_enter(S.IDLE)
	rig.set_glow(0.0)

## 后摇取消表：只有 cancel_into 里列出的状态才能在连段窗口里接上
func _attack_cancel(m: BattleMove, k: float) -> void:
	if state == S.AIR_ATTACK:
		if k <= 0.7 and _consume("dodge") and dodge_cd <= 0.0 and _spend(cfg.dodge_stamina):
			_start_dodge()
		return
	if _consume("parry") and m.can_cancel_to("PARRY"):
		_enter(S.PARRY)
		return
	if _consume("dodge") and m.can_cancel_to("DODGE") and dodge_cd <= 0.0 and _spend(cfg.dodge_stamina):
		_start_dodge()
		return
	if cfg.jump_cancels_attacks and _consume("jump"):
		_do_jump()
		return
	if _peek("attack") and combo_open:
		var nxt := move_index + 1
		if nxt <= 2 and m.can_cancel_to("ATTACK%d" % (nxt + 1)):
			if _consume("attack"):
				combo_index = nxt
				_start_attack(nxt)
				return
		elif move_index >= 2:
			# 第三段后摇里再按攻击：不接第四段（表里没写），按键会被丢弃到缓冲过期
			pass

func _ready_key(m: BattleMove) -> String:
	match m.id:
		"atk3": return "a3_wind"
		"air_attack": return "air_wind"
		_: return "idle_a"

func _wind_key(m: BattleMove) -> String:
	match m.id:
		"atk1": return "a1_wind"
		"atk2": return "a2_wind"
		"atk3": return "a3_wind"
		"air_attack": return "air_wind"
	return "idle_a"

func _hit_key(m: BattleMove) -> String:
	match m.id:
		"atk1": return "a1_hit"
		"atk2": return "a2_hit"
		"atk3": return "a3_hit"
		"air_attack": return "air_hit"
	return "a1_hit"

# ---------------------------------------------------------------- 闪避
func _start_dodge() -> void:
	dodge_cd = cfg.dodge_cooldown
	afterimage_t = 0.0
	if absf(in_mx) > 0.1:
		facing = signf(in_mx)
	velocity.y = 0.0
	end_attack()
	_enter(S.DODGE)

func _tick_dodge(delta: float) -> void:
	var k := clampf(state_t / cfg.dodge_time, 0.0, 1.0)
	var spd := (cfg.dodge_distance / maxf(0.08, cfg.dodge_time * 0.55)) * (1.0 - k * 0.85)
	velocity.x = facing * spd
	velocity.y = 0.0
	var seg := k * 4.0
	var i := mini(3, int(floor(seg)))
	var f := clampf(seg - float(i), 0.0, 1.0)
	rig.set_pose(RigPoses.mix(poses["dodge_%d" % i], poses["dodge_%d" % mini(3, i + 1)], f))
	# 残影
	afterimage_t -= delta
	if afterimage_t <= 0.0 and battle != null:
		afterimage_t = 0.03
		battle.spawn_afterimage(global_position, rig.pose, prof, pal, facing, 0.30)
	if state_t >= cfg.dodge_time:
		_enter(S.IDLE if is_on_floor() else S.FALL)

# ---------------------------------------------------------------- 弹反
func _tick_parry(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 2200.0 * delta)
	rig.set_pose(poses["parry"])
	rig.set_glow(0.35)
	if state_t >= cfg.parry_window + cfg.parry_recovery:
		rig.set_glow(0.0)
		_enter(S.IDLE if is_on_floor() else S.FALL)

func on_parry_success() -> void:
	counter_t = cfg.parry_counter_window
	velocity.x = -facing * 40.0
	_enter(S.PARRY_SUCCESS)

func _tick_parry_success(delta: float) -> void:
	rig.set_pose(poses["parry_ok"])
	rig.set_glow(0.6)
	velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
	if state_t >= cfg.parry_success_recovery:
		rig.set_glow(0.0)
		_enter(S.IDLE if is_on_floor() else S.FALL)

func is_parry_window() -> bool:
	return state == S.PARRY and state_t <= cfg.parry_window

func counter_ready() -> bool:
	return counter_t > 0.0

# ---------------------------------------------------------------- 蓄力剑气
func _tick_charge(delta: float) -> void:
	velocity.x = in_mx * cfg.move_speed * cfg.charge_move_scale
	hold_t += delta
	_spend(cfg.charge_stamina_per_sec * delta)
	glow = clampf(hold_t / cfg.charge_full, 0.0, 1.0)
	var full := hold_t >= cfg.charge_full
	if full and charge_flash <= 0.0 and glow >= 0.999:
		charge_flash = 0.5
		if battle != null:
			battle.charge_ready_fx(global_position)
	rig.set_pose(poses["charge_full"] if full else poses["charge"])
	rig.set_glow(glow)
	if not in_attack_held:
		_start_release()

func _start_release() -> void:
	glow = clampf(hold_t / cfg.charge_full, 0.0, 1.0)
	_enter(S.CHARGE_RELEASE)
	if battle != null:
		battle.spawn_sword_wave(global_position + Vector2(facing * 26.0, -34.0), facing, glow)
	hold_t = 0.0

func _tick_release(delta: float) -> void:
	velocity.x = facing * 60.0
	rig.set_pose(poses["release"])
	rig.set_glow(maxf(0.0, glow - state_t * 2.0))
	if state_t >= 0.34:
		glow = 0.0
		rig.set_glow(0.0)
		_enter(S.IDLE if is_on_floor() else S.FALL)

# ---------------------------------------------------------------- 受击 / 死亡
func on_hurt() -> void:
	if not alive:
		_enter(S.DEAD)
		return
	glow = 0.0
	hold_t = 0.0
	end_attack()
	_enter(S.HURT)

func _tick_hurt(delta: float) -> void:
	rig.set_pose(poses["hurt"])
	rig.set_glow(0.0)
	if state_t >= cfg.hurt_time:
		_enter(S.IDLE if is_on_floor() else S.FALL)

func kill() -> void:
	alive = false
	end_attack()
	_enter(S.DEAD)
