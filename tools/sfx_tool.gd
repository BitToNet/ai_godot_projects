## =============================================================================
##  sfx_tool —— 音效自检 / 试听导出 / 音色指纹 / 合成热点体检（**不参与游戏运行**）
##
##  用法（用控制台版引擎，才能看到输出）：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --script res://tools/sfx_tool.gd
##    ... --script res://tools/sfx_tool.gd -- --wav          # 导出试听 wav
##    ... --script res://tools/sfx_tool.gd -- --profile      # 合成热点体检（外层算子耗时）
##    ... --script res://tools/sfx_tool.gd -- --hash         # 打印每个音色的 PCM 指纹
##    ... --script res://tools/sfx_tool.gd -- --check        # 与 tools/sfx_pcm.json 比对
##    ... --script res://tools/sfx_tool.gd -- --write-baseline   # 更新音色指纹基线
##
##  输出（默认模式）：
##    · 每个音效的时长 / 峰值 / RMS / 三段能量占比（低<400Hz 中 400~2000Hz 高>2000Hz）
##      / 过零率（粗略亮度）/ -20dB 衰减时间（听感"尾巴"多长）
##    · --wav 时把每个音效导出成 audio_preview/<id>.wav 供试听
##      （audio_preview/ 里放了 .gdignore，Godot 不会导入这些 wav）
##    · --profile 时额外打印两张表：外层算子耗时（ms / µs 每采样）与逐采样算子次数
##    · --check 时只算 PCM 指纹并与基线比对（门禁用；exit 1 = 音色被改过）
##
##  音色指纹（--check / --write-baseline）：把 28 个音色的 16bit PCM 逐字节哈希后存档，
##  用来把「这次改动没动音色」变成可验证的事实，而不是一句声明。**有意改音色**时
##  必须显式跑一次 --write-baseline 更新 tools/sfx_pcm.json（和生成指纹一个套路）。
## =============================================================================
extends SceneTree

