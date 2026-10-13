## =============================================================================
##  SettlementSystem —— 进城办事（补给 / 招募 / 贸易 / 驻军）
##
##  与 EncounterSystem 的分工：那个管「路上撞见部队」，这个管「进定居点办事」。
##  两者的形状刻意保持一致，读一个就懂另一个：
##    · open()          → 时间 lock()（菜单开着时世界暂停）+ 关相机 + 抛 opened
##    · menu_entries()  → 菜单内容（数据驱动），HUD 只照着画，不判断谁能做什么
##    · resolve(action) → 每个条目的效果，所有收支都走 CampaignState
##    · close()         → 解锁时间 + 把地图操作还给玩家
##
##  本类**不碰任何 UI 节点**：菜单是「条目数组」，HUD 自己决定怎么画。
##  所以 tools/settlement_check.gd 可以在没有窗口、没有场景的情况下把
##  「买粮 / 招兵 / 低买高卖 / 存兵」全部跑一遍并断言。
##
##  参考 G:\warband_docs（外部资料，不在本仓库内）的骑砍反编译文档：
##   · 村庄招募 min(志愿者池, 编制余位, 金/10)（单价 10 金/人）；池子按招到的人数
##     **写回扣减**，原文是 each −1 而不是清零 —— 01 §2.7
##   · 服务项按类型分：城镇 5 项 / 城堡 1 项（管家）/ 村庄 1 项（长老）—— 05 §?
##   · 价格按繁荣度归一化；买价与卖价不对称（商人吃差价）—— 01 §1.7 / 02 §6.5
##  原文【未解】：菜单条目清单、志愿者刷新率、驻军来源、价格脚本频率 —— 这些都按
##  本地化设计实现，逐条记在 docs/ROADMAP.md 第十节，不假装是实证。
## =============================================================================
class_name SettlementSystem
extends RefCounted

## 菜单内容变了（HUD 重画按钮文字 / 灰化状态）
signal menu_changed
## 进城（HUD 打开菜单面板）
signal opened(settlement: Settlement)
## 出城（HUD 关闭菜单面板）
signal closed

var ctx: WorldContext
var current: Settlement = null      ## 正在办事的定居点（null = 不在菜单里）
var qty: int = 1                    ## 当前「数量」选择
var qty_steps: Array[int] = [1, 5, 10]
var trade_good: int = 0             ## 当前选中的货物 id
var enabled: bool = true            ## 调试 / 截图时可关掉

# =============================================================== 位置判定
## 玩家脚下（或紧邻）的定居点：进城的入口条件
func nearby() -> Settlement:
	if ctx == null or ctx.player == null or ctx.data == null:
		return null
	var best: Settlement = null
	var bd := 1e20
	var p := Vector2(ctx.player.position.x, ctx.player.position.z)
	for s in ctx.data.settlements:
		var d := s.pos.distance_squared_to(p)
		var r := s.interact_radius()
		if d <= r * r and d < bd:
			bd = d
			best = s
	return best

func can_interact() -> bool:
	return enabled and current == null and nearby() != null

# =============================================================== 开 / 关
## 开菜单。s 省略时取脚下最近的那个。已经开着 / 附近没有定居点 → 返回 false。
func open(s: Settlement = null) -> bool:
	if ctx == null or not enabled or current != null:
		return false
	if s == null:
		s = nearby()
	if s == null:
		return false
	current = s
	qty = 1
	trade_good = clampi(trade_good, 0, maxi(0, ctx.economy.good_count() - 1))
	# 进城 = 停下：与遭遇一致（原文进城也会打断行军）
	if ctx.player.moving:
		ctx.player.halt()
	ctx.time.lock()                 # 菜单开着时世界暂停，空格不生效
	ctx.set_camera_active(false)    # 方向键留给菜单，不拖镜头
	opened.emit(s)
	return true

func close() -> void:
	if current == null:
		return
	current = null
	if ctx != null:
		ctx.set_camera_active(true)
		ctx.time.unlock()           # 出城后按原状态重新裁决时间流动
	closed.emit()

