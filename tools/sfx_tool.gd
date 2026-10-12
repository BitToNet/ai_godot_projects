## =============================================================================
##  sfx_tool —— 音效自检 / 试听导出工具（**不参与游戏运行**，只在命令行用）
##
##  用法（用控制台版引擎，才能看到输出）：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --script res://tools/sfx_tool.gd
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --script res://tools/sfx_tool.gd -- --wav
##
##  输出：
##    · 每个音效的时长 / 峰值 / RMS / 三段能量占比（低<400Hz 中 400~2000Hz 高>2000Hz）
##      / 过零率（粗略亮度）/ -20dB 衰减时间（听感"尾巴"多长）
##    · --wav 时把每个音效导出成 audio_preview/<id>.wav 供试听
##      （audio_preview/ 里放了 .gdignore，Godot 不会导入这些 wav）
## =============================================================================
extends SceneTree

const OUT_DIR := "res://audio_preview"
const LP_CUT := 400.0
const HP_CUT := 2000.0

func _init() -> void:
	var want_wav := OS.get_cmdline_user_args().has("--wav")
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5F3A17
	var ids := SfxSynth.ids()
	if want_wav:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	print("=== 音效自检：%d 个音色（采样率 %d Hz，全部由代码合成）===" % [ids.size(), SfxSynth.RATE])
	print("    分类/量 依据：低频占比大 = 闷响/脚步；高频占比大 = 金属/提示音；衰减时间长 = 有余韵")
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
	print("--- 合计 %.2f 秒音频 / %d 个采样；合成耗时 %d ms；异常 %d 个 ---" % [
		total_sec, total_samples, Time.get_ticks_msec() - t0, bad])
	if want_wav:
		print("已导出试听文件到：%s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(1 if bad > 0 else 0)

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
