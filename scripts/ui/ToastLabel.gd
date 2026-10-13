## =============================================================================
##  ToastLabel —— 屏幕上方的临时提示（击败 Boss / 战败回城等）
##  自己管淡出计时；mouse_filter = IGNORE，否则这条 900×40 的横带会吞掉点击。
## =============================================================================
class_name ToastLabel
extends Label

const WIDTH := 900.0
const HEIGHT := 40.0
const TOP_MARGIN := 140.0

var _left: float = 0.0

func _ready() -> void:
	add_theme_font_override("font", UiTheme.font())
	add_theme_font_size_override("font_size", 24)
	add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.95))
	add_theme_constant_override("outline_size", 6)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	position = Vector2(0, TOP_MARGIN)
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size = Vector2(WIDTH, HEIGHT)
	visible = false

func show_text(text: String, dur: float = 5.0) -> void:
	self.text = text
	visible = true
	modulate.a = 1.0
	_left = dur

func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	modulate.a = clampf(_left, 0.0, 1.0)
	if _left <= 0.0:
		visible = false
