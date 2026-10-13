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

	# ---- 遭遇对话框 ----
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
	_ok(hud.dialog.attack_button.text.contains("攻"), "攻击按钮就位")

	hud.show_tooltip("提示", Vector2(10, 10))
	_ok(not hud._tooltip.visible, "对话框打开时悬停提示被抑制")

	hud.dialog.attack_button.pressed.emit()
	await process_frame
	_ok(not hud.is_encounter_open(), "点「攻击」后对话框自动关闭")
	_ok(got == ["attack"], "re-emit 成 encounter_choice（得到 %s）" % str(got))

	hud.show_encounter("遭遇 测试部队", "测试说明", Color(1, 1, 1))
	hud.dialog.retreat_button.pressed.emit()
	await process_frame
	_ok(got == ["attack", "retreat"], "「撤退」同样转发")

	hud.show_encounter("x", "y", Color(1, 1, 1))
	hud.hide_encounter()
	_ok(not hud.is_encounter_open(), "hide_encounter 关闭对话框")

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
