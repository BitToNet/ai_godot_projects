## =============================================================================
##  EncounterSystem —— 遭遇检测、对话框、冷却与「退避」
##
##  从 Main.gd 搬出：_check_encounters / _open_encounter / _on_encounter_choice /
##  _push_player_away 以及 encounters_enabled / cooldowns / encounter_party 三个字段。
##
##  与 BattleLauncher 的分工（两块互相回调，所以用信号断开环）：
##   · 这里决定「要不要开打」——玩家点攻击时只发 attack_requested，不自己建战斗场景；
##   · 打完之后由 BattleLauncher 发 finished，本系统负责结算落地部分
##     （战利品 / 兵力损失 / 战败回城 / 退避 / 冷却）。
## =============================================================================
class_name EncounterSystem
extends RefCounted

## 玩家在对话框里选了「攻击」：交给 BattleLauncher 开战
signal attack_requested(party: AIParty)

var ctx: WorldContext

var enabled: bool = true            ## 调试 / 截图时可关掉遭遇
var cooldowns: Dictionary = {}      ## instance_id → 剩余冷却秒数
var current: AIParty = null         ## 正在对话的部队（null = 没有对话）

## 最近一次遭遇的伤亡 / 收支台账（自检与日志用）。
## 为什么需要它：原文档的撤退士气公式（01 §5.8 simulate_retreat）直接读
## p_ally_casualties / p_enemy_casualties 两本账；本工程的 Boss 战是「单挑」表现，
## 没有逐兵伤亡，所以这两个数字是**按 EncounterRules.loss_rate(kind) 估算**的
## （记为【推断】）。但至少它被显式记账、可断言、也打得出来 ——
## 之前是每个调用点现凑一个数字传进公式里。
var last_ledger: Dictionary = {}

## 遭遇检测：时间未流动时不调用（见 Main._process）
func check(delta: float) -> void:
	if not enabled or ctx == null:
		return
	for k in cooldowns.keys():
		cooldowns[k] = float(cooldowns[k]) - delta
		if float(cooldowns[k]) <= 0.0:
			cooldowns.erase(k)
	for a in ctx.parties:
		if a == null or not is_instance_valid(a):
			continue
		if cooldowns.has(a.get_instance_id()):
			continue
		if ctx.player.distance_to_party(a) <= ctx.cfg.encounter_distance + ctx.rules.trigger_margin:
			open(a)
			return

func open(a: AIParty) -> void:
	current = a
	if ctx.player.moving:
		ctx.player.halt()          # 遭遇打断行军：部队停在原地
	ctx.time.lock()                # 对话期间强制暂停，空格不生效
	var fname := GameState.faction_name(ctx.data, a.faction_id)
	var col := Color(0.9, 0.85, 0.7)
	if a.faction_id >= 0:
		col = ctx.data.faction(a.faction_id).color
	var kindname: String = {"lord": "领主部队", "caravan": "商队", "bandit": "强盗团伙"}.get(a.ai_kind(), "部队")
	var lead_line := ""
	if a.boss_title != "":
		lead_line = "敌方首领：%s\n" % a.boss_title
	# 选项表是**数据**：HUD 只照着画，不做任何「能不能点」的判断（同 4b-2 的进城菜单）
	ctx.hud.show_encounter("遭遇 %s" % a.party_name,
		"%s · %s\n%s兵力：%d 人     你的兵力：%d 人\n\n时间已暂停 —— 请决定行动。" % [
			kindname, fname, lead_line, a.troop_count, ctx.player.troop_count], col,
		options())
	ctx.set_camera_active(false)
	# 遭遇提示音（对话框弹出）
	Sfx.play("encounter")

