## =============================================================================
##  input_check —— 输入层回归（**不参与游戏运行**，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/input_check.gd
##
##  第三轮把键位搬进 project.godot 的 [input] 段，并加了 InputRouter 做分发。
##  「手柄能不能玩」「键位改错了没」「遭遇框能不能用键盘作答」以前只能点开游戏按一按，
##  这里把它们变成断言：
##    1. [input] 段是否真被引擎读进了 InputMap（动作存在 + 有事件 + 关键键位对得上）
##    2. 每个动作是否都绑了手柄（否则「手柄支持」只是口号）
##    3. InputRouter 的分发与让路（遭遇框 / 进城菜单打开、战斗中、点海面都不该发出命令）
##    4. 遭遇框：打开即拿焦点、ui_cancel 撤退、ui_accept 真的能按下去（走完整输入管线）
##    5. 进城菜单（第四轮 4b-2）：灰掉的条目拿不到焦点、↓ 跳过灰条目、
##       确认键按下当前焦点条目、Esc 只发「离开」而不自己关面板
##
##  退出码：0 = 全部通过；1 = 有断言失败
## =============================================================================
extends SceneTree

## 相机替身：真 CameraRig 要有高度场才能 ray_to_terrain，而本工具不跑地图生成。
## 覆盖这一个方法就够 —— InputRouter 只通过它把屏幕坐标换成世界坐标。
class StubRig extends CameraRig:
	var hit := Vector3(50.0, 5.0, 60.0)
	func ray_to_terrain(_screen_pos: Vector2) -> Vector3:
		return hit

## 大地图 / 战斗 / 调试用到的全部动作（改名或漏绑都会在这里红）
const ACTIONS: Array = [
	"move_up", "move_down", "move_left", "move_right",
	"zoom_in", "zoom_out", "cam_rotate_left", "cam_rotate_right",
	"cam_rotate_up", "cam_rotate_down", "focus_party",
	"time_flow", "cycle_speed", "toggle_vegetation", "toggle_mute",
	"faction_labels_1", "faction_labels_2", "faction_labels_3",
	"battle_attack", "battle_jump", "battle_dodge", "battle_parry",
	"battle_pause", "debug_toggle",
	"dialog_confirm", "dialog_cancel", "dialog_next", "dialog_prev",
	"interact",
]

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
	print("[输入] InputMap 动作表 / InputRouter 分发 / 遭遇框键盘作答")
	_check_bindings()
	await _check_router()
	await _check_dialog()
	await _check_settlement_dialog()
	if _fails.is_empty():
		print("PASS：输入层全部正常（%d 项断言）" % _total)
		quit(0)
	else:
		print("FAIL：%d/%d 项断言未通过 —— %s" % [_fails.size(), _total, "; ".join(_fails)])
		quit(1)

## 进城菜单的测试条目（形状与 SettlementSystem.menu_entries() 一致）
func _entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"id": "supply", "label": "买补给 ×1（5 金）", "enabled": true, "hint": "现有 35 件"},
		{"id": "recruit", "label": "招 募（10 金/人）", "enabled": false, "hint": "没有志愿者"},
		{"id": "leave", "label": "离 开", "enabled": true, "hint": "回到大地图"},
	]
	return out

