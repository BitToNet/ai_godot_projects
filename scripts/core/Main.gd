## =============================================================================
##  Main —— 场景总装与游戏循环
##
##  这里是「场景的门面」：字段就是对外接口（tools/ 下的自检脚本、各系统都按这些
##  名字取用），逻辑都在别的文件里：
##    · WorldGenPipeline   : 生成 7 步（高度场 → 定居点 → 栅格 → 道路 → 贴图 →
##                           材质网格 → 部队/相机/迷雾/UI）+ 表现层与系统接线
##    · TimeFlowController : 骑砍式「时间流动 / 暂停」状态机
##    · EncounterSystem    : 遭遇检测、对话框、冷却、退避、战后结算
##    · SettlementSystem   : 进城办事（补给 / 招募 / 贸易 / 驻军）
##    · SelectionSystem    : 点地图上的单位 → 选中（前往 / 进入 / 追踪）
##    · BattleLauncher     : 进出 2D Boss 战
##    · EncounterRules     : 遭遇与 Boss 战的全部数值
##    · WorldContext       : 上面几块共享的世界句柄
##    · PartySpawner / MaterialFactory / OverworldView / HoverInspector / GameState
##
##  Main 自己只剩三件事：装配、每帧循环（_process）、以及几个改自身字段的 UI 回调。
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
var vegetation: VegetationScatter
var player: PlayerParty
var ai_parties: Array[AIParty] = []
var fog: FogOfWar
var view: OverworldView                    ## 标签缩放 / 大地图显隐（见 OverworldView.gd）
var hover: HoverInspector                  ## 悬停提示（见 HoverInspector.gd）

## 时间流动状态机（骑砍式：部队停下，时间也停下）搬到了 TimeFlowController，
## 这里只留一个引用；遭遇 / Boss 战用它 lock()，行军命令走 time.order_move()。
var time: TimeFlowController
var rules: EncounterRules            ## 遭遇 / Boss 战数值（见 EncounterRules.gd）
var economy: EconomyRules            ## 经济与军费数值表（见 EconomyRules.gd）
var campaign: CampaignState          ## 钱袋 / 补给 / 士气 / 声望 / 兵员档次（见 CampaignState.gd）
var ctx: WorldContext                ## 各系统共享的世界句柄（见 WorldContext.gd）
var encounters: EncounterSystem      ## 遭遇检测 / 对话 / 冷却（见 EncounterSystem.gd）
var settlements: SettlementSystem    ## 进城办事：补给 / 招募 / 贸易 / 驻军（见 SettlementSystem.gd）
var battler: BattleLauncher          ## 进出 Boss 战（见 BattleLauncher.gd）
var pipeline: WorldGenPipeline       ## 生成流水线（生成完仍然留着，方便回头查产物）
var picker: MapPicker                ## 屏幕空间拾取（见 MapPicker.gd）
var selection: SelectionSystem       ## 当前选中了谁（见 SelectionSystem.gd）

## 「先过去，抵达后自动进城」的目标。存的是**意图**而不是坐标：
## 抵达那一帧要按 id 重新拿定居点（这中间它可能已经被战乱换手 / 被读档重建）。
var _travel_target: Settlement = null
## 「追踪」的目标部队与最近一次已下达的目标点（见 _tick_tracking）
var _track_target: AIParty = null
var _track_goal: Vector2 = Vector2.ZERO
var _track_timer: float = 0.0
## 追踪的重寻路节流：目标每移动这么多米才重新寻路一次，且两次之间至少隔这么久。
## 玩家寻路走的是同步 A*（path_fine），不节流等于每帧一次全图搜索。
const TRACK_REPATH_S := 2.0
const TRACK_REPATH_M := 30.0

var _gen_ms: int = 0
## 程序化生成**彻底**结束（含收尾的两帧与 0.35 s 遮罩收场）后置 true。
## 工具脚本（tools/gen_fingerprint.gd、tools/perf_probe.gd）靠它判断何时可以安全取指纹 / 释放场景，
## 不要改用 _gen_ms：那个值在收尾协程还在 await 时就已置位，此时 free() 会报
## 「Resumed function '_step()' after await, but class instance is gone」。
var gen_done: bool = false

