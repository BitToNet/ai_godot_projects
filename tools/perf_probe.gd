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

var main: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	var user_args := OS.get_cmdline_user_args()
	var write_baseline := user_args.has("--write-baseline")
	var strict := user_args.has("--strict")

	var scene: PackedScene = load(SCENE)
	main = scene.instantiate()
	var ac := AudioConfig.new()
	ac.enabled = false           # 本探针不测音频合成；如需测，把它改回 true
	main.audio = ac
	main.config = MapConfig.new()
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

	print("[性能] 环境：种子 %d / 生成 %d ms / 植被 %d 实例 / AI 部队 %d 支 / 采样 %d 帧 × 2 场景" % [
		main.config.map_seed, int(main._gen_ms), main.vegetation.total(), main.ai_parties.size(), SAMPLE_FRAMES])
	print("[性能] 口径：frame_ms = 墙钟耗时（--fixed-fps 60 关闭实时同步）；不使用 Performance.TIME_PROCESS")

	# ---- 场景 1：idle（世界时间冻结）----
	var idle := await _sample("idle", false)

	# ---- 场景 2：march（下达行军令，世界时间流动）----
	var p := Vector2(main.player.position.x, main.player.position.z)
	var goal := Vector2(p.x + 160.0, p.y + 120.0)
	main._order_move(goal)
	var march := await _sample("march", true)

	var now := {"idle": idle, "march": march}
	_report(now)

	# 基准有效性：行军场景必须真的动起来，否则这半边测的是「站着不动的世界」
	if int(march["moved_frames"]) == 0:
		print("[性能] FAIL：march 场景 0/%d 帧处于行军状态 —— 行军令没生效，该场景的数值无意义" % SAMPLE_FRAMES)
		main.free()
		quit(1)
		return

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
	var t_prev := Time.get_ticks_usec()
	for i in SAMPLE_FRAMES:
		await process_frame
		var t_now := Time.get_ticks_usec()
		acc["frame_ms"].append(float(t_now - t_prev) / 1000.0)
		t_prev = t_now
		# 无头运行时鼠标恒在 (0,0)，会持续触发「屏幕边缘平移」把镜头推走 —— 手动按住
		if main.camera_rig != null:
			main.camera_rig.pan_offset = Vector2.ZERO
		if marching and main.player.moving:
			moved_frames += 1
		acc["draw_calls"].append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		acc["nodes"].append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		acc["objects"].append(Performance.get_monitor(Performance.OBJECT_COUNT))
		acc["static_mb"].append(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	var out := {}
	for k in acc.keys():
		out[k] = _stat(acc[k])
	out["moved_frames"] = moved_frames
	print("[性能] 场景 %s 采样完成：frame_ms avg %.3f / p95 %.3f（%d/%d 帧处于行军状态）" % [
		tag, float(out["frame_ms"]["avg"]), float(out["frame_ms"]["p95"]), moved_frames, SAMPLE_FRAMES])
	return out

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

func _compare(old: Dictionary, now: Dictionary) -> Array:
	var bad: Array = []
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
		"frames": SAMPLE_FRAMES,
		"metric_note": "frame_ms = 墙钟 ms/帧；不使用 Performance.TIME_PROCESS（实测为陈旧常数）",
		"veg_instances": main.vegetation.total(),
		"ai_parties": main.ai_parties.size(),
	}
	for scene_tag in ["idle", "march"]:
		var s: Dictionary = now[scene_tag]
		var flat: Dictionary = {"moved_frames": int(s["moved_frames"])}
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