# ---------------------------------------------------------------- 4) 进城菜单
func _check_settlement_dialog() -> void:
	var cfg := MapConfig.new()
	var hud := HUD.new()
	get_root().add_child(hud)
	hud.setup(cfg)
	await process_frame
	var actions: Array = []
	hud.settlement_action.connect(func(a: String): actions.append(a))

	hud.show_settlement_menu("测试镇　城镇", "测试镇 · 城镇 · 繁荣 80 · 驻军 12 人", _entries())
	await process_frame
	_ok(hud.is_settlement_open(), "show_settlement_menu 后菜单打开")
	_ok(hud.is_any_dialog_open(), "is_any_dialog_open 把进城菜单也算上")
	_ok(hud.settlement_dialog.row_actions() == ["supply", "recruit", "leave"],
		"条目顺序原样来自数据：%s" % [hud.settlement_dialog.row_actions()])
	_ok(hud.settlement_dialog.row_enabled() == [true, false, true],
		"灰化状态原样来自数据：%s" % [hud.settlement_dialog.row_enabled()])
	_ok(hud.settlement_dialog.row_hints()[1] == "没有志愿者",
		"灰掉的行仍然带原因：%s" % hud.settlement_dialog.row_hints()[1])
	_ok(hud.settlement_dialog.row_button(1).focus_mode == Control.FOCUS_NONE,
		"灰掉的行被移出焦点序列（免得焦点卡在按不动的按钮上）")

	# 打开即拿焦点，且拿的是**第一个可用**条目（第 0 行）
	var first := hud.settlement_dialog.row_button(0)
	_ok(first != null and first.has_focus(), "打开时焦点给第一个可用条目")

	# 键位提示来自 InputMap（不写死按键）
	_ok(hud.settlement_dialog.hint_label.text.contains("回车")
		and hud.settlement_dialog.hint_label.text.contains("Esc"),
		"菜单键位提示来自 InputMap：%s" % hud.settlement_dialog.hint_label.text)

	# ↓ 换焦点：应当跳过灰掉的第 1 行，落到第 2 行（内建焦点导航）
	_press(KEY_DOWN)
	await process_frame
	await process_frame
	var third := hud.settlement_dialog.row_button(2)
	_ok(third != null and third.has_focus(), "↓ 跳过灰掉的条目，落到下一行可用条目")

	# 确认键 → 按下当前焦点按钮（这是「手柄没有内建 ui_accept」的兜底）
	_press(KEY_ENTER)
	await process_frame
	_ok(actions == ["leave"], "回车按下当前焦点条目（得到 %s）" % [actions])

	# 面板不自己关：买完还要接着买，关不关由业务层决定
	_ok(hud.is_settlement_open(), "选完一条菜单仍然开着（等业务层决定关不关）")

	# 取消键 → 离开（同样只是发个信号）
	actions.clear()
	hud.settlement_dialog._unhandled_input(_key(KEY_ESCAPE))
	_ok(actions == ["leave"], "Esc → 离开（得到 %s）" % [actions])
	_ok(hud.is_settlement_open(), "Esc 也不自己关面板（由 SettlementSystem 关）")

	hud.hide_settlement()
	_ok(not hud.is_any_dialog_open(), "hide_settlement 后面板与「任一面板在场」都归零")

	hud.free()

