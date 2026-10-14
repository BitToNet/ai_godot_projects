## =============================================================================
##  asset_check —— 外部模型资产管线的**定式自检**（不建世界、不开窗，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/asset_check.gd
##
##  ---- 为什么要有这一步 ----
##  第③批-2 第一次把外部 GLB 引进世界（此前全工程零外部美术资源）。这条链上新出现的
##  失败方式全是「不报错、不崩、指纹也不变」的那一类，headless 下还画不出像素：
##    · 忘了 import（净克隆、换机器）→ 模型加载失败 → SettlementBuilder 静默回退程序化，
##      画面看起来「还行」，于是没人发现真模型根本没上；
##    · 清单里的 target_m 写错 → 房子变成 12 米巨物或 0.8 米玩具，数值全绿；
##    · 接地偏移算错符号 → 房子悬空半米或埋进地里；
##    · 图集前提被破坏（换了模型文件）→「一个材质喂所有建筑」不再成立；
##    · 材质 uniform 忘了赋值 → Godot 会**静默用默认值**，夜里村庄不跟着变暗。
##  所以这一步只做一件事：把上面每一条变成会红的断言。视觉好不好看仍归 visual_shot。
##
##  与 tools/visual_check.gd 的分工：那个验「观感接线」（光照/雾/天空/贴图），
##  这个验「资产契约」（清单能加载、尺度自洽、材质接线、兜底可用）。
##
##  退出码：0 = 全部通过；1 = 有断言失败
## =============================================================================
extends SceneTree

## 村庄布局的期望总栋数与**台地平整半径**（SettlementBuilder 用 13 × 0.85 = 11.05 米）。
## 写死在这里是有意的：改布局表就必须同时改这个数，逼着人回头看一眼边坡。
const EXPECTED_VILLAGE_MODELS := 8
const VILLAGE_FLAT_RADIUS := 11.05
## 尺度容差：目标世界高度 ±1%；接地 ±2 毫米；外接尺寸必须小于台地平整半径
const TOL_H := 0.01
const TOL_GROUND := 0.002

var _fails: Array[String] = []
var _total: int = 0
## 本工具造的 Node：**必须 free**，否则退出时报 "ObjectDB instances leaked"，
## 那行会被门禁当失败（visual_check 踩过这个坑）。
var _nodes: Array[Node] = []

func _initialize() -> void:
	_run()

func _ok(cond: bool, what: String) -> void:
	_total += 1
	if cond:
		print("  [ok]   %s" % what)
	else:
		_fails.append(what)
		print("  [FAIL] %s" % what)

func _run() -> void:
	print("[ASSET] 外部模型资产定式（不跑地图生成、不开窗）")
	_check_manifest()
	_check_geometry()
	_check_textures()
	_check_material()
	_check_layout()
	_check_fallback()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	print("")
	if _fails.is_empty():
		print("PASS：资产管线定式全部通过（%d 项断言）" % _total)
		quit(0)
	else:
		print("FAIL：%d/%d 项断言未通过 —— %s" % [_fails.size(), _total, "; ".join(_fails)])
		quit(1)

# ---------------------------------------------------------------- 清单能加载
func _check_manifest() -> void:
	print(" · 清单与加载")
	var keys := AssetManifest.model_keys()
	_ok(keys.size() > 0, "清单非空（%d 个模型）" % keys.size())
	for k in keys:
		var e: Dictionary = AssetManifest.MODELS[k]
		_ok(ResourceLoader.exists(e["path"]), "%s 的资源存在：%s" % [k, e["path"]])
		_ok(ModelLibrary.scene(k) != null, "%s 能加载成 PackedScene（没 import 会在这里红）" % k)
	# 缓存语义：同一 key 第二次取必须是同一个实例（整局只 load 一次）
	var a := ModelLibrary.scene(keys[0])
	var b := ModelLibrary.scene(keys[0])
	_ok(a != null and a == b, "同一个 key 第二次取到的是同一个 PackedScene 实例（走了缓存）")
	var st := ModelLibrary.cache_stats()
	_ok(int(st["scenes"]) == keys.size(), "场景缓存条目数 = 清单条目数（%d）" % int(st["scenes"]))

