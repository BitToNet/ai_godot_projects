## =============================================================================
##  AudioConfig —— 音频系统的全部可调参数（@export，可在 Inspector 里实时调）
##
##  · 音效（Sfx）全部是**运行时程序化合成**的（见 SfxSynth.gd），不加载外部音频；
##    背景音乐（Bgm）则是 XSXB-Band 工作室用真实 CC0 录音乐器渲染好的两首曲子
##    （audio/bgm/*.ogg）。两者共用这里的"总开关 / 静音"和各自的音量。
##  · 分类音量按用途分组：打击 / 弹反 / 移动 / 语音提示 / UI。
##    每一档都是叠加在音效自身基准音量之上的 dB 偏移（0 = 不动）。
## =============================================================================
class_name AudioConfig
extends Resource

@export_group("音频 · 总开关")
## 关掉后 Sfx 完全不发声，也不会合成音色（省启动时间）；BGM 同理不播放
@export var enabled: bool = true
## 总音量（dB）
@export var master_db: float = 0.0
## 是否随机抖动音高（同一动作每次听起来略有差别，避免机械重复感）
@export var pitch_jitter: float = 0.05

@export_group("音频 · 背景音乐（BGM）")
## BGM 总音量（dB）。音乐要垫在音效下面，所以默认为负值。
## 两首曲子的成品电平实测：大地图 峰值 -6.5 / 平均 -25.9 dBFS，Boss 战 峰值 -2.5 /
## 平均 -18.4 dBFS；音效是 0.92 峰值归一化（约 -0.7 dBFS），所以这里留 2 dB 底噪余量，
## 让音乐峰值始终比音效低 7 dB 以上，谁也盖不住谁。觉得音乐小了直接把这档往 0 调。
@export var bgm_db: float = -2.0
## 大地图曲目的额外音量偏移（dB）
@export var bgm_map_db: float = 0.0
## Boss 战曲目的额外音量偏移（dB）；战斗曲更密、更响，压一点
@export var bgm_battle_db: float = -2.0
## 进游戏时从静音淡入大地图曲的时长（秒）
@export var bgm_fade_in: float = 2.4
## 进入 Boss 战时切到战斗曲的时长（秒）；战斗要立刻起势，所以短
@export var bgm_fade_battle: float = 0.6
## 战斗结束淡回大地图曲的时长（秒）
@export var bgm_fade_map: float = 1.8

@export_group("音频 · 分类音量（dB）")
@export var combat_db: float = 0.0        ## 命中 / 破防 / 蓄力 / 剑气
@export var parry_db: float = 1.5         ## 弹反打铁声（最需要突出）
@export var move_db: float = -6.0         ## 脚步 / 马蹄 / 起跳 / 落地
@export var voice_db: float = -1.5        ## 受击闷哼 / 怒吼
@export var ui_db: float = -3.0           ## 遭遇提示 / 行军号角 / 结算

@export_group("音频 · 节奏（秒）")
@export var step_interval: float = 0.30   ## 战斗内跑步的脚步间隔
@export var boss_step_interval: float = 0.46  ## Boss 走位的沉重脚步间隔
@export var hoof_interval: float = 0.22   ## 大地图行军马蹄间隔

@export_group("音频 · 其它")
## Boss 出招前的听觉预警：可弹反 = 清脆 "叮"，不可弹反 = 低沉嗡鸣
@export var warn_cues: bool = true
## 音效池大小（同屏最多同时发声数）
@export_range(8, 64, 1) var polyphony: int = 24
## 大地图上能听到部队马蹄声的最远距离（米）
@export var hoof_audible_range: float = 120.0


static func create() -> AudioConfig:
	return AudioConfig.new()


## 取某一分类的音量偏移（供 Sfx 混音时相加）
func category_db(cat: String) -> float:
	match cat:
		"combat": return combat_db
		"parry": return parry_db
		"move": return move_db
		"voice": return voice_db
		"ui": return ui_db
	return 0.0
