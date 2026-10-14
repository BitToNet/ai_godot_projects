## =============================================================================
##  selection_check —— 点单位交互定式（**不参与游戏运行**，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/selection_check.gd
##
##  它守的四件事：
##    1) MapPicker 的**屏幕空间**判定：命中半径随距离换算成像素、钳在 [14, 90]、
##       定居点比部队优先一档、相机背后的目标点不到、没有相机 / 没有高度场时
##       返回空而不是崩。投影被抽成可覆写的方法，所以这里不需要渲染窗口。
##    2) SelectionSystem 的面板数据：标题 / 正文 / 条目的形状，
##       以及「被选中的部队打没了要自动清空」这条失效逻辑。
##    3) SelectionPanel 的非模态约定：面板在场**不算** is_any_dialog_open()、
##       挡得住点击（STOP）、Esc 关选中；有模态面板在场时 Esc 归它。
##    4) InputRouter 的左键分流：拾取器为空 = 老行为（点地行军，一字不变）；
##       命中 = pick_requested 且**不**再发行军命令；没命中 = 照常行军。
##
##  为什么值得单独一步：主场景 900 帧里玩家不动、不点任何东西，
##  「点城 → 选中 → 再点 → 进城」这条链在门禁里一步都走不到，
##  而它的失败方式恰恰是「点了没反应」——最难靠看日志发现的一类问题。
##
##  退出码：0 = 全部通过；1 = 有断言失败
## =============================================================================
extends SceneTree

## 把屏幕投影换成「世界 XZ 直接当像素」的等价映射：投影 = (x, z)，像素跨度 = 半径。
## 于是命中阈值就是 clampf(半径 + 6, 14, 90)，可以手算着断言。
class StubPicker extends MapPicker:
	func _project(world: Vector3) -> Vector2:
		return Vector2(world.x, world.z)

	func _behind(_world: Vector3) -> bool:
		return false

	func _pixel_span(_center: Vector3, radius_m: float) -> float:
		return radius_m

## 相机背后的目标：屏幕投影里「看不到」的目标不该能被点到
class BehindPicker extends StubPicker:
	func _behind(_world: Vector3) -> bool:
		return true

## 只回答「命中了谁」——用来验路由的分流，拾取几何由上面的 StubPicker 单独验
class ScriptedPicker extends MapPicker:
	var result: Dictionary = {}

	func pick(_screen_pos: Vector2) -> Dictionary:
		return result

## 信号计数器。**刻意不让闭包捕获被观察者自己**：`sel.changed.connect(func(): ... sel ...)`
## 会造出 sel → 连接 → 闭包 → sel 的引用环，RefCounted 永远释放不掉，
## 于是退出时报一串 "ObjectDB instances leaked" + "N resources still in use"
## （而且那份 ERROR 会被门禁判失败）。
class Recorder extends RefCounted:
	var hits: int = 0

var _fails: Array[String] = []
var _total: int = 0
## 本工具造的 Node（AIParty / PlayerParty 都是 Node3D）：**必须逐个 free**，
## 否则退出时引擎会打 "ObjectDB instances leaked at exit"，而那行 ERROR 会被门禁判失败。
var _nodes: Array[Node] = []

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
	print("[SELECT] 点单位交互定式（不跑地图生成）")
	await _check_picker()
	await _check_system()
	await _check_panel()
	await _check_router()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	print("")
	if _fails.is_empty():
		print("PASS：点单位交互定式全部通过（%d 项断言）" % _total)
		quit(0)
	else:
		print("FAIL：%d/%d 项断言未通过 —— %s" % [_fails.size(), _total, "; ".join(_fails)])
		quit(1)

# ---------------------------------------------------------------- 造数据
## 一个不生成世界的最小 MapData：高度场全 0、三个势力齐备
func _make_data() -> MapData:
	var data := MapData.new()
	data.hm = Heightmap.new(9, 100.0)
	data.factions = Faction.build_all()
	return data

func _make_settlement(pos: Vector2, radius: float = 10.0) -> Settlement:
	var s := Settlement.new()
	s.id = 7
	s.name = "测试城"
	s.kind = Settlement.Kind.TOWN
	s.faction_id = 0
	s.pos = pos
	s.ground_h = 0.0
	s.radius = radius
	s.garrison = 42
	s.prosperity = 55
	return s

