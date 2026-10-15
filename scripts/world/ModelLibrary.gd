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
	var h := body_box(key).size.y
	if h <= 0.0001:
		return 1.0
	return float(e["target_m"]) / h

## 接地偏移（世界单位，直接加到 position.y 上）：把模型最低点贴到 y = 0
static func ground_offset(key: String) -> float:
	return -body_box(key).position.y * world_scale(key)

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

# =============================================================== 身体轮廓（第④批）
#
# 默认（建筑那套）就是网格包围盒。清单条目可以声明 "body": "skinned" —— 那时只量
# **带蒙皮**的网格，并用蒙皮公式还原静置姿态的真实形状：
#
#     p = Σ w_i × (bone_global_rest × inverse_bind_i) × v
#
# 为什么必须有这条分支：unit_knight.glb 的包围盒高 2.4666 米，但它 15 个网格节点里有
# 9 个**不带蒙皮**（武器 / 备用网格），最高点其实是一把武器；身体轮廓只有 2.3145 米。
# 按包围盒定倍率，1.85 米的骑士会变成 1.74 米 —— 差 6%，肉眼看不出来。
# 更隐蔽的是：带蒙皮的面在 mesh 里存的 aabb 是**绑定空间**的界限（可能整块偏在原点下方），
# 拿它当"身高"会得到一个凭空的数。所以这条分支只认蒙皮顶点还原出来的形状。
static func body_box(key: String) -> AABB:
	var e := entry(key)
	if str(e.get("body", "aabb")) != "skinned":
		return merged_aabb(key)
	var inst := instance(key)
	if inst == null:
		return AABB()
	var acc: Array = []
	_collect_skinned(inst, Transform3D.IDENTITY, acc)
	inst.free()
	if acc.is_empty():
		return merged_aabb(key)
	var out: AABB = acc[0]
	for i in range(1, acc.size()):
		out = out.merge(acc[i])
	return out

