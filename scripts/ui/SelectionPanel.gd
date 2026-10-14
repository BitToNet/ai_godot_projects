## =============================================================================
##  SelectionPanel —— 左侧「选中目标」面板（点地图上的定居点 / 部队后出现）
##
##  与 EncounterDialog / SettlementDialog 的分工：那两个是**模态**的（开面板就锁世界
##  时间），本面板是**非模态**的 —— 只是把「你选中了谁」摆出来，地图照常能点：
##    · 点空地 → Main 清空选中（面板收起）并照常下发行军命令；
##    · 点别的目标 → 直接改选中（不需要先关面板）。
##  所以它**不**参与 HUD.is_any_dialog_open()（键盘路由不该因为「看了一眼详情」而让路）。
##
##  与另外两个面板一样：条目（做什么 / 能不能做 / 为什么）全由 SelectionSystem.entries()
##  给，这里只照着画，点一行只发 action_pressed(id)，**自己不做任何业务判断**。
##
##  输入：
##    · 面板挡住的区域不把左键透给地图（PanelContainer 默认 STOP）——
##      否则「点『进入』按钮」会连带把部队也指过去。
##    · Esc = 关闭选中，但它**只在自己是当前唯一在场者时**生效：遭遇框 / 进城菜单
##      打开时它们的 _unhandled_input 会先消费掉 dialog_cancel（它们在本面板之后
##      加入 HUD，收到输入更早），这里再兜一层判断免得两处同时响应。
## =============================================================================
class_name SelectionPanel
extends PanelContainer

signal action_pressed(action: String)

var _title: Label
var _body: Label
var _rows: VBoxContainer
var _hint: Label

var _buttons: Array[Button] = []
var _actions: Array[String] = []

func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0.05, 0.05, 0.07, 0.86)))
	# 默认 STOP 会吞掉覆盖区域的左键（小地图外框就曾因此让「点地行军」失效）——
	# 这里**要的就是**吞掉：面板上的点击不该同时变成地图命令。见文件头。
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 16
	offset_top = 168
	custom_minimum_size = Vector2(320, 0)
	visible = false

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)

	_title = UiTheme.label("", 19, Color(0.96, 0.90, 0.70))
	vb.add_child(_title)

	_body = UiTheme.label("", 13, Color(0.78, 0.84, 0.90))
	vb.add_child(_body)

	vb.add_child(HSeparator.new())

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	vb.add_child(_rows)

	# 键位提示从 InputMap 读，不写死「按 Esc」（改了 [input] 段这里跟着变）
	_hint = UiTheme.label(Strings.SELECT_HINT_LINE % [
		InputRouter.action_hint_text("dialog_confirm"),
		InputRouter.action_hint_text("dialog_cancel")], 12, Color(0.62, 0.66, 0.72))
	vb.add_child(_hint)

## 显示选中目标。title / body / entries 都是 SelectionSystem 组好的原样数据。
func open(title: String, body: String, entries: Array[Dictionary]) -> void:
	_title.text = title
	_body.text = body
	_rebuild(entries)
	visible = true

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
	for e in entries:
		var act := String(e.get("id", ""))
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)

		var b := Button.new()
		b.text = String(e.get("label", "?"))
		b.add_theme_font_size_override("font_size", 15)
		b.disabled = not bool(e.get("enabled", false))
		# 灰掉的行必须从焦点序列里彻底消失：焦点落在不能按的按钮上是死路一条
		b.focus_mode = Control.FOCUS_ALL if not b.disabled else Control.FOCUS_NONE
		b.pressed.connect(func() -> void: _answer(act))
		row.add_child(b)

		# 没有提示就别造那个 Label：造了不入树 = 每次重建漏一个孤儿节点
		# （Godot 只在退出时以 "ObjectDB instances leaked" 报出来，平时完全无声）
		var htext := String(e.get("hint", ""))
		if htext != "":
			row.add_child(UiTheme.label(htext, 11, Color(0.64, 0.68, 0.74)))

		_rows.add_child(row)
		_buttons.append(b)
		_actions.append(act)

func _first_enabled() -> Button:
	for b in _buttons:
		if not b.disabled:
			return b
	return null

func _release_focus() -> void:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f is Button and is_ancestor_of(f):
		(f as Button).release_focus()

## 面板自己**不**隐藏：关不关由业务层（Main 清空选中 → SelectionSystem.changed → HUD）决定，
## 这样「点另一座城」不会先闪一下再重开。
func _answer(action: String) -> void:
	action_pressed.emit(action)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not event.is_action_pressed("dialog_cancel"):
		return
	# 有模态面板在场时 Esc 归它（让路规则见文件头）
	var p := get_parent()
	if p is HUD and (p as HUD).is_any_dialog_open():
		return
	action_pressed.emit(Strings.SELECT_CLOSE)
	get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- 给自检用
func row_actions() -> Array[String]:
	return _actions

func row_enabled() -> Array[bool]:
	var out: Array[bool] = []
	for b in _buttons:
		out.append(not b.disabled)
	return out

func row_button(i: int) -> Button:
	if i < 0 or i >= _buttons.size():
		return null
	return _buttons[i]

func body_text() -> String:
	return _body.text if _body != null else ""

func title_text() -> String:
	return _title.text if _title != null else ""
