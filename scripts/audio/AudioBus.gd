## =============================================================================
##  AudioBus —— 音频总线（Master → Music / Sfx）的唯一写入口
## =============================================================================
##  为什么需要它（路线图第五轮 · 缺陷 G4「无音频总线」）：
##   · 改动前全仓库只有 Sfx.gd 一处 `bus = "Master"`，零 AudioServer 调用，
##     音效与背景音乐全挤在 Master 上，只能靠"每条音各自的 volume_db"分别调：
##     调一次总音量要重算每一声的 dB，而且 BGM 根本不听 master_db 的（见下）。
##   · 现在由 default_bus_layout.tres（Master → Music / Sfx）承担路由，
##     总线名、写回、临时压低（duck）只在本文件里出现。
##
##  分工（改动前 → 改动后，两处都是"修不一致"，不是换音色）：
##   · AudioConfig.master_db：原先只叠在音效的 volume_db 上，**音乐完全不受它影响**
##     （同一份"总音量"管不住 BGM，是个实打实的不一致）。现在写到 Master 总线，
##     一处生效、音效与音乐一起听令；音效播放器不再叠 master_db（否则会算两遍）。
##   · AudioConfig.bgm_db：原先叠在每条 BGM 播放器的 volume_db 上。现在写到 Music 总线，
##     播放器只留"单曲偏移（bgm_map_db / bgm_battle_db）× 淡入增益"。
##     于是 duck() 只需要动一条总线，而不用去改每条播放器。
##     总电平与改动前逐项相等（player 少掉的那几 dB 正好由总线补回）。
##   · 分类音量（combat / parry / move / voice / ui）**仍然在代码里逐声相加**，
##     没有拆成总线：那五档是"音色设计"的一部分（谁该突出），不是混音台的推子。
##
##  降级策略：找不到总线就退到 Master（老检出、或有人删了 .tres），
##  绝不报错、绝不静音整场 —— 门禁对 ERROR 零容忍，而 AudioServer 在 headless
##  （dummy 驱动、无声卡）下同样可用，所以这套逻辑在 CI 里也能验。
## =============================================================================
class_name AudioBus
extends RefCounted

const MASTER := "Master"
const MUSIC := "Music"
const SFX := "Sfx"
const LAYOUT := "res://default_bus_layout.tres"

static var _cfg: AudioConfig = null
static var _duck_db: float = 0.0     ## 当前压低深度（≤ 0；0 = 没压）
static var _applies: int = 0         ## 写回次数（自检断言用）
static var _ducks: int = 0           ## 触发压低次数（自检断言用）

# =============================================================== 查询
static func has_bus(name: String) -> bool:
	return AudioServer.get_bus_index(name) >= 0

## 路由用：能用所选总线就用，否则退 Master（降级而不是静音）
static func route(name: String) -> String:
	return name if has_bus(name) else MASTER

## Master 总线当前音量（dB）
static func master_db() -> float:
	return AudioServer.get_bus_volume_db(0) if has_bus(MASTER) else 0.0

## Music 总线当前音量（dB，已含 duck）
static func music_db() -> float:
	var i := AudioServer.get_bus_index(MUSIC)
	return AudioServer.get_bus_volume_db(i) if i >= 0 else 0.0

## Sfx 总线当前音量（dB）
static func sfx_db() -> float:
	var i := AudioServer.get_bus_index(SFX)
	return AudioServer.get_bus_volume_db(i) if i >= 0 else 0.0

static func duck_db() -> float:
	return _duck_db

static func stats() -> Dictionary:
	return {"applies": _applies, "ducks": _ducks}

# =============================================================== 写回
## 把 AudioConfig 的音量写进总线。幂等，Sfx.setup() 与 Bgm.setup() 各会调一次。
static func apply(cfg: AudioConfig = null) -> void:
	if cfg != null:
		_cfg = cfg
	if _cfg == null:
		return
	if has_bus(MASTER):
		AudioServer.set_bus_volume_db(0, _cfg.master_db)
	if has_bus(MUSIC):
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC), _cfg.bgm_db + _duck_db)
	_applies += 1

## 临时压低音乐，让扇子音（号角 / 开战 / 结算）站到前面。
## db 必须是负值（想"放大"请去 AudioConfig 里改 bgm_db，这里不提供放大器）。
## 恢复靠 SceneTree 计时器，不依赖每帧 tick —— 没有 Main 的自检里也能验。
## 不做嵌套计数：扇子音彼此隔得远，重叠时早恢复一点点不影响听感（有意简化）。
static func duck(db: float, sec: float) -> void:
	if db >= 0.0 or sec <= 0.0 or not has_bus(MUSIC):
		return
	_duck_db = minf(_duck_db, db)
	_ducks += 1
	apply()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_duck_db = 0.0
		apply()
		return
	tree.create_timer(sec).timeout.connect(_unduck)

static func _unduck() -> void:
	if _duck_db == 0.0:
		return
	_duck_db = 0.0
	apply()

# =============================================================== 自检辅助
static func reset() -> void:
	_duck_db = 0.0
	_applies = 0
	_ducks = 0
