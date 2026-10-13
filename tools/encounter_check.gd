## =============================================================================
##  encounter_check —— 遭遇系统回归（**不参与游戏运行**，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/encounter_check.gd
##
##  为什么需要它：第四轮 4c 把遭遇框从「两个写死的按钮」改成**数据驱动的选项表**
##  （EncounterSystem.options()），这张表从此是玩法的一部分 —— 它同时取决于
##  「敌人是哪种部队」「你的钱袋」「你的战力」，而这三样在门禁的 900 帧主场景里
##  一个都变不了。所以必须有一个不建世界、不建 UI 的入口把每条分支跑一遍。
##
##  断言覆盖：
##    1. 定价公式：买路钱 / 索要买路钱 / 战力门槛 / 声望折扣（纯函数逐项对账）
##    2. 选项表：强盗 / 商队 / 领主 × 有钱 / 没钱 / 兵力足 / 兵力不足 → 谁亮谁灰、灰的理由
##    3. 各选项效果：攻击只发信号、撤退掉队 + 士气 + 冷却 + 退避、买路扣钱、索要进账 + 声望
##    4. **不合法动作一律静默拒绝**（面板不是权威：自检 / 作弊 / 过期菜单都送得进来）
##    5. 时间锁：开框锁住、任何一条路走完之后必须解开
##       （旧 bug：撤退分支只 evaluate 不清 time_lock → 世界时间永久冻住）
##    6. 台账：每次解决都留下 last_ledger（action / 双方伤亡 / 收支），供日志与后续系统使用
##
##  参考：G:\warband_docs —— 原文档里「遭遇面板有哪些选项」是【未解】，所以定价、声望折扣、
##  「领主不收买路钱」这些是**本地化设计决策**（见 EncounterRules.gd 注释与 ROADMAP §10.8）。
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

# ---------------------------------------------------------------- 假世界
class Fake:
	var cfg: MapConfig
	var data: MapData
	var economy: EconomyRules
	var campaign: CampaignState
	var player: StubPlayer
	var time: TimeFlowController
	var hud: StubHud
	var ctx: WorldContext
	var sys: EncounterSystem

## 玩家替身：假世界没有导航网格（data.path_fine == null），PlayerParty.set_destination()
## 会去摸导航格 → 必然失败。覆盖它，只记下目标点。
## （4b-1 是在假世界里直接置 moving = true 绕开；4c 起撤退 / 买路 / 索要都会调 order_move
##  把玩家推开，所以这里必须有一个能安全接住「下令行军」的替身。）
class StubPlayer extends PlayerParty:
	var goal: Vector2 = Vector2.ZERO
	var orders: int = 0
	func set_destination(p: Vector2) -> void:
		goal = p
		has_target = true
		moving = true
		orders += 1

## HUD 替身：不建任何控件，只记「谁开过框、框里写了什么、给了哪些条目、弹过什么条」。
## 签名必须与 HUD 完全一致（GDScript 的覆盖会核对签名）。
class StubHud extends HUD:
	var titles: Array[String] = []
	var infos: Array[String] = []
	var entries: Array = []
	var toasts: Array[String] = []
	var open_flag: bool = false
	func show_encounter(title: String, info: String, _color: Color, e: Array = []) -> void:
		titles.append(title)
		infos.append(info)
		entries = e
		open_flag = true
	func hide_encounter() -> void:
		open_flag = false
	func is_encounter_open() -> bool:
		return open_flag
	func is_any_dialog_open() -> bool:
		return open_flag
	func show_toast(text: String, _dur: float = 5.0) -> void:
		toasts.append(text)

func _make_world(troops: int = 37, denars: int = 400) -> Fake:
	var f := Fake.new()
	f.cfg = MapConfig.new()
	f.data = MapData.new()
	f.data.cfg = f.cfg
	f.economy = EconomyRules.create()
	f.player = StubPlayer.new()
	f.player.troop_count = troops
	f.campaign = CampaignState.new()
	f.campaign.setup(f.economy, f.player)
	f.campaign.denars = denars               # 开局 400，这里方便单独压到「钱不够」
	f.time = TimeFlowController.new()
	f.time.player = f.player
	f.hud = StubHud.new()
	f.ctx = WorldContext.new()
	f.ctx.cfg = f.cfg
	f.ctx.data = f.data
	f.ctx.economy = f.economy
	f.ctx.campaign = f.campaign
	f.ctx.player = f.player
	f.ctx.time = f.time
	f.ctx.hud = f.hud
	f.ctx.rules = EncounterRules.create()
	f.sys = EncounterSystem.new()
	f.sys.ctx = f.ctx
	return f

