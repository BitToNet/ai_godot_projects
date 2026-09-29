## =============================================================================
##  NameForge —— 中世纪风格地名生成器（音节拼装，纯程序化）
##  三个势力各有自己的词根表，因此名字风格可区分。
## =============================================================================
class_name NameForge
extends RefCounted

const PREFIX_COMMON := [
	"艾尔", "布兰", "卡", "丹", "埃德", "芬", "加", "海", "伊", "卡德",
	"洛", "莫", "诺", "雷", "斯坦", "索恩", "瓦", "温", "布林", "德",
	"格", "希", "兰", "米", "奥", "罗", "塔", "沃", "泽", "乌",
]
const SUFFIX_COMMON := [
	"堡", "福德", "盖特", "霍尔", "斯泰德", "维克", "穆尔", "菲尔", "港", "要塞",
	"岩", "谷", "岭", "石", "卫", "湖", "林", "郡", "镇", "关",
]
const VILLAGE_FIRST := [
	"上", "下", "东", "西", "南", "北", "老", "新", "大", "小",
]
const VILLAGE_BODY := [
	"麦田", "橡树", "石桥", "磨坊", "牧羊", "河湾", "柳林", "蜂巢", "铁匠", "猎户",
	"白杨", "苹果园", "冬青", "山羊", "犁沟", "炭窑", "泉水", "马厩", "蜂园", "荒坡",
]
const VILLAGE_TAIL := ["村", "庄", "屯", "集", "邑"]

# 势力风味词根（0 = 中央王国, 1 = 北境, 2 = 沙漠苏丹国）
const FACTION_ROOTS := [
	["瓦兰", "卡尔", "瑞德", "阿尔", "罗萨", "伊斯", "米德", "格兰", "兰贝", "塔斯"],
	["诺德", "霜", "凛", "冰", "格罗", "斯卡尔", "铁", "狼", "雪", "石垒"],
	["萨兰", "阿兹", "哈", "贾", "苏丹", "纳", "沙", "塔里", "扎", "穆"],
]
const FACTION_TAIL_CASTLE := ["堡", "要塞", "城堡", "卫城"]
const FACTION_TAIL_TOWN := ["城", "镇", "港", "集市"]
const FACTION_TAIL_VILLAGE := ["村", "绿洲", "营地", "屯垦区"]

var rng: RandomNumberGenerator
var _used: Dictionary = {}

func _init(p_seed: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = p_seed
	rng.state = hash(str(p_seed) + "|names") | 1

func _pick(arr: Array) -> String:
	return str(arr[rng.randi_range(0, arr.size() - 1)])

## kind: "castle" / "town" / "village"
func make_name(kind: String, faction_id: int) -> String:
	for _try in 64:
		var n := _compose(kind, faction_id)
		if not _used.has(n):
			_used[n] = true
			return n
	return _compose(kind, faction_id) + str(rng.randi_range(2, 99))

func _compose(kind: String, faction_id: int) -> String:
	var roots: Array = FACTION_ROOTS[clampi(faction_id, 0, FACTION_ROOTS.size() - 1)]
	match kind:
		"castle":
			return _pick(roots) + _pick(FACTION_TAIL_CASTLE)
		"town":
			if rng.randf() < 0.6:
				return _pick(roots) + _pick(FACTION_TAIL_TOWN)
			return _pick(PREFIX_COMMON) + _pick(SUFFIX_COMMON)
		_:
			if rng.randf() < 0.55:
				return _pick(VILLAGE_FIRST) + _pick(VILLAGE_BODY) + _pick(VILLAGE_TAIL)
			return _pick(roots) + _pick(FACTION_TAIL_VILLAGE)

## 部队名
const LORD_TITLES := ["领主", "公爵", "伯爵", "男爵", "元帅"]
const LORD_GIVEN := ["阿尔", "布莱", "卡西", "德米", "埃里", "法尔", "格里", "哈罗", "伊戈", "尤利"]
const BANDIT_NAMES := ["血手", "黑鸦", "荒漠之狼", "断刃", "灰隼", "夜枭", "盐碱匪帮", "枯骨", "铁钩", "豺群"]
const CARAVAN_NAMES := ["商队", "驼队", "贩盐队", "香料商队", "粮商", "马帮"]

func make_lord(faction_id: int) -> String:
	return _pick(LORD_GIVEN) + _pick(FACTION_ROOTS[clampi(faction_id, 0, 2)]) + "·" + _pick(LORD_TITLES)

func make_bandit() -> String:
	return _pick(BANDIT_NAMES) + "团"

func make_caravan() -> String:
	return _pick(FACTION_ROOTS[rng.randi_range(0, 2)]) + _pick(CARAVAN_NAMES)
