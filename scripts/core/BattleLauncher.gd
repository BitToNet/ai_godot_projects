## =============================================================================
##  BattleLauncher —— 进出 2D 横版 Boss 战
##
##  从 Main.gd 搬出：_start_battle / _on_battle_finished / _terrain_kind_at。
##  只负责「场景的生命周期与进出场」：拼交给 BattleScene 的 payload、隐藏大地图、
##  冻结时间与输入、打完复位；**战利品 / 兵力损失 / 战败回城不在这里**，
##  那些交给 EncounterSystem.on_battle_finished（通过 finished 信号）。
##
##  场景挂在 ctx.host 下（战斗期间大地图整层隐藏，两者同树）。
## =============================================================================
class_name BattleLauncher
extends RefCounted

## 战斗场景已释放、世界已复位后发出；由 Main 转接给 EncounterSystem 做结算
signal finished(result: String, party: AIParty)

var ctx: WorldContext
var battle: BattleScene = null        ## 正在进行的战斗（null = 在大地图上）

## 依据遭遇点在大地图上的位置决定战斗背景风格：雪山 / 沙漠 / 草原
func terrain_kind_at(p: Vector2) -> String:
	var h := ctx.data.hm.height_at(p.x, p.y)
	if h >= ctx.cfg.snow_line:
		return "snow"
	if ctx.data.gen != null and ctx.data.gen.biome_desert.size() > 0:
		var gx := clampi(int(round(p.x / ctx.data.hm.cell)), 0, ctx.data.hm.res - 1)
		var gz := clampi(int(round(p.y / ctx.data.hm.cell)), 0, ctx.data.hm.res - 1)
		var i := gz * ctx.data.hm.res + gx
		if i >= 0 and i < ctx.data.gen.biome_desert.size() and ctx.data.gen.biome_desert[i] > 0.45:
			return "desert"
	return "grass"

## 进入 Boss 战：把玩家部队名 / 地形 / Boss 数据传给战斗场景，隐藏大地图
func start(a: AIParty) -> void:
	if battle != null or a == null or not is_instance_valid(a):
		return
	var p := Vector2(a.position.x, a.position.z)
	var terrain := terrain_kind_at(p)
	var bcfg := BattleConfig.create()
	var fcol := Color(0.72, 0.22, 0.22)
	if a.faction_id >= 0:
		fcol = ctx.data.faction(a.faction_id).color
	# 按敌人类型给不同的 HP / 破防值（商队护卫长最弱，领主最强）—— 公式在 EncounterRules
	var kind := a.ai_kind()
	var bhp := ctx.rules.boss_hp(kind, a.troop_count)
	var bpoise := ctx.rules.boss_poise(kind, a.troop_count)
	var payload := {
		"config": bcfg,
		"player_name": "玩家部队 · %d 人" % ctx.player.troop_count,
		"player_hp": bcfg.player_max_hp,
		"troops": ctx.player.troop_count,
		"terrain": terrain,
		"boss_kind": kind,
		"boss_name": a.boss_title if a.boss_title != "" else a.party_name,
		"boss_hp": bhp,
		"boss_poise": bpoise,
		"faction_color": fcol,
		"player_color": Color(0.70, 0.18, 0.20),
		"seed": ctx.cfg.map_seed * 7 + int(absf(p.x) * 13.0) + int(absf(p.y) * 29.0),
	}
	battle = BattleScene.new()
	ctx.host.add_child(battle)
	battle.setup(payload)
	battle.finished.connect(_on_scene_finished.bind(a))
	ctx.view.set_visible(false)
	ctx.time.lock()                # 战斗中世界时间保持冻结（空格无效）
	ctx.set_camera_active(false)   # 战斗中相机不再吃键鼠（BattleScene 自己收输入）
	if ctx.router != null:
		ctx.router.enabled = false  # 战斗中输入归 BattleScene，别让大地图热键漏进来
	print("[Boss战] 进入战斗：%s（类型 %s）｜ 地形 %s ｜ 敌方兵力 %d ｜ Boss HP %.0f 破防 %.0f" % [
		payload["boss_name"], kind, terrain, a.troop_count, bhp, bpoise])
	# 开战号角（鼓点 + 低音号角），同时把背景音乐切到战斗曲（短淡入，别拖过第一刀）
	Sfx.play("battle_start")
	Bgm.play("battle", ctx.audio.bgm_fade_battle)

## 战斗场景自己喊结束（BattleScene.finished）→ 复位世界，再把结果转出去
func _on_scene_finished(result: String, a: AIParty) -> void:
	if battle != null and is_instance_valid(battle):
		battle.queue_free()
	battle = null
	# 回到大地图：战斗曲长淡出，行军主题重新淡入（结算音效还在响，别抢）
	Bgm.play("map", ctx.audio.bgm_fade_map)
	ctx.view.set_visible(true)
	ctx.set_camera_active(true)
	if ctx.router != null:
		ctx.router.enabled = true
	# 回到大地图：解除强制暂停，交还给时间流动状态机
	# （战败会被送去城镇 → 行军中时间流动；其余情况部队原地待命 → 保持暂停）
	ctx.time.unlock()
	finished.emit(result, a)