func _make_party(pos: Vector2) -> AIParty:
	var a := AIParty.new()
	a.kind = AIParty.Kind.BANDIT
	a.party_name = "测试强盗"
	a.faction_id = 0
	a.troop_count = 23
	a.boss_title = "强盗头目"
	a.position = Vector3(pos.x, 0.0, pos.y)
	_nodes.append(a)
	return a

## 只用它的 position（SelectionSystem 算距离 / 判定「够不够近」都只看这个），
## 不走 setup_player —— 那需要材质与网格，而这里要验的与模型无关。
func _make_player(pos: Vector2) -> PlayerParty:
	var p := PlayerParty.new()
	p.position = Vector3(pos.x, 0.0, pos.y)
	_nodes.append(p)
	return p

# ---------------------------------------------------------------- 1) 拾取
func _check_picker() -> void:
	print("  -- MapPicker（屏幕空间判定）--")
	var data := _make_data()
	var s := _make_settlement(Vector2(50, 60))
	data.settlements.append(s)
	var a := _make_party(Vector2(200, 200))

	# pick() 只要求「有一个相机」：投影三个方法都被覆写了，用不到真正的视口，
	# 所以这里造一个不进树、不渲染的空 rig + 空 Camera3D（都记进 _nodes 待释放）。
	var rig := CameraRig.new()
	_nodes.append(rig)
	var cam := Camera3D.new()
	_nodes.append(cam)
	rig.cam = cam

	var pk := StubPicker.new()
	pk.camera_rig = rig
	pk.data = data
	pk.parties.append(a)

	# 定居点阈值 = clampf(半径 10 + 6 px 余量, 14, 90) = 16 px
	var hit := pk.pick(Vector2(50, 60))
	_ok(String(hit.get("kind", "")) == MapPicker.KIND_SETTLEMENT, "正上方点中定居点")
	_ok(hit.get("settlement") == s, "命中结果带的是那座城本身")
	_ok(float(hit.get("px", 9.9)) < 0.001, "正中目标时像素距离 ≈ 0")
	_ok(not pk.pick(Vector2(50 + 15, 60)).is_empty(), "半径 + 15 px 仍在命中圈内（阈值 16）")
	_ok(pk.pick(Vector2(50 + 25, 60)).is_empty(), "半径 + 25 px 打空")

	# 部队阈值 = clampf(7 + 6, 14, 90) × 0.85 = 11.05 px
	_ok(String(pk.pick(Vector2(200, 200)).get("kind", "")) == MapPicker.KIND_PARTY, "点中部队")
	_ok(pk.pick(Vector2(200 + 15, 200)).is_empty(), "部队圈更窄：15 px 外打空")
	_ok(pk.pick(Vector2(200 + 27, 200)).is_empty(), "两支部队之间（27 px）也打空")

	# 城与部队重叠：小目标占 6 px 让先
	data.settlements.append(_make_settlement(Vector2(60, 60)))
	var b := _make_party(Vector2(60, 60))
	pk.parties.append(b)
	_ok(String(pk.pick(Vector2(60, 60)).get("kind", "")) == MapPicker.KIND_PARTY,
		"针尖对针尖（领主常停在城中心）→ 部队，否则这些部队永远点不动")
	_ok(String(pk.pick(Vector2(60 + 5, 60)).get("kind", "")) == MapPicker.KIND_PARTY,
		"光标朝部队挪 5 px（让先额度内）→ 仍是部队")
	# 部队在城边 9 px 处（仍在自己的 11.05 px 圈内）：瞄准城心时不该被它抢走
	b.position = Vector3(60 + 9, 0.0, 60)
	_ok(String(pk.pick(Vector2(60, 60)).get("kind", "")) == MapPicker.KIND_SETTLEMENT,
		"瞄准城心、旁边 9 px 有部队 → 定居点（让先额度 6 px 之外）")
	_ok(String(pk.pick(Vector2(60 + 9, 60)).get("kind", "")) == MapPicker.KIND_PARTY,
		"但光标挪到部队身上 → 部队")
	b.position = Vector3(200.0, 0.0, 200.0)

	# 钳位：巨大半径不至于吃掉半屏（上限 90），极小半径远景也点得着（下限 14）
	var big := _make_settlement(Vector2(500, 500), 400.0)
	data.settlements.append(big)
	_ok(not pk.pick(Vector2(500 + 89, 500)).is_empty(), "超大城池：89 px 内仍可点（上限 90）")
	_ok(pk.pick(Vector2(500 + 92, 500)).is_empty(), "超大城池：92 px 外打空（上限真的生效）")
	var tiny := _make_settlement(Vector2(700, 700), 0.0)
	data.settlements.append(tiny)
	_ok(not pk.pick(Vector2(700 + 13, 700)).is_empty(), "半径 0 的小目标：13 px 内仍可点（下限 14）")
	_ok(pk.pick(Vector2(700 + 20, 700)).is_empty(), "半径 0 的小目标：20 px 外打空")

	# 相机背后 / 缺依赖
	var behind := BehindPicker.new()
	behind.camera_rig = rig
	behind.data = data
	_ok(behind.pick(Vector2(50, 60)).is_empty(), "相机背后的目标点不到")
	var naked := MapPicker.new()
	naked.data = data
	_ok(naked.pick(Vector2(50, 60)).is_empty(), "没有相机时返回空（不崩）")
	var no_hm := StubPicker.new()
	no_hm.camera_rig = rig
	no_hm.data = MapData.new()
	_ok(no_hm.pick(Vector2(0, 0)).is_empty(), "没有高度场时返回空（不崩）")
	# 拾取全程只读：调用三次不改变任何数据
	_ok(data.settlements.size() == 4 and s.radius == 10.0, "拾取不修改任何数据")

