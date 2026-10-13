## =============================================================================
##  PartySpawner —— 开局把所有部队摆到地图上（1 个玩家 + N 个 AI）
##
##  从 Main.gd 原样搬出：_spawn_player / _spawn_ai_parties / _add_ai /
##  _random_town / _random_wilderness / randi_range_seed。
##
##  ⚠ 改这里之前先读这段：**本文件的调用顺序就是生成指纹的一部分**。
##    · 每支部队的种子是 config.map_seed + 派对下标 * 97 + 7，
##      而下标取自 ai_parties.size()，所以「谁先被造出来」会改变所有后继部队的名字与视野；
##    · randi_range_seed / _random_wilderness 各自新建独立 RNG（不抽全局流），
##      所以搬动本文件的代码不会扰动地图生成的随机序列 —— 但如果将来把这些抽取
##      改成用 data.rng，就会立刻改变指纹。
##  自检：& $GODOT --headless --path <工程> --script res://tools/gen_fingerprint.gd
##
##  另一个好处：ai_parties 是**引用传递**的同一个数组，这里 append 的部队
##  Main 立刻就看得见（不必再靠 set_meta 之类的侧信道）。
## =============================================================================
class_name PartySpawner
extends RefCounted

var cfg: MapConfig
var data: MapData
## 部队是 Node3D，必须有父节点才会进场景树
var host: Node
## 部队模型材质（与建筑同 shader，独立实例）
var mat: ShaderMaterial
## 与 Main 共享的同一个数组
var parties: Array[AIParty]
## 强盗追击的目标。以前是 data.set_meta("player_ref", …) + 每帧 get_meta 取回，
## 现在由这里显式注入，AIParty 侧是 typed 字段。
var player_target: PlayerParty = null

## 玩家出生点：王都（城堡）附近；没有城堡就退回地图中心
func player_start() -> Vector3:
	var cap: Settlement = null
	for s in data.settlements:
		if s.kind == Settlement.Kind.CASTLE:
			cap = s
			break
	if cap == null and data.settlements.size() > 0:
		cap = data.settlements[0]
	var p := Vector2(cfg.map_size * 0.5, cfg.map_size * 0.5)
	if cap != null:
		p = cap.pos + Vector2(18, 26)
	return Vector3(p.x, data.hm.height_at(p.x, p.y), p.y)

func spawn_player() -> PlayerParty:
	var f0 := data.faction(0)
	var p := PlayerParty.new()
	p.name = "PlayerParty"
	host.add_child(p)
	p.position = player_start()
	var mesh := PartyModelBuilder.build("player", f0.color, PartyModelBuilder.HORSE_BROWN, f0.color)
	p.setup_player(data, cfg, "%s的部队" % f0.name.substr(0, 4), 0, GameState.PLAYER_START_TROOPS, mat, mesh)
	p.refresh_label()
	p.label.text = "玩家部队 · %d 人" % GameState.PLAYER_START_TROOPS
	return p

