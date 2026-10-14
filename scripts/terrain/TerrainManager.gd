## =============================================================================
##  TerrainManager —— 地形分块网格 + LOD
##
##  地图按 map_size / CHUNK_SIZE 分成 n×n 个 Chunk。1024 m 图上是 8x8 = 64 个 128 米的 Chunk，
##  每个 Chunk 有 4 级 LOD（每边 32 / 16 / 8 / 4 个四边形，即顶点间距恒为 MESH_SPACING = 4 m）。
##  等级按「相机到 Chunk 中心的水平距离」选取：
##      LOD0 < 220m   LOD1 < 400m   LOD2 < 660m   其余 LOD3
##  网格按需生成并缓存（首次访问才 build），因此远处的高精度网格永远不会被创建。
##  每个 Chunk 四周加一圈向下 8 米的「裙边(skirt)」，用来遮盖不同 LOD 之间的接缝。
##
##  换地图尺寸（ROADMAP §12.5 #5）：分块边长与每级四边形数都由 map_size 推导（见 chunk_size_for /
##  lod_quads_for）。1024 m 下两者算出来就是本文件里的旧常量，所以既有世界逐位不变；
##  4096 m 下变成 256 m 分块、16×16 = 256 块、每级四边形数翻倍（顶点间距仍 4 m）。
##
##  性能：1024 m 图上 LOD0 全图 64*(32*32*2)=131k 三角形；实际同屏通常只有 6~10 个 LOD0 Chunk，
##  远处自动降到 LOD3（每块仅 32 个三角形）。地面始终是 1 个材质、64 个 draw call
##  （被视锥剔除后更少）。
## =============================================================================
class_name TerrainManager
extends Node3D

const CHUNK_SIZE := 128.0        ## 1024 m 图的分块边长；同时也是推导下限
const LOD_QUADS := [32, 16, 8, 4] ## 1024 m 图的每级四边形数（LOD0 间距 = MESH_SPACING）
const LOD_DIST := [220.0, 400.0, 660.0, 1e9]
const SKIRT := 8.0
## 每级网格的顶点间距（米）。分块变大时四边形数**同步放大**，这条间距保持不变 ——
## 理由：SKIRT（8 m 裙边）与 LOD_DIST（米）都是按这个间距调出来的（见 §16.2 的说明）。
const MESH_SPACING := 4.0

## 分块边长按地图尺寸推导：1024 m 及以下仍是 128 m（8×8 = 64 块，与既有世界逐位一致），
## 4096 m 时 256 m（16×16 = 256 块）。见 ROADMAP §12.5 的 #5。
static func chunk_size_for(map_size: float) -> float:
	return maxf(CHUNK_SIZE, map_size / 16.0)

## 每级四边形数：随分块等比放大，让 MESH_SPACING 不随地图尺寸变化。
## 只放大分块而不放大四边形数，等于同时改掉「网格精度 / 裙边余量 / LOD 距离」三件事 ——
## 探针里的顶点位置与法线指纹也会跟着变，而那不是本批想改的东西。
static func lod_quads_for(map_size: float) -> Array:
	var k := chunk_size_for(map_size) / CHUNK_SIZE      # 1024 m ⇒ 1.0；4096 m ⇒ 2.0
	var out := []
	for q in LOD_QUADS:
		out.append(maxi(1, int(round(float(q) * k))))
	return out

var cfg: MapConfig
var data: MapData
var mat: ShaderMaterial

var _chunks: Array = []          ## {node, cx, cz, lod, cache: Dictionary, center: Vector3}
var _rebuild_budget: int = 2
var _timer: float = 0.0

## 本实例的分块边长 / 每级四边形数：都从 cfg 推导，而不是缓存在成员里 ——
## scale_probe 会绕过 setup() 直接调 _build_chunk_mesh()，缓存在 setup 里的值在那种用法下是空的。
func chunk_size() -> float:
	return chunk_size_for(cfg.map_size) if cfg != null else CHUNK_SIZE

func lod_quads() -> Array:
	return lod_quads_for(cfg.map_size) if cfg != null else LOD_QUADS

