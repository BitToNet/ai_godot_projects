## =============================================================================
##  EncounterDialog —— 遭遇对话框（攻击 / 撤退）
##  自己发 choice 信号，不直接调用业务逻辑；HUD 再把它转成 encounter_choice 往外抛。
##  mouse_filter = STOP：对话框打开时必须挡住「点地行军」。
##  键盘 / 手柄：打开时把焦点给「攻击」，← → 切换，ui_accept 确认、ui_cancel 撤退。
## =============================================================================
class_name EncounterDialog
extends Control

signal choice(action: String)

var _title: Label
var _info: Label
var attack_button: Button
var retreat_button: Button
var hint_label: Label

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

	var panel := UiTheme.panel(Color(0.06, 0.05, 0.07, 0.95),
		Color(0.88, 0.80, 0.55, 0.9), false)
	cc.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(460, 0)
	panel.add_child(vb)

	_title = UiTheme.label("", 26, Color(0.95, 0.88, 0.66))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)

	_info = UiTheme.label("", 16, Color(0.88, 0.90, 0.95))
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_info)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	vb.add_child(hb)

	attack_button = Button.new()
	attack_button.text = "  攻 击  "
	attack_button.add_theme_font_size_override("font_size", 18)
	attack_button.pressed.connect(func(): _answer("attack"))
	hb.add_child(attack_button)

	retreat_button = Button.new()
	retreat_button.text = "  撤 退  "
	retreat_button.add_theme_font_size_override("font_size", 18)
	retreat_button.pressed.connect(func(): _answer("retreat"))
	hb.add_child(retreat_button)

	# 键位提示直接从 InputMap 读（改键位这里跟着变，不再写死「按 X」）
	hint_label = UiTheme.label("%s 确认      %s 撤退      %s 切换选项" % [
		InputRouter.action_hint_text("dialog_confirm"),
		InputRouter.action_hint_text("dialog_cancel"),
		InputRouter.action_hint_text("dialog_next")], 14, Color(0.68, 0.70, 0.76))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint_label)

func open(title: String, info: String, color: Color) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", color)
	_info.text = info
	visible = true
	# 键盘 / 手柄作答的前提是「有东西拿着焦点」：按钮拿到焦点后，
	# ← → 切换选项、ui_accept 确认、ui_cancel 撤退 才成立。
	# 旧版从不 grab_focus()，于是遭遇框只能点鼠标（G3）。
	attack_button.grab_focus()

func close() -> void:
	visible = false
	attack_button.release_focus()

func is_open() -> bool:
	return visible

## 焦点在按钮上时，键盘确认键由按钮自己消费（内建 ui_accept）；
## 手柄没有内建 ui_accept 绑定，所以确认也在这里再兜一层。
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("dialog_cancel"):
		_answer("retreat")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dialog_confirm"):
		var f := get_viewport().gui_get_focus_owner()
		if f is Button:
			(f as Button).pressed.emit()
		else:
			_answer("attack")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dialog_next"):
		retreat_button.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dialog_prev"):
		attack_button.grab_focus()
		get_viewport().set_input_as_handled()

func _answer(action: String) -> void:
	visible = false
	attack_button.release_focus()
	choice.emit(action)