# ---------------------------------------------------------------- 2) 选中状态
func _check_system() -> void:
	print("  -- SelectionSystem（面板数据 / 失效）--")
	var data := _make_data()
	var s := _make_settlement(Vector2(50, 60))
	data.settlements.append(s)
	var a := _make_party(Vector2(20, 20))

	var player := _make_player(Vector2(30, 60))   # 距城 20 米

	var ctx := WorldContext.new()
	ctx.data = data
	ctx.player = player
	ctx.parties = [a]

	var sel := SelectionSystem.new()
	sel.ctx = ctx
	_ok(sel.is_empty(), "初始没有选中任何东西")
	_ok(sel.title() == "" and sel.body() == "" and sel.entries().is_empty(), "空选中不产生任何面板数据")

	sel.select_settlement(s)
	_ok(not sel.is_empty() and sel.settlement == s and sel.party == null, "选中定居点")
	_ok(sel.title() == "测试城　城镇", "定居点标题 = 名字 + 类型　得到「%s」" % sel.title())
	var body := sel.body()
	_ok(body.contains("瓦兰迪亚王国"), "正文带势力名（%s）" % body)
	_ok(body.contains("繁荣度：55") and body.contains("驻军：42 人"), "正文带繁荣度与驻军")
	_ok(body.contains("距离：20 米"), "正文带距离（20 米）　得到「%s」" % body)
	var es := sel.entries()
	_ok(es.size() == 2 and es[0]["id"] == "travel" and es[1]["id"] == "enter",
		"定居点两条：前往 / 进入　得到 %s" % [es.map(func(e: Dictionary) -> String: return e["id"])])
	_ok(bool(es[1]["enabled"]), "太远也不灰掉「进入」（由 Main 自动先过去）")
	_ok(String(es[1]["hint"]).contains("距离 20 米"), "太远时提示里写明还有多远")

	# 走进城门范围（radius 10 + 6 = 16 米）后，「进入」的提示改成正常的办事说明
	player.position = Vector3(72.0, 0.0, 60.0)   # 距城 22 米 → 还不够近
	_ok(sel.body().contains("距离：22 米"), "距离随玩家位置更新")
	player.position = Vector3(62.0, 0.0, 60.0)   # 距城 12 米 → 进了 interact_radius(16)
	_ok(String(sel.entries()[1]["hint"]) == Strings.SELECT_ACT_ENTER_HINT, "够近时提示换成办事说明")

	sel.select_party(a)
	_ok(sel.party == a and sel.settlement == null, "选中部队（定居点被顶掉）")
	_ok(sel.title() == "[强盗团伙] 测试强盗", "部队标题 = [类型] 名字　得到「%s」" % sel.title())
	var pb := sel.body()
	_ok(pb.contains("兵力：23 人"), "正文带兵力（%s）" % pb)
	_ok(pb.contains("驻扎") and pb.contains("首领：强盗头目"), "正文带状态与首领名号")
	var ep := sel.entries()
	_ok(ep.size() == 1 and ep[0]["id"] == "track" and bool(ep[0]["enabled"]), "部队一条：追踪")

	# 失效：部队被结算掉（不在 ctx.parties 里了）→ 自动清空
	var rec := Recorder.new()
	sel.changed.connect(func() -> void: rec.hits += 1)
	ctx.parties.clear()
	sel.tick()
	_ok(sel.is_empty(), "被选中的部队不在 ctx.parties 里 → 自动清空")
	_ok(rec.hits == 1, "清空也发 changed（HUD 据此收面板），发了 %d 次" % rec.hits)
	# 清空后再 tick 不该反复发信号（否则面板每帧重建）
	rec.hits = 0
	sel.tick()
	_ok(rec.hits == 0, "已经是空选中时 tick 不再发信号")
	# 读档路径用的 refresh()：有选中时刷一次，空选中时什么都不做
	sel.select_settlement(s)
	rec.hits = 0
	sel.refresh()
	_ok(rec.hits == 1, "有选中时 refresh() 让面板重算一次（读档后距离会变）")
	sel.clear()
	rec.hits = 0
	sel.refresh()
	_ok(rec.hits == 0, "空选中时 refresh() 不弹面板")

	# 直接 free 掉的部队同样要清空
	sel.select_party(_make_party(Vector2(1, 1)))
	var orphan := sel.party
	ctx.parties = [orphan]
	ctx.parties.clear()
	sel.tick()
	_ok(sel.is_empty(), "部队已被移出列表 → 自动清空")
	# 上面造的 Node 由 _run() 末尾统一 free（见 _nodes）