# ------------------------------------------------- 几何：尺度与接地必须自洽
func _check_geometry() -> void:
	print(" · 尺度与接地")
	var host := Node3D.new()
	host.position = Vector3(0, 100.0, 0)   # 抬高 100 米：接地断言就不会被 y=0 蒙对
	get_root().add_child(host)
	_nodes.append(host)
	for k in AssetManifest.model_keys():
		var e: Dictionary = AssetManifest.MODELS[k]
		var aabb := ModelLibrary.merged_aabb(k)
		_ok(aabb.size.y > 0.0001, "%s 的几何 AABB 体积非零（原始高 %.3f）" % [k, aabb.size.y])
		var k_scale := ModelLibrary.world_scale(k)
		# 1) 角度：旋转只能绕 Y，接地与高度不随 yaw 变
		for yaw in [0.0, 0.7]:
			var inst := ModelLibrary.spawn_at(k, host, Vector3(3.0, 0.0, -2.0), yaw)
			_ok(inst != null, "%s yaw=%.1f 落位成功" % [k, yaw])
			if inst == null:
				continue
			var wa := _world_aabb(inst, host.transform)
			_ok(absf(wa.position.y - host.position.y) <= TOL_GROUND,
					"%s yaw=%.1f 底面贴地（最低点 y=%.4f，期望 %.4f）" % [k, yaw, wa.position.y, host.position.y])
			var want_h := float(e["target_m"])
			_ok(absf(wa.size.y - want_h) <= want_h * TOL_H,
					"%s yaw=%.1f 世界高度 = %.3f 米（目标 %.1f）" % [k, yaw, wa.size.y, want_h])
			# 2) 外接尺寸必须小于村庄台地平整半径 —— 尺度写错数量级时这条会红
			var span := maxf(wa.size.x, wa.size.z)
			_ok(span < VILLAGE_FLAT_RADIUS,
					"%s 外接尺寸 %.2f 米 < 台地平整半径 %.1f 米" % [k, span, VILLAGE_FLAT_RADIUS])
			print("         %s 世界尺寸 %.2f × %.2f × %.2f 米（倍率 %.3f，接地偏移 %+.3f）"
					% [k, wa.size.x, wa.size.y, wa.size.z, k_scale, ModelLibrary.ground_offset(k)])
			host.remove_child(inst)
			inst.free()

func _world_aabb(n: Node, base: Transform3D) -> AABB:
	var acc: Array = []
	_collect_aabb(n, base, acc)
	var out := AABB()
	if not acc.is_empty():
		out = acc[0]
		for i in range(1, acc.size()):
			out = out.merge(acc[i])
	return out

## 为什么手算变换而不是用 global_transform：
##   SceneTree 脚本在 _initialize() 里跑，此时 root 还没进树，节点 get_global_transform()
##   会返回零变换并**打出 ERROR 行**（本工具第一版就这么翻的：断言全红 + 门禁判失败）。
##   这里从 base 开始逐级乘 transform，量到的仍然是 spawn_at 真正写进节点的那套
##   「缩放 + 绕 Y 旋转 + 接地偏移」，只是不依赖引擎的全局变换缓存。
func _collect_aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		acc.append(t * (n as MeshInstance3D).mesh.get_aabb())
		# 不 return：网格节点下面还可能有子节点（风车就是 3 个节点）
	for c in n.get_children():
		_collect_aabb(c, t, acc)

# ---------------------------------------------------------------- 贴图前提
func _check_textures() -> void:
	print(" · 图集前提（一个材质喂所有建筑）")
	var digests: Array[String] = []
	for k in AssetManifest.model_keys():
		var t := ModelLibrary.albedo_texture(k)
		_ok(t != null, "%s 取到自带图集贴图" % k)
		if t == null:
			continue
		_ok(t.get_width() > 0 and t.get_height() > 0,
				"%s 贴图尺寸 %d×%d" % [k, t.get_width(), t.get_height()])
		var d := _image_digest(t)
		_ok(d != "", "%s 贴图内容可哈希" % k)
		digests.append(d)
	var all_same := digests.size() > 0
	for d in digests:
		if d != digests[0]:
			all_same = false
	_ok(all_same, "全部模型的图集内容哈希一致（%d 个，%s）"
			% [digests.size(), digests[0].substr(0, 16) if digests.size() > 0 else "-"])

## 贴图内容 SHA-256（前 16 位足以判等）。注意 HashingContext.update 不收空数组，
## 所以空数据直接返回 ""（scale_probe 踩过：喂空数组会打出 ERROR 行）。
func _image_digest(t: Texture2D) -> String:
	var img := t.get_image()
	if img == null:
		return ""
	var data := img.get_data()
	if data.is_empty():
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()

