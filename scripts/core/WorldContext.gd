## =============================================================================
##  WorldContext —— 各个系统共享的那一份「世界句柄」
##
##  为什么要有它：遭遇 / Boss 战 / 生成管线这几块互相回调（开战要停时间、
##  战败要把玩家推开、推开要重新下达行军令），如果每块都各自持有一堆零散引用，
##  拆到一半就会变成「谁的字段是谁的」猜谜。这里把「谁都可能用到的东西」集中一份，
##  系统只读它、通过信号回写，Main 只负责在装配完成后把值塞进来。
##
##  约定：
##   · 只放**引用**，不放状态机（状态属于各个系统自己）；
##   · parties 是引用语义（Append 会同步可见），别在这里复制数组；
##   · 需要「行为」而不是数据时，宁可加一个小工具方法（如 set_camera_active），
##     也不要让每个系统各写一遍。
## =============================================================================
class_name WorldContext
extends RefCounted

var host: Node3D                 ## Main 自己：挂子节点 / 取视口用
var cfg: MapConfig
var audio: AudioConfig
var data: MapData
var hud: HUD
var camera: CameraRig
var router: InputRouter
var time: TimeFlowController
var rules: EncounterRules
var view: OverworldView
var day_night: DayNightCycle
var player: PlayerParty
var parties: Array[AIParty] = []
var economy: EconomyRules        ## 经济数值表（第四轮）
var campaign: CampaignState      ## 战役可变状态：钱袋 / 补给 / 士气 / 声望（第四轮）

## 相机的输入开关。遭遇框（选项切换复用方向键）与 Boss 战期间都要关掉地图操作，
## 不关的话「在对话框里按 →」会连带把镜头也拖走。
func set_camera_active(v: bool) -> void:
	if camera == null:
		return
	camera.process_mode = Node.PROCESS_MODE_INHERIT if v else Node.PROCESS_MODE_DISABLED