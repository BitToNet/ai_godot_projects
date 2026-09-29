## =============================================================================
##  PartyModelBuilder —— 用基础几何体拼出「骑马小人」
##  马 + 骑手全部由方块 / 圆球 / 圆柱组合，顶点色区分材质，
##  朝 +(-Z) 方向建模（与 Node3D.look_at 的约定一致）。
## =============================================================================
class_name PartyModelBuilder
extends RefCounted

const HORSE_DARK := Color(0.26, 0.19, 0.13)
const HORSE_BROWN := Color(0.42, 0.28, 0.16)
const HORSE_BLACK := Color(0.16, 0.15, 0.16)
const HORSE_WHITE := Color(0.76, 0.73, 0.68)
const HOOF := Color(0.13, 0.11, 0.10)
const LEATHER := Color(0.34, 0.24, 0.15)
const METAL := Color(0.66, 0.68, 0.72)
const SKIN := Color(0.78, 0.60, 0.46)

## kind: "player" / "lord" / "caravan" / "bandit"
static func build(kind: String, faction_color: Color, body: Color, cape: Color) -> ArrayMesh:
	var k := MeshKit.new()
	var horse := body
	match kind:
		"bandit":
			horse = HORSE_BLACK if randf_seed(kind, 1) < 0.5 else HORSE_DARK
		"caravan":
			horse = HORSE_BROWN
		"player":
			horse = HORSE_BROWN
		_:
			horse = HORSE_WHITE if randf_seed(kind, 2) < 0.35 else HORSE_BROWN

	var c_horse := MeshKit.to_color(horse)
	var c_dark := MeshKit.to_color(horse.darkened(0.3))
	var c_hoof := MeshKit.to_color(HOOF)

	# ---------------- 马身（面朝 -Z） ----------------
	k.add_box(Vector3(0, 1.18, 0.05), Vector3(0.70, 0.80, 1.85), c_horse, c_horse.lightened(0.05))
	# 前胸
	k.add_box(Vector3(0, 1.28, -0.85), Vector3(0.62, 0.66, 0.5), c_horse)
	# 后臀
	k.add_box(Vector3(0, 1.30, 0.92), Vector3(0.58, 0.62, 0.45), c_horse)
	# 脖子（向前下方倾斜）
	k.push_transform(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(38.0)), Vector3(0, 1.62, -0.86)))
	k.add_box(Vector3(0, 0.3, 0), Vector3(0.36, 0.95, 0.42), c_horse)
	k.pop_transform()
	# 头
	k.add_box(Vector3(0, 2.02, -1.32), Vector3(0.30, 0.34, 0.62), c_dark)
	# 耳朵
	k.add_box(Vector3(0.11, 2.26, -1.18), Vector3(0.09, 0.2, 0.09), c_dark)
	k.add_box(Vector3(-0.11, 2.26, -1.18), Vector3(0.09, 0.2, 0.09), c_dark)
	# 鬃毛
	k.add_box(Vector3(0, 1.95, -0.62), Vector3(0.14, 0.9, 0.5), MeshKit.to_color(horse.darkened(0.45)))
	# 四条腿
	for lx in [0.25, -0.25]:
		for lz in [-0.62, 0.62]:
			k.add_box(Vector3(lx, 0.62, lz), Vector3(0.17, 1.05, 0.19), c_horse)
			k.add_box(Vector3(lx, 0.09, lz), Vector3(0.19, 0.20, 0.21), c_hoof)
	# 尾巴
	k.push_transform(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-32.0)), Vector3(0, 1.42, 1.1)))
	k.add_box(Vector3(0, -0.42, 0), Vector3(0.16, 0.95, 0.16), c_dark)
	k.pop_transform()
	# 马鞍
	k.add_box(Vector3(0, 1.60, 0.05), Vector3(0.62, 0.14, 0.85), MeshKit.to_color(LEATHER))
	k.add_box(Vector3(0, 1.66, -0.28), Vector3(0.5, 0.22, 0.14), MeshKit.to_color(LEATHER.darkened(0.2)))

	# ---------------- 骑手 ----------------
	var c_tunic := MeshKit.to_color(cape)
	var c_tunic_d := MeshKit.to_color(cape.darkened(0.25))
	# 大腿（跨坐两侧）
	k.add_box(Vector3(0.42, 1.62, 0.16), Vector3(0.22, 0.72, 0.26), c_tunic_d)
	k.add_box(Vector3(-0.42, 1.62, 0.16), Vector3(0.22, 0.72, 0.26), c_tunic_d)
	# 靴子
	k.add_box(Vector3(0.44, 1.24, 0.02), Vector3(0.24, 0.22, 0.42), MeshKit.to_color(LEATHER.darkened(0.3)))
	k.add_box(Vector3(-0.44, 1.24, 0.02), Vector3(0.24, 0.22, 0.42), MeshKit.to_color(LEATHER.darkened(0.3)))
	# 躯干
	k.add_box(Vector3(0, 2.18, 0.06), Vector3(0.56, 0.74, 0.38), c_tunic)
	# 胸甲 / 束带
	k.add_box(Vector3(0, 2.24, -0.14), Vector3(0.5, 0.5, 0.12), MeshKit.to_color(METAL.darkened(0.25)))
	k.add_box(Vector3(0, 2.10, 0.06), Vector3(0.60, 0.12, 0.42), MeshKit.to_color(LEATHER))
	# 头 + 头盔
	k.add_sphere(Vector3(0, 2.72, 0.02), 0.20, 7, 5, MeshKit.to_color(SKIN))
	k.add_sphere(Vector3(0, 2.78, 0.02), 0.215, 7, 4, MeshKit.to_color(METAL))
	k.add_box(Vector3(0, 2.66, -0.16), Vector3(0.34, 0.24, 0.06), MeshKit.to_color(METAL.darkened(0.2)))
	# 手臂
	k.push_transform(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(28.0)), Vector3(0.34, 2.36, 0.02)))
	k.add_box(Vector3(0, -0.2, 0), Vector3(0.16, 0.6, 0.18), c_tunic_d)
	k.pop_transform()
	k.push_transform(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-18.0)), Vector3(-0.34, 2.30, -0.1)))
	k.add_box(Vector3(0, -0.24, 0), Vector3(0.16, 0.62, 0.18), c_tunic_d)
	k.pop_transform()
	# 披风（alpha = 0.5 → 顶点风动）
	k.add_flat_quad(Vector3(-0.36, 2.5, 0.32), Vector3(0.36, 2.5, 0.32),
		Vector3(0.44, 1.5, 0.42), Vector3(-0.44, 1.5, 0.42), MeshKit.to_flag(cape))
	# 圆盾（左臂）
	k.push_transform(Transform3D(Basis(Vector3.FORWARD, deg_to_rad(90.0)), Vector3(-0.52, 2.2, -0.12)))
	k.add_cylinder(Vector3.ZERO, 0.40, 0.40, 0.1, 8, MeshKit.to_color(faction_color.darkened(0.1)))
	k.add_cylinder(Vector3(0, 0.1, 0), 0.16, 0.12, 0.08, 6, MeshKit.to_color(METAL))
	k.pop_transform()

	var flag_scale := 1.0
	match kind:
		"lord", "player":
			# 长枪
			k.push_transform(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-14.0)), Vector3(0.42, 2.1, -0.2)))
			k.add_cylinder(Vector3(0, -1.3, 0), 0.06, 0.05, 3.4, 5, MeshKit.to_color(LEATHER.darkened(0.1)))
			k.add_cone(Vector3(0, 2.1, 0), 0.11, 0.5, 5, MeshKit.to_color(METAL))
			k.pop_transform()
		"bandit":
			# 弯刀
			k.add_box(Vector3(0.5, 2.72, -0.35), Vector3(0.07, 0.75, 0.12), MeshKit.to_color(METAL.darkened(0.1)))
			k.add_box(Vector3(0.5, 2.30, -0.35), Vector3(0.12, 0.2, 0.14), MeshKit.to_color(LEATHER.darkened(0.3)))
	# 旗手（领主/玩家举旗，商队挂小旗）
	if kind == "lord" or kind == "player":
		k.add_flag(Vector3(-0.42, 2.0, 0.3), 3.6 * flag_scale, 1.5, 0.95, faction_color)
	# 商队的驮包
	if kind == "caravan":
		k.add_box(Vector3(0, 1.86, 0.95), Vector3(0.72, 0.5, 0.62), MeshKit.to_color(LEATHER))
		k.add_box(Vector3(0, 1.86, 0.35), Vector3(0.72, 0.44, 0.5), MeshKit.to_color(LEATHER.lightened(0.1)))
	return k.build()

