## =============================================================================
##  Main —— 总装配与游戏循环
##
##  生成顺序（每一步都 await 一帧，让 Loading 界面能刷新）：
##    1. HeightmapGenerator  : 高度场 + 生物群系 + 湖泊 + 河流
##    2. SettlementBuilder   : 势力选址 + 地基平整（会改高度场）
##    3. NavGrid x3          : 战术细栅格 / AI 粗栅格 / 道路栅格
##    4. RoadNetwork         : A* 修路 + 桥梁
##    5. MapTextureBaker     : splat 图 / 高度图 / 小地图 / 领地
##    6. Terrain / Water / Settlement / Vegetation 网格
##    7. Party / AI Party / Camera / FogOfWar / HUD
##
##  时间流动（骑砍式的「暂停」）由 Main 统一裁决，见 _eval_time_flow()：
##    · 点击地图 → 部队开始行军，行军期间世界时间自动流动；
##      走到目的地的瞬间，世界时间立刻暂停。
##    · 行军途中按空格 → 行军立刻中断，世界时间暂停。
##    · 部队停下后长按空格 → 世界时间才开始流动（松开立刻恢复暂停）。
##    · 遭遇对话 / Boss 战期间强制暂停（_time_lock）。
##  暂停时不再调用任何部队与昼夜的 step，但相机与 UI 仍然响应。
## =============================================================================
extends Node3D

@export var config: MapConfig
@export var audio: AudioConfig             ## 音效参数（留空则用默认值）

var data: MapData
var day_night: DayNightCycle
var hud: HUD
var camera_rig: CameraRig
var router: InputRouter
var terrain: TerrainManager
var water: WaterBuilder
var vegetation: VegetationScatter
var player: PlayerParty
var ai_parties: Array[AIParty] = []
var fog: FogOfWar
var lights_root: Node3D

var terrain_mat: ShaderMaterial
var settlement_mat: ShaderMaterial
var vegetation_mat: ShaderMaterial
var party_mat: ShaderMaterial

## 时间流动状态机（骑砍式：部队停下，时间也停下）
enum TimeFlow {
	FROZEN,      ## 时间暂停：原地待命 / 行军被空格打断（开局默认状态）
	MARCHING,    ## 行军中：世界时间随部队移动自动流动，抵达瞬间转 FROZEN
	WAITING,     ## 原地长按空格：世界时间流动，松开立刻暂停
	LOCKED,      ## 遭遇对话 / Boss 战：强制暂停，空格无效
}

