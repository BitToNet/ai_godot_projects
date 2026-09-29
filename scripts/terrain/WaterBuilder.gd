## =============================================================================
##  WaterBuilder —— 水面构建
##   · 海洋：一块 3072x3072 的大平面（远超地图边界，避免看到地图「切边」），
##     顶点波动 + 菲涅尔 + 按水深染色 + 岸边泡沫，全部在水面 Shader 里做。
##   · 湖泊：每个湖一块小平面，水面高度 = 生成湖泊时记录的水位。
##   · 河流：沿河道折线生成一条三角带（ribbon），顶点高度 = 水面剖面，
##     因此河流能顺着地形从山上流到海里。
## =============================================================================
class_name WaterBuilder
extends Node3D

var cfg: MapConfig
var data: MapData
var ocean: MeshInstance3D
var mats: Array[ShaderMaterial] = []

func setup(p_cfg: MapConfig, p_data: MapData) -> void:
	cfg = p_cfg
	data = p_data

	# ---------------- 海洋 ----------------
	var pm := PlaneMesh.new()
	pm.size = Vector2(3200, 3200)
	pm.subdivide_width = 96
	pm.subdivide_depth = 96
	pm.center_offset = Vector3(cfg.map_size * 0.5, 0, cfg.map_size * 0.5)
	ocean = MeshInstance3D.new()
	ocean.name = "Ocean"
	ocean.mesh = pm
	ocean.material_override = _make_mat(cfg.sea_level, 1.0, 0.42, 0.85, 0.90, 0.40, 3.4,
		Color(0.30, 0.58, 0.60), Color(0.015, 0.075, 0.170))
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean)

	# ---------------- 湖泊 ----------------
	for i in data.gen.lakes.size():
		var l = data.gen.lakes[i]
		var lm := PlaneMesh.new()
		lm.size = Vector2(l.radius * 2.3, l.radius * 2.3)
		lm.subdivide_width = 12
		lm.subdivide_depth = 12
		var mi := MeshInstance3D.new()
		mi.name = "Lake_%d" % i
		mi.mesh = lm
		mi.position = Vector3(l.center.x, l.water_level, l.center.y)
		mi.material_override = _make_mat(l.water_level, 0.35, 0.16, 0.9, 0.80, 0.34, 1.6,
			Color(0.30, 0.56, 0.58), Color(0.03, 0.13, 0.22))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

	# ---------------- 河流 ----------------
	for i in data.gen.rivers.size():
		var r: Dictionary = data.gen.rivers[i]
		var pts: PackedVector3Array = r.points
		var widths: PackedFloat32Array = r.widths
		var dirs: PackedVector2Array = r.dirs
		if pts.size() < 2:
			continue
		var kit := MeshKit.new()
		for k in pts.size():
			var p: Vector3 = pts[k]
			var d: Vector2 = dirs[k]
			var perp := Vector2(-d.y, d.x)
			var w: float = widths[k]
			var a := Vector3(p.x + perp.x * w, p.y, p.z + perp.y * w)
			var b := Vector3(p.x - perp.x * w, p.y, p.z - perp.y * w)
			if k < pts.size() - 1:
				var p2: Vector3 = pts[k + 1]
				var d2: Vector2 = dirs[k + 1]
				var perp2 := Vector2(-d2.y, d2.x)
				var w2: float = widths[k + 1]
				var a2 := Vector3(p2.x + perp2.x * w2, p2.y, p2.z + perp2.y * w2)
				var b2 := Vector3(p2.x - perp2.x * w2, p2.y, p2.z - perp2.y * w2)
				kit.add_quad_up(a, a2, b2, b, Color(1, 1, 1))
		var mesh := kit.build()
		if mesh == null:
			continue
		var mi2 := MeshInstance3D.new()
		mi2.name = "River_%d" % i
		mi2.mesh = mesh
		var avg_dir := Vector2.ZERO
		for d3 in dirs:
			avg_dir += d3
		avg_dir = avg_dir.normalized() if avg_dir.length() > 0.01 else Vector2(0, 1)
		var m := _make_mat(cfg.sea_level, 0.25, 0.10, 0.55, 0.72, 0.26, 0.55,
			Color(0.33, 0.55, 0.56), Color(0.06, 0.18, 0.25))
		m.set_shader_parameter("flow_dir", avg_dir)
		m.set_shader_parameter("wave_speed", 2.6)
		mi2.material_override = m
		mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi2)

func _make_mat(level: float, wscale: float, wheight: float, foam: float, alpha: float, shallow_alpha: float,
		foam_far: float, shallow_col: Color, deep_col: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("height_map", data.height_texture)
	m.set_shader_parameter("map_size", cfg.map_size)
	m.set_shader_parameter("water_level", level)
	m.set_shader_parameter("wave_scale", wscale)
	m.set_shader_parameter("wave_height", wheight)
	m.set_shader_parameter("foam_strength", foam)
	m.set_shader_parameter("transparency", alpha)
	m.set_shader_parameter("shallow_alpha", shallow_alpha)
	m.set_shader_parameter("foam_far", foam_far)
	m.set_shader_parameter("foam_near", foam_far * 0.06)
	m.set_shader_parameter("shallow_color", shallow_col)
	m.set_shader_parameter("deep_color", deep_col)
	m.set_shader_parameter("sky_tint", Color(0.58, 0.74, 0.95))
	m.set_shader_parameter("foam_color", Color(0.94, 0.97, 0.99))
	mats.append(m)
	return m

func set_night(v: float) -> void:
	for m in mats:
		m.set_shader_parameter("night_amount", v)
