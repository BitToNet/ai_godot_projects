class_name Bgm
extends RefCounted
## 背景音乐（BGM）。
##
## 曲目由 XSXB-Band（小宝乐队）本地工作室写谱 + 用真实 CC0 录音乐器渲染，
## 放在 `res://audio/bgm/`。大地图一首、Boss 战一首，切换时做线性增益交叉淡入淡出。
##
## 总线：音乐挂在 **Music** 总线上（default_bus_layout.tres：Master → Music / Sfx）。
## 音量因此分两层：总线上的 `AudioConfig.bgm_db`（还能被 AudioBus.duck 临时压低，
## 让号角 / 结算这类扇子音站到前面），播放器上的单曲偏移 × 淡入增益。
## 改动前 bgm_db 是逐条叠在播放器 volume_db 上的 —— 总线方案下这两处总和相等。
##
## 和 `Sfx` 一样是纯静态类，由 `Main` 驱动：
##   setup() 建播放器 → play() 切曲 → tick(delta) 每帧推进淡入淡出。
## 静音不另存状态，直接读 `Sfx.is_muted()`，所以 M 键一次同时关掉音效与音乐。
## 资源缺失时静默降级（刚克隆还没放音频时游戏照常跑，只是没有音乐）。

const SILENT_GAIN := 0.0008          ## 低于此线性增益即停掉播放器，免得白占一路声部
const MUTE_FADE := 0.25              ## 按 M 静音 / 恢复时的淡化时长（秒）
const TRACKS := {
	"map": "res://audio/bgm/map_theme.ogg",
	"battle": "res://audio/bgm/battle_theme.ogg",
}

static var _host: Node = null
static var _cfg: AudioConfig = null
static var _players: Dictionary = {}     ## id -> AudioStreamPlayer
static var _gain: Dictionary = {}        ## id -> 当前线性增益 0..1
static var _target: Dictionary = {}      ## id -> 目标线性增益 0..1
static var _want: String = ""            ## 当前曲目 id（"" = 全部停）
static var _fade: float = 1.2
static var _muted_last := false          ## 上一帧的静音状态（用于切换时改用短淡化）
static var _counts: Dictionary = {}      ## id -> 累计切换次数（调试面板用）
static var _ready := false

static func setup(host: Node, cfg: AudioConfig = null) -> void:
	if host == null:
		return
	_host = host
	_cfg = cfg
	_ready = true
	AudioBus.apply(_cfg)        # 音乐音量落到 Music 总线（setup 早于 / 晚于 Sfx 都无所谓，幂等）

static func is_ready() -> bool:
	return _ready

static func current() -> String:
	return _want

## 切到某一首曲目。fade 是淡入淡出秒数（大地图 → 战斗用短淡入，回大地图用长淡出）
static func play(id: String, fade: float = 1.2) -> void:
	if not _ready or _host == null or not is_instance_valid(_host):
		return
	if id == _want or not TRACKS.has(id):
		return
	if not _ensure(id):
		return
	_want = id
	_fade = maxf(0.05, fade)
	for other in _players.keys():
		_target[other] = 1.0 if other == id else 0.0
	_counts[id] = int(_counts.get(id, 0)) + 1

## 停止全部音乐（例如回到主菜单；本工程目前只用于测试）
static func stop(fade: float = 1.0) -> void:
	if not _ready:
		return
	_want = ""
	_fade = maxf(0.05, fade)
	for id in _players.keys():
		_target[id] = 0.0

