## =============================================================================
##  MeshKit —— 纯代码几何体拼装器（ArrayMesh 生成）
##  所有模型（建筑 / 马匹 / 骑手 / 树木）都由基础几何体拼出来，不用任何外部模型。
##
##  绕序约定（Godot 正面 = 顺时针，front face normal = (c-a) x (b-a)）：
##  每个 quad 的顶点顺序都按此约定手写，保证法线朝外、光照正确。
## =============================================================================
class_name MeshKit
extends RefCounted

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()

# 当前变换栈（用于把方块/屋顶旋转后放进去）
var _xf := Transform3D.IDENTITY
var _xf_stack: Array[Transform3D] = []

func push_transform(t: Transform3D) -> void:
	_xf_stack.append(_xf)
	_xf = _xf * t

func pop_transform() -> void:
	if _xf_stack.size() > 0:
		_xf = _xf_stack.pop_back()

func _p(v: Vector3) -> Vector3:
	return _xf * v

func _n(v: Vector3) -> Vector3:
	return (_xf.basis * v).normalized()

func is_empty() -> bool:
	return verts.is_empty()

func vertex_count() -> int:
	return verts.size()

func clear() -> void:
	verts.clear(); norms.clear(); cols.clear(); idx.clear()

func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var pa := _p(a)
	var pb := _p(b)
	var pc := _p(c)
	# Godot 的正面法线 = (c-a) x (b-a)
	var n := (pc - pa).cross(pb - pa)
	if n.length_squared() < 1e-12:
		n = Vector3.UP
	else:
		n = n.normalized()
	n = _n(n)
	var base := verts.size()
	verts.append(pa); verts.append(pb); verts.append(pc)
	norms.append(n); norms.append(n); norms.append(n)
	cols.append(col); cols.append(col); cols.append(col)
	idx.append(base); idx.append(base + 1); idx.append(base + 2)

## 四边形，自动保证法线朝上（用于水面/农田等水平面片）
func add_quad_up(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.y < 0.0:
		add_quad(a, d, c, b, col)
	else:
		add_quad(a, b, c, d, col)

## 低多边形球（阔叶树冠 / 仙人掌 / 石头）
func add_sphere(center: Vector3, radius: float, segs: int = 8, rings: int = 5, col: Color = Color.WHITE) -> void:
	var sg := maxi(3, segs)
	var rg := maxi(2, rings)
	var rows: Array[PackedVector3Array] = []
	for r in range(rg + 1):
		var theta := PI * float(r) / float(rg)
		var row := PackedVector3Array()
		for s in sg:
			var phi := TAU * float(s) / float(sg)
			row.append(center + Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi)) * radius)
		rows.append(row)
	for r in rg:
		var r0 := rows[r]
		var r1 := rows[r + 1]
		for s in sg:
			var s2 := (s + 1) % sg
			# 顶端/底端退化为三角形
			if r == 0:
				add_tri(r0[0], r1[s], r1[s2], col)
			elif r == rg - 1:
				add_tri(r1[0], r0[s2], r0[s], col)
			else:
				add_quad(r0[s], r1[s], r1[s2], r0[s2], col)

## 四边形 a->b->c->d（按正面顺时针给出）
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(a, b, c, col)
	_tri(a, c, d, col)

# ---------------------------------------------------------------- 基础体
## 轴对齐方块（中心 + 尺寸）
func add_box(center: Vector3, size: Vector3, col: Color, col_top: Color = Color(0, 0, 0, -1)) -> void:
	add_box_xf(Transform3D(Basis.IDENTITY, center), size, col, col_top)

## 任意朝向的方块：xf 描述方块局部坐标 → 世界
func add_box_xf(xf: Transform3D, size: Vector3, col: Color, col_top: Color = Color(0, 0, 0, -1)) -> void:
	var h := size * 0.5
	var c_top := col if col_top.a < 0.0 else col_top
	push_transform(xf)
	# +X
	add_quad(Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), col)
	# -X
	add_quad(Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), col)
	# +Y (顶面可用单独颜色：屋顶/雪)
	add_quad(Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), c_top)
	# -Y
	add_quad(Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), col)
	# +Z
	add_quad(Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z), col)
	# -Z
	add_quad(Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z), col)
	pop_transform()

## 圆柱 / 圆台（塔楼、树干、井）：底面中心 base，高 h
func add_cylinder(base: Vector3, r_bottom: float, r_top: float, h: float, segments: int, col: Color, cap_top: bool = true, cap_bottom: bool = true, phase: float = 0.0) -> void:
	var seg := maxi(3, segments)
	var pb: PackedVector3Array = []
	var pt: PackedVector3Array = []
	for i in seg:
		var a := phase + TAU * float(i) / float(seg)
		pb.append(base + Vector3(cos(a) * r_bottom, 0.0, sin(a) * r_bottom))
		pt.append(base + Vector3(cos(a) * r_top, h, sin(a) * r_top))
	for i in seg:
		var j := (i + 1) % seg
		add_quad(pb[i], pb[j], pt[j], pt[i], col)
	if cap_top:
		var ct := base + Vector3(0, h, 0)
		for i in seg:
			add_tri(ct, pt[i], pt[(i + 1) % seg], col)
	if cap_bottom:
		for i in seg:
			add_tri(base, pb[(i + 1) % seg], pb[i], col)

