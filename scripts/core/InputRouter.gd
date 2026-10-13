## =============================================================================
##  InputRouter —— 大地图输入路由
##
##  为什么单独成文件：输入原本散在三处、各自写死物理键码 ——
##  Main._unhandled_input（R/V/M/1/2/3）、CameraRig._process（W/A/S/D）、
##  BattleScene._read_input（A/D/空格/Shift）。于是「手柄能玩」「键位可改」
##  「遭遇框能用键盘作答」三件事一件都做不到。
##
##  现在统一走 project.godot 的 [input] 动作表：
##    · 本文件只按动作名分发，加手柄 / 改键位不必动代码
##    · Main 只收语义信号（order_move / cycle_speed / …），不碰键码
##    · CameraRig / BattleScene 用 Input.get_vector / get_axis / 动作查询，
##      摇杆的力度直接就是模拟量
##
##  遭遇 / 进城对话框打开时本路由整体让路：键盘要先留给对话框作答（确认 / 取消 / 焦点）。
##  战斗中由 Main 关掉本路由（enabled = false），输入归 BattleScene。
## =============================================================================
class_name InputRouter
extends Node

## 点击地图下达行军命令（世界坐标）
signal order_move(goal: Vector2)
signal cycle_speed_requested
signal toggle_vegetation_requested
signal toggle_mute_requested
signal faction_labels_requested(faction_id: int)
## 进城 / 交互（第四轮 4b-2）：只表示「玩家想跟脚下的定居点打交道」，
## 附近有没有定居点、能不能进，由 SettlementSystem 判断 —— 路由不认识地图数据。
signal interact_requested
## 存 / 读档（第四轮 4d）。刻意**不**经过「面板在场就整体让路」那道闸：
## 面板状态不进存档（见 SaveGame.gd 文件头取舍 3），所以「能不能存」由业务层判并说明理由，
## 而不是按了没反应。
signal save_requested
signal load_requested

var camera_rig: CameraRig
var hud: HUD
var cfg: MapConfig
var enabled: bool = true

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or camera_rig == null or cfg == null:
		return
	# 遭遇 / 进城对话框在场时键盘鼠标都属于它。否则按 R / V / M / 1 会在
	# 「请决定行动」的同时把地图改掉，而对话框自己收不到任何按键。
	# 进城菜单同理：菜单开着时点地图行军 / 切流速都该被挡住（菜单自己会锁世界时间）。
	# 存 / 读档先于「对话框让路」：面板开着时也要能把请求送出去，
	# 由 Main 决定拒还是放（并给出一句为什么），见上面的信号注释。
	if event.is_action_pressed("quicksave"):
		save_requested.emit()
		return
	if event.is_action_pressed("quickload"):
		load_requested.emit()
		return
	if hud != null and hud.is_any_dialog_open():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 点到 UI 的点击不会走到 _unhandled_input；能到这里的左键都是「点地图」
		var hit := camera_rig.ray_to_terrain(event.position)
		if hit.y > cfg.sea_level + 0.2:
			order_move.emit(Vector2(hit.x, hit.z))
		return
	if event.is_action_pressed("interact"):
		interact_requested.emit()
	elif event.is_action_pressed("cycle_speed"):
		cycle_speed_requested.emit()
	elif event.is_action_pressed("toggle_vegetation"):
		toggle_vegetation_requested.emit()
	elif event.is_action_pressed("toggle_mute"):
		toggle_mute_requested.emit()
	elif event.is_action_pressed("faction_labels_1"):
		faction_labels_requested.emit(0)
	elif event.is_action_pressed("faction_labels_2"):
		faction_labels_requested.emit(1)
	elif event.is_action_pressed("faction_labels_3"):
		faction_labels_requested.emit(2)