# =============================================================== 菜单（数据驱动）
## 菜单条目：{id, label, enabled, hint}。灰掉的条目也要给 hint ——
## 玩家必须看得见「为什么不能点」（钱不够 / 编制满 / 池子里没人）。
func menu_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if current == null:
		return out
	for sid in current.service_ids():
		match sid:
			"supply":
				out.append(_entry_supply())
			"recruit":
				out.append(_entry_recruit())
			"trade":
				out.append(_entry_good())
				out.append(_entry_trade(true))
				out.append(_entry_trade(false))
			"garrison":
				out.append(_entry_garrison(true))
				out.append(_entry_garrison(false))
			"leave":
				out.append({"id": "leave", "label": "离 开", "enabled": true, "hint": "回到大地图"})
	if out.size() > 1:
		out.append(_entry_qty())
	return out

func _entry_supply() -> Dictionary:
	var c := ctx.campaign
	var unit := ctx.economy.supply_price(current.prosperity)
	var total := unit * qty
	var hint := "现有 %d 件 · 每天吃 %d 件" % [
		c.supplies, ctx.economy.supply_per_day(maxi(c.troops(), 1))]
	if c.denars < total:
		hint = "钱不够（需 %d 金）" % total
	return {"id": "supply", "label": "买补给 ×%d（%d 金）" % [qty, total],
		"enabled": c.denars >= total, "hint": hint}

func _entry_recruit() -> Dictionary:
	var c := ctx.campaign
	var per := ctx.economy.recruit_cost_per_man
	var free := c.free_capacity()
	var hint := "可招 %d 人（%d 金/人）" % [current.volunteers, per]
	if current.volunteers <= 0:
		hint = "没有志愿者（每 %d 天回 1 人）" % maxi(1, ctx.economy.volunteer_refill_days)
	elif free <= 0:
		hint = "编制已满（%d/%d）" % [c.troops(), c.capacity()]
	elif c.denars < per:
		hint = "钱不够（%d 金/人）" % per
	var ok := current.volunteers > 0 and free > 0 and c.denars >= per
	return {"id": "recruit", "label": "招 募（%d 金/人）" % per, "enabled": ok, "hint": hint}

func _entry_good() -> Dictionary:
	var gid := clampi(trade_good, 0, maxi(0, ctx.economy.good_count() - 1))
	return {"id": "good_next",
		"label": "货物：%s（持有 %d）" % [ctx.economy.good_name(gid), ctx.campaign.goods_of(gid)],
		"enabled": ctx.economy.good_count() > 1, "hint": "换一种货物"}

func _entry_trade(is_buy: bool) -> Dictionary:
	var r := ctx.economy
	var gid := clampi(trade_good, 0, maxi(0, r.good_count() - 1))
	var unit := 0
	if is_buy:
		unit = r.market_buy_price(r.good_base(gid), current.prosperity, _bias(gid))
	else:
		unit = r.market_sell_price(r.good_base(gid), current.prosperity, _bias(gid))
	var n := qty
	if is_buy:
		var can := ctx.campaign.denars / maxi(unit, 1)
		var ok := can >= 1
		var hint := "单价 %d 金 · 钱够买 %d 件" % [unit, can]
		if not ok:
			hint = "钱不够（单价 %d 金）" % unit
		return {"id": "trade", "label": "买入 ×%d（%d 金）" % [qty, unit * n],
			"enabled": ok, "hint": hint}
	var have := ctx.campaign.goods_of(gid)
	var hint2 := "单价 %d 金 · 持有 %d 件" % [unit, have]
	if have <= 0:
		hint2 = "没有可卖的%s（单价 %d 金）" % [r.good_name(gid), unit]
	return {"id": "trade_sell", "label": "卖出 ×%d（得 %d 金）" % [qty, unit * n],
		"enabled": have > 0, "hint": hint2}

func _entry_garrison(is_deposit: bool) -> Dictionary:
	var c := ctx.campaign
	if is_deposit:
		var keep := maxi(0, c.troops() - 5)     # 至少留 5 人看家（与战斗损失同一个下限）
		var hint := "城内 %d 人 · 可存 %d 人（至少留 5 人）" % [current.garrison, keep]
		return {"id": "garrison", "label": "驻军存入 ×%d" % qty,
			"enabled": keep > 0, "hint": hint}
	var room := c.free_capacity()
	var hint2 := "城内 %d 人 · 编制余位 %d" % [current.garrison, room]
	if current.garrison <= 0:
		hint2 = "城里没有你的兵"
	elif room <= 0:
		hint2 = "编制已满（%d/%d）" % [c.troops(), c.capacity()]
	return {"id": "garrison_withdraw", "label": "驻军取出 ×%d" % qty,
		"enabled": current.garrison > 0 and room > 0, "hint": hint2}