## 商队货车（由 Main 作为独立 MeshInstance3D 挂在商队节点下）
static func build_cart() -> ArrayMesh:
	var k := MeshKit.new()
	var wood := MeshKit.to_color(Color(0.40, 0.29, 0.18))
	k.add_box(Vector3(0, 1.15, 0), Vector3(2.6, 1.3, 4.6), wood)
	k.add_box(Vector3(0, 0.5, 0), Vector3(3.0, 0.35, 5.0), MeshKit.to_color(Color(0.30, 0.22, 0.14)))
	# 帆布顶
	k.add_prism(Vector3(0, 1.8, 0), 1.35, 1.0, 2.3, MeshKit.to_color(Color(0.82, 0.79, 0.70)))
	for sx in [1.5, -1.5]:
		k.push_transform(Transform3D(Basis(Vector3.FORWARD, deg_to_rad(90.0)), Vector3(sx, 0.75, 1.4)))
		k.add_cylinder(Vector3.ZERO, 0.75, 0.75, 0.22, 8, MeshKit.to_color(Color(0.28, 0.20, 0.12)))
		k.pop_transform()
		k.push_transform(Transform3D(Basis(Vector3.FORWARD, deg_to_rad(90.0)), Vector3(sx, 0.75, -1.4)))
		k.add_cylinder(Vector3.ZERO, 0.75, 0.75, 0.22, 8, MeshKit.to_color(Color(0.28, 0.20, 0.12)))
		k.pop_transform()
	return k.build()

static func randf_seed(tag: String, salt: int) -> float:
	var h := hash(tag + str(salt))
	return float(absi(h) % 1000) / 1000.0
