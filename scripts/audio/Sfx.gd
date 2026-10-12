## =============================================================================
##  Sfx —— 全局音效播放器（静态工具类，任何脚本直接 Sfx.play(...)）
##
##  职责：
##   · setup() 时向宿主节点挂一个 AudioStreamPlayer 池，并逐个合成全部音色
##     （合成交给 SfxSynth，每 5 个音色让出一帧，Loading 界面不会卡住）
##   · play()        —— 非定位音（UI / 号角 / 结算 / 全局提示）
##   · play_2d()     —— 按 2D 世界坐标播放（Boss 战里用，自带左右声像与距离衰减）
##   · play_3d()     —— 按 3D 世界坐标播放（大地图行军马蹄用）
##   · 分类音量 / 总音量 / 静音 / 音高随机抖动都取自 AudioConfig
##
##  设计约束：不加载任何外部音频文件，全部音色由代码合成（见 SfxSynth.gd）。
## =============================================================================
class_name Sfx
extends RefCounted

static var _host: Node = null
static var _cfg: AudioConfig = null
static var _bank: Dictionary = {}
static var _players: Array[AudioStreamPlayer] = []
static var _next: int = 0
static var _muted: bool = false
static var _ready: bool = false
static var _last_ms: Dictionary = {}      ## id -> 上次播放时刻（用于同音最短间隔）
static var _counts: Dictionary = {}       ## id -> 累计播放次数（调试用：F3 面板 / tools/sfx_battle_check.gd）
static var _rng := RandomNumberGenerator.new()

# =============================================================== 初始化
## 参数配置（未初始化时返回一份默认配置，调用方可以安全地直接读字段）
static func cfg() -> AudioConfig:
	if _cfg == null:
		_cfg = AudioConfig.create()
	return _cfg

static func is_ready() -> bool:
	return _ready and not _bank.is_empty()

## 建立音效池并合成全部音色（建议在 Main._ready() 里 await 一次）
static func setup(host: Node, c: AudioConfig = null) -> void:
	if host == null:
		return
	_host = host
	if c != null:
		_cfg = c
	_rng.seed = 0x5F3A17
	if not cfg().enabled:
		_ready = true
		return
	if not _bank.is_empty():
		_ready = true
		return
	# 播放池
	for i in maxi(4, cfg().polyphony):
		var p := AudioStreamPlayer.new()
		p.name = "SfxVoice%02d" % i
		p.bus = "Master"
		host.add_child(p)
		_players.append(p)
	# 逐个合成音色；按时间切片让出帧，Loading 界面不会卡住
	# （全部 28 个音色共约 16 秒音频，实测合成 ≈ 1.3 秒，切成若干片后每片 < 100ms）
	var ids := SfxSynth.ids()
	var tree := Engine.get_main_loop() as SceneTree
	var slice_t := Time.get_ticks_msec()
	for id in ids:
		var m := SfxSynth.meta(String(id))
		_bank[String(id)] = {
			"stream": SfxSynth.build(String(id), _rng),
			"cat": String(m[0]),
			"db": float(m[1]),
			"gap": float(m[2]),
			"pitch": float(m[3]),
		}
		if tree != null and Time.get_ticks_msec() - slice_t > 60:
			slice_t = Time.get_ticks_msec()
			await tree.process_frame
	_ready = true

# =============================================================== 开关 / 音量
static func is_muted() -> bool:
	return _muted

static func set_muted(v: bool) -> void:
	_muted = v
	if _muted:
		for p in _players:
			p.stop()

static func toggle_mute() -> bool:
	set_muted(not _muted)
	return _muted

static func set_master_db(db: float) -> void:
	cfg().master_db = db

# =============================================================== 调试统计
## 各音效累计播放次数（id -> 次数）
static func counts() -> Dictionary:
	return _counts

static func total_plays() -> int:
	var s := 0
	for k in _counts:
		s += int(_counts[k])
	return s

static func pool_size() -> int:
	return _players.size()

static func reset_counts() -> void:
	_counts.clear()

