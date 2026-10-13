## =============================================================================
##  BattleScene —— Boss 战斗场景（2D 横版侧视，仿《神之天平》ASTLIBRA）
##
##  结构：
##    CanvasLayer(-5) → SkyLayer（渐变天空，屏幕空间）
##    Node2D(self)    → ParallaxBackdrop 多层视差 + 竞技场（地面/平台/雾墙，自绘）
##                    → PlayerFighter / BossFighter / Projectile / 各种特效
##    CanvasLayer(10) → BattleHUD
##    Camera2D        → 水平跟随玩家、按双方距离拉远拉近、限制在竞技场内
##
##  手感：命中顿帧(hit-stop)、分档震屏、受击闪白、刀光/火花/残影、精准闪避慢动作
##  调试：F3 显示 Hitbox/Hurtbox、状态机状态与弹反窗口计时
## =============================================================================
class_name BattleScene
extends Node2D

signal finished(result: String)

const ST_INTRO := "intro"
const ST_FIGHT := "fight"
const ST_END := "end"

var cfg: BattleConfig
var payload: Dictionary = {}
var hud: BattleHUD
var sky: SkyLayer
var camera: Camera2D
var backdrop: ParallaxBackdrop
var player: PlayerFighter
var boss: BossFighter
var vis: Node2D
var dbg_layer: Node2D

var projectiles: Array = []
var fx: Array = []
var arena_left := 0.0
var arena_right := 1500.0
var ground_y := 0.0
var arena_pad := 26.0

var hitstop := 0.0
var local_scale := 1.0
var slow_t := 0.0
var shake_amt := 0.0
var shake_decay := 4.0
var st := ST_INTRO
var t := 0.0
var rng := RandomNumberGenerator.new()

## 战斗内统一的随机入口：子节点（如 BossFighter 选招）必须走这里，不要用全局 randf()。
## 全局 RNG 每次进程启动都重新随机播种，会让战斗不可复现 —— tools/sfx_battle_check.gd
## 用固定 seed 驱动战斗，却因此偶发失败（实测同一命令 4 次里 1 次 FAIL）。
## rng 在 setup() 里由 payload 的 "seed" 播种，因此本方法的结果是可复现的。
func roll01() -> float:
	return rng.randf()
var debug_on := false
var cam_anchor := 750.0
var warn_move: BattleMove = null
var warn_boss: BossFighter = null
var prev_attack_pressed := false
var prev_jump_pressed := false
var prev_dodge_pressed := false
var prev_parry_pressed := false
var sim_input: Dictionary = {}          ## 自动化测试用：为空时读真实输入
var use_sim := false
var result_t := 0.0
var stats := {"hits_taken": 0, "parries": 0, "perfect_dodges": 0, "damage_dealt": 0.0, "damage_taken": 0.0}

# =============================================================== 构建
func setup(p: Dictionary) -> void:
	payload = p
	cfg = p.get("config", null)
	if cfg == null:
		cfg = BattleConfig.create()
	arena_left = 0.0
	arena_right = cfg.arena_width
	ground_y = cfg.ground_y
	cam_anchor = (arena_left + arena_right) * 0.5
	rng.seed = int(p.get("seed", 12345))

	z_index = 0
	dbg_layer = Node2D.new()
	dbg_layer.z_index = 100
	add_child(dbg_layer)
	dbg_layer.draw.connect(_draw_debug_overlay)
	_build_arena()
	_build_backdrop()
	_build_fighters()
	_build_camera()
	_build_hud()

	set_process(true)
	set_physics_process(true)
	queue_redraw()

func _build_arena() -> void:
	# 地面
	var g := StaticBody2D.new()
	var gc := CollisionShape2D.new()
	var gr := RectangleShape2D.new()
	gr.size = Vector2((arena_right - arena_left) + 2400.0, 400.0)
	gc.shape = gr
	gc.position = Vector2((arena_left + arena_right) * 0.5, ground_y + 200.0)
	g.add_child(gc)
	add_child(g)
	# 两侧不可越过的边界
	for sgn in [-1.0, 1.0]:
		var w := StaticBody2D.new()
		var wc := CollisionShape2D.new()
		var wr := RectangleShape2D.new()
		wr.size = Vector2(80.0, 1400.0)
		wc.shape = wr
		var x := arena_left - 40.0 if sgn < 0.0 else arena_right + 40.0
		wc.position = Vector2(x, ground_y - 700.0)
		w.add_child(wc)
		add_child(w)
	# 两个低平台（可跳上去）
	var plats := [
		{"x": arena_left + 230.0, "y": ground_y - 64.0, "w": 150.0},
		{"x": arena_right - 230.0, "y": ground_y - 64.0, "w": 150.0},
	]
	for pd in plats:
		var b := StaticBody2D.new()
		var c := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = Vector2(pd["w"], 22.0)
		c.shape = r
		c.position = Vector2(pd["x"], pd["y"] + 11.0)
		b.add_child(c)
		b.set_meta("plat", pd)
		add_child(b)