func _ready() -> void:
	# 分级日志：级别来自 -- --log-level=debug 或环境变量 WARBAND_LOG（默认 info）
	Log.setup(OS.get_cmdline_user_args())
	var t0 := Time.get_ticks_msec()
	if config == null:
		config = MapConfig.new()
	if audio == null:
		audio = AudioConfig.new()
	get_window().theme = UiTheme.theme()

	# 整条装配流水线都在 WorldGenPipeline 里（生成 7 步 + 表现层 + 系统接线）。
	# 它是一个协程：await 期间每一步都会让出帧，Loading 界面才刷得动。
	pipeline = WorldGenPipeline.new()
	pipeline.host = self
	pipeline.cfg = config
	pipeline.audio = audio
	ctx = await pipeline.run()

	# 把产物挂到自己身上 —— 这些字段就是场景的对外接口，改名会牵动 tools/ 与各系统
	data = pipeline.data
	hud = pipeline.hud
	player = pipeline.player
	ai_parties = pipeline.parties
	day_night = pipeline.day_night
	camera_rig = pipeline.camera_rig
	router = pipeline.router
	vegetation = pipeline.vegetation
	fog = pipeline.fog
	view = pipeline.view
	hover = pipeline.hover
	time = pipeline.time
	rules = pipeline.rules
	economy = pipeline.economy
	campaign = pipeline.campaign
	encounters = pipeline.encounters
	settlements = pipeline.settlements
	battler = pipeline.battler
	picker = pipeline.picker
	selection = pipeline.selection

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
	print("[音频] 背景音乐就绪：当前 %s（音量 %.1f dB，缺失音频时自动静音）" % [
		Bgm.current(), audio.bgm_db])

## 收尾用：更新 Loading 文字并让出两帧
func _step(text: String) -> void:
	if hud != null:
		hud.set_loading(text)
	await get_tree().process_frame
	await get_tree().process_frame
# =============================================================== 时间流动
## 状态机本体在 TimeFlowController（含「长按空格 / 遭遇锁定」四条规则），
## 这里只保留调用点，见 time.evaluate() / time.order_move() / time.lock()。

# =============================================================== 循环
## 每帧给寻路队列的预算（微秒）：16.6 ms 的一帧里约占 12%。
## 见 PathQueue —— 预算比单个请求还小时「每帧至少完成一个」，所以队列不会卡死。
const PATH_BUDGET_US := 2000

func _process(delta: float) -> void:
	# view / hover / encounters / battler 都是生成流程最后才组装的（要等相机、植被、
	# 部队、HUD 全部就位），在那之前 _process 已经在跑（_ready 里全是 await），
	# 所以这里必须一起判空。
	if data == null or player == null or view == null or encounters == null or battler == null:
		return
	if settlements == null:
		return
	# 0) 背景音乐的淡入淡出必须在战斗早退之前推进，否则战斗中永远切不过去
	Bgm.tick(delta)
	if battler.battle != null:
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
	# 寻路请求队列：本帧 AI 刚提交的请求在这里立刻结算（每帧预算，见 PathQueue）。
	# 放在 AI step 之后 = 同一帧内完成，低负载下与旧的同步寻路几乎没有差别。
	if data.path_queue != null:
		data.path_queue.pump(PATH_BUDGET_US)
	# 追踪（第七轮）：目标部队走远了就重新下达目标点。放在 AI step 之后 ——
	# 用的是本帧刚更新过的位置，不会追着一帧前的位置跑。
	_tick_tracking(delta)
	# 选中目标的失效检查（被选中的部队可能刚被打没）
	if selection != null:
		selection.tick()
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
		encounters.check(delta)
	view.update_label_scale()
	hover.tick(delta)
	# 站在定居点旁边时提示一次交互键（系统内部 0.5 s 节流 + 只在目标变化时弹；
	# 提示条不发声音，sfx 联调断言的是精确播放次数）
	settlements.tick(delta)

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

