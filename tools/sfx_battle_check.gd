## =============================================================================
##  sfx_battle_check —— 音效联调自检（**不参与游戏运行**，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/sfx_battle_check.gd
##
##  做两件事：
##    1) 启动 Sfx（合成全部音色）
##    2) 用脚本输入驱动一场真实的 Boss 战：跑动 / 跳跃 / 落地 / 闪避 / 弹反 /
##       三段连招 / 蓄力剑气，并统计每个音效实际被触发了多少次
##
##  退出码 0 = 关键音效全部触发过；1 = 有缺失并打印缺失清单
## =============================================================================
extends SceneTree

const FRAMES := 900
const KEY_IDS := [
	"hit_light", "hit_crit", "hit_heavy", "parry", "dodge", "perfect_dodge",
	"jump", "land", "step_a", "step_b", "step_heavy",
	"hurt", "warn_parry", "warn_danger", "sword_wave", "charge_full",
	"poise_break", "roar", "result_win", "land",
]

var host: Node
var battle: BattleScene

func _initialize() -> void:
	_run()

func _run() -> void:
	host = Node.new()
	host.name = "SfxCheckHost"
	root.add_child(host)
	var t0 := Time.get_ticks_msec()
	await Sfx.setup(host)
	print("[联调] 音效库就绪：%d 个音色 / 合成 %d ms / 音效池 %d" % [
		SfxSynth.ids().size(), Time.get_ticks_msec() - t0, Sfx.pool_size()])
	battle = BattleScene.new()
	host.add_child(battle)
	battle.setup({
		"config": BattleConfig.create(),
		"terrain": "grass",
		"boss_name": "联调首领",
		"boss_kind": "bandit",
		"player_hp": 99999.0,
		"boss_hp": 99999.0,
		"boss_poise": 120.0,
		"seed": 20250929,
	})
	battle.set_sim_input({})
	print("[联调] 开始模拟 %d 帧（%.1f 秒）…" % [FRAMES, float(FRAMES) / 60.0])
	for i in FRAMES:
		battle.set_sim_input(_decide(i))
		await physics_frame
		if battle.st == BattleScene.ST_END:
			print("[联调] 战斗在第 %d 帧结束" % i)
			break
	_hook_pass()
	_check()
	host.free()

## 直接调用接线点，覆盖那些依赖精确时机的音效（保证"线接对了"，不依赖随机战况）
func _hook_pass() -> void:
	var pl := battle.player
	var pos := pl.global_position
	battle.charge_ready_fx(pos)
	battle.spawn_sword_wave(pos + Vector2(30, -34), 1.0, 1.0)
	battle._on_perfect_dodge(pl, pos)
	battle.on_boss_broken(battle.boss)
	battle.on_boss_phase2(battle.boss)
	battle._end_battle("win")
	print("[联调] 直接触发接线点：charge_full / sword_wave / perfect_dodge / poise_break / roar / result_win")

## 每帧的虚拟输入：走位 + 连招 + 蓄力 + 对 Boss 前摇做出反应
func _decide(i: int) -> Dictionary:
	var d := {"mx": 0.0, "attack": false, "attack_held": false, "jump": false, "jump_held": false,
		"dodge": false, "parry": false}
	var pl: PlayerFighter = battle.player
	if pl == null or battle.boss == null or not pl.alive:
		return d
	# 朝 Boss 走（触发跑步脚步）
	d["mx"] = signf(battle.boss.global_position.x - pl.global_position.x)
	# 起跳：多试几次（被击飞/硬直会吃掉输入缓冲）
	if i >= 45 and i % 45 == 0:
		d["jump"] = true
	if i > 45 and i % 45 < 12:
		d["jump_held"] = true
	# 闪避（若恰好撞上判定帧 → 触发"完美闪避"）
	if i > 100 and i % 90 == 0:
		d["dodge"] = true
	# 三段连招：每 25 帧点一下
	if i > 120 and i % 25 == 3:
		d["attack"] = true
	# 蓄力剑气：先给自己一段无敌（避免被 Boss 打断蓄力），按住 60 帧以上再松开
	if i == 395:
		pl.invuln = 3.0
	if i >= 400 and i <= 465:
		d["attack_held"] = true
	# 反应式防御：Boss 前摇快走完时 —— 可弹反就弹反（打铁），不可弹反就闪避
	var bm: BattleMove = battle.boss.move
	if bm != null and battle.boss.warn_active():
		if bm.telegraph - battle.boss.move_t <= 0.05:
			if bm.parryable:
				d["parry"] = true
			else:
				d["dodge"] = true
	return d

func _check() -> void:
	var counts := Sfx.counts()
	var rows: Array = counts.keys()
	rows.sort()
	print("[联调] 各音效触发次数：")
	for k in rows:
		print("      %-14s %d" % [String(k), int(counts[k])])
	var missing: Array = []
	for id in KEY_IDS:
		if int(counts.get(id, 0)) == 0:
			missing.append(id)
	print("[联调] 累计播放 %d 次 / 触发过 %d 种音效" % [Sfx.total_plays(), rows.size()])
	if missing.is_empty():
		print("[联调] PASS：关键音效全部触发过")
		quit(0)
	else:
		print("[联调] FAIL：以下音效没被触发过 -> %s" % str(missing))
		quit(1)
