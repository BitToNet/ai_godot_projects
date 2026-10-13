## =============================================================================
##  settlement_check —— 城镇交互（补给 / 招募 / 贸易 / 驻军）的定式自检
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/settlement_check.gd
##
##  为什么需要它：进城菜单是一条**闭环价值链**（钱 → 补给 / 兵 → 打赢 → 战利品 →
##  钱），而且每一环都有「边界情形」：钱不够、编制满了、池子里没人、城里没兵、
##  卖的东西自己没有。这些分支在门禁的 900 帧主场景里一个都走不到，所以必须有一个
##  不建世界、不建 UI 的入口直接把它们跑一遍 —— 所以 SettlementSystem 一行 UI 节点
##  都不碰，菜单只回过一个「条目数组」给 HUD 去画。
##
##  断言只锁「公式形状与边界」，不锁平衡结果 —— 价格要调就改 EconomyRules。
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
	var player: PlayerParty
	var time: TimeFlowController
	var ctx: WorldContext
	var sys: SettlementSystem
	var village: Settlement
	var town: Settlement
	var castle: Settlement

func _make_world(prosperity_v: int = 20, prosperity_t: int = 80) -> Fake:
	var f := Fake.new()
	f.cfg = MapConfig.new()
	f.data = MapData.new()
	f.data.cfg = f.cfg
	f.economy = EconomyRules.create()

	f.village = _mk(0, "测试村", Settlement.Kind.VILLAGE, Vector2(100, 100), prosperity_v)
	f.village.volunteers = 5
	f.town = _mk(1, "测试镇", Settlement.Kind.TOWN, Vector2(300, 300), prosperity_t)
	f.town.volunteers = 8
	f.castle = _mk(2, "测试堡", Settlement.Kind.CASTLE, Vector2(500, 500), 60)
	var arr: Array[Settlement] = [f.village, f.town, f.castle]
	f.data.settlements = arr

	f.player = PlayerParty.new()
	f.player.troop_count = GameState.PLAYER_START_TROOPS
	f.campaign = CampaignState.new()
	f.campaign.setup(f.economy, f.player)
	f.time = TimeFlowController.new()
	f.time.player = f.player
	f.ctx = WorldContext.new()
	f.ctx.cfg = f.cfg
	f.ctx.data = f.data
	f.ctx.economy = f.economy
	f.ctx.campaign = f.campaign
	f.ctx.player = f.player
	f.ctx.time = f.time
	f.sys = SettlementSystem.new()
	f.sys.ctx = f.ctx
	return f

func _mk(id: int, nm: String, kind: int, pos: Vector2, prosperity: int) -> Settlement:
	var s := Settlement.new()
	s.id = id
	s.name = nm
	s.kind = kind
	s.pos = pos
	s.prosperity = prosperity
	s.volunteers_cap = EconomyRules.create().volunteer_cap(kind)
	var bias: Array[int] = [0, 0, 0, 0]
	s.good_bias = bias
	return s

func _put(f: Fake, s: Settlement) -> void:
	f.player.position = Vector3(s.pos.x, 0.0, s.pos.y)

# ---------------------------------------------------------------- 主流程
func _run() -> void:
	var f := _make_world()
	print("[城镇] 定式自检（不跑地图生成、不建 UI）")

	_check_services(f)
	_check_prices(f)
	_check_supply(f)
	_check_recruit(f)
	_check_trade(f)
	_check_garrison(f)
	_check_menu(f)
	_check_open_close(f)
	_check_refill(f)
	_check_assign(f)

	print("")
	f.player.free()
	f.sys = null
	f.ctx = null

	if _fails.is_empty():
		print("PASS：城镇交互定式全部正常（%d 项断言）" % _total)
		quit(0)
	else:
		print("FAIL：%d/%d 项断言未通过 —— %s" % [_fails.size(), _total, "; ".join(_fails)])
		quit(1)

