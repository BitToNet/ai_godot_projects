## =============================================================================
##  SaveGame —— 存档的采集 / 落地 / 校验（第四轮 4d）
##
##  设计依据（G:\warband_docs）：原文**没有**存档格式的落档（「存档里有哪些字段、
##  什么顺序」是【未解】），所以格式本身是本工程的**显式设计决策**；但原文有三条
##  可以直接照用的设计含义，本文件逐条实现并标注：
##
##   · 【实证】04-数据字典 §17 `compatible_savegame_module_version`：原版把「存档模块
##     版本」写进存档、读取时比对 —— 版本不合就拒绝，而不是按新格式猜着读。
##     → 本文件的 `SAVE_VERSION`，再加 `map_seed` 与「定居点数量 / 部队 id」几道
##       身份门槛，任一不合就**拒绝读档**（宁可拒绝，不可猜）。
##   · 【实证】02-玩法设计 §3.4.1 设计含义：`change_player_party_morale` 在加 delta
##     **之前**先把读到的士气钳到 [0,100] —— 防的正是「存档塞进一个越界值（比如 300）」，
##     只钳结果的话那个坏值会一直粘在 100 上。→ 本文件对**每一个**字段都先钳再写，
##     而且把「钳掉了什么」记进 warnings（CampaignState.add_morale 也照此改了）。
##   · 【推断】02-玩法设计 §6.5 设计含义（`game_event_battle_end` 那个收尾脚本）：
##     读档之后不能留下「指向不存在对象」的引用。本工程对应的风险点是：遭遇里的当前
##     部队、进城菜单的当前定居点、玩家与部队的旧寻路路径、按 instance_id 记的遭遇冷却。
##     → apply() 结尾专门有一步「修引用」，全部归零或按稳定 id 重建。
##
##  本地化取舍（与原版不同、必须记账的地方）：
##   1. **不存地图**：地图是「种子决定论」的产物（map_seed → 6~7 秒重建）。存整张地图
##      只会把存档跟生成版本绑死。存档只记 `map_seed`，读档 = 重建世界 + 套状态。
##      代价是读档要重跑一遍生成（真机 6~7 秒），本工程接受（单机、无联机需求）。
##   2. **实体靠稳定 id 对齐，不靠数组顺序**：定居点用 `Settlement.id`，部队用
##      `AIParty.spawn_id`（生成顺序的序号，同一种子必然一致）。部队**不能**按数组下标存：
##      打赢一场 Boss 战会 `ctx.parties.erase()` 掉一格，数组下标从此全体错位。
##      档案里有、世界里没有 → 拒绝读档；世界里没有、档案里也没有（= 已经被打掉的）
##      → 读档后保持消失（打掉的部队不复活）。
##   3. **面板状态不存**：读档会把遭遇框 / 进城菜单收起来（apply 的修引用步骤）。
##      存档只在「没有面板」时允许（由 Main 判定，见 _on_quicksave_requested）。
##   4. **AI 的内部计时不存**（重寻路计时 / 追击计时 / 寻路失败退避 / 游荡锚点）：
##      读档后按生成态重来。它们只影响「下一步往哪走」，存下来会让格式跟着 AI 的
##      实现细节一起变。
##   5. **读档不重跑日结**：day 只是写回，绝不触发 day_changed —— 否则读一次档就
##      等于过了一天（扣粮 / 发薪 / 算逃兵）。
## =============================================================================
class_name SaveGame
extends RefCounted

const MAGIC := "warband-godot-save"
const SAVE_VERSION := 1
const DIR := "user://saves"
const SLOT_QUICK := "quick"

