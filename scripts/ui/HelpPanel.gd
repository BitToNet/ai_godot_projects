## =============================================================================
##  HelpPanel —— 左下角操作说明
##  纯静态文本；内容与键位改动同步（引入 InputMap 后按动作名描述，不再写死按键）。
## =============================================================================
class_name HelpPanel
extends PanelContainer

const TEXT := """【操作】
左键点击地面：部队寻路移动（行军途中时间自动流动，抵达后立刻暂停）
长按空格：原地推进世界时间（松开即暂停）
行军途中按空格：立刻停止前进并暂停
滚轮：缩放（近处平视 / 远处俯瞰）
中键或右键拖拽：旋转视角
WASD / 屏幕边缘：平移      F：回到部队
R：切换时间流速 ×1/×2/×4
1/2/3：仅显示某势力领地标签
V：显示 / 隐藏植被
M：音效 + 背景音乐静音 / 恢复"""

func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0.05, 0.05, 0.07, 0.62)))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 16
	offset_top = -288
	offset_bottom = -16
	add_child(UiTheme.label(TEXT, 14, Color(0.86, 0.90, 0.94)))