# ---------------------------------------------------------------- 1. 服务项与位置
func _check_services(f: Fake) -> void:
	print("\n-- 服务项 / 位置 --")
	var c := f.castle.service_ids()
	var v := f.village.service_ids()
	var t := f.town.service_ids()
	_ok(not c.has("recruit") and not c.has("trade") and c.has("garrison") and c.has("supply"),
		"城堡只办事不招兵不赶集：%s" % [c])
	_ok(not v.has("trade") and not v.has("garrison") and v.has("recruit") and v.has("supply"),
		"村庄能买粮能招兵，没有市场和驻军：%s" % [v])
	_ok(t.has("supply") and t.has("recruit") and t.has("trade") and t.has("garrison"),
		"城镇四样都有：%s" % [t])
	_ok(t[t.size() - 1] == "leave", "「离开」永远是最后一条")
	_ok(f.town.has_service("trade") and not f.town.has_service("nothing"), "has_service 判定正确")

	_ok(f.village.interact_radius() > f.village.radius, "交互半径大于建筑半径（能站在城墙外进城）")
	_put(f, f.village)
	_ok(f.sys.nearby() == f.village, "站在村里 → 认出村庄")
	_ok(f.sys.can_interact(), "站在村里 → 可以交互")
	f.player.position = Vector3(100 + f.village.radius + 6.5, 0.0, 100)
	_ok(f.sys.nearby() == null, "刚出交互半径 → 认不到定居点")
	_ok(not f.sys.can_interact(), "不在任何定居点旁 → 不能交互")
	f.player.position = Vector3(100, 0.0, 100)
	_ok(f.sys.nearby() == f.village, "回到村里 → 又认得出")

	_ok(f.village.prosperity_name() == "萧条", "繁荣 20 → 萧条")
	var s0 := Settlement.new()
	s0.prosperity = 0
	var s9 := Settlement.new()
	s9.prosperity = 99
	_ok(s0.prosperity_name() == "荒废" and s9.prosperity_name() == "繁荣",
		"繁荣度五档：0 → %s，99 → %s" % [s0.prosperity_name(), s9.prosperity_name()])

# ---------------------------------------------------------------- 2. 价格模型
func _check_prices(f: Fake) -> void:
	print("\n-- 价格模型 --")
	var r := f.economy
	_ok(r.prosperity_factor(0) == 130 and r.prosperity_factor(50) == 100
		and r.prosperity_factor(100) == 70,
		"繁荣度系数：0 → %d%%，50 → %d%%，100 → %d%%" % [
			r.prosperity_factor(0), r.prosperity_factor(50), r.prosperity_factor(100)])
	_ok(r.prosperity_factor(-5) == 130 and r.prosperity_factor(300) == 70, "繁荣度系数钳位生效")
	_ok(r.market_buy_price(8, 50) == 8, "基准价 8 在繁荣 50 处就是 8 金")
	_ok(r.market_buy_price(8, 0) == 10 and r.market_buy_price(8, 100) == 5,
		"同一件货：荒废地 10 金、繁荣地 5 金")
	_ok(r.market_sell_price(8, 50) == 4, "卖价 = 买价 × 60%%（8 → %d）" % r.market_sell_price(8, 50))
	_ok(r.market_buy_price(1, 100) >= 1, "再便宜也不低于 1 金")
	_ok(r.market_buy_price(8, 50, 15) == 9 and r.market_buy_price(8, 50, -15) == 6,
		"本地价差 ±15%% 生效（9 / 6）")
	_ok(r.supply_price(50) == 5 and r.supply_price(0) == 6,
		"补给基准 5 金：平常 5、荒废 6")
	# 贸易路线的存在性：在繁荣地买入、拉到荒废地卖出必须赚钱，否则贸易就是个摆设
	var buy := r.market_buy_price(8, 100)
	var sell := r.market_sell_price(8, 0)
	_ok(sell > buy, "低买高卖有利可图（繁荣地 %d 金买 → 荒废地 %d 金卖）" % [buy, sell])

