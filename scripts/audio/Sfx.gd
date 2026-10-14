## =============================================================================
##  Sfx —— 全局音效播放器（静态工具类，任何脚本直接 Sfx.play(...)）
##
##  职责：
##   · setup() 时向宿主节点挂一个 AudioStreamPlayer 池，并逐个合成全部音色
##     （合成交给 SfxSynth，每 5 个音色让出一帧，Loading 界面不会卡住）
##   · play()        —— 非定位音（UI / 号角 / 结算 / 全局提示）
##   · play_2d()     —— 按 2D 世界坐标播放（Boss 战里用，自带左右声像与距离衰减）
##   · play_3d()     —— 按 3D 世界坐标播放（大地图行军马蹄用）
##   · 分类音量 / 音高随机抖动取自 AudioConfig；总音量写在 Master 总线上（见 AudioBus）
##   · 播放器挂在 Sfx 总线上（default_bus_layout.tres：Master → Music / Sfx）；
##     号角 / 开战 / 结算这类"扇子音"会临时压低音乐（AudioBus.duck），别让 BGM 压住它
##   · 移动类音色（脚步 / 马蹄 / 起跳落地 / 闪避）优先用录音素材（SfxFoley），
##     有素材时每次播放随机挑一个 take，没有就回退到合成音色
##
##  设计约束：打击 / 金属 / 破风类音色全部由代码合成（见 SfxSynth.gd）；只有"移动"
##  这一类改用 CC0 录音素材（见 SfxFoley.gd 与 audio/sfx/foley/CREDITS.md）。
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

## 播放期音高抖动用**独立**的 RNG，不与合成用的 _rng 共用：
## 合成消耗多少个随机数是"实现细节"（命中 PCM 缓存时一次都不消耗），共用的话
## 冷启动与命中缓存两条路径会得到不同的抖动序列 —— 同一份代码两种开局，听感不该有差别。
## 固定种子，让抖动序列只取决于播放次数，与"这次是冷启动还是缓存"无关。
const _JIT_SEED := 0x5F3A17 + 7
static var _jit := RandomNumberGenerator.new()

## 录音变体（SfxFoley）挑选用**另一个**独立 RNG，理由同上：音高抖动序列是玩家能听出来的
## 东西，不该因为"这一声多挑了一个变体"就整体移位。同样固定种子，只取决于播放次数。
const _VAR_SEED := 0x5F3A17 + 23
static var _var := RandomNumberGenerator.new()

## 扇子音名单：播放时把音乐临时压低。刻意不塞进 SfxSynth.SPECS ——
## 那是"音色配方"，而这是"混音行为"，两件事放在一起以后必然互相牵制。
## "order" 曾经在这个名单里：大地图点击不再出声后（见 TimeFlowController.order_move），
## 它已经不是扇子音，留在名单里只会让人以为还有地方在播它。
const FANFARE := ["battle_start", "result_win", "result_lose"]

# =============================================================== 初始化
## 参数配置（未初始化时返回一份默认配置，调用方可以安全地直接读字段）
static func cfg() -> AudioConfig:
	if _cfg == null:
		_cfg = AudioConfig.create()
	return _cfg

## 是否已完成初始化。注意：关音频时（AudioConfig.enabled = false）**也算就绪** ——
## 此时只是没有音色库、播放直接丢弃；旧实现要求 _bank 非空，于是
## tools/sfx_*_check.gd 的等待循环会永久超时（而 README 恰恰推荐关音频省启动）。
static func is_ready() -> bool:
	return _ready and (not cfg().enabled or not _bank.is_empty())

