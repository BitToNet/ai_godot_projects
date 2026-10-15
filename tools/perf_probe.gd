## =============================================================================
##  perf_probe —— 性能基准采样（**不参与游戏运行**，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/perf_probe.gd
##    # 记录 / 更新基线：
##    ...--script res://tools/perf_probe.gd -- --write-baseline
##    # 超阈值时直接判失败（默认只警告）：
##    ...--script res://tools/perf_probe.gd -- --strict
##
##  采样两个场景各 300 帧（--fixed-fps 60 下 = 5 秒模拟时间）：
##    idle  —— 开局状态（世界时间冻结，只有相机 / UI / 地形流式加载在跑）
##    march —— 下达一次行军令后（世界时间流动，AI 部队同时 step，寻路 / 音效全开）
##
##  ---- 第七轮 ① 新增的三条**硬断言**（无论有没有 --strict 都会判失败）----
##  这三条钉的是「大地图上特别卡顿」那件事的机制，不是数值：
##    A. **冻结期不许有寻路请求**：idle 场景 path_queue.done_total 增量必须为 0。
##       旧实现在暂停时每帧重复入队 ⇒ 队列永不空 ⇒ 「每帧至少完成一个」退化成每帧一次满额
##       A*（4096 m 实测 idle p95 1070 ms / max 1495 ms）。这条断言直接钉住那个 bug。
##    B. **不许有 100 ms 以上的尖刺帧**（容忍 1 帧，机器抖动）：60 fps 的一帧是 16.6 ms，
##       100 ms = 掉 6 帧，玩家一定看得见。旧实现 60 帧里 ~30 帧超过它。
##    C. **队列不许积压**：march 场景 pending 必须能回到 0（累计待办峰值 ≤ 部队数）。
##  用法补充：`-- --size=2048` 覆盖地图尺寸（默认用 MapConfig 的出货默认值；门禁会显式清掉
##  WARBAND_MAP_SIZE 再跑本探针，所以这里量到的永远是**出货尺寸**）。
##
##  ---- 指标口径（2026-10-12 实测后修订，别退回旧写法）----
##  · frame_ms = 本帧**墙钟**耗时（Time.get_ticks_usec 差值），是真正可回归的那个数。
##    它必须在 --fixed-fps 60 下测：该开关关闭实时同步，引擎不再自行节流。
##    同一空场景实测：带开关 0.004 ms/帧，不带开关 6.900 ms/帧（引擎把帧率压在 ≈145）
##    —— 所以只有带开关时，「墙钟耗时 ≈ 真实 CPU 开销」这句话才成立。
##  · 旧版本采集的 Performance.TIME_PROCESS / TIME_FPS 已**全部移除**，因为实测证明
##    它们在本配置下是陈旧常数、与真实负载无关：
##      fixed-fps 下连续 12 次读取完全相同；idle 报 1150 ms/帧，而墙钟只有 0.84 ms/帧
##      （那个 1150 是生成阶段某一次慢帧的残值）。Engine.get_frames_per_second() 同样卡死。
##    用它们做基线 = 把常数写进仓库，还会掩盖真实回归。
##  · draw_calls 在 headless 恒为 0，只有开窗运行才有意义；保留字段仅为对照，**不设阈值**。
##
##  退出码：0 = 正常（或仅警告）；1 = --strict 且超阈值，或基准本身无效；2 = 超时 / 写基线失败
## =============================================================================
extends SceneTree

const SCENE := "res://scenes/Main.tscn"
const BASELINE := "res://tools/perf_baseline.json"
const WAIT_LIMIT := 6000
const SETTLE_FRAMES := 40        ## 生成完成后再等几帧（让 Loading 遮罩收掉、地形首块建好）
const SAMPLE_FRAMES := 300
const TOL_FRAME := 1.5           ## frame_ms.avg 允许放大到基线的 1.5 倍
const TOL_FRAME_P95 := 1.8       ## frame_ms.p95 允许放大到基线的 1.8 倍
const METRICS := ["frame_ms", "draw_calls", "nodes", "objects", "static_mb"]
## 第七轮 ① 硬门槛：单帧墙钟超过它 = 可见卡顿（60 fps 的一帧 16.6 ms）
const STALL_MS := 100.0
const STALL_TOLERANCE := 1       ## 容忍 1 帧（机器抖动 / 系统调度）
const MAX_REISSUES := 10         ## 行军场景里「玩家停下就再下一单」的次数上限
## 行军场景至少要有这么多比例的帧真的在行军，否则这个场景测的不是行军
const MARCH_MIN_RATIO := 0.5