## 遭遇检测 / 对话框 / 冷却 / 退避都在 EncounterSystem 里（见 EncounterSystem.gd），
## 进出 Boss 战在 BattleLauncher 里，两者的接线在 _ready 末尾。

# =============================================================== 换日结算
## 换日结算的回调（WorldGenPipeline 把 campaign.day_settled 接到这里）。
## 数值本身已经在 CampaignState 里落地了，这里只负责「把报告说出来」：
## 平时只 print，出事了（断粮 / 欠薪 / 逃兵）才弹提示条，免得每 2 分钟刷一次屏。
## 注意：这里**不播任何音效** —— 门禁的 sfx_* 自检在数音效触发次数，
## 加一声「金币」就会让那些断言失效（要加得连自检一起改，别偷偷加）。
func _on_day_settled(report: Dictionary) -> void:
	var day := int(report.get("day", 0))
	var troops := int(report.get("troops", 0))
	var supplies := int(report.get("supplies", 0))
	var morale := int(report.get("morale", 0))
	var deserted := int(report.get("deserted", 0))
	var week: Dictionary = report.get("week", {})
	Log.info("[日结] 第 %d 天：兵力 %d，粮 %d（吃 %d），士气 %d，钱 %d" % [
		day, troops, supplies, int(report.get("eaten", 0)), morale, int(report.get("denars", 0))])

	var notices: Array[String] = []
	if bool(report.get("starving", false)):
		notices.append("❗粮草耗尽，士气 −%d（去城镇/村庄补给）" % campaign.rules.starve_penalty)
	if not week.is_empty():
		var wage := int(week.get("wage", 0))
		var paid := int(week.get("paid", 0))
		if int(week.get("short", 0)) > 0:
			notices.append("❗军费不足：周薪 %d，只付了 %d（欠薪 %d 周）" % [
				wage, paid, int(week.get("debt_weeks", 0))])
			Log.warn("[周结] 军费不足：应发 %d，实发 %d，欠薪 %d 周" % [
				wage, paid, int(week.get("debt_weeks", 0))])
		else:
			notices.append("💰 发了本周军费 %d 金" % paid)
			Log.info("[周结] 军费已发：%d 金" % paid)
	if deserted > 0:
		notices.append("❗%d 名士兵因士气崩溃离队" % deserted)
	if not notices.is_empty() and hud != null:
		hud.show_toast("　".join(notices), 6.0)

# =============================================================== 存档 / 读档
## 快速存档 / 快速读档（第四轮 4d）。数据格式与校验全在 SaveGame.gd，这里只管
## 「什么时候允许、说给玩家听的话」。允许的条件写得很紧：
##   · 地图上（不在 Boss 战里；战斗中 router 本来也被关掉了，这里再兜一层）
##   · 没有面板开着（面板状态不进存档 —— 存下来读回去会得到「面板开着但对象换了」的错位）
func _blocked_reason() -> String:
	if battler != null and battler.battle != null:
		return "战斗进行中"
	if hud != null and hud.is_any_dialog_open():
		return "有面板开着（先关掉它：面板状态不进存档）"
	return ""

func _on_quicksave_requested() -> void:
	if ctx == null or campaign == null:
		return
	var why := _blocked_reason()
	if why != "":
		if hud != null:
			hud.show_toast("现在不能存档：%s" % why, 3.0)
		return
	var r := SaveGame.write(SaveGame.SLOT_QUICK, SaveGame.collect(ctx, encounters))
	if bool(r.get("ok", false)):
		print("[存档] 已写入 %s（%d 字节）：%s" % [
			str(r.get("path", "")), int(r.get("bytes", 0)), campaign.debug_line()])
		if hud != null:
			hud.show_toast("已存档：第 %d 天　金 %d　兵 %d　（%s 可再按一次覆盖）" % [
				campaign.day, campaign.denars, campaign.troops(),
				InputRouter.action_hint_text("quicksave")], 4.0)
	else:
		Log.warn("[存档] 失败：%s" % str(r.get("error", "")))
		if hud != null:
			hud.show_toast("存档失败：%s" % str(r.get("error", "")), 4.0)

