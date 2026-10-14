## =============================================================================
##  GameState —— 跨系统共享的运行时状态与全局数值
##
##  第三轮先收拢两处「散落在各文件里的同一件事」：
##    · 玩家初始兵力 37 在 Main.gd 写了两遍（setup_player 参数 + 标签文字）
##      → GameState.PLAYER_START_TROOPS
##    · 势力名的「无阵营」兜底文案有三份近似拷贝
##      （"无阵营" / "无阵营（流寇）" / "无主之地"）
##      → GameState.faction_name()
##  以及一处弱类型侧信道：Main 用 data.set_meta("player_ref", player)、
##  AIParty 每帧 get_meta 取回 → 改成 AIParty.player_target（typed，由 PartySpawner 注入）。
##
##  第四轮补齐了开局常量：钱袋 / 补给 / 士气 / 声望 / 兵员档次。**开局值只在这里**，
##  运行时会变的那一份在 CampaignState（那才是「一局游戏的状态」，会被存档序列化）。
##  凡是「第一次进游戏时应该有多少」的问题，答案都在本文件。
## =============================================================================
class_name GameState
extends RefCounted

## 玩家开局兵力。改这一处即可：部队数值与标签文字都读它。
const PLAYER_START_TROOPS := 37

## ---- 第四轮：战役开局值 ----
## 开局钱袋。参考：骑砍玩家开局钱数在原文档里【未解】（存于 exe），
## 这里按「够付约 8 周军费 + 一次升档」定，保证开局能升级、但升完就紧张。
const START_DENARS := 400
## 开局补给（件）。每 10 兵每天吃 1 件 → 37 兵约 12 天。
const START_SUPPLIES := 35
## 开局士气（EconomyRules.morale_of 会立刻按部队规模重算一次）
const START_MORALE := 50
## 开声望 / 兵员档次
## 开局声望 120 是**本地化取值**，不是骑砍原值（骑砍开局声望存于 exe，原文【未解】）。
## 取 120 的理由：它给出「领导力 1」，使 37 人开局正好落在
##   士气 50 + 12 − 37 + 15 = 40（中性）
##   编制 40 + 5 + 6 = 51（留出 14 个补兵位）
## 这两条一起把开局放在「能补兵、但军费已经能感觉到」的位置。
const START_RENOWN := 120
const START_TIER := 0

## 军费结算周期：7 天一发（照搬骑砍的周薪口径，见 EconomyRules 头部说明）
const DAYS_PER_WAGE_CYCLE := 7

## 势力显示名。fid < 0（或 255 = 无主之地）时返回兜底文案。
## 三处调用点的兜底文案不同（普通遭遇 / 悬停强盗 / 悬停领地），所以做成参数。
static func faction_name(data: MapData, fid: int, none_text: String = "无阵营") -> String:
	if fid < 0 or fid >= data.factions.size():
		return none_text
	return data.faction(fid).name

## 部队类型的显示名（AIParty.ai_kind() → 中文）。
## 悬停提示与选中面板都要它：以前这张映射表只写在 HoverInspector 里，
## 加第二个使用点时就必须搬出来，否则两处各写一份、改一处忘一处。
static func party_kind_name(ai_kind: String) -> String:
	return {
		"lord": "领主部队",
		"caravan": "商队",
		"bandit": "强盗团伙",
	}.get(ai_kind, "部队")