var game_paused: bool = true           ## 派生量：本帧世界时间是否暂停
var time_flow: int = TimeFlow.FROZEN   ## 当前时间流动状态（供 UI / 调试查看）
var speed_steps := [1.0, 2.0, 4.0]
var speed_index := 0
var encounter_party: AIParty = null
var battle: BattleScene = null        ## 正在进行的 2D Boss 战（null = 在大地图上）
var encounters_enabled: bool = true   ## 调试/截图时可关掉遭遇UI
var cooldowns: Dictionary = {}
var _space_latched: bool = false       ## 本次空格按住是否已被消费（打断行军 / 等待中下达命令）
var _time_lock: bool = false           ## 遭遇对话 / Boss 战：强制暂停，空格无效
var _hover_timer: float = 0.0
var _gen_ms: int = 0
## 程序化生成**彻底**结束（含收尾的两帧与 0.35 s 遮罩收场）后置 true。
## 工具脚本（tools/gen_fingerprint.gd、tools/perf_probe.gd）靠它判断何时可以安全取指纹 / 释放场景，
## 不要改用 _gen_ms：那个值在收尾协程还在 await 时就已置位，此时 free() 会报
## 「Resumed function '_step()' after await, but class instance is gone」。
var gen_done: bool = false
var _label_scale_applied: float = -1.0   ## 上次实际写入标签的缩放因子（-1 = 尚未应用）
var _label_count_applied: int = -1       ## 上次应用时的标签总数（用于识别新增部队）

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	if config == null:
		config = MapConfig.new()
	if audio == null:
		audio = AudioConfig.new()
	get_window().theme = UiTheme.theme()
	_build_loading_ui()
	await get_tree().process_frame
	await get_tree().process_frame

	# ---------------- 0. 音效（程序化合成，零外部音频文件）----------------
	# 28 个音色共约 16 秒音频，合成耗时约 2 秒；setup 内部按时切片让出帧，
	# Loading 界面不会卡死。不想听可以在 Inspector 里把 AudioConfig.enabled 关掉。
	await _step("合成音效（程序化 PCM：打击 / 打铁 / 脚步 / 号角）…")
	await Sfx.setup(self, audio)

	var cfg := config
	data = MapData.new()
	data.cfg = cfg
	data.factions = Faction.build_all()

	# ---------------- 1. 高度场 ----------------
	await _step("生成地形高度场（多层噪声叠加）…")
	data.gen = HeightmapGenerator.new(cfg)
	data.hm = data.gen.generate()
	await _step("雕刻河流与湖泊（河道下切 / 渡口）…")

	# ---------------- 2. 定居点选址 ----------------
	await _step("选择定居点位置并平整地基…")
	var sb := SettlementBuilder.new(cfg, data)
	sb.place_all()

	# ---------------- 3. 寻路栅格 ----------------
	await _step("构建寻路栅格（海/湖/河不可通行）…")
	data.nav_fine = NavGrid.new(257, cfg.map_size)
	data.nav_fine.build_from(cfg, data.hm, data.gen)
	data.nav_coarse = NavGrid.new(129, cfg.map_size)
	data.nav_coarse.build_from(cfg, data.hm, data.gen)
	data.nav_road = NavGrid.new(129, cfg.map_size)
	data.nav_road.build_from(cfg, data.hm, data.gen, true)
	data.path_fine = Pathfinder.new(data.nav_fine)
	data.path_fine.heuristic_weight = 1.3
	data.path_coarse = Pathfinder.new(data.nav_coarse)
	data.path_coarse.heuristic_weight = 1.6

	# ---------------- 4. 道路 ----------------
	await _step("铺设道路网（A* 修路 + 架桥）…")
	var rn := RoadNetwork.new(cfg, data)
	rn.build()

	# ---------------- 5. 烘焙贴图 ----------------
	await _step("烘焙地表混合图 / 小地图 / 高度图…")
	var baker := MapTextureBaker.new(cfg, data)
	baker.bake_all()

	# ---------------- 6. 材质与网格 ----------------
	await _step("生成着色器与地形分块网格…")
	_make_materials()
	terrain = TerrainManager.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(cfg, data, terrain_mat, _player_start())

	await _step("注入海洋 / 湖泊 / 河流水面…")
	water = WaterBuilder.new()
	water.name = "Water"
	add_child(water)
	water.setup(cfg, data)

	await _step("建造城堡 / 城镇 / 村庄…")
	lights_root = Node3D.new()
	lights_root.name = "NightLights"
	add_child(lights_root)
	sb.build_all(self, settlement_mat, null)
	rn.build_bridges(self, settlement_mat)
	_build_settlement_lights()

	await _step("播种植被（MultiMesh 批处理）…")
	vegetation = VegetationScatter.new()
	vegetation.cfg = cfg
	vegetation.data = data
	vegetation.build(self, vegetation_mat)

	# ---------------- 7. 部队 / 相机 / 迷雾 / UI ----------------
	await _step("集结部队…")
	_spawn_player()
	_spawn_ai_parties()

	await _step("设置相机与环境…")
	day_night = DayNightCycle.new()
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.setup(cfg, data)
	day_night.paused = true   # 开局世界时间是冻结的：行军或长按空格才开始流动
	day_night.register_shader(terrain_mat, "night_amount")
	for wm in water.mats:
		day_night.register_shader(wm, "night_amount")
	day_night.register_shader(vegetation_mat, "night_amount")
	day_night.register_shader(settlement_mat, "night_glow")
	day_night.register_shader(party_mat, "night_glow")
	for l in lights_root.get_children():
		if l is OmniLight3D:
			day_night.register_night_light(l)

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.setup(cfg, data, player)
	camera_rig.strategic_changed.connect(_on_strategic_changed)

	fog = FogOfWar.new()
	fog.enabled = cfg.fog_of_war
	fog.setup(cfg)
	if fog.enabled:
		terrain_mat.set_shader_parameter("fog_map", fog.texture)
		terrain_mat.set_shader_parameter("fog_enabled", 1.0)
		vegetation_mat.set_shader_parameter("fog_map", fog.texture)
		vegetation_mat.set_shader_parameter("fog_enabled", 1.0)
		settlement_mat.set_shader_parameter("fog_map", fog.texture)
		settlement_mat.set_shader_parameter("fog_enabled", 1.0)
		party_mat.set_shader_parameter("fog_map", fog.texture)
		party_mat.set_shader_parameter("fog_enabled", 1.0)
		fog.reveal(Vector2(player.position.x, player.position.z), cfg.fog_reveal_radius * 1.4)

	_setup_ui()

	_gen_ms = Time.get_ticks_msec() - t0
	print("[Warband] 地图生成完成：%d ms   定居点 %d   桥梁 %d   植被实例 %d" % [
		_gen_ms, data.settlements.size(), data.bridges.size(), vegetation.total()])

	await _step("完成！")
	await get_tree().create_timer(0.35).timeout
	hud.hide_loading()
	gen_done = true
	# ---------------- 背景音乐（XSXB-Band 渲染的真实录音曲目）----------------
	# 地图生成完、Loading 收起之后再起乐，免得玩家在加载界面听半首。
	Bgm.setup(self, audio)
	Bgm.play("map", audio.bgm_fade_in)
	print("[音频] 背景音乐就绪：当前 %s（音量 %.1f dB，缺失音频时自动静默）" % [
		Bgm.current(), audio.bgm_db])

