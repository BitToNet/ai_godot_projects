## =============================================================================
##  BossFighter —— Boss AI 状态机
##  状态：Idle / Approach / Move(各招式) / Staggered / Broken / Phase2Transition / Dead
##
##  三类敌人共用同一个状态机，只是招式表 / 体型 / 配色 / 伤害系数不同：
##    领主 lord    ：6 招全解锁（含二阶段组合技），最高大最硬
##    强盗头目 bandit：断岳重劈 / 裂地三连横扫 / 血怒冲锋 / 裂空飞斧（4 招）
##    商队护卫长 caravan：断岳重劈 / 裂地三连横扫 / 裂空飞斧（3 招，用长剑，伤害 ×0.82）
##
##  六种招式（见 BattleConfig._default_boss_moves）：
##    cleave  断岳重劈   可弹反(白光)  近距
##    sweep   裂地三连横扫 可弹反(白光)  中近距，3 段判定
##    slam    崩山践踏   不可弹反(红光) 跳起砸地 → 地面两侧冲击波
##    charge  血怒冲锋   不可弹反(红光) 突进穿过玩家
##    axe     裂空飞斧   可弹反(白光)  远程投射物，弹反后反弹打自己
##    fissure_combo 崩界裂隙 不可弹反(红光) 二阶段专属组合技
##
##  霸体：普通命中不会打断出招，只有弹反/破防值满才硬直；
##  破防：破防值满 → Broken 3 秒（受伤 ×1.5），之后清零。
##  二阶段：HP < 50% 播放怒吼转场，攻速 ×1.2，解锁组合技。
## =============================================================================
class_name BossFighter
extends Fighter

enum S { IDLE, APPROACH, MOVE, STAGGERED, BROKEN, PHASE2, DEAD }

const STATE_NAME := {
	S.IDLE: "Idle", S.APPROACH: "Approach", S.MOVE: "Move",
	S.STAGGERED: "Staggered", S.BROKEN: "Broken", S.PHASE2: "Phase2Transition", S.DEAD: "Dead",
}

var state: int = S.IDLE
var state_t: float = 0.0
var poses: Dictionary = {}
var move: BattleMove = null
var move_t: float = 0.0
var last_hit_index: int = -1
var last_move_id: String = ""
var same_count: int = 0
var gap_t: float = 0.8
var speed_mult: float = 1.0
var phase2: bool = false
var poise: float = 120.0
var max_poise: float = 120.0
var poise_hit_t: float = 0.0
var break_t: float = 0.0
var roar_t: float = 0.0
var player: Fighter = null
var warned: bool = false
var base_pal: Dictionary = {}
var kind: String = "lord"                 ## lord / bandit / caravan
var moves: Array[BattleMove] = []         ## 该类型可用的招式
var dmg_mult: float = 1.0                 ## 该类型的伤害系数
var step_t: float = 0.0                   ## 沉重脚步的节拍计时

func setup_boss(p_battle: Node, p_cfg: BattleConfig, p_hp: float, p_poise: float, p_kind: String = "lord") -> void:
	kind = p_kind
	var prof := RigPoses.boss_profile(kind)
	base_pal = RigPoses.boss_palette(kind)
	var body := Vector2(float(prof["torso_w"]) * 1.65, float(prof["height"]) * 0.94)
	build_fighter(p_battle, p_cfg, prof, base_pal, body, p_hp, false)
	box_y_scale = float(prof["height"]) / 192.0
	moves = cfg.boss_moves_for(kind)
	dmg_mult = cfg.boss_dmg_mult_for(kind)
	poses = RigPoses.boss_poses()
	max_poise = p_poise
	poise = 0.0
	set_draw_order(4)
	_enter(S.IDLE)

func set_player(p: Fighter) -> void:
	player = p

# =============================================================== 状态
func _enter(s: int) -> void:
	state = s
	state_t = 0.0
	state_label = STATE_NAME[s]
	if s != S.MOVE:
		close_hitbox()
		move = null
	if s == S.IDLE:
		gap_t = cfg.boss_idle_gap_phase2 if phase2 else cfg.boss_idle_gap

func is_broken() -> bool:
	return state == S.BROKEN

func warn_active() -> bool:
	return state == S.MOVE and move != null and move_t <= move.telegraph

