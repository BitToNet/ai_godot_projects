## =============================================================================
##  PartyModels —— 部队外观：外部 GLB 坐骑 + 骑手（第④批）
##
##  在这之前，部队是 PartyModelBuilder 用 ArrayMesh 拼的方块马 + 方块骑手。本文件
##  把那套换成参考项目那批 CC0 模型（KayKit 骑士 + Quaternius 坐骑），只做三件事：
##
##    1) **拼装**：坐骑实例 + 骑手实例（骑士播 Sit_Chair_Idle 坐姿）。
##       骑手高度由 ModelLibrary.rider_offset_y **推出**（实测背高 − 实测胯高），
##       不抄参考项目的 0.8839 —— 那是按它 468 米世界标定的。
##    2) **动画**：move / idle 两态（Gallop / Idle），带 glTF 骨架前缀兜底；切换幂等。
##    3) **回退**：任一模型缺失即返回 null，调用方回落到程序化方块模型（不崩、不刷 ERROR）。
##
##  ---- 与参考项目不同的两点（都是有意的）----
##  · 参考项目每支部队同步拼一份材质实例；我们在第①批量过帧预算，这里共用 GLB 原始材质
##    （贴图是 CC0 资产原文，不染色），势力身份靠头顶 Label3D 的势力色 + 玩家标记环。
##  · 参考项目把倍率写死在 JSON；我们只写"期望背高 / 期望体高"，倍率由几何实测推出。
## =============================================================================
class_name PartyModels
extends RefCounted

## 部队种类 → 坐骑键（玩家与领主同骑战马；商队骑驴；强盗骑另一匹，毛色可分辨）
const MOUNT_BY_KIND := {
	"player": "mount_horse",
	"lord": "mount_horse",
	"caravan": "mount_donkey",
	"bandit": "mount_horse_alt",
}
const RIDER := "rider_seated"

static func mount_key(kind: String) -> String:
	return str(MOUNT_BY_KIND.get(kind, "mount_horse"))

## 拼一个"坐骑 + 骑手"。失败返回 null（调用方回退程序化模型）。
static func rig(kind: String) -> Node3D:
	var mk := mount_key(kind)
	var mount := ModelLibrary.build(mk)
	if mount == null:
		return null
	var rider := ModelLibrary.build(RIDER)
	if rider == null:
		mount.free()
		return null
	_strip_unskinned(rider)
	rider.position = Vector3(0.0, ModelLibrary.rider_offset_y(mk, RIDER), 0.0)
	var root := Node3D.new()
	root.name = "Rig"
	root.set_meta("mount_key", mk)
	root.set_meta("mount", mount)
	root.set_meta("rider", rider)
	root.set_meta("motion", "")
	root.add_child(mount)
	root.add_child(rider)
	return root

## 去掉**不带蒙皮**的节点（骑士实测 9 个：头盔 / 披风 / 5 面盾牌 / 2 把剑）。两个理由：
##   ① 它们不跟动画走 —— 蒙皮靠骨骼，非蒙皮节点钉在**绑定姿态**上，坐姿里会浮在马旁边；
##   ② 一个骑士实例 15 个网格节点 = 15 次绘制调用，15 支部队就是 225 次，
##      是窗口实测「绘制调用 339 → 621」的主要来源，而策略视角下这些武器根本看不见。
## 留下的 6 个蒙皮网格（身/头/双臂/双腿）就是整条人形。
static func _strip_unskinned(n: Node) -> void:
	var drop: Array = []
	_collect_unskinned(n, drop)
	for d in drop:
		var par: Node = d.get_parent()
		if par != null:
			par.remove_child(d)
		d.free()

static func _collect_unskinned(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).skin == null:
			out.append(c)
		else:
			_collect_unskinned(c, out)

## 每帧调；**幂等**：运动状态没变就直接返回，不会把动画按回 0 秒
static func tick(rig: Node3D, moving: bool, speed: float) -> void:
	if rig == null:
		return
	var want := "move" if moving else "idle"
	if str(rig.get_meta("motion", "")) == want:
		return
	rig.set_meta("motion", want)
	var mk := str(rig.get_meta("mount_key", ""))
	ModelLibrary.play_motion(rig.get_meta("mount") as Node3D, mk, want, speed)
	ModelLibrary.play_motion(rig.get_meta("rider") as Node3D, RIDER, want, speed)

## 落座后骑手头顶的世界高度（米）—— 自检用，用来断言"人没飘也没埋"
static func mounted_height(kind: String) -> float:
	var mk := mount_key(kind)
	var off := ModelLibrary.rider_offset_y(mk, RIDER)
	return off + ModelLibrary.body_box(RIDER).size.y * ModelLibrary.world_scale(RIDER)