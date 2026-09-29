## =============================================================================
##  MapData —— 全局数据总线
##  生成流程的每一步都把结果放进这里，供地形网格 / 寻路 / 部队 / UI 查询。
## =============================================================================
class_name MapData
extends RefCounted

var cfg: MapConfig
var hm: Heightmap
var gen: HeightmapGenerator
var factions: Array[Faction] = []
var settlements: Array[Settlement] = []
var roads: Array = []            ## Array[PackedVector2Array]
var bridges: Array = []          ## Array[Dictionary]{pos: Vector2, dir: Vector2, len: float}

var nav_fine: NavGrid
var nav_coarse: NavGrid
var nav_road: NavGrid
var path_fine: Pathfinder
var path_coarse: Pathfinder

var splat_image: Image
var splat_texture: ImageTexture
var height_image: Image
var height_texture: ImageTexture
var minimap_image: Image
var minimap_texture: ImageTexture

const TERR_RES := 128
var territory: PackedByteArray    ## 128x128，势力 id，255 = 无主
var territory_cell: float = 8.0

var player_pos: Vector2 = Vector2.ZERO
var party_positions: Array[Vector2] = []   ## 所有部队位置（小地图/提示用）

# ---------------------------------------------------------------- 便捷查询
func height_at(x: float, z: float) -> float:
	return hm.height_at(x, z)

func normal_at(x: float, z: float) -> Vector3:
	return hm.normal_at(x, z)

func slope_at(x: float, z: float) -> float:
	return hm.slope_at(x, z)

func is_water(x: float, z: float) -> bool:
	return hm.height_at(x, z) <= cfg.sea_level + 0.3

func faction(id: int) -> Faction:
	return factions[clampi(id, 0, factions.size() - 1)]

## 领地归属（世界坐标）
func faction_at(x: float, z: float) -> int:
	if territory.is_empty():
		return 255
	var u := clampi(int(x / territory_cell), 0, TERR_RES - 1)
	var v := clampi(int(z / territory_cell), 0, TERR_RES - 1)
	return territory[v * TERR_RES + u]

## 最近定居点
func nearest_settlement(p: Vector2, max_dist: float = 1e9) -> Settlement:
	var best: Settlement = null
	var bd := max_dist
	for s in settlements:
		var d := s.pos.distance_to(p)
		if d < bd:
			bd = d
			best = s
	return best

func settlements_of(faction_id: int) -> Array[Settlement]:
	var out: Array[Settlement] = []
	for s in settlements:
		if s.faction_id == faction_id:
			out.append(s)
	return out

func settlements_of_kind(faction_id: int, kind: int) -> Array[Settlement]:
	var out: Array[Settlement] = []
	for s in settlements:
		if s.faction_id == faction_id and s.kind == kind:
			out.append(s)
	return out
