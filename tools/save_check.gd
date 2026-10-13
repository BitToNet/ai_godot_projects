## =============================================================================
##  save_check —— 存档回归（**不参与游戏运行**，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/save_check.gd
##
##  为什么需要它：门禁的 900 帧主场景里没人按 F5 / F9，所以「存档格式、读档校验、
##  坏数据钳制、读档后的引用修复」这四件事在别的步骤里**一项都验不到**。这里不跑地图
##  生成、不建 UI，只造两个同结构的假世界（A 存 → B 读，模拟「重开进程后再读档」），
##  把每条门与每个钳位逐项对账。
##
##  断言覆盖：
##    1. 采集：magic / 版本 / 种子 / 行数 / 字段清单齐全
##    2. 往返保真：A 存档 → B 读档，逐字段对账（含位置、士气、货物、繁荣度、部队兵力）
##    3. 三道门：版本 / magic / 种子 / 定居点数量 / 部队 id —— 不合就拒绝，
##       而且**拒绝时一个字段都不许写**（半读半写比不读更坏）
##    4. 坏数据钳制：越界值一律钳回 + 记警告；士气坏值不许「粘住」（02 §3.4.1 设计含义【实证】）
##    5. 修引用：遭遇 / 菜单 / 寻路路径 / 时间锁 / 冷却按新 instance_id 重建（02 §6.5【推断】）
##    6. 打掉的部队不复活（存档是「世界上还有什么」的唯一权威）
##    7. 文件层：写 → 回读 → 落地 → 写坏 → 拒绝 → 清理；erase 幂等
##    8. 稳定性：collect → apply → collect 两遍结果一致（字段不会在写回路上丢）
##
##  参考：G:\warband_docs —— 存档格式本身是【未解】（原文没有落档），本检查对的是
##  **本工程自己的格式与那三条设计含义**，见 SaveGame.gd 文件头。
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

func _eqi(actual: int, want: int, what: String) -> void:
	_ok(actual == want, "%s（实测 %d，期望 %d）" % [what, actual, want])

func _near(actual: float, want: float, what: String) -> void:
	_ok(absf(actual - want) <= 0.01, "%s（实测 %.2f，期望 %.2f）" % [what, actual, want])

func _has_warn(warns: Array, key: String) -> bool:
	for w in warns:
		if str(w).contains(key):
			return true
	return false

# ---------------------------------------------------------------- 假世界
class Fake:
	var cfg: MapConfig
	var data: MapData
	var economy: EconomyRules
	var campaign: CampaignState
	var player: PlayerParty
	var day_night: DayNightCycle
	var time: TimeFlowController
	var hud: StubHud
	var settlements: SettlementSystem
	var encounters: EncounterSystem
	var ctx: WorldContext

## HUD 替身：不建任何控件，只记「面板开着没有、弹过什么条」。
## 签名必须与 HUD 完全一致（GDScript 的覆盖会核对签名）。
class StubHud extends HUD:
	var open_flag: bool = false
	var settlement_open: bool = false
	var toasts: Array[String] = []
	func show_toast(text: String, _dur: float = 5.0) -> void:
		toasts.append(text)
	func show_encounter(_title: String, _info: String, _color: Color, _entries: Array = []) -> void:
		open_flag = true
	func hide_encounter() -> void:
		open_flag = false
	func is_encounter_open() -> bool:
		return open_flag
	func show_settlement_menu(_title: String, _status: String, _entries: Array[Dictionary]) -> void:
		settlement_open = true
	func hide_settlement() -> void:
		settlement_open = false
	func is_settlement_open() -> bool:
		return settlement_open
	func is_any_dialog_open() -> bool:
		return open_flag or settlement_open