static func _collect_skinned(node: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if node is Node3D:
		t = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.skin != null:
			_skinned_box(mi, t, acc)
	for c in node.get_children():
		_collect_skinned(c, t, acc)

static func _skinned_box(mi: MeshInstance3D, xf: Transform3D, acc: Array) -> void:
	var skel := _find_skeleton(mi)
	if skel == null:
		acc.append(xf * mi.mesh.get_aabb())
		return
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty():
			continue
		if bones.size() < verts.size() * 4 or weights.size() < verts.size() * 4:
			acc.append(xf * mi.mesh.get_aabb())
			continue
		var box := AABB()
		for i in verts.size():
			var p := Vector3.ZERO
			for k in 4:
				var w := weights[i * 4 + k]
				if w <= 0.0:
					continue
				var bind := bones[i * 4 + k]
				p += w * ((skel.get_bone_global_rest(mi.skin.get_bind_bone(bind)) * mi.skin.get_bind_pose(bind)) * verts[i])
			var wp := xf * p
			if i == 0:
				box = AABB(wp, Vector3.ZERO)
			else:
				box = box.expand(wp)
		acc.append(box)

static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null

## 公开版（部队拼装要用：rig 里第一个网格节点留给拾取 / 音效判定）
static func first_mesh(root: Node) -> MeshInstance3D:
	return _first_mesh(root)

# =============================================================== 动画（第④批）

const ANIM_RATE_MIN := 0.30
const ANIM_RATE_MAX := 2.50

## 片段名解析：清单写**逻辑名**（Gallop），实际片段可能带 glTF 导入器的骨架前缀
## （坐骑实测是 AnimalArmature|Gallop）。先精确匹配，再按 "|名字" 后缀匹配。
static func resolve_clip(ap: AnimationPlayer, want: String) -> String:
	if ap == null or want == "":
		return ""
	var list := ap.get_animation_list()
	if list.has(want):
		return want
	var suffix := "|" + want
	for n in list:
		if n.ends_with(suffix):
			return n
	return ""

## 递归找 AnimationPlayer 并缓存到节点上（部队每帧要用，不能每帧遍历子树）
static func animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node.has_meta("_ap"):
		var c = node.get_meta("_ap")
		if is_instance_valid(c):
			return c as AnimationPlayer
	for ch in node.get_children():
		if ch is AnimationPlayer:
			node.set_meta("_ap", ch)
			return ch as AnimationPlayer
	for ch in node.get_children():
		var ap := animation_player(ch)
		if ap != null:
			node.set_meta("_ap", ap)
			return ap
	return null

## 切运动状态（state = "move" / "idle"）。
##   · **只在换片段时重播**：每帧 play() 会把动画按回 0 秒 —— 走起来就是原地抽搐
##   · 速率 = 实际速度 ÷ 清单参考速度，夹到 0.30~2.50。我们这个世界部队 34~46 米/秒，
##     按真实比例要 7~9 倍频；夹住之后是"快而不失真"，与参考项目同一取舍。
static func play_motion(node: Node3D, key: String, state: String, speed: float) -> void:
	if node == null:
		return
	var ap := animation_player(node)
	if ap == null:
		return
	var e := entry(key)
	if e.is_empty():
		return
	var want := str(e.get("anim_move", "")) if state == "move" else str(e.get("anim_idle", ""))
	var clip := resolve_clip(ap, want)
	if clip == "":
		return
	if str(node.get_meta("clip", "")) == clip and ap.is_playing():
		return
	node.set_meta("clip", clip)
	ap.play(clip)
	var ref := maxf(float(e.get("anim_ref_speed", 1.0)), 0.01)
	ap.speed_scale = clampf(speed / ref, ANIM_RATE_MIN, ANIM_RATE_MAX) if state == "move" else 1.0

## 骑手落座偏移（世界米）—— **推**出来的，不抄参考项目的 0.8839（那是它 468 米世界的标定）：
##   背高 = 坐骑实测高 × 坐骑倍率（坐骑静止姿态下全身最高点就是背）
##   胯高 = 骑手实测高 × 骑手倍率 × RIDER_HIP_FRAC
## 相减即得：骑手胯骨正好落在马背上。tools/party_model_check.gd 断言它落在合理区间。
static func rider_offset_y(mount_key: String, rider_key: String) -> float:
	var back := body_box(mount_key).size.y * world_scale(mount_key)
	var hip := body_box(rider_key).size.y * world_scale(rider_key) * AssetManifest.RIDER_HIP_FRAC
	return back - hip

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

## 第一个网格节点的有效材质（material_override → surface_override → mesh 自带，三条路都试）。
## 为什么需要它：坐骑是平色的（材质非空但 albedo_texture 为空），只判贴图会把
## "模型自带材质"这件事整个漏掉。
static func material_of(key: String) -> Material:
	var inst := instance(key)
	if inst == null:
		return null
	var mi := _first_mesh(inst)
	var m: Material = null
	if mi != null:
		if mi.material_override != null:
			m = mi.material_override
		elif mi.get_surface_override_material_count() > 0 and mi.get_surface_override_material(0) != null:
			m = mi.get_surface_override_material(0)
		elif mi.mesh != null and mi.mesh.get_surface_count() > 0:
			m = mi.mesh.surface_get_material(0)
	inst.free()
	return m

## 把材质递归盖到实例的每个 MeshInstance3D 上（含阴影设置：程序化几何那边是显式打开的）
static func apply_material(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in node.get_children():
		apply_material(c, mat)

# =============================================================== 落位

## 例化并就地放好（缩放 + 贴地），**不入树、不定位** —— spawn_at 与部队拼装共用这一条路径，
## 免得"建筑按包围盒贴地、部队按蒙皮轮廓贴地"两套写法各自漂移。
static func build(key: String) -> Node3D:
	var inst := instance(key)
	if inst == null:
		return null
	inst.scale = Vector3.ONE * world_scale(key)
	inst.position = Vector3(0.0, ground_offset(key), 0.0)
	inst.set_meta("model_key", key)
	return inst

## 在 parent 的局部坐标 local_pos 处放一个模型：自动缩放、贴地、转向，返回实例（失败 null）。
## 注意 position.y 用的是**已缩放**的偏移，所以直接加在 position 上，不再乘 scale。
static func spawn_at(key: String, parent: Node3D, local_pos: Vector3, yaw: float, mat: Material = null) -> Node3D:
	if parent == null:
		return null
	var inst := build(key)
	if inst == null:
		return null
	inst.rotation.y = yaw
	inst.position = Vector3(local_pos.x, local_pos.y + ground_offset(key), local_pos.z)
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