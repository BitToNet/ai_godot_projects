## =============================================================================
##  WorldGenPipeline —— 从空场景到可玩世界的整条装配流水线
##
##  搬出前这一整段就是 Main._ready() 的前 190 行：程序化生成 7 步 + 表现层装配 +
##  系统接线。逐步用时都要 await 一帧（Loading 界面才刷得动），所以这是一个协程：
##    ctx = await pipeline.run()
##
##  host 契约（Main 是唯一的 host）——run() 结束时这些字段一定已经就位：
##    hud / data / day_night / camera_rig / router / vegetation / player /
##    ai_parties（同一个数组实例）/ fog / view / hover / time / rules /
##    economy / campaign / settlements / ctx / encounters / battler
##
##  只在本文件里活得下去的东西（生成完就没人再看）**不再挂到 host 上**：
##    四份 ShaderMaterial、TerrainManager、WaterBuilder、NightLights 容器、
##    PartySpawner。它们之间最后的关系（day_night.register_shader、
##    fog 的 shader 参数、view.nodes）都在这里一次性接完。
##
##  ⚠ 生成顺序即指纹：这里的 RNG 抽取顺序、await 次数、append 次序一个都不能动，
##    动了 tools/gen_fingerprint.json 的基线就会变红（那正是门禁要拦的事）。
## =============================================================================
class_name WorldGenPipeline
extends RefCounted

var host: Node
var cfg: MapConfig
var audio: AudioConfig

## 生成产物（装配完成后交给 Main / WorldContext）
var hud: HUD
var data: MapData
var day_night: DayNightCycle
var camera_rig: CameraRig
var router: InputRouter
var vegetation: VegetationScatter
var player: PlayerParty
var parties: Array[AIParty] = []      ## 就是 host.ai_parties 那个实例
var fog: FogOfWar
var view: OverworldView
var hover: HoverInspector
var time: TimeFlowController
var rules: EncounterRules
var economy: EconomyRules
var campaign: CampaignState
var settlements: SettlementSystem
var ctx: WorldContext
var encounters: EncounterSystem
var battler: BattleLauncher

## 只在生成期存在的对象
var terrain: TerrainManager
var water: WaterBuilder
var lights_root: Node3D
var spawner: PartySpawner
var terrain_mat: ShaderMaterial
var settlement_mat: ShaderMaterial
var vegetation_mat: ShaderMaterial
var party_mat: ShaderMaterial

