## =============================================================================
##  HelpPanel —— 左下角操作说明
##  说明文字在运行时按 project.godot 的 [input] 段拼出来：改了键位、插上手柄，
##  这里显示的按键跟着变，不再写死「按 M 静音」这类字面按键。
## =============================================================================
class_name HelpPanel
extends PanelContainer

## 每行：[动作名, 说明]。动作名为空串 = 纯说明行（不含键位）。
## 「左键点地」与「中键/右键拖拽」是鼠标手势（按坐标处理，不做成动作），故写在说明里。
const LINES: Array = [
	["", "左键点击地面：部队寻路移动（行军途中时间流动，抵达后立刻暂停）"],
	["time_flow", "长按 = 原地推进世界时间；行军途中按下 = 立刻停止前进并暂停"],
	["move_left", "平移视角（也可靠屏幕边缘移动鼠标）"],
	["zoom_in", "缩放：近处平视 / 远处俯瞰"],
	["cam_rotate_left", "旋转视角：左右转向（鼠标中键 / 右键拖拽亦可）"],
	["focus_party", "回到玩家部队"],
	["cycle_speed", "切换时间流速 ×1/×2/×4"],
	["toggle_vegetation", "显示 / 隐藏植被"],
	["toggle_mute", "音效 + 背景音乐静音 / 恢复"],
	["faction_labels_1", "只看某势力领地标签（其余势力见下方两行）"],
	["faction_labels_2", "另看一个势力的领地标签"],
	["faction_labels_3", "再看最后一个势力的领地标签"],
]

func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0.05, 0.05, 0.07, 0.62)))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 16
	offset_top = -352
	offset_bottom = -16
	add_child(UiTheme.label(_build_text(), 14, Color(0.86, 0.90, 0.94)))

func _build_text() -> String:
	var out := PackedStringArray()
	out.append("【操作】")
	for row in LINES:
		var action: String = row[0]
		var desc: String = row[1]
		if action == "":
			out.append(desc)
		else:
			out.append("%s：%s" % [InputRouter.action_keys_text(action), desc])
	return "\n".join(out)
