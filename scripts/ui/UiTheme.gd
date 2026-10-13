## =============================================================================
##  UiTheme —— 统一 UI 字体 / 主题
##  用 SystemFont 按名字加载系统中文字体（macOS: PingFang SC / Windows: 微软雅黑 /
##  Linux: Noto Sans CJK），这样 UI 与 Label3D 的中文才能正常显示。
## =============================================================================
class_name UiTheme
extends RefCounted

static var _font: Font = null
static var _theme: Theme = null

static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray([
			"PingFang SC", "Hiragino Sans GB", "Heiti SC", "Songti SC",
			"Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "Source Han Sans CN",
			"WenQuanYi Micro Hei", "Noto Sans SC", "sans-serif",
		])
		f.allow_system_fallback = true
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font = f
	return _font

static func theme() -> Theme:
	if _theme == null:
		var t := Theme.new()
		t.default_font = font()
		t.default_font_size = 16
		_theme = t
	return _theme

## 半透明底 + 描边的面板样式。UI 里所有面板都用它，避免每处各写一遍 StyleBoxFlat。
static func panel_style(bg: Color = Color(0.05, 0.05, 0.07, 0.78),
		border: Color = Color(0.72, 0.66, 0.50, 0.55)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(10)
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 6
	return s

## 建一个已套好面板样式的 PanelContainer。
## decorative = true 时顺手把 mouse_filter 设成 IGNORE：面板本身是纯装饰，
## 默认的 STOP 会吞掉其覆盖区域的左键（小地图外框就曾因此让「点地行军」失效）。
static func panel(bg: Color = Color(0.05, 0.05, 0.07, 0.78),
		border: Color = Color(0.72, 0.66, 0.50, 0.55), decorative: bool = true) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, border))
	if decorative:
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## 统一字号 + 颜色的 Label 构造（少写重复的 add_theme_*_override）
static func label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