# =============================================================== 遭遇菜单（第四轮 4c）
## 选项表：每项 {id, label, enabled, hint}，顺序即显示顺序。
## **这里是唯一决定「有哪些选项、能不能点」的地方** —— HUD / 对话框只照着画。
## 数据驱动的好处与进城菜单一样：这些选项的可用性取决于「敌人类别 + 你的钱 + 你的战力」，
## 而这三样在 900 帧的主场景里一个都变不了，所以必须能在没有窗口的情况下逐条断言
## （见 tools/encounter_check.gd）。
##
## 四个选项对应四条**不同**的路（顺序：动手 → 花钱 → 收钱 → 走人，与进城菜单「离开放最后」一致）：
##   attack  进 Boss 战：打赢拿战利品 + 声望，打输掉兵掉钱被送回城（旧有路径）
##   bribe   掏钱买平安：**强盗 / 商队**收买路钱（领主不收），钱不够就点不动
##   demand  反过来收他们的买路钱：兵力压倒对方（≥ demand_ratio）才亮，白拿一笔 + 声望
##   retreat 不战而走：掉队 + 士气按伤亡比例下降 + 冷却，代价最小但什么都拿不到
func options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var a := current
	if a == null or not is_instance_valid(a):
		return out
	var r := ctx.rules
	var kind := a.ai_kind()
	out.append({
		"id": "attack", "label": "攻 击", "enabled": true,
		"hint": "进入 Boss 战：预计掉队 %d 人" % int(a.troop_count * r.loss_rate(kind)),
	})
	if r.can_toll(kind):
		var price := r.bribe_price(kind, a.troop_count, ctx.campaign.renown)
		var disc := r.renown_discount(ctx.campaign.renown)
		out.append({
			"id": "bribe", "label": "花钱买路（%d 金）" % price,
			"enabled": ctx.campaign.denars >= price,
			"hint": "现有 %d 金；声望折扣 −%d%%" % [ctx.campaign.denars, disc],
		})
		var gain := r.demand_gain(kind, a.troop_count)
		var need := r.demand_need(kind, a.troop_count)
		var power := ctx.campaign.combat_power()
		out.append({
			"id": "demand", "label": "索要买路钱（%d 金）" % gain,
			"enabled": power >= need,
			"hint": "你的战力 %d，需要 ≥ %d" % [power, need],
		})
	else:
		# 领主：两样都灰掉，但**必须**给出理由（灰行不留白是 4b-2 定下的规矩）
		out.append({
			"id": "bribe", "label": "花钱买路", "enabled": false,
			"hint": "领主不收买路钱（军事贵族不吃这一套）",
		})
		out.append({
			"id": "demand", "label": "索要买路钱", "enabled": false,
			"hint": "领主宁死不交买路钱（讹诈只对强盗 / 商队有效）",
		})
	out.append({
		"id": "retreat", "label": "撤 退", "enabled": true,
		"hint": "不战而走：掉队约 %d 人、士气下降，%d 秒内它追不上来" % [
			int(a.troop_count * r.loss_rate(kind)), int(r.retreat_cooldown)],
	})
	return out

## 对话框的选项回调（HUD.encounter_choice）
func resolve(action: String) -> void:
	var a := current
	ctx.set_camera_active(true)   # 对话框已关：把地图操作还给玩家（Boss 战会立刻再关掉）
	if a == null or not is_instance_valid(a):
		current = null
		ctx.time.unlock()
		return
	if action == "attack":
		current = null
		ctx.hud.hide_encounter()
		attack_requested.emit(a)   # 现在所有部队（领主 / 商队 / 强盗）都会进入 Boss 战
		return
	# bribe / demand 的可行性在这里**重新判一遍**：面板是照着 options() 画的，但面板不是权威
	# （自检、作弊、改过数据的过期菜单都能把不可用的动作送进来）。判不过就什么都不做、把对话框
	# 留着让玩家改主意 —— 与 SettlementSystem.resolve 的静默拒绝是同一条规矩。
	var done := false
	match action:
		"bribe":
			done = _do_bribe(a)
		"demand":
			done = _do_demand(a)
		_:
			# "retreat" 与任何未知动作都按撤退处理：对话框只有 Esc / 手柄 B → "retreat"
			# 这一个兜底来源，而「什么都不做」会把玩家卡在锁着时间的对话框里。
			done = _do_retreat(a)
	if done:
		current = null
		ctx.hud.hide_encounter()

