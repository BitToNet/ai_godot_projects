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
