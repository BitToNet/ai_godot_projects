## =============================================================================
##  DebugStatsPanel —— 右下角性能数字（FPS / 绘制调用 / 三角形）
##  自己按固定间隔采样，避免每帧都去读 Performance 监视器。
## =============================================================================
class_name DebugStatsPanel
extends PanelContainer

const REFRESH_SEC := 0.25

var _label: Label
var _timer: float = 0.0

func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0.05, 0.05, 0.07, 0.62)))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -250
	offset_top = -46
	offset_right = -16
	offset_bottom = -16
	_label = UiTheme.label("", 14, Color(0.90, 0.94, 0.86))
	add_child(_label)

func _process(delta: float) -> void:
	_timer += delta
	if _timer <= REFRESH_SEC:
		return
	_timer = 0.0
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var dc := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var tri := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_label.text = "FPS %d   绘制调用 %d   三角形 %.1f 万" % [int(fps), int(dc), tri / 10000.0]