## 撤退：掉队 + 士气按 01 §5.8 的复合式下降 + 冷却 + 把玩家推开
func _do_retreat(a: AIParty) -> bool:
	var r := ctx.rules
	var kind := a.ai_kind()
	var loss := int(a.troop_count * r.loss_rate(kind))
	var lost := ctx.campaign.lose_troops(loss)
	# 士气公式要三个数：我方阵亡 / 敌方阵亡 / 我方总兵力。敌方那个数按对方损失率估一份
	# （台账见 last_ledger；原文这两本账是战斗真实记录，本工程是【推断】）。
	var enemy_dead := int(a.troop_count * r.loss_rate(kind))
	var total := maxi(1, ctx.player.troop_count + lost)
	var pen := r.retreat_morale_penalty(lost, enemy_dead, total)
	if pen > 0:
		ctx.campaign.add_morale(-pen)
	_record("retreat", kind, a.troop_count, lost, enemy_dead, 0, 0)
	cooldowns[a.get_instance_id()] = r.retreat_cooldown
	push_away(a.position)
	ctx.hud.show_toast("你避开了 %s 的锋芒，绕道而行（掉队 %d 人%s）" % [
		a.party_name, lost, "，士气 −%d" % pen if pen > 0 else ""])
	print("[遭遇] 撤退：避开 %s，掉队 %d 人，士气 −%d（当前 %d）" % [
		a.party_name, lost, pen, ctx.campaign.morale])
	# ⚠ 这里必须 **unlock** 而不是 evaluate：open() 把 time_lock 置成了 true，
	# 只 evaluate 的话 time_lock 仍是 true → 状态永远是 LOCKED → 世界时间再也不流动
	# （第四轮 4c 修掉的旧 bug：遭遇里选过一次撤退之后，时间会永久冻住）。
	# unlock() 会清掉锁并按「是否在行军」重新裁决，于是行军途中时间照常流动、抵达后再暂停。
	ctx.time.unlock()
	return true

## 花钱买路：扣钱 → 对方放行
func _do_bribe(a: AIParty) -> bool:
	var r := ctx.rules
	var kind := a.ai_kind()
	if not r.can_toll(kind):
		return false
	var price := r.bribe_price(kind, a.troop_count, ctx.campaign.renown)
	if not ctx.campaign.spend(price):
		return false                     # 钱不够：静默拒绝，对话框留着
	_record("bribe", kind, a.troop_count, 0, 0, -price, 0)
	cooldowns[a.get_instance_id()] = r.retreat_cooldown
	push_away(a.position)
	ctx.hud.show_toast("%s 收了 %d 金买路钱，放你过去（钱袋 %d 金）" % [
		a.party_name, price, ctx.campaign.denars])
	print("[遭遇] 买路：付给 %s %d 金，钱袋 %d 金" % [a.party_name, price, ctx.campaign.denars])
	ctx.time.unlock()
	return true

## 索要买路钱：兵力压倒对方才亮（门槛见 options() / EncounterRules.demand_need）
func _do_demand(a: AIParty) -> bool:
	var r := ctx.rules
	var kind := a.ai_kind()
	if not r.can_toll(kind):
		return false
	if ctx.campaign.combat_power() < r.demand_need(kind, a.troop_count):
		return false                     # 威慑不足：静默拒绝，对话框留着
	var gain := r.demand_gain(kind, a.troop_count)
	var ren := r.demand_renown(a.troop_count)
	ctx.campaign.earn(gain)
	ctx.campaign.add_renown(ren)
	_record("demand", kind, a.troop_count, 0, 0, gain, ren)
	cooldowns[a.get_instance_id()] = r.retreat_cooldown
	push_away(a.position)
	ctx.hud.show_toast("你朝 %s 索要买路钱：对方交出 %d 金，声望 +%d" % [
		a.party_name, gain, ren])
	print("[遭遇] 索要买路钱：%s 交出 %d 金，声望 +%d（钱袋 %d 金）" % [
		a.party_name, gain, ren, ctx.campaign.denars])
	ctx.time.unlock()
	return true

