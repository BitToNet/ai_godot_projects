## =============================================================================
##  BattleConfig —— Boss 战斗场景的全部可调数值（集中在一个 Resource 里）
##   · 玩家：HP / 气力 / 移动 / 跳跃 / 闪避 / 弹反 / 蓄力 / 三段连击
##   · Boss：HP / 破防 / 各招式（前摇·判定·后摇·伤害·预警色·距离区间·权重）
##   · 手感：输入缓冲、顿帧、震屏、慢动作
##  用 BattleConfig.create() 生成一份带默认招式的实例；也可以存成 .tres 后在
##  Inspector 里调，所有字段都是 @export。
## =============================================================================
class_name BattleConfig
extends Resource

@export_group("房间 / 相机")
@export var arena_width: float = 1500.0          ## 竞技场宽度（约 2.25 个屏幕）
@export var ground_y: float = 0.0                ## 地面高度（角色脚底 y）
@export var cam_zoom_near: float = 2.6           ## 双方靠近时的缩放（越大越近）
@export var cam_zoom_far: float = 1.95           ## 双方拉远时的缩放
@export var cam_smooth: float = 0.12
@export var cam_dist_full: float = 420.0         ## 距离达到该值时用 cam_zoom_far

@export_group("玩家 · 基础")
@export var player_max_hp: float = 260.0
@export var player_max_stamina: float = 100.0
@export var stamina_regen: float = 24.0
@export var stamina_regen_delay: float = 0.65
@export var move_speed: float = 168.0
@export var gravity: float = 1500.0
@export var max_fall_speed: float = 900.0
@export var body_size: Vector2 = Vector2(20, 58)

@export_group("玩家 · 跳跃")
@export var jump_velocity: float = -470.0
@export var jump_cut: float = 0.42               ## 松开跳跃键后的上升速度衰减（可变跳跃高度）
@export var air_control: float = 0.62
@export var coyote_time: float = 0.10            ## 土狼时间
@export var jump_buffer: float = 0.12            ## 落地缓冲

@export_group("玩家 · 取消规则（可配置表）")
@export var jump_cancels_attacks: bool = false   ## 跳跃不能取消普攻后摇（规范要求 false）
@export var combo_window_ratio: float = 0.70      ## 后摇的前 70% 才是「连段窗口」

@export_group("玩家 · 输入缓冲")
@export var input_buffer: float = 0.15           ## 输入缓冲窗口
@export var charge_start: float = 0.50           ## 按住多久进入蓄力
@export var charge_full: float = 1.20            ## 蓄满时间
@export var charge_move_scale: float = 0.45      ## 蓄力期间移动速度倍率
@export var charge_stamina_per_sec: float = 14.0

@export_group("玩家 · 闪避")
@export var dodge_distance: float = 122.0        ## 总位移
@export var dodge_time: float = 0.30             ## 总时长
@export var dodge_iframe: float = 0.25           ## 无敌帧时长
@export var dodge_cooldown: float = 0.60
@export var dodge_air_limit: int = 1             ## 空中每次落地前的闪避次数
@export var dodge_stamina: float = 16.0
@export var perfect_dodge_window: float = 0.22   ## 判定帧内闪避 → 慢动作
@export var perfect_dodge_slow: float = 0.35     ## 慢动作倍率
@export var perfect_dodge_time: float = 0.60

@export_group("玩家 · 弹反")
@export var parry_window: float = 0.15           ## 弹反窗口
@export var parry_recovery: float = 0.40         ## 弹反失败后摇（惩罚乱按）
@export var parry_success_recovery: float = 0.22
@export var parry_poise_damage: float = 34.0     ## 弹反对 Boss 破防值
@export var parry_stagger: float = 0.85          ## Boss 被弹开的硬直
@export var parry_counter_window: float = 1.30   ## 弹反成功后「反击斩」有效时间
@export var parry_counter_mult: float = 2.0      ## 反击斩伤害倍率
@export var parry_hitstop: float = 0.08
@export var parry_stamina: float = 10.0

@export_group("玩家 · 受击")
@export var hurt_time: float = 0.28
@export var hurt_invuln: float = 0.80            ## 受击后无敌时间（闪烁）

