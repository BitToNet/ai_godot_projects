## =============================================================================
##  path_queue_check —— 寻路请求队列（PathQueue）的行为契约自检（**不参与游戏运行**）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/path_queue_check.gd
##
##  为什么需要它：队列是「把一次几十毫秒的 A* 摊到多帧」的机制。它一旦算错或算丢，
##  表现是「部队偶尔站着不动」——这种东西在 900 帧主场景里很难稳定复现。所以这里直接
##  对契约下断言，而不是靠观察：
##    1) 结果与同步 find_path **逐点相同**（排队只改时机，不改结果）；
##    2) 严格先进先出，每个请求恰好完成一次；
##    3) 预算为 0 时每帧仍恰好前进一个（饿死保护）；
##    4) 大预算一次排空；「每帧一个」与「一次排空」结果一致；
##    5) 请求方在等待期间被释放（失效 Callable）→ 只丢结果，不崩、不少记账；
##    6) clear() 清待办但不动累计计数。
##    7) 【第七轮 ① 新增】冻结帧不发请求 / 流动帧才发请求 / 同一支部队只有一个在途请求；
##    8) 【第七轮 ① 新增】重请求摊还：单个请求超 SPREAD_TRIGGER_US 后，后续帧空转还债，
##       空转帧数 = min(SPREAD_MAX_FRAMES, 耗时/预算)，且不丢结果、不换顺序。
##
##  用真实的 1024 m 世界（与 gen_fingerprint.gd 同一入口），端点取真实部队与定居点位置，
##  所以量到的是真实的可达性分布。退出码：0 = 全部通过；1 = 有断言失败
## =============================================================================
extends SceneTree

const SCENE := "res://scenes/Main.tscn"
const WAIT_LIMIT := 6000

## 只用于验证「摊还」的假寻路器：不查地图，单纯烧掉固定时间后返回空路径。
## 这样摊还契约的验证与地图尺寸 / 机器速度无关，是确定性的。
class _SlowFinder extends Pathfinder:
	var burn_us: int = 20000
	var calls: int = 0
	func find_path(_from_world: Vector2, _to_world: Vector2) -> PackedVector3Array:
		var t0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - t0 < burn_us:
			pass
		calls += 1
		return PackedVector3Array()

var _fails: Array[String] = []
var _total: int = 0
var main: Node = null
var _seen: Array[int] = []

func _initialize() -> void:
	_run()

func _ok(cond: bool, what: String) -> void:
	_total += 1
	if not cond:
		_fails.append(what)