# ---------------------------------------------------------------- 1) 键位表
func _check_bindings() -> void:
	for a in ACTIONS:
		_ok(InputMap.has_action(a), "动作存在于 InputMap：%s" % a)
		if InputMap.has_action(a):
			_ok(InputMap.action_get_events(a).size() > 0, "动作绑定了事件：%s" % a)
	# 关键键位：故意写死几条，挡住「[input] 段被改坏 / 被覆盖」
	_ok(_has_key("time_flow", KEY_SPACE), "time_flow 绑了空格")
	_ok(_has_key("cycle_speed", KEY_R), "cycle_speed 绑了 R")
	_ok(_has_key("toggle_mute", KEY_M), "toggle_mute 绑了 M")
	_ok(_has_key("toggle_vegetation", KEY_V), "toggle_vegetation 绑了 V")
	_ok(_has_key("move_left", KEY_A), "move_left 绑了 A")
	_ok(_has_key("move_right", KEY_D), "move_right 绑了 D")
	_ok(_has_key("focus_party", KEY_F), "focus_party 绑了 F")
	_ok(_has_key("battle_dodge", KEY_SHIFT), "battle_dodge 绑了 Shift")
	_ok(_has_mouse("battle_attack", MOUSE_BUTTON_LEFT), "battle_attack 绑了鼠标左键")
	_ok(_has_mouse("battle_parry", MOUSE_BUTTON_RIGHT), "battle_parry 绑了鼠标右键")
	_ok(_has_mouse("zoom_in", MOUSE_BUTTON_WHEEL_UP), "zoom_in 绑了滚轮上")
	_ok(_has_mouse("zoom_out", MOUSE_BUTTON_WHEEL_DOWN), "zoom_out 绑了滚轮下")
	# 遭遇框的四个动作：键盘 + 手柄都要有。内建 ui_accept / ui_cancel 只绑了键盘
	# （dump 出来就 3 个键盘事件、没有手柄事件），直接拿它们当对话框按键，手柄就答不了题。
	_ok(_has_key("dialog_confirm", KEY_ENTER), "dialog_confirm 绑了回车")
	_ok(_has_key("dialog_confirm", KEY_KP_ENTER), "dialog_confirm 绑了小键盘回车")
	_ok(_has_joypad("dialog_confirm"), "dialog_confirm 绑了手柄确认键")
	_ok(_has_key("dialog_cancel", KEY_ESCAPE), "dialog_cancel 绑了 Esc")
	_ok(_has_joypad("dialog_cancel"), "dialog_cancel 绑了手柄取消键")
	_ok(_has_key("dialog_next", KEY_RIGHT), "dialog_next 绑了 →")
	_ok(_has_joypad("dialog_next"), "dialog_next 绑了手柄（十字键 / 肩键）")
	_ok(_has_key("dialog_prev", KEY_LEFT), "dialog_prev 绑了 ←")
	_ok(_has_joypad("dialog_prev"), "dialog_prev 绑了手柄（十字键 / 肩键）")
	# 进城交互键（第四轮 4b-2）：键盘 G + 手柄 A。
	# 手柄只有 A 这个选择 —— B/X/Y 分别是取消 / 时间 / 流速，十字键四向全给了移动。
	# 与 dialog_confirm 共用手柄 A 是有意的：A = 「确认 / 交互」是同一件事，
	# 而菜单开着时 InputRouter 整体让路，两者不会同时触发。
	_ok(_has_key("interact", KEY_G), "interact 绑了 G")
	_ok(_has_joypad("interact"), "interact 绑了手柄 A")
	# 手柄覆盖：这 19 个是「手柄能不能玩」的全部依赖
	var pad: Array = ["move_up", "move_down", "move_left", "move_right", "zoom_in", "zoom_out",
		"cam_rotate_left", "cam_rotate_right", "cam_rotate_up", "cam_rotate_down", "focus_party",
		"time_flow", "cycle_speed", "battle_attack", "battle_jump", "battle_dodge", "battle_parry",
		"battle_pause", "interact"]
	var no_pad := PackedStringArray()
	for a in pad:
		if not _has_joypad(a):
			no_pad.append(a)
	_ok(no_pad.is_empty(), "全部关键动作都绑了手柄（缺：%s）" % ("无" if no_pad.is_empty() else ", ".join(no_pad)))
	# 内建 ui_* 动作：遭遇框的「确认 / 取消」依赖它们存在
	_ok(InputMap.has_action("ui_accept") and InputMap.has_action("ui_cancel"),
		"内建 ui_accept / ui_cancel 可用（遭遇框确认 / 撤退依赖）")
	# 绑定 → 文本（操作说明面板与提示条靠它，不再写死按键）
	var mute_txt := InputRouter.action_keys_text("toggle_mute")
	_ok(mute_txt.contains("M"), "绑定文本可读：toggle_mute = %s" % mute_txt)
	var focus_txt := InputRouter.action_keys_text("focus_party")
	_ok(focus_txt.contains("手柄"), "绑定文本含手柄绑定：focus_party = %s" % focus_txt)
	# 一行提示版：一个键盘 + 一个手柄，别把 4 个同义键都堆上去
	_ok(InputRouter.action_hint_text("dialog_confirm") == "回车 / 手柄A",
		"一行提示版只取键盘 + 手柄各一个：dialog_confirm = %s" % InputRouter.action_hint_text("dialog_confirm"))
	_ok(InputRouter.action_hint_text("no_such_action") == "未绑定", "一行提示版对未知动作同样返回「未绑定」")
	_ok(InputRouter.action_keys_text("no_such_action") == "未绑定", "未知动作返回「未绑定」")

