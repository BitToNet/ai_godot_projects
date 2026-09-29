## =============================================================================
##  RigPoses —— 玩家骑士 / Boss 巨人的「骨骼姿势库」
##  每个姿势就是一组关节角度（见 FighterRig 的角度约定），动作由关键姿势插值得到，
##  因此每个动作都有可辨识的剪影：蓄力抬手、横斩、回斩、突刺、翻滚、弹反、倒地……
## =============================================================================
class_name RigPoses
extends RefCounted

# ---------------------------------------------------------------- 体型
static func player_profile() -> Dictionary:
	return {
		"height": 64.0, "hip_y": -28.0, "torso_len": 17.0, "neck_len": 4.0, "head_r": 7.6,
		"upper_arm": 11.0, "lower_arm": 11.0, "upper_leg": 15.0, "lower_leg": 15.0,
		"limb_w": 5.0, "torso_w": 13.0, "boot_len": 8.5,
		"weapon": "sword", "weapon_len": 32.0, "weapon_w": 3.4,
		"helmet": true, "has_cape": true, "cape_len": 30.0, "cloth_scale": 1.0,
		"has_pauldrons": true, "pauldron_scale": 1.0, "has_horns": false,
	}

## 敌人首领体型：lord 重甲巨人 / bandit 悍匪头目 / caravan 商队护卫长
static func boss_profile(kind: String = "lord") -> Dictionary:
	var d := {
		"height": 192.0, "hip_y": -86.0, "torso_len": 52.0, "neck_len": 10.0, "head_r": 20.0,
		"upper_arm": 34.0, "lower_arm": 32.0, "upper_leg": 44.0, "lower_leg": 42.0,
		"limb_w": 15.0, "torso_w": 42.0, "boot_len": 22.0,
		"weapon": "axe", "weapon_len": 96.0, "weapon_w": 8.0,
		"helmet": true, "has_cape": true, "cape_len": 52.0, "cloth_scale": 1.15,
		"has_pauldrons": true, "pauldron_scale": 1.55, "has_horns": true,
	}
	match kind:
		"bandit":
			d.merge({
				"height": 176.0, "hip_y": -78.0, "torso_len": 47.0, "neck_len": 9.0, "head_r": 18.5,
				"upper_arm": 31.0, "lower_arm": 29.0, "upper_leg": 40.0, "lower_leg": 38.0,
				"limb_w": 14.0, "torso_w": 40.0, "boot_len": 20.0,
				"weapon_len": 88.0, "weapon_w": 7.5,
				"cape_len": 30.0, "cloth_scale": 1.0, "pauldron_scale": 1.30,
			}, true)
		"caravan":
			d.merge({
				"height": 164.0, "hip_y": -72.0, "torso_len": 44.0, "neck_len": 9.0, "head_r": 17.5,
				"upper_arm": 29.0, "lower_arm": 27.0, "upper_leg": 37.0, "lower_leg": 36.0,
				"limb_w": 13.0, "torso_w": 37.0, "boot_len": 19.0,
				"weapon": "sword", "weapon_len": 84.0, "weapon_w": 6.0,
				"has_cape": true, "cape_len": 30.0, "cloth_scale": 1.0,
				"has_pauldrons": true, "pauldron_scale": 1.18, "has_horns": false,
			}, true)
	return d

static func player_palette(cape: Color) -> Dictionary:
	return {
		"armor": Color(0.60, 0.64, 0.76), "armor_light": Color(0.78, 0.82, 0.92),
		"armor_dark": Color(0.38, 0.42, 0.54), "skin": Color(0.87, 0.70, 0.57),
		"helmet_col": Color(0.72, 0.76, 0.86), "visor": Color(0.10, 0.12, 0.18),
		"belt": Color(0.36, 0.25, 0.16), "glove": Color(0.30, 0.26, 0.32),
		"boot": Color(0.26, 0.24, 0.32), "metal": Color(0.84, 0.87, 0.94),
		"metal_dark": Color(0.38, 0.41, 0.49), "grip": Color(0.30, 0.22, 0.15),
		"cape": cape, "outline": Color(0.05, 0.05, 0.09, 0.92), "eye_glow": 0.0,
	}