## 造一支敌军。挂到树根上（与真实世界一致）：打赢分支会 queue_free() 它，
## 不入树的孤儿节点在 quit 之前不一定被真正释放（会留下 resources still in use 的 ERROR）。
func _party(f: Fake, kind: int, nm: String, troops: int, pos: Vector2 = Vector2(200, 200)) -> AIParty:
	var p := AIParty.new()
	p.kind = kind
	p.party_name = nm
	p.troop_count = troops
	p.faction_id = -1                        # 无阵营：GameState.faction_name 走兜底文案
	p.boss_title = "头目"
	p.position = Vector3(pos.x, 0.0, pos.y)
	get_root().add_child(p)
	f.ctx.parties.append(p)
	return p

func _dispose(f: Fake) -> void:
	for p in f.ctx.parties:
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			p.free()
	f.ctx.parties.clear()
	f.player.free()
	f.hud.free()
	f.sys = null
	f.ctx = null

# ---------------------------------------------------------------- 主流程
func _run() -> void:
	print("[遭遇] 定式自检（不跑地图生成、不建 UI）")
	_check_pricing()
	_check_options()
	_check_attack()
	_check_retreat()
	_check_bribe()
	_check_demand()
	_check_reject()
	_check_trigger()
	await _check_battle()

	print("")
	if _fails.is_empty():
		print("PASS：遭遇系统定式全部正常（%d 项断言）" % _total)
		quit(0)
	else:
		print("FAIL：%d/%d 项断言未通过 —— %s" % [_fails.size(), _total, "; ".join(_fails)])
		quit(1)

# ---------------------------------------------------------------- 1. 定价公式
func _check_pricing() -> void:
	print("\n-- 1. 定价公式（本地化设计决策，见 EncounterRules.gd / ROADMAP §10.8）--")
	var r := EncounterRules.create()
	_ok(r.toll_per_man("bandit") == 3 and r.toll_per_man("caravan") == 5,
		"每人买路钱：强盗 3 金 / 商队 5 金")
	_ok(r.toll_per_man("lord") == 0 and not r.can_toll("lord"),
		"领主没有价码（toll_per_man = 0）")
	_ok(r.can_toll("bandit") and r.can_toll("caravan"), "强盗与商队都收买路钱")

	_ok(r.bribe_price("bandit", 30, 0) == 90, "无声望折扣时 30 人强盗要 90 金")
	_ok(r.bribe_price("bandit", 30, 120) == 84, "声望 120（折扣 6%）后 84 金")
	_ok(r.bribe_price("bandit", 30, 2000) == 63, "折扣封顶 30%：90 x 70/100 = 63")
	_ok(r.renown_discount(0) == 0 and r.renown_discount(200) == 10 and r.renown_discount(99999) == 30,
		"声望折扣 = 声望/20，上限 30%")
	_ok(r.bribe_price("bandit", 1, 0) == 10, "买路钱有 10 金下限（不值得为三瓜两枣谈一次）")
	_ok(r.bribe_price("caravan", 30, 120) == 141, "商队 30 人：150 金打完折 141 金")
	_ok(r.bribe_price("lord", 30, 0) == 0, "领主没有价码（配合灰行用）")

	_ok(r.enemy_power("bandit", 30) == 24 and r.enemy_power("caravan", 30) == 30
		and r.enemy_power("lord", 30) == 42,
		"敌方战力当量：强盗 24 / 商队 30 / 领主 42（人数 x 0.8 / 1.0 / 1.4）")
	_ok(r.demand_need("bandit", 30) == 36, "索要买路钱门槛 = ceil(1.5 x 24) = 36")
	_ok(r.demand_gain("bandit", 30) == 108, "索要到的钱 = 90 x 1.2 = 108")
	_ok(r.demand_gain("bandit", 30) > r.bribe_price("bandit", 30, 0),
		"收的比交的多一点（你是主动方）")
	_ok(r.demand_renown(30) == 1 and r.demand_renown(200) == 10,
		"索要成功给声望（兵力/20，至少 1）")
	_ok(r.demand_gain("lord", 30) == 0 and r.demand_need("lord", 30) == 63,
		"领主既不能买路也不能被讹（门槛 63 只是为了让灰行有数字可写）")
	print("     开局 37 战力：小股强盗（22 人，门槛 %d）唬得住，大队（78 人，门槛 %d）唬不住" % [
		r.demand_need("bandit", 22), r.demand_need("bandit", 78)])

