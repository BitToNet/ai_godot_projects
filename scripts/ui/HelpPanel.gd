## =============================================================================
##  HelpPanel —— 左下角操作说明
##  说明文字在运行时按 project.godot 的 [input] 段拼出来：改了键位、插上手柄，
##  这里显示的按键跟着变，不再写死「按 M 静音」这类字面按键。
##  文案本身在 scripts/core/Strings.gd（i18n 表），本文件只负责「哪一行配哪个动作」。
## =============================================================================
class_name HelpPanel
extends PanelContainer

## 每行：[动作名, 说明]。动作名为空串 = 纯说明行（不含键位）。
## 「左键点地」与「中键/右键拖拽」是鼠标手势（按坐标处理，不做成动作），故写在说明里。
const LINES: Array = [
	["", Strings.HELP_CLICK_MOVE],
	["interact", Strings.HELP_INTERACT],
	["time_flow", Strings.HELP_TIME_FLOW],
	["move_left", Strings.HELP_PAN],
	["zoom_in", Strings.HELP_ZOOM],
	["cam_rotate_left", Strings.HELP_ROTATE],
	["focus_party", Strings.HELP_FOCUS],
	["cycle_speed", Strings.HELP_SPEED],
	["toggle_vegetation", Strings.HELP_VEGETATION],
	["toggle_mute", Strings.HELP_MUTE],
	["faction_labels_1", Strings.HELP_FACTION_1],
	["faction_labels_2", Strings.HELP_FACTION_2],
	["faction_labels_3", Strings.HELP_FACTION_3],
	["quicksave", Strings.HELP_SAVE],
	["quickload", Strings.HELP_LOAD],
]

func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0.05, 0.05, 0.07, 0.62)))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 16
	offset_top = -390
	offset_bottom = -16
	add_child(UiTheme.label(_build_text(), 14, Color(0.86, 0.90, 0.94)))

func _build_text() -> String:
	var out := PackedStringArray()
	out.append(Strings.HELP_TITLE)
	for row in LINES:
		var action: String = row[0]
		var desc: String = row[1]
		if action == "":
			out.append(desc)
		else:
			out.append("%s：%s" % [InputRouter.action_keys_text(action), desc])
	return "\n".join(out)