## 敌人配色：lord 紫钢+血红披风 / bandit 皮革+锈铁 / caravan 蓝钢+蓝披风
static func boss_palette(kind: String = "lord") -> Dictionary:
	match kind:
		"bandit":
			return {
				"armor": Color(0.34, 0.26, 0.19), "armor_light": Color(0.47, 0.36, 0.26),
				"armor_dark": Color(0.20, 0.15, 0.11), "skin": Color(0.62, 0.47, 0.37),
				"helmet_col": Color(0.30, 0.23, 0.17), "visor": Color(0.07, 0.05, 0.04),
				"belt": Color(0.19, 0.13, 0.09), "glove": Color(0.27, 0.21, 0.16),
				"boot": Color(0.18, 0.14, 0.11), "metal": Color(0.56, 0.53, 0.48),
				"metal_dark": Color(0.31, 0.28, 0.25), "grip": Color(0.26, 0.18, 0.12),
				"cape": Color(0.20, 0.15, 0.11), "outline": Color(0.05, 0.03, 0.02, 0.95),
				"eye": Color(1.0, 0.76, 0.20), "eye_glow": 0.70, "horn": Color(0.72, 0.65, 0.52),
			}
		"caravan":
			return {
				"armor": Color(0.30, 0.34, 0.44), "armor_light": Color(0.47, 0.53, 0.63),
				"armor_dark": Color(0.18, 0.21, 0.28), "skin": Color(0.80, 0.62, 0.48),
				"helmet_col": Color(0.35, 0.39, 0.49), "visor": Color(0.09, 0.10, 0.13),
				"belt": Color(0.29, 0.22, 0.16), "glove": Color(0.30, 0.27, 0.29),
				"boot": Color(0.22, 0.20, 0.25), "metal": Color(0.70, 0.72, 0.78),
				"metal_dark": Color(0.32, 0.34, 0.40), "grip": Color(0.32, 0.22, 0.14),
				"cape": Color(0.13, 0.27, 0.52), "outline": Color(0.03, 0.04, 0.07, 0.95),
				"eye": Color(0.16, 0.16, 0.20), "eye_glow": 0.0, "horn": Color(0.78, 0.78, 0.80),
			}
	return {
		"armor": Color(0.34, 0.30, 0.37), "armor_light": Color(0.50, 0.43, 0.47),
		"armor_dark": Color(0.21, 0.18, 0.23), "skin": Color(0.52, 0.48, 0.44),
		"helmet_col": Color(0.30, 0.26, 0.31), "visor": Color(0.08, 0.06, 0.08),
		"belt": Color(0.24, 0.16, 0.12), "glove": Color(0.24, 0.20, 0.24),
		"boot": Color(0.19, 0.17, 0.21), "metal": Color(0.62, 0.62, 0.68),
		"metal_dark": Color(0.28, 0.28, 0.33), "grip": Color(0.25, 0.18, 0.12),
		"cape": Color(0.34, 0.07, 0.09), "outline": Color(0.03, 0.02, 0.04, 0.95),
		"eye": Color(1.0, 0.32, 0.14), "eye_glow": 1.0, "horn": Color(0.80, 0.75, 0.66),
	}

## 二阶段：整体染红 + 眼睛更亮
static func boss_phase2(pal: Dictionary) -> Dictionary:
	var p := pal.duplicate()
	for k in ["armor", "armor_light", "armor_dark", "metal", "metal_dark", "helmet_col"]:
		p[k] = (p[k] as Color).lerp(Color(0.55, 0.13, 0.14), 0.42)
	p["cape"] = Color(0.55, 0.08, 0.06)
	p["eye"] = Color(1.0, 0.55, 0.15)
	return p