## 记一笔台账（gold_delta 正数是进账；renown_delta 同理）。
## ally_start 由「当前兵力 + 阵亡」反推：_record 是在扣兵之后调用的，
## 而 lose_troops 有「至少留 5 人」的下限，所以只有反推才能拿到真正开战前的人数。
func _record(act: String, kind: String, enemy_start: int, ally_dead: int,
		enemy_dead: int, gold_delta: int, renown_delta: int) -> void:
	last_ledger = {
		"action": act, "kind": kind,
		"ally_start": ctx.player.troop_count + ally_dead, "enemy_start": enemy_start,
		"ally_dead": ally_dead, "enemy_dead": enemy_dead,
		"ally_left": ctx.player.troop_count,
		"gold_delta": gold_delta, "renown_delta": renown_delta,
	}

## 战斗结束后的落地结算：战利品 / 损失 / 战败回城 / 主动撤出（都由 BattleLauncher 触发）
func on_battle_finished(result: String, a: AIParty) -> void:
	if a == null or not is_instance_valid(a):
		return
	var title: String = a.boss_title if a.boss_title != "" else a.party_name
	var p := Vector2(a.position.x, a.position.z)
	var r := ctx.rules
	if result == "win":
		ctx.parties.erase(a)
		a.queue_free()
		var kind := a.ai_kind()
		# 战利品：EncounterRules.loot_rate(kind) 是「按敌人档位分档」的系数
		# （对应 01 §2.9：类型不同，商品掷骰分别是满额 / 减半 / 五分之一），
		# EconomyRules.loot_per_troop 是每人基准金（本地化，见那边的说明）。
		var spoils := int(round(float(a.troop_count) * r.loot_rate(kind) * ctx.economy.loot_per_troop))
		var loss := int(a.troop_count * r.loss_rate(kind))
		var loot_word := r.loot_word(kind)
		var lost := ctx.campaign.lose_troops(loss)
		ctx.campaign.add_spoils(spoils, loot_word)
		# 声望：本地化新增（原文用领主关系 / 影响力），供编制上限与军费折扣使用
		var renown := maxi(1, a.troop_count / 10)
		ctx.campaign.add_renown(renown)
		# 台账：打赢 = 敌方部队被抹掉（全灭），我方按损失率掉队
		_record("win", kind, a.troop_count, lost, a.troop_count, spoils, renown)
		ctx.hud.show_toast("击败了 %s！缴获%s %d 金，声望 +%d" % [title, loot_word, spoils, renown])
		print("[Boss战] 胜利：击败了 %s（%s），缴获%s %d 金，损失 %d 人，当前兵力 %d，钱 %d，声望 %d" % [
			title, kind, loot_word, spoils, loss, ctx.player.troop_count,
			ctx.campaign.denars, ctx.campaign.renown])
	elif result == "lose":
		# 战败：溃散掉一部分兵力，并被劫走一部分钱财（对应 01 §5.9 的战败处置；
		# 原文那套「30% 英雄被俘 / 假释 ±3」属于英雄系统，本工程 4c 再做玩家侧的选项）
		var loss2 := maxi(1, ctx.player.troop_count * 2 / 5)
		var lost := ctx.campaign.lose_troops(loss2)
		var toll := ctx.campaign.denars / 4
		if toll > 0:
			ctx.campaign.spend(toll)
		# 台账：战败时敌方伤亡记 0 —— 我们被打散了，没有可信的对方数字，不编
		_record("lose", a.ai_kind(), a.troop_count, lost, 0, -toll, 0)
		var town := nearest_town(p)
		if town != null:
			var h := ctx.data.hm.height_at(town.pos.x, town.pos.y)
			ctx.player.position = Vector3(town.pos.x, h + 0.4, town.pos.y)
			ctx.time.order_move(town.pos)
			ctx.day_night.time_of_day = fmod(ctx.day_night.time_of_day + 0.5, 1.0)
			ctx.hud.show_toast("战败…… 损失 %d 人、%d 金，你被送回了 %s（时间推进半天）" % [
				lost, toll, town.name])
			print("[Boss战] 战败：损失 %d 人、%d 金，被送回 %s，时间推进半天" % [lost, toll, town.name])
		cooldowns[a.get_instance_id()] = r.defeat_cooldown
	else:
		# 战斗里主动撤出：损失按该敌人的损失率估一份，士气代价照搬
		# 01 §5.8 simulate_retreat 的复合式（见 EncounterRules.retreat_morale_penalty）
		var kind3 := a.ai_kind()
		var loss3 := int(a.troop_count * r.loss_rate(kind3))
		var lost3 := ctx.campaign.lose_troops(loss3)
		# 敌方伤亡按对方的损失率估一份（旧实现是把 lost3 复制一份当敌方伤亡，
		# 相当于假定「双方伤亡永远相当」—— 那是凑数，现在是台账里的一个显式估计）
		var enemy_dead3 := int(a.troop_count * r.loss_rate(kind3))
		var pen := r.retreat_morale_penalty(lost3, enemy_dead3, maxi(1, ctx.player.troop_count + lost3))
		if pen > 0:
			ctx.campaign.add_morale(-pen)
		_record("battle_escape", kind3, a.troop_count, lost3, enemy_dead3, 0, 0)
		ctx.hud.show_toast("你撤出了与 %s 的战斗（损失 %d 人，士气 −%d → %d）" % [
			title, lost3, pen, ctx.campaign.morale])
		print("[Boss战] 撤出：损失 %d 人，士气 −%d（当前 %d）" % [lost3, pen, ctx.campaign.morale])
		cooldowns[a.get_instance_id()] = r.battle_retreat_cooldown
		push_away(a.position)