# ---------------------------------------------------------------- 2. 选项表
func _check_options() -> void:
	print("\n-- 2. 选项表：谁亮谁灰、灰的理由 --")
	var f := _make_world()
	var bandit := _party(f, AIParty.Kind.BANDIT, "响马", 30)
	f.sys.open(bandit)
	var rows := f.sys.options()
	_ok(rows.size() == 4, "遭遇菜单四行：%s" % [_ids(rows)])
	_ok(_ids(rows) == ["attack", "bribe", "demand", "retreat"],
		"顺序 = 动手 → 花钱 → 收钱 → 走人（与进城菜单「离开放最后」一致）")
	_ok(_enabled(rows) == [true, true, true, true],
		"开局（37 战力 / 400 金）：四行全亮 —— 打得起、买得起、唬得住")
	_ok(String(_find(rows, "attack").get("hint")).contains("预计掉队 3 人"),
		"攻击行写清预计损失：%s" % _find(rows, "attack").get("hint"))
	_ok(String(_find(rows, "bribe").get("label")).contains("84 金"),
		"买路行把价码写在按钮上：%s" % _find(rows, "bribe").get("label"))
	_ok(String(_find(rows, "bribe").get("hint")).contains("现有 400 金"),
		"买路行写出钱袋余额：%s" % _find(rows, "bribe").get("hint"))
	_ok(String(_find(rows, "demand").get("hint")).contains("需要 ≥ 36"),
		"索要行把门槛写清（差多少一眼看得见）：%s" % _find(rows, "demand").get("hint"))
	_ok(_has_all_keys(rows), "每行都齐四项 {id,label,enabled,hint}（面板少画一项就白屏）")

	# 换成最大号强盗（78 人）：买路钱涨上去，索要门槛超过开局战力
	var big := _party(f, AIParty.Kind.BANDIT, "大盗", 78)
	f.sys.open(big)
	var rows2 := f.sys.options()
	_ok(_enabled(rows2) == [true, true, false, true],
		"78 人强盗：索要买路钱灰掉（战力 37 < 门槛 %d）" % f.ctx.rules.demand_need("bandit", 78))
	_ok(String(_find(rows2, "bribe").get("label")).contains("219 金"),
		"买路钱随人数线性上涨：78 x 3 x 94/100 = 219 金")
	_ok(String(_find(rows2, "demand").get("hint")).contains("你的战力 37"),
		"灰行说清「你现在多少」：%s" % _find(rows2, "demand").get("hint"))

	f.campaign.denars = 50
	var rows3 := f.sys.options()
	_ok(not bool(_find(rows3, "bribe").get("enabled")),
		"钱袋 50 金 < 219 金：买路灰掉")
	_ok(String(_find(rows3, "bribe").get("hint")).contains("现有 50 金"),
		"灰行给出余额：%s" % _find(rows3, "bribe").get("hint"))
	_ok(bool(_find(rows3, "attack").get("enabled")) and bool(_find(rows3, "retreat").get("enabled")),
		"没钱照样能打能走（穷不是死路）")

	# 商队：单价高、护卫精悍 → 买得起但唬不住
	var cara := _party(f, AIParty.Kind.CARAVAN, "商队", 30)
	f.sys.open(cara)
	var rows4 := f.sys.options()
	_ok(_ids(rows4) == _ids(rows), "三种部队的选项集合一致（差别在可用性与价码）")
	_ok(_enabled(rows4) == [true, false, false, true],
		"商队 30 人：买路 141 金（> 50）与索要（门槛 45 > 37）都灰")

	# 领主：两样都不吃，而且必须说明理由
	var lord := _party(f, AIParty.Kind.LORD, "伯爵", 40)
	f.sys.open(lord)
	var rows5 := f.sys.options()
	_ok(_enabled(rows5) == [true, false, false, true], "领主：只有攻击与撤退可点")
	_ok(String(_find(rows5, "bribe").get("hint")).contains("领主不收买路钱"),
		"灰行说清为什么：%s" % _find(rows5, "bribe").get("hint"))
	_ok(String(_find(rows5, "demand").get("hint")).contains("宁死不交"),
		"另一条灰行同样是理由不是空白：%s" % _find(rows5, "demand").get("hint"))
	_ok(String(_find(rows5, "bribe").get("label")) == "花钱买路",
		"领主那行不写价码（没价码可写，写了就是骗人）")

	f.sys.current = null
	_ok(f.sys.options().is_empty(), "没有对话时选项表为空（面板拿到空表也不会画东西）")
	_dispose(f)