func _on_quickload_requested() -> void:
	if ctx == null or campaign == null:
		return
	var why := _blocked_reason()
	if why != "":
		if hud != null:
			hud.show_toast("现在不能读档：%s" % why, 3.0)
		return
	if not SaveGame.exists(SaveGame.SLOT_QUICK):
		if hud != null:
			hud.show_toast("没有存档 —— 先按 %s 存一个" % InputRouter.action_hint_text("quicksave"), 3.0)
		return
	var r := SaveGame.read(SaveGame.SLOT_QUICK)
	if not bool(r.get("ok", false)):
		if hud != null:
			hud.show_toast("读档失败：%s" % str(r.get("error", "")), 4.5)
		return
	var a := SaveGame.apply(ctx, r.get("data", {}), encounters, settlements)
	if not bool(a.get("ok", false)):
		Log.warn("[读档] 拒绝：%s" % str(a.get("error", "")))
		if hud != null:
			hud.show_toast("读档被拒绝：%s" % str(a.get("error", "")), 5.0)
		return
	var info: Dictionary = a.get("info", {})
	# 读档把整份世界状态换了一遍：位置 / 兵力 / 生死都可能与存档前不同，
	# 于是「先过去后进城」与「追踪」这两个挂着的意图一并作废（它们记的是旧位置），
	# 而选中面板原地刷新一次 —— 面板上的距离是 select 那一刻算的，不刷新就是旧值。
	_travel_target = null
	_track_target = null
	if selection != null:
		selection.refresh()
	# 迷雾要在这里揭（WorldContext 里没有 fog 这一项，也没必要为读档加一条引用）
	if fog != null and player != null:
		fog.reveal(Vector2(player.position.x, player.position.z), config.fog_reveal_radius_m() * 1.4)
	var warns: Array = a.get("warnings", [])
	print("[读档] 已载入第 %d 天：金 %d　粮 %d　士气 %d　兵 %d　部队 %d 支（打掉的 %d 支保持消失）%s" % [
		int(info.get("day", 0)), int(info.get("denars", 0)), int(info.get("supplies", 0)),
		int(info.get("morale", 0)), int(info.get("troops", 0)), int(info.get("parties", 0)),
		int(info.get("parties_gone", 0)),
		"" if warns.is_empty() else "　⚠ 修掉 %d 处坏数据" % warns.size()])
	if hud != null:
		var tail := "" if warns.is_empty() else "（修掉 %d 处坏数据）" % warns.size()
		hud.show_toast("已读档：第 %d 天　金 %d　兵 %d%s" % [
			int(info.get("day", 0)), int(info.get("denars", 0)), int(info.get("troops", 0)), tail], 4.0)
# =============================================================== 输入
## 键码 → 语义的分发已经搬进 InputRouter（含「遭遇对话框在场时整体让路」）。
## 这里只负责「按下之后改什么」，因此不再出现任何物理键码。
## 注意：点地行军 / 切换时间流速直接接到了 TimeFlowController（见 WorldGenPipeline._setup_ui），
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
	Log.debug("[UI] 势力 %s 的定居点标签：%s" % [data.faction(fid).name, "显示" if any_visible else "隐藏"])

# =============================================================== 点单位交互
## 左键点到了地图上的实体（InputRouter.pick_requested）。
## 两条规则，都是骑砍的手感：
##   · 定居点：**第一次点 = 选中**（看名字 / 类型 / 繁荣度 / 驻军 / 距离），
##     **再点一次同一座 = 进城**。这样「想看详情」与「想进去」不会互相误触。
##   · 部队：点一下即选中（面板上有「追踪」）。
## 点空地不会走到这里 —— 那是 order_move 那条路（见 _on_order_move）。
func _on_pick_requested(screen_pos: Vector2) -> void:
	if picker == null or selection == null:
		return
	var hit := picker.pick(screen_pos)
	if hit.is_empty():
		return
	var kind := String(hit.get("kind", ""))
	if kind == MapPicker.KIND_SETTLEMENT:
		var s: Settlement = hit.get("settlement")
		if s == null:
			return
		if selection.is_settlement(s):
			_enter_settlement(s)
			return
		_track_target = null
		selection.select_settlement(s)
	elif kind == MapPicker.KIND_PARTY:
		var a: AIParty = hit.get("party")
		if a == null:
			return
		selection.select_party(a)

