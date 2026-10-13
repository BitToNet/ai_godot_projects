## =============================================================================
##  CampaignState —— 战役层的可变状态（钱袋 / 补给 / 士气 / 声望 / 兵员档次）
##
##  为什么单独一个类：第四轮之前这些量一个都不存在，钱只是「战利品数字」，
##  打完就丢了。经济要成立，必须有一份**跨天持续、能被存档序列化**的状态。
##
##  与 GameState 的分工：
##   · GameState   = 开局常量 + 命名兜底（静态方法，无状态）
##   · CampaignState（本文件）= 一局游戏里会变的那部分
##
##  结算的触发点是 DayNightCycle.day_changed（每天一次），而不是 _process：
##  换日信号本来就是「一整天过去了」的唯一权威，挂上去以后时间流速、暂停、
##  Boss 战期间的时间锁定全部自动正确，不需要在别处再判一次。
##
##  数值与公式全部来自 EconomyRules（那里逐条标注了参考来源与本地化取舍）。
##
##  本类**不做任何表现**（不弹提示、不播音效、不刷标签），只回过一个 report
##  字典；谁关心谁去连 day_settled / week_settled。这样 headless 自检
##  （tools/economy_check.gd）可以不建世界、不建 UI，直接跑几百天。
## =============================================================================
class_name CampaignState
extends RefCounted

## 任何数值变化（HUD 刷新用）
signal changed
## 一天结束（report 见 _settle_day）
signal day_settled(report: Dictionary)
## 一周结束（发薪，report 见 _settle_week）
signal week_settled(report: Dictionary)

var rules: EconomyRules
var player: PlayerParty          ## 只读它的 troop_count / refresh_label()

var denars: int = GameState.START_DENARS
var supplies: int = GameState.START_SUPPLIES
var morale: int = GameState.START_MORALE
var renown: int = GameState.START_RENOWN
var tier: int = GameState.START_TIER       ## 兵员档次 0/1/2（EconomyRules.level_of_tier）
var debt_weeks: int = 0                    ## 连续欠薪周数
var day: int = 1
var starving: bool = false                 ## 昨天是否断粮（报告用）

func setup(p_rules: EconomyRules, p_player: PlayerParty) -> void:
	rules = p_rules
	player = p_player
	morale = rules.morale_of(troops(), tier, renown, supplies, debt_weeks)

# ------------------------------------------------------------------ 查询
func troops() -> int:
	return player.troop_count if player != null else 0

func capacity() -> int:
	return rules.party_capacity(renown)

func free_capacity() -> int:
	return maxi(0, capacity() - troops())

func wage() -> int:
	return rules.weekly_wage(troops(), tier, renown)

## 战斗强度：兵力 × 兵员档次倍率。给 Boss 战当玩家侧的强度，
## 也让「升档」有实际回报（否则它只是让工资涨、没有任何收益）。
func combat_power() -> int:
	return int(float(troops()) * rules.combat_multiplier(tier))

## Boss 战里的玩家血量 = 基准 × 强度 / 开局兵力。
## 除以开局兵力是刻意的：开局（37 人、档 0）时倍率正好是 1.0，
## 所以第四轮不会改变「开局第一战」的难度，只让变强之后的战斗跟着变强。
func combat_hp(base: float) -> float:
	return base * float(combat_power()) / float(maxi(GameState.PLAYER_START_TROOPS, 1))

func can_upgrade() -> bool:
	return tier < rules.max_tier() and denars >= rules.upgrade_cost(tier)

## 一行摘要（自检脚本 / 调试打印用）。货物只在不为空时追加，
## 免得把「没在做买卖」时的这行字撑长。
func debug_line() -> String:
	var s := "第%d天 金%d 粮%d 士气%d 声望%d 档次%s 兵力%d/%d 周薪%d 欠薪%d周" % [
		day, denars, supplies, morale, renown, rules.tier_name(tier),
		troops(), capacity(), wage(), debt_weeks]
	if goods_total() > 0:
		s += " 货物%d件" % goods_total()
	return s

# ------------------------------------------------------------------ 收支
func spend(amount: int) -> bool:
	if amount <= 0:
		return true
	if denars < amount:
		return false
	denars -= amount
	changed.emit()
	return true

func earn(amount: int) -> void:
	if amount <= 0:
		return
	denars += amount
	changed.emit()

## 战利品入账：战斗胜利后由 EncounterSystem 调用。
## 参考 01 §2.9 party_calculate_loot：战利品是**按敌方兵力程序化推导**的
## （原文里普通兵背包根本不加载，所以战利品不可能「读敌人身上的装备」）。
func add_spoils(amount: int, word: String = "缴获") -> void:
	if amount <= 0:
		return
	denars += amount
	changed.emit()

## 声望（本地化：原文用「领主关系/影响力」，本工程只有一支玩家部队，
## 所以把「打赢 + 兵力规模」折算成声望，供编制上限与军费折扣使用）
func add_renown(amount: int) -> void:
	if amount <= 0:
		return
	renown += amount
	changed.emit()

## 花钱补兵：返回实际补到的人数（受编制上限与钱双重钳制）
func recruit(count: int, cost_per_man: int) -> int:
	var afford := denars / maxi(cost_per_man, 1)
	var n := mini(count, mini(free_capacity(), afford))
	if n <= 0:
		return 0
	denars -= n * cost_per_man
	player.troop_count += n
	player.refresh_label()
	_sync_label()
	changed.emit()
	return n

