## =============================================================================
##  Settlement —— 单个定居点数据（城堡 / 城镇 / 村庄）
## =============================================================================
class_name Settlement
extends RefCounted

enum Kind { CASTLE, TOWN, VILLAGE }

var id: int = 0
var name: String = ""
var kind: int = Kind.VILLAGE
var faction_id: int = 0
var pos: Vector2 = Vector2.ZERO      ## 世界 XZ
var ground_h: float = 0.0            ## 平整后的地基高度
var radius: float = 14.0
var garrison: int = 12
var node: Node3D = null              ## 建筑网格挂载点
var label: Label3D = null
var parent_town: int = -1             ## 村庄所属城镇
var neighbors: Array[int] = []        ## 道路连通的定居点 id

func kind_name() -> String:
	match kind:
		Kind.CASTLE:
			return "王都·城堡"
		Kind.TOWN:
			return "城镇"
		_:
			return "村庄"

func importance() -> float:
	match kind:
		Kind.CASTLE:
			return 1.0
		Kind.TOWN:
			return 0.80
		_:
			return 0.55