func _make_world() -> Fake:
	var f := Fake.new()
	f.cfg = MapConfig.new()
	f.data = MapData.new()
	f.data.cfg = f.cfg
	f.economy = EconomyRules.create()
	f.player = PlayerParty.new()
	f.player.troop_count = 37
	f.campaign = CampaignState.new()
	f.campaign.setup(f.economy, f.player)
	f.time = TimeFlowController.new()
	f.time.player = f.player
	f.day_night = DayNightCycle.new()
	f.day_night.time_of_day = 8.0 / 24.0
	f.time.day_night = f.day_night
	f.hud = StubHud.new()
	f.settlements = SettlementSystem.new()
	f.encounters = EncounterSystem.new()
	f.ctx = WorldContext.new()
	f.ctx.cfg = f.cfg
	f.ctx.data = f.data
	f.ctx.economy = f.economy
	f.ctx.campaign = f.campaign
	f.ctx.player = f.player
	f.ctx.time = f.time
	f.ctx.day_night = f.day_night
	f.ctx.hud = f.hud
	f.ctx.rules = EncounterRules.create()
	f.settlements.ctx = f.ctx
	f.encounters.ctx = f.ctx
	return f

## 造一份**结构固定**的假世界：两个世界用它填，就能得到「定居点 id 相同、部队
## spawn_id 相同、但对象实例不同」的局面 —— 正是「重开进程后再读档」的情形。
func _fill(f: Fake) -> void:
	_add_settlement(f, 0, Settlement.Kind.TOWN, 60, 4, 6, 12)
	_add_settlement(f, 1, Settlement.Kind.CASTLE, 40, 0, 0, 20)
	_add_settlement(f, 2, Settlement.Kind.VILLAGE, 55, 3, 6, 8)
	_add_settlement(f, 3, Settlement.Kind.VILLAGE, 30, 1, 6, 6)
	_party(f, 0, AIParty.Kind.BANDIT, "黑风寨", 30, Vector2(200, 200))
	_party(f, 1, AIParty.Kind.CARAVAN, "南队", 24, Vector2(300, 300))
	_party(f, 2, AIParty.Kind.LORD, "北境领主", 150, Vector2(400, 400))

func _add_settlement(f: Fake, id: int, kind: int, prosperity: int, volunteers: int, cap: int, garrison: int) -> Settlement:
	var s := Settlement.new()
	s.id = id
	s.name = "定居点%d" % id
	s.kind = kind
	s.faction_id = 0
	s.pos = Vector2(100.0 + id * 10.0, 100.0)
	s.prosperity = prosperity
	s.volunteers = volunteers
	s.volunteers_cap = cap
	s.garrison = garrison
	f.data.settlements.append(s)
	return s

## 造一支部队并挂到树根上（与真实世界一致：读档会 queue_free() 掉「打掉的」那些，
## 不入树的孤儿节点不一定真被释放）。spawn_id 由调用者指定 = 生成顺序
func _party(f: Fake, spawn_id: int, kind: int, nm: String, troops: int, pos: Vector2) -> AIParty:
	var p := AIParty.new()
	p.spawn_id = spawn_id
	p.kind = kind
	p.party_name = nm
	p.troop_count = troops
	p.faction_id = -1
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
	f.day_night.free()
	f.encounters = null
	f.settlements = null
	f.ctx = null

# ---------------------------------------------------------------- 主流程
func _run() -> void:
	print("[存档] 定式自检（不跑地图生成、不建 UI）")
	_check_collect()
	_check_roundtrip()
	_check_doors()
	_check_garbage()
	_check_repair()
	_check_defeated()
	_check_file()
	await process_frame

	print("")
	if _fails.is_empty():
		print("PASS：存档定式全部正常（%d 项断言）" % _total)
		quit(0)
	else:
		print("FAIL：%d/%d 项断言未通过 —— %s" % [_fails.size(), _total, "; ".join(_fails)])
		quit(1)

