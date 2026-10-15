## =============================================================================
##  party_model_check —— 部队外部模型（坐骑 + 骑手）的定式自检（进一键盘门禁）
##
##  这段链上新出现的失败模式，条条都能让画面"看起来还行"却其实是坏的：
##    · 忘了 import（净克隆 / 换机器）→ rig() 返回 null → 全体回退方块马，没人发现；
##    · 模型文件被换掉（换了包 / 重新导出）→ 三角形数与实测轮廓全变，尺度跟着错；
##    · **拿包围盒当身高** → 包围盒里混着不带蒙皮的武器节点，且带蒙皮的面存的是
##      绑定空间的界限。骑士实测：包围盒 2.4666（最高点是武器）/ 身体 2.3145。
##      按包围盒定倍率会有 6% 系统误差，肉眼像"模型小了点"，却让"清单里 target_m
##      就是世界高度"这条前提不成立；
##    · glTF 导入器给片段加骨架前缀（AnimalArmature|Gallop）→ 清单里的逻辑名解析不到，
##      动画静默不播，马站着不动也能被当成"本来就这样"；
##    · 骑手偏移算错 → 人飘在马背上 0.5 米，或者整个埋进马肚子里；
##    · 署名丢了 → CC0 虽不强制署名，但本工程把来源记录当作可追溯性要求（见 ATTRIBUTION.md）。
##
##  用法：
##    Godot … --headless --script res://tools/party_model_check.gd            （断言，失败退出码 1）
##    Godot … --headless --script res://tools/party_model_check.gd -- --report（额外打印实测值）
## =============================================================================
extends SceneTree

var _pass := 0
var _fail := 0
var _report := false

const ARMY := ["mount_horse", "mount_horse_alt", "mount_donkey", "rider_seated"]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--report":
			_report = true
	print("[部队] 部队外部模型定式自检（不建世界、不开窗）")
	_check_manifest()
	_check_geometry()
	_check_clips()
	_check_seat()
	_check_credits()
	_check_rig_smoke()
	_check_fallback()
	_cleanup()
	print("[部队] ---- %d 过 / %d 失败 ----" % [_pass, _fail])
	if _fail == 0:
		print("[部队] PASS：部队模型 %d 项断言全过（%s）" % [_pass, _summary()])
		quit(0)
	else:
		print("[部队] FAIL：%d 项断言没过" % _fail)
		quit(1)


func _ok(c: bool, text: String) -> void:
	if c:
		_pass += 1
		print("[部队]   ok   %s" % text)
	else:
		_fail += 1
		print("[部队]   FAIL %s" % text)


func _check_manifest() -> void:
	var missing: Array = []
	for k in ARMY:
		if not AssetManifest.MODELS.has(k):
			missing.append(k)
	_ok(missing.is_empty(), "清单含全部 4 个部队条目（缺 %s）" % str(missing))
	var bad: Array = []
	for k in ARMY:
		var e: Dictionary = AssetManifest.MODELS.get(k, {})
		for f in ["path", "target_m", "tris", "anim_move", "anim_idle", "author", "license", "source"]:
			if not e.has(f):
				bad.append("%s.%s" % [k, f])
	_ok(bad.is_empty(), "每个条目都带 路径/期望高度/三角形/动画/作者/许可/来源（缺 %s）" % str(bad))
	var not_imported: Array = []
	for k in ARMY:
		if not ResourceLoader.exists(str(AssetManifest.MODELS[k]["path"])):
			not_imported.append(k)
	_ok(not_imported.is_empty(), "4 个 .glb 都已 import 且能加载（缺 %s —— 跑一次 --import）" % str(not_imported))


