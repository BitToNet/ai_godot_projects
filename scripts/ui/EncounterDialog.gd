## =============================================================================
##  EncounterDialog —— 遭遇对话框（选项表由业务层给，本面板只负责画）
##
##  第四轮 4c 起与 SettlementDialog 同构：**面板不做任何业务判断，也不自己决定何时关闭**。
##    · 有哪些选项 / 能不能点 / 为什么不能点，全由 EncounterSystem.options() 给（数据驱动）；
##    · 点一行只发 choice(action)，面板保持打开 —— 关不关由业务层决定：
##      例如「钱不够」时 EncounterSystem 会静默拒绝，对话框正好留着让玩家改主意；
##    · 灰掉的行**必须**带一行小字说明原因（「领主不收买路钱」），不留一个点不动的空按钮；
##    · 没传 entries 时用 default_entries()（攻击 / 撤退）兜底：截图脚本与早期自检
##      用的就是这一对，面板至少是能看能用的，而不是空的。
##
##  键盘 / 手柄：打开时焦点给第一个可用条目（↑↓ / ←→ 移动，内建焦点导航），
##  确认键 = 按下当前焦点按钮（手柄没有内建 ui_accept，这里兜一层），
##  Esc / 手柄 B = 撤退。取消键**故意不跟随光标**：遭遇框里最危险的动作是「攻击」，
##  不能因为光标恰好停在攻击上就把玩家送进战斗（连按取消的肌肉记忆会害死人）。
##
##  mouse_filter = STOP：对话框打开时必须挡住「点地行军」。
## =============================================================================
class_name EncounterDialog
extends Control

signal choice(action: String)

var _title: Label
var _info: Label
var _rows: VBoxContainer
var hint_label: Label
var rows_panel: PanelContainer

var _buttons: Array[Button] = []
var _actions: Array[String] = []
var _hints: Array[String] = []

## 默认两行（攻击 / 撤退）。只有「没有数据来源」的调用点才会走到它：
## tools/hud_shot.gd 的截图、以及只关心开关行为的自检。
static func default_entries() -> Array[Dictionary]:
	return [
		{"id": "attack", "label": "攻 击", "enabled": true, "hint": "进入 Boss 战"},
		{"id": "retreat", "label": "撤 退", "enabled": true, "hint": "不战而走（有代价）"},
	]

## 便捷入口：默认两行时的「攻击 / 撤退」按钮（截图脚本与早期自检按名字取）。
## 面板的权威数据始终是 entries → _buttons / _actions：这两个字段每次 _rebuild 都跟着重设，
## 所以不存在「两份数据打架」的可能（取不到时是 null，调用点会立刻炸出来，而不是静默画错）。
var attack_button: Button = null
var retreat_button: Button = null

func _ready() -> void:
	# 同 LoadingOverlay：只设 anchors 会保留 0×0 的当前矩形，offsets 变成 (0,0,-1600,-900)，
	# 结果是对话框缩在左上角、压住左上信息栏，且半透明遮罩完全没有尺寸。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.35)
	add_child(dim)

	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cc)

	rows_panel = UiTheme.panel(Color(0.06, 0.05, 0.07, 0.95),
		Color(0.88, 0.80, 0.55, 0.9), false)
	cc.add_child(rows_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(480, 0)
	rows_panel.add_child(vb)

	_title = UiTheme.label("", 26, Color(0.95, 0.88, 0.66))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)

	_info = UiTheme.label("", 16, Color(0.88, 0.90, 0.95))
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_info)

	vb.add_child(HSeparator.new())

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	vb.add_child(_rows)

	# 键位提示直接从 InputMap 读（改键位这里跟着变，不再写死「按 X」）
	hint_label = UiTheme.label("%s 确认      %s 撤退      ↑↓ 选择条目" % [
		InputRouter.action_hint_text("dialog_confirm"),
		InputRouter.action_hint_text("dialog_cancel")], 14, Color(0.68, 0.70, 0.76))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint_label)

## 打开对话框。entries 来自 EncounterSystem.options()：每项 {id, label, enabled, hint}，
## 顺序即显示顺序；空数组 = 用 default_entries() 兜底。
func open(title: String, info: String, color: Color, entries: Array = []) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", color)
	_info.text = info
	_rebuild(entries if not entries.is_empty() else default_entries())
	visible = true
	# 键盘 / 手柄作答的前提是「有东西拿着焦点」：按钮拿到焦点后，
	# ↑↓ 切换条目、ui_accept 确认 才成立。旧版从不 grab_focus()，于是遭遇框只能点鼠标（G3）。
	var first := _first_enabled()
	if first != null:
		first.grab_focus()

func close() -> void:
	visible = false
	_release_focus()

func is_open() -> bool:
	return visible

# ---------------------------------------------------------------- 条目构建
## entries 有意保持**弱类型 Array**：数据来源（EncounterSystem.options()）是
## Array[Dictionary]，而 default_entries() 的兜底也不能被类型转换挡住。
func _rebuild(entries: Array) -> void:
	_release_focus()
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_buttons.clear()
	_actions.clear()
	_hints.clear()
	attack_button = null
	retreat_button = null
	for e in entries:
		var ed: Dictionary = e
		var act := String(ed.get("id", ""))
		var hint := String(ed.get("hint", ""))
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)

		var b := Button.new()
		b.text = "  %s  " % String(ed.get("label", act))
		b.add_theme_font_size_override("font_size", 18)
		b.disabled = not bool(ed.get("enabled", false))
		# 灰掉的行必须从焦点序列里彻底消失：焦点落在不能按的按钮上是死路一条
		b.focus_mode = Control.FOCUS_ALL if not b.disabled else Control.FOCUS_NONE
		b.pressed.connect(func() -> void: _answer(act))
		row.add_child(b)

		if hint != "":
			var h := UiTheme.label(hint, 12, Color(0.66, 0.70, 0.76))
			h.name = "Hint"
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(h)

		_rows.add_child(row)
		_buttons.append(b)
		_actions.append(act)
		_hints.append(hint)
		if act == "attack":
			attack_button = b
		elif act == "retreat":
			retreat_button = b

func _first_enabled() -> Button:
	for b in _buttons:
		if not b.disabled:
			return b
	return null

func _release_focus() -> void:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f is Button and is_ancestor_of(f):
		(f as Button).release_focus()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("dialog_cancel"):
		_answer("retreat")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dialog_confirm"):
		# 焦点在按钮上时，键盘确认键其实由按钮自己消费（内建 ui_accept）；
		# 手柄没有内建 ui_accept 绑定，所以确认也在这里再兜一层。
		var f := get_viewport().gui_get_focus_owner()
		if f is Button and is_ancestor_of(f):
			(f as Button).pressed.emit()
		else:
			var fb := _first_enabled()
			if fb != null:
				fb.pressed.emit()
		get_viewport().set_input_as_handled()

## 面板自己**不**隐藏：发完信号就走，关不关由业务层决定（见文件头）。
func _answer(action: String) -> void:
	choice.emit(action)

# ---------------------------------------------------------------- 给自检用
func row_actions() -> Array[String]:
	return _actions

func row_hints() -> Array[String]:
	return _hints

func row_enabled() -> Array[bool]:
	var out: Array[bool] = []
	for b in _buttons:
		out.append(not b.disabled)
	return out

func row_button(i: int) -> Button:
	if i < 0 or i >= _buttons.size():
		return null
	return _buttons[i]