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
	ctx.hud.show_encounter("遭遇 %s" % a.party_name,
		"%s · %s\n%s兵力：%d 人     你的兵力：%d 人\n\n时间已暂停 —— 请决定行动。" % [
			kindname, fname, lead_line, a.troop_count, ctx.player.troop_count], col)
	ctx.set_camera_active(false)
	# 遭遇提示音（对话框弹出）
	Sfx.play("encounter")

## 对话框的选项回调（HUD.encounter_choice）
func resolve(action: String) -> void:
	var a := current
	current = null
	ctx.set_camera_active(true)   # 对话框已关：把地图操作还给玩家（Boss 战会立刻再关掉）
	if a == null or not is_instance_valid(a):
		ctx.time.unlock()
		return
	if action == "attack":
		ctx.hud.hide_encounter()
		attack_requested.emit(a)   # 现在所有部队（领主 / 商队 / 强盗）都会进入 Boss 战
		return
	print("[撤退] 你避开了 %s 的锋芒，绕道而行。" % a.party_name)
	cooldowns[a.get_instance_id()] = ctx.rules.retreat_cooldown
	push_away(a.position)
	ctx.hud.hide_encounter()
	# 撤退会重新下达行军命令 → 时间随移动流动，抵达后再次暂停
	ctx.time.evaluate()

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
		var spoils := int(round(float(a.troop_count) * r.loot_rate(kind)))
		var loss := int(a.troop_count * r.loss_rate(kind))
		var loot_word := r.loot_word(kind)
		ctx.player.troop_count = maxi(5, ctx.player.troop_count - loss)
		ctx.player.refresh_label()
		ctx.player.label.text = "玩家部队 · %d 人" % ctx.player.troop_count
		ctx.hud.show_toast("击败了 %s！缴获%s %d" % [title, loot_word, spoils])
		print("[Boss战] 胜利：击败了 %s（%s），缴获%s %d，当前兵力 %d" % [
			title, kind, loot_word, spoils, ctx.player.troop_count])
	elif result == "lose":
		var town := nearest_town(p)
		if town != null:
			var h := ctx.data.hm.height_at(town.pos.x, town.pos.y)
			ctx.player.position = Vector3(town.pos.x, h + 0.4, town.pos.y)
			ctx.time.order_move(town.pos)
			ctx.day_night.time_of_day = fmod(ctx.day_night.time_of_day + 0.5, 1.0)
			ctx.hud.show_toast("战败…… 你被送回了 %s（时间推进半天）" % town.name)
			print("[Boss战] 战败：被送回 %s，时间推进半天" % town.name)
		cooldowns[a.get_instance_id()] = r.defeat_cooldown
	else:
		ctx.hud.show_toast("你撤出了与 %s 的战斗" % title)
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