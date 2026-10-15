## =============================================================================
##  PathQueue —— 全局寻路请求队列 + 每帧预算（第六轮 6d 后半）
##
##  为什么要它：A* 是**同步**调用。一次 find_path 在 1024 m 图上约 13 ms（fine）/ 45.8 ms（coarse），
##  而 4096 m + 100 部队时单次会到 200~730 ms（见 ROADMAP §12.5 拦路虎 #1）——
##  直接写在 _process 里就是掉帧，且帧时间被单个请求的长度决定。
##
##  做法：AI 的寻路请求先入这条 FIFO 队列，每帧只花掉预算内的微秒数；
##  **但每帧至少完成一个请求**，否则当预算比单个请求还小时队列永远不会前进（饿死）。
##  完成时在**同一帧内同步**回调，回调里才 set_path。
##
##  契约（tools/path_queue_check.gd 逐条验证）：
##    · 结果与同步 find_path **逐点相同** —— 排队只改「什么时候算」，不改「算出什么」；
##    · 严格先进先出，每个请求恰好完成一次；
##    · 单帧耗时 ≤ 预算，例外只有「这一帧只做了一个、而它本身就超预算」（进展保证优先）。
##
##  ---- 第七轮 ① 新增：重请求摊还（spread）----
##  旧的「每帧至少完成一个」只保证队列会前进，不保证**帧时间**：在 4096 m / 100 部队下
##  单次粗栅格 A* 实测能到 1.5 s（临时探针 tools/frame_bisect_tmp.gd），于是只要队列非空，
##  每一帧都被这一整次搜索吃掉（实测 idle avg 184.9 ms / p95 1070 ms）。
##  现在的规则：单个请求耗时 ≥ SPREAD_TRIGGER_US 时，接下来 min(SPREAD_MAX_FRAMES, 耗时/预算)
##  帧**不再开始新请求**，把这笔开销摊到后续帧里还掉；代价是队列推进变慢（最多慢 0.2 s），
##  换来的是「不再连续两帧都掉到 1 秒级」。冷却是纯调度，不改任何结果与顺序。
##  spread_enabled 可关（队列自检关掉它逐条验证基础契约；生产路径恒为开）。
##
##  确定性：队列本身不抽任何随机数；RNG 抽取在各部队的调用点（寻路之前）完成，
##  所以排队不改变任何一条抽签序列，只把「拿到路径」推迟到下一帧。
## =============================================================================
class_name PathQueue
extends RefCounted

const DEFAULT_BUDGET_US := 2000   ## 每帧预算（微秒）——16.6 ms 的一帧里占约 12%
## 单个请求超过这个耗时（≈半帧）就认定它是「重请求」，开始摊还
const SPREAD_TRIGGER_US := 8000
## 摊还的帧数上限（12 帧 ≈ 0.2 s）：再多就是「队列看着停住了」，不是摊还
const SPREAD_MAX_FRAMES := 12

var pending: int = 0              ## 尚未完成的请求数
var done_total: int = 0           ## 累计完成数
var last_frame_us: int = 0        ## 上一帧实际花掉的微秒数
var last_frame_done: int = 0      ## 上一帧完成的请求数
var max_frame_us: int = 0         ## 历史单帧最大耗时（注意：大预算下可能是「一批」的耗时）
var max_req_us: int = 0           ## 历史单个请求最大耗时 —— 这才是「预算至少要多大」的依据
## 是否启用重请求摊还（见文件头）。自检把它关掉以验证基础契约，生产路径不要关。
var spread_enabled: bool = true
var cooldown_skips: int = 0       ## 累计因摊还而主动空过的帧数（诊断 + 断言用）

var _q: Array = []                ## [{finder, from, to, cb}]
var _head: int = 0                ## 队头下标（不用 pop_front，避免 O(n) 搬移）
var _enq_total: int = 0           ## 累计入队数（只增，供诊断）
var _cooldown: int = 0            ## 剩余冷却帧数（>0 时本帧不开始新请求）

## 入队一个请求。cb 收到 PackedVector3Array，在完成的同一帧内被同步调用。
func enqueue(finder: Pathfinder, from_world: Vector2, to_world: Vector2, cb: Callable) -> void:
	_q.append({"finder": finder, "from": from_world, "to": to_world, "cb": cb})
	pending += 1
	_enq_total += 1

## 每帧调用：最多花 budget_us 微秒，且至少完成一个请求。返回本帧完成数。
func pump(budget_us: int = DEFAULT_BUDGET_US) -> int:
	# 摊还中的空转帧：不开始新请求，但**不改任何状态**（队列、记账、结果都不动）
	if _cooldown > 0:
		_cooldown -= 1
		cooldown_skips += 1
		last_frame_done = 0
		last_frame_us = 0
		return 0
	var t0 := Time.get_ticks_usec()
	var made := 0
	while _head < _q.size():
		var req: Dictionary = _q[_head]
		_head += 1
		var t_req := Time.get_ticks_usec()
		var pts: PackedVector3Array = req["finder"].find_path(req["from"], req["to"])
		var req_us := Time.get_ticks_usec() - t_req
		var cb: Callable = req["cb"]
		# 请求方可能在等待期间被释放（部队销毁 / 场景切换）：Callable 失效就只丢结果
		if cb.is_valid():
			cb.call(pts)
		max_req_us = maxi(max_req_us, req_us)
		made += 1
		pending -= 1
		# 重请求摊还：这笔开销按预算折算成冷却帧，接下来的帧先空转还债
		if spread_enabled and req_us >= SPREAD_TRIGGER_US:
			_cooldown = maxi(_cooldown, mini(SPREAD_MAX_FRAMES, req_us / maxi(1, budget_us)))
		# 先完成再判预算 ⇒ 预算为 0 时也能每帧前进一个（饿死保护）
		if Time.get_ticks_usec() - t0 >= budget_us:
			break
	# 已消费的前缀占了一半以上就压掉，避免长跑时数组无限增长
	if _head > 64 and _head * 2 > _q.size():
		_q = _q.slice(_head)
		_head = 0
	last_frame_done = made
	last_frame_us = Time.get_ticks_usec() - t0
	max_frame_us = maxi(max_frame_us, last_frame_us)
	done_total += made
	return made

func clear() -> void:
	_q.clear()
	_head = 0
	pending = 0
	# 摊还冷却也一起清掉：队列已经空了，冷却没有任何需要摊的开销，
	# 留着它只会让「清空后立刻入队」的第一个请求白等最多 12 帧。
	_cooldown = 0

## 诊断文本（HUD / 探针用）
func stats() -> String:
	return "队列 %d 待完成 / 累计 %d 完成 / 上帧 %d 个 %d µs / 单帧峰值 %d µs / 单请求峰值 %d µs / 摊还空转 %d 帧" % [
		pending, done_total, last_frame_done, last_frame_us, max_frame_us, max_req_us, cooldown_skips]