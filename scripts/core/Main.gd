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
##  时间流动（骑砍式的「暂停」）由 TimeFlowController 统一裁决：
##    · 点击地图 → 部队开始行军，行军期间世界时间自动流动；
##      走到目的地的瞬间，世界时间立刻暂停。
##    · 行军途中按空格 → 行军立刻中断，世界时间暂停。
##    · 部队停下后长按空格 → 世界时间才开始流动（松开立刻恢复暂停）。
##    · 遭遇对话 / Boss 战期间强制暂停（time.lock()）。
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
var spawner: PartySpawner                  ## 开局摆部队（见 PartySpawner.gd）
var view: OverworldView                    ## 标签缩放 / 大地图显隐（见 OverworldView.gd）
var hover: HoverInspector                  ## 悬停提示（见 HoverInspector.gd）
var fog: FogOfWar
var lights_root: Node3D

var terrain_mat: ShaderMaterial
var settlement_mat: ShaderMaterial
var vegetation_mat: ShaderMaterial
var party_mat: ShaderMaterial

## 时间流动状态机（骑砍式：部队停下，时间也停下）搬到了 TimeFlowController，
## 这里只留一个引用；遭遇 / Boss 战用它 lock()，行军命令走 time.order_move()。
var time: TimeFlowController
var rules: EncounterRules            ## 遭遇 / Boss 战数值（见 EncounterRules.gd）

var encounter_party: AIParty = null
var battle: BattleScene = null        ## 正在进行的 2D Boss 战（null = 在大地图上）
var encounters_enabled: bool = true   ## 调试/截图时可关掉遭遇UI
var cooldowns: Dictionary = {}
var _gen_ms: int = 0
## 程序化生成**彻底**结束（含收尾的两帧与 0.35 s 遮罩收场）后置 true。
## 工具脚本（tools/gen_fingerprint.gd、tools/perf_probe.gd）靠它判断何时可以安全取指纹 / 释放场景，
## 不要改用 _gen_ms：那个值在收尾协程还在 await 时就已置位，此时 free() 会报
## 「Resumed function '_step()' after await, but class instance is gone」。
var gen_done: bool = false

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
	# 部队生成器在这里就位：地形要拿玩家出生点（王都旁），部队也在同一步之后落地
	spawner = PartySpawner.new()
	spawner.cfg = cfg
	spawner.data = data
	spawner.host = self
	spawner.mat = party_mat
	spawner.parties = ai_parties
	terrain = TerrainManager.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(cfg, data, terrain_mat, spawner.player_start())

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
	player = spawner.spawn_player()
	spawner.player_target = player    # 强盗追击的目标（typed 注入，替掉 data.set_meta("player_ref")）
	spawner.spawn_ai_parties()

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

	# 时间流动状态机与遭遇数值表：必须早于 _setup_ui()，
	# 因为输入路由会把「点地行军 / 切换流速」直接接到这两个对象上。
	time = TimeFlowController.new()
	time.player = player
	time.day_night = day_night
	rules = EncounterRules.create()
	_setup_ui()

	# 表现层助手：标签缩放 / 大地图整体显隐 / 悬停提示。
	# 放在这里是因为它们都要等相机、植被、部队、HUD 全部就位。
	view = OverworldView.new()
	view.camera_rig = camera_rig
	view.data = data
	view.parties = ai_parties
	view.player = player
	view.vegetation = vegetation
	view.nodes = [terrain, water, lights_root, camera_rig, player, hud]
	camera_rig.strategic_changed.connect(view.on_strategic_changed)

	hover = HoverInspector.new()
	hover.host = self
	hover.camera_rig = camera_rig
	hover.hud = hud
	hover.data = data
	hover.cfg = cfg
	hover.parties = ai_parties

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

func _build_loading_ui() -> void:
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(config)

func _make_materials() -> void:
	var mf := MaterialFactory.new()
	mf.build(config, data)
	terrain_mat = mf.terrain
	settlement_mat = mf.settlement
	party_mat = mf.party
	vegetation_mat = mf.vegetation

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
	router.order_move.connect(time.order_move)
	router.cycle_speed_requested.connect(time.cycle_speed)
	router.toggle_vegetation_requested.connect(_on_toggle_vegetation)
	router.toggle_mute_requested.connect(_on_toggle_mute)
	router.faction_labels_requested.connect(_toggle_faction_labels)

# =============================================================== 时间流动
## 状态机本体在 TimeFlowController（含「长按空格 / 遭遇锁定」四条规则），
## 这里只保留调用点，见 time.evaluate() / time.order_move() / time.lock()。

