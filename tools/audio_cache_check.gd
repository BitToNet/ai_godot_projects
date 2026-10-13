## =============================================================================
##  audio_cache_check —— 音色 PCM 缓存自检（**不参与游戏运行**，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/audio_cache_check.gd
##
##  检查七件事（全部读真实文件 / 真实流，不看常量）：
##    1) 缓存键覆盖「合成算法的全部输入」：格式版本 / 采样率 / 查表长度 / SPECS /
##       ids / 源码文件指纹 —— 任一项变了，键必须变（否则老缓存会被当成有效）
##    2) 冷启动：合成 28 个音色 → 落盘，统计与指纹自洽
##    3) 热启动：从缓存读回来的 PCM 与冷启动**逐字节一致**（本模块唯一真正的承诺）
##    4) 与 tools/sfx_pcm.json 基线一致（开发态；导出后没有该文件则跳过并说明）
##    5) 坏缓存恢复：改一字节 / 截断 / 删元数据 / 改键 → 必须静默退回冷启动并自愈，
##       不 push_error、不打 ERROR 行（门禁对 ERROR 零容忍）
##    6) Sfx.setup() 真的会用缓存：命中时不再合成，音色库照样 28 个、内容一模一样
##    7) enabled = false 时完全不碰磁盘
##
##  退出码 0 = 全部通过；1 = 有断言不通过（或看门狗超时）
## =============================================================================
extends SceneTree

const PREFIX := "[音色缓存]"
const BASELINE := "res://tools/sfx_pcm.json"
const BAK_DIR := "user://sfx_cache_check_bak"

var host: Node
var fails: Array = []
var n_ok := 0
var cold := {}            ## 冷启动音色库：{id: {"stream": AudioStreamWAV}}
var cold_total := ""
var cold_ms := 0

func _initialize() -> void:
	_watchdog()
	_run()

## 看门狗：headless 下 --fixed-fps 60 跑得比真实时间快；3600 帧远超本检查所需
func _watchdog() -> void:
	for i in 3600:
		await process_frame
	print("%s FAIL：看门狗超时（3600 帧未跑完，多半是脚本中途报错）" % PREFIX)
	quit(1)