## 左键点空地 → 行军。三件事一起做：
##   1. 玩家自己指了方向，就不该再有东西替他改目标 ⇒ 解除「追踪 / 先过去后进城」；
##   2. 清空选中（面板收起）—— 这也是「关掉选中面板」的自然手势；
##   3. 下发行军命令（时间流动的裁决仍在 TimeFlowController）。
func _on_order_move(goal: Vector2) -> void:
	_travel_target = null
	_track_target = null
	if selection != null:
		selection.clear()
	time.order_move(goal)

## 选中状态变了（HUD 重画面板 / 清空时收起）。面板数据由 SelectionSystem 组好。
func _on_selection_changed() -> void:
	if hud == null or selection == null:
		return
	if selection.is_empty():
		hud.hide_selection()
		return
	hud.show_selection(selection.title(), selection.body(), selection.entries())

## 选中面板上点了一条（含 Esc = "close"）。这里只解释动作，不改面板状态 ——
## 面板状态由 SelectionSystem 自己发 changed 回来，改两处迟早会不同步。
func _on_selection_action(action: String) -> void:
	if selection == null:
		return
	if action == Strings.SELECT_CLOSE:
		selection.clear()
		return
	if selection.is_empty():
		return
	var s := selection.settlement
	var a := selection.party
	if action == "enter" and s != null:
		_enter_settlement(s)
	elif action == "travel" and s != null:
		_travel_to(s)
	elif action == "track" and a != null:
		_track_party(a)

# ---------------------------------------------------------------- 进城 / 前往 / 追踪
## 进城。太远就先过去（抵达那一帧由 _on_player_arrived 接手自动进城）——
## 这比灰掉按钮 / 让玩家自己「先点前往再点进入」少两步操作。
func _enter_settlement(s: Settlement) -> void:
	if s == null or settlements == null or not settlements.enabled:
		return
	if _within_interact_range(s):
		_travel_target = null
		_track_target = null
		if not settlements.open(s):
			_report_settlement_refused()
		return
	_travel_target = s
	_track_target = null
	time.order_move(s.pos)
	if not player.moving:
		_travel_target = null
		if hud != null:
			hud.show_toast(Strings.SELECT_TRAVEL_UNREACHABLE % s.name, 3.0)
		return
	if hud != null:
		hud.show_toast(Strings.SELECT_TRAVEL_FIRST % [s.name, _distance_to(s.pos)], 3.0)

## 「前往」：只过去，不自动进城（抵达后想进再点一次城 —— 那时已在城门范围内）
func _travel_to(s: Settlement) -> void:
	if s == null or player == null:
		return
	_travel_target = null
	_track_target = null
	time.order_move(s.pos)
	if not player.moving and hud != null:
		hud.show_toast(Strings.SELECT_TRAVEL_UNREACHABLE % s.name, 3.0)

## 「追踪」：跟上这支部队。只在这里下一道命令，之后的重寻路在 _tick_tracking 里节流下发。
func _track_party(a: AIParty) -> void:
	if a == null or not is_instance_valid(a) or player == null:
		return
	_travel_target = null
	_track_target = a
	_track_goal = Vector2(a.position.x, a.position.z)
	_track_timer = TRACK_REPATH_S
	time.order_move(_track_goal)
	if hud == null:
		return
	if player.moving:
		hud.show_toast(Strings.SELECT_TRACK_ON % a.party_name, 2.0)
	else:
		_track_target = null
		hud.show_toast(Strings.SELECT_TRAVEL_UNREACHABLE % a.party_name, 3.0)