# =============================================================== 采集
## 把一局游戏里**会变的那部分**收成一个可 JSON 化的字典。
## 不在这里的东西一律是「生成期由种子决定」的（地形 / 路网 / 定居点选址 / 货物本地
## 价差 / 部队的出生位置与兵种），读档时由重建出来的世界提供。
static func collect(ctx: WorldContext, encounters: EncounterSystem = null) -> Dictionary:
	if ctx == null or ctx.campaign == null or ctx.player == null or ctx.data == null:
		return {}
	var camp := ctx.campaign
	var goods := {}
	for k in camp.goods.keys():
		goods[str(int(k))] = int(camp.goods[k])
	var stl: Array = []
	for s in ctx.data.settlements:
		stl.append({
			"id": s.id,
			"prosperity": s.prosperity,
			"volunteers": s.volunteers,
			"garrison": s.garrison,
		})
	var parties: Array = []
	for a in ctx.parties:
		if a == null or not is_instance_valid(a):
			continue
		parties.append({
			"spawn_id": a.spawn_id,
			"kind": a.kind,
			"troops": a.troop_count,
			"x": a.position.x,
			"z": a.position.z,
			"faction_id": a.faction_id,
			"heavy": a.heavy,
			"is_boss": a.is_boss,
			"name": a.party_name,
			"boss_title": a.boss_title,
			"cooldown": _cooldown_of(encounters, a),
		})
	var tod := 0.0
	var tday := camp.day
	if ctx.day_night != null:
		tod = ctx.day_night.time_of_day
		tday = ctx.day_night.day
	var sidx := 0
	if ctx.time != null:
		sidx = ctx.time.speed_index
	return {
		"magic": MAGIC,
		"version": SAVE_VERSION,
		"map_seed": int(ctx.cfg.map_seed),
		"saved_at": int(Time.get_unix_time_from_system()),
		"campaign": {
			"day": camp.day,
			"denars": camp.denars,
			"supplies": camp.supplies,
			"morale": camp.morale,
			"renown": camp.renown,
			"tier": camp.tier,
			"debt_weeks": camp.debt_weeks,
			"goods": goods,
		},
		"time": {"day": tday, "time_of_day": tod, "speed_index": sidx},
		"player": {
			"x": ctx.player.position.x,
			"z": ctx.player.position.z,
			"troops": ctx.player.troop_count,
		},
		"settlements": stl,
		"parties": parties,
	}

## 遭遇冷却按 spawn_id 记（instance_id 跨进程不稳定，见文件头取舍 2）
static func _cooldown_of(encounters: EncounterSystem, a: AIParty) -> float:
	if encounters == null or encounters.cooldowns == null:
		return 0.0
	return float(encounters.cooldowns.get(a.get_instance_id(), 0.0))