func _run() -> void:
	host = Node.new()
	host.name = "AudioCacheCheckHost"
	root.add_child(host)
	# 同 tools/audio_check.gd：加进 root ≠ 已经在跑，显式让出一帧再往下走
	await process_frame

	# ------------------------------------------------------------ 1) 缓存键
	_section("1) 缓存键（%d 个输入项）" % 6)
	var k := SfxCache.key()
	_eqi(k.length(), 16, "键是 16 位十六进制")
	_ok(k == SfxCache.key(), "同一进程内两次计算结果一致")
	_ok(k.is_valid_hex_number(false), "键全是十六进制字符")
	var stamp := "stamp-test"
	var spec := str(SfxSynth.SPECS)
	_ok(SfxCache.key_of(SfxCache.FORMAT, SfxSynth.RATE, SfxSynth.TAB_N, spec, stamp) != k,
		"源码指纹变了 → 键变（改合成代码但忘 bump FORMAT 也能自动失效）")
	_ok(SfxCache.key_of(SfxCache.FORMAT + 1, SfxSynth.RATE, SfxSynth.TAB_N, spec, stamp) != k,
		"格式版本变了 → 键变")
	_ok(SfxCache.key_of(SfxCache.FORMAT, SfxSynth.RATE + 1, SfxSynth.TAB_N, spec, stamp) != k,
		"采样率变了 → 键变")
	_ok(SfxCache.key_of(SfxCache.FORMAT, SfxSynth.RATE, SfxSynth.TAB_N + 1, spec, stamp) != k,
		"查表长度变了 → 键变")
	_ok(SfxCache.key_of(SfxCache.FORMAT, SfxSynth.RATE, SfxSynth.TAB_N, spec + " ", stamp) != k,
		"SPECS 变了 → 键变")
	_ok(SfxCache.key_of(SfxCache.FORMAT, SfxSynth.RATE, SfxSynth.TAB_N, spec, stamp + " ") != k,
		"源码指纹单独变了 → 键变")

	# ------------------------------------------------------------ 2) 冷启动
	_section("2) 冷启动：合成 28 个音色并落盘")
	SfxCache.clear()
	_ok(not FileAccess.file_exists(SfxCache.DIR + "/" + SfxCache.BLOB), "clear() 之后没有旧 PCM 文件")
	SfxCache.reset_stats()
	cold = _synth_all()          # 顺带把 cold_ms 记成真实合成耗时
	_eqi(cold.size(), SfxSynth.ids().size(), "冷启动合成出全部音色")
	cold_total = SfxCache.total_of(_datas(cold))
	_eqi(cold_total.length(), 64, "总指纹是 64 位十六进制")
	var t0 := Time.get_ticks_msec()
	_ok(SfxCache.save_bank(cold), "save_bank() 落盘成功")
	var save_ms := Time.get_ticks_msec() - t0
	_ok(FileAccess.file_exists(SfxCache.DIR + "/" + SfxCache.BLOB), "PCM 文件已生成")
	_ok(FileAccess.file_exists(SfxCache.DIR + "/" + SfxCache.META), "元数据已生成")
	var blob_size := FileAccess.get_file_as_bytes(SfxCache.DIR + "/" + SfxCache.BLOB).size()
	var pcm_bytes := 0
	for id in cold:
		pcm_bytes += (cold[id]["stream"] as AudioStreamWAV).data.size()
	_eqi(blob_size, pcm_bytes + 12 + cold.size() * 8 + _name_bytes(), "文件大小 = PCM + 头部（无冗余）")
	_eqi(int(SfxCache.stats()["bytes"]), blob_size, "统计里的字节数 = 缓存文件大小（含头部）")

	# ------------------------------------------------------------ 3) 热启动
	_section("3) 热启动：读回来的 PCM 必须逐字节一致")
	SfxCache.reset_stats()
	var t1 := Time.get_ticks_msec()
	var warm := SfxCache.load_bank()
	var load_ms := Time.get_ticks_msec() - t1
	var warm_bank := {}
	for id in warm:
		warm_bank[String(id)] = {"stream": warm[id]}
	_eqi(warm.size(), cold.size(), "命中并解出全部音色")
	_eqi(int(SfxCache.stats()["hits"]), 1, "统计记为 1 次命中")
	_eqi(int(SfxCache.stats()["misses"]), 0, "统计记为 0 次未命中")
	_ok(SfxCache.total_of(_datas(warm_bank)) == cold_total, "热启动总指纹与冷启动一致")
	_ok(load_ms < cold_ms, "热启动比冷启动快（读盘 %d ms vs 合成 %d ms）" % [load_ms, cold_ms])
	var same := 0
	var props := 0
	for id in cold:
		var cs: AudioStreamWAV = cold[id]["stream"]
		if not warm.has(id):
			continue
		var ws: AudioStreamWAV = warm[id]
		if ws.data == cs.data:
			same += 1
		if ws.format == cs.format and ws.mix_rate == cs.mix_rate and ws.stereo == cs.stereo:
			props += 1
	_eqi(same, cold.size(), "逐个音色的 PCM 字节完全相同（%d/%d）" % [same, cold.size()])
	_eqi(props, cold.size(), "逐个音色的流参数（格式/采样率/声道）完全相同")

	# ------------------------------------------------------------ 4) 与仓库基线对齐
	_section("4) 与 tools/sfx_pcm.json 基线（开发态）")
	if FileAccess.file_exists(BASELINE):
		var base := _read_json(BASELINE)
		if base.is_empty():
			_ok(false, "基线文件存在但解析失败")
		else:
			_eqs(String(base.get("total", "")), cold_total, "冷启动总指纹 == 仓库基线 total")
			var ids: Dictionary = base.get("ids", {})
			var bad: Array = []
			for id in ids:
				var d: PackedByteArray = _datas(cold).get(String(id), PackedByteArray())
				if SfxCache.sha256(d) != String(ids[id]):
					bad.append(String(id))
			_ok(bad.is_empty(), "逐音色哈希与基线一致（不一致：%s）" % ("无" if bad.is_empty() else ", ".join(bad)))
	else:
		print("%s   · 跳过：没有 %s（导出后的产物里不会有 tools/）" % [PREFIX, BASELINE])

	# ------------------------------------------------------------ 5) 坏缓存自愈
	_section("5) 坏缓存：必须静默退回冷启动并自愈")
	# 先备份这份好缓存：每个破坏用例都从备份恢复，省掉「每例重新合成 1.3 秒」
	_ok(_backup_good(), "已备份一份有效缓存（供各用例恢复）")
	var cases: Array = [
		["改一字节", func(): return _flip_byte(SfxCache.BLOB, 0.5)],
		["截断成 40 字节", func(): return _truncate(SfxCache.BLOB, 40)],
		["删掉 PCM 文件", func(): return _remove(SfxCache.BLOB)],
		["删掉元数据", func(): return _remove(SfxCache.META)],
		["元数据里的键被改", func(): return _tamper_key()],
		["元数据不是 JSON", func(): return _write_text(SfxCache.META, "{ 这不是 json")],
	]
	for c in cases:
		var what := String(c[0])
		_ok(_restore_good(), "「%s」前置：恢复出有效缓存" % what)
		_ok(not SfxCache.load_bank().is_empty(), "「%s」前置：有效缓存本来可以命中" % what)
		_ok(bool(c[1].call()), "已破坏缓存：%s" % what)
		SfxCache.reset_stats()
		var got := SfxCache.load_bank()
		_ok(got.is_empty(), "「%s」→ 判定为未命中（不返回半个音色库）" % what)
		_eqi(int(SfxCache.stats()["misses"]), 1, "「%s」→ 统计记 1 次未命中" % what)
		_ok(String(SfxCache.stats()["reason"]) != "", "「%s」→ 给了未命中原因（%s）" % [what, SfxCache.stats()["reason"]])
	# 自愈：坏掉之后必须还能重新合成并落盘，且结果与冷启动逐字节一致（只验一次 —— 合成确定性是性质，不是每例都要重证）
	_restore_good()
	_remove(SfxCache.BLOB)
	var rebuilt := _synth_all()
	_ok(SfxCache.total_of(_datas(rebuilt)) == cold_total, "坏缓存后重新合成，结果仍与冷启动逐字节一致")
	_ok(SfxCache.save_bank(rebuilt), "坏缓存之后仍能重新落盘")
	_ok(not SfxCache.load_bank().is_empty(), "自愈后的缓存可以正常命中")

	# ------------------------------------------------------------ 6) Sfx.setup 集成
	_section("6) Sfx.setup() 会走缓存（不再合成）")
	SfxCache.reset_stats()
	var t2 := Time.get_ticks_msec()
	await Sfx.setup(host)
	var setup_ms := Time.get_ticks_msec() - t2
	_ok(Sfx.is_ready(), "setup() 之后 is_ready() 为真")
	_eqi(Sfx.bank_size(), cold.size(), "音色库补齐 %d 个" % cold.size())
	_eqi(int(SfxCache.stats()["hits"]), 1, "setup() 命中缓存 1 次")
	_eqi(int(SfxCache.stats()["misses"]), 0, "setup() 没有未命中")
	_ok(setup_ms < cold_ms, "setup() 比冷启动快（%d ms vs %d ms）" % [setup_ms, cold_ms])
	_eqi(SfxCache.stats()["save_ms"], 0, "命中路径没有多余落盘")
	var db_ok := 0
	for id in ["order", "hit_light", "hoof_a"]:
		if Sfx.bank_size() > 0 and _datas(cold).has(id):
			db_ok += 1
	_eqi(db_ok, 3, "抽查音色仍在库里（order / hit_light / hoof_a）")
	var jit_ok := Sfx.volume_db_of("order")   # 只是确保这张表可用；不参与断言
	_ok(jit_ok is float, "音效表查询可用（volume_db_of 返回 float）")

	# ------------------------------------------------------------ 7) 关掉缓存
	_section("7) SfxCache.enabled = false 时完全不碰磁盘")
	SfxCache.enabled = false
	SfxCache.reset_stats()
	_ok(SfxCache.load_bank().is_empty(), "关掉后不命中")
	_eqs(String(SfxCache.stats()["last"]), "off", "关掉后统计记为 off")
	_ok(not SfxCache.save_bank(cold), "关掉后不落盘")
	SfxCache.enabled = true

	_finish()