func _check_geometry() -> void:
	var tri_bad: Array = []
	var big: Array = []
	for k in ARMY:
		var want := int(AssetManifest.MODELS[k]["tris"])
		var got := ModelLibrary.triangle_count(k)
		if got != want:
			tri_bad.append("%s 清单 %d / 实测 %d" % [k, want, got])
		if got > 12000:
			big.append("%s=%d" % [k, got])
	_ok(tri_bad.is_empty(), "三角形数与清单登记一致（%s）" % ("全部一致" if tri_bad.is_empty() else str(tri_bad)))
	_ok(big.is_empty(), "单模型三角形数都在 12000 以内（%s）" % ("全部达标" if big.is_empty() else str(big)))

	var scale_bad: Array = []
	for k in ARMY:
		var e: Dictionary = AssetManifest.MODELS[k]
		var h := ModelLibrary.body_box(k).size.y * ModelLibrary.world_scale(k)
		if absf(h - float(e["target_m"])) > 0.02:
			scale_bad.append("%s 推出 %.3f / 期望 %.2f" % [k, h, float(e["target_m"])])
	_ok(scale_bad.is_empty(), "倍率推出后世界高度 = target_m（%s）" % ("全部命中（±0.02 米）" if scale_bad.is_empty() else str(scale_bad)))

	# 本批最隐蔽的坑：包围盒里混着不带蒙皮的武器节点 → 身体轮廓必须单独量
	var aabb_h := ModelLibrary.merged_aabb("rider_seated").size.y
	var body := ModelLibrary.body_box("rider_seated")
	_ok(body.size.y > 1.8 and body.size.y < 2.8, "骑士身体轮廓实测在 1.8~2.8 米（%.4f）" % body.size.y)
	_ok(absf(body.position.y) < 0.02, "骑士身体轮廓**脚底就在 y = 0**（实得 %.4f）—— 蒙皮分支还原的是真实姿态，不是绑定空间的界限" % body.position.y)
	_ok(aabb_h > body.size.y, "包围盒比身体高（%.4f > %.4f）：多出来的是 9 个不带蒙皮的武器节点，所以不能拿包围盒当身高" % [aabb_h, body.size.y])


func _check_clips() -> void:
	var bad: Array = []
	for k in ARMY:
		var e: Dictionary = AssetManifest.MODELS[k]
		var inst := ModelLibrary.instance(k)
		if inst == null:
			bad.append("%s（实例化失败）" % k)
			continue
		var ap := ModelLibrary.animation_player(inst)
		if ap == null:
			bad.append("%s（没有 AnimationPlayer）" % k)
			inst.free()
			continue
		for f in ["anim_move", "anim_idle"]:
			var want := str(e[f])
			var got := ModelLibrary.resolve_clip(ap, want)
			if got == "":
				bad.append("%s.%s=%s 解析不到" % [k, f, want])
			elif _report:
				print("[部队]   · %s %s → 实际片段 `%s`（%.3f 秒）" % [k, f, got, ap.get_animation(got).length])
		if _report:
			print("[部队]   · %s 共 %d 条片段 / %d 骨" % [k, ap.get_animation_list().size(), ModelLibrary._find_skeleton(inst).get_bone_count()])
		inst.free()
	_ok(bad.is_empty(), "清单里的片段名都能解析到实际片段（含骨架前缀兜底）（%s）" % ("全部命中" if bad.is_empty() else str(bad)))


func _check_seat() -> void:
	if _report:
		for k in ARMY:
			print("[部队]   · %s 包围盒高 %.4f / 身体高 %.4f / 倍率 %.4f / 接地 %.4f" % [
				k, ModelLibrary.merged_aabb(k).size.y, ModelLibrary.body_box(k).size.y,
				ModelLibrary.world_scale(k), ModelLibrary.ground_offset(k)])
	var bad: Array = []
	for k in ["mount_horse", "mount_horse_alt", "mount_donkey"]:
		var off := ModelLibrary.rider_offset_y(k, "rider_seated")
		var top := PartyModels.mounted_height(k)
		if _report:
			print("[部队]   · %s 骑手偏移 %.4f / 骑手头顶 %.4f 米" % [k, off, top])
		if off <= 0.30 or off >= 1.60:
			bad.append("%s 偏移 %.3f 越界" % [k, off])
		if top < 2.2 or top > 3.4:
			bad.append("%s 头顶 %.3f 米越界" % [k, top])
	_ok(bad.is_empty(), "骑手落座偏移与总高都在合理区间（%s）" % ("3 种坐骑全部达标" if bad.is_empty() else str(bad)))
	var kinds := {}
	for kind in ["player", "lord", "caravan", "bandit"]:
		kinds[kind] = PartyModels.mount_key(kind)
	_ok(kinds["caravan"] == "mount_donkey" and kinds["bandit"] == "mount_horse_alt" and kinds["lord"] == "mount_horse",
		"坐骑按部队种类区分（商队→驴 / 强盗→另一匹 / 领主→战马）")