# =============================================================== 落地
## 校验 + 写回 + 修引用，返回 {ok, error, warnings, info}。
## 校验不过就**一个字段都不写**（拒绝读档不留半个状态）。
static func apply(ctx: WorldContext, data: Dictionary, encounters: EncounterSystem = null,
		settlements: SettlementSystem = null) -> Dictionary:
	if ctx == null or ctx.campaign == null or ctx.player == null or ctx.data == null:
		return _fail("世界还没准备好（地图生成完之后才能读档）")
	if ctx.campaign.rules == null:
		return _fail("战役状态没初始化")
	if data.is_empty():
		return _fail("存档是空的")
	if _str(data.get("magic", "")) != MAGIC:
		return _fail("这不是本工程的存档（magic 不匹配）")
	var ver := _int(data.get("version", -1), -1)
	if ver != SAVE_VERSION:
		return _fail("存档版本 %d 与当前 %d 不一致（原版也是直接拒绝，不猜着读）" % [ver, SAVE_VERSION])
	var seed_in := _int(data.get("map_seed", -1), -1)
	var seed_now := int(ctx.cfg.map_seed)
	if seed_in != seed_now:
		return _fail("存档来自另一张地图（种子 %d 与当前 %d 不符）" % [seed_in, seed_now])

	# ---------------- 先全部校验，一处不合就整体拒绝 ----------------
	var stl_rows := _arr(data.get("settlements", []))
	if stl_rows.size() != ctx.data.settlements.size():
		return _fail("定居点数量对不上（存档 %d，当前世界 %d）" % [stl_rows.size(), ctx.data.settlements.size()])
	var by_id := {}
	for s in ctx.data.settlements:
		by_id[s.id] = s
	for row in stl_rows:
		if typeof(row) != TYPE_DICTIONARY:
			return _fail("定居点条目不是字典")
		var sid := _int((row as Dictionary).get("id", -1), -1)
		if not by_id.has(sid):
			return _fail("存档里的定居点 %d 在当前世界里不存在（不是同一张地图）" % sid)

	var world_by_spawn := {}
	for a in ctx.parties:
		if a != null and is_instance_valid(a):
			world_by_spawn[a.spawn_id] = a
	var rows := _arr(data.get("parties", []))
	var save_by_spawn := {}
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			return _fail("部队条目不是字典")
		var rid := _int((row as Dictionary).get("spawn_id", -1), -1)
		if not world_by_spawn.has(rid):
			return _fail("存档里的部队 #%d 在当前世界里不存在（不是同一张地图）" % rid)
		if save_by_spawn.has(rid):
			return _fail("存档里的部队 #%d 重复出现" % rid)
		save_by_spawn[rid] = row

	# ---------------- 校验通过：开始写 ----------------
	var warns: Array[String] = []
	var camp := ctx.campaign
	var cd := _dict(data.get("campaign", {}))
	camp.day = _clamp_warn(warns, "campaign.day", _int(cd.get("day", camp.day), camp.day), 1, 99999)
	camp.denars = _clamp_warn(warns, "campaign.denars", _int(cd.get("denars", camp.denars), camp.denars), 0, 99999999)
	camp.supplies = _clamp_warn(warns, "campaign.supplies", _int(cd.get("supplies", camp.supplies), camp.supplies), 0, 99999)
	camp.morale = _clamp_warn(warns, "campaign.morale", _int(cd.get("morale", camp.morale), camp.morale), 0, 100)
	camp.renown = _clamp_warn(warns, "campaign.renown", _int(cd.get("renown", camp.renown), camp.renown), 0, 9999999)
	camp.debt_weeks = _clamp_warn(warns, "campaign.debt_weeks", _int(cd.get("debt_weeks", 0), 0), 0, 9999)
	camp.tier = _clamp_warn(warns, "campaign.tier", _int(cd.get("tier", camp.tier), camp.tier), 0, camp.rules.max_tier())
	camp.starving = false

	# 货物：只收合法货物 id，件数下限 0；非法 id 直接丢弃并留一条警告
	var gcount := 0
	if ctx.economy != null:
		gcount = ctx.economy.good_count()
	var goods := {}
	var gd := _dict(cd.get("goods", {}))
	for k in gd.keys():
		var gid := _int(k, -1)
		if gid < 0 or gid >= gcount:
			warns.append("丢弃了未知货物 id %s（本图共 %d 种货）" % [_str(k), gcount])
			continue
		var n := _clamp_warn(warns, "goods[%d]" % gid, _int(gd[k], 0), 0, 9999)
		if n > 0:
			goods[gid] = n
	camp.goods = goods

	# 玩家：位置 / 兵力。兵力超编只可能来自坏存档 → 钳到编制上限
	var pd := _dict(data.get("player", {}))
	var cap := camp.capacity()
	ctx.player.troop_count = _clamp_warn(warns, "player.troops",
		_int(pd.get("troops", ctx.player.troop_count), ctx.player.troop_count), 5, maxi(5, cap))
	_set_xz(ctx, ctx.player, _num(pd.get("x", ctx.player.position.x), ctx.player.position.x),
		_num(pd.get("z", ctx.player.position.z), ctx.player.position.z), warns)
	ctx.player.halt()          # 旧寻路路径作废：目的地可能已经不在存档里了
	ctx.player.refresh_label()

	# 定居点：繁荣度 / 志愿者池 / 驻军
	for row in stl_rows:
		var sd: Dictionary = row
		var s := by_id[_int(sd.get("id", -1), -1)] as Settlement
		s.prosperity = _clamp_warn(warns, "settlement[%d].prosperity" % s.id,
			_int(sd.get("prosperity", s.prosperity), s.prosperity), 0, 100)
		s.volunteers = _clamp_warn(warns, "settlement[%d].volunteers" % s.id,
			_int(sd.get("volunteers", s.volunteers), s.volunteers), 0, maxi(0, s.volunteers_cap))
		s.garrison = _clamp_warn(warns, "settlement[%d].garrison" % s.id,
			_int(sd.get("garrison", s.garrison), s.garrison), 0, 999999)

	# 部队：位置 / 兵力 / 身份字段；AI 的瞬时状态一律重置（文件头取舍 4）
	var new_cd := {}
	for row in rows:
		var ad: Dictionary = row
		var pid := _int(ad.get("spawn_id", -1), -1)
		var a := world_by_spawn[pid] as AIParty
		a.troop_count = _clamp_warn(warns, "party[%d].troops" % pid,
			_int(ad.get("troops", a.troop_count), a.troop_count), 1, 99999)
		a.kind = _clamp_warn(warns, "party[%d].kind" % pid, _int(ad.get("kind", a.kind), a.kind), 0, 2)
		a.faction_id = _int(ad.get("faction_id", a.faction_id), a.faction_id)
		a.heavy = bool(ad.get("heavy", a.heavy))
		a.is_boss = bool(ad.get("is_boss", a.is_boss))
		a.party_name = _str(ad.get("name", a.party_name))
		a.boss_title = _str(ad.get("boss_title", a.boss_title))
		_set_xz(ctx, a, _num(ad.get("x", a.position.x), a.position.x),
			_num(ad.get("z", a.position.z), a.position.z), warns)
		a.clear_path()
		a.chasing = false
		a.last_goal = Vector2(-1.0, -1.0)
		a.fail_cell = Vector2i(-1, -1)
		a.fail_until = 0.0
		a.fail_streak = 0
		a.refresh_label()
		var c := _num(ad.get("cooldown", 0.0), 0.0)
		if c > 0.0:
			new_cd[a.get_instance_id()] = clampf(c, 0.0, 600.0)
	# 世界里还在、档案里没有的部队 = 已经打赢 / 打散的那些：读档后保持消失
	var gone := 0
	for i in range(ctx.parties.size() - 1, -1, -1):
		var g := ctx.parties[i]
		if g == null or not is_instance_valid(g):
			continue
		if not save_by_spawn.has(g.spawn_id):
			ctx.parties.remove_at(i)
			g.queue_free()
			gone += 1

	# 时间：day 只写回、**不触发日结**（文件头取舍 5）；读完一律回到「暂停」态
	var td := _dict(data.get("time", {}))
	if ctx.day_night != null:
		ctx.day_night.day = camp.day
		ctx.day_night.time_of_day = fposmod(_num(td.get("time_of_day", ctx.day_night.time_of_day),
			ctx.day_night.time_of_day), 1.0)
	if ctx.time != null:
		ctx.time.speed_index = _clamp_warn(warns, "time.speed_index",
			_int(td.get("speed_index", 0), 0), 0, ctx.time.speed_steps.size() - 1)
		ctx.time.time_lock = false
		ctx.time.space_latched = false
		ctx.time.evaluate()
		if ctx.day_night != null:
			ctx.day_night.speed = ctx.time.speed_steps[ctx.time.speed_index]

	# ---------------- 修引用（【推断】02 §6.5 的设计含义）----------------
	if encounters != null:
		encounters.current = null
		encounters.cooldowns = new_cd
	if settlements != null:
		settlements.current = null
		settlements.qty = 1
		settlements.trade_good = 0
	if ctx.hud != null:
		ctx.hud.hide_encounter()
		ctx.hud.hide_settlement()
	if ctx.camera != null:
		ctx.camera.recenter()
	camp.changed.emit()
	return {
		"ok": true,
		"error": "",
		"warnings": warns,
		"info": {
			"day": camp.day,
			"denars": camp.denars,
			"supplies": camp.supplies,
			"morale": camp.morale,
			"troops": ctx.player.troop_count,
			"x": ctx.player.position.x,
			"z": ctx.player.position.z,
			"parties": rows.size(),
			"parties_gone": gone,
			"cooldowns": new_cd.size(),
		},
	}