# ---------------------------------------------------------------- 3. 攻击
func _check_attack() -> void:
	print("\n-- 3. 攻击：只发信号，不自己记账 --")
	var f := _make_world()
	var p := _party(f, AIParty.Kind.BANDIT, "响马", 30)
	var fired: Array[AIParty] = []
	f.sys.attack_requested.connect(func(a: AIParty): fired.append(a))
	f.sys.open(p)
	_ok(f.time.time_lock, "开框即锁住世界时间（对话框期间空格不生效）")
	_ok(f.hud.open_flag and f.hud.titles.size() == 1 and f.hud.titles[0] == "遭遇 响马",
		"对话框标题带上了部队名：%s" % [f.hud.titles])
	_ok(f.hud.infos[0].contains("强盗团伙") and f.hud.infos[0].contains("兵力：30 人"),
		"说明行写清敌人类别与兵力：%s" % f.hud.infos[0].replace("\n", " / "))
	_ok(f.hud.entries.size() == 4, "开框时把选项表交给了 HUD（面板照数据画，不自己判断）")

	f.sys.resolve("attack")
	_ok(fired.size() == 1 and fired[0] == p, "attack_requested 带上了那支部队")
	_ok(f.sys.current == null, "攻击后清空 current")
	_ok(not f.hud.open_flag, "攻击后对话框隐藏")
	_ok(f.campaign.denars == 400 and f.campaign.troops() == 37,
		"攻击本身不动钱也不动兵（结算在战斗返回之后）")
	_ok(f.time.time_lock,
		"攻击时**不**解锁时间：BattleLauncher.start 会立刻再锁一次（避免一帧的世界时间流动）")
	_dispose(f)