# ---------------------------------------------------------------- 3. 买补给
func _check_supply(f: Fake) -> void:
	print("\n-- 买补给 --")
	f.sys.open(f.village)
	var price := f.economy.supply_price(f.village.prosperity)
	var denars0 := f.campaign.denars
	var sup0 := f.campaign.supplies
	var got := f.sys.buy_supply(5)
	_ok(got == 5, "买 5 件到手 %d 件" % got)
	_ok(f.campaign.supplies == sup0 + 5, "补给 +5（%d → %d）" % [sup0, f.campaign.supplies])
	_ok(f.campaign.denars == denars0 - price * 5,
		"扣钱 %d 金（%d → %d）" % [price * 5, denars0, f.campaign.denars])

	# 买不起就少买几件（自动缩量，而不是直接失败）
	f.campaign.denars = price * 2 + 1
	var got2 := f.sys.buy_supply(10)
	_ok(got2 == 2, "只有 2 件的钱 → 买 %d 件（自动缩量）" % got2)
	_ok(f.campaign.denars == 1, "缩量后剩下的零钱 %d 金" % f.campaign.denars)
	_ok(f.sys.buy_supply(1) == 0, "一件都买不起时返回 0")
	f.sys.close()

# ---------------------------------------------------------------- 4. 招募
func _check_recruit(f: Fake) -> void:
	print("\n-- 招募（村庄 10 金/人） --")
	f.campaign.denars = 400
	f.player.troop_count = 37
	f.village.volunteers = 5
	f.sys.open(f.village)
	var money0 := f.campaign.denars
	var got := f.sys.recruit(3)
	_ok(got == 3, "招到 %d 人" % got)
	_ok(f.campaign.denars == money0 - 30, "10 金/人：扣 %d 金" % (money0 - f.campaign.denars))
	_ok(f.campaign.troops() == 40, "兵力 %d 人" % f.campaign.troops())
	_ok(f.village.volunteers == 2, "志愿者池按人数写回扣减（5 → %d，不是清零）" % f.village.volunteers)

	var got2 := f.sys.recruit(10)
	_ok(got2 == 2, "池子里只剩 2 人 → 只能招 %d 人" % got2)
	_ok(f.village.volunteers == 0, "招空后池子为 0")
	_ok(f.sys.recruit(1) == 0, "没有志愿者 → 招不到")

	# 编制上限：把兵力顶到编制
	f.village.volunteers = 5
	f.player.troop_count = f.campaign.capacity()
	_ok(f.campaign.free_capacity() == 0, "兵力顶到编制（%d）" % f.campaign.capacity())
	_ok(f.sys.recruit(1) == 0, "编制满了 → 招不到")
	var row := _find(f.sys.menu_entries(), "recruit")
	_ok(not bool(row.get("enabled", true)) and String(row.get("hint", "")).contains("编制已满"),
		"菜单把「编制已满」写进灰化原因：%s" % row.get("hint", ""))

	# 没钱
	f.player.troop_count = 37
	f.village.volunteers = 5
	f.campaign.denars = 5
	_ok(f.sys.recruit(1) == 0, "钱不够 10 金 → 招不到")
	var row2 := _find(f.sys.menu_entries(), "recruit")
	_ok(String(row2.get("hint", "")).contains("钱不够"), "菜单提示「钱不够」：%s" % row2.get("hint", ""))
	f.sys.close()

