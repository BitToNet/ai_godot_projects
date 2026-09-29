## =============================================================================
##  Hitbox / Hurtbox —— 攻击判定盒与受伤判定盒（都是 Area2D）
##   · Hitbox 只在「判定帧」把 monitoring 打开，并记录本次攻击序号；
##     每次攻击对同一个目标只结算一次（Fighter.hit_this_attack）
##   · Hurtbox 只作为被检测方（collision_mask = 0），不主动检测
## =============================================================================
class_name Hitbox
extends Area2D

var owner_fighter: Fighter = null
var move: BattleMove = null
var attack_id: int = 0