const OUT_DIR := "res://audio_preview"
const PCM_JSON := "res://tools/sfx_pcm.json"
const LP_CUT := 400.0
const HP_CUT := 2000.0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var want_wav := args.has("--wav")
	var want_profile := args.has("--profile")
	var want_hash := args.has("--hash")
	var want_check := args.has("--check")
	var write_baseline := args.has("--write-baseline")
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5F3A17
	var ids := SfxSynth.ids()
	if want_wav:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if want_check or want_hash or write_baseline:
		quit(_fingerprint_run(ids, rng, want_check, write_baseline))
		return
	print("=== 音效自检：%d 个音色（采样率 %d Hz，全部由代码合成）===" % [ids.size(), SfxSynth.RATE])
	print("    分类/量 依据：低频占比大 = 闷响/脚步；高频占比大 = 金属/提示音；衰减时间长 = 有余韵")
	if want_profile:
		SfxSynth.prof_reset()
	var t0 := Time.get_ticks_msec()
	var total_sec := 0.0
	var total_samples := 0
	var bad := 0
	for id in ids:
		var sid := String(id)
		var t_build := Time.get_ticks_msec()
		var st := SfxSynth.build(sid, rng)
		var build_ms := Time.get_ticks_msec() - t_build
		if st == null or st.data.is_empty():
			print("  [!!] %-14s 合成失败" % sid)
			bad += 1
			continue
		var mono := _decode(st)
		var n := mono.size()
		var sec := float(n) / float(st.mix_rate)
		total_sec += sec
		total_samples += n
		var peak := 0.0
		var sum2 := 0.0
		for i in n:
			var v := mono[i]
			peak = maxf(peak, absf(v))
			sum2 += v * v
		var rms := sqrt(sum2 / float(maxi(1, n)))
		var b := _bands(mono, st.mix_rate)
		var meta := SfxSynth.meta(sid)
		print("  %-14s %5.2fs 峰 %.2f RMS %.3f | 低 %3.0f%% 中 %3.0f%% 高 %3.0f%% | 过零 %5.0fHz | -20dB %.2fs | %s %.1fdB | %4dms" % [
			sid, sec, peak, rms, b[0], b[1], b[2], _zcr(mono, st.mix_rate), _decay_time(mono, peak, st.mix_rate),
			String(meta[0]), float(meta[1]), build_ms])
		if peak < 0.05 or rms < 0.002:
			print("     [!!] %s 几乎无声，检查合成参数" % sid)
			bad += 1
		if want_wav:
			_write_wav("%s/%s.wav" % [OUT_DIR, sid], st.data, st.mix_rate)
	if want_profile:
		_print_profile()
	print("--- 合计 %.2f 秒音频 / %d 个采样；合成耗时 %d ms；异常 %d 个 ---" % [
		total_sec, total_samples, Time.get_ticks_msec() - t0, bad])
	if want_wav:
		print("已导出试听文件到：%s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(1 if bad > 0 else 0)

# =============================================================== 音色指纹
## 28 个音色的 PCM 逐字节指纹。哈希里带上 id 与长度，免得"两个音色互换"看不出来。
## RATE 也进哈希：采样率变了而 PCM 字节恰好一样时同样应当报不同。
## ⚠ 配方住在 SfxCache.total_of()（音色缓存要用同一套值来判缓存是否可用），这里只调它 ——
##    两处各写一份的话，一旦悄悄漂移，"缓存指纹 == 仓库基线"这条断言就会莫名其妙地失灵。
func _fingerprint_run(ids: Array, rng: RandomNumberGenerator, check: bool, write_baseline: bool) -> int:
	var per := {}
	var datas := {}
	var samples := 0
	var t0 := Time.get_ticks_msec()
	for id in ids:
		var sid := String(id)
		var st := SfxSynth.build(sid, rng)
		if st == null or st.data.is_empty():
			print("[音色指纹] FAIL：%s 合成失败" % sid)
			return 1
		per[sid] = SfxCache.sha256(st.data)
		datas[sid] = st.data
		samples += st.data.size() / 2
	var total := SfxCache.total_of(datas)
	var ms := Time.get_ticks_msec() - t0
	if write_baseline:
		var f := FileAccess.open(PCM_JSON, FileAccess.WRITE)
		if f == null:
			print("[音色指纹] FAIL：无法写入 %s" % PCM_JSON)
			return 1
		f.store_string(JSON.stringify({
			"note": "音色 PCM 指纹基线（sfx_tool.gd --write-baseline 生成；有意改音色后才更新）",
			"rate": SfxSynth.RATE,
			"count": ids.size(),
			"samples": samples,
			"total": total,
			"ids": per,
		}, "  ") + "\n")
		f.close()
		print("[音色指纹] 已写入基线 %s（%d 个音色 / %d 采样 / 合计 %s）" % [
			PCM_JSON, ids.size(), samples, total.substr(0, 16)])
		return 0
	if check:
		var base := _load_baseline()
		if base.is_empty():
			print("[音色指纹] FAIL：基线缺失或不可读：%s（先跑一次 -- --write-baseline）" % PCM_JSON)
			return 1
		var old_ids: Dictionary = base.get("ids", {})
		var changed: Array = []
		for id in ids:
			var sid := String(id)
			if String(old_ids.get(sid, "")) != String(per[sid]):
				changed.append(sid)
		var extra: Array = []
		for k in old_ids.keys():
			if not per.has(String(k)):
				extra.append(String(k))
		if changed.is_empty() and extra.is_empty() and String(base.get("total", "")) == total:
			print("[音色指纹] PASS：%d 个音色 PCM 与基线逐字节一致（%d 采样 / 合计 %s）" % [
				ids.size(), samples, total.substr(0, 16)])
			return 0
		var head := changed.slice(0, 6)
		print("[音色指纹] FAIL：音色 PCM 与基线不同 —— 变了 %d 个%s%s；基线多出 %d 个%s；合计 %s ≠ 基线 %s" % [
			changed.size(),
			("：" + ", ".join(head) + ("…" if changed.size() > head.size() else "")) if changed.size() > 0 else "",
			"",
			extra.size(),
			("：" + ", ".join(extra.slice(0, 6))) if extra.size() > 0 else "",
			total.substr(0, 16), String(base.get("total", "?")).substr(0, 16)])
		print("        > 有意改音色就重跑：--script res://tools/sfx_tool.gd -- --write-baseline")
		return 1
	for id in ids:
		var sid := String(id)
		print("  %-14s %s" % [sid, String(per[sid]).substr(0, 16)])
	print("[音色指纹] 合计 %s（%d 个音色 / %d 采样 / 合成 %d ms）" % [
		total, ids.size(), samples, ms])
	return 0

func _load_baseline() -> Dictionary:
	if not FileAccess.file_exists(PCM_JSON):
		return {}
	var f := FileAccess.open(PCM_JSON, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	# 用实例版 parse：JSON.parse_string 失败时会 ERR_PRINT，而门禁对 ERROR 零容忍
	var j := JSON.new()
	if j.parse(txt) != OK:
		return {}
	return j.data if j.data is Dictionary else {}

## 保留这个薄封装只是为了不动其它调用点；实现与 SfxCache.sha256 完全相同
func _sha256_bytes(data: PackedByteArray) -> String:
	return SfxCache.sha256(data)

# =============================================================== 合成热点报表
func _print_profile() -> void:
	SfxSynth.prof_off()
	print("--- 合成热点：外层算子（按耗时降序；µs/采样 = 该算子单位成本）---")
	for r in SfxSynth.prof_report():
		print("  %-22s %5d 次 / %7d 采样 / %7.1f ms / %6.3f µs/采样" % [
			String(r[0]), int(r[1]), int(r[2]), float(r[3]), float(r[4])])
	print("--- 逐采样算子次数（由外层推导，不进计时器以免盖过被测代码）---")
	for r in SfxSynth.prof_op_report():
		print("  %-28s %8d 次" % [String(r[0]), int(r[1])])

func _decode(st: AudioStreamWAV) -> PackedFloat32Array:
	var n := st.data.size() / 2
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = float(st.data.decode_s16(i * 2)) / 32768.0
	return out

## 三段能量占比（一阶滤波器级联，O(n)，够粗略判断音色明暗）
func _bands(x: PackedFloat32Array, rate: int) -> Array:
	var a_lp := 1.0 - exp(-TAU * LP_CUT / float(rate))
	var a_hp := 1.0 - exp(-TAU * HP_CUT / float(rate))
	var lp1 := 0.0
	var lp2 := 0.0
	var hp1 := 0.0
	var hp2 := 0.0
	var e_low := 0.0
	var e_high := 0.0
	var e_all := 0.0
	for i in x.size():
		var v := x[i]
		e_all += v * v
		lp1 += a_lp * (v - lp1)
		lp2 += a_lp * (lp1 - lp2)
		e_low += lp2 * lp2
		hp1 += a_hp * (v - hp1)
		hp2 += a_hp * (hp1 - hp2)
		var hi := v - hp2
		e_high += hi * hi
	var total := maxf(1e-12, e_all)
	var low := 100.0 * e_low / total
	var high := 100.0 * e_high / total
	var mid := maxf(0.0, 100.0 - low - high)
	return [low, mid, high]

## 过零率（Hz）：粗略的"亮度"指标
func _zcr(x: PackedFloat32Array, rate: int) -> float:
	var c := 0
	for i in range(1, x.size()):
		if (x[i - 1] < 0.0) != (x[i] < 0.0):
			c += 1
	return float(c) * float(rate) / (2.0 * float(maxi(1, x.size())))

## 从峰值衰减 20dB 所需时间（按 1ms 分块取包络峰值）
func _decay_time(x: PackedFloat32Array, peak: float, rate: int) -> float:
	if peak <= 0.0:
		return 0.0
	var block := maxi(1, int(0.001 * float(rate)))
	var thr := peak * 0.1
	var last := 0
	var i := 0
	while i < x.size():
		var m := 0.0
		var j := mini(x.size(), i + block)
		for k in range(i, j):
			m = maxf(m, absf(x[k]))
		if m > thr:
			last = i
		i = j
	return float(last) / float(rate)

func _write_wav(path: String, pcm: PackedByteArray, rate: int) -> void:
	var h := PackedByteArray()
	h.resize(44)
	h.encode_u32(0, 0x46464952)          # "RIFF"
	h.encode_u32(4, 36 + pcm.size())
	h.encode_u32(8, 0x45564157)          # "WAVE"
	h.encode_u32(12, 0x20746D66)         # "fmt "
	h.encode_u32(16, 16)
	h.encode_u16(20, 1)                  # PCM
	h.encode_u16(22, 1)                  # 单声道
	h.encode_u32(24, rate)
	h.encode_u32(28, rate * 2)           # 字节率
	h.encode_u16(32, 2)                  # 块对齐
	h.encode_u16(34, 16)                 # 位深
	h.encode_u32(36, 0x61746164)         # "data"
	h.encode_u32(40, pcm.size())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("  [!!] 无法写入 %s" % path)
		return
	f.store_buffer(h)
	f.store_buffer(pcm)
	f.close()