func _build_backdrop() -> void:
	backdrop = ParallaxBackdrop.new()
	add_child(backdrop)
	backdrop.setup(str(payload.get("terrain", "grass")), rng.randi())
	var sky_cv := CanvasLayer.new()
	sky_cv.layer = -5
	add_child(sky_cv)
	sky = ParallaxBackdrop.make_sky(str(payload.get("terrain", "grass")))
	sky_cv.add_child(sky)

func _build_fighters() -> void:
	player = PlayerFighter.new()
	add_child(player)
	player.setup_player(self, cfg, RigPoses.player_palette(payload.get("player_color", Color(0.70, 0.18, 0.20))),
		float(payload.get("player_hp", cfg.player_max_hp)))
	player.global_position = Vector2(arena_left + (arena_right - arena_left) * 0.28, ground_y)

	boss = BossFighter.new()
	add_child(boss)
	boss.setup_boss(self, cfg, float(payload.get("boss_hp", cfg.boss_max_hp)),
		float(payload.get("boss_poise", cfg.boss_max_poise)), str(payload.get("boss_kind", "lord")))
	boss.global_position = Vector2(arena_left + (arena_right - arena_left) * 0.74, ground_y)
	player.set_target(boss)
	boss.set_player(player)
	player.hp_changed.connect(_on_player_hp)
	boss.hp_changed.connect(_on_boss_hp)
	boss.died.connect(_on_boss_dead)
	player.died.connect(_on_player_dead)

func _build_camera() -> void:
	camera = Camera2D.new()
	add_child(camera)
	camera.zoom = Vector2(cfg.cam_zoom_near, cfg.cam_zoom_near)
	camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	camera.position_smoothing_enabled = false

func _build_hud() -> void:
	hud = BattleHUD.new()
	add_child(hud)
	hud.setup(str(payload.get("boss_name", "首领")))
	hud.player_name = str(payload.get("player_name", "玩家部队"))
	hud.player_hp_max = player.max_hp
	hud.player_hp = player.hp
	hud.player_chip = player.hp
	hud.stamina_max = cfg.player_max_stamina
	hud.boss_hp_max = boss.max_hp
	hud.boss_hp = boss.hp
	hud.boss_chip = boss.hp
	hud.boss_poise_max = boss.max_poise
	hud.show_title(str(payload.get("boss_name", "首领")))
	hud.fade_alpha = 1.0

# =============================================================== 主循环
func _physics_process(delta: float) -> void:
	t += delta
	if slow_t > 0.0:
		slow_t -= delta
		if slow_t <= 0.0:
			local_scale = 1.0
	var d := delta * local_scale
	if st == ST_END:
		player.tick(delta)
		_tick_fx(delta)
		_tick_camera(delta)
		return
	var inp := _read_input()
	if player.alive:
		player.feed_input(inp)
	if hitstop > 0.0:
		hitstop -= delta
		_tick_fx(delta)
		_tick_camera(delta)
		return
	player.tick(d)
	boss.tick(d)
	_resolve_melee()
	_tick_projectiles(d)
	_tick_fx(delta)
	_tick_camera(delta)
	if st == ST_INTRO and t > 0.4:
		st = ST_FIGHT

func _process(delta: float) -> void:
	if hud == null:
		return
	hud.player_hp = player.hp
	hud.stamina = player.stamina
	hud.charge = player.glow if (player.state == PlayerFighter.S.CHARGE or player.state == PlayerFighter.S.CHARGE_RELEASE) else 0.0
	hud.charge_full = player.glow >= 0.999
	hud.counter_ready = player.counter_ready()
	hud.boss_hp = boss.hp
	hud.boss_poise = boss.poise
	hud.boss_broken = boss.is_broken()
	hud.boss_phase2 = boss.phase2
	if boss.warn_active():
		hud.boss_warn = 1.0
		hud.boss_warn_parryable = boss.warn_parryable()
	else:
		hud.boss_warn = 0.0
	hud.tick(delta)
	hud.fade_alpha = maxf(0.0, hud.fade_alpha - delta * 1.6)
	sky.tick(delta)
	backdrop.update(camera.global_position, cam_anchor)
	if debug_on:
		_build_debug_lines()
		dbg_layer.queue_redraw()
	queue_redraw()

