## =============================================================================
##  LoadingOverlay —— 开场加载遮罩
##  全屏铺满并 mouse_filter = STOP：地图生成期间必须挡住玩家的点击，
##  否则玩家会在世界还没建好时就把行军命令下到空地上。
## =============================================================================
class_name LoadingOverlay
extends Control

var _label: Label
## 标题 / 副标题也留成成员：文案迁进 Strings.gd 之后，「屏幕上还是那句」由 hud_check 直接断言取用
var _title: Label
var _sub: Label

func _ready() -> void:
	# 必须用 set_anchors_**and_offsets**_preset：只设 anchors 的那版会「保留当前矩形」，
	# 而此刻本控件还是 0×0，于是 offsets 被算成 (0, 0, -1600, -900) —— 遮罩永远 0 尺寸，
	# 既看不见黑底、也挡不住点击（hud_shot 截图 + hud_check 断言一起抓到的老 bug）。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 加载时其它面板还没数据（空的小地图外框 / 空性能条）却又在树上，
	# 会把「纯黑遮罩」画成一块花屏。抬高 z_index 让遮罩盖住同级所有面板。
	z_index = 100

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.07, 1.0)
	add_child(bg)

	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cc)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	cc.add_child(vb)

	_title = UiTheme.label(Strings.LOADING_TITLE, 40, Color(0.95, 0.88, 0.66))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)

	_sub = UiTheme.label(Strings.LOADING_SUBTITLE, 17, Color(0.72, 0.78, 0.85))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_sub)

	_label = UiTheme.label(Strings.LOADING_PREPARING, 16, Color(1.0, 0.85, 0.45))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_label)

## 更新「正在进行哪一步」那行文字（Main 的 _step() 每步调一次）
func set_step(text: String) -> void:
	if _label != null:
		_label.text = text

## 生成完成，撤掉遮罩（此后地图可点击）
func finish() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