## 位置落地：夹回地图内，并把 y 贴回地面（没有高度场的假世界只写 x/z —— 自检用）
static func _set_xz(ctx: WorldContext, n: Node3D, x: float, z: float, warns: Array[String]) -> void:
	var lim := float(ctx.cfg.map_size)
	if x < 0.0 or x > lim or z < 0.0 or z > lim:
		warns.append("坐标越界已夹回地图内：(%.0f, %.0f)" % [x, z])
	x = clampf(x, 0.0, lim)
	z = clampf(z, 0.0, lim)
	var y := n.position.y
	if ctx.data.hm != null:
		y = ctx.data.hm.height_at(x, z)
	n.position = Vector3(x, y, z)

# =============================================================== 文件
static func path_of(slot: String) -> String:
	return "%s/%s.json" % [DIR, slot]

## 给玩家看的真实路径（提示条上显示，免得「存到哪去了」变成谜）
static func os_path_of(slot: String) -> String:
	return ProjectSettings.globalize_path(path_of(slot))

static func exists(slot: String) -> bool:
	return FileAccess.file_exists(path_of(slot))

## 写盘并**立刻回读**：磁盘满 / 权限 / 写坏这类问题在这里就暴露，
## 而不是等玩家下次读档才发现文件是空的（回读会走完整的解析与 magic 校验）。
static func write(slot: String, data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {"ok": false, "error": "没有可写的内容", "path": path_of(slot)}
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := path_of(slot)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "打不开存档文件（错误码 %d）" % FileAccess.get_open_error(), "path": path}
	f.store_string(JSON.stringify(data, "  "))
	var bytes := f.get_length()
	f.close()
	var back := read(slot)
	if not bool(back.get("ok", false)):
		return {"ok": false, "error": "写完回读失败：%s" % _str(back.get("error", "")), "path": path}
	if bytes <= 0:
		return {"ok": false, "error": "存档文件是空的", "path": path}
	return {"ok": true, "error": "", "path": path, "bytes": bytes}

