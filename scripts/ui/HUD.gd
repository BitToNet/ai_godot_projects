## =============================================================================
##  HUD —— 全部 UI（纯代码构建，无需 .tscn）
##   左上：日期 / 时辰 / 时间流速 / 当前地形与速度倍率
##   右上：小地图（MinimapView）
##   中间：遭遇对话框（攻击 / 撤退）
##   跟随鼠标：悬停信息提示
##   左下：操作说明      右下：FPS / draw call
##   开场：Loading 遮罩（生成地图时显示进度）
## =============================================================================
class_name HUD
extends CanvasLayer

signal encounter_choice(action: String)

var cfg: MapConfig
var data: MapData
var day_night: DayNightCycle
var minimap: MinimapView

var _day_label: Label
var _speed_label: Label
var _terrain_label: Label
var _tooltip: PanelContainer
var _tooltip_label: Label
var _stats_label: Label
var _help_label: Label
var _loading_root: Control
var _loading_label: Label
var _enc_root: Control
var _enc_title: Label
var _enc_info: Label
var _pause_badge: Label
var _fps_timer: float = 0.0
var _toast_label: Label
var _toast_t: float = 0.0

func setup(p_cfg: MapConfig) -> void:
	cfg = p_cfg
	layer = 10
	_build_loading()
	_build_panels()
	_build_encounter()

## 地图生成完成后绑定运行时数据
func bind(p_data: MapData, p_day_night: DayNightCycle) -> void:
	data = p_data
	day_night = p_day_night

func _style(bg: Color = Color(0.05, 0.05, 0.07, 0.78), border: Color = Color(0.72, 0.66, 0.50, 0.55)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(10)
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 6
	return s

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style())
	return p

# ---------------------------------------------------------------- 布局
func _build_panels() -> void:
	# ---- 左上信息 ----
	var left := _panel()
	left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left.offset_left = 16
	left.offset_top = 16
	add_child(left)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	left.add_child(vb)
	_day_label = Label.new()
	_day_label.add_theme_font_size_override("font_size", 22)
	_day_label.add_theme_color_override("font_color", Color(0.98, 0.93, 0.78))
	vb.add_child(_day_label)
	_speed_label = Label.new()
	_speed_label.add_theme_font_size_override("font_size", 15)
	_speed_label.add_theme_color_override("font_color", Color(0.80, 0.86, 0.92))
	vb.add_child(_speed_label)
	_pause_badge = Label.new()
	_pause_badge.add_theme_font_size_override("font_size", 18)
	_pause_badge.add_theme_color_override("font_color", Color(1.0, 0.72, 0.30))
	_pause_badge.text = ""
	vb.add_child(_pause_badge)
	_terrain_label = Label.new()
	_terrain_label.add_theme_font_size_override("font_size", 14)
	_terrain_label.add_theme_color_override("font_color", Color(0.80, 0.88, 0.80))
	vb.add_child(_terrain_label)

	# ---- 右上小地图 ----
	var mm_frame := _panel()
	mm_frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mm_frame.offset_left = -332
	mm_frame.offset_top = 16
	mm_frame.offset_right = -16
	mm_frame.offset_bottom = 348
	mm_frame.add_theme_stylebox_override("panel", _style(Color(0.05, 0.05, 0.07, 0.88)))
	# 边框纯装饰：PanelContainer 默认是 STOP，会把整块右上角区域的左键拦住 → 点地行军失效
	mm_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mm_frame)
	minimap = MinimapView.new()
	minimap.custom_minimum_size = Vector2(300, 300)
	mm_frame.add_child(minimap)

	# ---- 悬停提示 ----
	_tooltip = _panel()
	_tooltip.add_theme_stylebox_override("panel", _style(Color(0.04, 0.04, 0.06, 0.90), Color(0.85, 0.78, 0.55, 0.8)))
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tooltip)
	_tooltip_label = Label.new()
	_tooltip_label.add_theme_font_size_override("font_size", 15)
	_tooltip_label.add_theme_color_override("font_color", Color(0.97, 0.95, 0.88))
	_tooltip.add_child(_tooltip_label)

	# ---- 左下操作说明 ----
	var help := _panel()
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.offset_left = 16
	help.offset_top = -288
	help.offset_bottom = -16
	help.add_theme_stylebox_override("panel", _style(Color(0.05, 0.05, 0.07, 0.62)))
	add_child(help)
	_help_label = Label.new()
	_help_label.add_theme_font_size_override("font_size", 14)
	_help_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.94))
	_help_label.text = "【操作】\n左键点击地面：部队寻路移动（行军途中时间自动流动，抵达后立刻暂停）\n长按空格：原地推进世界时间（松开即暂停）\n行军途中按空格：立刻停止前进并暂停\n滚轮：缩放（近处平视 / 远处俯瞰）\n中键或右键拖拽：旋转视角\nWASD / 屏幕边缘：平移      F：回到部队\nR：切换时间流速 ×1/×2/×4\n1/2/3：仅显示某势力领地标签\nV：显示 / 隐藏植被\nM：音效静音 / 恢复（音效全部由代码合成）"
	help.add_child(_help_label)

	# ---- 右下性能 ----
	var stats := _panel()
	stats.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	stats.offset_left = -250
	stats.offset_top = -46
	stats.offset_right = -16
	stats.offset_bottom = -16
	stats.add_theme_stylebox_override("panel", _style(Color(0.05, 0.05, 0.07, 0.62)))
	add_child(stats)
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 14)
	_stats_label.add_theme_color_override("font_color", Color(0.90, 0.94, 0.86))
	stats.add_child(_stats_label)