# ---------------------------------------------------------------- 输入
func _read_input() -> Dictionary:
	if use_sim:
		return sim_input
	var mx := Input.get_axis("move_left", "move_right")
	var atk := Input.is_action_pressed("battle_attack")
	var jmp := Input.is_action_pressed("battle_jump")
	var dg := Input.is_action_pressed("battle_dodge")
	var pr := Input.is_action_pressed("battle_parry")
	var d := {
		"mx": mx,
		"attack": atk and not prev_attack_pressed,
		"attack_held": atk,
		"jump": jmp and not prev_jump_pressed,
		"jump_held": jmp,
		"dodge": dg and not prev_dodge_pressed,
		"parry": pr and not prev_parry_pressed,
	}
	prev_attack_pressed = atk
	prev_jump_pressed = jmp
	prev_dodge_pressed = dg
	prev_parry_pressed = pr
	return d

func _unhandled_input(event: InputEvent) -> void:
	# 键位 / 手柄绑定同样来自 project.godot 的 [input] 段（debug_toggle / toggle_mute / battle_pause）
	if event.is_action_pressed("debug_toggle"):
		debug_on = not debug_on
		hud.debug_on = debug_on
	elif event.is_action_pressed("toggle_mute"):
		var muted := Sfx.toggle_mute()
		hud.show_title("音效已静音" if muted else "音效已开启", 1.2)
	elif event.is_action_pressed("battle_pause"):
		_end_battle("escape")

# ---------------------------------------------------------------- 相机
func _tick_camera(delta: float) -> void:
	var vp := get_viewport_rect().size
	var mid := (player.global_position.x + boss.global_position.x) * 0.5
	var dist := absf(player.global_position.x - boss.global_position.x) + absf(player.global_position.y - boss.global_position.y) * 0.35
	var k := clampf(dist / cfg.cam_dist_full, 0.0, 1.0)
	var target_zoom: float = lerpf(cfg.cam_zoom_near, cfg.cam_zoom_far, k)
	var z: float = lerpf(camera.zoom.x, target_zoom, 1.0 - exp(-6.0 * delta))
	camera.zoom = Vector2(z, z)
	var half_w := vp.x * 0.5 / z
	var tx := mid
	if arena_right - arena_left > half_w * 2.0:
		tx = clampf(mid, arena_left + half_w, arena_right - half_w)
	else:
		tx = (arena_left + arena_right) * 0.5
	var ty := ground_y - 76.0
	camera.global_position = Vector2(lerpf(camera.global_position.x, tx, 1.0 - exp(-7.0 * delta)),
		lerpf(camera.global_position.y, ty, 1.0 - exp(-5.0 * delta)))
	if shake_amt > 0.001:
		camera.offset = Vector2(rng.randf_range(-shake_amt, shake_amt), rng.randf_range(-shake_amt, shake_amt))
		shake_amt = maxf(0.0, shake_amt - shake_decay * shake_amt * delta - 6.0 * delta)
	else:
		camera.offset = Vector2.ZERO

func shake(amount: float, dur: float = 0.25) -> void:
	shake_amt = maxf(shake_amt, amount)
	shake_decay = 1.0 / maxf(0.05, dur)

func hit_stop(v: float) -> void:
	hitstop = maxf(hitstop, v)

func slow_motion(scale_v: float, dur: float) -> void:
	local_scale = scale_v
	slow_t = dur

# ---------------------------------------------------------------- 判定结算
func _resolve_melee() -> void:
	for f in player.poll_hits():
		if f == boss:
			resolve_hit(player, boss, player.hitbox.move)
	for f in boss.poll_hits():
		if f == player:
			resolve_hit(boss, player, boss.hitbox.move)