# ---------------------------------------------------------------- 4. 撤退
func _check_retreat() -> void:
	print("\n-- 4. 撤退：掉队 + 士气 + 冷却 + 退避，并且**解开时间锁** --")
	var f := _make_world()
	var p := _party(f, AIParty.Kind.BANDIT, "响马", 30)
	f.sys.open(p)
	var r := f.ctx.rules
	var dead := int(30 * r.loss_rate("bandit"))
	var enemy_dead := int(30 * r.loss_rate("bandit"))
	var pen := r.retreat_morale_penalty(dead, enemy_dead, 37)
	var before := f.campaign.denars
	var m0 := f.campaign.morale              # 开局士气 40（由补给 / 编制推出，不写死 50）
	f.sys.resolve("retreat")
	_ok(f.campaign.troops() == 37 - dead,
		"掉队 %d 人（37 → %d，按 EncounterRules.loss_rate）" % [dead, f.campaign.troops()])
	_ok(f.campaign.morale == m0 - pen,
		"士气按 01 §5.8 的复合式下降 %d（%d → %d）" % [pen, m0, f.campaign.morale])
	_ok(f.campaign.denars == before, "撤退不花钱（代价是人与士气）")
	_ok(f.sys.cooldowns.has(p.get_instance_id()), "撤退后这支部队进入冷却")
	_ok(is_equal_approx(float(f.sys.cooldowns[p.get_instance_id()]), r.retreat_cooldown),
		"冷却时长 = %.0f 秒（它追不上来）" % r.retreat_cooldown)
	_ok(f.player.orders == 1, "撤退会把玩家往反方向推开（重新下达一次行军令）")
	_ok(not f.time.time_lock,
		"撤退后时间锁必须解开 —— 旧 bug：只 evaluate 不清 time_lock，世界时间永久冻住")
	_ok(f.time.state == TimeFlowController.State.MARCHING,
		"解锁后按「正在行军」重新裁决时间状态（行军途中时间照常流动）")
	_ok(f.sys.current == null and not f.hud.open_flag, "撤退后遭遇结束、对话框隐藏")
	_ok(String(f.sys.last_ledger.get("action")) == "retreat", "台账 action = retreat")
	_ok(int(f.sys.last_ledger.get("ally_dead")) == dead
		and int(f.sys.last_ledger.get("enemy_dead")) == enemy_dead,
		"台账记下双方伤亡 %d / %d" % [dead, enemy_dead])
	_ok(int(f.sys.last_ledger.get("ally_start")) == 37
		and int(f.sys.last_ledger.get("ally_left")) == 37 - dead,
		"台账里开战前 37 人、撤完 %d 人（扣兵之后反推出来的）" % (37 - dead))
	_ok(f.hud.toasts.size() == 1 and f.hud.toasts[0].contains("避开"),
		"给了提示条：%s" % [f.hud.toasts])

	# 打光到只剩 5 人时的下限（lose_troops 有 floor，台账不能因此算错）
	var g := _make_world(6)
	var q := _party(g, AIParty.Kind.LORD, "伯爵卫队", 90)
	g.sys.open(q)
	var dead2 := int(90 * g.ctx.rules.loss_rate("lord"))
	g.sys.resolve("retreat")
	_ok(g.campaign.troops() == 5, "6 人部队按估算该掉 %d 人 → 触到 5 人下限（不会掉光）" % dead2)
	_ok(int(g.sys.last_ledger.get("ally_dead")) == 1,
		"台账记的是**真实**减员 1 人（不是估算的 %d 人）" % dead2)
	_dispose(g)
	_dispose(f)

# ---------------------------------------------------------------- 5. 买路
func _check_bribe() -> void:
	print("\n-- 5. 花钱买路：扣钱换平安 --")
	var f := _make_world()
	var p := _party(f, AIParty.Kind.CARAVAN, "商队", 30)
	f.sys.open(p)
	var price := f.ctx.rules.bribe_price("caravan", 30, f.campaign.renown)
	var m0 := f.campaign.morale
	f.sys.resolve("bribe")
	_ok(f.campaign.denars == 400 - price,
		"扣了 %d 金（400 → %d）" % [price, f.campaign.denars])
	_ok(f.campaign.troops() == 37, "买路不掉一兵一卒（这正是它存在的意义）")
	_ok(f.campaign.morale == m0, "买路不影响士气（仍是 %d）" % m0)
	_ok(int(f.sys.last_ledger.get("gold_delta")) == -price, "台账记下支出 −%d" % price)
	_ok(int(f.sys.last_ledger.get("ally_dead")) == 0, "台账里我方零伤亡")
	_ok(f.sys.cooldowns.has(p.get_instance_id()), "买路后同样进冷却（它去别处再拦人）")
	_ok(not f.time.time_lock, "买路后时间解锁")
	_ok(f.hud.toasts.size() == 1 and f.hud.toasts[0].contains("买路钱"),
		"提示条写明付了多少：%s" % [f.hud.toasts])
	_ok(p.troop_count == 30 and f.ctx.parties.has(p), "对方还在图上（买的是这一段的平安）")

	# 声望越高越便宜：同一支商队，声望 500 时要价更低
	var g := _make_world()
	g.campaign.renown = 500
	var q := _party(g, AIParty.Kind.CARAVAN, "商队", 30)
	g.sys.open(q)
	var cheap := g.ctx.rules.bribe_price("caravan", 30, g.campaign.renown)
	_ok(cheap < price, "声望 500（折扣 25%%）后只要 %d 金 < %d 金" % [cheap, price])
	_dispose(g)
	_dispose(f)

