## =============================================================================
##  SettlementDialog —— 进城菜单（补给 / 招募 / 贸易 / 驻军）
##
##  与 EncounterDialog 的关键区别：**本面板不做任何业务判断，也不自己决定何时关闭**。
##    · 条目（做什么 / 能不能做 / 为什么不能做）由 SettlementSystem.menu_entries() 给，
##      这里只照着画 —— 于是「钱不够 / 编制满 / 池子空 / 城里没兵 / 没货可卖」
##      五类边界可以在没有窗口的情况下直接断言（tools/settlement_check.gd）。
##    · 点一行只发 choice(action)，**面板保持打开**：买完补给还要接着招兵 / 赶集，
##      每次都关掉再按一次键的菜单没人愿意用。何时关由业务层（resolve("leave") →
##      closed 信号）决定，HUD 收到后再 hide_settlement()。
##    · 灰掉的行**必须**带一行小字说明原因（「钱不够（需 5 金）」），而不是让玩家
##      对着一个点不动的按钮猜。原因文字与按钮一起放在同一行组里，永远可见。
##
##  键盘 / 手柄：打开时焦点给第一个可用条目（↑↓ / ←→ 移动，内建焦点导航），
##  确认键 = 按下当前焦点按钮（手柄没有内建 ui_accept，这里兜一层），
##  Esc / 手柄 B = 「离开」。
## =============================================================================
class_name SettlementDialog
extends Control

signal choice(action: String)

var _title: Label
var _status: Label
var _rows: VBoxContainer
var hint_label: Label
var rows_panel: PanelContainer

var _buttons: Array[Button] = []
var _actions: Array[String] = []
var _hints: Array[String] = []

func _ready() -> void:
	# 与 EncounterDialog 同样的坑：只设 anchors 会保留 0×0 的当前矩形
	# （offsets 变成 (0,0,-1600,-900)），面板会缩在左上角。
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
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(520, 0)
	rows_panel.add_child(vb)

	_title = UiTheme.label("", 26, Color(0.95, 0.88, 0.66))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)

	_status = UiTheme.label("", 15, Color(0.72, 0.78, 0.86))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_status)

	vb.add_child(HSeparator.new())

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	vb.add_child(_rows)

	# 键位提示同样从 InputMap 读：改了 [input] 段这里跟着变，不写死「按 G」。
	hint_label = UiTheme.label("%s 确认      %s 离开      ↑↓ 选择条目" % [
		InputRouter.action_hint_text("dialog_confirm"),
		InputRouter.action_hint_text("dialog_cancel")], 14, Color(0.68, 0.70, 0.76))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint_label)

## 打开菜单。entries 来自 SettlementSystem.menu_entries()：
## 每项 {id, label, enabled, hint}，顺序即显示顺序。
func open(title: String, status: String, entries: Array[Dictionary]) -> void:
	_title.text = title
	_status.text = status
	_rebuild(entries)
	visible = true
	var first := _first_enabled()
	if first != null:
		first.grab_focus()

func close() -> void:
	visible = false
	_release_focus()

func is_open() -> bool:
	return visible

# ---------------------------------------------------------------- 条目构建
func _rebuild(entries: Array[Dictionary]) -> void:
	_release_focus()
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_buttons.clear()
	_actions.clear()
	_hints.clear()
	for e in entries:
		var act := String(e.get("id", ""))
		var hint := String(e.get("hint", ""))
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)

		var b := Button.new()
		b.text = String(e.get("label", "?"))
		b.add_theme_font_size_override("font_size", 17)
		b.disabled = not bool(e.get("enabled", false))
		# 灰掉的行必须从焦点序列里彻底消失：焦点落在不能按的按钮上是死路一条
		b.focus_mode = Control.FOCUS_ALL if not b.disabled else Control.FOCUS_NONE
		b.pressed.connect(func() -> void: _answer(act))
		row.add_child(b)

		var h := UiTheme.label(hint, 12, Color(0.66, 0.70, 0.76))
		h.name = "Hint"
		row.add_child(h)

		_rows.add_child(row)
		_buttons.append(b)
		_actions.append(act)
		_hints.append(hint)

func _first_enabled() -> Button:
	for b in _buttons:
		if not b.disabled:
			return b
	return null

func _release_focus() -> void:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f is Button and is_ancestor_of(f):
		(f as Button).release_focus()

## 面板自己**不**隐藏：买完还要接着买，关不关由业务层决定（见文件头）。
func _answer(action: String) -> void:
	choice.emit(action)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("dialog_cancel"):
		choice.emit("leave")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dialog_confirm"):
		var f := get_viewport().gui_get_focus_owner()
		if f is Button and is_ancestor_of(f):
			(f as Button).pressed.emit()
		get_viewport().set_input_as_handled()

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