func warn_parryable() -> bool:
	return move != null and move.parryable

# =============================================================== 主循环
func tick(delta: float) -> void:
	base_tick(delta)
	state_t += delta
	tint = Color(1, 1, 1)
	_poise_tick(delta)
	if not phase2 and alive and hp <= max_hp * cfg.boss_phase2_hp and state != S.PHASE2:
		_start_phase2()
		return

	match state:
		S.IDLE: _tick_idle(delta)
		S.APPROACH: _tick_approach(delta)
		S.MOVE: _tick_move(delta)
		S.STAGGERED: _tick_staggered(delta)
		S.BROKEN: _tick_broken(delta)
		S.PHASE2: _tick_phase2(delta)
		S.DEAD: _tick_dead(delta)

	if alive and state != S.PHASE2:
		apply_gravity(delta)
		move_and_slide()
	rig.scale.x = facing
	rig.position = Vector2.ZERO

func _poise_tick(delta: float) -> void:
	if poise_hit_t > 0.0:
		poise_hit_t -= delta
	elif state != S.BROKEN and poise > 0.0:
		poise = maxf(0.0, poise - cfg.boss_poise_decay * delta)

# ---------------------------------------------------------------- Idle / 走位
func _face_player() -> void:
	if player != null and is_instance_valid(player):
		var dx := player.global_position.x - global_position.x
		if absf(dx) > 4.0:
			facing = signf(dx)

func dist_to_player() -> float:
	if player == null or not is_instance_valid(player):
		return 999.0
	return absf(player.global_position.x - global_position.x)

func _tick_idle(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
	_face_player()
	rig.set_pose(_breathe())
	rig.set_glow(0.0)
	gap_t -= delta
	if gap_t <= 0.0:
		if not _pick_move():
			_enter(S.APPROACH)

func _tick_approach(delta: float) -> void:
	_face_player()
	velocity.x = facing * cfg.boss_move_speed * speed_mult
	var d := dist_to_player()
	var ph := fmod(Time.get_ticks_msec() * 0.005, 4.0)
	var i := int(floor(ph))
	rig.set_pose(RigPoses.mix(poses["walk_%d" % i], poses["walk_%d" % ((i + 1) % 4)], ph - float(i)))
	_tick_footsteps(delta)
	if d < 170.0 or gap_t <= 0.0:
		if not _pick_move():
			gap_t = 0.5
	# 走太久也强制出招
	if state_t > 1.6:
		_pick_move()

## Boss 走位时的沉重脚步（音高压低，听感更"重"）
func _tick_footsteps(delta: float) -> void:
	if battle == null or not is_on_floor():
		step_t = 0.0
		return
	step_t -= delta
	if step_t > 0.0:
		return
	step_t = maxf(0.18, Sfx.cfg().boss_step_interval) / maxf(0.6, speed_mult)
	Sfx.play_2d(battle, "step_heavy", global_position, -2.0, 0.85)

func _breathe() -> Dictionary:
	var b := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0026)
	return RigPoses.mix(poses["idle_a"], poses["idle_b"], b)

## 依距离 + 权重选招；同一招不能连续使用超过 2 次
func _pick_move() -> bool:
	var d := dist_to_player()
	var pool: Array = []
	var weights: Array = []
	if moves.is_empty():
		moves = cfg.boss_moves_for(kind)
	for m in moves:
		if m.phase2_only and not phase2:
			continue
		if m.id == last_move_id and same_count >= 2:
			continue
		if d < m.min_range or d > m.max_range:
			continue
		pool.append(m)
		weights.append(m.weight)
	if pool.is_empty():
		return false
	var total := 0.0
	for w in weights:
		total += float(w)
	# 走战斗实例那条**已播种**的 RNG，而不是全局 randf()：
	# 全局 RNG 每次进程启动都重新随机播种（Godot 4 默认行为），会让 Boss 的出招序列
	# 不可复现 —— tools/sfx_battle_check.gd 用固定 seed 驱动战斗，却因此偶发失败
	# （实测同一命令 4 次里 1 次 FAIL，缺 hit_crit / parry；播放次数在 54~63 之间漂）。
	# 地图生成走的是另一条随机流，改这里不影响生成指纹。
	# 写成「先按全局取一次、再有战斗实例就覆盖」是为了兼容 battle == null 的裸用场景，
	# 同时绕开 GDScript 的类型推断（`var r := (A if 条件 else B)` 会报 value doesn't have a set type）。
	var r := randf() * total
	if battle != null:
		r = battle.roll01() * total
	var acc := 0.0
	var pick: BattleMove = pool[pool.size() - 1]
	for i in pool.size():
		acc += float(weights[i])
		if r <= acc:
			pick = pool[i]
			break
	if pick.id == last_move_id:
		same_count += 1
	else:
		same_count = 1
		last_move_id = pick.id
	_start_move(pick)
	return true