# =============================================================== 绑定 → 文本
## 把动作当前的绑定读成可读文本（供操作说明 / 提示条显示）。
## 界面里因此不再写死「按 M 切换」这类字面按键 —— 改了 [input] 段，界面跟着变。
static func action_keys_text(action: String, sep: String = " / ") -> String:
	if not InputMap.has_action(action):
		return "未绑定"
	var parts := PackedStringArray()
	for ev in InputMap.action_get_events(action):
		var s := _event_text(ev)
		if s != "" and not parts.has(s):
			parts.append(s)
	return "未绑定" if parts.is_empty() else sep.join(parts)

## 只要「一个键盘绑定 + 一个手柄绑定」。对话框底部那种一行提示用这个：
## 完整键位表（一个有 4 个同义键）会把那一行撑得很长，读起来像报菜名。
static func action_hint_text(action: String, sep: String = " / ") -> String:
	if not InputMap.has_action(action):
		return "未绑定"
	var key_txt := ""
	var pad_txt := ""
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			if pad_txt == "":
				pad_txt = _event_text(ev)
		elif key_txt == "":
			key_txt = _event_text(ev)
	var parts := PackedStringArray()
	if key_txt != "":
		parts.append(key_txt)
	if pad_txt != "":
		parts.append(pad_txt)
	return "未绑定" if parts.is_empty() else sep.join(parts)

static func _event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return _key_name(code)
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "左键"
			MOUSE_BUTTON_RIGHT:
				return "右键"
			MOUSE_BUTTON_MIDDLE:
				return "中键"
			MOUSE_BUTTON_WHEEL_UP:
				return "滚轮上"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "滚轮下"
		return "鼠标键"
	if ev is InputEventJoypadButton:
		return _joy_button_name((ev as InputEventJoypadButton).button_index)
	if ev is InputEventJoypadMotion:
		return _joy_axis_name((ev as InputEventJoypadMotion).axis)
	return ""

## 键名要中文：OS.get_keycode_string() 给的是 "Enter" / "Kp Enter" / "Escape"，
## 混在「左键 / 手柄A / 十字键右」里很跳，所以常见键先查表，剩下的才回落到引擎名。
static func _key_name(code: int) -> String:
	match code:
		KEY_ENTER:
			return "回车"
		KEY_KP_ENTER:
			return "小键盘回车"
		KEY_SPACE:
			return "空格"
		KEY_ESCAPE:
			return "Esc"
		KEY_TAB:
			return "Tab"
		KEY_SHIFT:
			return "Shift"
		KEY_CTRL:
			return "Ctrl"
		KEY_ALT:
			return "Alt"
		KEY_UP:
			return "↑"
		KEY_DOWN:
			return "↓"
		KEY_LEFT:
			return "←"
		KEY_RIGHT:
			return "→"
		KEY_BACKSPACE:
			return "退格"
	return OS.get_keycode_string(code)

static func _joy_button_name(b: int) -> String:
	match b:
		JOY_BUTTON_A:
			return "手柄A"
		JOY_BUTTON_B:
			return "手柄B"
		JOY_BUTTON_X:
			return "手柄X"
		JOY_BUTTON_Y:
			return "手柄Y"
		JOY_BUTTON_BACK:
			return "手柄Back"
		JOY_BUTTON_START:
			return "手柄Start"
		JOY_BUTTON_LEFT_SHOULDER:
			return "手柄L1"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "手柄R1"
		JOY_BUTTON_DPAD_UP:
			return "十字键上"
		JOY_BUTTON_DPAD_DOWN:
			return "十字键下"
		JOY_BUTTON_DPAD_LEFT:
			return "十字键左"
		JOY_BUTTON_DPAD_RIGHT:
			return "十字键右"
	return "手柄键%d" % b

static func _joy_axis_name(axis: int) -> String:
	match axis:
		JOY_AXIS_LEFT_X:
			return "左摇杆左右"
		JOY_AXIS_LEFT_Y:
			return "左摇杆上下"
		JOY_AXIS_RIGHT_X:
			return "右摇杆左右"
		JOY_AXIS_RIGHT_Y:
			return "右摇杆上下"
		JOY_AXIS_TRIGGER_LEFT:
			return "手柄LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "手柄RT"
	return "手柄轴%d" % axis