func _step(text: String) -> void:
	if hud != null:
		hud.set_loading(text)
	await get_tree().process_frame
	await get_tree().process_frame

func _player_start() -> Vector3:
	# 玩家出生在该势力王都附近
	var cap: Settlement = null
	for s in data.settlements:
		if s.kind == Settlement.Kind.CASTLE:
			cap = s
			break
	if cap == null and data.settlements.size() > 0:
		cap = data.settlements[0]
	var p := Vector2(cfg_center(), cfg_center())
	if cap != null:
		p = cap.pos + Vector2(18, 26)
	return Vector3(p.x, data.hm.height_at(p.x, p.y), p.y)

func cfg_center() -> float:
	return config.map_size * 0.5

func _build_loading_ui() -> void:
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(config)

func _make_materials() -> void:
	var cfg := config
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/terrain.gdshader")
	terrain_mat.set_shader_parameter("splat_map", data.splat_texture)
	terrain_mat.set_shader_parameter("map_size", cfg.map_size)
	terrain_mat.set_shader_parameter("sea_level", cfg.sea_level)
	terrain_mat.set_shader_parameter("snow_line", cfg.snow_line)
	terrain_mat.set_shader_parameter("mountain_line", cfg.mountain_line)
	terrain_mat.set_shader_parameter("night_amount", 0.0)

	settlement_mat = ShaderMaterial.new()
	settlement_mat.shader = load("res://shaders/settlement.gdshader")
	settlement_mat.set_shader_parameter("map_size", cfg.map_size)
	settlement_mat.set_shader_parameter("night_glow", 0.0)

	party_mat = ShaderMaterial.new()
	party_mat.shader = load("res://shaders/settlement.gdshader")
	party_mat.set_shader_parameter("map_size", cfg.map_size)
	party_mat.set_shader_parameter("night_glow", 0.0)

	vegetation_mat = ShaderMaterial.new()
	vegetation_mat.shader = load("res://shaders/vegetation.gdshader")
	vegetation_mat.set_shader_parameter("map_size", cfg.map_size)
	vegetation_mat.set_shader_parameter("night_amount", 0.0)

func _build_settlement_lights() -> void:
	for s in data.settlements:
		if s.kind == Settlement.Kind.VILLAGE:
			continue
		var l := OmniLight3D.new()
		l.name = "Light_%d" % s.id
		l.position = Vector3(s.pos.x, s.ground_h + 9.0, s.pos.y)
		l.omni_range = 46.0 if s.kind == Settlement.Kind.CASTLE else 34.0
		l.light_color = Color(1.0, 0.72, 0.36)
		l.light_energy = 0.0
		l.visible = false
		l.shadow_enabled = false
		lights_root.add_child(l)

func _spawn_player() -> void:
	var cfg := config
	player = PlayerParty.new()
	player.name = "PlayerParty"
	add_child(player)
	var start := _player_start()
	player.position = start
	var mesh := PartyModelBuilder.build("player", data.faction(0).color, PartyModelBuilder.HORSE_BROWN, data.faction(0).color)
	var mat := party_mat
	player.setup_player(data, cfg, "%s的部队" % data.faction(0).name.substr(0, 4), 0, 37, mat, mesh)
	player.refresh_label()
	player.label.text = "玩家部队 · 37 人"
	data.set_meta("player_ref", player)

