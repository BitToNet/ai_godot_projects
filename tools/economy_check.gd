## =============================================================================
##  economy_check —— 经济 / 军费 / 士气 的定式自检 + 平衡曲线（**不参与游戏运行**）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/economy_check.gd
##
##  为什么需要它：经济是一条**反馈回路**（工资涨 → 欠薪 → 士气掉 → 逃兵 → 兵力少 →
##  工资又降），回路的形状只有在时间轴上跑几十天才能看出来。而门禁里的 900 帧主场景
##  连一天都过不完，所以这条回路必须有一个直接跑结算的入口。
##
##  本脚本不建世界、不建 UI：只 new 一个没有标签的 PlayerParty —— 结算逻辑本身
##  不依赖任何场景节点，这也正是把 CampaignState 写成 RefCounted 的原因。
##
##  数值全部来自 EconomyRules（那里逐条标注了骑砍参考来源与本地化取舍）。
##  断言只锁「公式形状」，不锁平衡结果 —— 平衡要改就改 EconomyRules，
##  这里要是跟着改断言，说明改错了地方。
##
##  退出码：0 = 全部通过；1 = 有断言失败
## =============================================================================
extends SceneTree

var _fails: Array[String] = []
var _total: int = 0

func _initialize() -> void:
	_run()

func _ok(cond: bool, what: String) -> void:
	_total += 1
	if cond:
		print("  [ok]   %s" % what)
	else:
		_fails.append(what)
		print("  [FAIL] %s" % what)

