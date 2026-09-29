## =============================================================================
##  FighterRig —— 程序化「骨骼部件」绘制器
##   · 没有任何外部素材：一根骨头 = 一个多边形，全部由代码在 _draw() 里算出来
##   · 姿势(pose) = 一组关节角度；姿势之间线性插值 = 关键帧动画
##   · 同一个绘制函数同时给玩家（64px 骑士）和 Boss（192px 重甲巨人）用，
##     区别只在 profile（体型）与 palette（配色）
##
##  角度约定：limb_dir(a) = (sin a, cos a)，a = 0 表示「竖直向下」，正值 = 朝角色正面
##           torso 用 up_dir(t) = (sin t, -cos t)，t = 0 表示竖直向上
##           膝盖/手肘是相对父关节的附加角，自然弯曲时膝盖为负、手肘为正
## =============================================================================
class_name FighterRig
extends Node2D

const KEYS := ["hip_x", "hip_y", "torso", "head", "arm_f", "elb_f", "arm_b", "elb_b",
	"leg_f", "kne_f", "leg_b", "kne_b", "wpn", "rot", "sy"]

var prof: Dictionary = {}
var pal: Dictionary = {}
var pose: Dictionary = {}
var flash: float = 0.0
var glow: float = 0.0            ## 蓄力发光强度 0~1

func setup(p_prof: Dictionary, p_pal: Dictionary) -> void:
	prof = p_prof
	pal = p_pal
	pose = RigPoses.neutral()
	queue_redraw()

func set_pose(p: Dictionary) -> void:
	pose = p
	queue_redraw()

func set_flash(v: float) -> void:
	flash = clampf(v, 0.0, 1.0)
	queue_redraw()