func _spawn_ai_parties() -> void:
	var cfg := config
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
	r.seed = config.map_seed + salt
	for _t in 400:
		var p := Vector2(r.randf_range(60.0, config.map_size - 60.0), r.randf_range(60.0, config.map_size - 60.0))
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
	return Vector2(config.map_size * 0.5, config.map_size * 0.5)

func _add_ai(kind: int, pname: String, faction: int, count: int, pos: Vector2, mesh: Mesh, speed: float, heavy: bool) -> AIParty:
	var p := AIParty.new()
	p.name = "AI_%s_%d" % [pname, ai_parties.size()]
	add_child(p)
	p.position = Vector3(pos.x, data.hm.height_at(pos.x, pos.y), pos.y)
	p.setup_ai(data, config, kind, pname, faction, count, speed, party_mat, mesh, config.map_seed + ai_parties.size() * 97 + 7)
	p.heavy = heavy
	if kind == AIParty.Kind.CARAVAN:
		var cart := MeshInstance3D.new()
		cart.mesh = PartyModelBuilder.build_cart()
		cart.material_override = party_mat
		cart.position = Vector3(0, 0, 3.4)
		cart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.add_child(cart)
	p.refresh_label()
	ai_parties.append(p)
	return p

func _setup_ui() -> void:
	hud.bind(data, day_night)
	hud.minimap.setup(data, player, ai_parties, fog)
	hud.set_terrain_text("草原 (1.0x)")
	hud.encounter_choice.connect(_on_encounter_choice)

	# 输入路由：键码 → 语义信号。键位表在 project.godot 的 [input] 段，
	# 这里不再出现任何 KEY_* 常量，加手柄 / 改键位都不用动代码。
	router = InputRouter.new()
	router.name = "InputRouter"
	add_child(router)
	router.camera_rig = camera_rig
	router.hud = hud
	router.cfg = config
	router.order_move.connect(_order_move)
	router.cycle_speed_requested.connect(_on_cycle_speed)
	router.toggle_vegetation_requested.connect(_on_toggle_vegetation)
	router.toggle_mute_requested.connect(_on_toggle_mute)
	router.faction_labels_requested.connect(_toggle_faction_labels)

# =============================================================== 时间流动
## 每帧裁决「世界时间是否流动」（旧版的空格开关已改为骑砍式状态机）：
##   1) 松开空格 → 解除消费标记，允许下一次长按生效；
##   2) 行军途中按下空格 → 行军立刻中断并进入暂停，这次按住不再触发时间流动；
##   3) 部队停下后长按空格 → 世界时间才流动，松开立刻暂停；
##   4) 遭遇对话 / Boss 战 → 强制暂停，空格无效。
##  「长按」这个键由动作 time_flow 定义（默认 空格 / 手柄 X），见 project.godot 的 [input] 段。
func _eval_time_flow() -> void:
	if player == null:
		return
	var space_down := Input.is_action_pressed("time_flow")
	if not space_down:
		_space_latched = false
	elif not _space_latched and player.moving:
		# 规则 2：行军途中按空格 → 移动立马停止，进入暂停状态
		_space_latched = true
		player.halt()
		print("[行军] 空格打断：部队立刻停止前进，世界时间暂停。")

	var next: int = TimeFlow.FROZEN
	if _time_lock:
		next = TimeFlow.LOCKED
	elif player.moving:
		next = TimeFlow.MARCHING
	elif space_down and not _space_latched:
		next = TimeFlow.WAITING
	time_flow = next
	game_paused = next == TimeFlow.FROZEN or next == TimeFlow.LOCKED
	if day_night != null:
		day_night.paused = game_paused

## 下达移动命令：行军期间世界时间自动流动，抵达的瞬间立刻暂停。
## 若此刻正按着空格（原地推进时间），把这次按指标记为「已消费」——
## 抵达后必须重新长按空格，世界时间才会再次流动。
func _order_move(goal: Vector2) -> void:
	if player == null:
		return
	if Input.is_action_pressed("time_flow"):
		_space_latched = true
	player.set_destination(goal)
	if player.moving:
		_eval_time_flow()
		# 行军号角（下达命令的听觉反馈）
		Sfx.play("order", -4.0)
		print("[行军] 前往 (%.0f, %.0f)：途中时间流动，抵达后立刻暂停。" % [goal.x, goal.y])

