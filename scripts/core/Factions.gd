## =============================================================================
##  Factions —— 三大势力定义（主色 / 领地方向偏好 / 名称）
## =============================================================================
class_name Faction
extends RefCounted

var id: int = 0
var name: String = ""
var color: Color = Color.WHITE        ## 主色（旗帜、标签、小地图领地）
var color_dark: Color = Color.BLACK   ## 建筑/深色变体
var home_dir: Vector2 = Vector2(0.5, 0.5)  ## 领地偏好（归一化 UV）
var biome_pref: int = 0               ## 0 = 草原, 1 = 北境雪山, 2 = 沙漠

static func build_all() -> Array[Faction]:
	var list: Array[Faction] = []

	var f0 := Faction.new()
	f0.id = 0
	f0.name = "瓦兰迪亚王国"
	f0.color = Color(0.80, 0.22, 0.20)
	f0.color_dark = Color(0.45, 0.12, 0.11)
	f0.home_dir = Vector2(0.55, 0.60)
	f0.biome_pref = 0
	list.append(f0)

	var f1 := Faction.new()
	f1.id = 1
	f1.name = "诺德霜原"
	f1.color = Color(0.22, 0.45, 0.85)
	f1.color_dark = Color(0.12, 0.24, 0.50)
	f1.home_dir = Vector2(0.40, 0.26)
	f1.biome_pref = 1
	list.append(f1)

	var f2 := Faction.new()
	f2.id = 2
	f2.name = "萨兰德苏丹国"
	f2.color = Color(0.88, 0.72, 0.16)
	f2.color_dark = Color(0.52, 0.40, 0.08)
	f2.home_dir = Vector2(0.80, 0.52)
	f2.biome_pref = 2
	list.append(f2)

	return list
