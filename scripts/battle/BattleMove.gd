## =============================================================================
##  BattleMove —— 单条招式的全部参数（玩家三段普攻 / Boss 各招式共用）
##  分成 前摇(startup) / 判定(active) / 后摇(recovery) 三段，全部用 @export 暴露，
##  方便在 Inspector 里反复调手感。
## =============================================================================
class_name BattleMove
extends Resource

@export_group("标识")
@export var id: String = "move"                  ## 内部 id（状态机用）
@export var display: String = "招式"              ## 调试 / HUD 显示
@export var anim: String = "atk1"                ## 对应 FighterRig 的动画片段名

@export_group("时序（秒）")
@export var startup: float = 0.12                ## 前摇
@export var active: float = 0.08                 ## 判定持续
@export var recovery: float = 0.22               ## 后摇（可被 cancel_into 里的状态取消）
@export var hit_interval: float = 0.0            ## >0 且 hits>1 时为多段判定的间隔
@export var hits: int = 1                        ## 判定次数（横扫连击 / 蓄满剑气多段）

@export_group("数值")
@export var damage: float = 12.0
@export var poise_damage: float = 8.0            ## 对 Boss 破防值的累积
@export var knockback: float = 110.0
@export var lift: float = 0.0                    ## 命中后给目标的额外竖直速度
@export var hitstop: float = 0.05                ## 命中顿帧
@export var stamina: float = 10.0                ## 消耗气力
@export var move_dist: float = 0.0               ## 出招时的前冲位移
@export var crit_mult: float = 1.0               ## 暴击倍率（第 3 段 / 反击斩用）

@export_group("判定盒（相对角色脚底，朝右为正）")
@export var box_offset: Vector2 = Vector2(30, -34)
@export var box_size: Vector2 = Vector2(52, 38)
@export var box_active_from: float = 0.0         ## 判定盒在 active 段内的启用比例（1=全程）

@export_group("规则")
@export var parryable: bool = true               ## Boss 招式：能否被弹反（白/红预警）
@export var guard_break: bool = false            ## 是否无视玩家无敌帧（未使用，保留扩展）
@export var cancel_into: PackedStringArray = PackedStringArray(["DODGE"])  ## 后摇可取消进入的状态

@export_group("Boss 专用：AI 选招")
@export var weight: float = 1.0                  ## 随机权重
@export var min_range: float = 0.0               ## 触发距离下限
@export var max_range: float = 999.0             ## 触发距离上限
@export var telegraph: float = 0.4               ## 预警时长（前摇里闪光的时长）
@export var projectile: String = ""              ## 非空则在该招式判定帧生成投射物
@export var phase2_only: bool = false            ## 仅二阶段可用

func total_time() -> float:
	if hits > 1 and hit_interval > 0.0:
		return startup + active + hit_interval * float(hits - 1) + recovery
	return startup + active + recovery

func can_cancel_to(state: String) -> bool:
	return cancel_into.has(state)
