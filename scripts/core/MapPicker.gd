## =============================================================================
##  MapPicker —— 屏幕空间拾取（「点到定居点 / 部队」的判定）
##
##  为什么不是 3D 射线 + 碰撞体：大地图上**一个碰撞体都没有**（地形是自制网格、
##  部队与建筑都是自制 MeshInstance3D）。为了「点一下选中」去给每个实体加
##  CollisionShape3D，等于把物理世界与每帧同步开销一起引进来，而这条路径根本不
##  需要物理。做法与参考实现（F:\aigc_code\godot_ai_test 的 map_scene.gd::_pick_at()，
##  外部资料、不在本仓库内）一致：
##    · 把实体中心的世界坐标**投影到屏幕**，比较「鼠标点到投影点的像素距离」；
##    · 命中阈值 = 把实体的世界半径用同一个投影换算成像素（近大远小），再加
##      PICK_PAD_PX 的准头余量，钳在 [14, 90] px —— 于是「点标签附近也算点到」这种
##      骑砍式手感不需要包围盒，远处的目标也还点得着（下限那一档）。
##    · 部队的阈值再乘 0.85（小目标要瞄得更准）；两支都命中时按**绝对像素距离**比
##      谁更近，但部队有 PARTY_ADVANTAGE_PX 的让先 —— 见那个常量的注释。
##
##  本类**纯只读**：不抽随机数、不改任何状态、不发信号，可以在自检里反复调用。
##  投影这一步单独抽成三个可覆写的方法（_project / _behind / _pixel_span），
##  自检因此不需要真的建一个渲染窗口（见 tools/selection_check.gd 的 StubPicker）。
## =============================================================================
class_name MapPicker
extends RefCounted

## 命中结果的 kind 取值。Main / SelectionSystem 也用它，避免第三份字符串字面量。
const KIND_SETTLEMENT := "settlement"
const KIND_PARTY := "party"

## 部队的可点半径（米）：与 HoverInspector 的 7.0 同一个口径
const PARTY_RADIUS_M := 7.0
## 命中半径换算成像素后额外加的准头余量（像素）：让「点在模型边缘 / 标签旁边」也算点到
const PICK_PAD_PX := 6.0
## 部队阈值收紧系数：小目标要瞄得更准才算命中（13 px 的圈实际 11.05 px）
const PARTY_THRESHOLD_SCALE := 0.85
## 命中半径换算成像素后的钳位区间（下限保证远景还点得着，上限避免城池吃掉半屏）
const MIN_PICK_PX := 14.0
const MAX_PICK_PX := 90.0
## 两支都命中时给部队的让先（像素）：谁离光标更近就是谁，部队再额外占这么多。
## 为什么需要它：本项目的领主 AI 以 `s.pos`（城中心）为巡逻终点，会**站在城里**，
## 按「定居点一律优先」的写法这些部队永远点不动；而完全按最近者取胜又会让
## 「瞄准城、旁边正好有商队路过」变成选中商队。6 px 差不多是「光标明显朝部队挪了一下」。
const PARTY_ADVANTAGE_PX := 6.0
## 部队中心相对脚底抬高多少米（模型大致重心）
const PARTY_CENTER_LIFT := 1.5

var camera_rig: CameraRig
var data: MapData
var parties: Array[AIParty] = []

## 屏幕坐标 → 命中结果。返回 {} 表示点到空地（调用方据此下发行军命令）。
## 命中结果：{kind, px, score, screen_pos, settlement?/party?}
##   · px = 光标到投影点的像素距离；score = px / 命中阈值（< 1 即命中）。
##     比大小用 px（绝对距离），score 留作诊断与 UI 参考。
func pick(screen_pos: Vector2) -> Dictionary:
	if camera_rig == null or camera_rig.cam == null or data == null:
		return {}
	var s := _pick_settlement(screen_pos)
	var p := _pick_party(screen_pos)
	if s.is_empty():
		return p
	if p.is_empty():
		return s
	if float(p["px"]) <= float(s["px"]) + PARTY_ADVANTAGE_PX:
		return p
	return s

# ---------------------------------------------------------------- 分类拾取
func _pick_settlement(screen_pos: Vector2) -> Dictionary:
	if data.hm == null:
		return {}
	var best: Dictionary = {}
	var best_score := 1e20
	for s in data.settlements:
		if s == null:
			continue
		var c := _settlement_center(s)
		var d := _screen_distance(screen_pos, c)
		if d < 0.0:
			continue
		var thr := _pick_radius_px(c, s.radius)
		if d > thr:
			continue
		var score := d / maxf(1.0, thr)
		if score < best_score:
			best_score = score
			best = {
				"kind": KIND_SETTLEMENT,
				"px": d,
				"score": score,
				"screen_pos": _project(c),
				"settlement": s,
			}
	return best

func _pick_party(screen_pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 1e20
	for a in parties:
		if a == null or not is_instance_valid(a):
			continue
		var c := Vector3(a.position.x, a.position.y + PARTY_CENTER_LIFT, a.position.z)
		var d := _screen_distance(screen_pos, c)
		if d < 0.0:
			continue
		var thr := _pick_radius_px(c, PARTY_RADIUS_M, PARTY_THRESHOLD_SCALE)
		if d > thr:
			continue
		var score := d / maxf(1.0, thr)
		if score < best_score:
			best_score = score
			best = {
				"kind": KIND_PARTY,
				"px": d,
				"score": score,
				"screen_pos": _project(c),
				"party": a,
			}
	return best

## 定居点中心：地面高度取「平整后的地基」与「高度场实际值」的较大者。
## 生成期会把地基推到 ground_h，两个值正常应当相等；取 max 是为了让
## ground_h 尚未赋值的场景（个别自检直接造 MapData）也能落在真实地面上。
func _settlement_center(s: Settlement) -> Vector3:
	var h := maxf(s.ground_h, data.hm.height_at(s.pos.x, s.pos.y))
	return Vector3(s.pos.x, h, s.pos.y)

# ---------------------------------------------------------------- 投影（可覆写）
func _project(world: Vector3) -> Vector2:
	return camera_rig.cam.unproject_position(world)

func _behind(world: Vector3) -> bool:
	return camera_rig.cam.is_position_behind(world)

## 世界半径 → 屏幕像素跨度：把中心与「中心 + 相机右向 × 半径」都投影出来量距离。
func _pixel_span(center: Vector3, radius_m: float) -> float:
	var right := camera_rig.cam.global_transform.basis.x
	return _project(center).distance_to(_project(center + right * radius_m))

## 屏幕点到实体的像素距离；实体在相机背后时返回 -1（调用方一律跳过）。
func _screen_distance(screen_pos: Vector2, world: Vector3) -> float:
	if _behind(world):
		return -1.0
	return screen_pos.distance_to(_project(world))

## 命中阈值（像素）= clampf(世界半径的像素跨度 + PICK_PAD_PX, MIN, MAX) × scale。
## 先钳位再乘 scale：否则小目标的收紧会被下限那 14 px 直接吃掉（等于没收紧）。
func _pick_radius_px(center: Vector3, radius_m: float, scale: float = 1.0) -> float:
	return clampf(_pixel_span(center, radius_m) + PICK_PAD_PX, MIN_PICK_PX, MAX_PICK_PX) * scale