func setup(p_cfg: MapConfig, p_data: MapData, p_mat: ShaderMaterial, focus: Vector3) -> void:
	cfg = p_cfg
	data = p_data
	mat = p_mat
	var cs := chunk_size()
	var n := int(ceil(cfg.map_size / cs))
	for cz in n:
		for cx in n:
			var node := MeshInstance3D.new()
			node.name = "Chunk_%d_%d" % [cx, cz]
			node.material_override = mat
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(node)
			var c := Vector3(float(cx) * cs + cs * 0.5, 0.0, float(cz) * cs + cs * 0.5)
			_chunks.append({"node": node, "cx": cx, "cz": cz, "lod": -1, "cache": {}, "center": c})
	# 先全部建 LOD3（最粗，很便宜），保证开场瞬间地面不会缺块
	_rebuild_budget = 1 << 30
	for ch in _chunks:
		_apply_lod(ch, 3)
	_update_lods(focus, true)
	_rebuild_budget = 2

func _process(delta: float) -> void:
	_timer += delta
	if _timer < 0.25:
		return
	_timer = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_rebuild_budget = 2
	_update_lods(cam.global_position, false)

func _update_lods(cam_pos: Vector3, force: bool) -> void:
	# 先算出「想换到哪一级」，再按距离从近到远处理：缓存命中的换级是免费的（见 _apply_lod），
	# 真正吃预算的是新建块 —— 每 0.25 s 只有 2 次新建机会，应该优先喂给离相机最近的块，
	# 否则按数组顺序（行的顺序）处理时，远处块会先把这两次机会抢走
	var want: Array = []
	for ch in _chunks:
		var c: Vector3 = ch.center
		var d := Vector2(cam_pos.x - c.x, cam_pos.z - c.z).length()
		var lod := 3
		for i in LOD_DIST.size():
			if d < LOD_DIST[i]:
				lod = i
				break
		# 迟滞：避免在阈值附近来回抖动
		if not force and ch.lod >= 0:
			if lod < ch.lod and d > LOD_DIST[maxi(0, ch.lod - 1)] * 0.92:
				lod = ch.lod
		if lod != ch.lod:
			want.append({"ch": ch, "lod": lod, "d": d})
	if want.is_empty():
		return
	want.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	for w in want:
		_apply_lod(w["ch"], int(w["lod"]))

func _apply_lod(ch: Dictionary, lod: int) -> void:
	# 缓存命中必须**先于**预算判断：换级本该是免费的（网格早就在内存里），
	# 6a 的探针把这条暴露出来了 —— 原来缓存命中也被 _rebuild_budget 挡着，
	# 相机一动就要等好几帧才换级（远处先糊、近处先清），而预算真正该约束的是新建
	var cache: Dictionary = ch.cache
	var mesh = cache.get(lod)
	if mesh == null:
		if _rebuild_budget <= 0:
			return
		mesh = _build_chunk_mesh(ch.cx, ch.cz, int(lod_quads()[lod]))
		cache[lod] = mesh
		_rebuild_budget -= 1
	ch.node.mesh = mesh
	# LOD2/3 只在远处出现：关掉它们的阴影投射（远处地形的阴影本来也糊成一团）
	ch.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lod >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	ch.lod = lod

