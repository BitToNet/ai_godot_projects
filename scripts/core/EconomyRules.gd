## =============================================================================
##  EconomyRules —— 经济与军费的数值表（改平衡只动这里）
##
##  参考外部资料（本机 G:\warband_docs，**不在本仓库内**）的骑砍反编译文档。
##  文中标签沿用原文档的三级证据标准：实证 / 推断 / 未解。
##  照搬的是**算术语义与模型形状**，凡是本工程没有的量（兵种等级、技能、
##  物品背包）都做了本地化映射，注释里逐处标「本地化」。
##
##  照搬（均为原文档【实证】）：
##   · 单兵周薪 (等级+3)²/25，整数截断，下限 1 —— 01 §2.2 game_get_troop_wage
##   · 周薪口径：Σ 单兵周薪 × 人数 —— 01 §2.4 calculate_weekly_party_wage
##   · 领导力折扣 wage×(100−5×领导力)/100 —— 01 §2.2
##   · 士气 = 50 + 领导力×12 − 人数 + 食物加成 − 断粮 30 − 欠薪惩罚 —— 01 §3.3
##   · 欠薪惩罚 clamp(欠款×10 / max(周薪,1), 1, 31) —— 01 §3.3
##   · 村庄招募 10 金/人、min(志愿者池, 编制余位, 金/10) —— 01 §2.7
##   · 战利品「每人基准 30 金 × 兵种档位系数」的形状 —— 01 §2.9 party_calculate_loot
##
##  本地化映射（**不是骑砍原值**，原文没有对应概念）：
##   · 等级 → 兵员档次 tier：level_of_tier = [4, 12, 22]（民兵 / 正规军 / 精锐）
##   · 领导力 → 声望 renown：leadership_of_renown() = 声望/100，封顶 10
##     （原文里「领导力 10 砍一半工资」是最关键的一档，这里让它对应声望 1000）
##   · 食物营养值（原文【未解】：item_get_slot(item,1) 无发行文件可查）
##     → 用「件数 × 3/2、封顶 food_bonus_cap」代替
##   · 每日补给消耗量（原文【未解】：consume_food 的调用者不在 34 个脚本内）
##     → supply_per_day() = 每 10 兵 1 件
##   · 逃兵（原文**没有**忠诚/逃兵状态量，只有 morale）→ deserters() 是本工程新增
## =============================================================================
class_name EconomyRules
extends Resource

## 兵员档次 → 代用等级（本地化映射：三档分别对应民兵 / 正规军 / 精锐）
@export var level_of_tier: Array[int] = [4, 12, 22]
## 档次显示名（HUD / 菜单用）
@export var tier_names: Array[String] = ["民兵", "正规军", "精锐"]
## 升到下一档的一次性训练费（本地化：对应原文「升级费 10…200」的量级，
## 但原文是每级 10~200 的分段表，本工程只有三档，所以取三个代表值）
@export var tier_upgrade_cost: Array[int] = [0, 240, 900]

## 声望 → 领导力（本地化映射，封顶 10）
@export var renown_per_leadership: int = 100
@export var leadership_cap: int = 10

## 每 10 名士兵每天消耗 1 件补给（本地化）
@export var troops_per_supply: int = 10
## 每件食物提供的士气加成（原文：食物营养值×3/2；本地化）
@export var food_morale_per_item: float = 1.5
## 食物士气加成封顶（本地化：避免「囤粮 = 无限士气」）
@export var food_bonus_cap: int = 15
## 断粮惩罚（照搬 01 §3.3 的 −30）
@export var starve_penalty: int = 30
## 欠薪：每欠 1 周扣多少士气，以及单次上限（照搬 clamp(…, 1, 31) 的形状）
@export var debt_morale_per_week: int = 10
@export var debt_morale_cap: int = 31

## 编制上限（本地化：对应原文 领导力×5 与 base_companion_limit 的形状）
@export var base_party_capacity: int = 40
@export var capacity_per_leadership: int = 5
## 声望每多少点额外 +1 编制
@export var renown_per_capacity: int = 20

## 士气低于该值开始逃兵（本地化新增）
@export var desert_morale_threshold: int = 20

## 补给单价（本地化：原文的食物标价在 25~220 之间，本工程金币量级更小，
## 所以取 5 金/件。第四轮的城镇市场会用这个值作为基准价，再按繁荣度浮动）
@export var supply_unit_price: int = 5

## 兵员档次的战斗力倍率（**本地化，原文没有这个表**）：骑砍里档次的差异体现在
## 兵种属性 / 装备 / 升级树上，本工程没有兵种属性表，所以直接给一个倍率。
## 没有它「升档」就是纯支出 —— 花了 240 金只换来工资涨 9 倍，没人会做这个选择。
@export var tier_combat_multiplier: Array[float] = [1.0, 1.35, 1.8]

