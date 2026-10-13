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
##  后续（第四轮的经济 / 存档）会继续往这里搬：钱袋、驻军、声望、战役进度。
## =============================================================================
class_name GameState
extends RefCounted

## 玩家开局兵力。改这一处即可：部队数值与标签文字都读它。
const PLAYER_START_TROOPS := 37

## 势力显示名。fid < 0（或 255 = 无主之地）时返回兜底文案。
## 三处调用点的兜底文案不同（普通遭遇 / 悬停强盗 / 悬停领地），所以做成参数。
static func faction_name(data: MapData, fid: int, none_text: String = "无阵营") -> String:
	if fid < 0 or fid >= data.factions.size():
		return none_text
	return data.faction(fid).name