# ---------------------------------------------------------------- 1. 采集
func _check_collect() -> void:
	print("\n-- 1. 采集：格式身份与字段清单 --")
	var f := _make_world()
	_fill(f)
	var d := SaveGame.collect(f.ctx, f.encounters)
	_ok(str(d.get("magic", "")) == SaveGame.MAGIC, "magic 已写入（%s）" % SaveGame.MAGIC)
	_eqi(int(d.get("version", -1)), SaveGame.SAVE_VERSION, "版本号")
	_eqi(int(d.get("map_seed", -1)), f.cfg.map_seed, "地图种子（读档靠它认门）")
	_eqi((d.get("settlements", []) as Array).size(), f.data.settlements.size(), "定居点行数")
	_eqi((d.get("parties", []) as Array).size(), f.ctx.parties.size(), "部队行数")
	_ok(d.has("campaign") and d.has("time") and d.has("player"), "campaign / time / player 三段都在")

	# 字段清单本身就是格式：漏一个字段，读档后就会静默丢状态
	var ck := (d.get("campaign", {}) as Dictionary).keys()
	var missing: Array[String] = []
	for k in ["day", "denars", "supplies", "morale", "renown", "tier", "debt_weeks", "goods"]:
		if not ck.has(k):
			missing.append(k)
	_ok(missing.is_empty(), "战役段字段齐全（缺：%s）" % str(missing))
	var pk := (d.get("player", {}) as Dictionary).keys()
	_ok(pk.has("x") and pk.has("z") and pk.has("troops"), "玩家段有位置与兵力")
	var tk := (d.get("time", {}) as Dictionary).keys()
	_ok(tk.has("day") and tk.has("time_of_day") and tk.has("speed_index"), "时间段有日 / 时刻 / 流速")
	var row0: Dictionary = (d.get("parties", []) as Array)[0]
	_ok(row0.has("spawn_id") and row0.has("kind") and row0.has("troops") and row0.has("cooldown"),
		"部队行含 稳定 id / 兵种 / 兵力 / 冷却")
	_ok(int(row0.get("spawn_id", -1)) == 0, "部队行按 spawn_id 记（不是数组下标）")

	# 冷却来自遭遇系统，按 instance_id 落在临时键上（读档时才换算回 spawn_id 对齐）
	f.encounters.cooldowns[f.ctx.parties[0].get_instance_id()] = 9.5
	var d2 := SaveGame.collect(f.ctx, f.encounters)
	_near(float(((d2.get("parties", []) as Array)[0] as Dictionary).get("cooldown", 0.0)), 9.5, "冷却被采集")
	_ok(SaveGame.collect(null).is_empty(), "世界为空时采集返回空字典（不炸）")
	var d3 := SaveGame.collect(f.ctx)
	_near(float(((d3.get("parties", []) as Array)[0] as Dictionary).get("cooldown", 0.0)), 0.0,
		"不传遭遇系统时冷却记 0（自检 / 纯采集路径不用它）")
	_dispose(f)

