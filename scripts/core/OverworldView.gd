## =============================================================================
##  OverworldView —— 大地图这一层的「显示开关」与标签缩放
##
##  从 Main.gd 搬出三件事：_update_label_scale / _set_overworld_visible /
##  _on_strategic_changed。都是纯表现层，不抽任何随机数，所以搬动不影响指纹。
##
##  标签缩放原本每帧对 33 个 Label3D 白写同一个值（写 pixel_size 会标脏并重建字形网格），
##  现在按 1/64 量化 + 数量比对做早退，稳态开销为 0；数量比对同时保证
##  「运行中新建的部队」标签不会因为早退而漏掉缩放。
## =============================================================================
class_name OverworldView
extends RefCounted

var camera_rig: CameraRig
var data: MapData
var parties: Array[AIParty]
var player: PartyBase
var vegetation: VegetationScatter
## 进出 Boss 战时整体显示 / 隐藏的节点：地形 / 水面 / 夜灯 / 相机 / 玩家 / HUD
var nodes: Array = []

## 上次实际写入标签的缩放因子与当时的标签总数（-1 = 尚未应用）
var _scale_applied: float = -1.0
var _count_applied: int = -1

func update_label_scale() -> void:
	if camera_rig == null or data == null:
		return
	var f := clampf(camera_rig.zoom_height / 90.0, 0.85, 4.2)
	# f 只由滚轮缩放（camera_rig.zoom_height）决定，平视时每帧都是同一个值
	f = snappedf(f, 1.0 / 64.0)
	var n := data.settlements.size() + parties.size() + 1
	if n == _count_applied and is_equal_approx(f, _scale_applied):
		return
	_scale_applied = f
	_count_applied = n
	for s in data.settlements:
		if s.label != null:
			s.label.pixel_size = 0.026 * f
	for a in parties:
		if a != null and is_instance_valid(a) and a.label != null:
			a.label.pixel_size = 0.024 * f
	if player != null and player.label != null:
		player.label.pixel_size = 0.024 * f

## 相机在「战术 / 战略」之间切换：战略视图把植被整层剔掉，省下大量 draw call
func on_strategic_changed(is_strategic: bool) -> void:
	if vegetation != null and vegetation.root != null:
		vegetation.root.visible = not is_strategic
	# 战略视图里定居点标签再放大一档（配合 update_label_scale 的缩放）
	if is_strategic:
		print("[视图] 进入战略视图：植被剔除，定居点标签放大")

## 进 Boss 战时把整个大地图藏起来（战斗场景是 2D 横版，铺在同一棵树上）
func set_visible(v: bool) -> void:
	var list: Array = nodes.duplicate()
	for a in parties:
		list.append(a)
	for n in list:
		if n == null or not is_instance_valid(n):
			continue
		if n is Node3D or n is CanvasItem or n is CanvasLayer:
			n.visible = v