func _start_move(m: BattleMove) -> void:
	move = m
	move_t = 0.0
	last_hit_index = -1
	warned = false
	arm_attack(m)
	_enter(S.MOVE)
	_face_player()
	match m.id:
		"slam":
			velocity.y = -430.0
			velocity.x = clampf((player.global_position.x - global_position.x) * 1.4, -160.0, 160.0) if player != null else 0.0
		"charge":
			# 冲锋起步：一记低沉的踏地声（随后是持续的突进）
			if battle != null:
				Sfx.play_2d(battle, "step_heavy", global_position, -1.0, 0.62)

# ---------------------------------------------------------------- 出招
## 测试/调试用：直接指定某个招式
func start_move_for_test(id: String) -> void:
	var m := cfg.boss_move(id)
	if m != null:
		_start_move(m)

func _active_dur(m: BattleMove) -> float:
	return m.active + maxf(0.0, float(m.hits - 1)) * m.hit_interval

func _hit_open(m: BattleMove, t: float) -> bool:
	if t < m.startup:
		return false
	if m.hits <= 1 or m.hit_interval <= 0.0:
		return t < m.startup + m.active
	var k := int(floor((t - m.startup) / m.hit_interval))
	if k >= m.hits:
		return false
	return (t - m.startup - float(k) * m.hit_interval) < m.active

func _hit_index(m: BattleMove, t: float) -> int:
	if m.hits <= 1 or m.hit_interval <= 0.0:
		return 0 if t >= m.startup and t < m.startup + m.active else -1
	if t < m.startup:
		return -1
	var k := int(floor((t - m.startup) / m.hit_interval))
	if k >= m.hits:
		return -1
	if (t - m.startup - float(k) * m.hit_interval) < m.active:
		return k
	return -1

func _tick_move(delta: float) -> void:
	var m := move
	if m == null:
		_enter(S.IDLE)
		return
	move_t += delta * speed_mult
	var ad := _active_dur(m)

	# ---- 预警：前摇的前 telegraph 秒闪白/闪红 ----
	if move_t <= m.telegraph:
		var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.03)
		if m.parryable:
			tint = Color(1.0 + 0.9 * pulse, 1.0 + 0.9 * pulse, 1.0 + 1.0 * pulse)
		else:
			tint = Color(1.0 + 1.1 * pulse, 1.0 - 0.55 * pulse, 1.0 - 0.55 * pulse)
		if not warned:
			warned = true
			if battle != null:
				battle.on_boss_warn(self, m)
	else:
		tint = Color(1, 1, 1)

	# ---- 各招式专属 ----
	match m.id:
		"charge":
			if move_t >= m.startup and move_t < m.startup + m.active:
				velocity.x = facing * 620.0
			else:
				velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		"slam":
			velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
			if move_t >= m.startup - 0.06 and move_t < m.startup + m.active and last_hit_index < 0:
				if battle != null:
					battle.spawn_shockwaves(global_position, 1.0)
					battle.spawn_shockwaves(global_position, -1.0)
					battle.shake(cfg.shake_heavy.x, cfg.shake_heavy.y)
					battle.spawn_dust_burst(global_position, 14)
		_:
			velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)
	# 投射物
	if m.projectile != "" and move_t >= m.startup and last_hit_index < 0:
		last_hit_index = 0
		if battle != null:
			match m.projectile:
				"axe":
					battle.spawn_boss_axe(global_position + Vector2(facing * 40.0, -110.0), facing)
				"fissure":
					battle.spawn_fissure(global_position, facing)
				"shockwave":
					pass
	# 判定盒
	var want := _hit_open(m, move_t)
	var hi := _hit_index(m, move_t)
	if hi >= 0 and hi != last_hit_index:
		last_hit_index = hi
		hit_this_attack.clear()
	if want and not hitbox.monitoring:
		open_hitbox()
	elif not want and hitbox.monitoring:
		close_hitbox()

	# ---- 姿势 ----
	var wind_key := "%s_wind" % m.anim
	var hit_key := "%s_hit" % m.anim
	if m.anim == "charge":
		wind_key = "charge_wind"
		hit_key = "charge_hit"
	if not poses.has(wind_key):
		wind_key = "cleave_wind"
	if not poses.has(hit_key):
		hit_key = "cleave_hit"
	if move_t < m.startup:
		rig.set_pose(RigPoses.mix(poses["idle_a"], poses[wind_key], clampf(move_t / maxf(0.01, m.startup * 0.8), 0.0, 1.0)))
	elif _hit_open(m, move_t):
		rig.set_pose(poses[hit_key])
	else:
		var k2 := clampf((move_t - m.startup) / maxf(0.01, ad), 0.0, 1.0)
		if k2 < 1.0:
			rig.set_pose(RigPoses.mix(poses[wind_key], poses[hit_key], k2))
		else:
			rig.set_pose(RigPoses.mix(poses[hit_key], poses["idle_a"], clampf((move_t - m.startup - ad) / maxf(0.01, m.recovery), 0.0, 1.0)))
	rig.set_glow(1.0 if phase2 else 0.0)

	if move_t >= m.startup + ad + m.recovery:
		close_hitbox()
		end_attack()
		_enter(S.IDLE)