func _build_loading() -> void:
	_loading_root = Control.new()
	_loading_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_loading_root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.07, 1.0)
	_loading_root.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_root.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	cc.add_child(vb)
	var title := Label.new()
	title.text = "骑马与砍杀 · 战略大地图"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.66))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "程序化生成中：地形 / 河流 / 植被 / 定居点 / 道路 / 部队"
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(0.72, 0.78, 0.85))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	_loading_label = Label.new()
	_loading_label.text = "准备中…"
	_loading_label.add_theme_font_size_override("font_size", 16)
	_loading_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_loading_label)

func set_loading(text: String) -> void:
	if _loading_label != null:
		_loading_label.text = text

func hide_loading() -> void:
	if _loading_root != null:
		_loading_root.visible = false

# ---------------------------------------------------------------- 遭遇对话
func _build_encounter() -> void:
	_enc_root = Control.new()
	_enc_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_enc_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_enc_root.visible = false
	add_child(_enc_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.35)
	_enc_root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_enc_root.add_child(cc)
	var panel := _panel()
	panel.add_theme_stylebox_override("panel", _style(Color(0.06, 0.05, 0.07, 0.95), Color(0.88, 0.80, 0.55, 0.9)))
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(460, 0)
	panel.add_child(vb)
	_enc_title = Label.new()
	_enc_title.add_theme_font_size_override("font_size", 26)
	_enc_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_enc_title)
	_enc_info = Label.new()
	_enc_info.add_theme_font_size_override("font_size", 16)
	_enc_info.add_theme_color_override("font_color", Color(0.88, 0.90, 0.95))
	_enc_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_enc_info)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	vb.add_child(hb)
	var attack := Button.new()
	attack.text = "  攻 击  "
	attack.add_theme_font_size_override("font_size", 18)
	attack.pressed.connect(func(): _encounter_answer("attack"))
	hb.add_child(attack)
	var retreat := Button.new()
	retreat.text = "  撤 退  "
	retreat.add_theme_font_size_override("font_size", 18)
	retreat.pressed.connect(func(): _encounter_answer("retreat"))
	hb.add_child(retreat)

func show_encounter(title: String, info: String, color: Color) -> void:
	_enc_title.text = title
	_enc_title.add_theme_color_override("font_color", color)
	_enc_info.text = info
	_enc_root.visible = true
	_tooltip.visible = false

func hide_encounter() -> void:
	_enc_root.visible = false

func is_encounter_open() -> bool:
	return _enc_root.visible

func _encounter_answer(action: String) -> void:
	_enc_root.visible = false
	encounter_choice.emit(action)

# ---------------------------------------------------------------- 每帧刷新
func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_label != null:
			_toast_label.modulate.a = clampf(_toast_t, 0.0, 1.0)
			if _toast_t <= 0.0:
				_toast_label.visible = false
	if day_night != null:
		var speed_txt := "暂停" if day_night.paused else ("×%d" % int(day_night.speed))
		_day_label.text = "第 %d 天   %s" % [day_night.day, day_night.time_string()]
		_speed_label.text = "时间流速：%s" % speed_txt
		if day_night.paused:
			_pause_badge.text = "⏸ 时间已暂停（长按空格流动 / 点击地图行军）"
		elif day_night.is_night():
			_pause_badge.text = "🌙 夜色降临，定居点点亮灯火"
		else:
			_pause_badge.text = ""
	_fps_timer += delta
	if _fps_timer > 0.25:
		_fps_timer = 0.0
		var fps := Performance.get_monitor(Performance.TIME_FPS)
		var dc := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var tri := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		_stats_label.text = "FPS %d   绘制调用 %d   三角形 %.1f 万" % [int(fps), int(dc), tri / 10000.0]

## 屏幕上方的临时提示（击败 Boss / 战败回城等）
func show_toast(text: String, dur: float = 5.0) -> void:
	if _toast_label == null:
		_toast_label = Label.new()
		_toast_label.add_theme_font_override("font", UiTheme.font())
		_toast_label.add_theme_font_size_override("font_size", 24)
		_toast_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
		_toast_label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.95))
		_toast_label.add_theme_constant_override("outline_size", 6)
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_toast_label.position = Vector2(0, 140)
		_toast_label.custom_minimum_size = Vector2(900, 40)
		_toast_label.size = Vector2(900, 40)
		add_child(_toast_label)
	_toast_label.text = text
	_toast_label.visible = true
	_toast_t = dur

func set_terrain_text(t: String) -> void:
	if _terrain_label != null:
		_terrain_label.text = "当前地形：" + t

func show_tooltip(text: String, screen_pos: Vector2) -> void:
	if _enc_root.visible:
		return
	_tooltip_label.text = text
	_tooltip.visible = true
	var vp := get_viewport().get_visible_rect().size
	var sz := _tooltip.get_combined_minimum_size()
	var p := screen_pos + Vector2(18, 14)
	if p.x + sz.x > vp.x - 8:
		p.x = screen_pos.x - sz.x - 14
	if p.y + sz.y > vp.y - 8:
		p.y = screen_pos.y - sz.y - 10
	_tooltip.position = p

func clear_tooltip() -> void:
	_tooltip.visible = false