func _build_chunk_mesh(cx: int, cz: int, quads: int) -> ArrayMesh:
	var hm := data.hm
	var cs := chunk_size()
	var step := cs / float(quads)
	var n := quads + 1
	var vcount := n * n
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(vcount); norms.resize(vcount); uvs.resize(vcount)
	var ox := float(cx) * cs
	var oz := float(cz) * cs
	# ---- 高度格 + 中心差分法线 ----
	# 原来每顶点调一次 hm.normal_at()，它内部是 4 次 height_at（±cell 有限差分）——
	# 一块 LOD0 = 1089 顶点 × 5 次采样。改成「先把这一块（含一圈外环）的高度算成格点数组，
	# 再从相邻格点做中心差分」：每顶点 1 次采样 + 4 次数组读（探针实测单顶点 4.09 → 0.8 µs 量级，
	# 见 ROADMAP §12.2）。外环是为了让**边界顶点也能用中心差分**，否则块与块之间的法线会有光照缝。
	# 法线公式与 Heightmap.normal_at 相同（(h(x-s)-h(x+s), 2s, h(z-s)-h(z+s)) 再归一化），
	# 但差分步长从固定的高度图 cell（本工程 heightmap_res=513 / 1024 m → 2 m）换成了**本级网格的步长**
	# （LOD0 4 m / LOD1 8 m / LOD2 16 m / LOD3 32 m）。这是本次唯一有视觉含义的取舍：法线不再"过采样"
	# 细于本级网格的起伏 —— 近处略微平滑、远处明显更平（远处本来也看不出，且 LOD2/3 已关阴影）。
	# 顶点位置与索引**逐位不变**（探针 terrain_pos_hash / terrain_idx_hash 为证），只有 terrain_norm_hash 变。
	# 想连法线也逐位不变，就得按 2 m 建格（LOD0 一块 67x67 = 4489 次采样约 3.4 ms），比现在慢一倍多，不值。
	var g := quads + 3
	var grid := PackedFloat64Array()
	grid.resize(g * g)
	for j in g:
		var wz := oz + float(j - 1) * step
		var row := j * g
		for i in g:
			grid[row + i] = hm.height_at(ox + float(i - 1) * step, wz)
	for j in n:
		var wz := oz + float(j) * step
		for i in n:
			var wx := ox + float(i) * step
			var k := j * n + i
			var gc := (j + 1) * g + (i + 1)
			verts[k] = Vector3(wx, grid[gc], wz)
			norms[k] = Vector3(grid[gc - 1] - grid[gc + 1], 2.0 * step, grid[gc - g] - grid[gc + g]).normalized()
			uvs[k] = Vector2(wx / 16.0, wz / 16.0)
	var idx := PackedInt32Array()
	idx.resize(quads * quads * 6)
	var w := 0
	for j in quads:
		for i in quads:
			var a := j * n + i
			var b := a + 1
			var c := a + n + 1
			var d := a + n
			# 绕序 (a,b,c)+(a,c,d) → 法线朝上（Godot 正面为顺时针）
			idx[w] = a; idx[w + 1] = b; idx[w + 2] = c
			idx[w + 3] = a; idx[w + 4] = c; idx[w + 5] = d
			w += 6
	# ---- 裙边：四周向下的垂直面，遮住 LOD 接缝 ----
	var verts2 := verts.duplicate()
	var norms2 := norms.duplicate()
	var uvs2 := uvs.duplicate()
	var idx2 := idx.duplicate()
	_add_skirt(verts2, norms2, uvs2, idx2, n, quads)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts2
	arrays[Mesh.ARRAY_NORMAL] = norms2
	arrays[Mesh.ARRAY_TEX_UV] = uvs2
	arrays[Mesh.ARRAY_INDEX] = idx2
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

func _add_skirt(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array, n: int, quads: int) -> void:
	# 四条边：0 = -Z, 1 = +Z, 2 = -X, 3 = +X
	for edge in 4:
		for i in quads:
			var i0 := 0
			var i1 := 0
			var out_n := Vector3.ZERO
			match edge:
				0:
					i0 = i
					i1 = i + 1
					out_n = Vector3(0, 0, -1)
				1:
					i0 = (n - 1) * n + i
					i1 = i0 + 1
					out_n = Vector3(0, 0, 1)
				2:
					i0 = i * n
					i1 = i0 + n
					out_n = Vector3(-1, 0, 0)
				_:
					i0 = i * n + (n - 1)
					i1 = i0 + n
					out_n = Vector3(1, 0, 0)
			var a := verts[i0]
			var b := verts[i1]
			var c := b - Vector3(0, SKIRT, 0)
			var d := a - Vector3(0, SKIRT, 0)
			var base := verts.size()
			verts.append(a); verts.append(b); verts.append(c); verts.append(d)
			var uv_a := Vector2(a.x, a.z) / 16.0
			var uv_b := Vector2(b.x, b.z) / 16.0
			uvs.append(uv_a); uvs.append(uv_b); uvs.append(uv_b); uvs.append(uv_a)
			for _k in 4:
				norms.append(out_n)
			idx.append(base); idx.append(base + 1); idx.append(base + 2)
			idx.append(base); idx.append(base + 2); idx.append(base + 3)

## 让所有 Chunk 立刻以最高精度重建（用于截图/调试）
func force_full_lod() -> void:
	for ch in _chunks:
		ch.lod = -1
	_rebuild_budget = 9999
	_update_lods(Vector3(cfg.map_size * 0.5, 0, cfg.map_size * 0.5), true)