static func read(slot: String) -> Dictionary:
	var path := path_of(slot)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "没有存档文件", "path": path}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "读不了存档文件（错误码 %d）" % FileAccess.get_open_error(), "path": path}
	var text := f.get_as_text()
	f.close()
	# 用实例版 JSON.parse：静态版 JSON.parse_string 在失败时会 ERR_PRINT（门禁把 ERROR 行
	# 当失败），而且它只给一个布尔；实例版能拿到行号与原因，正好写进给玩家看的提示。
	var j := JSON.new()
	var err := j.parse(text)
	if err != OK:
		return {"ok": false, "error": "存档不是合法 JSON（第 %d 行：%s）" % [j.get_error_line(), j.get_error_message()], "path": path}
	var parsed: Variant = j.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "存档顶层不是对象（data 是 %s）" % type_string(typeof(parsed)), "path": path}
	return {"ok": true, "error": "", "data": parsed, "path": path}

static func erase(slot: String) -> bool:
	if not exists(slot):
		return true
	return DirAccess.remove_absolute(path_of(slot)) == OK

# =============================================================== 小工具
static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "warnings": [], "info": {}}

static func _arr(v: Variant) -> Array:
	return v if typeof(v) == TYPE_ARRAY else []

static func _dict(v: Variant) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}

static func _str(v: Variant) -> String:
	return v if v is String else str(v)

static func _int(v: Variant, def: int) -> int:
	if v is int or v is float or v is bool:
		return int(v)
	if v is String and (v as String).is_valid_int():
		return (v as String).to_int()
	return def

static func _num(v: Variant, def: float) -> float:
	if v is int or v is float or v is bool:
		return float(v)
	if v is String and (v as String).is_valid_float():
		return (v as String).to_float()
	return def

## 钳值 + 记账：越界时把「字段 原值 → 钳后值」记一条警告。
## 这是 02 §3.4.1 那条设计含义的落地：坏存档不许把越界值漏进新状态，
## 而且必须留下痕迹 —— 静默钳掉和静默接受一样危险，一个你不知情，一个会扩散。
static func _clamp_warn(warns: Array[String], field: String, v: int, lo: int, hi: int) -> int:
	var c := clampi(v, lo, hi)
	if c != v:
		warns.append("%s 越界：%d → %d" % [field, v, c])
	return c