# ---------------------------------------------------------------- 2. 往返
func _check_roundtrip() -> void:
	print("\n-- 2. 往返保真：A 世界存档 → B 世界读档（模拟重开进程）--")
	var a := _make_world()
	_fill(a)
	# 把 A 调成一个处处有辨识度的状态（第 28 天 = 发薪日，顺手验「读档不重跑日结」）
	a.campaign.day = 28
	a.campaign.denars = 1234
	a.campaign.supplies = 5
	a.campaign.morale = 63
	a.campaign.renown = 260
	a.campaign.tier = 1
	a.campaign.debt_weeks = 2
	a.campaign.goods = {0: 3, 2: 1}
	a.player.troop_count = 44
	a.player.position = Vector3(321.5, 7.5, 654.25)
	(a.data.settlements[1] as Settlement).prosperity = 77   # 城堡：有繁荣度与驻军，但没有招兵池
	(a.data.settlements[1] as Settlement).garrison = 33
	(a.data.settlements[2] as Settlement).volunteers = 2    # 村庄：招兵池在它身上
	var pa := a.ctx.parties[0] as AIParty
	pa.troop_count = 55
	pa.position = Vector3(410.0, 0.0, 220.0)
	pa.boss_title = "黑风寨大头目"
	a.encounters.cooldowns[pa.get_instance_id()] = 12.5
	a.day_night.day = 28
	a.day_night.time_of_day = 0.375
	a.time.speed_index = 2
	a.day_night.speed = 4.0
	var d := SaveGame.collect(a.ctx, a.encounters)

	# B：同结构、不同实例，先弄脏一点，免得「原本就对」蒙混过关
	var b := _make_world()
	_fill(b)
	b.campaign.day = 3
	b.campaign.denars = 7
	b.campaign.morale = 12
	b.campaign.renown = 0
	b.player.troop_count = 20
	(b.data.settlements[1] as Settlement).prosperity = 5
	(b.ctx.parties[0] as AIParty).troop_count = 9
	var r := SaveGame.apply(b.ctx, d, b.encounters, b.settlements)
	_ok(bool(r.get("ok", false)), "读档成功（%s）" % str(r.get("error", "")))
	_ok((r.get("warnings", []) as Array).is_empty(), "干净存档零警告")

	_eqi(b.campaign.day, 28, "日")
	_eqi(b.campaign.denars, 1234, "钱袋")
	_eqi(b.campaign.supplies, 5, "补给")
	_eqi(b.campaign.morale, 63, "士气")
	_eqi(b.campaign.renown, 260, "声望")
	_eqi(b.campaign.tier, 1, "兵员档次")
	_eqi(b.campaign.debt_weeks, 2, "欠薪周数")
	_eqi(b.campaign.goods_of(0), 3, "货物 0 的件数")
	_eqi(b.campaign.goods_of(2), 1, "货物 2 的件数")
	_eqi(b.campaign.troops(), 44, "兵力（取自部队本体）")
	_near(b.player.position.x, 321.5, "玩家 x")
	_near(b.player.position.z, 654.25, "玩家 z")
	_eqi((b.data.settlements[1] as Settlement).prosperity, 77, "定居点 1 繁荣度")
	_eqi((b.data.settlements[2] as Settlement).volunteers, 2, "定居点 2 志愿者（村庄才有招兵池）")
	_eqi((b.data.settlements[1] as Settlement).garrison, 33, "定居点 1 驻军")
	var pb := b.ctx.parties[0] as AIParty
	_eqi(pb.troop_count, 55, "部队 #0 兵力")
	_near(pb.position.x, 410.0, "部队 #0 x")
	_near(pb.position.z, 220.0, "部队 #0 z")
	_ok(pb.boss_title == "黑风寨大头目", "部队 #0 名号")
	_eqi(b.day_night.day, 28, "昼夜系统的日（与战役同步）")
	_near(b.day_night.time_of_day, 0.375, "一天中的时刻")
	_eqi(b.time.speed_index, 2, "时间流速档位")
	_near(b.day_night.speed, 4.0, "流速真的推给了昼夜系统（×4）")

	# 冷却：按**新实例**的 instance_id 重建（不是照抄 A 的键）
	_eqi(b.encounters.cooldowns.size(), 1, "冷却条数")
	_ok(b.encounters.cooldowns.has(pb.get_instance_id()), "冷却键是 B 世界里那支部队的实例 id（重建而非照抄）")
	_near(float(b.encounters.cooldowns.get(pb.get_instance_id(), 0.0)), 12.5, "冷却值")
	_eqi(int((r.get("info", {}) as Dictionary).get("parties_gone", -1)), 0, "没有部队被移除")
	_eqi(int((r.get("info", {}) as Dictionary).get("parties", -1)), 3, "读档覆盖了 3 支部队")

	# 第 28 天是发薪日：如果读档顺手跑了一次日结，军费与补给都会变
	_eqi(b.campaign.denars, 1234, "**读档不重跑日结**：军费没被扣（第 28 天是发薪日）")
	_eqi(b.campaign.supplies, 5, "**读档不重跑日结**：粮没被吃")

	# 稳定性：读档之后重新采集，两遍的每一段都应逐字一致（saved_at 除外）
	var d2 := SaveGame.collect(b.ctx, b.encounters)
	var same := true
	for k in ["campaign", "time", "player", "settlements", "parties"]:
		if JSON.stringify(d.get(k)) != JSON.stringify(d2.get(k)):
			same = false
			print("     差异段：%s" % k)
	_ok(same, "collect → apply → collect 稳定（每段逐字一致）")

	var again := SaveGame.apply(b.ctx, d, b.encounters, b.settlements)
	_ok(bool(again.get("ok", false)) and b.campaign.denars == 1234, "同一份存档再读一次仍然成立（幂等）")
	_dispose(a)
	_dispose(b)

