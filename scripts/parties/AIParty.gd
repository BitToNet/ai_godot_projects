## =============================================================================
##  AIParty —— AI 部队（领主 / 商队 / 强盗）
##  行为：
##   · 领主 LORD   ：在本势力定居点之间巡逻（优先王都 → 城镇 → 村庄）
##   · 商队 CARAVAN：在城镇之间往返；寻路代价里道路便宜，因此自然走官道
##   · 强盗 BANDIT ：野外游荡；玩家进入视野(vision)后追击玩家
##  寻路统一用粗栅格（8 米/格）以降低 CPU 开销，并且各部队的重算时间互相错开。
## =============================================================================
class_name AIParty
extends PartyBase

enum Kind { LORD, CARAVAN, BANDIT }

const CHASE_REPATH := 1.4          ## 追击时的重寻路间隔（秒）
const FAIL_BACKOFF_MIN := 3.0      ## 寻路失败后的退避下限（秒）
const FAIL_BACKOFF_MAX := 60.0     ## 退避上限（秒）

var kind: int = Kind.BANDIT
var vision: float = 90.0
var repath_timer: float = 0.0
var repath_interval: float = 9.0
## 该部队是否有**在途**的寻路请求（入队到回调之间为 true）。
## 第七轮 ① 新增：没有它时，`not moving` 每帧都成立，同一支部队会反复往队列里塞同一个请求。
var path_pending: bool = false
## 首次寻路的错峰延迟（0~3 s）。**不抽随机数**，直接用出生点散列 —— 抽签会扰动各部队的
## RNG 序列（强盗游荡点、选点阈值都吃同一股流），而错峰只需要「彼此不同」，不需要随机性。
var start_delay: float = 0.0
var last_goal: Vector2 = Vector2(-1, -1)
var fail_cell: Vector2i = Vector2i(-1, -1)  ## 上次寻路失败的粗栅格格子
var fail_until: float = 0.0                 ## 该格子的退避截止时刻（_elapsed 秒）
var fail_streak: int = 0                    ## 连续失败次数（成功一次即清零）
var _elapsed: float = 0.0                   ## 本部队自己的计时（秒）
var chasing: bool = false
var wander_center: Vector2 = Vector2.ZERO
var rng: RandomNumberGenerator
var heavy: bool = false   ## 领主部队（用于 UI 区分）
var is_boss: bool = true       ## 该部队的首领会作为 Boss 出场（现在所有部队都会进战斗场景）
var boss_title: String = ""    ## Boss 战里显示的名号（领主 / 商队护卫长 / 强盗头目 / 强盗首领）
## 强盗追击的目标。由 PartySpawner 显式注入（typed）；
## 以前是 data.set_meta("player_ref", player) + 每帧 get_meta 取回的弱类型侧信道。
var player_target: PartyBase = null

func setup_ai(p_data: MapData, p_cfg: MapConfig, p_kind: int, p_name: String, p_faction: int, p_count: int, p_speed: float, mat: Material, model_mesh: Mesh, p_seed: int) -> void:
	kind = p_kind
	setup(p_data, p_cfg, p_name, p_faction, p_count, p_speed, mat, model_mesh)
	rng = RandomNumberGenerator.new()
	rng.state = hash(str(p_seed) + "|ai") | 1
	repath_timer = rng.randf_range(0.5, 4.0)
	repath_interval = rng.randf_range(7.0, 13.0)
	wander_center = Vector2(position.x, position.z)
	vision = p_cfg.bandit_vision_m() * rng.randf_range(0.8, 1.25)
	start_delay = fposmod(position.x * 0.0173 + position.z * 0.0311, 3.0)
	refresh_label()

func ai_kind() -> String:
	match kind:
		Kind.LORD:
			return "lord"
		Kind.CARAVAN:
			return "caravan"
		_:
			return "bandit"

func step(delta: float) -> void:
	repath_timer -= delta
	_elapsed += delta
	# ---- 第七轮 ①：世界时间冻结时**不再思考** ----
	# delta == 0（暂停 / 开局 / 遭遇锁）时，部队不会移动、repath_timer 也不会减少，于是
	# `not moving` 恒为真 —— 修之前每帧都朝寻路队列里塞一次请求；而队列的契约是
	# 「每帧至少完成一个」（PathQueue 的饿死保护），暂停期间就变成**每帧付一整次粗栅格 A\***。
	# 4096 m 出货图的实测（临时探针 tools/frame_bisect_tmp.gd，60 帧/档）：
	#   idle（时间冻结）avg 184.9 / p50 42.0 / p95 1070.0 / max 1495.4 ms   ← 用户报的「特别卡」
	#   把 Main._process 关掉后同场景 avg 0.40 ms ⇒ 全部代价都在 _process 里，且 AI 清空后
	#   avg 减半、p50 掉到 0.42 ms ⇒ 主体是寻路请求风暴，不是迷雾/地形/小地图。
	# 对照：1024 m 只有 avg 0.803 / p95 5.4 ms（14 支部队，风暴规模小两个数量级）。
	# 冻结期间跳过思考不丢任何状态：位置、计时器、moving 本来就不变，时间一恢复当帧照常思考。
	if delta > 0.0:
		if kind == Kind.BANDIT:
			_bandit_think(delta)
		elif not path_pending and _elapsed >= start_delay and (not moving or repath_timer <= 0.0):
			# start_delay 只影响「开局第一次」：此后每支部队各自的 repath_interval 已经错开。
			# 没有它的话，开局第一次解除暂停时全部 31~100 支部队会在同一帧抛出请求。
			_route_think()
	super.step(delta)