# =============================================================== 播放
## 非定位播放（UI / 号角 / 结算 / 全局提示）
static func play(id: String, vol_db := 0.0, pitch := 1.0) -> void:
	if _muted or _players.is_empty():
		return
	var e := _entry(id)
	if e.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = e["stream"]
	p.pitch_scale = _pitch_of(e, pitch)
	p.volume_db = _final_db(e, vol_db)
	p.play()

## 按 2D 世界坐标播放（战斗场景：自带左右声像 + 距离衰减）
static func play_2d(parent: Node, id: String, pos: Vector2, vol_db := 0.0, pitch := 1.0) -> void:
	var e := _entry(id)
	if e.is_empty():
		return
	if parent == null or not is_instance_valid(parent) or not (parent is Node2D):
		play(id, vol_db, pitch)
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = e["stream"]
	p.pitch_scale = _pitch_of(e, pitch)
	p.volume_db = _final_db(e, vol_db)
	# 2D 定位音：镜头（Camera2D）就是听者，自带左右声像与距离衰减
	p.attenuation = 1.0
	p.max_distance = 1600.0
	parent.add_child(p)
	p.global_position = pos
	_autofree(parent, p)

## 按 3D 世界坐标播放（大地图行军马蹄等）
static func play_3d(parent: Node, id: String, pos: Vector3, vol_db := 0.0, pitch := 1.0) -> void:
	var e := _entry(id)
	if e.is_empty():
		return
	if parent == null or not is_instance_valid(parent) or not (parent is Node3D):
		play(id, vol_db, pitch)
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = e["stream"]
	p.pitch_scale = _pitch_of(e, pitch)
	p.volume_db = _final_db(e, vol_db)
	# 3D 定位音：以 Camera3D 为听者（大地图拉远时马蹄声自然变轻）
	p.unit_size = 90.0
	p.max_distance = 700.0
	parent.add_child(p)
	p.global_position = pos
	_autofree(parent, p)

static func stop_all() -> void:
	for p in _players:
		p.stop()

# =============================================================== 内部
## 取音色条目：未初始化或已静音时返回空字典；同时做"同音最短间隔"节流
static func _entry(id: String) -> Dictionary:
	if _muted or not _ready:
		return {}
	if not _bank.has(id):
		return {}
	var e: Dictionary = _bank[id]
	var gap := float(e["gap"])
	var now := Time.get_ticks_msec()
	if gap > 0.0 and now - int(_last_ms.get(id, -999999)) < int(gap * 1000.0):
		return {}
	_last_ms[id] = now
	_counts[id] = int(_counts.get(id, 0)) + 1
	return e

static func _final_db(e: Dictionary, extra: float) -> float:
	return cfg().master_db + cfg().category_db(String(e["cat"])) + float(e["db"]) + extra

static func _pitch_of(e: Dictionary, pitch: float) -> float:
	var j := cfg().pitch_jitter
	var p: float = float(e["pitch"]) * pitch
	if j > 0.0:
		p *= 1.0 + _rng.randf_range(-j, j)
	return clampf(p, 0.25, 4.0)

## 播放一次就回收的临时播放器：
## 正常靠 finished 回收；再挂一个兜底计时器（某些音频驱动不会发 finished）
static func _autofree(parent: Node, p: Node) -> void:
	p.connect("finished", p.queue_free)
	p.play()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var dur := 1.0
	var st: AudioStream = p.get("stream")
	if st != null:
		dur = st.get_length()
	var ps: float = p.get("pitch_scale")
	# 兜底回收：不把节点本身放进闭包（节点可能已被 finished 提前释放），
	# 只带 instance_id，回调时再判断对象是否还在
	tree.create_timer(dur / maxf(0.25, ps) + 0.5).timeout.connect(_free_by_id.bind(p.get_instance_id()))

static func _free_by_id(id: int) -> void:
	if not is_instance_id_valid(id):
		return
	var o := instance_from_id(id)
	if o is Node:
		(o as Node).queue_free()