func _entry_qty() -> Dictionary:
	var next := qty_steps[(qty_steps.find(qty) + 1) % qty_steps.size()]
	return {"id": "qty", "label": "数量 ×%d（点一下变 ×%d）" % [qty, next], "enabled": true,
		"hint": "影响买补给 / 招募 / 买卖货物 / 驻军"}

## 菜单回调（HUD.settlement_action → 这里）。未知动作忽略。
func resolve(action: String) -> void:
	if current == null:
		return
	match action:
		"leave", "close":
			close()
			return
		"supply":
			buy_supply(qty)
		"recruit":
			recruit(qty)
		"good_next":
			trade_good = (trade_good + 1) % maxi(1, ctx.economy.good_count())
		"trade":
			trade(trade_good, qty, true)
		"trade_sell":
			trade(trade_good, qty, false)
		"garrison":
			garrison_deposit(qty)
		"garrison_withdraw":
			garrison_withdraw(qty)
		"qty":
			qty = qty_steps[(qty_steps.find(qty) + 1) % qty_steps.size()]
		_:
			return
	menu_changed.emit()

# =============================================================== 具体交易
## 买补给：单价按繁荣度浮动，买不起就自动少买几件（返回实际件数）
func buy_supply(count: int) -> int:
	if current == null:
		return 0
	var unit := ctx.economy.supply_price(current.prosperity)
	if unit <= 0:
		return 0
	var n := mini(count, ctx.campaign.denars / unit)
	if n <= 0:
		return 0
	if not ctx.campaign.spend(unit * n):
		return 0
	ctx.campaign.add_supplies(n)
	_report("买了 %d 件补给（%d 金）" % [n, unit * n])
	return n

## 招募：照搬 01 §2.7 的 min(志愿者池, 编制余位, 金/人)，
## 志愿者池按**实际招到的人数**扣减（原文 each −1 的语义）。
## CampaignState.recruit 已经负责「编制 + 钱」两重钳制，这里只管池子。
func recruit(count: int) -> int:
	if current == null:
		return 0
	var n := mini(count, current.volunteers)
	if n <= 0:
		return 0
	var got := ctx.campaign.recruit(n, ctx.economy.recruit_cost_per_man)
	if got <= 0:
		return 0
	current.volunteers = maxi(0, current.volunteers - got)
	_report("招募了 %d 人（%d 金）" % [got, got * ctx.economy.recruit_cost_per_man])
	return got

## 买卖货物。is_buy = true 从定居点买入，false 卖给它。
## 价格 = 基准 × 繁荣度系数 × (100 + 本地价差)/100；卖价再乘 60%。
## 于是「在繁荣的城镇买入、拉到荒废的村庄卖出」是有利可图的 —— 这就是贸易路线。
func trade(gid: int, count: int, is_buy: bool) -> int:
	if current == null or count <= 0:
		return 0
	var r := ctx.economy
	if gid < 0 or gid >= r.good_count():
		return 0
	var bias := _bias(gid)
	if is_buy:
		var unit := r.market_buy_price(r.good_base(gid), current.prosperity, bias)
		var n := mini(count, ctx.campaign.denars / maxi(unit, 1))
		if n <= 0:
			return 0
		if not ctx.campaign.spend(unit * n):
			return 0
		ctx.campaign.add_goods(gid, n)
		_report("买入 %d 件%s（%d 金）" % [n, r.good_name(gid), unit * n])
		return n
	var have := ctx.campaign.goods_of(gid)
	var sell := mini(count, have)
	if sell <= 0:
		return 0
	var price := r.market_sell_price(r.good_base(gid), current.prosperity, bias)
	var taken := ctx.campaign.take_goods(gid, sell)
	if taken <= 0:
		return 0
	ctx.campaign.earn(price * taken)
	_report("卖出 %d 件%s（得 %d 金）" % [taken, r.good_name(gid), price * taken])
	return taken