## 整条流水线。返回装配好的 WorldContext（同时已写回 host 的公开字段）。
func run() -> WorldContext:
	parties = host.ai_parties
	_build_loading_ui()
	# 与原版一致：先空等两帧让 Loading 界面出来，再进第 0 步
	await host.get_tree().process_frame
	await host.get_tree().process_frame

	# ---------------- 0. 音效（程序化合成，零外部音频文件）----------------
	# 28 个音色共约 16 秒音频，合成耗时约 2 秒；setup 内部按时切片让出帧，
	# Loading 界面不会卡死。不想听可以在 Inspector 里把 AudioConfig.enabled 关掉。
	await _loading("合成音效（程序化 PCM：打击 / 打铁 / 脚步 / 号角）…")
	await Sfx.setup(host, audio)

	data = MapData.new()
	data.cfg = cfg
	data.factions = Faction.build_all()

	# ---------------- 1. 高度场 ----------------
	await _loading("生成地形高度场（多层噪声叠加）…")
	data.gen = HeightmapGenerator.new(cfg)
	data.hm = data.gen.generate()
	await _loading("雕刻河流与湖泊（河道下切 / 渡口）…")

	# ---------------- 2. 定居点选址 ----------------
	await _loading("选择定居点位置并平整地基…")
	var sb := SettlementBuilder.new(cfg, data)
	sb.place_all()

	# ---------------- 3. 寻路栅格 ----------------
	# 分辨率按「目标格距」推导，而不是写死 257 / 129：
	#   细栅格 4 m/格、粗栅格 8 m/格、道路栅格 8 m/格 —— 这三条格距就是 1024 m 图上
	#   257 / 129 / 129 的来历，所以换尺寸前逐位不变（见 tools/map_size_check.gd 的断言）。
	# 4096 m 图上细栅格变成 1025² = 105 万节点（A* 单次搜索随之变贵，见 ROADMAP §12.5 #1）。
	await _loading("构建寻路栅格（海/湖/河不可通行）…")
	data.nav_fine = NavGrid.new(NavGrid.res_for(cfg.map_size, 4.0), cfg.map_size)
	data.nav_fine.build_from(cfg, data.hm, data.gen)
	data.nav_coarse = NavGrid.new(NavGrid.res_for(cfg.map_size, 8.0), cfg.map_size)
	data.nav_coarse.build_from(cfg, data.hm, data.gen)
	data.nav_road = NavGrid.new(NavGrid.res_for(cfg.map_size, 8.0), cfg.map_size)
	data.nav_road.build_from(cfg, data.hm, data.gen, true)
	data.path_fine = Pathfinder.new(data.nav_fine)
	data.path_fine.heuristic_weight = 1.3
	data.path_coarse = Pathfinder.new(data.nav_coarse)
	data.path_coarse.heuristic_weight = 1.6
	# 第六轮 6d 后半：AI 寻路统一走队列（每帧预算）；玩家点击仍走同步 find_path
	# —— 玩家的点击必须立刻有反应，AI 的路可以晚一帧（差的就是「卡顿」与「不掉帧」）
	data.path_queue = PathQueue.new()

	# ---------------- 4. 道路 ----------------
	await _loading("铺设道路网（A* 修路 + 架桥）…")
	var rn := RoadNetwork.new(cfg, data)
	rn.build()

	# ---------------- 5. 烘焙贴图 ----------------
	await _loading("烘焙地表混合图 / 小地图 / 高度图…")
	var baker := MapTextureBaker.new(cfg, data)
	baker.bake_all()

	# ---------------- 6. 材质与网格 ----------------
	await _loading("生成着色器与地形分块网格…")
	_make_materials()
	# 部队生成器在这里就位：地形要拿玩家出生点（王都旁），部队也在同一步之后落地
	spawner = PartySpawner.new()
	spawner.cfg = cfg
	spawner.data = data
	spawner.host = host
	spawner.mat = party_mat
	spawner.parties = parties
	terrain = TerrainManager.new()
	terrain.name = "Terrain"
	host.add_child(terrain)
	terrain.setup(cfg, data, terrain_mat, spawner.player_start())

	await _loading("注入海洋 / 湖泊 / 河流水面…")
	water = WaterBuilder.new()
	water.name = "Water"
	host.add_child(water)
	water.setup(cfg, data)

	await _loading("建造城堡 / 城镇 / 村庄…")
	lights_root = Node3D.new()
	lights_root.name = "NightLights"
	host.add_child(lights_root)
	sb.build_all(host, settlement_mat, null)
	rn.build_bridges(host, settlement_mat)
	_build_settlement_lights()

	await _loading("播种植被（MultiMesh 批处理）…")
	vegetation = VegetationScatter.new()
	vegetation.cfg = cfg
	vegetation.data = data
	vegetation.build(host, vegetation_mat)

	# ---------------- 7. 部队 / 相机 / 迷雾 / UI ----------------
	await _loading("集结部队…")
	player = spawner.spawn_player()
	spawner.player_target = player    # 强盗追击的目标（typed 注入，替掉 data.set_meta("player_ref")）
	spawner.spawn_ai_parties()

	await _loading("设置相机与环境…")
	day_night = DayNightCycle.new()
	day_night.name = "DayNight"
	host.add_child(day_night)
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
	host.add_child(camera_rig)
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

	# 第四轮：战役经济。状态本体（钱袋 / 补给 / 士气 / 声望）只在这里建一次；
	# 必须早于 _setup_ui()，因为 HUD 要在绑定阶段拿到它来显示钱袋 / 粮 / 士气。
	# 换日结算挂在 day_changed 上 —— 时间流速 / 暂停 / Boss 战锁时间全都自动正确，
	# 不需要在 _process 里再判一次「今天结过没有」。
	# 注意：这里只做纯算术与信号接线，既不抽 RNG 也不 await，生成指纹不受影响。
	economy = EconomyRules.create()
	campaign = CampaignState.new()
	campaign.setup(economy, player)
	day_night.day_changed.connect(campaign.on_day_changed)
	campaign.day_settled.connect(Callable(host, "_on_day_settled"))

	_setup_ui()

	# 表现层助手：标签缩放 / 大地图整体显隐 / 悬停提示。
	# 放在这里是因为它们都要等相机、植被、部队、HUD 全部就位。
	view = OverworldView.new()
	view.camera_rig = camera_rig
	view.data = data
	view.parties = parties
	view.player = player
	view.vegetation = vegetation
	# view.nodes 持有这几样：战斗结束 view.set_visible(true) 还得靠它们把大地图放回来
	view.nodes = [terrain, water, lights_root, camera_rig, player, hud]
	camera_rig.strategic_changed.connect(view.on_strategic_changed)

	hover = HoverInspector.new()
	hover.host = host
	hover.camera_rig = camera_rig
	hover.hud = hud
	hover.data = data
	hover.cfg = cfg
	hover.parties = parties

	# 共享上下文 + 两个系统（遭遇 / Boss 战）。它们互相回调，用信号断开环：
	#   玩家选「攻击」→ encounters.attack_requested → battler.start
	#   战斗结束        → battler.finished         → encounters.on_battle_finished（结算）
	# 必须放在 view 组装之后：Boss 战进场要 view.set_visible(false)。
	var ctx := WorldContext.new()
	ctx.host = host as Node3D
	ctx.cfg = cfg
	ctx.audio = audio
	ctx.data = data
	ctx.hud = hud
	ctx.camera = camera_rig
	ctx.router = router
	ctx.time = time
	ctx.rules = rules
	ctx.view = view
	ctx.day_night = day_night
	ctx.player = player
	ctx.parties = parties

	# 第四轮：把经济状态交给共享上下文（encounters 结算战利品 / 城镇菜单花钱都要它）
	ctx.economy = economy
	ctx.campaign = campaign

	encounters = EncounterSystem.new()
	encounters.ctx = ctx
	battler = BattleLauncher.new()
	battler.ctx = ctx
	hud.encounter_choice.connect(encounters.resolve)
	encounters.attack_requested.connect(battler.start)
	battler.finished.connect(encounters.on_battle_finished)

	# 第四轮：进城办事（补给 / 招募 / 贸易 / 驻军）。
	# 每个定居点的繁荣度 / 志愿者池 / 货物本地价差在这里一次性定下来 ——
	# assign_environment 走 cfg.make_rng("settlement_economy") 这条**独立随机流**，
	# 既不消耗主生成流的抽取次数，也不改生成顺序 ⇒ 生成指纹不变。
	# 志愿者回流同样挂 day_changed（与日结共用一个权威换日信号）。
	#
	# ⚠ 刻意**不写** ctx.settlements：本系统已经有 settlements.ctx 这个引用，
	#    再加一条反向引用就构成 RefCounted 引用环（两个对象互持，引用计数永远不归零），
	#    表现为进程退出时 "N resources still in use at exit" + 纹理 RID 泄漏
	#    —— 门禁里所有建世界的步骤都会因此变红（实测 6 步）。需要它的地方
	#    （Main / 工具脚本）直接拿 pipeline.settlements。
	settlements = SettlementSystem.new()
	settlements.ctx = ctx
	# 繁荣度 / 志愿者池 / 每种货的本地价差：生成期一次性定下来（幂等，同种子同结果）
	SettlementSystem.assign_environment(cfg, data, economy)
	report_settlement_env()
	day_night.day_changed.connect(settlements.on_day_changed)
	# 4b-2：进城菜单接线。菜单是数据驱动的 —— HUD 只把条目画出来，
	# 「能不能点 / 为什么不能点」由 menu_entries() 给，点了什么由 resolve() 解释。
	# 面板何时关也由业务层决定（resolve("leave") → closed → HUD 收起）：
	# 买完补给还要接着招兵，不能一点就关。
	hud.settlement_action.connect(settlements.resolve)
	settlements.opened.connect(Callable(host, "_on_settlement_opened"))
	settlements.menu_changed.connect(Callable(host, "_on_settlement_menu_changed"))
	settlements.closed.connect(Callable(host, "_on_settlement_closed"))
	router.interact_requested.connect(Callable(host, "_on_interact_requested"))
	# 4d：快速存档 / 快速读档（数据格式与校验在 SaveGame.gd，这里只接线）
	router.save_requested.connect(Callable(host, "_on_quicksave_requested"))
	router.load_requested.connect(Callable(host, "_on_quickload_requested"))
	return ctx