## 建立音效池并合成全部音色（建议在 Main._ready() 里 await 一次）
static func setup(host: Node, c: AudioConfig = null) -> void:
	if host == null:
		return
	_host = host
	if c != null:
		_cfg = c
	_rng.seed = 0x5F3A17
	AudioBus.apply(cfg())        # 总音量 / 音乐音量先落到总线上（幂等）
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
		p.bus = AudioBus.route(AudioBus.SFX)   # 音效总线（缺 .tres 时自动退 Master）
		host.add_child(p)
		_players.append(p)
	var ids := SfxSynth.ids()
	# 1) 先试 PCM 缓存（user://sfx_cache）：命中就省掉 ~1.1 秒合成，见 ROADMAP §11.4。
	#    缓存是**整体命中 / 整体丢弃**的：噪声音色共用一条 RNG 流，不能只补一两个，
	#    否则后面所有音色的噪声都会变样（音色悄悄变了，比慢 1 秒糟糕得多）。
	var cached := SfxCache.load_bank()
	if not cached.is_empty():
		for id in ids:
			var sid := String(id)
			var cm := SfxSynth.meta(sid)
			_bank[sid] = {
				"stream": cached[sid],
				"cat": String(cm[0]),
				"db": float(cm[1]),
				"gap": float(cm[2]),
				"pitch": float(cm[3]),
			}
		_jit.seed = _JIT_SEED
		_attach_foley()
		_ready = true
		return
	# 2) 冷启动：逐个合成音色；按时间切片让出帧，Loading 界面不会卡住
	# （全部 28 个音色共约 16 秒音频，合成 ≈ 1.1 秒，切成若干片后每片 < 100ms）
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
	# 3) 落盘（写不进去只影响下次启动的快慢，不影响本次运行）
	SfxCache.save_bank(_bank)
	_jit.seed = _JIT_SEED
	_attach_foley()
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
	AudioBus.apply()          # 立刻生效：总音量已经不在逐声的 volume_db 里了

# =============================================================== 调试统计
## 各音效累计播放次数（id -> 次数）
static func counts() -> Dictionary:
	return _counts

static func total_plays() -> int:
	var s := 0
	for k in _counts:
		s += int(_counts[k])
	return s

## 音色库条目数（自检用；关音频时为 0）
static func bank_size() -> int:
	return _bank.size()

# =============================================================== 录音素材层（自检用）
static func foley_ready() -> bool:
	return SfxFoley.is_ready()

## 某个动作挂上了几个录音变体（0 = 该动作仍用合成音色）
static func foley_variants(id: String) -> int:
	return SfxFoley.variant_count(id)

static func foley_total() -> int:
	return SfxFoley.total_variants()

static func foley_missing() -> Array[String]:
	return SfxFoley.missing()

## 某个音色当前是否走录音素材
static func uses_foley(id: String) -> bool:
	return not SfxFoley.variants_of(id).is_empty()

## 音色**条目上真正挂到**的录音变体数（0 = 建库时没挂上，播放会退回合成音色）。
## 与 foley_variants() 的分工：那个问"素材层有什么"，这个问"音色库挂上了什么"——
## 只有后者能抓住"素材齐全但 _attach_foley 没跑"这类断链（不写状态，不走节流）。
static func entry_foley_count(id: String) -> int:
	if not _bank.has(id):
		return 0
	return (_bank[id].get("variants", []) as Array).size()

static func pool_size() -> int:
	return _players.size()

static func reset_counts() -> void:
	_counts.clear()

# =============================================================== 播放
## 非定位播放（UI / 号角 / 结算 / 全局提示）
static func play(id: String, vol_db := 0.0, pitch := 1.0) -> void:
	var e := _peek(id)
	if e.is_empty():
		return
	_commit(id)
	_duck_for_fanfare(id)
	_play_plain(e, vol_db, pitch)

## 按 2D 世界坐标播放（战斗场景：自带左右声像 + 距离衰减）
static func play_2d(parent: Node, id: String, pos: Vector2, vol_db := 0.0, pitch := 1.0) -> void:
	var e := _peek(id)
	if e.is_empty():
		return
	_commit(id)
	if parent == null or not is_instance_valid(parent) or not (parent is Node2D):
		# 退化成非定位播放：直接用已取到的 e，不能再走 play()（那会二次节流 → 100% 丢音）
		_play_plain(e, vol_db, pitch)
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = _stream_of(e)
	p.pitch_scale = _pitch_of(e, pitch)
	p.volume_db = _final_db(e, vol_db)
	# 2D 定位音：镜头（Camera2D）就是听者，自带左右声像与距离衰减
	p.bus = AudioBus.route(AudioBus.SFX)
	p.attenuation = 1.0
	p.max_distance = 1600.0
	parent.add_child(p)
	p.global_position = pos
	_autofree(parent, p)