## 士兵减员（战斗损失 / 逃兵）。floor 与战斗结算保持一致（5 人起见底）
func lose_troops(count: int) -> int:
	if count <= 0:
		return 0
	var before := troops()
	player.troop_count = maxi(5, before - count)
	player.refresh_label()
	_sync_label()
	changed.emit()
	return before - troops()

## 领回士兵（从驻军取人，不花钱，只受编制余位限制）。
## 与 recruit 的分工：recruit 是「在定居点招新兵」（花钱 + 受志愿者池限制），
## 这里是把存在城里的老兵领回来 —— 所以免费，但照样不能超编。
func take_troops(count: int) -> int:
	if count <= 0 or player == null:
		return 0
	var n := mini(count, free_capacity())
	if n <= 0:
		return 0
	player.troop_count += n
	player.refresh_label()
	_sync_label()
	changed.emit()
	return n

# ------------------------------------------------------------------ 货物（第四轮：贸易）
## 货物 id → 件数。原文货物住在定居点的 item slot 里，玩家侧是同一套物品表；
## 本工程没有物品系统，所以玩家侧只留一个 id→件数 的小背包（存档也好序列化）。
var goods: Dictionary = {}

func goods_of(gid: int) -> int:
	return int(goods.get(gid, 0))

func goods_total() -> int:
	var n := 0
	for k in goods.keys():
		n += int(goods[k])
	return n

func add_goods(gid: int, count: int) -> void:
	if count <= 0:
		return
	goods[gid] = goods_of(gid) + count
	changed.emit()

## 取走货物：返回实际取走件数（不够就全拿走）
func take_goods(gid: int, count: int) -> int:
	if count <= 0:
		return 0
	var have := goods_of(gid)
	var n := mini(count, have)
	if n <= 0:
		return 0
	if have - n <= 0:
		goods.erase(gid)
	else:
		goods[gid] = have - n
	changed.emit()
	return n

## 补给入账（买补给 / 将来的缴获口粮都走这里）
func add_supplies(count: int) -> int:
	if count <= 0:
		return 0
	supplies += count
	changed.emit()
	return count

func upgrade_tier() -> bool:
	if tier >= rules.max_tier():
		return false
	var cost := rules.upgrade_cost(tier)
	if not spend(cost):
		return false
	tier += 1
	changed.emit()
	return true

## 直接改士气（撤退代价 / 战斗结果等事件用）。
##
## ⚠ 先把**读到的**士气钳一次，再加 delta、再钳一次 —— 02-玩法设计 §3.4.1 的设计
## 含义【实证】：原版 change_player_party_morale 就是这么写的，防的正是「存档或别的
## 脚本塞进一个越界值（比如 300）」：只钳结果的话 300 − 5 → 295 → 钳到 100，
## 那个坏值会一直**粘在 100** 上再也降不下来。读档侧的同类防御见 SaveGame._clamp_warn。
func add_morale(delta: int) -> void:
	if delta == 0:
		return
	morale = clampi(clampi(morale, 0, 100) + delta, 0, 100)
	changed.emit()

# ------------------------------------------------------------------ 每日 / 每周结算
## 接 DayNightCycle.day_changed
func on_day_changed(new_day: int) -> void:
	day = new_day
	var report := _settle_day()
	day_settled.emit(report)

func _settle_day() -> Dictionary:
	var t := troops()
	# 1) 补给消耗（本地化：原文 consume_food 的调用量【未解】，这里每 10 兵 1 件/天）
	var need := rules.supply_per_day(t)
	var eaten := mini(need, supplies)
	supplies -= eaten
	starving = supplies <= 0 and need > 0

	# 2) 每周发薪（照搬 01 §2.4 的周薪口径；本工程 1 天 = 2 分钟，7 天结一次）
	var week := {}
	if day % GameState.DAYS_PER_WAGE_CYCLE == 0:
		week = _settle_week()

	# 3) 士气（照搬 01 §3.3 的模型）
	morale = rules.morale_of(t, tier, renown, supplies, debt_weeks)

	# 4) 逃兵（本地化新增：原文只有 morale，没有逃兵规则）
	var left := rules.deserters(t, morale)
	var deserted := 0
	if left > 0:
		deserted = lose_troops(left)
		morale = rules.morale_of(troops(), tier, renown, supplies, debt_weeks)

	changed.emit()
	var report := {
		"day": day,
		"troops": troops(),
		"need": need,
		"eaten": eaten,
		"supplies": supplies,
		"starving": starving,
		"morale": morale,
		"deserted": deserted,
		"denars": denars,
		"week": week,
	}
	return report

func _settle_week() -> Dictionary:
	var w := wage()
	if w <= 0:
		return {}
	var paid := 0
	if denars >= w:
		paid = w
		denars -= w
		debt_weeks = 0
	else:
		paid = denars
		denars = 0
		debt_weeks += 1
	var report := {"wage": w, "paid": paid, "short": maxi(0, w - paid), "debt_weeks": debt_weeks}
	week_settled.emit(report)
	return report

func _sync_label() -> void:
	# 走 PartyBase.refresh_label() 而不是自己拼字符串：那里已经判了 label == null，
	# 兵种名字的格式也只有一份（headless 自检里 player 没有 label，也不会炸）。
	if player != null:
		player.refresh_label()