# ---------------------------------------------------------------- 材质接线
func _check_material() -> void:
	print(" · 材质接线")
	var cfg := MapConfig.new()
	var m := MaterialFactory.model_material(cfg, Color(0.8, 0.2, 0.2))
	_ok(m != null, "model_material() 建出材质")
	if m == null:
		return
	_ok(m.shader != null, "shader 已加载（res://shaders/settlement_model.gdshader）")
	# 「没赋过值的 uniform，get_shader_parameter() 返回 null」—— must 逐个钉住
	for p in ["albedo_tex", "tint", "tint_strength", "night_glow", "map_size", "fog_enabled"]:
		_ok(m.get_shader_parameter(p) != null, "uniform %s 被赋过值" % p)
	_ok(m.get_shader_parameter("tint_strength") == MaterialFactory.MODEL_TINT_STRENGTH,
			"染色强度 = MaterialFactory.MODEL_TINT_STRENGTH（%.2f）" % MaterialFactory.MODEL_TINT_STRENGTH)
	var again := MaterialFactory.model_material(cfg, Color(0.8, 0.2, 0.2))
	_ok(again == m, "同一种势力色第二次取到同一个材质实例（按色缓存）")
	var mats := MaterialFactory.model_materials()
	_ok(mats.size() == 1, "材质注册表有 1 个条目（供 WorldGenPipeline 注册昼夜 / 迷雾）")

# ---------------------------------------------------------------- 布局契约
func _check_layout() -> void:
	print(" · 村庄布局契约")
	_ok(AssetManifest.village_model_count() == EXPECTED_VILLAGE_MODELS,
			"村庄总栋数 = %d" % EXPECTED_VILLAGE_MODELS)
	# 各模型栋数是照搬参考项目 village 段的那部分：写死在这里，改数量必须过这一关
	var want := {"bld_house_a": 4, "bld_house_b": 2, "bld_well": 1, "bld_windmill": 1}
	var got := {}
	for e in AssetManifest.VILLAGE_LAYOUT:
		got[e["key"]] = int(got.get(e["key"], 0)) + int(e["count"])
	_ok(got == want, "各模型栋数 = 参考项目 village 段（house_a 4 / house_b 2 / well 1 / windmill 1）")
	_ok(float(AssetManifest.VILLAGE_MIN_GAP) > 0.0,
			"落位最小余量 %.1f 米 > 0（两栋建筑不许重叠）" % AssetManifest.VILLAGE_MIN_GAP)
	for e in AssetManifest.VILLAGE_LAYOUT:
		var k: String = e["key"]
		_ok(AssetManifest.MODELS.has(k), "布局条目 %s 在模型清单里" % k)
		_ok(float(e["radius_min"]) <= float(e["radius_max"]),
				"%s 半径区间合法（%.1f ~ %.1f 米）" % [k, float(e["radius_min"]), float(e["radius_max"])])
		# 建筑必须落在台地平整半径内，而且要**扣掉自己的外接半径**：
		# 只卡中心点是不够的 —— 4.6 米高的房子放在 r=10.5 处，外沿能伸到 13 米插进边坡。
		var fr := ModelLibrary.footprint_radius(k)
		var far := float(e["radius_max"]) + fr
		_ok(far <= VILLAGE_FLAT_RADIUS,
				"%s 最远中心 %.1f + 外接半径 %.2f = %.2f 米 ≤ 台地平整半径 %.2f 米"
				% [k, float(e["radius_max"]), fr, far, VILLAGE_FLAT_RADIUS])
	_check_spacing()