# ---------------------------------------------------------------- 3. 三道门
func _check_doors() -> void:
	print("\n-- 3. 三道门：不合就拒绝，而且一个字段都不许写 --")
	var a := _make_world()
	_fill(a)
	a.campaign.denars = 555
	a.campaign.day = 6
	var d := SaveGame.collect(a.ctx, a.encounters)
	var b := _make_world()
	_fill(b)
	b.campaign.denars = 7
	b.campaign.day = 1
	(b.ctx.parties[0] as AIParty).troop_count = 11

	var cases: Array = []
	var v1 := d.duplicate(true)
	v1["version"] = 99
	cases.append([v1, "版本"])
	var v2 := d.duplicate(true)
	v2["magic"] = "not-our-save"
	cases.append([v2, "magic"])
	var v3 := d.duplicate(true)
	v3["map_seed"] = int(a.cfg.map_seed) + 1
	cases.append([v3, "种子"])
	var v4 := d.duplicate(true)
	(v4["settlements"] as Array).pop_back()
	cases.append([v4, "定居点数量"])
	var v5 := d.duplicate(true)
	(v5["parties"] as Array).append({"spawn_id": 999, "kind": 0, "troops": 10, "x": 100.0, "z": 100.0})
	cases.append([v5, "部队 id"])
	var v6 := d.duplicate(true)
	(v6["parties"] as Array).append(((v6["parties"] as Array)[0] as Dictionary).duplicate(true))
	cases.append([v6, "重复部队 id"])

	for case in cases:
		var bad: Dictionary = case[0]
		var label: String = case[1]
		var rr := SaveGame.apply(b.ctx, bad, b.encounters, b.settlements)
		_ok(not bool(rr.get("ok", false)), "拒绝%s不符的存档（%s）" % [label, str(rr.get("error", ""))])
		_eqi(b.campaign.denars, 7, "拒绝后钱袋没动（%s）" % label)
		_eqi(b.campaign.day, 1, "拒绝后日期没动（%s）" % label)
		_eqi((b.ctx.parties[0] as AIParty).troop_count, 11, "拒绝后部队兵力没动（%s）" % label)
	_ok(not bool(SaveGame.apply(b.ctx, {}, null, null).get("ok", false)), "空字典被拒绝")
	var ok_r := SaveGame.apply(b.ctx, d, b.encounters, b.settlements)
	_ok(bool(ok_r.get("ok", false)), "同一份存档换回正常内容就能读（门不是把好档挡住）")
	_eqi(b.campaign.denars, 555, "读档后钱袋 = 存档值")
	_dispose(a)
	_dispose(b)

# ---------------------------------------------------------------- 4. 坏数据
func _check_garbage() -> void:
	print("\n-- 4. 坏数据钳制（02 §3.4.1 设计含义【实证】：坏值不许漏进新状态）--")
	var a := _make_world()
	_fill(a)
	a.campaign.renown = 260                       # 编制上限 63，方便看「超编被钳」
	var d := SaveGame.collect(a.ctx, a.encounters)
	var bad := d.duplicate(true)
	(bad["campaign"] as Dictionary)["morale"] = 300
	(bad["campaign"] as Dictionary)["tier"] = 99
	(bad["campaign"] as Dictionary)["goods"] = {"0": 2, "999": 5}
	(bad["player"] as Dictionary)["troops"] = 99999
	(bad["player"] as Dictionary)["x"] = -50.0
	(bad["player"] as Dictionary)["z"] = 999999.0
	((bad["settlements"] as Array)[0] as Dictionary)["prosperity"] = -50
	((bad["settlements"] as Array)[0] as Dictionary)["volunteers"] = 999
	((bad["parties"] as Array)[0] as Dictionary)["troops"] = 0
	((bad["parties"] as Array)[0] as Dictionary)["kind"] = 7
	(bad["time"] as Dictionary)["speed_index"] = 9

	var b := _make_world()
	_fill(b)
	var r := SaveGame.apply(b.ctx, bad, b.encounters, b.settlements)
	_ok(bool(r.get("ok", false)), "坏值存档仍然可读（钳回合法值，而不是整档报废）")
	var warns: Array = r.get("warnings", [])
	_ok(warns.size() >= 9, "越界处都留了警告（%d 条）" % warns.size())
	_ok(_has_warn(warns, "morale"), "警告里有士气")
	_ok(_has_warn(warns, "tier"), "警告里有档次")
	_ok(_has_warn(warns, "player.troops"), "警告里有兵力")
	_ok(_has_warn(warns, "未知货物"), "警告里有未知货物 id")
	_ok(_has_warn(warns, "坐标越界"), "警告里有坐标越界")

	_eqi(b.campaign.morale, 100, "士气 300 → 100")
	_eqi(b.campaign.tier, b.campaign.rules.max_tier(), "档次 99 → 封顶")
	_eqi(b.campaign.goods_of(0), 2, "合法货物保留")
	_eqi(b.campaign.goods_total(), 2, "未知货物被丢弃（总数只剩合法的）")
	_eqi(b.campaign.troops(), b.campaign.capacity(), "兵力 99999 → 编制上限")
	_near(b.player.position.x, 0.0, "x = -50 → 夹到 0")
	_near(b.player.position.z, float(b.cfg.map_size), "z = 999999 → 夹到地图边")
	_eqi((b.data.settlements[0] as Settlement).prosperity, 0, "繁荣度 -50 → 0")
	_eqi((b.data.settlements[0] as Settlement).volunteers, (b.data.settlements[0] as Settlement).volunteers_cap,
		"志愿者 999 → 池子上限")
	_eqi((b.ctx.parties[0] as AIParty).troop_count, 1, "部队兵力 0 → 1（不许出现空部队）")
	_eqi((b.ctx.parties[0] as AIParty).kind, 2, "兵种 7 → 夹到最大枚举")
	_eqi(b.time.speed_index, b.time.speed_steps.size() - 1, "流速档位 9 → 最后一档")

	# 这条是整批的关键：坏值不许「粘住」—— 士气被钳到 100 之后，减 5 必须能降到 95
	# （只钳结果的老写法：300 − 5 → 295 → 钳到 100，那个坏值会一直粘在 100 上）
	b.campaign.add_morale(-5)
	_eqi(b.campaign.morale, 95, "**坏值不粘**：钳到 100 的士气再减 5 → 95（不是 100）")
	_dispose(a)
	_dispose(b)

