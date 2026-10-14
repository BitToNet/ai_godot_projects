## =============================================================================
##  ModelLibrary —— 外部 GLB 模型的加载 / 缓存 / 尺度推导 / 接地（第③批-2）
##
##  AssetManifest 说「要什么、应该多大」，本文件负责「怎么把它站到地上」。
##  四个坑在这里一次填掉：
##
##  1) **尺度必须是推出来的，不是手抄的**
##     参考项目把 scale 写死在 JSON 里（它那边是对的：那是它自己量的）。
##     我们这边世界尺寸不同，直接搬倍率会得到 1.3 米高的房子。这里用
##     「target_m（期望世界高度）÷ 几何实测 AABB 高度」实时推导 —— 抄错的可能性归零，
##     而且 asset_check 能把推导结果反过来断言一遍。
##
##  2) **接地偏移**
##     有的模型原点不在底面（参考项目的 bld_windmill 的 minY = −0.501，因为它的
##     塔身有一截画在了原点以下）。偏移公式 y = −minY × scale 是把底面精确贴到
##     y = 0 平面的唯一解 —— 参考项目清单里的 prop_tree_a（minY −0.103、scale 1.588、
##     y_offset 0.1629）正好验算成立。手抄这个数迟早会错一个格子。
##
##  3) **4 种建筑共用一张图集 ⇒ 共用 1 个材质**
##     KayKit 的这批模型内嵌同一张 15,783 字节的图集（见 ATTRIBUTION.md）。
##     所以建筑可以共用一个 ShaderMaterial（每势力一个），而不是每栋楼一个材质实例。
##     这条前提不靠信念：asset_check 会比对全部模型的贴图内容哈希。
##
##  4) **加载失败必须是「可回退」而不是「崩」**
##     返回 null 让调用方（SettlementBuilder）整套回退程序化几何；
##     同时**不用** Godot 的错误路径去撞（先 ResourceLoader.exists 再 load），
##     免得一次回退就在门禁里刷出 ERROR 行 —— 那会让「真失败」和「兜底」混在一起。
##
##  缓存是进程级静态的（同 MaterialFactory._tex_cache 的定式）：一个进程里多个世界
##  只付一次加载成本；clear_cache() 供自检反复跑。
## =============================================================================
class_name ModelLibrary
extends RefCounted

static var _scene_cache: Dictionary = {}
static var _aabb_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}

# =============================================================== 加载与清单

## 取清单条目；key 不在清单里返回空字典（调用方只要看到空字典就回退，不崩）
static func entry(key: String) -> Dictionary:
	if not AssetManifest.MODELS.has(key):
		return {}
	return AssetManifest.MODELS[key]

## PackedScene（失败返回 null，并且**不缓存失败** —— import 补上后同进程还能救回来）
static func scene(key: String) -> PackedScene:
	if _scene_cache.has(key):
		return _scene_cache[key]
	var e := entry(key)
	if e.is_empty():
		push_warning("ModelLibrary: 清单里没有 %s" % key)
		return null
	var p: String = e["path"]
	if not ResourceLoader.exists(p):
		push_warning("ModelLibrary: 资源不存在 %s（没 import？跑一次 --import）" % p)
		return null
	var ps := ResourceLoader.load(p) as PackedScene
	if ps == null:
		push_warning("ModelLibrary: %s 不是 PackedScene" % p)
		return null
	_scene_cache[key] = ps
	return ps

## 新实例（未入树；调用方负责 add_child）。失败返回 null。
static func instance(key: String) -> Node3D:
	var ps := scene(key)
	if ps == null:
		return null
	return ps.instantiate() as Node3D

# =============================================================== 几何