func _check_credits() -> void:
	var t := FileAccess.get_file_as_string("res://assets/world/models/ATTRIBUTION.md")
	_ok(t.length() > 0, "ATTRIBUTION.md 可读（%d 字节）" % t.length())
	var bad: Array = []
	for k in ARMY:
		var e: Dictionary = AssetManifest.MODELS[k]
		if not t.contains(str(e["author"])):
			bad.append("%s 作者 %s" % [k, e["author"]])
		if not t.contains(str(e["source"])):
			bad.append("%s 来源 %s" % [k, e["source"]])
		if not t.contains(str(e["path"]).get_file()):
			bad.append("%s 文件名 %s" % [k, str(e["path"]).get_file()])
		if not str(e["license"]).begins_with("CC0"):
			bad.append("%s 许可 %s 不是 CC0" % [k, e["license"]])
	_ok(bad.is_empty(), "ATTRIBUTION.md 能查到每个模型的作者 / 来源 URL / 文件名，且许可都是 CC0（%s）"
		% ("4 个全部可追溯" if bad.is_empty() else str(bad)))


func _check_rig_smoke() -> void:
	var rig := PartyModels.rig("player")
	_ok(rig != null, "拼装成功：rig(player) 返回非空")
	# 放进树再释放：离树 free() 一个带 15 个网格节点的子树会让引擎在退出时报
	# 「Leaked instance dependency / RID allocations leaked」，门禁按错误行判失败。
	if rig != null:
		get_root().add_child(rig)
	if rig == null:
		return
	_ok(rig.get_child_count() == 2, "拼装出 2 个节点（坐骑 + 骑手），实得 %d" % rig.get_child_count())
	var mount := rig.get_child(0)
	var rider := rig.get_child(1)
	_ok(ModelLibrary.animation_player(mount) != null, "坐骑带 AnimationPlayer")
	_ok(ModelLibrary.animation_player(rider) != null, "骑手带 AnimationPlayer")
	var left: Array = []
	_collect_meshes(rider, left)
	var skinned := 0
	for m in left:
		if m.skin != null:
			skinned += 1
	_ok(left.size() == skinned and skinned > 0,
		"骑手只剩蒙皮网格（%d 个，全是蒙皮）—— 非蒙皮的武器/头盔钉在绑定姿态上会浮在坐姿旁边" % left.size())
	_ok(absf(rider.position.y - ModelLibrary.rider_offset_y("mount_horse", "rider_seated")) < 0.001,
		"骑手挂在推导出的座位高度 %.4f 米" % rider.position.y)
	PartyModels.tick(rig, true, 46.0)
	var mv := ModelLibrary.animation_player(mount)
	var clip_move := str(mount.get_meta("clip", ""))
	_ok(clip_move.contains("Gallop") and mv.speed_scale > 1.0, "移动态 → 播 `%s`，速率夹到 %.2f（46 米/秒 ÷ 参考 5.0）" % [clip_move, mv.speed_scale])
	var before := mv.speed_scale
	PartyModels.tick(rig, true, 46.0)
	_ok(is_equal_approx(mv.speed_scale, before) and str(rig.get_meta("motion")) == "move", "同状态重复 tick 幂等（不会把动画按回 0 秒）")
	PartyModels.tick(rig, false, 0.0)
	var clip_idle := str(mount.get_meta("clip", ""))
	_ok(clip_idle.contains("Idle") and is_equal_approx(mv.speed_scale, 1.0), "静止态 → 播 `%s`，速率回 1.00" % clip_idle)
	get_root().remove_child(rig)
	rig.free()


func _check_fallback() -> void:
	var none := ModelLibrary.build("no_such_model_key")
	_ok(none == null, "清单外键 → build() 返回 null（调用方回退方块模型，不崩）")
	var one := ModelLibrary.build("rider_seated")
	_ok(one != null, "正常键 → build() 正常返回（回退判据不是恒真）")
	if one != null:
		get_root().add_child(one)
		get_root().remove_child(one)
		one.free()


func _cleanup() -> void:
	ModelLibrary.clear_cache()


## 自检用：递归收集 MeshInstance3D
func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


func _summary() -> String:
	return "坐骑背高 %.2f/%.2f/%.2f 米 · 骑士体高 %.2f 米 · 骑手偏移 %.2f 米" % [
		ModelLibrary.body_box("mount_horse").size.y * ModelLibrary.world_scale("mount_horse"),
		ModelLibrary.body_box("mount_horse_alt").size.y * ModelLibrary.world_scale("mount_horse_alt"),
		ModelLibrary.body_box("mount_donkey").size.y * ModelLibrary.world_scale("mount_donkey"),
		ModelLibrary.body_box("rider_seated").size.y * ModelLibrary.world_scale("rider_seated"),
		ModelLibrary.rider_offset_y("mount_horse", "rider_seated")]