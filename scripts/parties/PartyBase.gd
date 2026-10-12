## =============================================================================
##  PartyBase —— 部队基类（玩家 / AI 共用）
##  · 沿 A* 路径行进，速度 = 基准速度 × 地形速度倍率（道路 1.2 / 草原 1.0 /
##    森林 0.7 / 山地 0.5 / 雪地 0.4）
##  · 贴合地形高度、朝移动方向转向（角度插值）、按速度做上下颠簸
##  · 头顶 Label3D 显示部队名与人数，颜色取势力色
## =============================================================================
class_name PartyBase
extends Node3D

var data: MapData
var cfg: MapConfig
var party_name: String = "部队"
var faction_id: int = 0
var troop_count: int = 20
var speed_base: float = 40.0
var is_player: bool = false

var path: PackedVector3Array = PackedVector3Array()
var path_index: int = 0
var target: Vector2 = Vector2.ZERO
var has_target: bool = false
var moving: bool = false

var model: MeshInstance3D
var label: Label3D
var _bob: float = 0.0
var _yaw: float = 0.0
var _dist_travelled: float = 0.0
var idle_time: float = 0.0

func setup(p_data: MapData, p_cfg: MapConfig, p_name: String, p_faction: int, p_count: int, p_speed: float, mat: Material, model_mesh: Mesh) -> void:
	data = p_data
	cfg = p_cfg
	party_name = p_name
	faction_id = p_faction
	troop_count = p_count
	speed_base = p_speed
	model = MeshInstance3D.new()
	model.mesh = model_mesh
	model.material_override = mat
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(model)
	label = Label3D.new()
	label.text = party_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.022
	label.font_size = 84
	label.outline_size = 22
	label.outline_modulate = Color(0.02, 0.02, 0.04, 0.95)
	label.modulate = _label_color()
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.render_priority = 12
	label.position = Vector3(0, 4.6, 0)
	add_child(label)
	_snap_to_ground()
	_yaw = rotation.y

func _label_color() -> Color:
	if faction_id >= 0 and faction_id < data.factions.size():
		return data.faction(faction_id).color.lightened(0.35)
	return Color(0.95, 0.92, 0.85)

func refresh_label() -> void:
	if label == null:
		return
	match ai_kind():
		"lord":
			label.text = "%s\n%s · %d 人" % [party_name, data.faction(faction_id).name, troop_count]
		"caravan":
			label.text = "%s · %d 人" % [party_name, troop_count]
		"bandit":
			label.text = "%s · %d 人" % [party_name, troop_count]
		_:
			label.text = "%s · %d 人" % [party_name, troop_count]

## 子类覆写："" / "lord" / "caravan" / "bandit"
func ai_kind() -> String:
	return ""

func _snap_to_ground() -> void:
	var h := data.hm.height_at(position.x, position.z)
	position.y = maxf(h, cfg.sea_level)

# ---------------------------------------------------------------- 路径
func set_path(pts: PackedVector3Array) -> void:
	path = pts
	path_index = 0
	moving = path.size() >= 1
	has_target = moving
	if moving:
		target = Vector2(path[path.size() - 1].x, path[path.size() - 1].z)

func clear_path() -> void:
	path = PackedVector3Array()
	path_index = 0
	moving = false
	has_target = false

## 立即中断移动：清空路径与目标点（按空格打断行军 / 遭遇打断行军时调用）
func halt() -> void:
	if not moving and path.is_empty() and not has_target:
		return
	clear_path()
	on_path_finished()

func remaining_distance() -> float:
	if not moving:
		return 0.0
	var d := 0.0
	var p := Vector2(position.x, position.z)
	for i in range(path_index, path.size()):
		var q := Vector2(path[i].x, path[i].z)
		d += p.distance_to(q)
		p = q
	return d

# ---------------------------------------------------------------- 每帧推进
func step(delta: float) -> void:
	if moving:
		_advance(delta)
		idle_time = 0.0
	else:
		idle_time += delta
	_update_visual(delta)

func terrain_speed() -> float:
	return data.nav_fine.speed_at_world(Vector2(position.x, position.z))

func _advance(delta: float) -> void:
	var budget := speed_base * terrain_speed() * delta
	var guard := 0
	while budget > 0.0 and path_index < path.size() and guard < 64:
		guard += 1
		var cur := Vector2(position.x, position.z)
		var nxt := Vector2(path[path_index].x, path[path_index].z)
		var d := cur.distance_to(nxt)
		if d <= 0.001:
			path_index += 1
			continue
		if d <= budget:
			position.x = nxt.x
			position.z = nxt.y
			budget -= d
			_dist_travelled += d
			path_index += 1
		else:
			var dir := (nxt - cur) / d
			var step_v := dir * budget
			position.x += step_v.x
			position.z += step_v.y
			_dist_travelled += budget
			budget = 0.0
	if path_index >= path.size():
		clear_path()
		on_path_finished()

func on_path_finished() -> void:
	pass

func _update_visual(delta: float) -> void:
	_snap_to_ground()
	# 朝向：朝路径下一节点插值转向
	var desired := _yaw
	if moving and path_index < path.size():
		var nxt := Vector2(path[path_index].x, path[path_index].z)
		var d := nxt - Vector2(position.x, position.z)
		if d.length_squared() > 0.04:
			desired = atan2(-d.x, -d.y)
	elif moving:
		desired = _yaw
	if not moving and idle_time > 0.0:
		pass
	# 注意：模型朝 -Z 建模，所以 yaw = atan2(-dx, -dz)
	_yaw = lerp_angle(_yaw, desired, clampf(delta * 6.0, 0.0, 1.0))
	rotation.y = _yaw
	# 颠簸
	var s := terrain_speed()
	_bob += delta * (4.0 + 6.0 * s) * (1.0 if moving else 0.25)
	if model != null:
		model.position.y = sin(_bob) * (0.12 if moving else 0.03)
		model.rotation.z = sin(_bob * 0.5) * (0.02 if moving else 0.0)

func distance_to_party(other: PartyBase) -> float:
	return Vector2(position.x, position.z).distance_to(Vector2(other.position.x, other.position.z))