## 递归合并全部 MeshInstance3D 的网格 AABB（世界风车有 3 个节点，只看第一个会量矮）。
## 关键：**每个节点自己的 transform 都要乘进去**，网格节点也不例外 ——
## 风车的叶片节点是带旋转的，第一版写成 `elif` 把网格节点自己的 transform 漏掉了，
## 于是量出 1.195 米高（应 1.458），倍率偏大 22%、接地偏了 2.5 米。
## 是 tools/asset_check.gd 用「从父链手算世界体积」把它抓出来的。
static func _merge_aabb(node: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if node is Node3D:
		t = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		acc.append(t * (node as MeshInstance3D).mesh.get_aabb())
		# 不 return：网格节点下面还可能有子节点
	for c in node.get_children():
		_merge_aabb(c, t, acc)

## 原始（未缩放）AABB。失败返回零体积 AABB（AABB() 的 size 为 0）
static func merged_aabb(key: String) -> AABB:
	if _aabb_cache.has(key):
		return _aabb_cache[key]
	var inst := instance(key)
	if inst == null:
		return AABB()
	var acc: Array = []
	_merge_aabb(inst, Transform3D.IDENTITY, acc)
	inst.free()
	var out := AABB()
	if not acc.is_empty():
		out = acc[0]
		for i in range(1, acc.size()):
			out = out.merge(acc[i])
	_aabb_cache[key] = out
	return out

## 世界倍率 = 期望高度 ÷ 几何实测高度
static func world_scale(key: String) -> float:
	var e := entry(key)
	if e.is_empty():
		return 1.0
	var h := merged_aabb(key).size.y
	if h <= 0.0001:
		return 1.0
	return float(e["target_m"]) / h

## 接地偏移（世界单位，直接加到 position.y 上）：把模型最低点贴到 y = 0
static func ground_offset(key: String) -> float:
	return -merged_aabb(key).position.y * world_scale(key)

## 外接半径（米，水平面内、与朝向无关）：XZ 外接矩形对角线的一半 × 倍率。
## 用途：算「建筑最外沿能伸多远」—— 卡台地平整半径必须用它（对角线上界）。
static func footprint_radius(key: String) -> float:
	var a := merged_aabb(key)
	return Vector2(a.size.x, a.size.z).length() * 0.5 * world_scale(key)

## 内切半径（米）：XZ 外接矩形**短边**的一半 × 倍率。
## 用途：落位时的最小中心距判据（见 SettlementBuilder._place_one）。
## 为什么不用外接半径：外接半径是「对角线上界」，两栋都按最坏朝向转 45° 才算得出来 ——
## 4 栋房子要按那个上界排开，8 栋建筑在半径 8.5 米的台地上根本塞不下（面积就差 40%）。
## 内切半径挡的是**墙体相交**：这两个数一共只差 0.2~0.7 米，
## 「和 + 1.1 米余量」已经≥「两者最长半边之和」，所以墙绝不会插进墙里（asset_check 逐对断言）。
static func inner_radius(key: String) -> float:
	var a := merged_aabb(key)
	return minf(a.size.x, a.size.z) * 0.5 * world_scale(key)

## 三角形总数（asset_check 与交付记录用）
static func triangle_count(key: String) -> int:
	var inst := instance(key)
	if inst == null:
		return 0
	var n := 0
	for mi in _all_meshes(inst):
		if mi.mesh != null:
			n += mi.mesh.get_faces().size() / 3
	inst.free()
	return n

static func _all_meshes(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_all_meshes(c))
	return out

static func _first_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for c in root.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null

# =============================================================== 贴图与材质

## 模型自带的图集贴图（glTF 导入把材质挂在 mesh 的 surface 上，
## 但也可能被写成 surface override 或 material override —— 三条路都试一遍）
static func albedo_texture(key: String) -> Texture2D:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: Texture2D = null
	var inst := instance(key)
	if inst != null:
		var mi := _first_mesh(inst)
		if mi != null:
			var m: Material = null
			if mi.material_override != null:
				m = mi.material_override
			elif mi.get_surface_override_material_count() > 0 and mi.get_surface_override_material(0) != null:
				m = mi.get_surface_override_material(0)
			elif mi.mesh != null and mi.mesh.get_surface_count() > 0:
				m = mi.mesh.surface_get_material(0)
			if m is BaseMaterial3D:
				tex = (m as BaseMaterial3D).albedo_texture
			elif m is ShaderMaterial and (m as ShaderMaterial).get_shader_parameter("albedo_tex") != null:
				tex = (m as ShaderMaterial).get_shader_parameter("albedo_tex")
		inst.free()
	_tex_cache[key] = tex
	return tex

## 把材质递归盖到实例的每个 MeshInstance3D 上（含阴影设置：程序化几何那边是显式打开的）
static func apply_material(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in node.get_children():
		apply_material(c, mat)

# =============================================================== 落位

## 在 parent 的局部坐标 local_pos 处放一个模型：自动缩放、贴地、转向，返回实例（失败 null）。
## 注意 position.y 用的是**已缩放**的偏移，所以直接加在 position 上，不再乘 scale。
static func spawn_at(key: String, parent: Node3D, local_pos: Vector3, yaw: float, mat: Material = null) -> Node3D:
	if parent == null:
		return null
	var inst := instance(key)
	if inst == null:
		return null
	inst.scale = Vector3.ONE * world_scale(key)
	inst.rotation.y = yaw
	inst.position = Vector3(local_pos.x, local_pos.y + ground_offset(key), local_pos.z)
	inst.set_meta("model_key", key)
	if mat != null:
		apply_material(inst, mat)
	parent.add_child(inst)
	return inst

# =============================================================== 缓存

static func cache_stats() -> Dictionary:
	return {
		"scenes": _scene_cache.size(),
		"aabbs": _aabb_cache.size(),
		"textures": _tex_cache.size(),
	}

static func clear_cache() -> void:
	_scene_cache.clear()
	_aabb_cache.clear()
	_tex_cache.clear()