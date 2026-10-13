## =============================================================================
##  TopBar —— 左上信息栏
##   第 N 天 / 时辰 / 时间流速 / 暂停徽标 / 当前地形
##  自己 _process 刷新，不依赖 HUD 转发（HUD 因此不需要每帧回调）。
## =============================================================================
class_name TopBar
extends PanelContainer

var day_night: DayNightCycle

var _day_label: Label
var _speed_label: Label
var _pause_badge: Label
var _terrain_label: Label

func _ready() -> void:
	# 纯装饰面板：IGNORE 才能让「点地行军」在它覆盖的区域内也生效
	add_theme_stylebox_override("panel", UiTheme.panel_style())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 16
	offset_top = 16

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	add_child(vb)

	_day_label = UiTheme.label("", 22, Color(0.98, 0.93, 0.78))
	vb.add_child(_day_label)
	_speed_label = UiTheme.label("", 15, Color(0.80, 0.86, 0.92))
	vb.add_child(_speed_label)
	_pause_badge = UiTheme.label("", 18, Color(1.0, 0.72, 0.30))
	vb.add_child(_pause_badge)
	_terrain_label = UiTheme.label("", 14, Color(0.80, 0.88, 0.80))
	vb.add_child(_terrain_label)

func bind(p_day_night: DayNightCycle) -> void:
	day_night = p_day_night

func _process(_delta: float) -> void:
	if day_night == null:
		return
	var speed_txt := "暂停" if day_night.paused else ("×%d" % int(day_night.speed))
	_day_label.text = "第 %d 天   %s" % [day_night.day, day_night.time_string()]
	_speed_label.text = "时间流速：%s" % speed_txt
	if day_night.paused:
		_pause_badge.text = "⏸ 时间已暂停（长按空格流动 / 点击地图行军）"
	elif day_night.is_night():
		_pause_badge.text = "🌙 夜色降临，定居点点亮灯火"
	else:
		_pause_badge.text = ""

func set_terrain_text(t: String) -> void:
	if _terrain_label != null:
		_terrain_label.text = "当前地形：" + t