@export_group("Boss · 基础")
@export var boss_max_hp: float = 900.0
@export var boss_max_poise: float = 120.0
@export var boss_body_size: Vector2 = Vector2(70, 180)
@export var boss_move_speed: float = 92.0
@export var boss_break_time: float = 3.0         ## 破防眩晕时长
@export var boss_break_damage_mult: float = 1.5  ## 破防期间受伤倍率
@export var boss_break_reset_delay: float = 3.0  ## 破防结束后破防值清零耗时
@export var boss_phase2_hp: float = 0.5          ## 进入二阶段的血量比例
@export var boss_phase2_speed: float = 1.20      ## 二阶段攻速倍率
@export var boss_idle_gap: float = 0.55          ## 每次出招后的间隔（给玩家输出窗口）
@export var boss_idle_gap_phase2: float = 0.34
@export var boss_poise_decay: float = 7.0        ## 破防值自然衰减（每秒，1.5s 未受击后开始）
@export var boss_poise_decay_delay: float = 1.5
@export var boss_knock_scale: float = 0.22       ## 霸体：Boss 受到的击退衰减
@export var boss_roar_time: float = 1.70         ## 二阶段转场时长

@export_group("手感")
@export var hitstop_light: float = 0.05
@export var hitstop_heavy: float = 0.10
@export var shake_light: Vector2 = Vector2(3.0, 0.14)
@export var shake_medium: Vector2 = Vector2(7.0, 0.24)
@export var shake_heavy: Vector2 = Vector2(13.0, 0.42)

@export_group("招式表")
@export var player_attacks: Array[BattleMove] = []
@export var boss_moves: Array[BattleMove] = []

## ---------- 工厂：生成一份带全部默认招式的配置 ----------
static func create() -> BattleConfig:
	var c := BattleConfig.new()
	c.player_attacks = _default_player_attacks()
	c.boss_moves = _default_boss_moves()
	return c

static func _mv(d: Dictionary) -> BattleMove:
	var m := BattleMove.new()
	for k in d.keys():
		m.set(k, d[k])
	return m

## 三段普攻 + 空中斩 + 蓄力剑气（剑气本体是投射物，这里的招式只是挥剑动作）
static func _default_player_attacks() -> Array[BattleMove]:
	var a: Array[BattleMove] = []
	# ---- 第 1 段：横斩 ----
	a.append(_mv({
		"id": "attack1", "display": "横斩", "anim": "atk1",
		"startup": 0.10, "active": 0.07, "recovery": 0.20,
		"damage": 22.0, "poise_damage": 7.0, "knockback": 90.0, "hitstop": 0.05,
		"stamina": 8.0, "move_dist": 26.0,
		"box_offset": Vector2(32, -34), "box_size": Vector2(56, 40),
		"cancel_into": PackedStringArray(["DODGE", "ATTACK2", "PARRY"]),
	}))
	# ---- 第 2 段：回斩 ----
	a.append(_mv({
		"id": "attack2", "display": "回斩", "anim": "atk2",
		"startup": 0.09, "active": 0.07, "recovery": 0.22,
		"damage": 26.0, "poise_damage": 9.0, "knockback": 110.0, "hitstop": 0.05,
		"stamina": 9.0, "move_dist": 30.0,
		"box_offset": Vector2(34, -36), "box_size": Vector2(60, 44),
		"cancel_into": PackedStringArray(["DODGE", "ATTACK3", "PARRY"]),
	}))
	# ---- 第 3 段：前冲突刺（伤害最高 + 小位移 + 击退，后摇最长） ----
	a.append(_mv({
		"id": "attack3", "display": "破军突刺", "anim": "atk3",
		"startup": 0.16, "active": 0.10, "recovery": 0.38,
		"damage": 44.0, "poise_damage": 16.0, "knockback": 260.0, "lift": -120.0,
		"hitstop": 0.10, "stamina": 14.0, "move_dist": 78.0, "crit_mult": 1.3,
		"box_offset": Vector2(40, -34), "box_size": Vector2(74, 38),
		# 第三段后摇不能接第四段，只能闪避/弹反取消
		"cancel_into": PackedStringArray(["DODGE", "PARRY"]),
	}))
	# ---- 空中斩 ----
	a.append(_mv({
		"id": "air_attack", "display": "空中斩", "anim": "air",
		"startup": 0.09, "active": 0.14, "recovery": 0.20,
		"damage": 30.0, "poise_damage": 10.0, "knockback": 150.0, "lift": -60.0,
		"hitstop": 0.06, "stamina": 10.0, "move_dist": 20.0,
		"box_offset": Vector2(30, -26), "box_size": Vector2(60, 48),
		"cancel_into": PackedStringArray(["DODGE"]),
	}))
	return a