# =============================================================== 循环
func _process(delta: float) -> void:
	# view / hover 是生成流程最后才组装的（要等相机、植被、部队、HUD 全部就位），
	# 在那之前 _process 已经在跑（_ready 里全是 await），所以这里必须一起判空。
	if data == null or player == null or view == null:
		return
	# 0) 背景音乐的淡入淡出必须在战斗早退之前推进，否则战斗中永远切不过去
	Bgm.tick(delta)
	if battle != null:
		return
	# 1) 先判定本帧时间是否流动（行军 / 长按空格 / 强制锁）
	time.evaluate()
	var dt := 0.0 if time.game_paused else delta
	# 2) 玩家先走：抵达的那一帧立刻冻结世界，AI / 遭遇 / 昼夜都不再推进
	player.step(dt)
	if not player.moving:
		time.evaluate()
		dt = 0.0 if time.game_paused else delta
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
	if not time.game_paused:
		_check_encounters(delta)
	view.update_label_scale()
	hover.tick(delta)

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
	if player.moving:
		player.halt()          # 遭遇打断行军：部队停在原地
	time.lock()                # 对话期间强制暂停，空格不生效
	var fname := GameState.faction_name(data, a.faction_id)
	var col := Color(0.9, 0.85, 0.7)
	if a.faction_id >= 0:
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
	_set_camera_active(true)   # 对话框已关：把地图操作还给玩家（Boss 战会立刻再关掉）
	if a == null or not is_instance_valid(a):
		time.unlock()
		return
	if action == "attack":
		hud.hide_encounter()
		# 现在所有部队（领主 / 商队 / 强盗）都进入 Boss 战斗场景，打的是各自的头目
		_start_battle(a)
		return
	else:
		print("[撤退] 你避开了 %s 的锋芒，绕道而行。" % a.party_name)
		cooldowns[a.get_instance_id()] = rules.retreat_cooldown
		_push_player_away(a.position)
	hud.hide_encounter()
	# 撤退会重新下达行军命令 → 时间随移动流动，抵达后再次暂停
	time.evaluate()

func _push_player_away(from: Vector3) -> void:
	var d := Vector2(player.position.x - from.x, player.position.z - from.z)
	if d.length() < 0.1:
		d = Vector2(1, 0)
	d = d.normalized()
	var goal := Vector2(player.position.x, player.position.z) + d * rules.push_away_distance
	var m := rules.push_away_margin
	goal.x = clampf(goal.x, m, config.map_size - m)
	goal.y = clampf(goal.y, m, config.map_size - m)
	time.order_move(goal)

# =============================================================== 输入
## 键码 → 语义的分发已经搬进 InputRouter（含「遭遇对话框在场时整体让路」）。
## 这里只负责「按下之后改什么」，因此不再出现任何物理键码。
## 注意：点地行军 / 切换时间流速直接接到了 TimeFlowController（见 _setup_ui），
## 不经过 Main。
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
	# 按敌人类型给不同的 HP / 破防值（商队护卫长最弱，领主最强）—— 公式在 EncounterRules
	var kind := a.ai_kind()
	var bhp := rules.boss_hp(kind, a.troop_count)
	var bpoise := rules.boss_poise(kind, a.troop_count)
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
	view.set_visible(false)
	time.lock()                # 战斗中世界时间保持冻结（空格无效）
	if camera_rig != null:
		_set_camera_active(false)   # 战斗中相机不再吃键鼠（BattleScene 自己收输入）
	if router != null:
		router.enabled = false   # 战斗中输入归 BattleScene，别让大地图热键漏进来
	print("[Boss战] 进入战斗：%s（类型 %s）｜ 地形 %s ｜ 敌方兵力 %d ｜ Boss HP %.0f 破防 %.0f" % [
		payload["boss_name"], kind, terrain, a.troop_count, bhp, bpoise])
	# 开战号角（鼓点 + 低音号角），同时把背景音乐切到战斗曲（短淡入，别拖过第一刀）
	Sfx.play("battle_start")
	Bgm.play("battle", audio.bgm_fade_battle)

## 战斗结束：胜利 → Boss 部队消失；失败 → 送回最近的城镇并推进半天；撤退 → 原样返回
func _on_battle_finished(result: String, a: AIParty) -> void:
	if battle != null and is_instance_valid(battle):
		battle.queue_free()
	battle = null
	# 回到大地图：战斗曲长淡出，行军主题重新淡入（结算音效还在响，别抢）
	Bgm.play("map", audio.bgm_fade_map)
	view.set_visible(true)
	if camera_rig != null:
		_set_camera_active(true)
	if router != null:
		router.enabled = true
	# 回到大地图：解除强制暂停，交还给时间流动状态机
	# （战败会被送去城镇 → 行军中时间流动；其余情况部队原地待命 → 保持暂停）
	time.unlock()
	if a == null or not is_instance_valid(a):
		return
	var title: String = a.boss_title if a.boss_title != "" else a.party_name
	var p := Vector2(a.position.x, a.position.z)
	if result == "win":
		ai_parties.erase(a)
		a.queue_free()
		var kind2 := a.ai_kind()
		# 战利品与损失率都在 EncounterRules 里（商队货物值钱，但护卫精悍、损失也小）
		var spoils := int(round(float(a.troop_count) * rules.loot_rate(kind2)))
		var loss := int(a.troop_count * rules.loss_rate(kind2))
		var loot_word := rules.loot_word(kind2)
		player.troop_count = maxi(5, player.troop_count - loss)
		player.refresh_label()
		player.label.text = "玩家部队 · %d 人" % player.troop_count
		hud.show_toast("击败了 %s！缴获%s %d" % [title, loot_word, spoils])
		print("[Boss战] 胜利：击败了 %s（%s），缴获%s %d，当前兵力 %d" % [title, kind2, loot_word, spoils, player.troop_count])
	elif result == "lose":
		var town := _nearest_town(p)
		if town != null:
			player.position = Vector3(town.pos.x, data.hm.height_at(town.pos.x, town.pos.y) + 0.4, town.pos.y)
			time.order_move(town.pos)
			day_night.time_of_day = fmod(day_night.time_of_day + 0.5, 1.0)
			hud.show_toast("战败…… 你被送回了 %s（时间推进半天）" % town.name)
			print("[Boss战] 战败：被送回 %s，时间推进半天" % town.name)
		cooldowns[a.get_instance_id()] = rules.defeat_cooldown
	else:
		hud.show_toast("你撤出了与 %s 的战斗" % title)
		cooldowns[a.get_instance_id()] = rules.battle_retreat_cooldown
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