# ---------------------------------------------------------------- 6. 索要买路钱
func _check_demand() -> void:
	print("\n-- 6. 索要买路钱：兵力压倒对方才吃得到 --")
	var f := _make_world()
	var p := _party(f, AIParty.Kind.BANDIT, "响马", 30)
	f.sys.open(p)
	var r := f.ctx.rules
	var gain := r.demand_gain("bandit", 30)
	var ren := r.demand_renown(30)
	var need := r.demand_need("bandit", 30)
	var m0 := f.campaign.morale
	_ok(f.campaign.combat_power() >= need,
		"开局战力 %d ≥ 门槛 %d（小股强盗唬得住）" % [f.campaign.combat_power(), need])
	f.sys.resolve("demand")
	_ok(f.campaign.denars == 400 + gain, "白拿 %d 金（400 → %d）" % [gain, f.campaign.denars])
	_ok(f.campaign.renown == 120 + ren, "声望 +%d（120 → %d）" % [ren, f.campaign.renown])
	_ok(f.campaign.troops() == 37 and f.campaign.morale == m0, "不动兵也不掉士气（%d）" % m0)
	_ok(int(f.sys.last_ledger.get("gold_delta")) == gain
		and int(f.sys.last_ledger.get("renown_delta")) == ren,
		"台账记下进账 %d 与声望 %d" % [gain, ren])
	_ok(f.sys.current == null and not f.time.time_lock and not f.hud.open_flag,
		"解决后遭遇结束、对话框隐藏、时间解锁")
	_ok(f.hud.toasts.size() == 1 and f.hud.toasts[0].contains("索要买路钱"),
		"提示条写明讹到了多少：%s" % [f.hud.toasts])

	# 兵越多越唬得住：60 人时同一支强盗的门槛反而更容易过
	var g := _make_world(120)
	var q := _party(g, AIParty.Kind.BANDIT, "大盗", 78)
	g.sys.open(q)
	_ok(g.campaign.combat_power() >= g.ctx.rules.demand_need("bandit", 78),
		"120 人（战力 %d）压得住 78 人强盗（门槛 %d）—— 4a 的编制成长在这里兑现" % [
			g.campaign.combat_power(), g.ctx.rules.demand_need("bandit", 78)])
	_dispose(g)
	_dispose(f)

# ---------------------------------------------------------------- 7. 静默拒绝
func _check_reject() -> void:
	print("\n-- 7. 不合法动作一律静默拒绝（面板不是权威）--")
	# 7a 钱不够
	var f := _make_world(37, 50)
	var p := _party(f, AIParty.Kind.BANDIT, "响马", 30)
	var acts: Array[String] = []
	f.sys.attack_requested.connect(func(_a: AIParty): acts.append("attack"))
	f.sys.open(p)
	var price := f.ctx.rules.bribe_price("bandit", 30, f.campaign.renown)
	f.sys.resolve("bribe")
	_ok(f.sys.current == p, "钱不够（50 < %d）时买路被拒绝：current 不动" % price)
	_ok(f.hud.open_flag, "面板还开着，玩家可以改选别的")
	_ok(f.campaign.denars == 50, "钱没动")
	_ok(f.time.time_lock, "被拒绝时时间仍锁着（否则对话框开着而世界在跑）")
	_ok(acts.is_empty(), "被拒绝不会偷偷开战")
	f.sys.resolve("retreat")
	_ok(f.sys.current == null and not f.time.time_lock, "拒绝之后仍然能正常撤退（不会卡死）")
	_dispose(f)

	# 7b 威慑不足
	var g := _make_world()
	var big := _party(g, AIParty.Kind.BANDIT, "大盗", 78)
	var acts2: Array[String] = []
	g.sys.attack_requested.connect(func(_a: AIParty): acts2.append("attack"))
	g.sys.open(big)
	g.sys.resolve("demand")
	_ok(g.sys.current == big and g.campaign.denars == 400 and acts2.is_empty(),
		"战力 37 < 门槛 %d：索要被拒绝（钱没多、也没被拖进战斗）" % g.ctx.rules.demand_need("bandit", 78))
	g.sys.resolve("retreat")
	_ok(g.sys.current == null and g.sys.cooldowns.has(big.get_instance_id()),
		"拒绝之后照样能撤退，且撤退会照常登记冷却")
	_dispose(g)

	# 7c 领主两样都不吃
	var h := _make_world()
	var lord := _party(h, AIParty.Kind.LORD, "伯爵", 40)
	h.sys.open(lord)
	h.sys.resolve("bribe")
	_ok(h.sys.current == lord and h.campaign.denars == 400, "领主不吃买路钱：拒绝且不扣钱")
	h.sys.resolve("demand")
	_ok(h.sys.current == lord and h.campaign.denars == 400, "领主不吃讹诈：拒绝且不加钱")
	_dispose(h)

	# 7d 未知动作按撤退处理（对话框只有 Esc → retreat 这一个兜底来源）
	var k := _make_world()
	var m := _party(k, AIParty.Kind.BANDIT, "响马", 30)
	k.sys.open(m)
	k.sys.resolve("这不是一个选项")
	_ok(k.sys.current == null and not k.time.time_lock,
		"未知动作走撤退分支（而不是把玩家卡在锁着时间的对话框里）")
	_ok(String(k.sys.last_ledger.get("action")) == "retreat", "台账同样记 retreat")
	_dispose(k)

	# 7e 没有对话时 resolve 不该崩（战斗结算之后可能又被调一次）
	var n := _make_world()
	n.time.lock()
	n.sys.resolve("attack")
	_ok(n.sys.current == null and not n.time.time_lock, "current 为空时 resolve 只解锁，不崩")
	_dispose(n)