## Boss 六招（两招不可弹反 = 红光，四招可弹反 = 白光）
static func _default_boss_moves() -> Array[BattleMove]:
	var m: Array[BattleMove] = []
	# 1) 重劈（可弹反，白光预警）
	m.append(_mv({
		"id": "cleave", "display": "断岳重劈", "anim": "cleave",
		"startup": 0.62, "active": 0.13, "recovery": 0.62,
		"damage": 38.0, "poise_damage": 0.0, "knockback": 300.0, "lift": -150.0,
		"hitstop": 0.08, "parryable": true, "telegraph": 0.45,
		"weight": 1.5, "min_range": 0.0, "max_range": 190.0,
		"box_offset": Vector2(64, -70), "box_size": Vector2(108, 120),
	}))
	# 2) 横扫连击（2~3 段，每段都能弹反）
	m.append(_mv({
		"id": "sweep", "display": "裂地三连横扫", "anim": "sweep",
		"startup": 0.42, "active": 0.10, "recovery": 0.55, "hits": 3, "hit_interval": 0.34,
		"damage": 24.0, "knockback": 170.0, "hitstop": 0.05,
		"parryable": true, "telegraph": 0.34,
		"weight": 1.4, "min_range": 0.0, "max_range": 210.0,
		"box_offset": Vector2(58, -60), "box_size": Vector2(120, 96),
	}))
	# 3) 跳跃砸地（不可弹反，落地两侧冲击波）
	m.append(_mv({
		"id": "slam", "display": "崩山践踏", "anim": "slam",
		"startup": 0.55, "active": 0.16, "recovery": 0.72,
		"damage": 30.0, "knockback": 220.0, "lift": -260.0, "hitstop": 0.10,
		"parryable": false, "telegraph": 0.42,
		"weight": 1.0, "min_range": 0.0, "max_range": 320.0,
		"projectile": "shockwave",
		"box_offset": Vector2(0, -40), "box_size": Vector2(240, 90),
	}))
	# 4) 冲锋突进（不可弹反，要闪避穿过）
	m.append(_mv({
		"id": "charge", "display": "血怒冲锋", "anim": "charge",
		"startup": 0.48, "active": 0.60, "recovery": 0.50,
		"damage": 34.0, "knockback": 320.0, "lift": -140.0, "hitstop": 0.07,
		"hit_interval": 0.40, "hits": 1,
		"parryable": false, "telegraph": 0.40,
		"weight": 1.0, "min_range": 150.0, "max_range": 700.0,
		"move_dist": 0.0,
		"box_offset": Vector2(50, -60), "box_size": Vector2(110, 110),
	}))
	# 5) 飞斧（可弹反，弹反后反弹回去打 Boss）
	m.append(_mv({
		"id": "axe", "display": "裂空飞斧", "anim": "throw",
		"startup": 0.50, "active": 0.10, "recovery": 0.55,
		"damage": 22.0, "knockback": 130.0, "hitstop": 0.05,
		"parryable": true, "telegraph": 0.36,
		"weight": 1.2, "min_range": 170.0, "max_range": 999.0,
		"projectile": "axe",
		"box_offset": Vector2(40, -70), "box_size": Vector2(10, 10),
	}))
	# 6) 二阶段专属组合技：地面裂隙 + 追击重劈
	m.append(_mv({
		"id": "fissure_combo", "display": "崩界裂隙", "anim": "fissure",
		"startup": 0.58, "active": 0.22, "recovery": 0.68, "hits": 3, "hit_interval": 0.22,
		"damage": 27.0, "knockback": 200.0, "lift": -180.0, "hitstop": 0.06,
		"parryable": false, "telegraph": 0.44, "phase2_only": true,
		"weight": 1.6, "min_range": 0.0, "max_range": 640.0,
		"projectile": "fissure",
		"box_offset": Vector2(0, -50), "box_size": Vector2(200, 110),
	}))
	return m

## 不同敌人类型的招式表（领主最全，商队护卫长最少）
const KIND_MOVES := {
	"lord": ["cleave", "sweep", "slam", "charge", "axe", "fissure_combo"],
	"bandit": ["cleave", "sweep", "charge", "axe"],
	"caravan": ["cleave", "sweep", "axe"],
}

## 不同敌人类型的伤害系数（越小越弱）
const KIND_DMG_MULT := {"lord": 1.0, "bandit": 0.92, "caravan": 0.82}

func boss_moves_for(kind: String) -> Array[BattleMove]:
	var ids: Array = KIND_MOVES.get(kind, KIND_MOVES["bandit"])
	var out: Array[BattleMove] = []
	for id in ids:
		var m := boss_move(str(id))
		if m != null:
			out.append(m)
	if out.is_empty():
		out = boss_moves.duplicate()
	return out

func boss_dmg_mult_for(kind: String) -> float:
	return float(KIND_DMG_MULT.get(kind, 1.0))

func player_move(id: String) -> BattleMove:
	for m in player_attacks:
		if m.id == id:
			return m
	return null

func boss_move(id: String) -> BattleMove:
	for m in boss_moves:
		if m.id == id:
			return m
	return null
