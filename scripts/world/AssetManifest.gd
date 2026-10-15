## =============================================================================
##  AssetManifest —— 外部模型资产的**唯一清单**（第③批-2）
##
##  在这之前，本工程里没有任何「从外面拿进来的模型」：28 个音色是现场合成的、
##  定居点是 MeshKit 用方块 / 棱柱拼的、UI 是纯代码画的。第③批第一次把外部 GLB
##  引进世界，于是需要三样以前不存在的东西，本文件是第一样：
##    · AssetManifest（本文件）—— **要哪些模型、每个模型在世界里应该多大**
##    · ModelLibrary           —— 怎么加载 / 缓存 / 推导尺度 / 接地
##    · tools/asset_check.gd   —— 怎么证明上面两件事真的成立（进一键盘门禁）
##
##  ---- 为什么清单是 GDScript 常量表，不是参考项目的 JSON ----
##  参考项目用 assets/world/manifest_world.json 做数据驱动（改倍率不用改代码）。
##  本工程没有**任何**运行时数据文件：MapConfig / Strings / GameState 全是代码常量，
##  唯一的 JSON 是 tools/*_baseline.json —— 那是给工具读的基线，不是运行时数据。
##  为一个四条目清单引入 JSON，等于新增「文件缺失」「解析失败」两种失败模式，
##  换来的灵活性暂时用不上；等模型涨到几十个、且需要非程序员调参时再谈。
##
##  ---- target_m 的语义是「世界高度（米）」，不是倍率 ----
##  参考项目的 scale 是相对倍率，但它那个世界只有 468 米宽（grid 260 × cell 1.8），
##  村庄布局半径 1.0~2.0 —— 直接套到我们这边（村庄半径 13 米）会把村庄缩成一堆
##  1.3 米高的火柴盒。所以本清单只声明**期望的世界高度**，倍率由 ModelLibrary 用
##  「target_m ÷ 几何实测高度」实时推出（接地偏移同理）。于是 8 个手抄魔数
##  变成 2 条可验证的规则，asset_check 负责证明它们成立。
## =============================================================================
class_name AssetManifest
extends RefCounted

## 模型清单。三件事：
##   path     —— 必须真的存在、且被 import 过（asset_check 第 1 条断言，硬失败）
##   target_m —— 期望的世界高度（米）。取值对齐**它替换掉的程序化几何**：
##               程序化小屋 w 3.4~4.8 / 总高 4.2~5.2 米，风车取 6.0 米当地标。
##               90 米战略机位下 0.119 米/像素，4 米高的房子约 34 像素 —— 体量读感不退化。
##   tris     —— 实测登记的三角形数：不用来算什么，只为让「文件被换掉了」在门禁里暴露。
const MODELS := {
	"bld_house_a": {"path": "res://assets/world/models/bld_house_a.glb", "target_m": 4.0, "tris": 1011},
	"bld_house_b": {"path": "res://assets/world/models/bld_house_b.glb", "target_m": 4.6, "tris": 1393},
	"bld_well": {"path": "res://assets/world/models/bld_well.glb", "target_m": 2.6, "tris": 726},
	"bld_windmill": {"path": "res://assets/world/models/bld_windmill.glb", "target_m": 6.0, "tris": 2653},

	# ---- 第④批：部队（坐骑 + 骑手），全部 CC0，见 assets/world/models/ATTRIBUTION.md ----
	# 「body」字段 = 量**可见身体轮廓**的口径（默认 "aabb"）：
	#   "aabb"    —— 网格包围盒就是可见轮廓。三匹坐骑整匹就是一张蒙皮网格，
	#                且静止姿态下**背是全身最高点**（头是低着的），所以 target_m 就是"背高"。
	#   "skinned" —— 包围盒里混着**不带蒙皮**的节点（武器 / 备用网格），那些节点的形状
	#                不代表"这个人多高"。unit_knight 实测：包围盒 2.4666 米（最高点是武器），
	#                身体轮廓 2.3145 米（15 个网格节点里 9 个不带蒙皮）。按包围盒定倍率，
	#                1.85 米的骑士只有 1.74 米 —— 差 6%，肉眼看不出来，但"清单里的 target_m
	#                就是世界高度"这条前提就不成立了。
	# 「anim_*」只写**逻辑名**：坐骑的实际片段名带头骨前缀（AnimalArmature|Gallop），
	# 由 ModelLibrary.resolve_clip 兜底解析，tools/party_model_check.gd 断言这些片段真的存在。
	# 「anim_ref_speed」= 片段看起来"不打滑"时的世界速度（米/秒），速率 = 实际速度 ÷ 它，夹到 0.30~2.50。
	# 「texture」= 该模型是否自带图集贴图。坐骑是**平色**（Quaternius 那套只给 albedo_color），
	# 骑士带 KayKit 角色包图集 —— 声明出来，asset_check 才会在"文件被换成另一批"时报红。
	"mount_horse": {
		"path": "res://assets/world/models/mount_horse.glb", "target_m": 1.40, "tris": 2182,
		"body": "aabb", "texture": false, "anim_move": "Gallop", "anim_idle": "Idle", "anim_ref_speed": 5.0,
		"author": "Quaternius", "license": "CC0 1.0", "source": "https://poly.pizza/m/bEdE4rmZy9",
	},
	"mount_horse_alt": {
		"path": "res://assets/world/models/mount_horse_alt.glb", "target_m": 1.40, "tris": 2182,
		"body": "aabb", "texture": false, "anim_move": "Gallop", "anim_idle": "Idle", "anim_ref_speed": 4.84,
		"author": "Quaternius", "license": "CC0 1.0", "source": "https://poly.pizza/m/qvTrSG9pZF",
	},
	"mount_donkey": {
		"path": "res://assets/world/models/mount_donkey.glb", "target_m": 1.10, "tris": 2000,
		"body": "aabb", "texture": false, "anim_move": "Gallop", "anim_idle": "Idle", "anim_ref_speed": 3.74,
		"author": "Quaternius", "license": "CC0 1.0", "source": "https://poly.pizza/m/qmX6nhnvp7",
	},
	"rider_seated": {
		"path": "res://assets/world/models/unit_knight.glb", "target_m": 1.85, "tris": 6952,
		"body": "skinned", "texture": true, "anim_move": "Sit_Chair_Idle", "anim_idle": "Sit_Chair_Idle", "anim_ref_speed": 1.0,
		"author": "Kay Lousberg (KayKit)", "license": "CC0 1.0",
		"source": "https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0",
	},
}