# ---------------------------------------------------------------- 3) 面板
func _check_panel() -> void:
	print("  -- SelectionPanel（非模态 / Esc / 让路）--")
	var cfg := MapConfig.new()
	var hud := HUD.new()
	hud.name = "HUD"
	get_root().add_child(hud)
	hud.setup(cfg)
	await process_frame

	var acts: Array[String] = []
	hud.selection_action.connect(func(x: String): acts.append(x))

	_ok(not hud.is_selection_open(), "未选中时面板是隐藏的")
	_ok(not hud.is_any_dialog_open(), "两个模态面板都没开时 is_any_dialog_open 为假")

	var entries: Array[Dictionary] = [
		{"id": "travel", "label": Strings.SELECT_ACT_TRAVEL, "enabled": true, "hint": "h"},
		{"id": "enter", "label": Strings.SELECT_ACT_ENTER, "enabled": false, "hint": ""},
	]
	hud.show_selection("测试城　城镇", "正文", entries)
	await process_frame
	_ok(hud.is_selection_open(), "show_selection 后面板打开")
	# 非模态：看一眼详情不该让键盘路由整体让路（这是它与另外两块面板最大的区别）
	_ok(not hud.is_any_dialog_open(), "选中面板**不算** is_any_dialog_open（非模态）")
	_ok(hud.selection_panel.mouse_filter == Control.MOUSE_FILTER_STOP,
		"面板挡住自己覆盖的区域（STOP）：点按钮不会顺手把部队派出去")
	_ok(hud.selection_panel.offset_left >= 16, "面板从左 16 px 起（不与顶栏重叠）")
	_ok(hud.selection_panel.offset_top >= 150, "面板在顶栏之下（offset_top = %d）" % hud.selection_panel.offset_top)
	_ok(hud.selection_panel.row_actions() == ["travel", "enter"],
		"条目按数据顺序建：%s" % [hud.selection_panel.row_actions()])
	_ok(hud.selection_panel.row_enabled() == [true, false],
		"灰行落到 disabled 上：%s" % [hud.selection_panel.row_enabled()])
	_ok(not hud.selection_panel.row_button(0).has_focus(),
		"打开面板不抢焦点（免得空格 / 回车误触条目）")
	_ok(hud.selection_panel.title_text() == "测试城　城镇", "标题原样落到面板上")
	_ok(hud.selection_panel.body_text() == "正文", "正文原样落到面板上")

	# 点条目 → 只发信号，面板自己不关（关不关由 Main 清选中决定）
	hud.selection_panel.row_button(0).pressed.emit()
	_ok(acts == ["travel"], "点「前往」→ action_pressed(travel)　得到 %s" % [acts])
	_ok(hud.is_selection_open(), "点完条目面板仍开着（由业务层决定收不收）")

	# Esc → 关闭选中（但面板自己不关）
	hud.selection_panel._unhandled_input(_key(KEY_ESCAPE))
	_ok(acts == ["travel", Strings.SELECT_CLOSE], "Esc → action_pressed(close)　得到 %s" % [acts])
	_ok(hud.is_selection_open(), "Esc 后面板仍开着（关它的是业务层）")

	# 有模态面板在场时 Esc 归它：选中面板不许同时响应
	acts.clear()
	hud.show_settlement_menu("测试镇　城镇", "状态行", [])
	await process_frame
	hud.selection_panel._unhandled_input(_key(KEY_ESCAPE))
	_ok(acts.is_empty(), "进城菜单在场时选中面板不抢 Esc")
	hud.hide_settlement()

	# 业务层清空选中 → HUD 收起面板
	acts.clear()
	hud.hide_selection()
	_ok(not hud.is_selection_open(), "hide_selection 后面板与状态都归零")
	hud.selection_panel._unhandled_input(_key(KEY_ESCAPE))
	_ok(acts.is_empty(), "隐藏后 Esc 不再发信号")

	hud.free()