## 落位判据的**静态可行性**：这两条断言的意义是「布局表本身摆得下、而且摆下就不会穿模」，
## 它们只用实测几何 + 表里的半径带算，不跑 RNG、不建世界 —— 表改坏了当场红。
func _check_spacing() -> void:
	print(" · 落位间距与槽位可行性")
	# 1) 内切半径必须存在且 ≤ 外接半径（判据用的就是内切半径）
	for k in AssetManifest.model_keys():
		var ir := ModelLibrary.inner_radius(k)
		_ok(ir > 0.1 and ir <= ModelLibrary.footprint_radius(k) + 0.001,
				"%s 内切半径 %.2f ≤ 外接半径 %.2f 米" % [k, ir, ModelLibrary.footprint_radius(k)])
	# 2) 墙体不相交：布局表里**真会同时出现**的每一对，都要满足
	#    「内切之和 + 余量 ≥ 最长半边之和」（最长半边 = 两栋都按最坏朝向转过 90°）
	var counts := {}
	for e in AssetManifest.VILLAGE_LAYOUT:
		counts[e["key"]] = int(counts.get(e["key"], 0)) + int(e["count"])
	var keys: Array = counts.keys()
	keys.sort()
	var worst_pair := ""
	var worst_margin := INF
	var max_r: Array = []          # 环上（半径带不含原点）的条目
	for i in keys.size():
		for j in range(i, keys.size()):
			var a: String = keys[i]
			var b: String = keys[j]
			if a == b and int(counts[a]) < 2:
				continue
			var need: float = ModelLibrary.inner_radius(a) + ModelLibrary.inner_radius(b) \
					+ AssetManifest.VILLAGE_MIN_GAP
			var wall: float = _max_half_side(a) + _max_half_side(b)
			if need - wall < worst_margin:
				worst_margin = need - wall
				worst_pair = "%s↔%s" % [a, b]
			_ok(need >= wall - 0.001,
					"%s↔%s 判据 %.2f 米 ≥ 最长半边之和 %.2f 米（墙体不会相交）" % [a, b, need, wall])
	_ok(worst_margin >= 0.0, "最苛刻的一对是 %s（余量 %.2f 米）" % [worst_pair, worst_margin])
	# 3) 槽位可行性：环上有 n 栋时两槽最小夹角 = 槽宽 × (1 − 2×JITTER)，
	#    该夹角下的弦长（两栋都取半径下界，此时弦长最短）必须 ≥ 最苛刻的一对判据
	var n := 0
	var ring_min_r: Array = []
	for e in AssetManifest.VILLAGE_LAYOUT:
		if float(e["radius_min"]) > 0.1:
			n += int(e["count"])
			ring_min_r.append(float(e["radius_min"]))
	if n >= 2:
		var r_min := float(ring_min_r.min())
		var slot_w := TAU / float(n)
		var dth := slot_w * (1.0 - 2.0 * AssetManifest.VILLAGE_SLOT_JITTER)
		var chord := 2.0 * r_min * sin(dth * 0.5)
		var need_max := 0.0
		for i in keys.size():
			for j in range(i, keys.size()):
				var a: String = keys[i]
				var b: String = keys[j]
				if float(_layout_radius_min(a)) <= 0.1 or float(_layout_radius_min(b)) <= 0.1:
					continue
				if a == b and int(counts[a]) < 2:
					continue
				need_max = maxf(need_max, ModelLibrary.inner_radius(a) + ModelLibrary.inner_radius(b)
						+ AssetManifest.VILLAGE_MIN_GAP)
		_ok(chord >= need_max - 0.001,
				"环上 %d 栋：半径下界 %.1f 米时相邻槽弦长 %.2f 米 ≥ 最苛刻判据 %.2f 米"
				% [n, r_min, chord, need_max])

## 布局表里某个 key 的半径下界（找不到返回 -1）
func _layout_radius_min(k: String) -> float:
	for e in AssetManifest.VILLAGE_LAYOUT:
		if e["key"] == k:
			return float(e["radius_min"])
	return -1.0

## XZ 最长半边（米）：两栋建筑都按最坏朝向转 90° 时，各自能伸出的最大半宽
func _max_half_side(k: String) -> float:
	var a := ModelLibrary.merged_aabb(k)
	return maxf(a.size.x, a.size.z) * 0.5 * ModelLibrary.world_scale(k)

# ---------------------------------------------------------------- 兜底可用
func _check_fallback() -> void:
	print(" · 兜底与可重复")
	var host := Node3D.new()
	get_root().add_child(host)
	_nodes.append(host)
	var bad := ModelLibrary.spawn_at("__no_such_key__", host, Vector3.ZERO, 0.0)
	_ok(bad == null, "清单外的 key：spawn_at 返回 null（调用方据此整套回退程序化）")
	_ok(host.get_child_count() == 0, "失败的落位没有留下任何节点")
	_ok(ModelLibrary.scene("__no_such_key__") == null, "清单外的 key：scene() 返回 null，不崩")
	# 清缓存后能重新加载（自检可以反复跑）
	ModelLibrary.clear_cache()
	MaterialFactory.clear_model_materials()
	_ok(ModelLibrary.cache_stats()["scenes"] == 0, "clear_cache() 之后场景缓存归零")
	var k0: String = AssetManifest.model_keys()[0]
	_ok(ModelLibrary.scene(k0) != null, "清缓存后能重新加载 %s" % k0)