## 骑手坐姿的**胯骨高度占体高的比例** —— 实测值（Knight Sit_Chair_Idle @1.2s）：
##   胯骨 0.4813 ÷ 体高 2.3145 = 0.2080
## 存成比例而不是绝对值：换模型 / 改体高时它自动跟着变，不会像参考项目那样留一个
## 只对它有意义的 0.8839（那是它 468 米世界标定的）。tools/party_model_check.gd 会重测这一项。
const RIDER_HIP_FRAC := 0.2080

## 村庄布局表：极坐标（米），原点 = 定居点中心（台地中心，y 就是 ground_h）。
##   · 条目顺序 = 落位抽取顺序，动了它村庄排布就变（几何不进指纹，门禁无感，但没必要动）
##   · 数量照搬参考项目 village 段（house_a×4 / house_b×2 / well×1 / windmill×1 = 8 栋）
##   · 半径是**重新定的**：参考世界村庄直径只有 4~5 单位，照抄会让 4 栋房子挤在
##     半径 1.5 米的圈里。这里按我方 13 米村庄半径重定。
##   · radius_max 必须留在台地平整半径内（13 × 0.85 = 11.05 米），且要**扣掉建筑自己的
##     外接半径** —— 只卡中心点是不够的：一栋 4.6 米高的房子放在 r=10.5 处，外沿能伸到
##     13 米，直接插进边坡。这一条由 asset_check 用实测几何逐条断言，不靠嘴说。
##   · radius_min ≥ 6.4：水井占住中心（r ≤ 2.6），房子不许再挤到井边上；
##     而且半径下界要和「角度槽」联动 —— 相邻两槽的房子最小中心距就是槽弦长
##     2·radius_min·sin(槽宽/2)，见 VILLAGE_SLOT_JITTER 那条注释。
##     两栋建筑到底要多远才算「不重叠」由 VILLAGE_MIN_GAP + 实测内切半径动态算，
##     所以这张表里只写半径带，不写间距。
const VILLAGE_LAYOUT := [
	{"key": "bld_well", "count": 1, "radius_min": 0.0, "radius_max": 2.6},
	{"key": "bld_house_a", "count": 4, "radius_min": 6.4, "radius_max": 8.5},
	{"key": "bld_house_b", "count": 2, "radius_min": 6.4, "radius_max": 8.5},
	{"key": "bld_windmill", "count": 1, "radius_min": 6.5, "radius_max": 8.0},
]

## 落位时的最小余量（米）：两栋建筑的中心距必须 ≥ 各自**内切半径**之和 + 这个数。
## 0.6 抬到 1.1 是算出来的，不是拍的：最苛刻的一对是 house_b ↔ windmill
##   inner(1.57) + inner(1.68) + gap ≥ max半边(1.98) + max半边(2.32)
##   ⇒ gap ≥ 1.04 → 取 1.1。
## 满足这一条，就等于「两栋房子的**墙体**在任何朝向下都不会相交」（最苛刻那对只剩几厘米）；
## 能挨到一起的只有屋檐角，那个在低多边形村庄里读起来就是「连着的房子」，可以接受。
## 这一条由 asset_check 按布局表里**真会同时出现**的组合逐对断言。
const VILLAGE_MIN_GAP := 1.1

## 环上落位的「角度槽」抖动幅度（占槽宽的比例）：每栋房子只能在 (槽心 ± 槽宽/12) 内偏。
## 为什么要有槽：纯随机角度 + 纯随机半径实测摆不满（9 个村只摆下 62/72 栋）——
##   「随机顺序丢盘子」在台地这点面积上必然卡住，而且摆下的那些还会互相插进去。
## 为什么抖动只有 1/12：相邻两槽的**最小**夹角 = 槽宽 × (1 − 2/12) = 5/6 槽宽，
##   于是最小中心距 = 2·radius_min·sin(5/6 槽宽 / 2)。这一条是布局表能不能摆下的
##   **硬条件**，由 asset_check 拿实测内切半径算出来断言（不是估的）。
const VILLAGE_SLOT_JITTER := 1.0 / 12.0

## 溯源与许可（机器可读的一份；人读的在 assets/world/models/ATTRIBUTION.md）。
## 全部 CC0 1.0，无需署名；记下来只为可追溯。
const CREDIT := {
	"license": "CC0 1.0 Universal",
	"author": "Kay Lousberg (KayKit)",
	"source": "https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack",
	"acquired": "2026-10-14 经用户授权，复制参考项目已转好的 GLB（贴图内嵌，无外部依赖）",
}

## 清单里的全部 key（排序后返回，便于打印与断言）
static func model_keys() -> Array:
	var ks: Array = MODELS.keys()
	ks.sort()
	return ks

## 村庄一共摆几栋建筑（布局表求和）
static func village_model_count() -> int:
	var n := 0
	for e in VILLAGE_LAYOUT:
		n += int(e["count"])
	return n