# ---------------------------------------------------------------- 5. 贸易
func _check_trade(f: Fake) -> void:
	print("\n-- 贸易（低买高卖） --")
	f.campaign.denars = 400
	f.campaign.goods.clear()
	f.player.troop_count = 37
	var gid := 0
	var town_price := f.economy.market_buy_price(f.economy.good_base(gid), f.town.prosperity)
	f.sys.open(f.town)
	var got := f.sys.trade(gid, 10, true)
	_ok(got == 10, "在城镇买入 %d 件%s" % [got, f.economy.good_name(gid)])
	_ok(f.campaign.goods_of(gid) == 10, "背包里有 %d 件" % f.campaign.goods_of(gid))
	_ok(f.campaign.denars == 400 - town_price * 10, "买入扣钱（单价 %d 金）" % town_price)
	_ok(f.sys.trade(gid, 99, false) == 10, "卖出超过持有 → 只卖出手里的 10 件")
	_ok(f.campaign.goods_of(gid) == 0, "卖光后背包里没有这件货（不残留 0）")

	# 一次完整的贸易路线：繁荣城镇买入 → 荒废村庄卖出
	f.campaign.denars = 400
	f.sys.open(f.town)
	f.sys.trade(gid, 10, true)
	var after_buy := f.campaign.denars
	f.sys.close()
	f.sys.open(f.village)
	f.sys.trade(gid, 10, false)
	var after_sell := f.campaign.denars
	_ok(after_sell > after_buy, "跑一趟赚到钱：买入后 %d → 卖出后 %d（+%d）" % [
		after_buy, after_sell, after_sell - after_buy])
	_ok(f.campaign.take_goods(gid, 1) == 0, "没有存货时取不走货")

	f.campaign.denars = 3
	_ok(f.sys.trade(gid, 1, true) == 0, "钱不够 → 买不进")
	f.sys.close()
	f.sys.open(f.town)          # 「卖出」那一行只有城镇 / 市场才有，村庄菜单里没有
	var row := _find(f.sys.menu_entries(), "trade_sell")
	_ok(not bool(row.get("enabled", true)), "没货时「卖出」行被灰掉：%s" % row.get("hint", ""))
	f.sys.close()

# ---------------------------------------------------------------- 6. 驻军
func _check_garrison(f: Fake) -> void:
	print("\n-- 驻军（存兵省军费） --")
	f.campaign.denars = 400
	f.player.troop_count = 37
	f.castle.garrison = 12
	var wage_before := f.campaign.wage()
	f.sys.open(f.castle)
	var moved := f.sys.garrison_deposit(10)
	_ok(moved == 10, "存入 %d 人" % moved)
	_ok(f.campaign.troops() == 27, "部队剩 %d 人" % f.campaign.troops())
	_ok(f.castle.garrison == 22, "城内共 %d 人" % f.castle.garrison)
	_ok(f.campaign.wage() < wage_before, "存兵后周薪下降（%d → %d）—— 这才是驻军的用处" % [
		wage_before, f.campaign.wage()])

	var moved2 := f.sys.garrison_deposit(100)
	_ok(f.campaign.troops() == 5, "怎么存都至少留 5 人看家（当前 %d）" % f.campaign.troops())
	_ok(moved2 == 22, "一次存走 %d 人" % moved2)

	var got := f.sys.garrison_withdraw(5)
	_ok(got == 5, "取回 %d 人" % got)
	_ok(f.castle.garrison == 39, "城内剩 %d 人" % f.castle.garrison)

	# 编制满了就取不回来
	f.player.troop_count = f.campaign.capacity()
	_ok(f.sys.garrison_withdraw(5) == 0, "编制满了 → 取不回来")
	var row := _find(f.sys.menu_entries(), "garrison_withdraw")
	_ok(String(row.get("hint", "")).contains("编制已满"), "菜单提示「编制已满」：%s" % row.get("hint", ""))
	f.player.troop_count = 30
	f.castle.garrison = 0
	_ok(f.sys.garrison_withdraw(5) == 0, "城里没有兵 → 取不到")
	f.sys.close()

