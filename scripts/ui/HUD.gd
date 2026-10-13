## =============================================================================
##  HUD —— UI 门面（纯代码构建，无需 .tscn）
##
##  本体只负责「建控件 + 转发调用」，每块界面各自成文件：
##    LoadingOverlay   开场遮罩（生成进度）      TopBar            左上：日期 / 时辰 / 流速 / 地形
##    MinimapView      右上：小地图              HoverTooltip      跟随鼠标的悬停提示
##    HelpPanel        左下：操作说明            DebugStatsPanel   右下：FPS / draw call
##    ToastLabel       上方：临时提示            EncounterDialog   中央：遭遇对话框
##
##  Main 只跟本文件的公开方法打交道（接口与拆分前完全一致，改动对外无感）。
##  每块控件自己 _process，HUD 不再需要每帧回调。
## =============================================================================
class_name HUD
extends CanvasLayer

signal encounter_choice(action: String)

var cfg: MapConfig
var data: MapData
var day_night: DayNightCycle
var minimap: MinimapView
var topbar: TopBar
var dialog: EncounterDialog

var _loading: LoadingOverlay
var _tooltip: HoverTooltip
var _toast: ToastLabel

func setup(p_cfg: MapConfig) -> void:
	cfg = p_cfg
	layer = 10

	_loading = LoadingOverlay.new()
	_loading.name = "LoadingOverlay"
	add_child(_loading)

	topbar = TopBar.new()
	topbar.name = "TopBar"
	add_child(topbar)

	_build_minimap()

	_tooltip = HoverTooltip.new()
	_tooltip.name = "HoverTooltip"
	add_child(_tooltip)

	var help := HelpPanel.new()
	help.name = "HelpPanel"
	add_child(help)

	var stats := DebugStatsPanel.new()
	stats.name = "DebugStatsPanel"
	add_child(stats)

	dialog = EncounterDialog.new()
	dialog.name = "EncounterDialog"
	add_child(dialog)
	dialog.choice.connect(_on_dialog_choice)

	# 提示条最后加入 → 始终盖在遭遇对话框之上（与拆分前的实际层级一致）
	_toast = ToastLabel.new()
	_toast.name = "ToastLabel"
	add_child(_toast)

func _build_minimap() -> void:
	# 外框纯装饰：默认的 STOP 会拦住整块右上角的左键 → 点地行军失效，必须 IGNORE
	var frame := UiTheme.panel(Color(0.05, 0.05, 0.07, 0.88))
	frame.name = "MinimapFrame"
	frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	frame.offset_left = -332
	frame.offset_top = 16
	frame.offset_right = -16
	frame.offset_bottom = 348
	add_child(frame)

	minimap = MinimapView.new()
	minimap.name = "Minimap"
	minimap.custom_minimum_size = Vector2(300, 300)
	frame.add_child(minimap)

## 地图生成完成后绑定运行时数据
func bind(p_data: MapData, p_day_night: DayNightCycle) -> void:
	data = p_data
	day_night = p_day_night
	topbar.bind(p_day_night)

# ---------------------------------------------------------------- 对外接口
func set_loading(text: String) -> void:
	_loading.set_step(text)

func hide_loading() -> void:
	_loading.finish()

func set_terrain_text(t: String) -> void:
	topbar.set_terrain_text(t)

func show_toast(text: String, dur: float = 5.0) -> void:
	_toast.show_text(text, dur)

func show_tooltip(text: String, screen_pos: Vector2) -> void:
	if dialog.is_open():
		return
	_tooltip.show_text(text, screen_pos)

func clear_tooltip() -> void:
	_tooltip.clear()

func show_encounter(title: String, info: String, color: Color) -> void:
	dialog.open(title, info, color)
	_tooltip.clear()

func hide_encounter() -> void:
	dialog.close()

func is_encounter_open() -> bool:
	return dialog.is_open()

func _on_dialog_choice(action: String) -> void:
	encounter_choice.emit(action)
