## =============================================================================
##  BattleHUD —— 仿《神之天平》的战斗 HUD（全部由代码绘制，无任何贴图）
##   左上：玩家头像框（程序化绘制的骑士立绘）+ HP 条（带延迟白条）+ 气力/蓄力条
##   下中：Boss 名称 + 长条 HP + 破防(韧性)条
##   中央：开场 Boss 名称大字标题 / 胜利·战败结算文字
##   F3 ：调试信息（状态机状态、弹反窗口、蓄力进度）
## =============================================================================
class_name BattleHUD
extends CanvasLayer

var cv: Control
var font: Font
var vp := Vector2(1600, 900)

# 显示数据（由 BattleScene 每帧写入）
var player_name := "玩家部队"
var player_hp := 1.0
var player_hp_max := 1.0
var player_chip := 1.0
var stamina := 1.0
var stamina_max := 1.0
var charge := 0.0
var charge_full := false
var counter_ready := false

var boss_name := "Boss"
var boss_hp := 1.0
var boss_hp_max := 1.0
var boss_chip := 1.0
var boss_poise := 0.0
var boss_poise_max := 1.0
var boss_broken := false
var boss_phase2 := false

var title_text := ""
var title_t := 0.0
var title_show := 0.0
var result_text := ""
var result_t := 0.0
var result_show := 0.0
var fade_alpha := 0.0

var debug_on := false
var dbg_lines: Array = []
var hit_flash := 0.0
var parry_flash := 0.0
var boss_warn := 0.0
var boss_warn_parryable := true
var hint_lines: Array = []

func setup(boss_title: String) -> void:
	layer = 10
	font = UiTheme.font()
	cv = Control.new()
	cv.set_anchors_preset(Control.PRESET_FULL_RECT)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cv)
	cv.draw.connect(_on_draw)
	boss_name = boss_title
	hint_lines = [
		"A / D 移动   空格 跳跃(长按更高)   Shift 闪避",
		"鼠标左键 攻击(连按三段 / 按住蓄力剑气)   鼠标右键 弹反",
		"F3 调试    Esc / P 结束战斗",
	]
	vp = Vector2(1600, 900)

func _process(_d: float) -> void:
	vp = cv.get_viewport_rect().size
	cv.queue_redraw()

## 受伤时 HP 先掉，白色残血条延迟追上
func tick(delta: float) -> void:
	if player_chip > player_hp:
		if title_t <= 0.0:
			player_chip = maxf(player_hp, player_chip - maxf(player_hp_max, 1.0) * 0.75 * delta)
	elif player_chip < player_hp:
		player_chip = player_hp
	if boss_chip > boss_hp:
		boss_chip = maxf(boss_hp, boss_chip - maxf(boss_hp_max, 1.0) * 0.42 * delta)
	elif boss_chip < boss_hp:
		boss_chip = boss_hp
	if hit_flash > 0.0:
		hit_flash -= delta * 3.0
	if parry_flash > 0.0:
		parry_flash -= delta * 2.4
	if boss_warn > 0.0:
		# 预警文字在出招结束后约 0.4 秒淡出，不要一直挂在屏幕上
		boss_warn = maxf(0.0, boss_warn - delta * 2.4)
	if title_show > 0.0:
		title_show -= delta
	if result_show > 0.0:
		result_show -= delta

# =============================================================== 绘制
func _on_draw() -> void:
	var s := vp
	# 受击红边
	if hit_flash > 0.0:
		cv.draw_rect(Rect2(Vector2.ZERO, s), Color(0.9, 0.1, 0.1, 0.16 * hit_flash))
	# 弹反成功白光
	if parry_flash > 0.0:
		cv.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.30 * parry_flash))
	_draw_player_panel()
	_draw_boss_panel()
	_draw_hints()
	if debug_on:
		_draw_debug()
	_draw_title()
	_draw_result()
	if fade_alpha > 0.001:
		cv.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, fade_alpha))