# =============================================================== 内部
## 打印一句定居点环境概览：让「繁荣度 / 志愿者池真的被赋值了」在门禁日志里看得见。
## 光靠 settlement_check 只能证明函数本身对，证明不了生成期确实调用了它。
func report_settlement_env() -> void:
	var lo := 100
	var hi := 0
	var vol := 0
	for s in data.settlements:
		lo = mini(lo, s.prosperity)
		hi = maxi(hi, s.prosperity)
		vol += s.volunteers
	print("[Warband] 定居点环境：%d 个   繁荣度 %d..%d   志愿者池 %d 人   货物 %d 种" % [
		data.settlements.size(), lo, hi, vol, economy.good_count()])

## 推进一步并让 Loading 界面刷新两帧（顺序 / 次数即指纹，别合并）
func _loading(text: String) -> void:
	if hud != null:
		hud.set_loading(text)
	await host.get_tree().process_frame
	await host.get_tree().process_frame

func _build_loading_ui() -> void:
	hud = HUD.new()
	hud.name = "HUD"
	host.add_child(hud)
	hud.setup(cfg)

func _make_materials() -> void:
	var mf := MaterialFactory.new()
	mf.build(cfg, data)
	terrain_mat = mf.terrain
	settlement_mat = mf.settlement
	party_mat = mf.party
	vegetation_mat = mf.vegetation

## 夜里给城堡 / 城镇点灯（村庄不点）
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
	hud.bind_campaign(campaign)
	hud.minimap.setup(data, player, parties, fog)
	hud.set_terrain_text("草原 (1.0x)")

	# 输入路由：键码 → 语义信号。键位表在 project.godot 的 [input] 段，
	# 这里不再出现任何 KEY_* 常量，加手柄 / 改键位都不用动代码。
	router = InputRouter.new()
	router.name = "InputRouter"
	host.add_child(router)
	router.camera_rig = camera_rig
	router.hud = hud
	router.cfg = cfg
	router.order_move.connect(time.order_move)
	router.cycle_speed_requested.connect(time.cycle_speed)
	# 这三个回调仍然住在 Main（它们只改 Main 自己的字段），跨脚本用 Callable 取
	router.toggle_vegetation_requested.connect(Callable(host, "_on_toggle_vegetation"))
	router.toggle_mute_requested.connect(Callable(host, "_on_toggle_mute"))
	router.faction_labels_requested.connect(Callable(host, "_toggle_faction_labels"))