## 按 3D 世界坐标播放（大地图行军马蹄等）
static func play_3d(parent: Node, id: String, pos: Vector3, vol_db := 0.0, pitch := 1.0) -> void:
	var e := _peek(id)
	if e.is_empty():
		return
	_commit(id)
	if parent == null or not is_instance_valid(parent) or not (parent is Node3D):
		# 退化成非定位播放：同上，避免二次节流吞掉这一声
		_play_plain(e, vol_db, pitch)
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _stream_of(e)
	p.pitch_scale = _pitch_of(e, pitch)
	p.volume_db = _final_db(e, vol_db)
	# 3D 定位音：以 Camera3D 为听者（大地图拉远时马蹄声自然变轻）
	p.bus = AudioBus.route(AudioBus.SFX)
	p.unit_size = 90.0
	p.max_distance = 700.0
	parent.add_child(p)
	p.global_position = pos
	_autofree(parent, p)

static func stop_all() -> void:
	for p in _players:
		p.stop()

# =============================================================== 内部
## 挂载录音素材（SfxFoley）：给对应音色条目加上 "variants" —— 播放时随机取一个 take。
## 没有素材 / 素材缺失的 id 保持纯合成音色；一个素材都没加载到时这一层等于不存在。
static func _attach_foley() -> void:
	SfxFoley.load_all()
	_var.seed = _VAR_SEED
	for id in SfxFoley.loaded_ids():
		var sid := String(id)
		if not _bank.has(sid):
			continue
		var vs := SfxFoley.variants_of(sid)
		if vs.is_empty():
			continue
		(_bank[sid] as Dictionary)["variants"] = vs

## 取这一声要播的流：有录音变体就随机挑一个（同一动作多个 take），否则用合成音色。
static func _stream_of(e: Dictionary) -> AudioStream:
	var v: Variant = e.get("variants")
	if v is Array:
		var arr := v as Array
		if not arr.is_empty():
			return arr[_var.randi() % arr.size()] as AudioStream
	return e["stream"] as AudioStream

## 取音色条目并做"同音最短间隔"节流判定，**不写任何状态**。
## 调用方在确认这一声一定会发出去（含下面的退化路径）之后再调 _commit()。
## 拆成 _peek / _commit 的原因：play_2d / play_3d 在 parent 非法时会退化成非定位播放，
## 旧实现里退化路径会再走一遍节流 —— 同一毫秒必然被拦下，等于 100% 丢音。
static func _peek(id: String) -> Dictionary:
	if _muted or not _ready:
		return {}
	if not _bank.has(id):
		return {}
	var e: Dictionary = _bank[id]
	var gap := float(e["gap"])
	if gap > 0.0 and Time.get_ticks_msec() - int(_last_ms.get(id, -999999)) < int(gap * 1000.0):
		return {}
	return e

## 记账：写入播放时刻（供节流）并累加调试计数
static func _commit(id: String) -> void:
	_last_ms[id] = Time.get_ticks_msec()
	_counts[id] = int(_counts.get(id, 0)) + 1

## 用共享播放池放一条非定位音（不做节流 / 不计数）
static func _play_plain(e: Dictionary, vol_db: float, pitch: float) -> void:
	if _muted or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _stream_of(e)
	p.pitch_scale = _pitch_of(e, pitch)
	p.volume_db = _final_db(e, vol_db)
	p.play()

## 单个音色的最终音量（dB）。**不含** master_db —— 那一档在 Master 总线上（自检用）。
static func volume_db_of(id: String, extra := 0.0) -> float:
	if not _bank.has(id):
		return 0.0
	return _final_db(_bank[id], extra)

## 第 i 个池播放器所在的总线（自检用）
static func player_bus(i: int) -> String:
	if i < 0 or i >= _players.size():
		return ""
	return _players[i].bus

## 扇子音播放时压低音乐（名单见 FANFARE，深度 / 时长见 AudioConfig.fanfare_duck_*）
static func _duck_for_fanfare(id: String) -> void:
	if not FANFARE.has(id):
		return
	AudioBus.duck(cfg().fanfare_duck_db, cfg().fanfare_duck_time)

static func _final_db(e: Dictionary, extra: float) -> float:
	return cfg().category_db(String(e["cat"])) + float(e["db"]) + extra

static func _pitch_of(e: Dictionary, pitch: float) -> float:
	var j := cfg().pitch_jitter
	var p: float = float(e["pitch"]) * pitch
	if j > 0.0:
		p *= 1.0 + _jit.randf_range(-j, j)
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
