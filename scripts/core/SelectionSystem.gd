## =============================================================================
##  SelectionSystem —— 「当前选中了谁」的状态 + 面板数据
##
##  与 EncounterSystem / SettlementSystem 同一套形状：
##    · 本类**不碰任何 UI 节点**，只把「标题 / 正文 / 条目数组」组好交给 HUD；
##    · 面板点什么只发信号，动作的含义由 Main 解释（前往 / 进入 / 追踪都要动相机、
##      动时间、动寻路，那是场景的事，不是状态的事）；
##    · 所以 tools/selection_check.gd 可以在没有窗口、没有渲染的情况下把
##      「选中 → 正文 → 条目 → 失效自动清空」整条走一遍并断言。
##
##  为什么单独一个系统而不是把两个字段塞进 Main：
##    「选中的部队被打没了要自动清空」这类失效逻辑需要一个能每帧被问一次的地方，
##    放进 Main 就会和 _process 里已有的十几件事混在一起（Main 已经在做门面）。
##
##  数据来源：SettlementSystem 的 current 是「正在办事的城」，本类的 settlement 是
##  「在大地图上被点中的城」—— 两者刻意分开：看详情不该把世界时间锁上。
## =============================================================================
class_name SelectionSystem
extends RefCounted

## 选中目标变了（HUD 重画面板）。清空也发这个信号，面板据此收起。
signal changed

var ctx: WorldContext
var kind: String = ""                  ## "" / MapPicker.KIND_SETTLEMENT / KIND_PARTY
var settlement: Settlement = null      ## kind == settlement 时有效
var party: AIParty = null              ## kind == party 时有效

# =============================================================== 状态
func is_empty() -> bool:
	return kind == ""

func is_settlement(s: Settlement) -> bool:
	return kind == MapPicker.KIND_SETTLEMENT and settlement != null and settlement == s

func is_party(p: AIParty) -> bool:
	return kind == MapPicker.KIND_PARTY and party != null and party == p

func select_settlement(s: Settlement) -> void:
	if s == null:
		clear()
		return
	kind = MapPicker.KIND_SETTLEMENT
	settlement = s
	party = null
	changed.emit()

func select_party(p: AIParty) -> void:
	if p == null or not is_instance_valid(p):
		clear()
		return
	kind = MapPicker.KIND_PARTY
	party = p
	settlement = null
	changed.emit()

func clear() -> void:
	if kind == "" and settlement == null and party == null:
		return
	kind = ""
	settlement = null
	party = null
	changed.emit()

## 数据被外部改过之后（读档 / 换日）刷新一次面板：位置、兵力、繁荣度都可能变了，
## 而正文是 select 那一刻算好的。空选中时什么也不做（读档不该凭空弹出一个面板）。
func refresh() -> void:
	if not is_empty():
		changed.emit()

## 每帧校验一次：被选中的部队可能已经打没了（ctx.parties.erase()）或已被 free。
## 这种情况必须自动清空 —— 否则面板会一直指着一个不存在的目标，
## 点「追踪」时空指针，或者更糟：点得动但没反应（最难查的一类问题）。
func tick() -> void:
	if kind != MapPicker.KIND_PARTY:
		return
	if party == null or not is_instance_valid(party):
		clear()
		return
	if ctx != null and ctx.parties != null and not ctx.parties.has(party):
		clear()

# =============================================================== 面板数据
## 标题：定居点「名字　类型」，部队「[类型] 名字」
func title() -> String:
	match kind:
		MapPicker.KIND_SETTLEMENT:
			if settlement != null:
				return Strings.SELECT_TITLE_SETTLEMENT % [settlement.name, settlement.kind_name()]
		MapPicker.KIND_PARTY:
			if party != null:
				return Strings.SELECT_TITLE_PARTY % [
					GameState.party_kind_name(party.ai_kind()), party.party_name]
	return ""

## 正文：一行一件事，手机上也能一眼看完（值是数据，不做任何判断）
func body() -> String:
	if ctx == null or ctx.data == null:
		return ""
	match kind:
		MapPicker.KIND_SETTLEMENT:
			if settlement == null:
				return ""
			var s := settlement
			var terr := GameState.faction_name(ctx.data, ctx.data.faction_at(s.pos.x, s.pos.y), "无主之地")
			return Strings.SELECT_BODY_SETTLEMENT % [
				s.kind_name(), ctx.data.faction(s.faction_id).name,
				s.prosperity, s.prosperity_name(), s.garrison, terr, distance_m(s.pos)]
		MapPicker.KIND_PARTY:
			if party == null:
				return ""
			var a := party
			var fname := GameState.faction_name(ctx.data, a.faction_id, "无阵营（流寇）")
			var lead := Strings.SELECT_BODY_PARTY_LEAD % a.boss_title if a.boss_title != "" else ""
			return Strings.SELECT_BODY_PARTY % [
				fname, a.troop_count, party_status_text(a), lead, distance_m(
					Vector2(a.position.x, a.position.z))]
	return ""

## 条目：{id, label, enabled, hint}，顺序即显示顺序，与进城菜单同一套约定。
## 全部 enabled —— 距离不够时 Main 会自动「先过去、抵达后自动进城」（见 Main._enter_settlement），
## 灰掉按钮再让玩家猜为什么点不动，是更差的体验。
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match kind:
		MapPicker.KIND_SETTLEMENT:
			if settlement == null:
				return out
			out.append({
				"id": "travel",
				"label": Strings.SELECT_ACT_TRAVEL,
				"enabled": true,
				"hint": Strings.SELECT_ACT_TRAVEL_HINT,
			})
			var reach := _reachable()
			out.append({
				"id": "enter",
				"label": Strings.SELECT_ACT_ENTER,
				"enabled": true,
				"hint": Strings.SELECT_ACT_ENTER_HINT if reach
					else Strings.SELECT_ACT_ENTER_FAR % distance_m(settlement.pos),
			})
		MapPicker.KIND_PARTY:
			if party == null:
				return out
			out.append({
				"id": "track",
				"label": Strings.SELECT_ACT_TRACK,
				"enabled": true,
				"hint": Strings.SELECT_ACT_TRACK_HINT,
			})
	return out

# =============================================================== 小工具
## 到目标的直线距离（米，取整）。远征距离在正文里数字比「很远」有用得多。
func distance_m(world: Vector2) -> int:
	if ctx == null or ctx.player == null:
		return 0
	var p := Vector2(ctx.player.position.x, ctx.player.position.z)
	return int(round(p.distance_to(world)))

## 玩家是否已经站在「能进城」的范围内（与 SettlementSystem.nearby() 同一个口径）
func _reachable() -> bool:
	if settlement == null or ctx == null or ctx.player == null:
		return false
	var p := Vector2(ctx.player.position.x, ctx.player.position.z)
	return p.distance_to(settlement.pos) <= settlement.interact_radius()

## 部队状态文案。与 HoverInspector 的悬停文案同口径（追击中 / 行军中 / 驻扎）。
static func party_status_text(a: AIParty) -> String:
	if a.chasing:
		return "追击中！"
	if a.moving:
		return "行军中"
	return "驻扎"