func _run() -> void:
	var scene: PackedScene = load(SCENE)
	if scene == null:
		print("[寻路队列] FAIL：加载不了 %s" % SCENE)
		quit(2)
		return
	main = scene.instantiate()
	var ac := AudioConfig.new()
	ac.enabled = false
	main.audio = ac
	main.config = MapConfig.new()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	var guard := 0
	while guard < WAIT_LIMIT:
		guard += 1
		await process_frame
		if main.gen_done:
			break
	if not main.gen_done:
		print("[寻路队列] FAIL：等待地图生成超时（%d 帧）" % guard)
		quit(2)
		return

	var data: MapData = main.data
	var q: PathQueue = data.path_queue
	_ok(q != null, "WorldGenPipeline 已建好 path_queue（接线检查）")
	if q == null:
		_finish()
		return
	_ok(q.pending == 0, "生成结束后队列已排空（pending %d）" % q.pending)
	# 第七轮 ① 之前这里断言的是 `done_total >= 1`，而那个「1」恰恰来自「暂停时每帧重复入队」
	# 这个 bug 本身：开局世界是冻结的（TimeFlowController 初始 FROZEN），修好之后生成期
	# 一个请求都不该发。下面第 7 节把「冻结不发 / 流动才发」两个方向都钉死。
	_ok(q.done_total == 0, "开局冻结期间不发任何寻路请求（累计完成 %d）" % q.done_total)

	# 基础契约（结果 / FIFO / 饿死保护 / 记账）与「摊还」无关：先关掉摊还逐条验证，
	# 摊还本身在第 8 节单独验证（用假寻路器，确定性）。
	q.spread_enabled = false

	var pf: Pathfinder = data.path_coarse
	var pairs: Array = _pairs(24)
	_ok(pairs.size() == 24, "取到 24 对真实端点（部队 → 定居点）")
	if pairs.size() == 0:
		_finish()
		return

	# ---- 1) 与同步 find_path 逐点相同
	var want: Array = []
	for p in pairs:
		want.append(pf.find_path(p[0], p[1]))
	var got: Array = []
	for i in pairs.size():
		q.enqueue(pf, pairs[i][0], pairs[i][1], func(pts: PackedVector3Array) -> void:
			got.append(pts))
	_ok(q.pending == pairs.size(), "入队后 pending == 入队数（%d）" % pairs.size())
	var pumps := 0
	var drained := 0
	while q.pending > 0 and pumps < 5000:
		pumps += 1
		drained += q.pump(0)
	_ok(q.pending == 0, "预算 0 下也能排空")
	_ok(pumps == pairs.size(), "预算 0 时每次 pump 恰好完成一个（%d 次 / %d 个请求）" % [pumps, pairs.size()])
	_ok(drained == pairs.size(), "完成数守恒（%d/%d）" % [drained, pairs.size()])
	_ok(got.size() == pairs.size(), "回调次数 == 请求数（%d）" % got.size())
	var bad := -1
	for i in mini(got.size(), want.size()):
		if not _pts_eq(got[i], want[i]):
			bad = i
			break
	_ok(bad < 0, "排队结果与同步 find_path 逐点相同（%d 对，首个不同=第 %d 对）" % [pairs.size(), bad])

	# ---- 2) 严格先进先出
	_seen.clear()
	for i in 40:
		var pr: Array = pairs[i % pairs.size()]
		q.enqueue(pf, pr[0], pr[1], func(_pts: PackedVector3Array) -> void:
			_seen.append(_seen.size()))
	var n1 := q.pump(1 << 30)
	_ok(n1 == 40, "大预算一次排空 40 个（实测 %d）" % n1)
	_ok(_seen.size() == 40, "FIFO 批次回调 40 次（实测 %d）" % _seen.size())
	var ordered := _seen.size() == 40
	for i in _seen.size():
		if _seen[i] != i:
			ordered = false
			break
	_ok(ordered, "回调严格按入队顺序（先进先出）")

	# ---- 3) 失效 Callable（请求方被释放）只丢结果
	var before: int = q.done_total
	for i in 12:
		var pr2: Array = pairs[i % pairs.size()]
		q.enqueue(pf, pr2[0], pr2[1], Callable())
	_ok(q.pending == 12, "失效 Callable 也照常入队（pending %d）" % q.pending)
	q.pump(1 << 30)
	_ok(q.pending == 0 and q.done_total == before + 12, "失效 Callable 不崩且记账守恒（done_total %d）" % q.done_total)
	_ok(q.last_frame_done == 12, "上帧完成数正确（%d）" % q.last_frame_done)
	_ok(q.max_frame_us >= q.last_frame_us and q.max_frame_us > 0, "耗时统计自洽（单帧峰值 %d µs）" % q.max_frame_us)
	_ok(q.max_req_us > 0, "单请求耗时峰值被记录（%d µs）" % q.max_req_us)

	# ---- 4) 「每帧一个」与「一次排空」结果一致
	var a_res: Array = []
	var b_res: Array = []
	var ids: Array = []
	for i in 8:
		ids.append(pairs[(i * 3) % pairs.size()])
	for p in ids:
		q.enqueue(pf, p[0], p[1], func(pts: PackedVector3Array) -> void:
			a_res.append(pts))
	while q.pending > 0:
		q.pump(0)
	for p in ids:
		q.enqueue(pf, p[0], p[1], func(pts: PackedVector3Array) -> void:
			b_res.append(pts))
	q.pump(1 << 30)
	var same2 := a_res.size() == b_res.size() and a_res.size() == ids.size()
	if same2:
		for i in a_res.size():
			if not _pts_eq(a_res[i], b_res[i]):
				same2 = false
				break
	_ok(same2, "同一批请求「每帧一个」与「一次排空」结果一致（%d 个）" % a_res.size())

	# ---- 5) clear() 只清待办
	var done_before: int = q.done_total
	for i in 5:
		var pr4: Array = pairs[i % pairs.size()]
		q.enqueue(pf, pr4[0], pr4[1], Callable())
	q.clear()
	_ok(q.pending == 0, "clear() 清空待办")
	_ok(q.done_total == done_before, "clear() 不动累计完成数（仍为 %d）" % q.done_total)

	# ---- 6) 100 个积压的摊开形态（100 部队的规模感受）
	for i in 100:
		var pr5: Array = pairs[i % pairs.size()]
		q.enqueue(pf, pr5[0], pr5[1], Callable())
	var t0 := Time.get_ticks_usec()
	var frames := 0
	while q.pending > 0:
		q.pump(0)
		frames += 1
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_ok(frames == 100, "100 个积压需要 100 次 pump（每帧一个，实测 %d）" % frames)
	_ok(q.done_total > 0, "累计完成数为正（%d）" % q.done_total)

	# ---- 7) 第七轮 ①：冻结帧不发请求 / 流动帧才发 / 同一支部队同时只有一个在途请求 ----
	# 只碰一支领主/商队部队，副作用最小；不经过 Main._process，免得连带跑遭遇与战斗。
	var probe: AIParty = null
	for a in main.ai_parties:
		if a != null and is_instance_valid(a) and a.kind != AIParty.Kind.BANDIT:
			probe = a
			break
	_ok(probe != null, "世界里至少有一支领主 / 商队部队可供契约验证")
	if probe != null:
		var done0: int = q.done_total
		for i in 8:
			probe.step(0.0)
		_ok(q.done_total == done0 and q.pending == 0,
			"时间冻结时部队一帧也不提交请求（step(0) × 8：done %d → %d，pending %d）" % [done0, q.done_total, q.pending])
		_ok(not probe.path_pending, "冻结帧不会把 path_pending 卡住")
		probe._elapsed = 99.0     # 越过 start_delay，模拟「时间已经流动了一会儿」
		probe.step(1.0 / 60.0)
		_ok(q.pending == 1 and probe.path_pending,
			"时间流动后当帧提交一个请求（pending %d，path_pending %s）" % [q.pending, str(probe.path_pending)])
		for i in 3:
			probe.step(1.0 / 60.0)
		_ok(q.pending == 1, "同一支部队同时只有一个在途请求（pending 仍为 %d）" % q.pending)
		q.pump(1 << 30)
		_ok(not probe.path_pending and q.pending == 0,
			"回调结算后 path_pending 归零（pending %d）" % q.pending)

	# ---- 8) 第七轮 ①：重请求摊还（用假寻路器，确定性，与地图尺寸无关）----
	q.spread_enabled = true
	q.cooldown_skips = 0
	var sf := _SlowFinder.new(data.nav_coarse)
	sf.burn_us = 20000        # 20 ms ⇒ 冷却 = 20000 / 2000 = 10 帧
	var order: Array = []
	for i in 3:
		q.enqueue(sf, Vector2.ZERO, Vector2.ONE, func(_pts: PackedVector3Array) -> void:
			order.append(order.size()))
	# 期望形态：1 个请求 → 10 帧空转 → 1 个请求 → 10 帧空转 → 1 个请求（共 23 帧）
	var seq: Array = []
	for i in 23:
		seq.append(q.pump(PathQueue.DEFAULT_BUDGET_US))
	var want_seq: Array = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
	_ok(seq == want_seq, "重请求后空转还债：帧形态 %s（期望 %s）" % [str(seq), str(want_seq)])
	_ok(q.pending == 0 and sf.calls == 3, "摊还不丢请求、不重复（pending %d，实调 %d 次）" % [q.pending, sf.calls])
	_ok(order.size() == 3, "摊还不丢回调（%d 次）" % order.size())
	_ok(q.cooldown_skips == 20, "空转帧数 = min(12, 20 ms/2 ms) × 3 = 20（实测 %d）" % q.cooldown_skips)
	_ok(sf.burn_us < PathQueue.SPREAD_TRIGGER_US or q.cooldown_skips > 0,
		"≥8 ms 的请求确实触发了摊还")
	# 关掉摊还后同样 3 个请求应当连做（证明摊还是可关的纯调度，不影响结果）
	q.spread_enabled = false
	q.clear()                 # clear() 会连冷却一起清掉（否则这里的第一个请求会白等 10 帧）
	q.cooldown_skips = 0
	sf.burn_us = 20000
	for i in 3:
		q.enqueue(sf, Vector2.ZERO, Vector2.ONE, Callable())
	var fast := 0
	while q.pending > 0 and fast < 10:
		q.pump(PathQueue.DEFAULT_BUDGET_US)
		fast += 1
	_ok(fast == 3 and q.cooldown_skips == 0, "关掉摊还后 3 个请求 3 帧做完且不空转（%d 帧）" % fast)
	print("[寻路队列] 100 个 coarse 请求共 %.1f ms（单次均值 %.2f ms；预算 2000 µs/帧 ⇒ 至少 %d 帧）" % [
		ms, ms / 100.0, int(ms / 2.0) + 1])
	print("[寻路队列] %s" % q.stats())
	print("[寻路队列] 世界：种子 %d / %d 米 / 定居点 %d / 部队 %d" % [
		main.config.map_seed, int(main.config.map_size), data.settlements.size(), main.ai_parties.size()])
	_finish()

func _pts_eq(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true

## 真实端点：起点取玩家与 AI 部队当前位置，终点取定居点。全部是世界里真实存在的点。
func _pairs(n: int) -> Array:
	var out: Array = []
	var starts: Array = []
	if main.player != null:
		starts.append(Vector2(main.player.position.x, main.player.position.z))
	for a in main.ai_parties:
		if a != null and is_instance_valid(a):
			starts.append(Vector2(a.position.x, a.position.z))
	var dests: Array = []
	for s in main.data.settlements:
		dests.append(s.pos)
	if starts.is_empty() or dests.is_empty():
		return out
	for i in n:
		out.append([starts[i % starts.size()], dests[(i * 5 + 1) % dests.size()]])
	return out

func _finish() -> void:
	print("")
	if _fails.is_empty():
		print("PASS：寻路队列契约全部成立（%d 项断言）" % _total)
		quit(0)
	else:
		print("FAIL：%d/%d 项断言未通过 —— %s" % [_fails.size(), _total, "; ".join(_fails)])
		quit(1)