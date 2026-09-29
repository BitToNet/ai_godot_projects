## =============================================================================
##  MinimapView —— 右上角小地图
##  底图是 MapTextureBaker 烘焙的 256² 贴图（生物群系 + 势力领地 + 道路），
##  上面用 _draw() 实时叠加：定居点、AI 部队、玩家、战争迷雾、边框。
## =============================================================================
class_name MinimapView
extends Control

var data: MapData
var player: PartyBase
var ai_parties: Array = []
var fog: FogOfWar
var zoom: float = 1.0
var _blink: float = 0.0

func setup(p_data: MapData, p_player: PartyBase, p_ai: Array, p_fog: FogOfWar) -> void:
	data = p_data
	player = p_player
	ai_parties = p_ai
	fog = p_fog
	custom_minimum_size = Vector2(300, 300)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(delta: float) -> void:
	_blink += delta
	queue_redraw()

func _w2m(p: Vector2) -> Vector2:
	return Vector2(p.x / data.cfg.map_size * size.x, p.y / data.cfg.map_size * size.y)

func _draw() -> void:
	if data == null or data.minimap_texture == null:
		return
	draw_texture_rect(data.minimap_texture, Rect2(Vector2.ZERO, size), false)
	# 战争迷雾叠加
	if fog != null and fog.enabled and fog.texture != null:
		draw_texture_rect(fog.texture, Rect2(Vector2.ZERO, size), false, Color(0.02, 0.02, 0.06, 1.0))
	# 定居点
	for s in data.settlements:
		var p := _w2m(s.pos)
		var f := data.faction(s.faction_id)
		var r := 2.2
		match s.kind:
			Settlement.Kind.CASTLE:
				r = 4.6
				# 王都画一个方块
				draw_rect(Rect2(p - Vector2(r, r), Vector2(r * 2, r * 2)), f.color, true)
				draw_rect(Rect2(p - Vector2(r, r), Vector2(r * 2, r * 2)), Color(1, 1, 1, 0.85), false, 1.0)
				continue
			Settlement.Kind.TOWN:
				r = 3.2
			_:
				r = 1.8
		draw_circle(p, r, f.color)
		draw_arc(p, r + 1.0, 0, TAU, 12, Color(0.05, 0.05, 0.08, 0.85), 1.0)
	# 道路已经烘焙进底图；这里画 AI 部队
	for a in ai_parties:
		if a == null or not is_instance_valid(a):
			continue
		var p2 := _w2m(Vector2(a.position.x, a.position.z))
		var col := Color(0.95, 0.95, 0.95)
		var kind: String = a.ai_kind()
		if kind == "bandit":
			col = Color(0.85, 0.25, 0.25)
		elif kind == "caravan":
			col = Color(0.95, 0.85, 0.35)
		else:
			col = data.faction(a.faction_id).color.lightened(0.3)
		if kind == "bandit" and a.chasing:
			draw_circle(p2, 3.4 + sin(_blink * 6.0) * 1.2, Color(1.0, 0.2, 0.15, 0.55))
		draw_circle(p2, 2.4, col)
	# 玩家（三角箭头）
	if player != null:
		var pp := _w2m(Vector2(player.position.x, player.position.z))
		var fwd := Vector3(sin(player.rotation.y), 0, cos(player.rotation.y)) * -1.0
		var right := Vector3(fwd.z, 0, -fwd.x)
		var a3 := pp + Vector2(fwd.x, fwd.z) * 7.0
		var b3 := pp + Vector2(right.x, right.z) * 4.5 - Vector2(fwd.x, fwd.z) * 3.0
		var c3 := pp - Vector2(right.x, right.z) * 4.5 - Vector2(fwd.x, fwd.z) * 3.0
		draw_colored_polygon(PackedVector2Array([a3, b3, c3]), Color(1.0, 0.98, 0.85))
		draw_polyline(PackedVector2Array([a3, b3, c3, a3]), Color(0.1, 0.1, 0.12), 1.0)
		# 视野圈
		var vr := data.cfg.fog_reveal_radius / data.cfg.map_size * size.x
		draw_arc(pp, vr, 0, TAU, 48, Color(1, 1, 1, 0.25), 1.0)
	# 边框
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.82, 0.72, 0.9), false, 2.0)
	draw_rect(Rect2(Vector2(-3, -3), size + Vector2(6, 6)), Color(0.08, 0.07, 0.06, 0.95), false, 3.0)