func resolve_hit(attacker: Fighter, defender: Fighter, move: BattleMove) -> void:
	if move == null or not defender.alive:
		return
	var hit_pos := defender.global_position + Vector2(0, -defender.body_size.y * 0.6)

	# ---- 玩家防御判定 ----
	if defender.is_player:
		var pl := defender as PlayerFighter
		if pl.is_dodging_with_iframe():
			if pl.state_t <= cfg.perfect_dodge_window and slow_t <= 0.0:
				_on_perfect_dodge(pl, hit_pos)
			return
		if pl.is_parry_window():
			if move.parryable:
				_on_parry_success(pl, attacker as BossFighter, move, hit_pos)
				return
		if not pl.can_be_hit():
			return
	else:
		if not defender.can_be_hit():
			return

	# ---- 伤害计算 ----
	var dmg := move.damage
	var is_counter := false
	var is_crit := false
	if attacker.is_player:
		var pl2 := attacker as PlayerFighter
		if pl2.counter_ready():
			is_counter = true
			dmg *= cfg.parry_counter_mult
			pl2.counter_t = 0.0
		if move.crit_mult > 1.0:
			is_crit = true
			dmg *= move.crit_mult
		if defender == boss and boss.is_broken():
			dmg *= cfg.boss_break_damage_mult
	if attacker == boss:
		dmg *= boss.dmg_mult
	var knock := move.knockback
	if defender == boss:
		knock *= cfg.boss_knock_scale
	defender.receive_damage(dmg, attacker.global_position.x, knock, move.lift, cfg.hurt_time)
	defender.on_hurt()

	# ---- 表现 ----
	var heavy := is_counter or is_crit or move.hitstop >= 0.09
	hit_stop(move.hitstop)
	spawn_hit_sparks(hit_pos, attacker.is_player)
	# 击中音效：我方命中 = 剑刃劈砍；会心/反击斩换更亮的金属音色；Boss 命中我方 = 沉闷重击
	if attacker.is_player:
		Sfx.play_2d(self, "hit_crit" if (is_counter or is_crit) else "hit_light", hit_pos)
	else:
		Sfx.play_2d(self, "hit_heavy", hit_pos)
	_reg(SlashFx.slash(self, hit_pos, randf_range(-0.7, 0.7) + (0.0 if attacker.is_player else PI),
		54.0, Color(1, 1, 1, 0.95), 2.4, 13.0 if heavy else 9.0))
	shake(cfg.shake_heavy.x if heavy else cfg.shake_medium.x, cfg.shake_heavy.y if heavy else cfg.shake_medium.y)
	var col := Color(1, 0.95, 0.75)
	var big := false
	if is_counter:
		col = Color(1.0, 0.82, 0.25)
		big = true
	elif is_crit:
		col = Color(1.0, 0.55, 0.25)
		big = true
	pop_text(hit_pos, str(int(round(dmg))), col, big)
	if is_counter:
		pop_text(hit_pos + Vector2(0, -26), "反击斩!", Color(1.0, 0.85, 0.35), true)
	elif is_crit:
		pop_text(hit_pos + Vector2(0, -26), "会心!", Color(1.0, 0.6, 0.3), false)

	# ---- 统计 / 破防 ----
	if attacker.is_player:
		stats["damage_dealt"] = float(stats["damage_dealt"]) + dmg
		if defender == boss:
			boss.add_poise(move.poise_damage)
			if boss.state == BossFighter.S.PHASE2:
				pass
	else:
		stats["damage_taken"] = float(stats["damage_taken"]) + dmg
		stats["hits_taken"] = int(stats["hits_taken"]) + 1
		hud.hit_flash = 1.0

func resolve_projectile_hit(p: Projectile, defender: Fighter) -> void:
	if defender == null or not defender.alive:
		return
	var hit_pos := defender.global_position + Vector2(0, -defender.body_size.y * 0.55)
	if defender.is_player:
		var pl := defender as PlayerFighter
		if pl.is_dodging_with_iframe():
			if pl.state_t <= cfg.perfect_dodge_window and slow_t <= 0.0:
				_on_perfect_dodge(pl, hit_pos)
			return
		if pl.is_parry_window() and p.parryable:
			# 弹反投射物：反弹回去打原主
			_on_parry_success(pl, boss, null, hit_pos)
			p.reflect(pl)
			pop_text(hit_pos + Vector2(0, -30), "弹返!", Color(0.6, 1.0, 1.0), true)
			return
		if not pl.can_be_hit():
			return
	else:
		if not defender.can_be_hit():
			return
	var dmg := p.damage
	if defender == boss and boss.is_broken():
		dmg *= cfg.boss_break_damage_mult
	defender.receive_damage(dmg, p.global_position.x, p.knockback, p.lift, cfg.hurt_time)
	defender.on_hurt()
	hit_stop(p.hitstop + 0.02)
	shake(cfg.shake_medium.x, cfg.shake_medium.y)
	spawn_hit_sparks(hit_pos, p.from_player)
	Sfx.play_2d(self, "hit_heavy" if not p.from_player else "hit_light", hit_pos, -2.0)
	pop_text(hit_pos, str(int(round(dmg))), Color(1, 0.95, 0.75), false)
	if p.from_player:
		stats["damage_dealt"] = float(stats["damage_dealt"]) + dmg
		if defender == boss:
			boss.add_poise(p.poise_damage)
	else:
		stats["damage_taken"] = float(stats["damage_taken"]) + dmg
		stats["hits_taken"] = int(stats["hits_taken"]) + 1
		hud.hit_flash = 1.0

