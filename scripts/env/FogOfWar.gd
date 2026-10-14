## =============================================================================
##  FogOfWar —— 战争迷雾（加分项）
##  128x128 的探索度贴图：R 通道 = 已探索程度(0..1)，A 通道 = 1-R（供小地图叠加）
##  地形 / 建筑 / 植被 三个 Shader 都会采样它，把未探索区域压暗。
##  玩家与 AI 部队位置会不断「揭开」迷雾。
## =============================================================================
class_name FogOfWar
extends RefCounted

const RES := 128

var cfg: MapConfig
var explored: PackedFloat32Array
var image: Image
var texture: ImageTexture
var enabled: bool = true
var _accum: float = 0.0
var _bytes: PackedByteArray = PackedByteArray()   ## 常驻 RGBA 缓冲（不再每次重建 Image + 16k 次脚本循环）
var _dirty: bool = false                          ## 自上次上传后是否有格子被揭开

func setup(p_cfg: MapConfig) -> void:
	cfg = p_cfg
	explored.resize(RES * RES)
	for i in explored.size():
		explored[i] = 0.0
	var n := RES * RES
	_bytes.resize(n * 4)
	for i in n:
		_bytes[i * 4 + 3] = 205        # A = 迷雾浓度：初始全未探索
	image = Image.create_from_data(RES, RES, false, Image.FORMAT_RGBA8, _bytes)
	texture = ImageTexture.create_from_image(image)
	_dirty = false

## 把单个格子的探索度写进常驻缓冲（只动被揭开的那一格）
func _write_cell(i: int, v: float) -> void:
	var o := i * 4
	var cv := clampf(v, 0.0, 1.0)
	_bytes[o] = int(cv * 255.0)                  # R = 已探索
	_bytes[o + 3] = int((1.0 - cv) * 205.0)      # A = 迷雾浓度（小地图叠加用）
	_dirty = true

func reveal(p: Vector2, radius: float) -> void:
	var cell := cfg.map_size / float(RES - 1)
	var cx := int(p.x / cell)
	var cz := int(p.y / cell)
	var cr := int(ceil(radius / cell)) + 1
	for dz in range(-cr, cr + 1):
		for dx in range(-cr, cr + 1):
			var x := cx + dx
			var z := cz + dz
			if x < 0 or z < 0 or x >= RES or z >= RES:
				continue
			var q := Vector2(float(x) * cell, float(z) * cell)
			var d := q.distance_to(p)
			if d > radius:
				continue
			var v := 1.0 - smoothstep(radius * 0.55, radius, d)
			var i := z * RES + x
			if v > explored[i]:
				explored[i] = v
				_write_cell(i, v)

func update(delta: float, points: Array) -> void:
	if not enabled:
		return
	_accum += delta
	if _accum < 0.2:
		return
	_accum = 0.0
	for p in points:
		reveal(p, cfg.fog_reveal_radius_m())
	if not _dirty:
		return          # 没有新揭开的格子就不上传：原地不动时原来每 0.2 秒都会重建 + 上传一次
	_dirty = false
	image.set_data(RES, RES, false, Image.FORMAT_RGBA8, _bytes)
	texture.update(image)