# ---------------------------------------------------------------- 7. 菜单
func _check_menu(f: Fake) -> void:
	print("\n-- 菜单条目（数据驱动） --")
	f.sys.open(f.village)
	var rows := f.sys.menu_entries()
	_ok(rows.size() == 4, "村庄 %d 行（补给 / 招募 / 离开 + 数量）" % rows.size())
	_ok(_has_all_keys(rows), "每行都有 id / label / enabled / hint 四个键")
	_ok(rows[rows.size() - 1].get("id", "") == "qty", "数量行在最后（离开之后）")
	f.sys.close()
	f.sys.open(f.town)
	_ok(f.sys.menu_entries().size() == 9, "城镇 %d 行（贸易 3 行 + 驻军 2 行）" % f.sys.menu_entries().size())
	var q0 := f.sys.qty
	f.sys.resolve("qty")
	var q1 := f.sys.qty
	f.sys.resolve("qty")
	var q2 := f.sys.qty
	f.sys.resolve("qty")
	_ok(q0 == 1 and q1 == 5 and q2 == 10 and f.sys.qty == 1,
		"数量循环 1 → 5 → 10 → 1（实得 %d/%d/%d/%d）" % [q0, q1, q2, f.sys.qty])
	var g0 := f.sys.trade_good
	f.sys.resolve("good_next")
	var g1 := f.sys.trade_good
	for i in f.economy.good_count() - 1:
		f.sys.resolve("good_next")
	_ok(g1 != g0 and f.sys.trade_good == g0, "货物切换会回绕（%d → %d → … → %d）" % [g0, g1, f.sys.trade_good])
	f.sys.resolve("不存在的动作")
	_ok(f.sys.current == f.town, "未知动作被忽略，菜单不关")
	f.sys.close()
	f.sys.open(f.castle)
	_ok(f.sys.menu_entries().size() == 5, "城堡 %d 行（补给 / 存 / 取 / 离开 + 数量）" % f.sys.menu_entries().size())
	f.sys.resolve("leave")
	_ok(f.sys.current == null, "「离开」把菜单关掉")

	# 钱为 0 时买补给那一行必须灰掉且说得出原因
	f.campaign.denars = 0
	f.sys.open(f.village)
	var row := _find(f.sys.menu_entries(), "supply")
	_ok(not bool(row.get("enabled", true)) and String(row.get("hint", "")).contains("钱不够"),
		"钱为 0 时买补给灰掉并说明原因：%s" % row.get("hint", ""))
	f.sys.close()

# ---------------------------------------------------------------- 8. 开 / 关与时间锁
func _check_open_close(f: Fake) -> void:
	print("\n-- 进城 / 出城 --")
	f.campaign.denars = 400
	_put(f, f.town)
	# 这里不调 set_destination —— 那个要寻路栅格（假世界里没有），直接立起「行军中」标志
	f.player.moving = true
	_ok(f.player.moving, "先让部队在行军")
	_ok(f.sys.open(), "在城镇旁可以不指定参数直接进城（自动取最近）")
	_ok(f.sys.current == f.town, "当前定居点是城镇")
	_ok(not f.player.moving, "进城打断行军（原地停下）")
	_ok(f.time.time_lock, "菜单开着时世界时间被锁住")
	_ok(not f.sys.open(f.village), "已经在菜单里 → 不再开第二个")
	_ok(f.sys.status_line().contains(f.town.name), "状态行有地名：%s" % f.sys.status_line())
	f.sys.close()
	_ok(f.sys.current == null, "出城后没有当前定居点")
	_ok(not f.time.time_lock, "出城后解锁时间")
	f.sys.close()
	_ok(f.sys.current == null and not f.time.time_lock,
		"重复出城是空操作（close 对 null 当前点直接返回）")

	f.sys.enabled = false
	_ok(not f.sys.open(f.town), "关掉系统后进不了城（截图 / 调试用）")
	_ok(not f.sys.can_interact(), "关掉系统后不能交互")
	f.sys.enabled = true

