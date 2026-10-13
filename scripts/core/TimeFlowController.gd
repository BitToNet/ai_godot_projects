## =============================================================================
##  TimeFlowController —— 「世界时间何时流动」的状态机（骑砍式的暂停）
##
##  从 Main.gd 搬出：enum TimeFlow / game_paused / time_flow / speed_steps /
##  speed_index / _space_latched / _time_lock 与 _eval_time_flow() / _order_move()。
##
##  规则（原样保留）：
##   1) 松开 time_flow（默认 空格 / 手柄X）→ 解除消费标记，允许下一次长按生效；
##   2) 行军途中按下 → 行军立刻中断并进入暂停，这次按住不再触发时间流动；
##   3) 部队停下后长按 → 世界时间才流动，松开立刻暂停；
##   4) 遭遇对话 / Boss 战（time_lock）→ 强制暂停，空格无效。
##
##  外部只读 game_paused / state 即可；锁定与解锁走 lock() / unlock()，
##  不要把 time_lock 直接当开关用（Boss 战结束还要重新 evaluate 一次）。
## =============================================================================
class_name TimeFlowController
extends RefCounted

enum State {
	FROZEN,      ## 时间暂停：原地待命 / 行军被空格打断（开局默认状态）
	MARCHING,    ## 行军中：世界时间随部队移动自动流动，抵达瞬间转 FROZEN
	WAITING,     ## 原地长按空格：世界时间流动，松开立刻暂停
	LOCKED,      ## 遭遇对话 / Boss 战：强制暂停，空格无效
}

var state: int = State.FROZEN        ## 当前状态（供 UI / 调试查看）
var game_paused: bool = true         ## 派生量：本帧世界时间是否暂停
var speed_steps: Array[float] = [1.0, 2.0, 4.0]
var speed_index: int = 0
var time_lock: bool = false          ## 遭遇对话 / Boss 战：强制暂停，空格无效
var space_latched: bool = false      ## 本次长按是否已被消费（打断行军 / 等待中下达命令）

var player: PartyBase
var day_night: DayNightCycle

## 每帧（以及下达命令 / 锁定变化后）裁决世界时间是否流动
func evaluate() -> void:
	if player == null:
		return
	var space_down := Input.is_action_pressed("time_flow")
	if not space_down:
		space_latched = false
	elif not space_latched and player.moving:
		# 规则 2：行军途中按空格 → 移动立马停止，进入暂停状态
		space_latched = true
		player.halt()
		print("[行军] 空格打断：部队立刻停止前进，世界时间暂停。")

	var next: int = State.FROZEN
	if time_lock:
		next = State.LOCKED
	elif player.moving:
		next = State.MARCHING
	elif space_down and not space_latched:
		next = State.WAITING
	state = next
	game_paused = next == State.FROZEN or next == State.LOCKED
	if day_night != null:
		day_night.paused = game_paused

## 下达移动命令：行军期间世界时间自动流动，抵达的瞬间立刻暂停。
## 若此刻正按着空格（原地推进时间），把这次按指标记为「已消费」——
## 抵达后必须重新长按空格，世界时间才会再次流动。
func order_move(goal: Vector2) -> void:
	if player == null:
		return
	if Input.is_action_pressed("time_flow"):
		space_latched = true
	player.set_destination(goal)
	if player.moving:
		evaluate()
		# 行军号角（下达命令的听觉反馈）
		Sfx.play("order", -4.0)
		print("[行军] 前往 (%.0f, %.0f)：途中时间流动，抵达后立刻暂停。" % [goal.x, goal.y])

## 强制暂停（遭遇对话 / Boss 战），并立刻刷新 game_paused
func lock() -> void:
	time_lock = true
	evaluate()

func unlock() -> void:
	time_lock = false
	evaluate()

## 循环切换时间流速（1x → 2x → 4x → 1x）
func cycle_speed() -> void:
	speed_index = (speed_index + 1) % speed_steps.size()
	if day_night != null:
		day_night.speed = speed_steps[speed_index]