func _has_key(action: String, code: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			if k.physical_keycode == code or k.keycode == code:
				return true
	return false

func _has_mouse(action: String, btn: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == btn:
			return true
	return false

func _has_joypad(action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			return true
	return false

# ---------------------------------------------------------------- 2) 分发
func _check_router() -> void:
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

	var orders: Array = []
	var hits: Dictionary = {}
	router.order_move.connect(func(g: Vector2): orders.append(g))
	router.cycle_speed_requested.connect(func(): hits["speed"] = true)
	router.toggle_vegetation_requested.connect(func(): hits["veg"] = true)
	router.toggle_mute_requested.connect(func(): hits["mute"] = true)
	router.faction_labels_requested.connect(func(fid: int): hits["fid"] = fid)
	router.interact_requested.connect(func(): hits["interact"] = true)

	# 点地图 → 行军命令（坐标来自 ray_to_terrain）
	router._unhandled_input(_click(Vector2(800, 450)))
	_ok(orders.size() == 1 and orders[0].is_equal_approx(Vector2(50, 60)),
		"点地图 → order_move(Vector2(50, 60))　得到 %s" % [orders])
	# 点到海面（低于 sea_level）→ 不下命令
	orders.clear()
	rig.hit = Vector3(50.0, cfg.sea_level - 5.0, 60.0)
	router._unhandled_input(_click(Vector2(800, 450)))
	_ok(orders.is_empty(), "点到海面不发行军命令")
	rig.hit = Vector3(50.0, 5.0, 60.0)

	# 动作 → 语义信号
	router._unhandled_input(_key(KEY_R))
	_ok(hits.get("speed", false), "R（cycle_speed）→ cycle_speed_requested")
	router._unhandled_input(_key(KEY_V))
	_ok(hits.get("veg", false), "V → toggle_vegetation_requested")
	router._unhandled_input(_key(KEY_M))
	_ok(hits.get("mute", false), "M → toggle_mute_requested")
	router._unhandled_input(_key(KEY_2))
	_ok(hits.get("fid", -1) == 1, "2 → faction_labels_requested(1)　得到 %s" % [hits.get("fid", -1)])
	# 手柄事件也应当走同一条路（摇杆 / 按键都能触发，说明不是只认键盘）
	hits.clear()
	router._unhandled_input(_pad_button(JOY_BUTTON_Y))
	_ok(hits.get("speed", false), "手柄 Y（= cycle_speed）同样触发 cycle_speed_requested")
	hits.clear()
	router._unhandled_input(_key(KEY_SPACE))
	_ok(hits.is_empty() and orders.is_empty(), "time_flow 是「按住」类动作，不在这里发一次性信号")

	# 交互键（第四轮 4b-2）：键盘 G 与手柄 A 都要发出来
	router._unhandled_input(_key(KEY_G))
	_ok(hits.get("interact", false), "G（interact）→ interact_requested")
	hits.clear()
	router._unhandled_input(_pad_button(JOY_BUTTON_A))
	_ok(hits.get("interact", false), "手柄 A（interact）→ interact_requested")
	hits.clear()

	# 遭遇框打开 → 键盘鼠标全部让路（G3：键盘要先留给对话框）
	hud.show_encounter("遭遇 测试部队", "测试说明", Color(1, 1, 1))
	await process_frame
	orders.clear()
	hits.clear()
	router._unhandled_input(_click(Vector2(800, 450)))
	router._unhandled_input(_key(KEY_R))
	_ok(orders.is_empty() and hits.is_empty(), "遭遇框打开时点击与热键都让路给对话框")
	hud.hide_encounter()

	# 进城菜单打开 → 同样整体让路（菜单会锁世界时间，键盘归它；交互键也不能二次开菜单）
	hud.show_settlement_menu("测试镇　城镇", "测试镇 · 城镇", _entries())
	await process_frame
	orders.clear()
	hits.clear()
	router._unhandled_input(_click(Vector2(800, 450)))
	router._unhandled_input(_key(KEY_R))
	router._unhandled_input(_key(KEY_G))
	_ok(orders.is_empty() and hits.is_empty(),
		"进城菜单打开时点击 / 热键 / 交互键都让路")
	hud.hide_settlement()

	# 战斗中关掉路由
	router.enabled = false
	orders.clear()
	hits.clear()
	router._unhandled_input(_click(Vector2(800, 450)))
	router._unhandled_input(_key(KEY_R))
	_ok(orders.is_empty() and hits.is_empty(), "战斗中（enabled = false）不发任何信号")

	router.free()
	hud.free()
	rig.free()

# ---------------------------------------------------------------- 3) 遭遇框
func _check_dialog() -> void:
	var cfg := MapConfig.new()
	var hud := HUD.new()
	get_root().add_child(hud)
	hud.setup(cfg)
	await process_frame
	var choices: Array = []
	hud.encounter_choice.connect(func(a: String): choices.append(a))

	# 打开即拿焦点：这是「键盘 / 手柄能作答」的前提
	hud.show_encounter("遭遇 测试部队", "测试说明", Color(1, 1, 1))
	await process_frame
	_ok(hud.dialog.attack_button.has_focus(), "遭遇框打开时「攻击」拿到焦点")
	_ok(hud.dialog.hint_label.text.contains("回车") and hud.dialog.hint_label.text.contains("Esc"),
		"对话框键位提示来自 InputMap：%s" % hud.dialog.hint_label.text)

	# 取消键 → 撤退（焦点在按钮上时没人消费 dialog_cancel，落到对话框自己的 _unhandled_input）
	var esc := _key(KEY_ESCAPE)
	_ok(esc.is_action_pressed("dialog_cancel"), "Esc 匹配动作 dialog_cancel")
	hud.dialog._unhandled_input(esc)
	_ok(choices == ["retreat"], "Esc → 撤退（得到 %s）" % [choices])
	_ok(not hud.is_encounter_open(), "撤退后对话框关闭")
	_ok(not hud.dialog.attack_button.has_focus(), "关闭后焦点已释放（免得空格又按到上次的按钮）")

	# 确认键走完整输入管线：焦点在「攻击」上，回车应当把它按下去
	choices.clear()
	hud.show_encounter("遭遇 测试部队", "测试说明", Color(1, 1, 1))
	await process_frame
	_ok(hud.dialog.attack_button.has_focus(), "重新打开后焦点回到「攻击」")
	_press(KEY_ENTER)
	await process_frame
	await process_frame
	_ok(choices == ["attack"], "回车（dialog_confirm）→ 攻击（得到 %s）" % [choices])

	# 手柄确认键：内建 ui_accept 没有手柄事件，全靠 dialog_confirm
	choices.clear()
	hud.show_encounter("遭遇 测试部队", "测试说明", Color(1, 1, 1))
	await process_frame
	Input.parse_input_event(_pad_button(JOY_BUTTON_A))
	await process_frame
	await process_frame
	_ok(choices == ["attack"], "手柄 A（dialog_confirm）→ 攻击（得到 %s）" % [choices])

	# 手柄取消键
	choices.clear()
	hud.show_encounter("遭遇 测试部队", "测试说明", Color(1, 1, 1))
	await process_frame
	Input.parse_input_event(_pad_button(JOY_BUTTON_B))
	await process_frame
	await process_frame
	_ok(choices == ["retreat"], "手柄 B（dialog_cancel）→ 撤退（得到 %s）" % [choices])

	# 焦点可以在两个按钮之间移动（键盘 →，手柄十字键 / 肩键同理）
	choices.clear()
	hud.show_encounter("遭遇 测试部队", "测试说明", Color(1, 1, 1))
	await process_frame
	_press(KEY_RIGHT)
	await process_frame
	await process_frame
	_ok(hud.dialog.retreat_button.has_focus(), "→ 把焦点移到「撤退」")
	_press(KEY_ENTER)
	await process_frame
	await process_frame
	_ok(choices == ["retreat"], "回车确认焦点上的「撤退」（得到 %s）" % [choices])

	# 手柄 D-pad 也能切换焦点
	choices.clear()
	hud.show_encounter("遭遇 测试部队", "测试说明", Color(1, 1, 1))
	await process_frame
	Input.parse_input_event(_pad_button(JOY_BUTTON_DPAD_RIGHT))
	await process_frame
	await process_frame
	_ok(hud.dialog.retreat_button.has_focus(), "手柄十字键→ 把焦点移到「撤退」")
	Input.parse_input_event(_pad_button(JOY_BUTTON_DPAD_LEFT))
	await process_frame
	await process_frame
	_ok(hud.dialog.attack_button.has_focus(), "手柄十字键← 把焦点移回「攻击」")
	hud.hide_encounter()

	hud.free()

# ---------------------------------------------------------------- 事件构造
## 注意两个坑（都是实测出来的）：
##  1) device 必须留默认的 0。写成 -1（InputEvent.DEVICE_ID_EMULATION）时，
##     [input] 段里 device=-1 的动作照样匹配，但引擎内建 ui_* 动作（device=0）一律不匹配，
##     表现为「明明按了 Esc，对话框却没反应」——而这是测试代码的错，不是游戏的错。
##  2) keycode 与 physical_keycode 都写上：本工程的动作用 physical 声明，
##     引擎内建 ui_* 用 keycode；两者同时给出时两种动作都能匹配上。
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

func _pad_button(btn: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	e.pressed = true
	return e

## 走真实输入管线（Input → Viewport → 焦点控件），用来验「按键真的能按下按钮」
func _press(code: int) -> void:
	Input.parse_input_event(_key(code))