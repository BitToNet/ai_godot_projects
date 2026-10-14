## =============================================================================
##  TopBar —— 左上信息栏
##   第 N 天 / 时辰 / 时间流速 / 暂停徽标 / 当前地形
##   第四轮新增：钱袋 / 补给 / 士气 / 声望 / 兵员档次（战役经济状态）
##  自己 _process 刷新，不依赖 HUD 转发（HUD 因此不需要每帧回调）。
## =============================================================================
class_name TopBar
extends PanelContainer

var day_night: DayNightCycle
var campaign: CampaignState

var _day_label: Label
var _speed_label: Label
var _pause_badge: Label
var _terrain_label: Label
var _purse_label: Label
## 钱袋行的节流 + 去重：这一行的值一天才动一次（换日结算 / 战斗结算），
## 没必要时每帧重建字符串、更没必要每帧 add_theme_color_override ——
## 主题覆盖会脏掉 Label 的样式缓存、把它标成需要重绘，属于「每帧白干活」。
var _purse_text: String = ""
var _purse_col: Color = Color(0, 0, 0, 0)
var _purse_timer: float = 0.0

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

	# 经济状态行（第四轮）。放在最下面：上面的日期 / 流速 / 地形是老位置，
	# 加在尾部不会让已有的截图断言和视觉习惯错位。
	_purse_label = UiTheme.label("", 14, Color(0.96, 0.88, 0.62))
	vb.add_child(_purse_label)

func bind(p_day_night: DayNightCycle) -> void:
	day_night = p_day_night

## 绑定战役经济状态（第四轮）。与 bind() 分开：hud_check 那条「不建世界」的
## 自检路径没有 CampaignState，得让 _purse_label 优雅地空着。
## 除了定时轮询，还接上 changed 信号：换日结算 / 战斗缴获 / 招募花钱都会立刻反映，
## 不用等下一次轮询（轮询只兜底那些不 emit 的字段变更）。
func bind_campaign(p_campaign: CampaignState) -> void:
	if campaign != null and campaign.changed.is_connected(_refresh_purse):
		campaign.changed.disconnect(_refresh_purse)
	campaign = p_campaign
	if campaign != null:
		campaign.changed.connect(_refresh_purse)
	_refresh_purse()

## 钱袋行。断粮 / 低士气 / 欠薪要一眼看出来，所以用颜色区分而不是加长文案。
## 只在文字或颜色真的变了才写回控件（见上面 _purse_* 的说明）。
func _refresh_purse() -> void:
	if _purse_label == null:
		return
	if campaign == null:
		if _purse_text != "":
			_purse_text = ""
			_purse_label.text = ""
		return
	var c := campaign
	var txt := Strings.PURSE_LINE % [
		c.denars, c.supplies, c.morale, c.renown,
		c.rules.tier_name(c.tier), c.troops(), c.capacity()]
	if c.debt_weeks > 0:
		txt += Strings.ARREARS % c.debt_weeks
	var col := Color(0.96, 0.88, 0.62)
	if c.debt_weeks > 0 or c.morale < 20:
		col = Color(1.0, 0.52, 0.42)        # 欠薪 / 濒临溃散
	elif c.supplies <= 0 or c.morale < 40:
		col = Color(1.0, 0.76, 0.38)        # 断粮 / 士气偏低
	if txt != _purse_text:
		_purse_text = txt
		_purse_label.text = txt
	if col != _purse_col:
		_purse_col = col
		_purse_label.add_theme_color_override("font_color", col)

func _process(delta: float) -> void:
	if day_night == null:
		return
	# 钱袋行 4 Hz 刷新就够了（值最多一天变一次），不必每帧
	_purse_timer += delta
	if _purse_timer >= 0.25:
		_purse_timer = 0.0
		_refresh_purse()
	var speed_txt := Strings.SPEED_PAUSED if day_night.paused else (Strings.SPEED_MULT % int(day_night.speed))
	_day_label.text = Strings.DAY_LABEL % [day_night.day, day_night.time_string()]
	_speed_label.text = Strings.SPEED_HINT % speed_txt
	if day_night.paused:
		# 键名从 [input] 段读（手柄上就是「长按 手柄X」），不写死空格
		_pause_badge.text = Strings.PAUSE_BADGE % InputRouter.action_hint_text("time_flow")
	elif day_night.is_night():
		_pause_badge.text = Strings.NIGHT_BADGE
	else:
		_pause_badge.text = ""

func set_terrain_text(t: String) -> void:
	if _terrain_label != null:
		_terrain_label.text = Strings.TERRAIN + t