func set_glow(v: float) -> void:
	glow = clampf(v, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	draw_rig(self, prof, pose, pal, flash, glow)

# =============================================================== 正向运动学
static func dir_of(a: float) -> Vector2:
	return Vector2(sin(a), cos(a))

static func up_of(t: float) -> Vector2:
	return Vector2(sin(t), -cos(t))

## 由 profile + pose 解算出所有关节位置（脚底为原点，y 向上为负）
static func joints(p: Dictionary, pose: Dictionary) -> Dictionary:
	var hl: float = float(p["hip_y"])
	var hip := Vector2(float(pose.get("hip_x", 0.0)), hl + float(pose.get("hip_y", 0.0)))
	var torso_a: float = float(pose["torso"])
	var head_a: float = float(pose["head"])
	var tlen: float = float(p["torso_len"])
	var nlen: float = float(p["neck_len"])
	var hrad: float = float(p["head_r"])
	var ua: float = float(p["upper_arm"])
	var la: float = float(p["lower_arm"])
	var ul: float = float(p["upper_leg"])
	var ll: float = float(p["lower_leg"])

	var sh := hip + up_of(torso_a) * tlen
	var nk := sh + up_of(torso_a + head_a * 0.6) * nlen
	var hc := nk + up_of(torso_a + head_a) * (hrad * 0.85)

	var eb_f := sh + dir_of(float(pose["arm_f"])) * ua
	var hd_f := eb_f + dir_of(float(pose["arm_f"]) + float(pose["elb_f"])) * la
	var eb_b := sh + dir_of(float(pose["arm_b"])) * ua
	var hd_b := eb_b + dir_of(float(pose["arm_b"]) + float(pose["elb_b"])) * la

	var kn_f := hip + dir_of(float(pose["leg_f"])) * ul
	var ft_f := kn_f + dir_of(float(pose["leg_f"]) + float(pose["kne_f"])) * ll
	var kn_b := hip + dir_of(float(pose["leg_b"])) * ul
	var ft_b := kn_b + dir_of(float(pose["leg_b"]) + float(pose["kne_b"])) * ll

	var out := {
		"hip": hip, "sh": sh, "nk": nk, "head": hc,
		"eb_f": eb_f, "hd_f": hd_f, "eb_b": eb_b, "hd_b": hd_b,
		"kn_f": kn_f, "ft_f": ft_f, "kn_b": kn_b, "ft_b": ft_b,
	}
	# 整体旋转（闪避翻滚 / 倒地）以髋部为轴，再按 sy 压扁（落地缓冲）
	var rot: float = float(pose.get("rot", 0.0))
	var sy: float = float(pose.get("sy", 1.0))
	for k in out.keys():
		var v: Vector2 = out[k]
		v.y *= sy
		if absf(rot) > 0.0001:
			var rel: Vector2 = v - hip
			var c := cos(rot)
			var sn := sin(rot)
			v = hip + Vector2(rel.x * c - rel.y * sn, rel.x * sn + rel.y * c)
		out[k] = v
	# 武器：从持剑手握把出发
	var hand: Vector2 = out["hd_f"]
	var wl: float = float(p["weapon_len"])
	var wa: float = float(pose["wpn"])
	out["wpn_tip"] = hand + dir_of(wa) * wl
	out["wpn_guard"] = hand + dir_of(wa) * (wl * 0.14)
	return out

# =============================================================== 绘制
static func mixc(c: Color, flash: float) -> Color:
	if flash <= 0.001:
		return c
	return c.lerp(Color(1, 1, 1, c.a), flash)

static func _seg(ci: CanvasItem, a: Vector2, b: Vector2, w0: float, w1: float, col: Color, outline: Color, olw: float = 1.2) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.0001:
		return
	var n := Vector2(-d.y, d.x) / l
	var pts := PackedVector2Array([
		a + n * (w0 * 0.5), b + n * (w1 * 0.5), b - n * (w1 * 0.5), a - n * (w0 * 0.5)])
	if outline.a > 0.0:
		var o := pts.duplicate()
		for i in o.size():
			o[i] = o[i] + (o[i] - (a + b) * 0.5).normalized() * olw
		ci.draw_colored_polygon(o, outline)
	ci.draw_colored_polygon(pts, col)

static func _poly(ci: CanvasItem, pts: PackedVector2Array, col: Color, outline: Color, olw: float = 1.2) -> void:
	if outline.a > 0.0 and olw > 0.0:
		var o := PackedVector2Array()
		var c := Vector2.ZERO
		for p in pts:
			c += p
		c /= float(pts.size())
		for p in pts:
			o.append(p + (p - c).normalized() * olw)
		ci.draw_colored_polygon(o, outline)
	ci.draw_colored_polygon(pts, col)

static func _circle(ci: CanvasItem, c: Vector2, r: float, col: Color, outline: Color, seg: int = 12) -> void:
	var pts := PackedVector2Array()
	for i in seg:
		var a := TAU * float(i) / float(seg)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	_poly(ci, pts, col, outline, 1.4)

static func draw_rig(ci: CanvasItem, p: Dictionary, pose: Dictionary, pal: Dictionary, flash: float, glow: float = 0.0) -> void:
	var j := joints(p, pose)
	var outline: Color = pal.get("outline", Color(0.05, 0.05, 0.08, 0.85))
	var lw: float = p.get("limb_w", 5.0)
	var cs: float = p.get("cloth_scale", 1.0)
	var in_air_extra: float = 0.0

	# ---------------- 披风（最底层） ----------------
	if p.get("has_cape", false):
		var sh: Vector2 = j["sh"]
		var hip: Vector2 = j["hip"]
		var sway: float = float(pose.get("torso", 0.0)) * 0.8 + 0.25
		var cl: float = float(p.get("cape_len", 34.0)) * cs
		var cp := PackedVector2Array([
			sh + Vector2(-9, -2) * cs,
			sh + Vector2(7, -2) * cs,
			hip + Vector2(11 + sway * 16.0, cl),
			hip + Vector2(-15 + sway * 10.0, cl * 0.85),
		])
		_poly(ci, cp, mixc(pal.get("cape", Color(0.5, 0.1, 0.1)), flash * 0.7), outline, 1.0)

	# ---------------- 后腿 / 后臂 ----------------
	var back := mixc(pal.get("armor_dark", Color(0.35, 0.33, 0.4)), flash * 0.75)
	_seg(ci, j["hip"], j["kn_b"], lw * 1.05, lw * 0.92, back, outline)
	_seg(ci, j["kn_b"], j["ft_b"], lw * 0.92, lw * 0.78, mixc(pal.get("armor_dark", back).darkened(0.12), flash * 0.7), outline)
	_draw_boot(ci, j["ft_b"], pose.get("leg_b", 0.0) + pose.get("kne_b", 0.0), p, mixc(pal.get("boot", Color(0.22, 0.2, 0.26)), flash * 0.7), outline)
	_seg(ci, j["sh"], j["eb_b"], lw * 0.95, lw * 0.82, back, outline)
	_seg(ci, j["eb_b"], j["hd_b"], lw * 0.82, lw * 0.7, back, outline)
	_circle(ci, j["hd_b"], lw * 0.55, mixc(pal.get("armor_dark", back), flash * 0.7), outline, 8)

	# ---------------- 躯干 ----------------
	var hip: Vector2 = j["hip"]
	var sh: Vector2 = j["sh"]
	var tw: float = p.get("torso_w", 13.0)
	var tp := PackedVector2Array([
		hip + Vector2(-tw * 0.42, 0), hip + Vector2(tw * 0.42, 0),
		sh + Vector2(tw * 0.56, 0), sh + Vector2(-tw * 0.56, 0)])
	_poly(ci, tp, mixc(pal.get("armor", Color(0.6, 0.62, 0.7)), flash), outline, 1.4)
	# 胸甲高光 / 腰带
	_poly(ci, PackedVector2Array([
		hip + Vector2(-tw * 0.42, -2), hip + Vector2(tw * 0.42, -2),
		hip + Vector2(tw * 0.36, 2), hip + Vector2(-tw * 0.36, 2)]),
		mixc(pal.get("belt", Color(0.3, 0.22, 0.16)), flash * 0.8), Color(0, 0, 0, 0))
	var chest := PackedVector2Array([
		sh + Vector2(-tw * 0.5, 3), sh + Vector2(tw * 0.5, 3),
		hip + Vector2(tw * 0.3, -tw * 0.35), hip + Vector2(-tw * 0.3, -tw * 0.35)])
	_poly(ci, chest, mixc(pal.get("armor_light", pal.get("armor", Color(0.7, 0.72, 0.8))), flash), Color(0, 0, 0, 0))

	# ---------------- 护肩 ----------------
	if p.get("has_pauldrons", false):
		for sgn in [-1.0, 1.0]:
			var sp: Vector2 = sh + Vector2(sgn * tw * 0.5, 1.5)
			_circle(ci, sp, tw * 0.42 * p.get("pauldron_scale", 1.0), mixc(pal.get("armor_light", Color(0.7, 0.72, 0.82)), flash), outline, 9)

	# ---------------- 头 ----------------
	var hc: Vector2 = j["head"]
	var hr: float = p["head_r"]
	var hrot: float = pose["torso"] + pose["head"]
	_circle(ci, hc, hr, mixc(pal.get("skin", Color(0.85, 0.68, 0.55)), flash), outline, 14)
	# 头盔（骑士全盔 / Boss 尖角盔）
	if p.get("helmet", true):
		var hp2 := PackedVector2Array()
		for i in 9:
			var a2 := PI + PI * float(i) / 8.0
			hp2.append(hc + Vector2(cos(a2), sin(a2) * 0.95) * hr * 1.12)
		hp2.append(hc + Vector2(hr * 1.1, hr * 0.15))
		hp2.append(hc + Vector2(-hr * 1.1, hr * 0.15))
		_poly(ci, hp2, mixc(pal.get("helmet_col", pal.get("armor", Color(0.65, 0.67, 0.75))), flash), outline, 1.3)
		# 面甲缝隙
		var vis := PackedVector2Array([
			hc + Vector2(dir_of(hrot).x * hr * 0.55, -hr * 0.18),
			hc + Vector2(dir_of(hrot).x * hr * 1.06, -hr * 0.05),
			hc + Vector2(dir_of(hrot).x * hr * 1.06, hr * 0.28),
			hc + Vector2(dir_of(hrot).x * hr * 0.5, hr * 0.3)])
		_poly(ci, vis, mixc(pal.get("visor", Color(0.1, 0.12, 0.18)), flash * 0.5), Color(0, 0, 0, 0))
	if p.get("has_horns", false):
		for sgn2 in [-1.0, 1.0]:
			var base := hc + Vector2(sgn2 * hr * 0.75, -hr * 0.5)
			# 用三角形（保证不自交，凸多边形三角化必定成功）
			_poly(ci, PackedVector2Array([
				base + Vector2(-sgn2 * 5.0, 3.0), base + Vector2(sgn2 * 5.0, 3.0),
				base + Vector2(sgn2 * hr * 1.25, -hr * 1.45)]),
				mixc(pal.get("horn", Color(0.75, 0.7, 0.6)), flash), outline, 1.0)
	# 眼睛发光（Boss）
	if float(pal.get("eye_glow", 0.0)) > 0.01:
		var ex := hc + Vector2(dir_of(hrot).x * hr * 0.62, hr * 0.05)
		_circle(ci, ex, hr * 0.22, pal.get("eye", Color(1.0, 0.25, 0.15)), Color(0, 0, 0, 0), 8)

	# ---------------- 前腿 ----------------
	var front := mixc(pal.get("armor", Color(0.6, 0.62, 0.7)), flash)
	_seg(ci, j["hip"], j["kn_f"], lw * 1.15, lw * 1.0, front, outline)
	_seg(ci, j["kn_f"], j["ft_f"], lw * 1.0, lw * 0.85, mixc(pal.get("armor", front).darkened(0.06), flash), outline)
	_draw_boot(ci, j["ft_f"], pose.get("leg_f", 0.0) + pose.get("kne_f", 0.0), p, mixc(pal.get("boot", Color(0.24, 0.22, 0.28)), flash), outline)

	# ---------------- 前臂 ----------------
	_seg(ci, j["sh"], j["eb_f"], lw * 1.05, lw * 0.9, mixc(pal.get("armor_light", front), flash), outline)
	_seg(ci, j["eb_f"], j["hd_f"], lw * 0.9, lw * 0.75, mixc(pal.get("armor", front), flash), outline)
	_circle(ci, j["hd_f"], lw * 0.62, mixc(pal.get("glove", Color(0.3, 0.26, 0.3)), flash * 0.8), outline, 8)

	# ---------------- 武器 ----------------
	_draw_weapon(ci, p, j, pose, pal, flash, glow)

static func _draw_boot(ci: CanvasItem, foot: Vector2, ang: float, p: Dictionary, col: Color, outline: Color) -> void:
	var d := dir_of(ang + PI * 0.5)
	var s: float = p.get("boot_len", 9.0)
	var pts := PackedVector2Array([
		foot + d * s * 0.9 + Vector2(0, -2.4),
		foot + d * s * 0.9 + Vector2(0, 2.4),
		foot - d * s * 0.25 + Vector2(0, 2.6),
		foot - d * s * 0.25 + Vector2(0, -2.4)])
	_poly(ci, pts, col, outline, 1.0)

static func _draw_weapon(ci: CanvasItem, p: Dictionary, j: Dictionary, pose: Dictionary, pal: Dictionary, flash: float, glow: float) -> void:
	var kind: String = p.get("weapon", "sword")
	if kind == "none":
		return
	if pose.get("hide_weapon", 0.0) > 0.5:
		return
	var hand: Vector2 = j["hd_f"]
	var wa: float = pose["wpn"]
	var d := dir_of(wa)
	var n := Vector2(-d.y, d.x)
	var wl: float = p["weapon_len"]
	var ww: float = p.get("weapon_w", 3.4)

	if kind == "sword":
		# 剑柄
		_seg(ci, hand - d * 3.0, hand + d * wl * 0.16, ww * 0.55, ww * 0.5,
			mixc(pal.get("grip", Color(0.28, 0.2, 0.14)), flash), Color(0, 0, 0, 0))
		# 护手
		var g := hand + d * wl * 0.14
		_seg(ci, g - n * ww * 2.1, g + n * ww * 2.1, ww * 0.62, ww * 0.62,
			mixc(pal.get("metal_dark", Color(0.35, 0.36, 0.42)), flash), Color(0, 0, 0, 0))
		# 剑身
		var tip := hand + d * wl
		var blade := PackedVector2Array([
			g + n * ww * 0.62, tip + n * ww * 0.12, tip - n * ww * 0.12, g - n * ww * 0.62])
		var bc: Color = mixc(pal.get("metal", Color(0.78, 0.8, 0.88)), flash)
		if glow > 0.01:
			var gp := PackedVector2Array()
			for v in blade:
				gp.append(v + (v - hand).normalized() * (2.0 + 7.0 * glow))
			ci.draw_colored_polygon(gp, Color(0.55, 0.8, 1.0, 0.20 + 0.45 * glow))
			bc = bc.lerp(Color(0.75, 0.92, 1.0), glow * 0.75)
		_poly(ci, blade, bc, mixc(pal.get("metal_dark", Color(0.3, 0.32, 0.38)), flash * 0.6), 0.9)
		# 中脊高光
		_seg(ci, g + d * 2.0, hand + d * wl * 0.92, ww * 0.22, ww * 0.1,
			Color(1, 1, 1, 0.35 + 0.4 * glow), Color(0, 0, 0, 0))
	elif kind == "axe":
		_seg(ci, hand - d * 4.0, hand + d * wl, ww * 0.7, ww * 0.62,
			mixc(pal.get("grip", Color(0.3, 0.22, 0.15)), flash), Color(0, 0, 0, 0))
		var head_c := hand + d * wl * 0.86
		var bl := PackedVector2Array([
			head_c - n * ww * 0.9 + d * 3.0,
			head_c + n * ww * 6.2 + d * 9.0,
			head_c + n * ww * 7.0 - d * 8.0,
			head_c - n * ww * 0.9 - d * 6.0])
		var ac: Color = mixc(pal.get("metal", Color(0.7, 0.72, 0.8)), flash)
		if glow > 0.01:
			ac = ac.lerp(Color(1.0, 0.45, 0.35), glow * 0.8)
		_poly(ci, bl, ac, mixc(pal.get("metal_dark", Color(0.3, 0.32, 0.38)), flash * 0.6), 1.0)
		# 斧背尖刺
		_poly(ci, PackedVector2Array([
			head_c - n * ww * 0.9 + d * 1.0, head_c - n * ww * 0.9 - d * 2.0,
			head_c - n * ww * 3.4]), mixc(pal.get("metal_dark", Color(0.4, 0.4, 0.45)), flash), Color(0, 0, 0, 0))