## 把玩家朝远离 from 的方向推开一段距离，并重新下达行军令（撤退 / 战败回城后都用）
func push_away(from: Vector3) -> void:
	var d := Vector2(ctx.player.position.x - from.x, ctx.player.position.z - from.z)
	if d.length() < 0.1:
		d = Vector2(1, 0)
	d = d.normalized()
	var m := ctx.rules.push_away_margin
	var goal := Vector2(ctx.player.position.x, ctx.player.position.z) + d * ctx.rules.push_away_distance
	goal.x = clampf(goal.x, m, ctx.cfg.map_size - m)
	goal.y = clampf(goal.y, m, ctx.cfg.map_size - m)
	ctx.time.order_move(goal)

## 最近的己方/中立城镇（用于战败回城）
func nearest_town(p: Vector2) -> Settlement:
	var best: Settlement = null
	var bd := 1e20
	var my_faction := ctx.data.faction_at(p.x, p.y)
	for s in ctx.data.settlements:
		if s.kind == Settlement.Kind.VILLAGE:
			continue
		if my_faction != 255 and s.faction_id != my_faction:
			continue
		var d := s.pos.distance_squared_to(p)
		if d < bd:
			bd = d
			best = s
	if best == null:
		# 没有己方城镇：退而求其次，任何非村庄都行
		for s in ctx.data.settlements:
			if s.kind == Settlement.Kind.VILLAGE:
				continue
			var d2 := s.pos.distance_squared_to(p)
			if d2 < bd:
				bd = d2
				best = s
	return best