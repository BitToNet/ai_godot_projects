## =============================================================================
##  EncounterRules —— 遭遇与 Boss 战的全部数值（一张表，改平衡只动这里）
##
##  搬出前这些数字散在 Main._start_battle / _on_encounter_choice /
##  _on_battle_finished 三处（Boss HP / 破防公式、冷却秒数、战利品与损失率、
##  文案），改一个值要在三个函数之间来回找。
##
##  用 Resource 的另一个好处：将来要做「难度档位」或让 MOD 覆盖，
##  直接换一个 .tres 就行（现在用 create() 拿默认值）。
## =============================================================================
class_name EncounterRules
extends Resource

## 触发距离在 MapConfig.encounter_distance 之外再贴近这么多米
@export var trigger_margin := 3.0
## 撤退后的冷却：这段时间内同一支部队不会再触发遭遇
@export var retreat_cooldown := 14.0
## 战败后的冷却（被送回城镇，别一落地又撞上）
@export var defeat_cooldown := 30.0
## 战斗里主动撤出的冷却
@export var battle_retreat_cooldown := 25.0
## 撤退 / 战败时被推开的距离（米）
@export var push_away_distance := 34.0
## 推开落点的边界留白
@export var push_away_margin := 4.0

## Boss 基础三围：默认（领主）最强，bandit / caravan 各自更低
@export var boss_hp_base := 300.0
@export var boss_hp_per_troop := 1.10
@export var boss_poise_base := 90.0
@export var boss_poise_per_troop := 0.22

static func create() -> EncounterRules:
	return EncounterRules.new()

## 按敌人类型给不同的 HP（商队护卫长最弱，领主最强）
func boss_hp(kind: String, troops: int) -> float:
	var t := float(troops)
	match kind:
		"bandit":
			return 130.0 + t * 2.10
		"caravan":
			return 110.0 + t * 1.70
		_:
			return boss_hp_base + t * boss_hp_per_troop

## 按敌人类型给不同的破防值
func boss_poise(kind: String, troops: int) -> float:
	var t := float(troops)
	match kind:
		"bandit":
			return 55.0 + t * 0.42
		"caravan":
			return 48.0 + t * 0.38
		_:
			return boss_poise_base + t * boss_poise_per_troop

## 战利品倍率（乘敌方兵力 = 缴获数量）
func loot_rate(kind: String) -> float:
	match kind:
		"caravan":
			return 1.15      # 商队货物值钱，但护卫精悍、损失也小
		"bandit":
			return 0.85
		_:
			return 0.6

## 我方损失率
func loss_rate(kind: String) -> float:
	match kind:
		"caravan":
			return 0.08
		"bandit":
			return 0.10
		_:
			return 0.12

## 缴获物的称呼（辎重 / 货物 / 赃物）
func loot_word(kind: String) -> String:
	match kind:
		"caravan":
			return "货物"
		"bandit":
			return "赃物"
		_:
			return "辎重"

## 撤退的士气代价（**照搬** 01 §5.8 simulate_retreat 末尾那三行，含整数截断）：
##     share = (我方阵亡×100 / (我方阵亡 + 敌方阵亡)) × 我方阵亡 / 我方总兵力
##     士气 += share × −30 / 100
## 关键在它是**两个比例的乘积**：小队死 2 人可能和大队死 20 人扣得一样多，
## 所以「撤退贵不贵」取决于「你在这支队伍里占多大比例」，而不是绝对伤亡。
## 返回值是**要扣的正数**（0 表示不扣）。原文里 allyDead/enemyDead/allyTotal 都是
## 那场战斗的记账部队，本工程没有这两个账本，调用点按「双方伤亡相当」估算敌方数字。
func retreat_morale_penalty(ally_dead: int, enemy_dead: int, ally_total: int) -> int:
	if ally_dead + enemy_dead <= 0 or ally_total <= 0:
		return 0
	var share := (ally_dead * 100 / (ally_dead + enemy_dead)) * ally_dead / ally_total
	return share * 30 / 100