func _on_perfect_dodge(pl: PlayerFighter, pos: Vector2) -> void:
	stats["perfect_dodges"] = int(stats["perfect_dodges"]) + 1
	slow_motion(cfg.perfect_dodge_slow, cfg.perfect_dodge_time)
	_reg(SlashFx.ring(self, pl.global_position + Vector2(0, -30), 46.0, Color(0.6, 0.95, 1.0), 0.4))
	pop_text(pl.global_position + Vector2(0, -74), "完美闪避!", Color(0.55, 0.95, 1.0), true)
	shake(cfg.shake_light.x, cfg.shake_light.y)
	# 完美闪避音效：反向上扫的"吸入感" + 上行铃声（与慢动作同步）
	Sfx.play_2d(self, "perfect_dodge", pl.global_position + Vector2(0, -30))

func _on_parry_success(pl: PlayerFighter, bs: BossFighter, move: BattleMove, pos: Vector2) -> void:
	stats["parries"] = int(stats["parries"]) + 1
	hit_stop(cfg.parry_hitstop)
	hud.parry_flash = 1.0
	shake(cfg.shake_heavy.x * 0.8, cfg.shake_heavy.y)
	_reg(SlashFx.ring(self, pos, 58.0, Color(1, 1, 1), 0.34))
	_reg(SparkBurst.burst(self, pos, 26, Color(1, 0.98, 0.8), 1.4))
	pop_text(pos + Vector2(0, -22), "弹反!", Color(1.0, 0.95, 0.55), true)
	# 弹反音效：打铁声（铁砧 + 非谐金属泛音）；弹返投射物时升调并多一层回旋风
	Sfx.play_2d(self, "parry_reflect" if move == null else "parry", pos)
	pl.on_parry_success()
	if bs != null:
		bs.add_poise(cfg.parry_poise_damage)
		bs.on_staggered(cfg.parry_stagger)

# =============================================================== 特效生成
## 登记特效：登记后由 _tick_fx() 统一推进生命周期。
## 兜底：若某个特效忘了走 _reg()（历史上弹反火花就漏过一次，变成永久钉在屏幕上的鬼影），
## 它的 fx_managed 保持 false，会由自身 _process 推进，最坏也只是多跑一次 tick，
## 绝不会永远停在生成的那一帧。
func _reg(n: Node) -> void:
	if "fx_managed" in n:
		n.set("fx_managed", true)
	fx.append(n)

## 飘字（伤害数字 / 弹反! / 破防! 等）：必须注册进 fx，否则不会被 tick，
## 就会永远钉在屏幕上不消失。
func pop_text(pos: Vector2, text: String, col: Color, big: bool) -> void:
	_reg(FloatingText.spawn(self, pos, text, col, big))

func spawn_afterimage(pos: Vector2, pose: Dictionary, prof: Dictionary, pal: Dictionary, facing: float, dur: float) -> void:
	var a := Afterimage.new()
	add_child(a)
	a.setup(pos, pose, prof, pal, facing, dur)
	_reg(a)

func spawn_hit_sparks(pos: Vector2, from_player: bool) -> void:
	var col := Color(1.0, 0.95, 0.7) if from_player else Color(0.95, 0.6, 0.45)
	_reg(SparkBurst.burst(self, pos, 16, col, 1.0))
	_reg(SparkBurst.burst(self, pos, 8, Color(1, 1, 1), 0.7, 1.6))

func spawn_dust_burst(pos: Vector2, n: int) -> void:
	_reg(SparkBurst.burst(self, pos, n, Color(0.75, 0.72, 0.65, 0.85), 0.8, 2.6, -90.0, 1))

func spawn_land_puff(pos: Vector2) -> void:
	_reg(SparkBurst.burst(self, pos, 7, Color(0.8, 0.78, 0.7, 0.8), 0.55, 2.2, -90.0, 1))

func spawn_dissipate(pos: Vector2, col: Color) -> void:
	_reg(SparkBurst.burst(self, pos, 12, col, 0.9))
	_reg(SlashFx.ring(self, pos, 34.0, col, 0.26))