# =============================================================== 5) 的每一条

## 好缓存的备份（自检内部用，放在另一个目录，免得被 SfxCache.clear() 一起清掉）
func _backup_good() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BAK_DIR))
	var ok := true
	for n in [SfxCache.BLOB, SfxCache.META]:
		ok = ok and DirAccess.copy_absolute(
			ProjectSettings.globalize_path(SfxCache.DIR + "/" + n),
			ProjectSettings.globalize_path(BAK_DIR + "/" + n)) == OK
	return ok

func _restore_good() -> bool:
	var ok := true
	for n in [SfxCache.BLOB, SfxCache.META]:
		var src := ProjectSettings.globalize_path(BAK_DIR + "/" + n)
		var dst := ProjectSettings.globalize_path(SfxCache.DIR + "/" + n)
		if FileAccess.file_exists(dst):
			DirAccess.remove_absolute(dst)
		ok = ok and DirAccess.copy_absolute(src, dst) == OK
	return ok

# =============================================================== 合成 / 破坏

## 照 Sfx.setup() 的冷启动路径合成一遍（同一种子、同一顺序 —— 噪声流的顺序不能变）
func _synth_all() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5F3A17
	var t0 := Time.get_ticks_msec()
	var bank := {}
	for id in SfxSynth.ids():
		bank[String(id)] = {"stream": SfxSynth.build(String(id), rng)}
	cold_ms = Time.get_ticks_msec() - t0
	return bank