# =============================================================== 循环
func _process(delta: float) -> void:
	if data == null or player == null:
		return
	# 0) 背景音乐的淡入淡出必须在战斗早退之前推进，否则战斗中永远切不过去
	Bgm.tick(delta)
	if battle != null:
		return
	# 1) 先判定本帧时间是否流动（行军 / 长按空格 / 强制锁）
	_eval_time_flow()
	var dt := 0.0 if game_paused else delta
	# 2) 玩家先走：抵达的那一帧立刻冻结世界，AI / 遭遇 / 昼夜都不再推进
	player.step(dt)
	if not player.moving:
		_eval_time_flow()
		dt = 0.0 if game_paused else delta
	# 部队
	for a in ai_parties:
		if a != null and is_instance_valid(a):
			a.step(dt)
	# 行军音效（马蹄）：只在世界时间流动的那几帧发声，暂停时自动静音
	_tick_party_audio(dt)
	# 迷雾（纯视觉，不受时间暂停影响）
	if fog != null:
		var pts: Array = [Vector2(player.position.x, player.position.z)]
		for a in ai_parties:
			if a != null and is_instance_valid(a):
				pts.append(Vector2(a.position.x, a.position.z))
		fog.update(delta, pts)
	# 遭遇检测（时间未流动时不检测）
	if not game_paused:
		_check_encounters(delta)
	_update_label_scale()
	# 悬停
	_hover_timer += delta
	if _hover_timer > 0.1:
		_hover_timer = 0.0
		_update_hover()

## 大地图行军马蹄声：玩家部队固定听得见；AI 部队按与相机的距离剔除并衰减，
## 免得十几支部队同时响在耳朵里糊成一片。
func _tick_party_audio(dt: float) -> void:
	if dt <= 0.0 or player == null:
		return
	var listener := Vector2(player.position.x, player.position.z)
	if camera_rig != null and camera_rig.cam != null:
		listener = Vector2(camera_rig.cam.global_position.x, camera_rig.cam.global_position.z)
	player.tick_movement_audio(dt, listener)
	for a in ai_parties:
		if a != null and is_instance_valid(a):
			a.tick_movement_audio(dt, listener)

func _update_label_scale() -> void:
	if camera_rig == null:
		return
	var f := clampf(camera_rig.zoom_height / 90.0, 0.85, 4.2)
	# f 只由滚轮缩放（camera_rig.zoom_height）决定，平视时每帧都是同一个值；
	# 而写 Label3D.pixel_size 会标脏并重建字形网格 —— 原来每帧对 33 个标签白写一次，
	# 100 部队规模下就是每帧 100+ 次。量化到 1/64 后早退，稳态开销归零。
	# 同时比较标签数量：将来若在运行中新建部队，标签会立刻被补上缩放，不会被早退漏掉。
	f = snappedf(f, 1.0 / 64.0)
	var n := data.settlements.size() + ai_parties.size() + 1
	if n == _label_count_applied and is_equal_approx(f, _label_scale_applied):
		return
	_label_scale_applied = f
	_label_count_applied = n
	for s in data.settlements:
		if s.label != null:
			s.label.pixel_size = 0.026 * f
	for a in ai_parties:
		if a != null and is_instance_valid(a) and a.label != null:
			a.label.pixel_size = 0.024 * f
	if player.label != null:
		player.label.pixel_size = 0.024 * f

func _check_encounters(delta: float) -> void:
	if not encounters_enabled:
		return
	for k in cooldowns.keys():
		cooldowns[k] = float(cooldowns[k]) - delta
		if float(cooldowns[k]) <= 0.0:
			cooldowns.erase(k)
	for a in ai_parties:
		if a == null or not is_instance_valid(a):
			continue
		if cooldowns.has(a.get_instance_id()):
			continue
		if player.distance_to_party(a) <= config.encounter_distance + 3.0:
			_open_encounter(a)
			return

func _open_encounter(a: AIParty) -> void:
	encounter_party = a
	_time_lock = true          # 对话期间强制暂停，空格不生效
	if player.moving:
		player.halt()          # 遭遇打断行军：部队停在原地
	_eval_time_flow()
	var fname := "无阵营"
	var col := Color(0.9, 0.85, 0.7)
	if a.faction_id >= 0:
		fname = data.faction(a.faction_id).name
		col = data.faction(a.faction_id).color
	var kindname: String = {"lord": "领主部队", "caravan": "商队", "bandit": "强盗团伙"}.get(a.ai_kind(), "部队")
	var lead_line := ""
	if a.boss_title != "":
		lead_line = "敌方首领：%s\n" % a.boss_title
	hud.show_encounter("遭遇 %s" % a.party_name,
		"%s · %s\n%s兵力：%d 人     你的兵力：%d 人\n\n时间已暂停 —— 请决定行动。" % [kindname, fname, lead_line, a.troop_count, player.troop_count],
		col)
	# 视角也冻住：方向键 / 左摇杆同时是 move_*（平移视角）与对话框的选项切换键，
	# 不冻的话「在对话框里按 →」会连带把镜头也拖走。
	_set_camera_active(false)
	# 遭遇提示音（对话框弹出）
	Sfx.play("encounter")