func charge_ready_fx(pos: Vector2) -> void:
	var r := SlashFx.ring(self, pos + Vector2(0, -32), 74.0, Color(0.7, 0.92, 1.0), 0.34)
	_reg(r)
	_reg(SparkBurst.burst(self, pos + Vector2(0, -32), 18, Color(0.75, 0.95, 1.0), 0.9, TAU))
	shake(cfg.shake_light.x, cfg.shake_light.y)
	# 蓄满提示音（与剑身闪光同帧）
	Sfx.play_2d(self, "charge_full", pos + Vector2(0, -32))

func spawn_sword_wave(pos: Vector2, facing: float, power: float) -> void:
	var p := Projectile.new()
	add_child(p)
	p.owner_fighter = player
	p.setup(self, "wave", pos, facing, true)
	p.fire_wave(facing, power)
	projectiles.append(p)
	# 剑气出手：蓄得越满音调越高、越响
	Sfx.play_2d(self, "sword_wave", pos, -2.0 if power < 0.985 else 0.5, lerpf(1.12, 0.88, clampf(power, 0.0, 1.0)))
	if power >= 0.985:
		hit_stop(0.10)
		shake(cfg.shake_heavy.x, cfg.shake_heavy.y)
	else:
		shake(cfg.shake_light.x, cfg.shake_light.y)

func spawn_boss_axe(pos: Vector2, facing: float) -> void:
	var p := Projectile.new()
	add_child(p)
	p.owner_fighter = boss
	p.setup(self, "axe", pos, facing, false)
	p.fire_axe(facing)
	projectiles.append(p)
	# Boss 掷斧：同一段风声压低音高（更沉、更重）
	Sfx.play_2d(self, "sword_wave", pos, -3.0, 0.70)

func spawn_shockwaves(pos: Vector2, dir: float) -> void:
	var p := Projectile.new()
	add_child(p)
	p.owner_fighter = boss
	p.setup(self, "shockwave", Vector2(pos.x, ground_y - 13.0), dir, false)
	p.fire_shockwave(dir)
	projectiles.append(p)
	# 地面冲击波：低沉的一记闷响
	Sfx.play_2d(self, "land", Vector2(pos.x, ground_y - 13.0), -1.0, 0.62)

func spawn_fissure(pos: Vector2, facing: float) -> void:
	var p := Projectile.new()
	add_child(p)
	p.owner_fighter = boss
	p.setup(self, "fissure", Vector2(pos.x, ground_y - 46.0), facing, false)
	p.fire_fissure(facing)
	projectiles.append(p)
	shake(cfg.shake_medium.x, cfg.shake_medium.y)
	Sfx.play_2d(self, "sword_wave", Vector2(pos.x, ground_y - 46.0), -5.0, 0.55)

func spawn_fissure_spike(pos: Vector2) -> void:
	_reg(SparkBurst.burst(self, pos, 9, Color(1.0, 0.5, 0.25), 0.9, 2.0, -90.0))
	_reg(SlashFx.slash(self, pos + Vector2(0, -20), -PI * 0.5, 26.0, Color(1.0, 0.55, 0.3), 2.0, 8.0))

func remove_projectile(p: Projectile) -> void:
	projectiles.erase(p)
	p.queue_free()