var main: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	var user_args := OS.get_cmdline_user_args()
	var write_baseline := user_args.has("--write-baseline")
	var strict := user_args.has("--strict")
	var size_arg := _arg_value(user_args, "--size=")

	var scene: PackedScene = load(SCENE)
	main = scene.instantiate()
	var ac := AudioConfig.new()
	ac.enabled = false           # 本探针不测音频合成；如需测，把它改回 true
	main.audio = ac
	main.config = MapConfig.new()
	if size_arg > 0.0:
		main.config.map_size = size_arg
		main.config.heightmap_res = main.config.scaled_heightmap_res()
	root.add_child(main)

	var guard := 0
	while guard < WAIT_LIMIT:
		guard += 1
		await process_frame
		# 等 gen_done 而不是 _gen_ms：后者置位时收尾协程仍在 await，
		# 那时 free() 会报「Resumed function '_step()' after await, but class instance is gone」
		if main.gen_done:
			break
	if not main.gen_done:
		print("[性能] FAIL：等待地图生成超时（%d 帧）" % guard)
		quit(2)
		return
	for i in SETTLE_FRAMES:
		await process_frame

	print("[性能] 环境：种子 %d / 尺寸 %.0f m / 生成 %d ms / 植被 %d 实例 / AI 部队 %d 支 / 采样 %d 帧 × 2 场景" % [
		main.config.map_seed, main.config.map_size, int(main._gen_ms), main.vegetation.total(),
		main.ai_parties.size(), SAMPLE_FRAMES])
	print("[性能] 口径：frame_ms = 墙钟耗时（--fixed-fps 60 关闭实时同步）；不使用 Performance.TIME_PROCESS")

	# ---- 场景 1：idle（世界时间冻结）----
	var idle := await _sample("idle", false)

	# ---- 场景 2：march（下达行军令，世界时间流动）----
	# 遭遇会 time.lock() 把世界锁进战斗，那样后半段采样的就不是「行军中的大地图」了；
	# 本探针只测大地图帧时间，所以行军场景里关掉遭遇（第七轮 ①；EncounterSystem.enabled 本就是
	# 给调试 / 截图用的开关）。_sample 里还会在玩家停下时继续下单，保证整段都在行军。
	main.encounters.enabled = false
	var p := Vector2(main.player.position.x, main.player.position.z)
	var goal := Vector2(p.x + 160.0, p.y + 120.0)
	main.time.order_move(goal)
	var march := await _sample("march", true)
	main.encounters.enabled = true

	var now := {"idle": idle, "march": march}
	_report(now)

	# ---- 第七轮 ① 三条硬断言（与 --strict 无关，永远判失败）----
	var fails: Array = []
	# A. 冻结期不许有寻路请求
	if int(idle["queue_done"]) != 0:
		fails.append("idle（世界冻结）期间仍完成了 %d 个寻路请求 —— 暂停时必须一个都不提交（见 AIParty.step 的 delta>0 判定）" % int(idle["queue_done"]))
	# B. 不许有可见尖刺
	for tag in ["idle", "march"]:
		var n_stall := int(now[tag]["frames_gt_stall"])
		if n_stall > STALL_TOLERANCE:
			fails.append("%s 场景有 %d 帧超过 %.0f ms（容忍 %d 帧；frame_ms.max %.1f ms）—— 这是玩家看得见的卡顿" % [
				tag, n_stall, STALL_MS, STALL_TOLERANCE, float(now[tag]["frame_ms"]["max"])])
	# C. 队列不许积压
	var party_n := maxi(1, main.ai_parties.size())
	for tag in ["idle", "march"]:
		if int(now[tag]["queue_pending_max"]) > party_n:
			fails.append("%s 场景寻路队列积压到 %d 个（部队数 %d）—— 同一支部队不该有多个在途请求" % [
				tag, int(now[tag]["queue_pending_max"]), party_n])
	if int(march["queue_done"]) <= 0:
		fails.append("march 场景一个寻路请求都没完成 —— 行军令没生效或队列没在推进")
	# 基准有效性：行军场景必须真的在行军，否则这半边测的是「站着不动的世界」
	if int(march["moved_frames"]) < int(round(float(SAMPLE_FRAMES) * MARCH_MIN_RATIO)):
		fails.append("march 场景只有 %d/%d 帧处于行军状态（下限 %.0f%%）—— 行军令没生效或很快停下，该场景的数值无意义" % [
			int(march["moved_frames"]), SAMPLE_FRAMES, MARCH_MIN_RATIO * 100.0])
	if not fails.is_empty():
		for line in fails:
			print("[性能] FAIL：%s" % String(line))
		print("[性能] FAIL：%d 条硬断言未通过（这些与机器负载无关，是机制回归）" % fails.size())
		main.free()
		quit(1)
		return
	print("[性能] 硬断言通过：冻结期 0 个寻路请求 / 无 >%.0f ms 尖刺（容忍 %d 帧）/ 队列峰值 ≤ 部队数 / 行军期完成 %d 个请求" % [
		STALL_MS, STALL_TOLERANCE, int(march["queue_done"])])

	if write_baseline:
		_write_baseline(now)
		main.free()
		return

	var old := _read_baseline()
	if old.is_empty():
		print("[性能] 提示：基线缺失 -> %s（跑一次 -- --write-baseline 建立基线）" % BASELINE)
		main.free()
		quit(0)
		return
	var bad: Array = _compare(old, now)
	if bad.is_empty():
		print("[性能] PASS：未超过基线阈值（frame_ms.avg ×%.2f / p95 ×%.2f）" % [TOL_FRAME, TOL_FRAME_P95])
		main.free()
		quit(0)
		return
	for line in bad:
		print("[性能] 超阈值：%s" % String(line))
	if strict:
		print("[性能] FAIL：--strict 模式下超阈值")
		main.free()
		quit(1)
		return
	print("[性能] WARN：超过基线阈值（本机负载会影响墙钟数值，故默认只警告；加 --strict 可判失败）")
	main.free()
	quit(0)