# ---------------------------------------------------------------- 4) 路由分流
func _check_router() -> void:
	print("  -- InputRouter（左键：选中还是行军）--")
	var cfg := MapConfig.new()
	var rig := StubRig.new()
	get_root().add_child(rig)
	var hud := HUD.new()
	get_root().add_child(hud)
	hud.setup(cfg)
	var router := InputRouter.new()
	get_root().add_child(router)
	router.camera_rig = rig
	router.hud = hud
	router.cfg = cfg
	await process_frame

	var orders: Array[Vector2] = []
	var picks: Array[Vector2] = []
	router.order_move.connect(func(g: Vector2): orders.append(g))
	router.pick_requested.connect(func(p: Vector2): picks.append(p))

	# 没有拾取器 = 本轮之前的行为，逐位一致（tools/input_check.gd 走的就是这条）
	router._unhandled_input(_click(Vector2(800, 450)))
	_ok(orders == [Vector2(50, 60)] and picks.is_empty(),
		"没有拾取器时左键仍是纯行军命令　得到 %s" % [orders])

	# 有拾取器但没点到东西：照常行军
	orders.clear()
	var sp := ScriptedPicker.new()
	router.picker = sp
	router._unhandled_input(_click(Vector2(800, 450)))
	_ok(orders == [Vector2(50, 60)] and picks.is_empty(), "拾取未命中 → 照常行军")

	# 点到了实体：发 pick_requested，且**不**再发行军命令（否则点城看详情会顺手出兵）
	orders.clear()
	sp.result = {"kind": MapPicker.KIND_SETTLEMENT, "score": 0.1}
	router._unhandled_input(_click(Vector2(801, 451)))
	_ok(picks == [Vector2(801, 451)] and orders.is_empty(),
		"点中定居点 → 只发 pick_requested，不发行军命令（得到 picks=%s orders=%s）" % [picks, orders])

	# 对话框让路优先级高于拾取：模态面板在场时连选中都不发生
	picks.clear()
	orders.clear()
	hud.show_encounter("遭遇 测试部队", "测试说明", Color(1, 1, 1))
	await process_frame
	router._unhandled_input(_click(Vector2(801, 451)))
	_ok(picks.is_empty() and orders.is_empty(), "遭遇框在场时连拾取也让路")
	hud.hide_encounter()

	router.free()
	hud.free()
	rig.free()

# ---------------------------------------------------------------- 桩 / 事件
## 只需要 ray_to_terrain 的相机桩（真射线要高度场，这里不建世界）
class StubRig extends CameraRig:
	var hit: Vector3 = Vector3(50.0, 5.0, 60.0)

	func ray_to_terrain(_screen_pos: Vector2) -> Vector3:
		return hit

## 注意：device 留默认 0、keycode 与 physical_keycode 都写（理由见 input_check.gd 的注释）
func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e

func _click(pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	return e
