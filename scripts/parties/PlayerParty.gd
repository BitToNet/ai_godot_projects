## =============================================================================
##  PlayerParty —— 玩家部队
##  · 鼠标左键点击地面（Main 负责射线求交）→ 这里做 A* 寻路（细栅格）
##  · 目标标记（旋转光环 + 光柱）与路径预览（贴地三角带）
##  · 时间流动由 Main 统一裁决：行军途中时间自动流动，抵达瞬间暂停；
##    移动中按空格 → halt() 立刻停下并暂停；原地长按空格 → 时间才流动。
##    暂停时 Main 不再调用 step()
## =============================================================================
class_name PlayerParty
extends PartyBase

var marker_root: Node3D
var marker_ring: MeshInstance3D
var preview: MeshInstance3D
var preview_mat: StandardMaterial3D
var _spin: float = 0.0

func setup_player(p_data: MapData, p_cfg: MapConfig, p_name: String, p_faction: int, p_count: int, mat: Material, model_mesh: Mesh) -> void:
	is_player = true
	setup(p_data, p_cfg, p_name, p_faction, p_count, p_cfg.player_speed, mat, model_mesh)
	_build_marker()
	refresh_label()

func _build_marker() -> void:
	preview_mat = StandardMaterial3D.new()
	preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_mat.albedo_color = Color(1.0, 0.86, 0.35, 0.85)
	preview_mat.vertex_color_use_as_albedo = true
	preview_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	marker_root = Node3D.new()
	marker_root.name = "TargetMarker"
	marker_root.visible = false
	add_child(marker_root)

	# 光环（两圈 + 四个指针）
	var k := MeshKit.new()
	var seg := 28
	var r_in := 2.6
	var r_out := 3.3
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var p0i := Vector3(cos(a0) * r_in, 0, sin(a0) * r_in)
		var p0o := Vector3(cos(a0) * r_out, 0, sin(a0) * r_out)
		var p1i := Vector3(cos(a1) * r_in, 0, sin(a1) * r_in)
		var p1o := Vector3(cos(a1) * r_out, 0, sin(a1) * r_out)
		var c := Color(1.0, 0.88, 0.36, 0.9) if i % 2 == 0 else Color(1.0, 0.55, 0.18, 0.8)
		k.add_quad_up(p0i, p1i, p1o, p0o, c)
	# 中心十字
	k.add_quad_up(Vector3(-0.35, 0, -1.6), Vector3(0.35, 0, -1.6), Vector3(0.35, 0, 1.6), Vector3(-0.35, 0, 1.6), Color(1, 0.85, 0.3, 0.85))
	k.add_quad_up(Vector3(-1.6, 0, -0.35), Vector3(1.6, 0, -0.35), Vector3(1.6, 0, 0.35), Vector3(-1.6, 0, 0.35), Color(1, 0.85, 0.3, 0.85))
	# 光柱
	k.add_cylinder(Vector3(0, 0, 0), 0.22, 0.06, 16.0, 6, Color(1.0, 0.85, 0.35, 0.22), false, false)
	marker_ring = MeshInstance3D.new()
	marker_ring.mesh = k.build()
	marker_ring.material_override = preview_mat
	marker_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker_root.add_child(marker_ring)

	preview = MeshInstance3D.new()
	preview.name = "PathPreview"
	preview.material_override = preview_mat
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(preview)

## 命令部队前往某点
func set_destination(p: Vector2) -> void:
	var from := Vector2(position.x, position.z)
	var pts := data.path_fine.find_path(from, p)
	if pts.size() < 1:
		return
	set_path(pts)
	_show_marker(p)
	_build_preview(pts)

func _show_marker(p: Vector2) -> void:
	marker_root.visible = true
	var h := data.hm.height_at(p.x, p.y)
	marker_root.position = Vector3(p.x, maxf(h, cfg.sea_level) + 0.45, p.y)

func _build_preview(pts: PackedVector3Array) -> void:
	if pts.size() < 2:
		preview.mesh = null
		return
	var k := MeshKit.new()
	var w := 0.55
	for i in range(1, pts.size()):
		var a := Vector3(pts[i - 1].x, 0, pts[i - 1].z)
		var b := Vector3(pts[i].x, 0, pts[i].z)
		var d := (b - a)
		if d.length_squared() < 0.0001:
			continue
		var perp := Vector3(-d.z, 0, d.x).normalized() * w
		a.y = data.hm.height_at(a.x, a.z) + 0.5
		b.y = data.hm.height_at(b.x, b.z) + 0.5
		k.add_quad_up(a - perp, b - perp, b + perp, a + perp, Color(1.0, 0.83, 0.32, 0.72))
	preview.mesh = k.build()

func step(delta: float) -> void:
	super.step(delta)
	_spin += delta * 1.1
	if marker_root != null and marker_root.visible:
		marker_root.rotation.y = _spin
		marker_root.position.y = maxf(data.hm.height_at(marker_root.position.x, marker_root.position.z), cfg.sea_level) + 0.45 + sin(_spin * 2.0) * 0.25
	if not moving and preview != null and preview.mesh != null:
		preview.mesh = null

func on_path_finished() -> void:
	if preview != null:
		preview.mesh = null

## 立即停止行军（Main 的「移动中按空格」/ 遭遇打断会调用）：
## 清空路径、收起目标点光环与路径预览，部队就地停下。
func halt() -> void:
	super.halt()
	if marker_root != null:
		marker_root.visible = false
	if preview != null:
		preview.mesh = null
