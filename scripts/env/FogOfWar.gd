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

func setup(p_cfg: MapConfig) -> void:
	cfg = p_cfg
	explored.resize(RES * RES)
	for i in explored.size():
		explored[i] = 0.0
	image = Image.create_from_data(RES, RES, false, Image.FORMAT_RGBA8, _to_bytes())
	texture = ImageTexture.create_from_image(image)

func _to_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(RES * RES * 4)
	for i in explored.size():
		var v := clampf(explored[i], 0.0, 1.0)
		var o := i * 4
		b[o] = int(v * 255.0)          # R = 已探索
		b[o + 1] = 0
		b[o + 2] = 0
		b[o + 3] = int((1.0 - v) * 205.0)   # A = 迷雾浓度（小地图叠加用）
	return b

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

func update(delta: float, points: Array) -> void:
	if not enabled:
		return
	_accum += delta
	if _accum < 0.2:
		return
	_accum = 0.0
	for p in points:
		reveal(p, cfg.fog_reveal_radius)
	image = Image.create_from_data(RES, RES, false, Image.FORMAT_RGBA8, _to_bytes())
	texture.update(image)