# ---------------------------------------------------------------- 姿势构造
static func neutral() -> Dictionary:
	return P({})

## 用「只写出差异」的写法构造完整姿势
static func P(over: Dictionary) -> Dictionary:
	var d := {
		"hip_x": 0.0, "hip_y": 0.0, "torso": 0.03, "head": 0.0,
		"arm_f": 0.14, "elb_f": 0.26, "arm_b": -0.12, "elb_b": 0.24,
		"leg_f": 0.07, "kne_f": -0.09, "leg_b": -0.07, "kne_b": -0.11,
		"wpn": -0.55, "rot": 0.0, "sy": 1.0,
	}
	for k in over.keys():
		d[k] = over[k]
	return d

## 两个姿势之间插值
static func mix(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	k = clampf(k, 0.0, 1.0)
	var o := a.duplicate()
	for key in b.keys():
		if o.has(key) and typeof(o[key]) == TYPE_FLOAT and typeof(b[key]) == TYPE_FLOAT:
			o[key] = lerpf(float(a[key]), float(b[key]), k)
		else:
			o[key] = b[key]
	return o

# =============================================================== 玩家姿势
static func player_poses() -> Dictionary:
	var st := P({})
	return {
		"idle_a": st,
		"idle_b": P({"hip_y": -1.2, "torso": 0.06, "arm_f": 0.19, "elb_f": 0.30, "head": -0.03}),
		"run_0": P({"torso": 0.20, "head": -0.06, "arm_f": 0.85, "elb_f": 0.55, "arm_b": -0.75, "elb_b": 0.60,
			"leg_f": 0.62, "kne_f": -0.30, "leg_b": -0.58, "kne_b": -0.55, "hip_y": -2.0, "wpn": -1.05}),
		"run_1": P({"torso": 0.22, "head": -0.06, "arm_f": 0.35, "elb_f": 0.70, "arm_b": -0.30, "elb_b": 0.75,
			"leg_f": 0.12, "kne_f": -0.75, "leg_b": -0.12, "kne_b": -0.25, "hip_y": -3.5, "wpn": -0.95}),
		"run_2": P({"torso": 0.20, "head": -0.06, "arm_f": -0.55, "elb_f": 0.70, "arm_b": 0.65, "elb_b": 0.55,
			"leg_f": -0.55, "kne_f": -0.50, "leg_b": 0.60, "kne_b": -0.30, "hip_y": -2.0, "wpn": -0.85}),
		"run_3": P({"torso": 0.22, "head": -0.06, "arm_f": -0.20, "elb_f": 0.75, "arm_b": 0.25, "elb_b": 0.70,
			"leg_f": -0.15, "kne_f": -0.25, "leg_b": 0.20, "kne_b": -0.72, "hip_y": -3.5, "wpn": -1.00}),
		"jump": P({"torso": -0.10, "arm_f": 1.30, "elb_f": 0.40, "arm_b": 0.95, "elb_b": 0.50,
			"leg_f": 0.55, "kne_f": -1.05, "leg_b": -0.25, "kne_b": -0.85, "hip_y": -3.0, "wpn": 0.55}),
		"fall": P({"torso": 0.10, "arm_f": 1.55, "elb_f": 0.25, "arm_b": -1.20, "elb_b": 0.30,
			"leg_f": 0.40, "kne_f": -0.35, "leg_b": -0.35, "kne_b": -0.30, "wpn": 0.95}),
		"land": P({"sy": 0.86, "hip_y": 2.5, "torso": 0.24, "arm_f": 0.55, "elb_f": 0.80,
			"arm_b": -0.50, "elb_b": 0.70, "leg_f": 0.30, "kne_f": -0.85, "leg_b": -0.30, "kne_b": -0.80, "wpn": -0.30}),
		# 三段普攻
		"a1_wind": P({"torso": -0.16, "head": 0.10, "arm_f": 2.05, "elb_f": -0.55, "arm_b": -0.55, "elb_b": 0.35,
			"leg_f": 0.18, "kne_f": -0.20, "leg_b": -0.22, "kne_b": -0.24, "wpn": -1.35, "hip_x": -3.0}),
		"a1_hit": P({"torso": 0.34, "head": 0.12, "arm_f": 1.62, "elb_f": 0.05, "arm_b": -1.15, "elb_b": 0.30,
			"leg_f": 0.55, "kne_f": -0.28, "leg_b": -0.45, "kne_b": -0.30, "wpn": 1.42, "hip_x": 5.0}),
		"a2_wind": P({"torso": -0.05, "head": 0.14, "arm_f": 0.30, "elb_f": 0.20, "arm_b": 1.35, "elb_b": -0.40,
			"leg_f": 0.32, "kne_f": -0.30, "leg_b": -0.30, "kne_b": -0.26, "wpn": -1.85, "hip_x": -2.0}),
		"a2_hit": P({"torso": 0.28, "head": -0.10, "arm_f": 2.35, "elb_f": 0.10, "arm_b": -1.30, "elb_b": 0.25,
			"leg_f": 0.40, "kne_f": -0.30, "leg_b": -0.35, "kne_b": -0.30, "wpn": 2.25, "hip_x": 4.0}),
		"a3_wind": P({"torso": 0.34, "head": -0.12, "arm_f": -0.35, "elb_f": 0.95, "arm_b": 0.85, "elb_b": 0.55,
			"leg_f": 0.50, "kne_f": -0.75, "leg_b": -0.48, "kne_b": -0.70, "wpn": 0.10, "hip_x": -7.0, "hip_y": 1.5}),
		"a3_hit": P({"torso": 0.46, "head": -0.16, "arm_f": 1.50, "elb_f": 0.06, "arm_b": -0.35, "elb_b": 0.85,
			"leg_f": 0.85, "kne_f": -0.20, "leg_b": -0.72, "kne_b": -0.35, "wpn": 1.57, "hip_x": 12.0, "hip_y": -1.0}),
		# 空中斩
		"air_wind": P({"torso": -0.22, "arm_f": 2.45, "elb_f": -0.65, "arm_b": 0.60, "elb_b": 0.40,
			"leg_f": 0.60, "kne_f": -1.15, "leg_b": -0.30, "kne_b": -0.90, "wpn": -1.55}),
		"air_hit": P({"torso": 0.38, "arm_f": 1.15, "elb_f": 0.20, "arm_b": -0.90, "elb_b": 0.30,
			"leg_f": 0.20, "kne_f": -0.45, "leg_b": -0.30, "kne_b": -0.75, "wpn": 1.75}),
		# 闪避（三段：下蹲 → 翻滚 → 起身）
		"dodge_0": P({"sy": 0.80, "hip_y": 4.0, "torso": 0.48, "head": -0.20, "arm_f": 0.65, "elb_f": 1.05,
			"arm_b": -0.60, "elb_b": 0.90, "leg_f": 0.70, "kne_f": -1.25, "leg_b": -0.60, "kne_b": -1.10, "wpn": -0.10}),
		"dodge_1": P({"rot": 1.35, "hip_y": 3.0, "torso": 0.55, "head": 0.10, "arm_f": 1.10, "elb_f": 1.20,
			"arm_b": -0.90, "elb_b": 1.10, "leg_f": 0.95, "kne_f": -1.45, "leg_b": -0.75, "kne_b": -1.35, "wpn": -0.20}),
		"dodge_2": P({"rot": 2.55, "hip_y": 3.0, "torso": 0.50, "head": 0.10, "arm_f": 1.15, "elb_f": 1.15,
			"arm_b": -0.95, "elb_b": 1.05, "leg_f": 0.90, "kne_f": -1.40, "leg_b": -0.70, "kne_b": -1.30, "wpn": -0.25}),
		"dodge_3": P({"sy": 0.88, "hip_y": 2.0, "torso": 0.30, "arm_f": 0.45, "elb_f": 0.85,
			"leg_f": 0.35, "kne_f": -0.70, "leg_b": -0.35, "kne_b": -0.60, "wpn": -0.45}),
		# 弹反
		"parry": P({"torso": -0.10, "head": 0.06, "arm_f": 1.25, "elb_f": 0.85, "arm_b": 0.35, "elb_b": 1.15,
			"leg_f": 0.25, "kne_f": -0.30, "leg_b": -0.25, "kne_b": -0.28, "wpn": 1.50}),
		"parry_ok": P({"torso": -0.24, "head": 0.12, "arm_f": 1.65, "elb_f": 0.45, "arm_b": 0.15, "elb_b": 1.20,
			"leg_f": 0.40, "kne_f": -0.35, "leg_b": -0.40, "kne_b": -0.30, "wpn": 1.85, "hip_x": -4.0}),
		# 蓄力剑气
		"charge": P({"torso": -0.14, "head": 0.05, "arm_f": 2.60, "elb_f": 0.30, "arm_b": 2.35, "elb_b": 0.45,
			"leg_f": 0.30, "kne_f": -0.55, "leg_b": -0.30, "kne_b": -0.50, "wpn": -1.62, "hip_y": 1.0}),
		"charge_full": P({"torso": -0.20, "head": 0.08, "arm_f": 2.75, "elb_f": 0.20, "arm_b": 2.50, "elb_b": 0.35,
			"leg_f": 0.34, "kne_f": -0.60, "leg_b": -0.34, "kne_b": -0.55, "wpn": -1.68, "hip_y": 1.5}),
		"release": P({"torso": 0.50, "head": -0.18, "arm_f": 1.35, "elb_f": 0.02, "arm_b": -0.55, "elb_b": 0.75,
			"leg_f": 0.80, "kne_f": -0.25, "leg_b": -0.65, "kne_b": -0.35, "wpn": 1.50, "hip_x": 10.0}),
		# 受击 / 倒地
		"hurt": P({"torso": -0.42, "head": -0.30, "arm_f": -0.75, "elb_f": 0.90, "arm_b": -1.05, "elb_b": 0.70,
			"leg_f": -0.35, "kne_f": -0.35, "leg_b": 0.42, "kne_b": -0.40, "wpn": -1.20, "hip_x": -5.0}),
		"dead": P({"rot": 1.50, "hip_y": 6.0, "torso": 0.30, "head": -0.35, "arm_f": 1.65, "elb_f": 0.25,
			"arm_b": -0.30, "elb_b": 0.55, "leg_f": 0.55, "kne_f": -0.45, "leg_b": -0.25, "kne_b": -0.65, "wpn": -0.60}),
		"win": P({"torso": -0.10, "arm_f": 2.75, "elb_f": 0.15, "arm_b": 0.20, "elb_b": 0.60,
			"leg_f": 0.20, "kne_f": -0.20, "leg_b": -0.20, "kne_b": -0.22, "wpn": -1.60}),
	}

# =============================================================== Boss 姿势
static func boss_poses() -> Dictionary:
	var st := P({"torso": 0.06, "arm_f": 0.30, "elb_f": 0.45, "arm_b": -0.25, "elb_b": 0.40,
		"leg_f": 0.12, "kne_f": -0.16, "leg_b": -0.12, "kne_b": -0.18, "wpn": -0.30})
	return {
		"idle_a": st,
		"idle_b": P({"hip_y": -3.0, "torso": 0.10, "arm_f": 0.36, "elb_f": 0.50, "arm_b": -0.30, "elb_b": 0.44,
			"leg_f": 0.12, "kne_f": -0.18, "leg_b": -0.12, "kne_b": -0.20, "wpn": -0.26}),
		"walk_0": P({"torso": 0.14, "hip_y": -4.0, "leg_f": 0.55, "kne_f": -0.45, "leg_b": -0.50, "kne_b": -0.35,
			"arm_f": 0.10, "elb_f": 0.55, "arm_b": -0.45, "elb_b": 0.45, "wpn": -0.45}),
		"walk_1": P({"torso": 0.16, "hip_y": -2.0, "leg_f": 0.05, "kne_f": -0.70, "leg_b": -0.05, "kne_b": -0.25,
			"arm_f": 0.30, "elb_f": 0.60, "arm_b": -0.25, "elb_b": 0.50, "wpn": -0.35}),
		"walk_2": P({"torso": 0.14, "hip_y": -4.0, "leg_f": -0.50, "kne_f": -0.35, "leg_b": 0.55, "kne_b": -0.45,
			"arm_f": -0.30, "elb_f": 0.60, "arm_b": 0.15, "elb_b": 0.55, "wpn": -0.55}),
		"walk_3": P({"torso": 0.16, "hip_y": -2.0, "leg_f": -0.05, "kne_f": -0.25, "leg_b": 0.05, "kne_b": -0.70,
			"arm_f": -0.10, "elb_f": 0.55, "arm_b": 0.25, "elb_b": 0.50, "wpn": -0.40}),
		# 重劈（可弹反）
		"cleave_wind": P({"torso": -0.42, "head": 0.24, "arm_f": 2.85, "elb_f": -0.55, "arm_b": 2.55, "elb_b": -0.35,
			"leg_f": 0.30, "kne_f": -0.40, "leg_b": -0.35, "kne_b": -0.45, "wpn": -1.70, "hip_x": -8.0}),
		"cleave_hit": P({"torso": 0.62, "head": -0.28, "arm_f": 1.35, "elb_f": 0.10, "arm_b": 1.10, "elb_b": 0.35,
			"leg_f": 0.85, "kne_f": -0.45, "leg_b": -0.70, "kne_b": -0.40, "wpn": 1.30, "hip_x": 14.0}),
		# 横扫连击（可弹反，三段）
		"sweep_wind": P({"torso": -0.20, "head": 0.18, "arm_f": 0.55, "elb_f": 0.30, "arm_b": 1.90, "elb_b": -0.30,
			"leg_f": 0.35, "kne_f": -0.35, "leg_b": -0.30, "kne_b": -0.35, "wpn": -2.20, "hip_x": -5.0}),
		"sweep_hit": P({"torso": 0.42, "head": -0.16, "arm_f": 2.55, "elb_f": 0.15, "arm_b": -1.40, "elb_b": 0.40,
			"leg_f": 0.60, "kne_f": -0.40, "leg_b": -0.50, "kne_b": -0.40, "wpn": 2.55, "hip_x": 8.0}),
		# 跳跃砸地（不可弹反）
		"slam_wind": P({"sy": 0.82, "hip_y": 8.0, "torso": 0.30, "arm_f": 2.20, "elb_f": 0.70,
			"arm_b": 2.00, "elb_b": 0.75, "leg_f": 0.55, "kne_f": -1.15, "leg_b": -0.55, "kne_b": -1.10, "wpn": -1.95}),
		"slam_air": P({"torso": -0.20, "arm_f": 2.95, "elb_f": -0.30, "arm_b": 2.70, "elb_b": -0.20,
			"leg_f": 0.70, "kne_f": -1.35, "leg_b": -0.45, "kne_b": -1.25, "wpn": -1.80}),
		"slam_hit": P({"sy": 0.88, "hip_y": 6.0, "torso": 0.55, "head": -0.30, "arm_f": 1.10, "elb_f": 0.25,
			"arm_b": 0.95, "elb_b": 0.40, "leg_f": 0.75, "kne_f": -1.00, "leg_b": -0.75, "kne_b": -1.00, "wpn": 1.20}),
		# 冲锋突进（不可弹反）
		"charge_wind": P({"torso": -0.30, "head": 0.20, "arm_f": 0.20, "elb_f": 1.30, "arm_b": -0.20, "elb_b": 1.25,
			"leg_f": 0.45, "kne_f": -0.80, "leg_b": -0.45, "kne_b": -0.75, "wpn": -1.10, "hip_x": -6.0}),
		"charge_hit": P({"torso": 0.55, "head": -0.25, "arm_f": -0.45, "elb_f": 1.05, "arm_b": -0.90, "elb_b": 0.90,
			"leg_f": 0.95, "kne_f": -0.30, "leg_b": -0.85, "kne_b": -0.40, "wpn": -0.60, "hip_x": 10.0}),
		# 飞斧（可弹反）
		"throw_wind": P({"torso": -0.30, "head": 0.20, "arm_f": 2.60, "elb_f": -0.70, "arm_b": 1.10, "elb_b": 0.60,
			"leg_f": 0.30, "kne_f": -0.45, "leg_b": -0.35, "kne_b": -0.45, "wpn": -1.60, "hip_x": -6.0}),
		"throw_hit": P({"torso": 0.48, "head": -0.20, "arm_f": 1.45, "elb_f": 0.05, "arm_b": -0.95, "elb_b": 0.55,
			"leg_f": 0.75, "kne_f": -0.30, "leg_b": -0.60, "kne_b": -0.35, "wpn": 1.50, "hip_x": 9.0, "hide_weapon": 1.0}),
		# 二阶段组合技：地面裂隙
		"fissure_wind": P({"sy": 0.90, "hip_y": 5.0, "torso": 0.40, "arm_f": 1.90, "elb_f": 0.90,
			"arm_b": 1.75, "elb_b": 0.95, "leg_f": 0.50, "kne_f": -0.95, "leg_b": -0.50, "kne_b": -0.90, "wpn": -1.20}),
		"fissure_hit": P({"sy": 0.84, "hip_y": 9.0, "torso": 0.70, "head": -0.35, "arm_f": 0.95, "elb_f": 0.30,
			"arm_b": 0.85, "elb_b": 0.45, "leg_f": 0.85, "kne_f": -1.20, "leg_b": -0.85, "kne_b": -1.15, "wpn": 1.05}),
		# 硬直 / 破防 / 转阶段 / 倒地
		"stagger": P({"torso": -0.55, "head": -0.35, "arm_f": -0.85, "elb_f": 1.00, "arm_b": -1.15, "elb_b": 0.85,
			"leg_f": -0.45, "kne_f": -0.45, "leg_b": 0.50, "kne_b": -0.50, "wpn": -1.30, "hip_x": -10.0}),
		"broken": P({"sy": 0.86, "hip_y": 22.0, "torso": 0.75, "head": -0.45, "arm_f": 0.35, "elb_f": 0.55,
			"arm_b": 0.15, "elb_b": 0.60, "leg_f": 1.15, "kne_f": -1.60, "leg_b": -0.99, "kne_b": -1.55, "wpn": 0.30}),
		"roar": P({"torso": -0.35, "head": 0.45, "arm_f": 2.60, "elb_f": -0.45, "arm_b": -2.30, "elb_b": -0.35,
			"leg_f": 0.35, "kne_f": -0.35, "leg_b": -0.35, "kne_b": -0.35, "wpn": -1.30}),
		"dead": P({"rot": 1.48, "hip_y": 20.0, "torso": 0.35, "head": -0.40, "arm_f": 1.55, "elb_f": 0.30,
			"arm_b": -0.35, "elb_b": 0.55, "leg_f": 0.60, "kne_f": -0.50, "leg_b": -0.30, "kne_b": -0.70, "wpn": -0.50}),
	}
