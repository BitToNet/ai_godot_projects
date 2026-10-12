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

## 剧本分成两段（原来是单一节奏，结果两个音效永远测不到，见下面的常量注释）：
##   前 COMBO_END 帧 = 进攻段，后 540 帧 = 防守段
const COMBO_END := 360

## 连段攻击间隔。连段窗口是「后摇的前 70%」（cfg.combo_window_ratio = 0.70）：
## attack1 = 起手 0.10 + 判定 0.07 + 后摇 0.20，窗口落在起手后 0.17~0.31 s（第 10~18 帧）。
## 原来每 25 帧（0.417 s）才点一次 —— 窗口早关了、招式也已结束（combo_index 归零），
## 于是永远停在第一段。而 crit_mult = 1.3 只写在第 3 段上（BattleConfig.gd 的 attack3），
## 所以 hit_crit **从来没有机会响**。取 14 帧（0.233 s）正好落在窗口内。
const COMBO_ATTACK_PERIOD := 14

## 弹反提前量：在 Boss 真正出判定帧前 ≤ 0.12 s 按下（cfg.parry_window = 0.15 s）。
## 不能用「预警快结束时才按」：各招的 startup - telegraph = cleave 0.17 / sweep 0.08 /
## axe 0.14 / slam 0.13，预警结束后还要等这么久才吃判定，cleave 会超出 0.15 s 窗口。
const PARRY_LEAD := 0.12

## 关键音效清单（注意：这里是去重后的清单 —— 原来 "land" 出现了两次，
## 白白多占一个断言位，还掩盖了本该被覆盖的其它音效）
const KEY_IDS := [
	"hit_light", "hit_crit", "hit_heavy", "parry", "dodge", "perfect_dodge",
	"jump", "land", "step_a", "step_b", "step_heavy",
	"hurt", "warn_parry", "warn_danger", "sword_wave", "charge_full",
	"poise_break", "roar", "result_win",
]

## 这些音色在别的场景触发（开战 / 弹反抛射物 / 战败 / 界面返回），本自检的剧本覆盖不到，
## 因此只做提示、不做断言 —— 免得看起来像漏测，也免得把它们误当成死音色。
## （它们都有真实调用点；唯一真正没有调用点的是 proj_impact，见 docs/ROADMAP.md）
const OTHER_SCENE_IDS := ["battle_start", "parry_reflect", "result_lose", "proj_impact", "ui_back"]

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
	if not Sfx.cfg().enabled:
		# 音效被 AudioConfig.enabled=false 关掉时既不合成也不播放，本自检无从判定：
		# 明确报 SKIP（退出码 0），而不是既不说"通过"也不说"失败"地留个假象。
		print("[联调] SKIP：AudioConfig.enabled = false（音效已关闭），本次自检不适用")
		host.free()
		quit(0)
		return
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
	# 红光预警（warn_danger）与白光预警（warn_parry）是 on_boss_warn 里同一行的两个分支，
	# 走哪支由 Boss 的**随机**招式表决定（含不可弹反的只有 slam / charge 两招，
	# charge 还要求距离 >150）。固定剧本不保证抽到，所以这里直接压一次不可弹反的招，
	# 保证两支接线都被覆盖 —— 否则「换一条 RNG 流」就会让本自检莫名其妙地少覆盖一种音色。
	for m in battle.cfg.boss_moves_for(battle.boss.kind):
		if not m.parryable:
			battle.on_boss_warn(battle.boss, m)
			break
	battle.on_boss_broken(battle.boss)
	battle.on_boss_phase2(battle.boss)
	# Boss 的沉重脚步（step_heavy）只有两个触发点：APPROACH 追击时（_tick_footsteps，
	# 但 _pick_move 几乎总能选到招，实际很难进入 APPROACH）和 charge 起步时
	# （_start_move 的 "charge" 分支）。两者都由随机招式表决定，剧本不保证抽到，
	# 所以直接用 BossFighter 里已备好的测试钩子 start_move_for_test("charge") 压一次接线。
	battle.boss.start_move_for_test("charge")
	battle._end_battle("win")
	print("[联调] 直接触发接线点：charge_full / sword_wave / perfect_dodge / warn_danger / poise_break / roar / result_win / step_heavy")

## 每帧的虚拟输入，分两个阶段：
##   进攻段（i < COMBO_END）：按连段窗口的节拍连打，逼出第 3 段的会心（hit_crit）
##   防守段（其余）：完全不按攻击 —— 弹反只能从 IDLE/RUN 或攻击后摇取消窗口进入，
##                  一直出招会把弹反输入吃掉（这正是 parry 从来没响过的原因）
func _decide(i: int) -> Dictionary:
	var d := {"mx": 0.0, "attack": false, "attack_held": false, "jump": false, "jump_held": false,
		"dodge": false, "parry": false}
	var pl: PlayerFighter = battle.player
	if pl == null or battle.boss == null or not pl.alive:
		return d
	# 朝 Boss 走（触发跑步脚步，并保持在攻击距离内）
	d["mx"] = signf(battle.boss.global_position.x - pl.global_position.x)
	if i < COMBO_END:
		# 连段节拍：间隔必须落在连段窗口内，否则连不到第 3 段（见 COMBO_ATTACK_PERIOD）
		if i > 30 and i % COMBO_ATTACK_PERIOD == 0:
			d["attack"] = true
		return d

	# ---- 防守段 ----
	# 起跳 / 落地节拍（覆盖 jump / land / step_heavy）
	if i % 45 == 0:
		d["jump"] = true
	if i % 45 < 12:
		d["jump_held"] = true
	# 闪避节拍（撞上判定帧时会升级成 perfect_dodge）
	if i > COMBO_END + 70 and i % 90 == 0:
		d["dodge"] = true
	# 蓄力剑气：先给自己一段无敌（避免被 Boss 打断蓄力），按住 60 帧以上再松开。
	# 只按 attack_held（不是 attack 边沿），所以不会破坏「本段不出招」这个前提。
	if i == COMBO_END + 20:
		pl.invuln = 3.0
	if i >= COMBO_END + 25 and i <= COMBO_END + 90:
		d["attack_held"] = true
	# 反应式防御：按「距判定帧还有多久」而不是「距预警结束还有多久」来按（见 PARRY_LEAD）
	var bm: BattleMove = battle.boss.move
	if bm != null and battle.boss.warn_active():
		var to_hit := bm.startup - battle.boss.move_t
		if bm.parryable:
			if to_hit <= PARRY_LEAD:
				d["parry"] = true
		elif to_hit <= 0.10:
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
	var untested: Array = []
	for id in OTHER_SCENE_IDS:
		if int(counts.get(id, 0)) == 0:
			untested.append(id)
	if not untested.is_empty():
		print("[联调] 提示：以下音色需其它场景才会触发，本自检未覆盖 -> %s" % str(untested))
	if missing.is_empty():
		print("[联调] PASS：关键音效全部触发过")
		quit(0)
	else:
		print("[联调] FAIL：以下音效没被触发过 -> %s" % str(missing))
		quit(1)
