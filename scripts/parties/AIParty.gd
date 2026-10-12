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

func setup_ai(p_data: MapData, p_cfg: MapConfig, p_kind: int, p_name: String, p_faction: int, p_count: int, p_speed: float, mat: Material, model_mesh: Mesh, p_seed: int) -> void:
	kind = p_kind
	setup(p_data, p_cfg, p_name, p_faction, p_count, p_speed, mat, model_mesh)
	rng = RandomNumberGenerator.new()
	rng.state = hash(str(p_seed) + "|ai") | 1
	repath_timer = rng.randf_range(0.5, 4.0)
	repath_interval = rng.randf_range(7.0, 13.0)
	wander_center = Vector2(position.x, position.z)
	vision = p_cfg.bandit_vision * rng.randf_range(0.8, 1.25)
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
	if kind == Kind.BANDIT:
		_bandit_think(delta)
	else:
		if not moving or repath_timer <= 0.0:
			_route_think()
	super.step(delta)

# ---------------------------------------------------------------- 强盗
func _bandit_think(_delta: float) -> void:
	var player = data.get_meta("player_ref", null)
	if player == null:
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
	var pts := data.path_coarse.find_path(my, goal)
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