# ---------------------------------------------------------------- 强盗
func _bandit_think(_delta: float) -> void:
	var player := player_target
	if player == null or not is_instance_valid(player):
		return
	var pd := Vector2(player.position.x, player.position.z)
	var my := Vector2(position.x, position.z)
	var dist := my.distance_to(pd)
	if dist < vision:
		chasing = true
	elif dist > vision * 2.4:
		chasing = false
	if chasing:
		# 追击：固定节流重算。
		# 原来这里还有一条 `or last_goal.distance_to(pd) > 22.0` 的旁路：玩家速度 46 m/s，
		# 22 米约 0.5 秒就走完，这条旁路几乎总是成立，等于把节流彻底绕开
		# （≈2 次 A*/秒/部队，7 支强盗同时追击就是寻路风暴）。
		if repath_timer <= 0.0:
			_repath_to(pd, CHASE_REPATH)
	else:
		chasing = false
		if not moving and repath_timer <= 0.0:
			# 游荡：以出生点为中心随机取一个 120~320 米外的目标
			var a := rng.randf_range(0.0, TAU)
			var r := rng.randf_range(120.0, 320.0)
			var g := wander_center + Vector2(cos(a), sin(a)) * r
			g.x = clampf(g.x, 8.0, cfg.map_size - 8.0)
			g.y = clampf(g.y, 8.0, cfg.map_size - 8.0)
			# 注意：随机数必须在寻路之前抽取，才能保持与旧实现相同的 RNG 抽取顺序
			# （地图布局的确定性依赖各部队的抽签序列不变）
			_repath_to(g, rng.randf_range(6.0, 11.0))

# ---------------------------------------------------------------- 领主 / 商队
func _route_think() -> void:
	var my := Vector2(position.x, position.z)
	var goal := Vector2.INF
	var guarded := 0
	while guarded < 12:
		guarded += 1
		var cand := _pick_goal()
		if cand == Vector2.INF:
			break
		if cand.distance_to(my) > 90.0 and cand.distance_to(last_goal) > 60.0:
			goal = cand
			break
	if goal == Vector2.INF:
		repath_timer = 4.0
		return
	# 同上：随机数先取，保持 RNG 抽取顺序不变
	_repath_to(goal, repath_interval * rng.randf_range(0.7, 1.3))

## 重算路径到 goal。interval = 下一次重算的间隔（秒）。
## 失败处理：记住失败的粗栅格格子，在 3→6→12→24→60 秒的指数退避窗口内不再对它重试；
## 连续失败次数在成功一次后清零。这样「随机游荡点反复落在同一片不可达区域」不会
## 每次都发起搜索。目标格一变（部队走了 / 换了个目标）就立刻正常重试。
func _repath_to(goal: Vector2, interval: float) -> bool:
	var gcell := data.nav_coarse.cell_of(goal)
	if gcell == fail_cell and _elapsed < fail_until:
		repath_timer = interval
		return false
	var my := Vector2(position.x, position.z)
	# 第六轮 6d 后半：AI 寻路走全局队列（每帧预算，见 PathQueue）。结果与同步 find_path
	# **逐点相同**，只是要等队列排到它（通常就是下一帧）—— 4096 m / 100 部队时，这就是
	# 「不掉帧」与「一次卡 200~730 ms」的区别。
	# data.path_queue 为空（个别检查直接构造 MapData）时退回同步，行为与旧版完全一致。
	if data.path_queue != null:
		# 第七轮 ①：同一支部队同时只允许**一个**在途请求。
		# 没有这条时，`not moving` 每帧成立 ⇒ 每帧重复入队同一个目标，队列的 pending 永远掉不到 0，
		# 「每帧至少完成一个」就退化成每帧一次满额 A*。回调里会把 path_pending 清掉。
		if path_pending:
			return false
		path_pending = true
		repath_timer = interval
		data.path_queue.enqueue(data.path_coarse, my, goal, func(pts: PackedVector3Array) -> void:
			_apply_path(pts, goal, gcell, interval))
		return true
	return _apply_path(data.path_coarse.find_path(my, goal), goal, gcell, interval)

## 寻路结果的统一结算：同步与队列两条路共用，保证两条路的成功/失败行为一致
## （成功则 set_path 并清零失败计数；失败则按指数退避记住这个目标格）。
func _apply_path(pts: PackedVector3Array, goal: Vector2, gcell: Vector2i, interval: float) -> bool:
	path_pending = false   # 请求已结算（成功或失败），下一帧可以再提交
	if pts.size() >= 1:
		set_path(pts)
		last_goal = goal
		fail_streak = 0
		fail_cell = Vector2i(-1, -1)
		fail_until = 0.0
		repath_timer = interval
		return true
	fail_streak += 1
	var backoff := minf(FAIL_BACKOFF_MIN * pow(2.0, float(fail_streak - 1)), FAIL_BACKOFF_MAX)
	fail_cell = gcell
	fail_until = _elapsed + backoff
	repath_timer = interval
	return false

func _pick_goal() -> Vector2:
	match kind:
		Kind.LORD:
			# 本势力定居点之间巡逻
			var own: Array[Settlement] = []
			for s in data.settlements:
				if s.faction_id == faction_id:
					own.append(s)
			if own.is_empty():
				return Vector2.INF
			var w := 0.0
			for s in own:
				w += s.importance()
			var pick := rng.randf() * w
			for s in own:
				pick -= s.importance()
				if pick <= 0.0:
					return s.pos
			return own[own.size() - 1].pos
		Kind.CARAVAN:
			# 城镇之间往返（跨势力，形成长商路）
			var towns: Array[Settlement] = []
			for s in data.settlements:
				if s.kind == Settlement.Kind.TOWN or s.kind == Settlement.Kind.CASTLE:
					towns.append(s)
			if towns.is_empty():
				return Vector2.INF
			return towns[rng.randi_range(0, towns.size() - 1)].pos
	return Vector2.INF