func _tick_projectiles(d: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p = projectiles[i]
		if not is_instance_valid(p):
			projectiles.remove_at(i)
			continue
		p.tick(d)

func _tick_fx(delta: float) -> void:
	for i in range(fx.size() - 1, -1, -1):
		var n = fx[i]
		if not is_instance_valid(n):
			fx.remove_at(i)
			continue
		n.tick(delta)

# =============================================================== Boss 事件
func on_boss_warn(b: BossFighter, m: BattleMove) -> void:
	warn_move = m
	warn_boss = b
	# 出招预警的听觉提示（可在 AudioConfig 里关掉）：
	# 可弹反 = 清脆 "叮"（提示玩家按右键打铁）；不可弹反 = 低沉嗡鸣（提示快闪避）
	if Sfx.cfg().warn_cues:
		Sfx.play_2d(self, "warn_parry" if m.parryable else "warn_danger",
			b.global_position + Vector2(0, -b.body_size.y * 0.62))

func on_boss_broken(_b: BossFighter) -> void:
	hit_stop(0.12)
	shake(cfg.shake_heavy.x, cfg.shake_heavy.y)
	pop_text(boss.global_position + Vector2(0, -220), "破防!", Color(0.7, 0.95, 1.0), true)
	_reg(SparkBurst.burst(self, boss.global_position + Vector2(0, -100), 30, Color(0.9, 0.95, 1.0), 1.2))
	Sfx.play_2d(self, "poise_break", boss.global_position + Vector2(0, -100))

func on_boss_phase2(_b: BossFighter) -> void:
	shake(cfg.shake_heavy.x * 1.6, 1.2)
	pop_text(boss.global_position + Vector2(0, -230), "第二阶段！", Color(1.0, 0.4, 0.3), true)
	_reg(SparkBurst.burst(self, boss.global_position + Vector2(0, -110), 40, Color(1.0, 0.5, 0.25), 1.5))
	hud.show_title("第 二 阶 段", 2.0)
	Sfx.play_2d(self, "roar", boss.global_position + Vector2(0, -110))

func _on_player_hp(_hp: float, _m: float) -> void:
	pass

func _on_boss_hp(_hp: float, _m: float) -> void:
	pass

func _on_boss_dead() -> void:
	_end_battle("win")

func _on_player_dead() -> void:
	_end_battle("lose")

func _end_battle(res: String) -> void:
	if st == ST_END:
		return
	st = ST_END
	result_t = 0.0
	match res:
		"win":
			hud.show_result("胜利", 3.2)
			player.state = PlayerFighter.S.IDLE
			shake(cfg.shake_medium.x, 0.5)
			Sfx.play("result_win")
		"lose":
			hud.show_result("战败", 3.2)
			Sfx.play("result_lose")
		_:
			hud.show_result("撤退", 2.2)
			Sfx.play("ui_back")
	set_meta("result", res)
	_finish_later(res)

func _finish_later(res: String) -> void:
	await get_tree().create_timer(2.6).timeout
	hud.fade_alpha = 0.0
	var tw := create_tween()
	tw.tween_property(hud, "fade_alpha", 1.0, 0.6)
	await tw.finished
	finished.emit(res)

# =============================================================== 绘制（竞技场 + 调试）
func _draw() -> void:
	var gc: Color = backdrop.ground_col if backdrop != null else Color(0.3, 0.44, 0.22)
	var gd: Color = backdrop.ground_dark if backdrop != null else Color(0.18, 0.28, 0.14)
	# 地面
	draw_rect(Rect2(arena_left - 600.0, ground_y, (arena_right - arena_left) + 1200.0, 420.0), gd)
	draw_rect(Rect2(arena_left - 600.0, ground_y, (arena_right - arena_left) + 1200.0, 26.0), gc)
	draw_line(Vector2(arena_left - 600.0, ground_y), Vector2(arena_right + 600.0, ground_y),
		gc.lightened(0.35), 3.0)
	# 地面装饰
	if backdrop != null:
		for a in backdrop.accents:
			var x: float = a["x"]
			draw_line(Vector2(x, ground_y), Vector2(x + 2.0, ground_y - float(a["h"])), a["c"], 2.0)
	# 平台
	for c in get_children():
		if c is StaticBody2D and c.has_meta("plat"):
			var pd: Dictionary = c.get_meta("plat")
			var r := Rect2(pd["x"] - pd["w"] * 0.5, pd["y"], pd["w"], 22.0)
			draw_rect(r, gd.darkened(0.18))
			draw_rect(Rect2(r.position, Vector2(r.size.x, 6.0)), gc.darkened(0.12))
			draw_rect(r, gd.darkened(0.55), false, 1.5)
	# 两侧雾墙 / 岩壁
	for sgn in [-1.0, 1.0]:
		var x0: float = arena_left if sgn < 0.0 else arena_right
		var dir: float = -1.0 if sgn < 0.0 else 1.0
		for i in 5:
			var w := 40.0 + 26.0 * float(i)
			var c := Color(0.78, 0.82, 0.9, 0.16 - 0.025 * float(i))
			draw_rect(Rect2(minf(x0, x0 + dir * w), ground_y - 520.0, w, 620.0), c)
		draw_rect(Rect2(minf(x0, x0 + dir * 26.0), ground_y - 520.0, 26.0, 620.0), Color(0.10, 0.11, 0.15, 0.85))
		draw_line(Vector2(x0, ground_y - 520.0), Vector2(x0, ground_y + 100.0), Color(0.85, 0.9, 1.0, 0.5), 2.0)
	# Boss 招式地面预警
	# 纯投射物招式的判定盒只是占位小方块，不画地面预警
	if boss != null and boss.warn_active() and boss.move != null and boss.move.box_size.x >= 44.0:
		var m := boss.move
		var prog := clampf(boss.move_t / maxf(0.01, m.telegraph), 0.0, 1.0)
		var cx := boss.global_position.x + m.box_offset.x * boss.facing
		var w2: float = m.box_size.x
		var h2: float = 34.0
		# 可弹反=白色提示框（描边为主，避免一片死白），不可弹反=红色实心警示
		var col := Color(1, 1, 1, 0.14) if m.parryable else Color(1.0, 0.25, 0.2, 0.34)
		var line_c := Color(1, 1, 1, 0.85) if m.parryable else Color(1.0, 0.35, 0.28, 0.95)
		var r2 := Rect2(cx - w2 * 0.5, ground_y - h2, w2, h2)
		draw_rect(r2, Color(col.r, col.g, col.b, col.a * (0.35 + 0.65 * prog)))
		draw_rect(r2, line_c, false, 2.5)
		# 上沿随前摇进度向下压，读起来像"危险区域正在合拢"
		draw_rect(Rect2(cx - w2 * 0.5, ground_y - h2 * prog, w2, h2 * prog),
			Color(col.r, col.g, col.b, (0.30 if m.parryable else 0.45)))


## 调试层：画在所有角色之上（z_index=100）
func _draw_debug_overlay() -> void:
	if not debug_on:
		return
	_draw_debug_boxes()

func _draw_debug_boxes() -> void:
	for f in [player, boss]:
		if f == null:
			continue
		_draw_area_rect(f.hurtbox, Color(0.3, 0.6, 1.0, 0.35), Color(0.4, 0.7, 1.0))
		if f.hitbox.monitoring:
			_draw_area_rect(f.hitbox, Color(1.0, 0.2, 0.2, 0.4), Color(1.0, 0.3, 0.3))
	for p in projectiles:
		if is_instance_valid(p):
			_draw_area_rect(p.hitbox, Color(1.0, 0.6, 0.1, 0.35), Color(1.0, 0.7, 0.2))

func _draw_area_rect(a: Area2D, fill: Color, line: Color) -> void:
	if a == null:
		return
	var cs := a.get_child(0) as CollisionShape2D
	if cs == null or not (cs.shape is RectangleShape2D):
		return
	var sz: Vector2 = (cs.shape as RectangleShape2D).size
	var c := a.global_position + cs.position
	dbg_layer.draw_rect(Rect2(c - sz * 0.5, sz), fill)
	dbg_layer.draw_rect(Rect2(c - sz * 0.5, sz), line, false, 2.0)

func _build_debug_lines() -> void:
	var pl := player
	var bl := boss
	var lines: Array = []
	lines.append("玩家状态: %s   蓄力 %.2f  连段 %d" % [pl.state_label, pl.glow, pl.combo_index + 1])
	if pl.is_parry_window():
		lines.append("弹反窗口剩余: %.3f 秒" % maxf(0.0, cfg.parry_window - pl.state_t))
	else:
		lines.append("弹反窗口: 关闭")
	lines.append("闪避无敌剩余: %.3f   反击斩: %s" % [maxf(0.0, cfg.dodge_iframe - pl.state_t) if pl.state == PlayerFighter.S.DODGE else 0.0,
		"就绪" if pl.counter_ready() else "无"])
	lines.append("Boss状态: %s   %s   招式: %s" % [bl.state_label,
		"二阶段" if bl.phase2 else "一阶段", bl.move.display if bl.move != null else "-"])
	lines.append("Boss 破防值: %.0f / %.0f   硬直剩余 %.2f" % [bl.poise, bl.max_poise, bl.break_t if bl.is_broken() else 0.0])
	lines.append("顿帧: %.3f   慢动作: %.2f   缩放: %.2f" % [hitstop, slow_t, camera.zoom.x])
	lines.append("弹幕: %d   特效: %d   FPS: %d" % [projectiles.size(), fx.size(), Engine.get_frames_per_second()])
	lines.append("音效: 累计 %d 次（音效池 %d，%s）" % [Sfx.total_plays(), Sfx.pool_size(),
		"已静音" if Sfx.is_muted() else "开启"])
	lines.append("背景音乐: %s（%s，切换 %d 次）" % [
		Bgm.current() if Bgm.current() != "" else "未播放",
		"正在响" if Bgm.is_playing(Bgm.current()) else "淡入中 / 已停",
		Bgm.total_plays()])
	hud.dbg_lines = lines

# =============================================================== 测试接口
func set_sim_input(d: Dictionary) -> void:
	sim_input = d
	use_sim = true

func clear_sim_input() -> void:
	use_sim = false
	sim_input = {}

func boss_state_name() -> String:
	return boss.state_label

func player_state_name() -> String:
	return player.state_label