# ---------------------------------------------------------------- 受击反应
func add_poise(v: float) -> void:
	poise_hit_t = cfg.boss_poise_decay_delay
	poise += v
	if poise >= max_poise and state != S.BROKEN and alive:
		poise = max_poise
		_break()

func _break() -> void:
	close_hitbox()
	end_attack()
	break_t = cfg.boss_break_time
	poise = 0.0
	_enter(S.BROKEN)
	if battle != null:
		battle.on_boss_broken(self)

func _tick_broken(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
	rig.set_pose(poses["broken"])
	tint = Color(1.15, 1.0, 0.95)
	break_t -= delta
	if break_t <= 0.0:
		poise = 0.0
		poise_hit_t = 0.0
		_enter(S.IDLE)

func on_staggered(t: float) -> void:
	if state == S.PHASE2 or not alive:
		return
	close_hitbox()
	end_attack()
	break_t = 0.0
	_enter(S.STAGGERED)
	state_t = 0.0
	velocity.x = -facing * 130.0
	stagger_left = t

var stagger_left: float = 0.0

func _tick_staggered(delta: float) -> void:
	stagger_left -= delta
	velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)
	rig.set_pose(poses["stagger"])
	if stagger_left <= 0.0:
		last_move_id = ""      # 被弹反后可以再出同一招
		same_count = 0
		_enter(S.IDLE)

func on_hurt() -> void:
	# 霸体：普通命中不打断出招，只有闪白反馈
	pass

# ---------------------------------------------------------------- 二阶段
func _start_phase2() -> void:
	phase2 = true
	speed_mult = cfg.boss_phase2_speed
	close_hitbox()
	end_attack()
	roar_t = cfg.boss_roar_time
	_enter(S.PHASE2)
	pal = RigPoses.boss_phase2(base_pal)
	rig.setup(prof, pal)
	invuln = cfg.boss_roar_time
	if battle != null:
		battle.on_boss_phase2(self)

func _tick_phase2(delta: float) -> void:
	velocity.x = 0.0
	velocity.y = 0.0
	rig.set_pose(poses["roar"])
	rig.set_glow(1.0)
	tint = Color(1.2 + 0.5 * sin(Time.get_ticks_msec() * 0.02), 0.55, 0.55)
	roar_t -= delta
	if roar_t <= 0.0:
		tint = Color(1, 1, 1)
		_enter(S.IDLE)

# ---------------------------------------------------------------- 死亡
func kill() -> void:
	alive = false
	close_hitbox()
	end_attack()
	_enter(S.DEAD)

func _tick_dead(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	apply_gravity(delta)
	var k := clampf(state_t / 0.35, 0.0, 1.0)
	rig.set_pose(RigPoses.mix(poses["idle_a"], poses["dead"], k))
	rig.set_glow(0.0)