## 相机的输入开关。遭遇框（选项切换复用方向键）与 Boss 战期间都应当关掉地图操作。
func _set_camera_active(v: bool) -> void:
	if camera_rig == null:
		return
	camera_rig.process_mode = Node.PROCESS_MODE_INHERIT if v else Node.PROCESS_MODE_DISABLED

func _on_encounter_choice(action: String) -> void:
	var a := encounter_party
	encounter_party = null
	_time_lock = false
	_set_camera_active(true)   # 对话框已关：把地图操作还给玩家（Boss 战会立刻再关掉）
	if a == null or not is_instance_valid(a):
		_eval_time_flow()
		return
	if action == "attack":
		hud.hide_encounter()
		# 现在所有部队（领主 / 商队 / 强盗）都进入 Boss 战斗场景，打的是各自的头目
		_start_battle(a)
		return
	else:
		print("[撤退] 你避开了 %s 的锋芒，绕道而行。" % a.party_name)
		cooldowns[a.get_instance_id()] = 14.0
		_push_player_away(a.position)
	hud.hide_encounter()
	# 撤退会重新下达行军命令 → 时间随移动流动，抵达后再次暂停
	_eval_time_flow()

func _push_player_away(from: Vector3) -> void:
	var d := Vector2(player.position.x - from.x, player.position.z - from.z)
	if d.length() < 0.1:
		d = Vector2(1, 0)
	d = d.normalized()
	var goal := Vector2(player.position.x, player.position.z) + d * 34.0
	goal.x = clampf(goal.x, 4.0, config.map_size - 4.0)
	goal.y = clampf(goal.y, 4.0, config.map_size - 4.0)
	_order_move(goal)

# =============================================================== 输入
## 键码 → 语义的分发已经搬进 InputRouter（含「遭遇对话框在场时整体让路」）。
## 这里只负责「按下之后改什么」，因此不再出现任何物理键码。
func _on_cycle_speed() -> void:
	speed_index = (speed_index + 1) % speed_steps.size()
	day_night.speed = speed_steps[speed_index]

func _on_toggle_vegetation() -> void:
	vegetation.root.visible = not vegetation.root.visible

func _on_toggle_mute() -> void:
	var muted := Sfx.toggle_mute()
	hud.show_toast("音效 / 音乐：%s（%s 切换）" % [
		"已静音" if muted else "已开启", InputRouter.action_keys_text("toggle_mute")], 2.0)

func _toggle_faction_labels(fid: int) -> void:
	if fid >= data.factions.size():
		return
	var any_visible := false
	for s in data.settlements:
		if s.faction_id == fid and s.label != null:
			s.label.visible = not s.label.visible
			any_visible = any_visible or s.label.visible
	print("[UI] 势力 %s 的定居点标签：%s" % [data.faction(fid).name, "显示" if any_visible else "隐藏"])

func _on_strategic_changed(is_strategic: bool) -> void:
	if vegetation != null and vegetation.root != null:
		vegetation.root.visible = not is_strategic
	# 战略视图里定居点标签再放大一档（配合 _update_label_scale 的缩放）
	if is_strategic:
		print("[视图] 进入战略视图：植被剔除，定居点标签放大")