# ---------------------------------------------------------------- 8. 触发与冷却
func _check_trigger() -> void:
	print("\n-- 8. 遭遇检测 / 冷却 / 开关 --")
	var f := _make_world()
	var reach := f.cfg.encounter_distance + f.ctx.rules.trigger_margin
	f.player.position = Vector3(100.0, 0.0, 100.0)
	var p := _party(f, AIParty.Kind.BANDIT, "响马", 30, Vector2(100.0 + reach - 1.0, 100.0))
	f.sys.check(1.0 / 60.0)
	_ok(f.sys.current == p, "贴到触发距离内（%.0f < %.0f）自动开框" % [reach - 1.0, reach])
	_ok(f.time.time_lock and f.hud.open_flag, "自动开框同样锁时间 + 显示对话框")
	_ok(f.hud.entries.size() == 4, "自动开框也带上了选项表（面板与手动开框同源）")
	f.sys.resolve("retreat")

	f.player.position = Vector3(100.0, 0.0, 100.0)     # 撤退把玩家推开了，挪回来试冷却
	f.sys.check(1.0)
	_ok(f.sys.current == null, "冷却期内不会被同一支部队再次缠上")
	_ok(not f.time.time_lock, "冷却期内没有开框，时间也不该被锁")
	f.sys.cooldowns.clear()
	f.sys.check(1.0 / 60.0)
	_ok(f.sys.current == p, "冷却清掉后又能触发")

	f.sys.resolve("retreat")
	f.sys.enabled = false
	f.sys.cooldowns.clear()
	f.sys.check(1.0 / 60.0)
	_ok(f.sys.current == null, "enabled = false 时完全不检测（截图 / 调试用）")
	f.sys.enabled = true

	# 冷却随时间自然流逝
	f.sys.cooldowns[p.get_instance_id()] = 2.0
	f.sys.check(1.0)
	_ok(float(f.sys.cooldowns.get(p.get_instance_id(), 0.0)) < 1.01, "冷却按 delta 递减")
	f.sys.check(1.5)
	_ok(not f.sys.cooldowns.has(p.get_instance_id()), "冷却归零后自动清掉（字典不会无限长）")
	_dispose(f)