## 每帧（见 _process）推进追踪。解除追踪的两种情形都写在这里：
##   · 目标没了（被别处结算掉 / 打赢后被 erase）→ 清空选中并说一句；
##   · 我军自己停下了（抵达 / 被空格打断 / 被遭遇打断）→ 静默解除。
##     这一条不能省：否则「按空格停止行军」会在 2 秒后被追踪逻辑重新启动，
##     玩家会以为按键坏了。
func _tick_tracking(delta: float) -> void:
	if _track_target == null:
		return
	if not is_instance_valid(_track_target) or not ai_parties.has(_track_target):
		_track_target = null
		if selection != null and selection.kind == MapPicker.KIND_PARTY:
			selection.clear()
		if hud != null:
			hud.show_toast(Strings.SELECT_TRACK_LOST, 2.5)
		return
	if time.state == TimeFlowController.State.FROZEN:
		_track_target = null
		return
	_track_timer -= delta
	if _track_timer > 0.0:
		return
	var goal := Vector2(_track_target.position.x, _track_target.position.z)
	if goal.distance_to(_track_goal) < TRACK_REPATH_M:
		return
	_track_goal = goal
	_track_timer = TRACK_REPATH_S
	# 刻意直接调 set_destination 而不再走 time.order_move()：追踪的重寻路不是新命令，
	# 不该每 2 秒在日志里打一行「前往 (x, y)」，也不该重新触发空格消费标记。
	player.set_destination(goal)

## 抵达（只在正常走完路径时发，见 PlayerParty.arrived）——
## 「先过去，抵达后自动进城」在这里收尾。
func _on_player_arrived() -> void:
	if _travel_target == null:
		return
	var s := _travel_target
	_travel_target = null
	if settlements == null:
		return
	if not settlements.open(s):
		if hud != null and not hud.is_any_dialog_open():
			hud.show_toast(Strings.SELECT_ENTER_FAILED, 3.0)
		return
	# 进城 = 菜单接管，选中面板收起（菜单是模态的，两面板不该同时在场）
	if selection != null:
		selection.clear()

func _within_interact_range(s: Settlement) -> bool:
	if s == null or player == null:
		return false
	return _distance_to(s.pos) <= s.interact_radius()

func _distance_to(world: Vector2) -> int:
	if player == null:
		return 0
	var p := Vector2(player.position.x, player.position.z)
	return int(round(p.distance_to(world)))

## 开不了菜单时给一句为什么（与 _on_interact_requested 的兜底同一口径）
func _report_settlement_refused() -> void:
	if hud != null and not hud.is_any_dialog_open():
		hud.show_toast(Strings.SELECT_ENTER_FAILED, 3.0)

# =============================================================== 进城菜单
## 交互键（见 InputRouter.interact_requested）→ 进最近的那个定居点。
## 附近没有 / 世界时间被别人锁着（遭遇对话、Boss 战）时不硬开，给一句提示：
## 「按了没反应」是最难查的一类问题，宁可让 UI 说清楚。
func _on_interact_requested() -> void:
	if settlements == null:
		return
	if settlements.open():
		return
	if hud != null and not hud.is_any_dialog_open():
		hud.show_toast("附近没有可以进入的定居点（走到村庄 / 城镇 / 城堡旁再按）", 2.5)

func _on_settlement_opened(_s: Settlement) -> void:
	# 进城菜单是模态的（会锁世界时间），选中面板必须先收起来 ——
	# 否则两块面板同时在场，玩家会以为还能继续点地图。
	_travel_target = null
	_track_target = null
	if selection != null:
		selection.clear()
	_refresh_settlement_menu()

func _on_settlement_menu_changed() -> void:
	_refresh_settlement_menu()

func _on_settlement_closed() -> void:
	if hud != null:
		hud.hide_settlement()

## 把「当前菜单」原样交给 HUD：标题 / 状态行 / 条目数组都来自系统，Main 不加工。
func _refresh_settlement_menu() -> void:
	if hud == null or settlements == null:
		return
	var s := settlements.current
	if s == null:
		return
	hud.show_settlement_menu("%s　%s" % [s.name, s.kind_name()],
		settlements.status_line(), settlements.menu_entries())