# =============================================================== 悬停提示
func _update_hover() -> void:
	if camera_rig == null or hud == null:
		return
	var mouse := get_viewport().get_mouse_position()
	if hud.is_encounter_open():
		hud.clear_tooltip()
		return
	var hit := camera_rig.ray_to_terrain(mouse)
	if hit.y < config.sea_level - 1.0:
		hud.clear_tooltip()
		hud.set_terrain_text("海洋 / 不可通行")
		return
	var p := Vector2(hit.x, hit.z)
	# 1) 部队
	for a in ai_parties:
		if a == null or not is_instance_valid(a):
			continue
		if Vector2(a.position.x, a.position.z).distance_to(p) < 7.0:
			var fname := "无阵营（流寇）"
			if a.faction_id >= 0:
				fname = data.faction(a.faction_id).name
			var kindname: String = {"lord": "领主部队", "caravan": "商队", "bandit": "强盗团伙"}.get(a.ai_kind(), "部队")
			var lead: String = ("\n首领：%s" % a.boss_title) if a.boss_title != "" else ""
			var hint: String = {"lord": "\n（可发起 Boss 战 · 最强）", "bandit": "\n（可发起 Boss 战）",
				"caravan": "\n（可发起 Boss 战 · 最弱）"}.get(a.ai_kind(), "")
			hud.show_tooltip("[%s] %s\n阵营：%s\n兵力：%d 人\n状态：%s%s%s" % [
				kindname, a.party_name, fname, a.troop_count,
				"追击中！" if a.chasing else ("行军中" if a.moving else "驻扎"), lead, hint], mouse)
			hud.set_terrain_text(data.nav_fine.describe_at_world(p))
			return
	# 2) 定居点
	for s in data.settlements:
		if s.pos.distance_to(p) < s.radius + 6.0:
			var f := data.faction(s.faction_id)
			var terr := data.faction_at(s.pos.x, s.pos.y)
			hud.show_tooltip("%s\n类型：%s\n势力：%s\n驻军：%d 人\n领地归属：%s" % [
				s.name, s.kind_name(), f.name, s.garrison,
				data.faction(terr).name if terr != 255 else "无主之地"], mouse)
			hud.set_terrain_text(data.nav_fine.describe_at_world(p))
			return
	hud.clear_tooltip()
	hud.set_terrain_text(data.nav_fine.describe_at_world(p))

# =============================================================== Boss 战斗场景（2D 横版）
## 依据遭遇点在大地图上的位置决定战斗背景风格：雪山 / 沙漠 / 草原
func _terrain_kind_at(p: Vector2) -> String:
	var h := data.hm.height_at(p.x, p.y)
	if h >= config.snow_line:
		return "snow"
	if data.gen != null and data.gen.biome_desert.size() > 0:
		var gx := clampi(int(round(p.x / data.hm.cell)), 0, data.hm.res - 1)
		var gz := clampi(int(round(p.y / data.hm.cell)), 0, data.hm.res - 1)
		var i := gz * data.hm.res + gx
		if i >= 0 and i < data.gen.biome_desert.size() and data.gen.biome_desert[i] > 0.45:
			return "desert"
	return "grass"

## 进入 Boss 战：把玩家部队名 / 地形 / Boss 数据传给战斗场景，隐藏大地图
func _start_battle(a: AIParty) -> void:
	if battle != null or a == null or not is_instance_valid(a):
		return
	var p := Vector2(a.position.x, a.position.z)
	var terrain := _terrain_kind_at(p)
	var bcfg := BattleConfig.create()
	var fcol := Color(0.72, 0.22, 0.22)
	if a.faction_id >= 0:
		fcol = data.faction(a.faction_id).color
	# 按敌人类型给不同的 HP / 破防值（商队护卫长最弱，领主最强）
	var kind := a.ai_kind()
	var troops := float(a.troop_count)
	var bhp := 300.0 + troops * 1.10
	var bpoise := 90.0 + troops * 0.22
	match kind:
		"bandit":
			bhp = 130.0 + troops * 2.10
			bpoise = 55.0 + troops * 0.42
		"caravan":
			bhp = 110.0 + troops * 1.70
			bpoise = 48.0 + troops * 0.38
	var payload := {
		"config": bcfg,
		"player_name": "玩家部队 · %d 人" % player.troop_count,
		"player_hp": bcfg.player_max_hp,
		"troops": player.troop_count,
		"terrain": terrain,
		"boss_kind": kind,
		"boss_name": a.boss_title if a.boss_title != "" else a.party_name,
		"boss_hp": bhp,
		"boss_poise": bpoise,
		"faction_color": fcol,
		"player_color": Color(0.70, 0.18, 0.20),
		"seed": config.map_seed * 7 + int(absf(p.x) * 13.0) + int(absf(p.y) * 29.0),
	}
	battle = BattleScene.new()
	add_child(battle)
	battle.setup(payload)
	battle.finished.connect(_on_battle_finished.bind(a))
	_set_overworld_visible(false)
	_time_lock = true          # 战斗中世界时间保持冻结
	game_paused = true
	day_night.paused = true
	if camera_rig != null:
		_set_camera_active(false)   # 战斗中相机不再吃键鼠（BattleScene 自己收输入）
	if router != null:
		router.enabled = false   # 战斗中输入归 BattleScene，别让大地图热键漏进来
	print("[Boss战] 进入战斗：%s（类型 %s）｜ 地形 %s ｜ 敌方兵力 %d ｜ Boss HP %.0f 破防 %.0f" % [
		payload["boss_name"], kind, terrain, a.troop_count, bhp, bpoise])
	# 开战号角（鼓点 + 低音号角），同时把背景音乐切到战斗曲（短淡入，别拖过第一刀）
	Sfx.play("battle_start")
	Bgm.play("battle", audio.bgm_fade_battle)

