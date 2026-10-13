## =============================================================================
##  EncounterDialog —— 遭遇对话框（攻击 / 撤退）
##  自己发 choice 信号，不直接调用业务逻辑；HUD 再把它转成 encounter_choice 往外抛。
##  mouse_filter = STOP：对话框打开时必须挡住「点地行军」。
## =============================================================================
class_name EncounterDialog
extends Control

signal choice(action: String)

var _title: Label
var _info: Label
var attack_button: Button
var retreat_button: Button

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

func open(title: String, info: String, color: Color) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", color)
	_info.text = info
	visible = true

func close() -> void:
	visible = false

func is_open() -> bool:
	return visible

func _answer(action: String) -> void:
	visible = false
	choice.emit(action)
