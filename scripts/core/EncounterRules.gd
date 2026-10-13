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

# =============================================================== 遭遇菜单的定价（第四轮 4c）
## 原文档里「遭遇面板有哪些选项」是【未解】（没有发行文件可查），所以下面这张表是**显式
## 设计决策**，不是照搬：
##   · 「花钱买路」与「索要买路钱」是同一件事的两个方向 —— 谁掏钱取决于双方兵力对比；
##   · 领主部队两边都不参与（不收买路钱、也不吃讹诈）—— 军事贵族的面子问题。
##     好处是三种遭遇（强盗 / 商队 / 领主）的手感真的不同，而不是同一张菜单换名字。
@export var toll_per_man_bandit := 3      ## 强盗：每人 3 金（拦路收费）
@export var toll_per_man_caravan := 5     ## 商队：货值高、护卫少，愿意多掏
@export var demand_ratio := 1.5           ## 索要买路钱所需的战力优势（我方 / 敌方）
@export var demand_multiplier := 1.2      ## 你收的比他们收你的略多（你是主动方）
@export var renown_discount_step := 20    ## 每 20 点声望，买路钱便宜 1%
@export var renown_discount_max := 30     ## 折扣上限 30%（再高就没人拦你了，那是另一套机制）

## 这种部队收不收买路钱（领主不收）
func can_toll(kind: String) -> bool:
	return kind == "bandit" or kind == "caravan"

## 每人买路钱（领主返回 0，配合 can_toll 用）
func toll_per_man(kind: String) -> int:
	match kind:
		"caravan":
			return toll_per_man_caravan
		"bandit":
			return toll_per_man_bandit
		_:
			return 0

## 敌方战力当量，与 CampaignState.combat_power 同量纲（人数 × 兵员质量）：
## 强盗是乌合之众（0.8），商队护卫训练有素（1.0），领主部队是职业军（1.4）。
## 这三个系数是**本地化取值** —— 原文档里没有「部队战力」这种可直接比较的量。
func enemy_power(kind: String, troops: int) -> int:
	var m := 1.0
	match kind:
		"bandit":
			m = 0.8
		"caravan":
			m = 1.0
		_:
			m = 1.4
	return int(round(float(troops) * m))

## 声望折扣（百分比）：声望越高，强盗越不敢狮子大开口 —— 本地化新增，
## 给 4a 的声望再加一条「在地图上看得见」的用处。
func renown_discount(renown: int) -> int:
	return clampi(renown / renown_discount_step, 0, renown_discount_max)

## 买路钱 = 人数 × 每人单价 ×（1 − 声望折扣），至少 10 金（不值得为三瓜两枣谈一次）
func bribe_price(kind: String, troops: int, renown: int) -> int:
	var base := troops * toll_per_man(kind)
	if base <= 0:
		return 0
	return maxi(10, base * (100 - renown_discount(renown)) / 100)

## 索要买路钱：他们得交多少（比他们收你的多 demand_multiplier 倍）
func demand_gain(kind: String, troops: int) -> int:
	var base := troops * toll_per_man(kind)
	if base <= 0:
		return 0
	return maxi(10, int(round(float(base) * demand_multiplier)))

## 索要买路钱所需的战力（不足则这一项灰掉，玩家看得见差多少）
func demand_need(kind: String, troops: int) -> int:
	return ceili(demand_ratio * float(enemy_power(kind, troops)))

## 索要买路钱成功时的声望收益（你白拿了一笔，还长了威风）
func demand_renown(troops: int) -> int:
	return maxi(1, troops / 20)