## 圆锥（塔尖、针叶树冠）
func add_cone(base: Vector3, radius: float, h: float, segments: int, col: Color, cap_bottom: bool = true, phase: float = 0.0) -> void:
	var seg := maxi(3, segments)
	var apex := base + Vector3(0, h, 0)
	var ring: PackedVector3Array = []
	for i in seg:
		var a := phase + TAU * float(i) / float(seg)
		ring.append(base + Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	for i in seg:
		add_tri(ring[i], ring[(i + 1) % seg], apex, col)
	if cap_bottom:
		for i in seg:
			add_tri(base, ring[(i + 1) % seg], ring[i], col)

func add_tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	_tri(a, b, c, col)

## 三角棱柱（人字屋顶）：宽 2hx，脊高 hy，长 2hz，中心在底面中心
func add_prism(center_bottom: Vector3, half_w: float, ridge_h: float, half_l: float, col: Color, xf: Transform3D = Transform3D.IDENTITY) -> void:
	var hx := half_w
	var hy := ridge_h
	var hz := half_l
	push_transform(Transform3D(xf.basis, xf.origin + center_bottom))
	var L0 := Vector3(-hx, 0, -hz)
	var L1 := Vector3(hx, 0, -hz)
	var L2 := Vector3(0, hy, -hz)
	var R0 := Vector3(-hx, 0, hz)
	var R1 := Vector3(hx, 0, hz)
	var R2 := Vector3(0, hy, hz)
	add_tri(L0, L1, L2, col)          # -Z 山墙
	add_tri(R0, R2, R1, col)          # +Z 山墙
	add_quad(L1, R1, R2, L2, col)     # +X 坡面
	add_quad(R0, L0, L2, R2, col)     # -X 坡面
	add_quad(L0, R0, R1, L1, col)     # 底面
	pop_transform()

## 金字塔屋顶（四坡顶）：底 2hx * 2hz，顶在中心上方 h
func add_pyramid(center_bottom: Vector3, half_x: float, half_z: float, h: float, col: Color) -> void:
	var a := center_bottom + Vector3(-half_x, 0, -half_z)
	var b := center_bottom + Vector3(half_x, 0, -half_z)
	var c := center_bottom + Vector3(half_x, 0, half_z)
	var d := center_bottom + Vector3(-half_x, 0, half_z)
	var apex := center_bottom + Vector3(0, h, 0)
	add_tri(a, b, apex, col)
	add_tri(b, c, apex, col)
	add_tri(c, d, apex, col)
	add_tri(d, a, apex, col)

## 竖直平面片（旗帜 / 帆布 / 农田色块），用双面（法线朝 +Z 与 -Z 各一份）
func add_flat_quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col: Color) -> void:
	add_quad(p0, p1, p2, p3, col)
	add_quad(p3, p2, p1, p0, col)

## 水平地面片（农田色块），y 稍微抬高避免 z-fighting
func add_ground_quad(corners: Array[Vector3], col: Color) -> void:
	if corners.size() < 4:
		return
	add_quad(corners[0], corners[1], corners[2], corners[3], col)

## 旗帜：旗杆 + 旗面（旗面 alpha = 0.5 触发顶点风动）
func add_flag(base: Vector3, pole_h: float, w: float, h: float, col: Color, pole_col: Color = Color(0.32, 0.26, 0.2)) -> void:
	add_cylinder(base, 0.09, 0.07, pole_h, 5, pole_col, false, false)
	var top := base.y + pole_h
	var fb := Vector3(base.x, top - h, base.z)
	var flag_col := Color(col.r, col.g, col.b, 0.5)
	add_flat_quad(
		Vector3(fb.x, fb.y, fb.z),
		Vector3(fb.x + w, fb.y, fb.z),
		Vector3(fb.x + w, fb.y + h, fb.z),
		Vector3(fb.x, fb.y + h, fb.z),
		flag_col)

func build() -> ArrayMesh:
	if idx.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

static func to_color(c: Color) -> Color:
	## 普通建材（alpha = 0）
	return Color(c.r, c.g, c.b, 0.0)

static func to_window(c: Color) -> Color:
	## 窗户：夜间自发光（alpha = 1）
	return Color(c.r, c.g, c.b, 1.0)

static func to_flag(c: Color) -> Color:
	## 旗帜：顶点风动（alpha = 0.5）
	return Color(c.r, c.g, c.b, 0.5)