## 驻军存入：把部队留在城里。意义在于**工资按人数算** —— 养不起时先把人存起来。
## 原文的驻军来源【未解】，所以这里只做「存 / 取」，驻军暂不参与战斗（第五轮再说）。
## 复用 lose_troops 的下限：无论怎么存，队伍里至少留 5 人。
func garrison_deposit(count: int) -> int:
	if current == null or count <= 0:
		return 0
	var moved := ctx.campaign.lose_troops(count)
	if moved <= 0:
		return 0
	current.garrison += moved
	_report("驻军存入 %d 人（城内共 %d 人）" % [moved, current.garrison])
	return moved

## 驻军取出：免费（是自家的兵），但仍受编制余位限制
func garrison_withdraw(count: int) -> int:
	if current == null or count <= 0:
		return 0
	var take := mini(count, current.garrison)
	if take <= 0:
		return 0
	var got := ctx.campaign.take_troops(take)
	if got <= 0:
		return 0
	current.garrison = maxi(0, current.garrison - got)
	_report("驻军取出 %d 人（城内剩 %d 人）" % [got, current.garrison])
	return got

## 状态行（菜单标题下面那一行）
func status_line() -> String:
	if current == null:
		return ""
	return "%s · %s · 繁荣 %d（%s）· 驻军 %d 人 · 志愿者 %d 人" % [
		current.name, current.kind_name(), current.prosperity, current.prosperity_name(),
		current.garrison, current.volunteers]

## 接 DayNightCycle.day_changed：志愿者回流。原文的刷新率【未解】→ 每 2 天每地 +1。
func on_day_changed(day: int) -> void:
	if ctx == null or not enabled:
		return
	var every := maxi(1, ctx.economy.volunteer_refill_days)
	if day % every != 0:
		return
	for s in ctx.data.settlements:
		# 上限也顺手夹一次：将来若上限随类型 / 事件变化，池子不会留在超限值上
		if s.volunteers > s.volunteers_cap:
			s.volunteers = s.volunteers_cap
		elif s.volunteers < s.volunteers_cap:
			s.volunteers = mini(s.volunteers_cap, s.volunteers + 1)
	# 菜单正开着时把新数字立刻反映出来（否则面板上还是旧值）
	if current != null:
		menu_changed.emit()

# =============================================================== 生成期 / 内部
## 给每个定居点定下繁荣度 / 志愿者池 / 每种货的本地价差。
##
## ⚠ 只用 cfg.make_rng("...") 这条**独立随机流**：既不消耗主生成流的抽取次数，
##   也不动生成顺序，所以生成指纹不变（gen_fingerprint 也根本不哈希这几个字段）。
##   生成期调用一次即可，重复调用结果相同（同一 tag → 同一个流 → 同一串数）。
static func assign_environment(cfg: MapConfig, data: MapData, economy: EconomyRules) -> void:
	if cfg == null or data == null or economy == null:
		return
	var rng := cfg.make_rng("settlement_economy")
	for s in data.settlements:
		# 繁荣度：以类型为底（城堡/城镇更富），再叠一段随机；钳 [0,100]
		var base := int(s.importance() * 70.0)
		s.prosperity = clampi(base + rng.randi_range(-25, 25), 0, 100)
		s.volunteers_cap = economy.volunteer_cap(s.kind)
		s.volunteers = s.volunteers_cap if s.volunteers_cap > 0 else 0
		var bias: Array[int] = []
		for i in economy.good_count():
			# 本地价差 ±15%：让「这儿的盐便宜」有确定性（同一张地图每次一样）
			bias.append(rng.randi_range(-15, 15))
		s.good_bias = bias

func _bias(gid: int) -> int:
	if current == null or gid < 0 or gid >= current.good_bias.size():
		return 0
	return int(current.good_bias[gid])

## 交易后的即时反馈（复用 HUD 的提示条；没有 HUD 时静默 —— 自检里不建 UI）
func _report(text: String) -> void:
	if ctx != null and ctx.hud != null:
		var who := current.name if current != null else ""
		ctx.hud.show_toast("%s：%s" % [who, text], 3.0)