# ---------------------------------------------------------------- 9. 志愿者回流
func _check_refill(f: Fake) -> void:
	print("\n-- 志愿者回流 --")
	f.village.volunteers = 0
	f.village.volunteers_cap = 12
	f.town.volunteers = 30
	f.town.volunteers_cap = 20
	f.sys.on_day_changed(1)
	_ok(f.village.volunteers == 0, "第 1 天不是回流日（每 2 天 +1）")
	f.sys.on_day_changed(2)
	_ok(f.village.volunteers == 1, "第 2 天村庄 +1（%d）" % f.village.volunteers)
	f.sys.on_day_changed(4)
	_ok(f.village.volunteers == 2, "第 4 天再 +1（%d）" % f.village.volunteers)
	f.village.volunteers = 12
	f.sys.on_day_changed(6)
	_ok(f.village.volunteers == 12, "到上限不再涨（%d/%d）" % [f.village.volunteers, f.village.volunteers_cap])
	_ok(f.town.volunteers == 20, "超出上限的城镇被压回上限（%d）" % f.town.volunteers)

# ---------------------------------------------------------------- 10. 生成期的环境赋值
func _check_assign(f: Fake) -> void:
	print("\n-- 生成期赋值（繁荣度 / 志愿者 / 货物价差） --")
	var cfg := MapConfig.new()
	var data := MapData.new()
	data.cfg = cfg
	var arr: Array[Settlement] = []
	for i in 12:
		var s := Settlement.new()
		s.id = i
		s.name = "S%d" % i
		s.kind = [Settlement.Kind.VILLAGE, Settlement.Kind.TOWN, Settlement.Kind.CASTLE][i % 3]
		s.pos = Vector2(64 + i * 48, 128 + (i % 5) * 96)
		arr.append(s)
	data.settlements = arr
	var economy := EconomyRules.create()
	SettlementSystem.assign_environment(cfg, data, economy)
	var ok_range := true
	var ok_cap := true
	var ok_bias := true
	for s in data.settlements:
		if s.prosperity < 0 or s.prosperity > 100:
			ok_range = false
		if s.volunteers != s.volunteers_cap or s.volunteers_cap != economy.volunteer_cap(s.kind):
			ok_cap = false
		if s.good_bias.size() != economy.good_count():
			ok_bias = false
		for b in s.good_bias:
			if b < -15 or b > 15:
				ok_bias = false
	_ok(ok_range, "繁荣度都落在 [0,100]")
	_ok(ok_cap, "志愿者池 = 类型上限（城堡 0 / 村庄 %d / 城镇 %d）" % [
		economy.volunteer_cap_village, economy.volunteer_cap_town])
	_ok(ok_bias, "每种货都有 ±15%% 以内的本地价差")
	var snap := _snapshot(data)
	SettlementSystem.assign_environment(cfg, data, economy)
	_ok(_snapshot(data) == snap, "同种子重复赋值结果一致（确定性）")
	var cfg2 := MapConfig.new()
	cfg2.map_seed = 20260101
	var data2 := MapData.new()
	data2.cfg = cfg2
	var arr2: Array[Settlement] = []
	for s in arr:
		var s2 := Settlement.new()
		s2.id = s.id
		s2.kind = s.kind
		arr2.append(s2)
	data2.settlements = arr2
	SettlementSystem.assign_environment(cfg2, data2, economy)
	_ok(_snapshot(data2) != snap, "换种子后繁荣度 / 价差整体不同（地图可复现但各不相同）")
	print("     城堡的志愿者上限是 %d（不招兵的地方池子为空）" % economy.volunteer_cap(Settlement.Kind.CASTLE))

# ---------------------------------------------------------------- 小工具
func _find(rows: Array[Dictionary], id: String) -> Dictionary:
	for r in rows:
		if String(r.get("id", "")) == id:
			return r
	return {}

func _has_all_keys(rows: Array[Dictionary]) -> bool:
	for r in rows:
		if not (r.has("id") and r.has("label") and r.has("enabled") and r.has("hint")):
			return false
	return true

func _snapshot(data: MapData) -> String:
	var parts := PackedStringArray()
	for s in data.settlements:
		parts.append("%d:%d:%d:%s" % [s.id, s.prosperity, s.volunteers, str(s.good_bias)])
	return "|".join(parts)