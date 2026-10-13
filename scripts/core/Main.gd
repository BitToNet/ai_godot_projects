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
func _process(delta: float) -> void:
	# view / hover / encounters / battler 都是生成流程最后才组装的（要等相机、植被、
	# 部队、HUD 全部就位），在那之前 _process 已经在跑（_ready 里全是 await），
	# 所以这里必须一起判空。
	if data == null or player == null or view == null or encounters == null or battler == null:
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
	print("[日结] 第 %d 天：兵力 %d，粮 %d（吃 %d），士气 %d，钱 %d" % [
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
			print("[周结] 军费不足：应发 %d，实发 %d，欠薪 %d 周" % [
				wage, paid, int(week.get("debt_weeks", 0))])
		else:
			notices.append("💰 发了本周军费 %d 金" % paid)
			print("[周结] 军费已发：%d 金" % paid)
	if deserted > 0:
		notices.append("❗%d 名士兵因士气崩溃离队" % deserted)
	if not notices.is_empty() and hud != null:
		hud.show_toast("　".join(notices), 6.0)

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
	print("[UI] 势力 %s 的定居点标签：%s" % [data.faction(fid).name, "显示" if any_visible else "隐藏"])

