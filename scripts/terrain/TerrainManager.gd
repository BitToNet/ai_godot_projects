## =============================================================================
##  TerrainManager —— 地形分块网格 + LOD
##
##  地图 1024x1024 分成 8x8 = 64 个 128 米的 Chunk，每个 Chunk 有 4 级 LOD
##  （每边 32 / 16 / 8 / 4 个四边形）。等级按「相机到 Chunk 中心的水平距离」选取：
##      LOD0 < 220m   LOD1 < 400m   LOD2 < 660m   其余 LOD3
##  网格按需生成并缓存（首次访问才 build），因此远处的高精度网格永远不会被创建。
##  每个 Chunk 四周加一圈向下 8 米的「裙边(skirt)」，用来遮盖不同 LOD 之间的接缝。
##
##  性能：LOD0 全图 64*(32*32*2)=131k 三角形；实际同屏通常只有 6~10 个 LOD0 Chunk，
##  远处自动降到 LOD3（每块仅 32 个三角形）。地面始终是 1 个材质、64 个 draw call
##  （被视锥剔除后更少）。
## =============================================================================
class_name TerrainManager
extends Node3D

const CHUNK_SIZE := 128.0
const LOD_QUADS := [32, 16, 8, 4]
const LOD_DIST := [220.0, 400.0, 660.0, 1e9]
const SKIRT := 8.0

var cfg: MapConfig
var data: MapData
var mat: ShaderMaterial

var _chunks: Array = []          ## {node, cx, cz, lod, cache: Dictionary, center: Vector3}
var _rebuild_budget: int = 2
var _timer: float = 0.0

func setup(p_cfg: MapConfig, p_data: MapData, p_mat: ShaderMaterial, focus: Vector3) -> void:
	cfg = p_cfg
	data = p_data
	mat = p_mat
	var n := int(ceil(cfg.map_size / CHUNK_SIZE))
	for cz in n:
		for cx in n:
			var node := MeshInstance3D.new()
			node.name = "Chunk_%d_%d" % [cx, cz]
			node.material_override = mat
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(node)
			var c := Vector3(float(cx) * CHUNK_SIZE + CHUNK_SIZE * 0.5, 0.0, float(cz) * CHUNK_SIZE + CHUNK_SIZE * 0.5)
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
			_apply_lod(ch, lod)

func _apply_lod(ch: Dictionary, lod: int) -> void:
	if _rebuild_budget <= 0:
		return
	var cache: Dictionary = ch.cache
	if not cache.has(lod):
		cache[lod] = _build_chunk_mesh(ch.cx, ch.cz, LOD_QUADS[lod])
		_rebuild_budget -= 1
	ch.node.mesh = cache[lod]
	ch.lod = lod

func _build_chunk_mesh(cx: int, cz: int, quads: int) -> ArrayMesh:
	var hm := data.hm
	var step := CHUNK_SIZE / float(quads)
	var n := quads + 1
	var vcount := n * n
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(vcount); norms.resize(vcount); uvs.resize(vcount)
	var ox := float(cx) * CHUNK_SIZE
	var oz := float(cz) * CHUNK_SIZE
	for j in n:
		var wz := oz + float(j) * step
		for i in n:
			var wx := ox + float(i) * step
			var k := j * n + i
			var y := hm.height_at(wx, wz)
			verts[k] = Vector3(wx, y, wz)
			norms[k] = hm.normal_at(wx, wz)
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