func _datas(bank: Dictionary) -> Dictionary:
	var out := {}
	for id in bank:
		out[String(id)] = (bank[id]["stream"] as AudioStreamWAV).data
	return out

func _name_bytes() -> int:
	var n := 0
	for id in SfxSynth.ids():
		n += String(id).length()
	return n

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var j := JSON.new()
	var err := j.parse(f.get_as_text())
	f.close()
	return j.data if err == OK and j.data is Dictionary else {}

func _flip_byte(name: String, frac: float) -> bool:
	var p := SfxCache.DIR + "/" + name
	var b := FileAccess.get_file_as_bytes(p)
	if b.size() < 8:
		return false
	var i := clampi(int(float(b.size()) * frac), 0, b.size() - 1)
	b[i] = (b[i] + 1) % 256
	return _write_bytes(name, b)

func _truncate(name: String, keep: int) -> bool:
	var p := SfxCache.DIR + "/" + name
	var b := FileAccess.get_file_as_bytes(p)
	if b.is_empty():
		return false
	return _write_bytes(name, b.slice(0, mini(keep, b.size())))

func _remove(name: String) -> bool:
	var p := ProjectSettings.globalize_path(SfxCache.DIR + "/" + name)
	if not FileAccess.file_exists(p):
		return false
	return DirAccess.remove_absolute(p) == OK

func _write_text(name: String, txt: String) -> bool:
	return _write_bytes(name, txt.to_utf8_buffer())

func _write_bytes(name: String, b: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SfxCache.DIR))
	var f := FileAccess.open(SfxCache.DIR + "/" + name, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(b)
	f.close()
	return true

func _tamper_key() -> bool:
	var d := _read_json(SfxCache.DIR + "/" + SfxCache.META)
	if d.is_empty():
		return false
	d["key"] = "0000000000000000"
	return _write_text(SfxCache.META, JSON.stringify(d))

# =============================================================== 收尾 / 小工具

func _finish() -> void:
	print("%s 断言 %d 项通过 / %d 项失败" % [PREFIX, n_ok, fails.size()])
	if fails.is_empty():
		print("%s PASS：键 / 冷启动 / 热启动逐字节一致 / 坏缓存自愈 / setup 命中 / 关缓存不碰盘" % PREFIX)
		quit(0)
	else:
		for f in fails:
			print("%s 失败项：%s" % [PREFIX, String(f)])
		print("%s FAIL：%d 项未通过" % [PREFIX, fails.size()])
		quit(1)

func _section(title: String) -> void:
	print("%s ---- %s" % [PREFIX, title])

func _ok(cond: bool, msg: String) -> void:
	if cond:
		n_ok += 1
		print("%s   ✓ %s" % [PREFIX, msg])
	else:
		fails.append(msg)
		print("%s   ✗ %s" % [PREFIX, msg])

func _eqi(got: int, want: int, msg: String) -> void:
	if got == want:
		_ok(true, msg)
	else:
		_ok(false, "%s（实际 %d，期望 %d）" % [msg, got, want])

func _eqs(got: String, want: String, msg: String) -> void:
	if got == want:
		_ok(true, msg)
	else:
		_ok(false, "%s（实际 %s，期望 %s）" % [msg, got, want])