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

var kind: int = Kind.BANDIT
var vision: float = 90.0
var repath_timer: float = 0.0
var repath_interval: float = 9.0
var last_goal: Vector2 = Vector2(-1, -1)
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
	rng.seed = p_seed
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
		# 追击：频繁重算，但至少间隔 1.2 秒
		if repath_timer <= 0.0 or last_goal.distance_to(pd) > 22.0:
			var pts := data.path_coarse.find_path(my, pd)
			if pts.size() >= 1:
				set_path(pts)
			last_goal = pd
			repath_timer = 1.4
	else:
		chasing = false
		if not moving and repath_timer <= 0.0:
			# 游荡：以出生点为中心随机取一个 120~320 米外的目标
			var a := rng.randf_range(0.0, TAU)
			var r := rng.randf_range(120.0, 320.0)
			var g := wander_center + Vector2(cos(a), sin(a)) * r
			g.x = clampf(g.x, 8.0, cfg.map_size - 8.0)
			g.y = clampf(g.y, 8.0, cfg.map_size - 8.0)
			var pts2 := data.path_coarse.find_path(my, g)
			if pts2.size() >= 1:
				set_path(pts2)
				last_goal = g
			repath_timer = rng.randf_range(6.0, 11.0)

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
	var pts := data.path_coarse.find_path(my, goal)
	if pts.size() >= 1:
		set_path(pts)
		last_goal = goal
		repath_timer = repath_interval * rng.randf_range(0.7, 1.3)
	else:
		repath_timer = 3.0

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
