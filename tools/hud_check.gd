## =============================================================================
##  hud_check —— HUD 对外接口冒烟测试（**不参与游戏运行**，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/hud_check.gd
##
##  为什么不跑 Main.tscn：地图生成要 6 秒，而这里要验的只是 UI 接口本身。
##  直接 new 一个 HUD 挂到树根，逐项走一遍 Main / BattleScene 会用到的方法。
##  存在的意义：门禁里那 900 帧主场景运行**玩家不移动、不触发遭遇**，
##  UI 的交互路径（遭遇框开关 / 提示抑制 / 提示条淡出）以前完全没有覆盖，
##  第三轮拆 HUD 时这类回归只能靠人工点开游戏看 —— 现在有断言了。
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

func _run() -> void:
	var cfg := MapConfig.new()
	var hud := HUD.new()
	hud.name = "HUD"
	get_root().add_child(hud)
	hud.setup(cfg)
	await process_frame

	print("[HUD] 对外接口冒烟（不跑地图生成）")

	# ---- 开场遮罩 ----
	# 视口尺寸作参照：headless 下是 1600×1600，开窗口时是 1600×900，所以断言只跟视口比、不写死像素。
	var vp: Vector2 = get_root().get_visible_rect().size
	# 开场遮罩的三行文案（迁进 Strings.gd 之前就在这里，第七轮 §14.2 迁完必须一字不差）。
	# **必须在 set_loading 之前断**：set_loading 会把进度行覆盖成它自己的文字。
	# 这里故意按字面量断言 —— 断 Strings.X 等于断常量自己，证明不了观感没变。
	_ok(hud._loading._title.text == "骑马与砍杀 · 战略大地图", "开局遮罩标题未变")
	_ok(hud._loading._sub.text == "程序化生成中：地形 / 河流 / 植被 / 定居点 / 道路 / 部队",
		"开局遮罩副标题未变")
	_ok(hud._loading._label.text == "准备中…", "开局遮罩进度行初始文案未变")
	hud.set_loading("加载中：测试")
	_ok(hud._loading.visible, "遮罩初始可见")
	_ok(hud._loading.mouse_filter == Control.MOUSE_FILTER_STOP, "遮罩挡住点击（STOP）")
	# 回归守卫：0×0 的 STOP 控件谁也挡不住。只调 set_anchors_preset 会让 offsets 保留 0×0 矩形。
	_ok(hud._loading.size == vp, "遮罩铺满视口（%s vs %s）" % [hud._loading.size, vp])
	_ok((hud._loading.get_child(0) as Control).size == vp, "遮罩黑底铺满视口")
	# 遮罩不能只盖住 3D 视图：同级面板（空小地图外框 / 空性能条 / 操作说明）默认画在它之上，
	# 会让加载画面变成「黑底 + 一堆空框」。
	var _max_z := 0
	for _ch in hud.get_children():
		if _ch is CanvasItem:
			_max_z = maxi(_max_z, (_ch as CanvasItem).z_index)
	_ok(_max_z > 0 and _max_z == hud._loading.z_index,
		"遮罩 z_index 为同级最高（%d）：加载时盖住所有面板" % _max_z)
	hud.hide_loading()
	_ok(not hud._loading.visible, "hide_loading 后遮罩隐藏")

	# ---- 绑定运行时数据 ----
	var data := MapData.new()
	data.cfg = cfg
	data.factions = Faction.build_all()
	var dn := DayNightCycle.new()
	dn.paused = true          # 只取它的纯查询方法，不入树（避免 _process 需要 sun/env）
	hud.bind(data, dn)
	await process_frame

	# ---- 左上信息栏 ----
	hud.set_terrain_text("平原")
	_ok(hud.topbar._terrain_label.text == "当前地形：平原", "set_terrain_text 落到左上栏")
	_ok(hud.topbar._day_label.text.begins_with("第 1 天"), "日期行已刷新（得到「%s」）" % hud.topbar._day_label.text)
	_ok(hud.topbar._pause_badge.text.contains("暂停"), "暂停徽标随 paused 显示")

	# ---- 左上信息栏：钱袋 / 粮 / 士气 / 档次（第四轮）----
	# 没绑战役状态时必须留空：hud_check 这条路径不建世界、也没有 CampaignState，
	# 显示「钱袋 0 金」会让人以为游戏真的没钱了，空白才是诚实的。
	_ok(hud.topbar._purse_label.text == "", "未绑定战役状态时钱袋行留空")
	var e_rules := EconomyRules.create()
	var e_pp := PlayerParty.new()
	e_pp.troop_count = GameState.PLAYER_START_TROOPS
	var e_cs := CampaignState.new()
	e_cs.setup(e_rules, e_pp)
	hud.bind_campaign(e_cs)
	_ok(hud.topbar._purse_label.text.contains("钱袋 %d 金" % e_cs.denars),
		"绑定后钱袋行显示金额（「%s」）" % hud.topbar._purse_label.text)
	_ok(hud.topbar._purse_label.text.contains("粮 %d 件" % e_cs.supplies), "钱袋行显示补给")
	_ok(hud.topbar._purse_label.text.contains("士气 %d" % e_cs.morale), "钱袋行显示士气")
	_ok(hud.topbar._purse_label.text.contains(e_rules.tier_name(e_cs.tier)), "钱袋行显示兵员档次")
	_ok(hud.topbar._purse_label.text.contains("%s %d/%d" % [
			e_rules.tier_name(e_cs.tier), e_cs.troops(), e_cs.capacity()]),
		"钱袋行显示档次 + 兵力 / 编制")
	# 值变了要跟着变。钱袋行是 4 Hz 节流的，所以把计时器直接推到点，不靠等真时间。
	e_cs.denars += 100
	e_cs.add_morale(-25)                    # 40 → 15：掉进「濒临溃散」的红色档
	hud.topbar._purse_timer = 1.0
	await process_frame
	_ok(hud.topbar._purse_label.text.contains("钱袋 %d 金" % e_cs.denars), "钱袋变化后跟着刷新")
	e_cs.debt_weeks = 3
	hud.topbar._purse_timer = 1.0
	await process_frame
	_ok(hud.topbar._purse_label.text.contains("欠薪 3 周"), "欠薪时显示欠薪周数")
	hud.bind_campaign(null)
	_ok(hud.topbar._purse_label.text == "", "解绑后钱袋行清空（不留下过期数字）")
	e_pp.free()

	# ---- 悬停提示 ----
	hud.show_tooltip("测试提示", Vector2(100, 100))
	_ok(hud._tooltip.visible, "show_tooltip 显示提示")
	hud.clear_tooltip()
	_ok(not hud._tooltip.visible, "clear_tooltip 收起提示")

	# ---- 遭遇对话框（第四轮 4c 起：选项表数据驱动，面板自己不关）----
	var got: Array = []
	hud.encounter_choice.connect(func(a: String): got.append(a))

	hud.show_encounter("遭遇 测试部队", "测试说明", Color(1, 1, 1))
	_ok(hud.is_encounter_open(), "show_encounter 后对话框打开")
	_ok(hud.dialog.mouse_filter == Control.MOUSE_FILTER_STOP, "对话框挡住点击（STOP）")
	# 几何回归守卫：遭遇框曾经缩在左上角（对话框 0×0、遮罩 0×0），截图看不出来但点得到。
	await process_frame
	await process_frame
	_ok(hud.dialog.size == vp, "对话框铺满视口（%s vs %s）" % [hud.dialog.size, vp])
	_ok((hud.dialog.get_child(0) as Control).size == vp, "遭遇遮罩（dim）铺满视口")
	var _dcc := hud.dialog.get_child(1) as Control
	_ok(_dcc.size == vp, "居中容器铺满视口")
	var _dpanel := _dcc.get_child(0) as Control
	# 容差 1 px：CenterContainer 按整数像素取整，is_equal_approx 的 1e-5 会把 0.5 px 差额判失败。
	_ok((_dpanel.position - (vp - _dpanel.size) * 0.5).length() <= 1.0,
		"面板居中（pos=%s，视口 %s）" % [_dpanel.position, vp])
	_ok(hud.dialog.row_actions() == ["attack", "retreat"],
		"不传 entries 时用兜底两行：%s" % [hud.dialog.row_actions()])
	_ok(hud.dialog.attack_button.text.contains("攻"), "攻击按钮就位")
	_ok(hud.dialog.row_button(0).has_focus(), "打开时焦点给第一个可用条目")
	# 文案迁进 Strings.gd（第七轮 §14.2）后，提示行仍然逐字是原来那句。
	# 这里**故意按字面量断言**：断 Strings.X 等于断常量自己，证明不了观感没变。
	_ok(hud.dialog.hint_label.text.ends_with("↑↓ 选择条目")
		and hud.dialog.hint_label.text.contains("确认")
		and hud.dialog.hint_label.text.contains("撤退"),
		"遭遇框提示行文案未变（%s）" % hud.dialog.hint_label.text)

	hud.show_tooltip("提示", Vector2(10, 10))
	_ok(not hud._tooltip.visible, "对话框打开时悬停提示被抑制")

	hud.dialog.attack_button.pressed.emit()
	await process_frame
	_ok(got == ["attack"], "re-emit 成 encounter_choice（得到 %s）" % str(got))
	_ok(hud.is_encounter_open(), "面板自己不关：何时关由 EncounterSystem 决定")

	hud.show_encounter("遭遇 测试部队", "测试说明", Color(1, 1, 1))
	hud.dialog.retreat_button.pressed.emit()
	await process_frame
	_ok(got == ["attack", "retreat"], "「撤退」同样转发")
	hud.hide_encounter()
	_ok(not hud.is_encounter_open(), "hide_encounter 关闭对话框")

	# ---- 遭遇多选项（第四轮 4c）：条目整条来自 EncounterSystem.options() ----
	var enc: Array[Dictionary] = [
		{"id": "attack", "label": "攻 击", "enabled": true, "hint": "进入 Boss 战：预计掉队 7 人"},
		{"id": "bribe", "label": "花钱买路（180 金）", "enabled": false, "hint": "现有 120 金；声望折扣 −6%"},
		{"id": "demand", "label": "索要买路钱（216 金）", "enabled": true, "hint": "你的战力 37，需要 ≥ 36"},
		{"id": "retreat", "label": "撤 退", "enabled": true, "hint": "不战而走（有代价）"},
	]
	hud.show_encounter("遭遇 测试部队", "测试说明", Color(1, 1, 1), enc)
	await process_frame
	_ok(hud.dialog.row_actions() == ["attack", "bribe", "demand", "retreat"],
		"四条选项按数据顺序排列：%s" % [hud.dialog.row_actions()])
	_ok(hud.dialog.row_enabled() == [true, false, true, true],
		"可用性原样来自数据：%s" % [hud.dialog.row_enabled()])
	_ok(hud.dialog.row_hints()[1].contains("现有 120 金"),
		"灰掉的行必须带原因：%s" % hud.dialog.row_hints()[1])
	_ok(hud.dialog.row_button(1).disabled
		and hud.dialog.row_button(1).focus_mode == Control.FOCUS_NONE,
		"灰行不进焦点链（连按 ↓ 不会卡在点不动的按钮上）")
	_ok(hud.dialog.row_button(0).has_focus(), "焦点给第一个可用条目")
	_ok(hud.dialog.row_button(0).text.contains("攻") and hud.dialog.attack_button == hud.dialog.row_button(0),
		"按数据画出来的攻击行就是 attack_button")
	hud.dialog.row_button(2).pressed.emit()
	await process_frame
	_ok(got == ["attack", "retreat", "demand"], "「索要买路钱」也能转发（得到 %s）" % [str(got)])
	_ok(hud.is_encounter_open(), "选完一条遭遇选项面板同样不自己关")
	hud.hide_encounter()
	_ok(not hud.is_encounter_open() and not hud.is_any_dialog_open(), "hide_encounter 后归零")

	# ---- 进城菜单（第四轮 4b-2）：HUD 只负责画，条目数据整条来自系统 ----
	var sent: Array = []
	hud.settlement_action.connect(func(a: String): sent.append(a))
	_ok(not hud.is_settlement_open(), "未进城时菜单是隐藏的")
	_ok(not hud.is_any_dialog_open(), "两个面板都没开时 is_any_dialog_open 为假")

	var entries: Array[Dictionary] = [
		{"id": "supply", "label": "买补给 ×1（5 金）", "enabled": true, "hint": "现有 35 件"},
		{"id": "recruit", "label": "招 募（10 金/人）", "enabled": false, "hint": "钱不够（需 10 金）"},
		{"id": "leave", "label": "离 开", "enabled": true, "hint": "回到大地图"},
	]
	hud.show_settlement_menu("测试镇　城镇", "测试镇 · 城镇 · 繁荣 80", entries)
	await process_frame
	await process_frame
	_ok(hud.is_settlement_open(), "show_settlement_menu 后菜单打开")
	_ok(hud.is_any_dialog_open(), "is_any_dialog_open 把进城菜单也算上")
	_ok(hud.settlement_dialog.mouse_filter == Control.MOUSE_FILTER_STOP, "进城菜单挡住点击（STOP）")
	_ok(hud.settlement_dialog.size == vp, "进城菜单铺满视口（%s vs %s）" % [hud.settlement_dialog.size, vp])
	# 同一个坑的回归守卫：EncounterDialog 曾经只设 anchors 而缩在左上角，
	# 进城菜单是照它写的，必须一起守住「遮罩铺满 + 面板居中」。
	var _scc := hud.settlement_dialog.get_child(1) as Control
	_ok((hud.settlement_dialog.get_child(0) as Control).size == vp, "进城遮罩（dim）铺满视口")
	_ok(_scc.size == vp, "进城居中容器铺满视口")
	var _spanel := _scc.get_child(0) as Control
	_ok((_spanel.position - (vp - _spanel.size) * 0.5).length() <= 1.0,
		"进城面板居中（pos=%s，视口 %s）" % [_spanel.position, vp])
	_ok(hud.settlement_dialog.row_actions() == ["supply", "recruit", "leave"],
		"条目顺序原样来自数据：%s" % [hud.settlement_dialog.row_actions()])
	_ok(hud.settlement_dialog.row_enabled() == [true, false, true],
		"灰化状态原样来自数据：%s" % [hud.settlement_dialog.row_enabled()])
	_ok(hud.settlement_dialog.row_hints()[1] == "钱不够（需 10 金）",
		"灰掉的行必须带原因：%s" % hud.settlement_dialog.row_hints()[1])
	_ok(hud.settlement_dialog._status.text.contains("繁荣 80"),
		"状态行原样显示系统给的文字：%s" % hud.settlement_dialog._status.text)
	_ok(hud.settlement_dialog.row_button(0).has_focus(), "打开时焦点给第一个可用条目")
	_ok(hud.settlement_dialog.row_button(1).disabled, "「不可用」落到 Button.disabled 上（不是只换颜色）")
	_ok(hud.settlement_dialog.hint_label.text.ends_with("↑↓ 选择条目")
		and hud.settlement_dialog.hint_label.text.contains("离开"),
		"进城菜单提示行文案未变（%s）" % hud.settlement_dialog.hint_label.text)

	# 菜单打开时悬停提示同样让路（否则提示条会浮在菜单上面）
	hud.show_tooltip("提示", Vector2(10, 10))
	_ok(not hud._tooltip.visible, "进城菜单打开时悬停提示被抑制")

	hud.settlement_dialog.row_button(0).pressed.emit()
	await process_frame
	_ok(sent == ["supply"], "点条目 → settlement_action（得到 %s）" % [sent])
	_ok(hud.is_settlement_open(), "选完一条菜单仍然开着（买完接着买，不一点就关）")

	hud.hide_settlement()
	_ok(not hud.is_any_dialog_open(), "hide_settlement 后面板与「任一面板在场」都归零")

	# ---- 临时提示条：到期自动淡出 ----
	hud.show_toast("测试提示条", 1.0)
	_ok(hud._toast.visible, "show_toast 显示提示条")
	_ok(hud._toast.mouse_filter == Control.MOUSE_FILTER_IGNORE, "提示条不吞点击（IGNORE）")
	for i in 70:                     # 1.0 秒 @ 60fps，多跑几帧
		await process_frame
	_ok(not hud._toast.visible, "提示条到期自动隐藏")

	# ---- 装饰面板不吞点击（第一轮只修了小地图外框，其余面板同批处理）----
	var frame: PanelContainer = hud.get_node("MinimapFrame")
	_ok(frame.mouse_filter == Control.MOUSE_FILTER_IGNORE, "小地图外框 IGNORE")
	_ok(hud.get_node("HelpPanel").mouse_filter == Control.MOUSE_FILTER_IGNORE, "操作说明面板 IGNORE")
	_ok(hud.get_node("DebugStatsPanel").mouse_filter == Control.MOUSE_FILTER_IGNORE, "性能面板 IGNORE")

	# ---- 两块「只读」面板的文案（第七轮 §14.2 迁进 Strings.gd）逐字未变 ----
	# 迁 TopBar 时靠已有断言守观感；这两块此前没有任何文案断言，所以本批补上
	# （开局遮罩的三行在上面 set_loading 之前已断过）。
	# 断的是**渲染出来的字符串**，不是 Strings.gd 里的常量（断常量等于没断）。
	var help_label := hud.get_node("HelpPanel").get_child(0) as Label
	_ok(help_label.text.begins_with("【操作】"), "操作说明标题仍是「【操作】」")
	_ok(help_label.text.contains("左键点击地面：部队寻路移动（行军途中时间流动，抵达后立刻暂停）"),
		"操作说明首行文案未变")
	_ok(help_label.text.contains("快速读档（回到上次存档；会重跑一遍地图生成）"), "操作说明末行文案未变")
	# 性能面板每 0.25 s 采一次样（@60fps 约 15 帧），多跑几帧让它至少刷一次再按格式断言
	var stats_label := hud.get_node("DebugStatsPanel").get_child(0) as Label
	for i in 20:
		await process_frame
	var stats_re := RegEx.new()
	stats_re.compile("^FPS \\d+   绘制调用 \\d+   三角形 [\\d.]+ 万$")
	_ok(stats_re.search(stats_label.text) != null, "性能面板文案格式未变（%s）" % stats_label.text)

	print("")
	# 主动清理：本工具是自行 quit 的，不清理会留下
	# 「ERROR: N resources still in use at exit」——而那行会被门禁的 ERROR 断言判为失败。
	# hud 挂在树根上不会随脚本退出自动释放，dn 根本没入树，两者都得手动 free。
	hud.free()
	dn.free()

	if _fails.is_empty():
		print("PASS：HUD 对外接口全部正常（%d 项断言）" % _total)
		quit(0)
	else:
		print("FAIL：%d/%d 项断言未通过 —— %s" % [_fails.size(), _total, "; ".join(_fails)])
		quit(1)