func _set_overworld_visible(v: bool) -> void:
	var list: Array = [terrain, water, lights_root, camera_rig, player, hud]
	for a in ai_parties:
		list.append(a)
	for n in list:
		if n == null or not is_instance_valid(n):
			continue
		if n is Node3D or n is CanvasItem or n is CanvasLayer:
			n.visible = v

## 战斗结束：胜利 → Boss 部队消失；失败 → 送回最近的城镇并推进半天；撤退 → 原样返回
func _on_battle_finished(result: String, a: AIParty) -> void:
	if battle != null and is_instance_valid(battle):
		battle.queue_free()
	battle = null
	# 回到大地图：战斗曲长淡出，行军主题重新淡入（结算音效还在响，别抢）
	Bgm.play("map", audio.bgm_fade_map)
	_set_overworld_visible(true)
	if camera_rig != null:
		_set_camera_active(true)
	if router != null:
		router.enabled = true
	# 回到大地图：解除强制暂停，交还给时间流动状态机
	# （战败会被送去城镇 → 行军中时间流动；其余情况部队原地待命 → 保持暂停）
	_time_lock = false
	_eval_time_flow()
	if a == null or not is_instance_valid(a):
		return
	var title: String = a.boss_title if a.boss_title != "" else a.party_name
	var p := Vector2(a.position.x, a.position.z)
	if result == "win":
		ai_parties.erase(a)
		a.queue_free()
		var kind2 := a.ai_kind()
		var loot_rate := 0.6
		var loss_rate := 0.12
		var loot_word := "辎重"
		match kind2:
			"caravan":
				loot_rate = 1.15      # 商队货物值钱，但护卫精悍、损失也小
				loss_rate = 0.08
				loot_word = "货物"
			"bandit":
				loot_rate = 0.85
				loss_rate = 0.10
				loot_word = "赃物"
		var spoils := int(round(float(a.troop_count) * loot_rate))
		player.troop_count = maxi(5, player.troop_count - int(a.troop_count * loss_rate))
		player.refresh_label()
		player.label.text = "玩家部队 · %d 人" % player.troop_count
		hud.show_toast("击败了 %s！缴获%s %d" % [title, loot_word, spoils])
		print("[Boss战] 胜利：击败了 %s（%s），缴获%s %d，当前兵力 %d" % [title, kind2, loot_word, spoils, player.troop_count])
	elif result == "lose":
		var town := _nearest_town(p)
		if town != null:
			player.position = Vector3(town.pos.x, data.hm.height_at(town.pos.x, town.pos.y) + 0.4, town.pos.y)
			_order_move(town.pos)
			day_night.time_of_day = fmod(day_night.time_of_day + 0.5, 1.0)
			hud.show_toast("战败…… 你被送回了 %s（时间推进半天）" % town.name)
			print("[Boss战] 战败：被送回 %s，时间推进半天" % town.name)
		cooldowns[a.get_instance_id()] = 30.0
	else:
		hud.show_toast("你撤出了与 %s 的战斗" % title)
		cooldowns[a.get_instance_id()] = 25.0
		_push_player_away(a.position)

## 最近的己方/中立城镇（用于战败回城）
func _nearest_town(p: Vector2) -> Settlement:
	var best: Settlement = null
	var bd := 1e20
	var my_faction := data.faction_at(p.x, p.y)
	for s in data.settlements:
		if s.kind == Settlement.Kind.VILLAGE:
			continue
		if my_faction != 255 and s.faction_id != my_faction:
			continue
		var d := s.pos.distance_squared_to(p)
		if d < bd:
			bd = d
			best = s
	if best == null:
		for s in data.settlements:
			if s.kind == Settlement.Kind.VILLAGE:
				continue
			var d2 := s.pos.distance_squared_to(p)
			if d2 < bd:
				bd = d2
				best = s
	return best