## 每帧推进交叉淡入淡出。必须放在 `Main._process` 的最前面 ——
## 战斗时 `_process` 会提前 return，写晚了战斗中就没法淡出。
## 静音不单独暂停播放器：暂停会让 `playing` 变 false，而下面"没在播就补 play()"
## 会把曲子每帧从 0 秒重开（听起来是嗡嗡的爆音）。所以静音就是"把增益淡到 0"。
static func tick(delta: float) -> void:
	if not _ready or _players.is_empty():
		return
	var muted: bool = Sfx.is_muted()
	if muted != _muted_last:
		# 玩家按 M 时希望立刻有反应，别等上一段淡化（起播时可能是 2.4 s）走完
		_muted_last = muted
		_fade = MUTE_FADE
	var step: float = delta / _fade
	for id in _players.keys():
		var p: AudioStreamPlayer = _players[id]
		if p == null or not is_instance_valid(p):
			continue
		var g: float = float(_gain.get(id, 0.0))
		var t: float = float(_target.get(id, 0.0))
		if muted:
			t = 0.0
		if g < t:
			g = minf(t, g + step)
		elif g > t:
			g = maxf(t, g - step)
		_gain[id] = g
		if g <= SILENT_GAIN:
			# 低于阈值就真的停掉这一路（下次 play() 会从头播）
			if p.playing:
				p.stop()
			p.volume_db = -80.0
			continue
		if not p.playing:
			p.play()
		p.volume_db = _base_db(id) + linear_to_db(g)

# ------------------------------------------------------------------ 内部

## 懒加载：第一次真正需要某首曲目时才 load + 建播放器
static func _ensure(id: String) -> bool:
	if _players.has(id):
		return true
	var path: String = TRACKS[id]
	if not ResourceLoader.exists(path):
		push_warning("BGM 音频缺失：%s（游戏继续运行，只是没有背景音乐）" % path)
		return false
	# 刻意绕开资源缓存（CACHE_MODE_IGNORE）：这首曲子只属于这一个播放器，没必要在全局缓存里
	# 再挂一份引用。否则播放器销毁后流仍被缓存钉住，引擎收尾时会报
	# "N instances were leaked at exit" + "ERROR: N resources still in use at exit"，
	# 而 tools/run_checks.ps1 把 ERROR 行判为失败（headless 跑主场景时必现）。
	var stream: AudioStream = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if stream == null:
		return false
	# 循环播放：导入设置里已经勾了 loop，这里再兜一次底，防止 .import 被改回不循环
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	var p := AudioStreamPlayer.new()
	p.name = "Bgm_" + id
	p.stream = stream
	p.volume_db = -80.0
	p.bus = AudioBus.route(AudioBus.MUSIC)   # 音乐总线（缺 .tres 时自动退 Master）
	# 本工程用 _time_lock 冻结世界时间，不暂停 SceneTree；这里设 ALWAYS 只是保险
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	_host.add_child(p)
	_players[id] = p
	_gain[id] = 0.0
	_target[id] = 0.0
	return true

static func _base_db(id: String) -> float:
	if _cfg == null:
		return -8.0
	var db: float = 0.0            # bgm_db 已经在 Music 总线上，这里只留单曲偏移
	if id == "map":
		db += _cfg.bgm_map_db
	elif id == "battle":
		db += _cfg.bgm_battle_db
	return db

# ------------------------------------------------------------------ 调试

static func counts() -> Dictionary:
	return _counts.duplicate()

static func total_plays() -> int:
	var n := 0
	for k in _counts.keys():
		n += int(_counts[k])
	return n

static func reset_counts() -> void:
	_counts.clear()

static func pool_size() -> int:
	return _players.size()

## 某首曲子播放器上的音量（dB，只含单曲偏移 × 淡入增益；bgm_db 在 Music 总线上）
static func db_of(id: String) -> float:
	if not _players.has(id):
		return 0.0
	var p: AudioStreamPlayer = _players[id]
	if p == null or not is_instance_valid(p):
		return 0.0
	return p.volume_db

## 某首曲子的播放器所在总线（自检用）
static func bus_of(id: String) -> String:
	if not _players.has(id):
		return ""
	var p: AudioStreamPlayer = _players[id]
	if p == null or not is_instance_valid(p):
		return ""
	return p.bus

static func is_playing(id: String) -> bool:
	if not _players.has(id):
		return false
	var p: AudioStreamPlayer = _players[id]
	return p != null and is_instance_valid(p) and p.playing
