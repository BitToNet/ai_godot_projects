## =============================================================================
##  HoverInspector —— 鼠标悬停时往 HUD 里填「这里有什么」
##
##  从 Main.gd 搬出：_update_hover()（含每帧节流用的 _hover_timer）。
##  纯只读查询（部队 → 定居点 → 空地），不抽随机数、不改世界状态。
##
##  优先级刻意保持不变：先看部队（半径 7 m），再看定居点（半径 + 6 m），
##  都没有就清掉提示框、只留地形说明。
## =============================================================================
class_name HoverInspector
extends RefCounted

## 取鼠标位置要用视口，所以需要一个场景树里的节点当宿主
var host: Node
var camera_rig: CameraRig
var hud: HUD
var data: MapData
var cfg: MapConfig
var parties: Array[AIParty]

## 悬停检测每 0.1 秒一次就够（射线 + 遍历定居点没必要每帧做）
const INTERVAL := 0.1
var _timer: float = 0.0

func tick(delta: float) -> void:
	_timer += delta
	if _timer > INTERVAL:
		_timer = 0.0
		update()

func update() -> void:
	if host == null or camera_rig == null or hud == null:
		return
	var mouse := host.get_viewport().get_mouse_position()
	if hud.is_encounter_open():
		hud.clear_tooltip()
		return
	var hit := camera_rig.ray_to_terrain(mouse)
	if hit.y < cfg.sea_level - 1.0:
		hud.clear_tooltip()
		hud.set_terrain_text("海洋 / 不可通行")
		return
	var p := Vector2(hit.x, hit.z)
	# 1) 部队
	for a in parties:
		if a == null or not is_instance_valid(a):
			continue
		if Vector2(a.position.x, a.position.z).distance_to(p) < 7.0:
			var fname := GameState.faction_name(data, a.faction_id, "无阵营（流寇）")
			var kindname := GameState.party_kind_name(a.ai_kind())
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
				GameState.faction_name(data, terr, "无主之地")], mouse)
			hud.set_terrain_text(data.nav_fine.describe_at_world(p))
			return
	hud.clear_tooltip()
	hud.set_terrain_text(data.nav_fine.describe_at_world(p))