# ---------------------------------------------------------------- 5. 修引用
func _check_repair() -> void:
	print("\n-- 5. 修引用（02 §6.5 设计含义【推断】：不许留下指向不存在对象的引用）--")
	var a := _make_world()
	_fill(a)
	a.campaign.denars = 321
	a.campaign.day = 9
	var d := SaveGame.collect(a.ctx, a.encounters)
	var b := _make_world()
	_fill(b)
	# 先把 B 弄成「处处都有活引用」的样子
	b.encounters.current = b.ctx.parties[0]
	b.settlements.current = b.data.settlements[0]
	b.settlements.qty = 10
	b.hud.open_flag = true
	b.hud.settlement_open = true
	b.player.moving = true
	b.player.has_target = true
	b.player.path = PackedVector3Array([Vector3(1, 0, 1), Vector3(2, 0, 2)])
	b.time.time_lock = true
	b.time.space_latched = true
	b.day_night.paused = false

	var r := SaveGame.apply(b.ctx, d, b.encounters, b.settlements)
	_ok(bool(r.get("ok", false)), "读档成功")
	_ok(b.encounters.current == null, "遭遇里的当前部队被清掉")
	_ok(b.settlements.current == null, "进城菜单的当前定居点被清掉")
	_eqi(b.settlements.qty, 1, "数量选择回到 1")
	_ok(not b.hud.open_flag, "遭遇面板被收起")
	_ok(not b.hud.settlement_open, "进城菜单面板被收起")
	_ok(not b.player.moving and not b.player.has_target and b.player.path.is_empty(),
		"玩家的旧寻路路径作废（部队就地停下）")
	_ok(not b.time.time_lock, "时间锁解开")
	_ok(not b.time.space_latched, "长按空格的闩锁复位")
	_ok(b.time.game_paused, "读档后世界时间是暂停的（与开局一致）")
	_eqi(b.time.state, TimeFlowController.State.FROZEN, "时间状态 = FROZEN")
	_ok(b.day_night.paused, "昼夜系统也跟着暂停")
	_eqi(b.day_night.day, 9, "昼夜的日 = 存档里的日")
	for p in b.ctx.parties:
		var ap := p as AIParty
		_ok(not ap.moving and not ap.chasing and ap.last_goal == Vector2(-1.0, -1.0),
			"部队 #%d 的追击与旧目标被复位（AI 内部计时不入存档）" % ap.spawn_id)
	_dispose(a)
	_dispose(b)