func spawn_ai_parties() -> void:
	var total := cfg.ai_party_count
	var lords := data.factions.size()
	var caravans := maxi(2, int(round(float(total) * 0.28)))
	var bandits := maxi(1, total - lords - caravans)
	var idx := 0
	# 领主：每个势力一个
	for f in data.factions:
		var home: Settlement = null
		for s in data.settlements:
			if s.faction_id == f.id and s.kind == Settlement.Kind.CASTLE:
				home = s
				break
		if home == null:
			continue
		var p := home.pos + Vector2(cos(float(idx)) * 30.0, sin(float(idx)) * 30.0)
		var mesh := PartyModelBuilder.build("lord", f.color, PartyModelBuilder.HORSE_WHITE, f.color)
		var lp := _add_ai(AIParty.Kind.LORD, NameForge.new(cfg.map_seed + 31 + f.id).make_lord(f.id), f.id,
			randi_range_seed(cfg.map_seed + f.id * 7, 140, 280), p, mesh, cfg.ai_speed * 1.08, true)
		lp.is_boss = true
		lp.boss_title = "%s · %s领主" % [lp.party_name, f.name]
		idx += 1
	# 商队
	for i in caravans:
		var town := _random_town(i * 13 + 3)
		if town == null:
			continue
		var fid := town.faction_id
		var p2 := town.pos + Vector2(cos(float(i)) * 22.0, sin(float(i)) * 22.0)
		var mesh2 := PartyModelBuilder.build("caravan", data.faction(fid).color, PartyModelBuilder.HORSE_BROWN, data.faction(fid).color.darkened(0.2))
		var np := NameForge.new(cfg.map_seed + 91 + i)
		var cp := _add_ai(AIParty.Kind.CARAVAN, np.make_caravan(), fid,
			randi_range_seed(cfg.map_seed + i * 5, 18, 45), p2, mesh2, cfg.ai_speed * 0.82, false)
		cp.is_boss = true
		cp.boss_title = "%s · 护卫长" % cp.party_name
	# 强盗：野外
	var bandit_leader: AIParty = null
	var best_bandit := -1
	for i in bandits:
		var p3 := _random_wilderness(i * 29 + 5)
		var mesh3 := PartyModelBuilder.build("bandit", Color(0.45, 0.35, 0.25), PartyModelBuilder.HORSE_BLACK, Color(0.22, 0.18, 0.16))
		var np2 := NameForge.new(cfg.map_seed + 171 + i)
		var bp := _add_ai(AIParty.Kind.BANDIT, np2.make_bandit(), -1,
			randi_range_seed(cfg.map_seed + i * 11, 22, 78), p3, mesh3, cfg.ai_speed * 0.92, false)
		bp.is_boss = true
		bp.boss_title = "%s（强盗头目）" % bp.party_name
		if bp.troop_count >= best_bandit:
			best_bandit = bp.troop_count
			bandit_leader = bp
	# 人数最多的强盗团伙 = 强盗首领（Boss 战对手）
	if bandit_leader != null:
		bandit_leader.boss_title = "%s（强盗首领）" % bandit_leader.party_name
		bandit_leader.heavy = true

## 用「种子 + 区间」独立抽一个整数：同种子同结果，不依赖也不扰动全局 RNG 流
func randi_range_seed(s: int, a: int, b: int) -> int:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r.randi_range(a, b)

func _random_town(salt: int) -> Settlement:
	var towns: Array[Settlement] = []
	for s in data.settlements:
		if s.kind != Settlement.Kind.VILLAGE:
			towns.append(s)
	if towns.is_empty():
		return null
	return towns[absi(salt) % towns.size()]

func _random_wilderness(salt: int) -> Vector2:
	var r := RandomNumberGenerator.new()
	r.seed = cfg.map_seed + salt
	for _t in 400:
		var p := Vector2(r.randf_range(60.0, cfg.map_size - 60.0), r.randf_range(60.0, cfg.map_size - 60.0))
		if data.is_water(p.x, p.y):
			continue
		var cell := data.nav_fine.cell_of(p)
		if data.nav_fine.is_blocked(cell.x, cell.y):
			continue
		# 离定居点远一点
		var far := true
		for s in data.settlements:
			if p.distance_to(s.pos) < 60.0:
				far = false
				break
		if far:
			return p
	return Vector2(cfg.map_size * 0.5, cfg.map_size * 0.5)

func _add_ai(kind: int, pname: String, faction: int, count: int, pos: Vector2, mesh: Mesh, speed: float, heavy: bool) -> AIParty:
	var p := AIParty.new()
	# 稳定实体 id = 生成顺序的序号（同一种子必然一致；读档靠它对齐，见 SaveGame.gd）
	p.spawn_id = parties.size()
	p.name = "AI_%s_%d" % [pname, parties.size()]
	host.add_child(p)
	p.position = Vector3(pos.x, data.hm.height_at(pos.x, pos.y), pos.y)
	p.setup_ai(data, cfg, kind, pname, faction, count, speed, mat, mesh, cfg.map_seed + parties.size() * 97 + 7)
	p.heavy = heavy
	p.player_target = player_target
	if kind == AIParty.Kind.CARAVAN:
		var cart := MeshInstance3D.new()
		cart.mesh = PartyModelBuilder.build_cart()
		cart.material_override = mat
		cart.position = Vector3(0, 0, 3.4)
		cart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.add_child(cart)
	p.refresh_label()
	parties.append(p)
	return p