func _draw_player_panel() -> void:
	var o := Vector2(26, 20)
	var ps := 92.0
	# 头像框
	cv.draw_rect(Rect2(o, Vector2(ps, ps)), Color(0.05, 0.06, 0.09, 0.72))
	cv.draw_rect(Rect2(o, Vector2(ps, ps)), Color(0.85, 0.78, 0.55, 0.9), false, 2.0)
	# 程序化头像：用骑士骨骼画一个缩小立绘
	var prof := RigPoses.player_profile()
	var pose := RigPoses.P({"torso": -0.05, "arm_f": 0.30, "elb_f": 0.55, "arm_b": -0.25, "elb_b": 0.40,
		"leg_f": 0.10, "kne_f": -0.12, "leg_b": -0.10, "kne_b": -0.14, "wpn": -1.35})
	var pal := RigPoses.player_palette(Color(0.72, 0.22, 0.22))
	var old := cv.get_transform()
	cv.draw_set_transform(o + Vector2(ps * 0.5, ps * 0.92), 0.0, Vector2(0.95, 0.95))
	FighterRig.draw_rig(cv, prof, pose, pal, 0.0, 0.0)
	cv.draw_set_transform(old.origin, old.get_rotation(), old.get_scale())
	# 名字
	cv.draw_string(font, o + Vector2(ps + 12, 18), player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
		Color(0.95, 0.92, 0.82))
	# HP 条
	var bx := o.x + ps + 12
	var by := o.y + 28
	var bw := 268.0
	var bh := 22.0
	_bar(Rect2(bx, by, bw, bh), player_hp / maxf(1.0, player_hp_max), player_chip / maxf(1.0, player_hp_max),
		Color(0.85, 0.24, 0.24), Color(0.35, 0.06, 0.08))
	cv.draw_string(font, Vector2(bx + 6, by + 17), "%d / %d" % [int(round(player_hp)), int(round(player_hp_max))],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.94))
	# 气力条
	var sy := by + bh + 6.0
	_bar(Rect2(bx, sy, bw, 11), stamina / maxf(1.0, stamina_max), 0.0, Color(0.35, 0.72, 0.95), Color(0.08, 0.16, 0.24))
	cv.draw_string(font, Vector2(bx + bw + 8, sy + 10), "气力", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.75))
	# 蓄力条（与气力条同位置叠加显示）
	if charge > 0.0:
		var cw := bw
		cv.draw_rect(Rect2(bx, sy, cw * clampf(charge, 0.0, 1.0), 11),
			Color(0.55, 0.88, 1.0, 0.95) if not charge_full else Color(1.0, 0.95, 0.6, 1.0))
		cv.draw_string(font, Vector2(bx + cw + 6, sy + 10),
			"蓄力 %d%%" % int(charge * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(1.0, 0.95, 0.6) if charge_full else Color(0.7, 0.9, 1.0))
	# 反击斩就绪提示
	if counter_ready:
		cv.draw_string(font, Vector2(bx, sy + 34), "★ 反击斩就绪（下一刀伤害 ×2）", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(1.0, 0.85, 0.35))

func _bar(r: Rect2, ratio: float, chip: float, col: Color, bg: Color) -> void:
	cv.draw_rect(r, bg)
	cv.draw_rect(r, Color(0, 0, 0, 0.55), false, 2.0)
	if chip > ratio:
		cv.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(chip, 0.0, 1.0), r.size.y)),
			Color(0.95, 0.95, 0.95, 0.85))
	if ratio > 0.0:
		cv.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(ratio, 0.0, 1.0), r.size.y)), col)
	# 高光
	cv.draw_rect(Rect2(r.position + Vector2(0, 1), Vector2(r.size.x * clampf(ratio, 0.0, 1.0), r.size.y * 0.3)),
		Color(1, 1, 1, 0.18))