# ---------------------------------------------------------------- 6. 打掉的不复活
func _check_defeated() -> void:
	print("\n-- 6. 打掉的部队不复活（存档 = 世界上还有什么）--")
	var a := _make_world()
	_fill(a)
	var dead := a.ctx.parties[1] as AIParty
	a.ctx.parties.remove_at(1)
	dead.free()
	var d := SaveGame.collect(a.ctx, a.encounters)
	_eqi((d.get("parties", []) as Array).size(), 2, "打掉的那支不进存档")
	var b := _make_world()
	_fill(b)
	_eqi(b.ctx.parties.size(), 3, "B 世界里还是 3 支（生成期决定）")
	var r := SaveGame.apply(b.ctx, d, b.encounters, b.settlements)
	_ok(bool(r.get("ok", false)), "读档成功（打掉的不算「世界里缺失的部队」）")
	_eqi(b.ctx.parties.size(), 2, "读档后只剩 2 支")
	_eqi(int((r.get("info", {}) as Dictionary).get("parties_gone", -1)), 1, "移除了 1 支已经被打掉的")
	_eqi((b.ctx.parties[0] as AIParty).spawn_id, 0, "留下 #0")
	_eqi((b.ctx.parties[1] as AIParty).spawn_id, 2, "留下 #2（下标会错位，spawn_id 不会）")
	_dispose(a)
	_dispose(b)

# ---------------------------------------------------------------- 7. 文件层
func _check_file() -> void:
	print("\n-- 7. 文件层：写 → 回读 → 落地 → 写坏 → 清理 --")
	var slot := "_selftest"
	SaveGame.erase(slot)
	_ok(not SaveGame.exists(slot), "起点：测试槽没有文件")
	_ok(not bool(SaveGame.write(slot, {}).get("ok", false)), "空内容不许写（提前拒绝）")
	_ok(not bool(SaveGame.read(slot).get("ok", false)), "读不存在的槽：拒绝（%s）" % str(SaveGame.read(slot).get("error", "")))

	var a := _make_world()
	_fill(a)
	a.campaign.denars = 777
	a.campaign.day = 12
	a.campaign.morale = 58
	var d := SaveGame.collect(a.ctx, a.encounters)
	var w := SaveGame.write(slot, d)
	_ok(bool(w.get("ok", false)), "写盘成功（%s）" % str(w.get("error", "")))
	_ok(int(w.get("bytes", 0)) > 0, "字节数 > 0（%d）" % int(w.get("bytes", 0)))
	_ok(SaveGame.exists(slot), "文件存在")
	_ok(SaveGame.os_path_of(slot).ends_with("_selftest.json"), "os_path_of 给出真实路径：%s" % SaveGame.os_path_of(slot))

	var back := SaveGame.read(slot)
	_ok(bool(back.get("ok", false)), "回读成功")
	var d2 := back.get("data", {}) as Dictionary
	_ok(str(d2.get("magic", "")) == SaveGame.MAGIC, "回读后 magic 还在")
	_eqi(int((d2.get("campaign", {}) as Dictionary).get("denars", -1)), 777, "回读后钱袋一致")
	_eqi((d2.get("settlements", []) as Array).size(), 4, "回读后定居点行数一致")

	# 读出来的东西必须真能落地（而不只是「字段看着对」）
	var c := _make_world()
	_fill(c)
	var rc := SaveGame.apply(c.ctx, d2, c.encounters, c.settlements)
	_ok(bool(rc.get("ok", false)), "从文件读出来的存档能落地（%s）" % str(rc.get("error", "")))
	_eqi(c.campaign.denars, 777, "落地后钱袋")
	_eqi(c.campaign.day, 12, "落地后日期")
	_eqi(c.campaign.morale, 58, "落地后士气")

	# 写坏的文件
	var fh := FileAccess.open(SaveGame.path_of(slot), FileAccess.WRITE)
	fh.store_string("{ 这不是 JSON")
	fh.close()
	var badread := SaveGame.read(slot)
	_ok(not bool(badread.get("ok", false)), "写坏的存档被 read 拒绝：%s" % str(badread.get("error", "")))
	_ok(SaveGame.erase(slot), "清理测试存档")
	_ok(not SaveGame.exists(slot), "清理后文件不在")
	_ok(SaveGame.erase(slot), "erase 幂等（已经不在也返回 true）")
	_dispose(a)
	_dispose(c)