## =============================================================================
##  HoverTooltip —— 跟随鼠标的信息提示
##  贴边时会自动翻到鼠标另一侧，避免跑出屏幕。
## =============================================================================
class_name HoverTooltip
extends PanelContainer

var _label: Label

func _ready() -> void:
	add_theme_stylebox_override("panel",
		UiTheme.panel_style(Color(0.04, 0.04, 0.06, 0.90), Color(0.85, 0.78, 0.55, 0.8)))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_label = UiTheme.label("", 15, Color(0.97, 0.95, 0.88))
	add_child(_label)

func show_text(text: String, screen_pos: Vector2) -> void:
	_label.text = text
	visible = true
	var vp := get_viewport().get_visible_rect().size
	var sz := get_combined_minimum_size()
	var p := screen_pos + Vector2(18, 14)
	if p.x + sz.x > vp.x - 8:
		p.x = screen_pos.x - sz.x - 14
	if p.y + sz.y > vp.y - 8:
		p.y = screen_pos.y - sz.y - 10
	position = p

func clear() -> void:
	visible = false