func _draw_boss_panel() -> void:
	var bw := minf(980.0, vp.x - 200.0)
	var bx := (vp.x - bw) * 0.5
	var by := vp.y - 96.0
	# 名称
	var nm := boss_name
	if boss_phase2 and title_show <= 0.0:
		nm = boss_name + "  【第二阶段】"
	cv.draw_string(font, Vector2(bx, by - 8), nm, HORIZONTAL_ALIGNMENT_CENTER, bw, 22,
		Color(1.0, 0.72, 0.66) if boss_phase2 else Color(0.95, 0.90, 0.82))
	# HP
	_bar(Rect2(bx, by, bw, 24), boss_hp / maxf(1.0, boss_hp_max), boss_chip / maxf(1.0, boss_hp_max),
		Color(0.78, 0.16, 0.20) if not boss_phase2 else Color(0.95, 0.32, 0.12), Color(0.22, 0.04, 0.05))
	# 破防条
	var py := by + 28.0
	_bar(Rect2(bx, py, bw, 10), boss_poise / maxf(1.0, boss_poise_max), 0.0,
		Color(1.0, 0.85, 0.35) if not boss_broken else Color(0.6, 0.9, 1.0), Color(0.16, 0.14, 0.06))
	cv.draw_string(font, Vector2(bx + 4, py + 9), "破防值", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.7))
	if boss_broken:
		cv.draw_string(font, Vector2(bx + bw * 0.5, py - 6), "破 防 ！  受伤 ×1.5",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color(0.7, 0.95, 1.0))
	# 预警提示（只在出招前摇期间显示，之后淡出）
	if boss_warn > 0.02:
		var fade: float = clampf(boss_warn, 0.0, 1.0)
		var c := Color(1, 1, 1, 0.95) if boss_warn_parryable else Color(1.0, 0.35, 0.3, 0.95)
		c.a *= fade
		var txt := "可弹反（白）" if boss_warn_parryable else "不可弹反（红）· 闪避或跳跃"
		cv.draw_string(font, Vector2(bx, by + 58), txt, HORIZONTAL_ALIGNMENT_CENTER, bw, 18, c)

func _draw_hints() -> void:
	var y := vp.y - 130.0
	for i in hint_lines.size():
		cv.draw_string(font, Vector2(28, y + 20.0 * float(i)), hint_lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(1, 1, 1, 0.55))

func _draw_debug() -> void:
	var y := 210.0
	cv.draw_rect(Rect2(24, y - 20, 430, 26.0 + 20.0 * float(dbg_lines.size())), Color(0, 0, 0, 0.55))
	for i in dbg_lines.size():
		cv.draw_string(font, Vector2(32, y + 20.0 * float(i)), str(dbg_lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(0.6, 1.0, 0.7))

func _draw_title() -> void:
	if title_show <= 0.0:
		return
	var a := clampf(title_show, 0.0, 1.0)
	if title_show > 1.6:
		a = clampf((2.6 - title_show) / 0.6, 0.0, 1.0)
	var y := vp.y * 0.34
	cv.draw_rect(Rect2(0, y - 60, vp.x, 128), Color(0, 0, 0, 0.42 * a))
	cv.draw_string(font, Vector2(0, y + 6), title_text, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 62,
		Color(1.0, 0.86, 0.55, a))
	cv.draw_string(font, Vector2(0, y + 46), "——  BOSS  ——", HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20,
		Color(1, 1, 1, 0.7 * a))

func _draw_result() -> void:
	if result_show <= 0.0:
		return
	var a := clampf(result_show, 0.0, 1.0)
	cv.draw_rect(Rect2(0, vp.y * 0.38, vp.x, 150), Color(0, 0, 0, 0.5 * a))
	cv.draw_string(font, Vector2(0, vp.y * 0.38 + 92), result_text, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 88,
		Color(1.0, 0.88, 0.5, a) if result_text == "胜利" else Color(0.85, 0.35, 0.35, a))

func show_title(txt: String, dur: float = 2.6) -> void:
	title_text = txt
	title_show = dur
	title_t = dur

func show_result(txt: String, dur: float = 3.0) -> void:
	result_text = txt
	result_show = dur