func _run() -> void:
	var rules := EconomyRules.create()
	var pp := PlayerParty.new()
	pp.troop_count = GameState.PLAYER_START_TROOPS
	var cs := CampaignState.new()
	cs.setup(rules, pp)

	print("[经济] 定式自检（不跑地图生成）")
	print("  开局：%s" % cs.debug_line())

	# ---------------- 军费：照搬 (等级+3)²/25 ----------------
	_ok(rules.wage_per_man_week(0) == 1, "单兵周薪 档0（代用等级 4）=(4+3)²/25=1")
	_ok(rules.wage_per_man_week(1) == 9, "单兵周薪 档1（代用等级 12）=(12+3)²/25=9")
	_ok(rules.wage_per_man_week(2) == 25, "单兵周薪 档2（代用等级 22）=(22+3)²/25=25")
	_ok(rules.weekly_wage(37, 0, 0) == 37, "37 人档0 周薪 = 37（Σ 单兵周薪 × 人数）")
	_ok(rules.weekly_wage(37, 2, 0) == 925, "37 人档2 周薪 = 925（精锐化 25 倍工资）")
	_ok(rules.leadership_of_renown(1000) == 10, "声望 1000 → 领导力 10")
	_ok(rules.leadership_of_renown(99999) == 10, "领导力封顶 10（不能无限减薪）")
	_ok(rules.leadership_of_renown(50) == 0, "声望 50 → 领导力 0")
	_ok(rules.weekly_wage(37, 0, 1000) == 18, "领导力 10 → 工资减半（37×50/100=18，整数截断）")
	_ok(rules.weekly_wage(37, 0, 1000) == rules.weekly_wage_base(37, 0) * 50 / 100,
		"折扣式 = 基数×(100−5×领导力)/100（照搬 game_get_troop_wage 末行）")

	# ---------------- 编制 ----------------
	_ok(rules.party_capacity(0) == rules.base_party_capacity, "声望 0 → 编制 = 基础 40")
	_ok(rules.party_capacity(400) == 80, "声望 400 → 编制 80（+领导力4×5 + 400/20）")

	# ---------------- 士气：照搬 50 + 领导力×12 − 人数 + 食物 − 断粮 − 欠薪 ------
	_ok(rules.morale_of(37, 0, 120, 35, 0) == 40,
		"开局士气 = 50 + 12(领导力1) − 37 + 15(满粮封顶) = 40")
	_ok(rules.morale_of(10, 0, 120, 35, 0) == 67, "小队（10 人）满粮士气 = 67")
	_ok(rules.morale_of(10, 0, 120, 0, 0) == 22, "同样 10 人断粮 → 22（−15 食物 −30 断粮）")
	_ok(rules.morale_of(137, 0, 120, 35, 0) == 0, "兵力 137 → 规模压力把士气压到 0（钳位）")
	_ok(rules.morale_of(37, 0, 120, 35, 1) == 30, "欠薪 1 周 −10")
	_ok(rules.morale_of(37, 0, 120, 35, 9) == 9, "欠薪 9 周 −31（clamp 上界，照搬 01 §3.3）")
	_ok(rules.food_bonus(1000) == rules.food_bonus_cap, "食物士气加成封顶（本地化）")

	# ---------------- 补给与逃兵 ----------------
	_ok(rules.supply_per_day(37) == 3, "37 兵每天吃 3 件补给（每 10 兵 1 件）")
	_ok(rules.supply_per_day(3) == 1, "再小的部队每天至少吃 1 件")
	_ok(rules.deserters(37, 40) == 0, "士气 40 不逃兵")
	_ok(rules.deserters(37, 0) == 9, "士气 0 → 逃 9 人（37×25%）")

	# ---------------- 撤退士气代价：两个比例的乘积 ----------------
	_ok(_retreat(4, 4, 37) == 1, "撤退代价 双方各阵亡 4 / 队 37 → −1")
	_ok(_retreat(20, 20, 100) == 3, "撤退代价 双方各阵亡 20 / 队 100 → −3")
	_ok(_retreat(2, 18, 10) == 0,
		"撤退代价 我方只占 1/10 阵亡 → 截断成 0（原式是复合比例，不是线性）")

	# ---------------- 招募：min(志愿者池, 编制余位, 金/10) ----------------
	var d0 := cs.denars
	var free0 := cs.free_capacity()
	var got := cs.recruit(100, 10)
	_ok(got == free0, "招募数 = 编制余位（钱够时先卡编制，%d 人）" % got)
	_ok(cs.troops() == GameState.PLAYER_START_TROOPS + got, "兵力按招募数增加")
	_ok(cs.denars == d0 - got * 10, "扣钱 = 人数 × 10 金（照搬村民 10 金/人）")
	_ok(cs.recruit(100, 10) == 0, "编制满了招不到人")
	_ok(cs.denars == d0 - got * 10, "被拒时一分钱不扣")
	# 钱不够时按 金/10 截断。必须用一个编制还有余位的小队来测：
	# 上面那支部队已经招满，先卡编制，测不出「钱」这一层。
	var poor := CampaignState.new()
	var p2 := PlayerParty.new()
	p2.troop_count = 10
	poor.setup(rules, p2)
	poor.denars = 25
	_ok(poor.recruit(5, 10) == 2, "钱不够时按 金/10 截断（25 金 → 2 人）")
	_ok(poor.denars == 5, "截断后剩 5 金（20 金买了 2 人）")
	_ok(poor.recruit(5, 10) == 0, "只剩 5 金时一个人也招不到")
	p2.free()

	# ---------------- 升档与战利品入账 ----------------
	var before := cs.wage()
	_ok(cs.upgrade_tier(), "升档成功（钱够）")
	_ok(cs.tier == 1 and cs.wage() > before, "升档后周薪上升（%d → %d）" % [before, cs.wage()])
	cs.add_spoils(306, "赃物")
	cs.add_renown(6)
	_ok(cs.denars > 0 and cs.renown > 0, "战利品与声望入账")

	# ---------------- 战斗力：升档必须买到东西 ----------------
	# 开局（37 人、档 0）倍率正好 1.0 —— 这是「第四轮不改变开局第一战手感」的保证。
	var fresh := CampaignState.new()
	var p3 := PlayerParty.new()
	p3.troop_count = GameState.PLAYER_START_TROOPS
	fresh.setup(rules, p3)
	_ok(fresh.combat_power() == GameState.PLAYER_START_TROOPS,
		"开局战斗强度 = 兵力（倍率 1.0）")
	_ok(is_equal_approx(fresh.combat_hp(120.0), 120.0),
		"开局战斗血量 = 基准（与第四轮之前完全一致）")
	fresh.tier = 2
	_ok(fresh.combat_power() > GameState.PLAYER_START_TROOPS, "升到精锐后强度上升")
	_ok(fresh.combat_power() == 66, "37 人精锐强度 = int(37×1.8) = 66")
	_ok(fresh.combat_hp(120.0) > 200.0 and fresh.combat_hp(120.0) < 220.0,
		"精锐战斗血量 ≈ 基准 × 1.8（%.1f，升级费买到的是血量）" % fresh.combat_hp(120.0))
	p3.free()

	# ---------------- 时间轴：跑 42 天，看回路形状 ----------------
	# 假设（写清楚，免得把平衡结论当成实证）：每 5 天打赢一场 50 人匪帮；
	# 粮低于 15 件就按 supply_unit_price 补到 30 件；第 15 天升级到「正规军」。
	print("")
	print("[经济] 时间轴：开局 %d 金 / %d 兵，每 5 天一场 50 人匪帮，粮 <15 就补到 30，第 15 天升档" % [
		GameState.START_DENARS, GameState.PLAYER_START_TROOPS])
	var sim := CampaignState.new()
	var sp := PlayerParty.new()
	sp.troop_count = GameState.PLAYER_START_TROOPS
	sim.setup(rules, sp)
	var min_denars := sim.denars
	var weeks_paid := 0
	var weeks_short := 0
	var starve_days := 0
	var upgraded_on := 0
	for d in range(2, 43):
		if d % 5 == 0:
			sim.add_spoils(int(round(50.0 * 0.85 * rules.loot_per_troop)), "赃物")
			sim.add_renown(5)
		if d == 15 and sim.can_upgrade():
			sim.upgrade_tier()
			upgraded_on = d
		if sim.supplies < 15:
			var buy := mini(30 - sim.supplies, sim.denars / rules.supply_unit_price)
			if buy > 0:
				sim.spend(buy * rules.supply_unit_price)
				sim.supplies += buy
		sim.on_day_changed(d)
		min_denars = mini(min_denars, sim.denars)
		if d % GameState.DAYS_PER_WAGE_CYCLE == 0:
			if sim.debt_weeks > 0:
				weeks_short += 1
			else:
				weeks_paid += 1
		if sim.starving:
			starve_days += 1
		if d % 7 == 0 or sim.debt_weeks > 0 or sim.starving:
			print("    第 %2d 天：%s" % [d, sim.debug_line()])
	print("    42 天结果：%s" % sim.debug_line())
	print("    足额发薪 %d 次 / 欠薪 %d 次，断粮 %d 天，最低钱袋 %d，升档在第 %d 天" % [
		weeks_paid, weeks_short, starve_days, min_denars, upgraded_on])
	_ok(starve_days == 0, "记得补给就不断粮（跑 42 天断了 %d 天）" % starve_days)
	_ok(weeks_short == 0, "按这条收支曲线不断薪（欠薪 %d 次）" % weeks_short)
	_ok(min_denars >= 0, "钱袋不会变成负数（最低 %d）" % min_denars)
	_ok(upgraded_on == 15, "第 15 天成功升档（钱够）")
	_ok(sim.tier == 1 and sim.wage() > rules.weekly_wage(sim.troops(), 0, sim.renown),
		"升档后周薪高于同兵力的档0（越强越贵）")
	_ok(sim.troops() >= GameState.PLAYER_START_TROOPS, "有粮有钱时不掉兵（当前 %d）" % sim.troops())

	print("")
	pp.free()
	sp.free()

	if _fails.is_empty():
		print("PASS：经济定式全部正常（%d 项断言）" % _total)
		quit(0)
	else:
		print("FAIL：%d/%d 项断言未通过 —— %s" % [_fails.size(), _total, "; ".join(_fails)])
		quit(1)

## 小工具：撤退士气代价（让断言行读起来是「输入 → 输出」）
func _retreat(ally_dead: int, enemy_dead: int, ally_total: int) -> int:
	return EncounterRules.create().retreat_morale_penalty(ally_dead, enemy_dead, ally_total)