# ---------------------------------------------------------------- 9. 战斗结算
func _check_battle() -> void:
	print("\n-- 9. 战斗结算：打赢 / 打输 / 战斗中途撤出 --")
	# 9a 打赢：战利品 + 声望 + 这支部队从地图上消失
	var f := _make_world()
	var p := _party(f, AIParty.Kind.BANDIT, "响马", 30)
	var spoils := int(30 * f.ctx.rules.loot_rate("bandit") * f.ctx.economy.loot_per_troop)
	f.sys.on_battle_finished("win", p)
	_ok(f.campaign.denars == 400 + spoils,
		"战利品入账 %d 金（30 x 0.85 x %.1f）" % [spoils, f.ctx.economy.loot_per_troop])
	_ok(f.campaign.renown == 123, "声望 +3（兵力/10）")
	_ok(not f.ctx.parties.has(p), "打赢后这支部队从地图上移除")
	_ok(String(f.sys.last_ledger.get("action")) == "win" and int(f.sys.last_ledger.get("enemy_dead")) == 30,
		"台账 action = win、敌方全灭 30 人")
	_ok(f.campaign.troops() == 37 - 3, "我方按损失率掉队 3 人（37 → %d）" % f.campaign.troops())
	_ok(not f.time.time_lock,
		"战斗结算不会把世界时间永久锁死（解锁由 BattleLauncher 在 finished 之前完成）")
	await process_frame                     # 让 queue_free 的那支部队真的被释放
	_dispose(f)

	# 9b 打输：掉兵 + 交赎金 + 一段冷却（假世界没有城镇 → 走「找不到城」的兜底）
	var g := _make_world()
	var q := _party(g, AIParty.Kind.BANDIT, "响马", 30)
	var loss2 := maxi(1, 37 * 2 / 5)
	var toll := 400 / 4
	g.sys.on_battle_finished("lose", q)
	_ok(g.campaign.troops() == 37 - loss2,
		"战败掉兵 %d 人（37 → %d，floor 5 人）" % [loss2, g.campaign.troops()])
	_ok(g.campaign.denars == 400 - toll,
		"战败被拿走四分之一钱（400 → %d）" % g.campaign.denars)
	_ok(g.sys.cooldowns.has(q.get_instance_id()), "战败后有一段时间不能再被它缠上")
	_ok(String(g.sys.last_ledger.get("action")) == "lose"
		and int(g.sys.last_ledger.get("enemy_dead")) == 0,
		"台账 action = lose，敌方伤亡记 0（我们被打散了，没有可信数字，不编）")
	_ok(q.troop_count == 30 and g.ctx.parties.has(q), "战败不会抹掉对方（它还在，下次还想抢你）")
	_dispose(g)

	# 9c 战斗中途撤出：掉队 + 士气（敌方伤亡是**估**出来的，不再假装「双方一样」）
	var h := _make_world()
	var s := _party(h, AIParty.Kind.CARAVAN, "商队", 40)
	var dead3 := int(40 * h.ctx.rules.loss_rate("caravan"))
	var enemy3 := int(40 * h.ctx.rules.loss_rate("caravan"))
	var pen3 := h.ctx.rules.retreat_morale_penalty(dead3, enemy3, 37)
	var m3 := h.campaign.morale
	h.sys.on_battle_finished("escape", s)
	_ok(h.campaign.troops() == 37 - dead3, "战斗中途撤出掉队 %d 人" % dead3)
	_ok(h.campaign.morale == m3 - pen3,
		"士气 −%d（%d → %d，按伤亡比例而非固定值）" % [pen3, m3, h.campaign.morale])
	_ok(String(h.sys.last_ledger.get("action")) == "battle_escape", "台账 action = battle_escape")
	_ok(int(h.sys.last_ledger.get("enemy_dead")) == enemy3,
		"台账里敌方伤亡是**估**出来的 %d（【推断】：单挑表现里没有逐兵伤亡）" % enemy3)
	_ok(h.campaign.renown == 120, "撤退不给声望（白跑一趟）")
	_dispose(h)

# ---------------------------------------------------------------- 小工具
func _find(rows: Array[Dictionary], id: String) -> Dictionary:
	for r in rows:
		if String(r.get("id", "")) == id:
			return r
	return {}

func _ids(rows: Array[Dictionary]) -> Array:
	var out: Array = []
	for r in rows:
		out.append(String(r.get("id", "")))
	return out

func _enabled(rows: Array[Dictionary]) -> Array:
	var out: Array = []
	for r in rows:
		out.append(bool(r.get("enabled", false)))
	return out

func _has_all_keys(rows: Array[Dictionary]) -> bool:
	for r in rows:
		if not (r.has("id") and r.has("label") and r.has("enabled") and r.has("hint")):
			return false
	return true