static func create() -> EconomyRules:
	return EconomyRules.new()

# ------------------------------------------------------------------ 军费
## 单兵周薪：(等级+3)²/25 整数截断，下限 1（照搬 01 §2.2）
func wage_per_man_week(tier: int) -> int:
	var lv: int = int(level_of_tier[clampi(tier, 0, level_of_tier.size() - 1)])
	return maxi((lv + 3) * (lv + 3) / 25, 1)

## 声望 → 领导力（本地化映射）
func leadership_of_renown(renown: int) -> int:
	return clampi(renown / maxi(renown_per_leadership, 1), 0, leadership_cap)

## 部队周薪总额（未打折）：Σ 单兵周薪 × 人数
func weekly_wage_base(troops: int, tier: int) -> int:
	return maxi(troops, 0) * wage_per_man_week(tier)

## 实际应付周薪：再乘领导力折扣 (100 − 5×领导力)/100（照搬 01 §2.2 的形状）
func weekly_wage(troops: int, tier: int, renown: int) -> int:
	var lead := leadership_of_renown(renown)
	return maxi(troops, 0) * wage_per_man_week(tier) * (100 - 5 * lead) / 100

## 升档要花的一次性训练费
func upgrade_cost(tier: int) -> int:
	var next := clampi(tier + 1, 0, tier_upgrade_cost.size() - 1)
	return int(tier_upgrade_cost[next])

func tier_name(tier: int) -> String:
	return tier_names[clampi(tier, 0, tier_names.size() - 1)]

func max_tier() -> int:
	return level_of_tier.size() - 1

## 某档的战斗力倍率
func combat_multiplier(tier: int) -> float:
	return float(tier_combat_multiplier[clampi(tier, 0, tier_combat_multiplier.size() - 1)])

# ------------------------------------------------------------------ 士气
## 食物士气加成：件数 × 3/2、封顶（本地化替代原文的「营养值」）
func food_bonus(supplies: int) -> int:
	return mini(int(float(maxi(supplies, 0)) * food_morale_per_item), food_bonus_cap)

## 欠薪惩罚：clamp(欠款×10 / max(周薪,1), 1, 31) 的形状（照搬 01 §3.3）
## 本地化：本工程的「欠款」单位是「欠了几周」，所以用 debt_weeks × 10 作分子。
func debt_penalty(debt_weeks: int) -> int:
	if debt_weeks <= 0:
		return 0
	return clampi(debt_weeks * debt_morale_per_week, 1, debt_morale_cap)

## 完整士气模型：50 + 领导力×12 − 人数 + 食物 − 断粮 − 欠薪，钳 [0,100]（照搬 01 §3.3）
func morale_of(troops: int, tier: int, renown: int, supplies: int, debt_weeks: int) -> int:
	var m := 50 + leadership_of_renown(renown) * 12 - maxi(troops, 0)
	m += food_bonus(supplies)
	if supplies <= 0:
		m -= starve_penalty
	m -= debt_penalty(debt_weeks)
	return clampi(m, 0, 100)

# ------------------------------------------------------------------ 编制与补给
## 编制上限：基础 + 领导力×5 + 声望/20（本地化，对应原文 leadership 加编制的形状）
func party_capacity(renown: int) -> int:
	return base_party_capacity + leadership_of_renown(renown) * capacity_per_leadership \
		+ maxi(renown, 0) / maxi(renown_per_capacity, 1)

## 每天消耗的补给件数（本地化：原文的调用量【未解】）
func supply_per_day(troops: int) -> int:
	return maxi(1, maxi(troops, 0) / maxi(troops_per_supply, 1))

## 逃兵人数（本地化新增：原文只有 morale，没有逃兵规则）
func deserters(troops: int, morale: int) -> int:
	if morale >= desert_morale_threshold:
		return 0
	var short := float(desert_morale_threshold - morale) / float(desert_morale_threshold)
	return maxi(1, int(float(troops) * short * 0.25))

# ------------------------------------------------------------------ 战利品
## 每个敌兵折算的战利品金币（**本地化**：原文是「每人基准 30 × (掠夺+10)/10」的
## 物品掷骰权重，产出的是按市价计的货物；本工程没有物品背包，直接折算成金币，
## 所以取 6 而不是 30 —— 否则一场匪帮遭遇就够付几十周军费，经济立刻失去张力。
## 保留原文的「按敌人档位分档」形状：强盗 / 商队 / 领主 用 EncounterRules.loot_rate。
@export var loot_per_troop: float = 6.0