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

# ---------------------------------------------------------------- 第四轮：城镇交互
## 繁荣度 0..100（照搬 05 §? 「繁荣度 = slot 50，钳 [0,100]，按 20 一档分 5 级」的形状）。
## 在生成期由 SettlementSystem.assign_environment() 用**独立随机流**填好。
var prosperity: int = 50
## 可招募志愿者：招募时按实际招到的人数**写回扣减**（原文是 each −1，不是清零）—— 01 §2.7
var volunteers: int = 0
var volunteers_cap: int = 0
## 每种货物的本地价差（百分比，−15..+15）：让「这儿便宜、那儿贵」有路线可走
var good_bias: Array[int] = []

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

# ---------------------------------------------------------------- 第四轮：城镇交互
## 交互半径：定居点自身半径 + 一点余量（玩家要能站在城墙外就进城）
func interact_radius() -> float:
	return radius + 6.0

## 繁荣度档名（0..20 荒废 / 20..40 萧条 / 40..60 平常 / 60..80 富庶 / 80..100 繁荣）
func prosperity_name() -> String:
	var names := ["荒废", "萧条", "平常", "富庶", "繁荣"]
	return names[clampi(prosperity / 20, 0, names.size() - 1)]

## 这个定居点提供哪些服务（**服务项本身是文档【未解】的，这里是本地化设计**）：
##   · 城堡：只有补给与驻军 —— 军事据点，不赶集、不招兵
##   · 城镇：补给 / 招募 / 贸易 / 驻军（原文城镇有 5 项服务，本工程没有酒馆与竞技场）
##   · 村庄：补给 / 招募（原文村庄只有长老的 1 项服务，本工程把「买粮」也算进村庄）
## 条目顺序 = 菜单顺序，HUD 只照着画，不自己判断谁能做什么。
func service_ids() -> Array[String]:
	var out: Array[String] = []
	match kind:
		Kind.CASTLE:
			out = ["supply", "garrison", "leave"]
		Kind.TOWN:
			out = ["supply", "recruit", "trade", "garrison", "leave"]
		_:
			out = ["supply", "recruit", "leave"]
	return out

func has_service(id: String) -> bool:
	return service_ids().has(id)