# ---------------------------------------------------------------- 采样
func _sample(tag: String, marching: bool) -> Dictionary:
	var acc := {"frame_ms": [], "draw_calls": [], "nodes": [], "objects": [], "static_mb": []}
	var moved_frames := 0
	var reissues := 0
	var march_dir := 0.0
	var queue_done_0 := _queue_done()
	var queue_pending_max := 0
	var t_prev := Time.get_ticks_usec()
	for i in SAMPLE_FRAMES:
		await process_frame
		var t_now := Time.get_ticks_usec()
		acc["frame_ms"].append(float(t_now - t_prev) / 1000.0)
		t_prev = t_now
		# 无头运行时鼠标恒在 (0,0)，会持续触发「屏幕边缘平移」把镜头推走 —— 手动按住
		if main.camera_rig != null:
			main.camera_rig.pan_offset = Vector2.ZERO
		# 行军场景必须**整段都在行军**：抵达 / 被挡 / 路径失效都会让玩家停下，而世界时间随之
		# 冻结（TimeFlowController：只有 player.moving 才 MARCHING）—— 一停就换个方向再下一单，
		# 否则后 4/5 的帧测的其实是 idle（旧基线 1024 m 就是 148/300）。
		if marching and reissues < MAX_REISSUES and not main.player.moving and main.battler.battle == null:
			reissues += 1
			march_dir += 0.9
			var base := Vector2(main.player.position.x, main.player.position.z)
			main.time.order_move(base + Vector2(cos(march_dir), sin(march_dir)) * 260.0)
		if marching and main.player.moving:
			moved_frames += 1
		queue_pending_max = maxi(queue_pending_max, _queue_pending())
		acc["draw_calls"].append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		acc["nodes"].append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		acc["objects"].append(Performance.get_monitor(Performance.OBJECT_COUNT))
		acc["static_mb"].append(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	var out := {}
	for k in acc.keys():
		out[k] = _stat(acc[k])
	out["moved_frames"] = moved_frames
	out["reissues"] = reissues
	var stalls := 0
	for v in acc["frame_ms"]:
		if float(v) > STALL_MS:
			stalls += 1
	out["frames_gt_stall"] = stalls
	out["queue_done"] = _queue_done() - queue_done_0
	out["queue_pending_max"] = queue_pending_max
	print("[性能] 场景 %s 采样完成：frame_ms avg %.3f / p95 %.3f / max %.3f（%d/%d 帧行军；续单 %d 次；寻路完成 %d 个；队列峰值 %d；>%.0f ms 的帧 %d）" % [
		tag, float(out["frame_ms"]["avg"]), float(out["frame_ms"]["p95"]), float(out["frame_ms"]["max"]),
		moved_frames, SAMPLE_FRAMES, reissues, int(out["queue_done"]), queue_pending_max, STALL_MS, stalls])
	return out

func _queue_done() -> int:
	if main.data == null or main.data.path_queue == null:
		return 0
	return main.data.path_queue.done_total

func _queue_pending() -> int:
	if main.data == null or main.data.path_queue == null:
		return 0
	return main.data.path_queue.pending

func _stat(arr: Array) -> Dictionary:
	if arr.is_empty():
		return {"avg": 0.0, "p95": 0.0, "max": 0.0, "min": 0.0}
	var s: Array = arr.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += float(v)
	var n := s.size()
	return {
		"avg": sum / float(n),
		"p95": float(s[mini(n - 1, int(floor(float(n) * 0.95)))]),
		"max": float(s[n - 1]),
		"min": float(s[0]),
	}

func _report(now: Dictionary) -> void:
	print("[性能] 指标表（avg / p95 / max）：")
	print("      %-8s %-12s %12s %12s %12s" % ["场景", "指标", "avg", "p95", "max"])
	for scene_tag in ["idle", "march"]:
		var s: Dictionary = now[scene_tag]
		for metric in METRICS:
			var st: Dictionary = s[metric]
			print("      %-8s %-12s %12.3f %12.3f %12.3f" % [
				scene_tag, metric, float(st["avg"]), float(st["p95"]), float(st["max"])])
	print("      注：frame_ms 单位 ms，越小越好；draw_calls 在 headless 恒为 0（需开窗另测）。")

## 取 `--key=值` 形式的用户参数（返回 0.0 表示没给）
func _arg_value(args: PackedStringArray, key: String) -> float:
	for a in args:
		if a.begins_with(key):
			var v := a.substr(key.length())
			if v.is_valid_float():
				return v.to_float()
	return 0.0

func _compare(old: Dictionary, now: Dictionary) -> Array:
	var bad: Array = []
	# 绝不跨尺寸比数值：本工程最大的沟通坑就是「1024 m 门禁口径」被当成「出货口径」。
	# 基线记了尺寸，尺寸不一致时明说「跳过比较」，而不是拿小图基线去判大图回归。
	var old_size := float(old.get("map_size", 0.0))
	if old_size > 0.0 and absf(old_size - main.config.map_size) > 0.5:
		print("[性能] 注意：基线是 %.0f m 的世界、本次跑的是 %.0f m —— 跨尺寸不比较数值（只跑硬断言）" % [
			old_size, main.config.map_size])
		return []
	for scene_tag in ["idle", "march"]:
		var o: Dictionary = old.get(scene_tag, {})
		if o.is_empty():
			bad.append("基线缺少场景 %s" % scene_tag)
			continue
		var n: Dictionary = now[scene_tag]
		var old_avg := float(o.get("frame_ms", {}).get("avg", 0.0))
		var new_avg := float(n["frame_ms"]["avg"])
		if old_avg > 0.05 and new_avg > old_avg * TOL_FRAME:
			bad.append("%s：frame_ms.avg %.3f ms > 基线 %.3f ms × %.2f" % [scene_tag, new_avg, old_avg, TOL_FRAME])
		var old_p95 := float(o.get("frame_ms", {}).get("p95", 0.0))
		var new_p95 := float(n["frame_ms"]["p95"])
		if old_p95 > 0.05 and new_p95 > old_p95 * TOL_FRAME_P95:
			bad.append("%s：frame_ms.p95 %.3f ms > 基线 %.3f ms × %.2f" % [scene_tag, new_p95, old_p95, TOL_FRAME_P95])
	return bad

# ---------------------------------------------------------------- 基线
func _read_baseline() -> Dictionary:
	if not FileAccess.file_exists(BASELINE):
		return {}
	var f := FileAccess.open(BASELINE, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _write_baseline(now: Dictionary) -> void:
	var obj := {
		"note": "由 tools/perf_probe.gd --write-baseline 生成；frame_ms 是 --fixed-fps 60 下的墙钟耗时（本机 headless 实测），仅作回归参考，非硬门槛",
		"seed": main.config.map_seed,
		"map_size": main.config.map_size,
		"frames": SAMPLE_FRAMES,
		"metric_note": "frame_ms = 墙钟 ms/帧；不使用 Performance.TIME_PROCESS（实测为陈旧常数）。跨尺寸不比较数值（_compare 会跳过）",
		"veg_instances": main.vegetation.total(),
		"ai_parties": main.ai_parties.size(),
	}
	for scene_tag in ["idle", "march"]:
		var s: Dictionary = now[scene_tag]
		var flat: Dictionary = {
			"moved_frames": int(s["moved_frames"]),
			"reissues": int(s["reissues"]),
			"frames_gt_stall": int(s["frames_gt_stall"]),
			"queue_done": int(s["queue_done"]),
			"queue_pending_max": int(s["queue_pending_max"]),
		}
		for metric in METRICS:
			flat[metric] = s[metric]
		obj[scene_tag] = flat
	var f := FileAccess.open(BASELINE, FileAccess.WRITE)
	if f == null:
		print("[性能] FAIL：无法写入基线 %s（错误码 %d）" % [BASELINE, FileAccess.get_open_error()])
		main.free()
		quit(2)
		return
	f.store_string(JSON.stringify(obj, "\t") + "\n")
	f.close()
	print("[性能] 已写入基线：%s（idle avg %.3f ms / march avg %.3f ms）" % [
		BASELINE, float(now["idle"]["frame_ms"]["avg"]), float(now["march"]["frame_ms"]["avg"])])
	quit(0)
