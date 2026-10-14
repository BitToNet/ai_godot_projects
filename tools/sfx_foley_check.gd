## =============================================================================
##  sfx_foley_check —— 录音素材层（SfxFoley）自检（**不参与游戏运行**，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/sfx_foley_check.gd
##
##  做五件事：
##    1) 清单：每个动作的变体数是否达到预期、缺失清单是否为空
##    2) 规格：单声道 / 44100 Hz / 时长区间 / 不削波 / 非静音
##    3) 响度：每个动作的录音素材与**它替换掉的合成音色**逐项对照，
##       峰值 dB 与 10ms 窗口 RMS dB 两个口径都印出来
##    4) 校准提示：若两者偏离，直接打印"该给这个动作加多少 dB"的建议值，
##       把该值填进 audio/sfx/foley 的构建脚本（build_foley.ps1 的 $match 表）后重建即可。
##    5) 运行时挂载：再走一遍游戏真正走的路（`Sfx.setup()` 建库），确认录音变体**真的挂在
##       音色条目上** —— 只查素材层的话，"素材齐全但 _attach_foley 没跑"会一路绿灯，
##       而游戏里仍然在放合成音色。
##
##  为什么要做响度对照：素材是**噪波型**，合成音色是**音色型**，同样峰值下听感
##  差别很大。这一步保证"换素材"不顺手把整套混音的平衡改掉。
##
##  退出码 0 = 全部通过；1 = 有缺失 / 规格不符 / 与合成音色偏离过大
## =============================================================================
extends SceneTree

## 期望的变体数下限（与 SfxFoley.SETS 一一对应）
const EXPECT := {
	"step_a": 4, "step_b": 4, "step_heavy": 3,
	"hoof_a": 4, "hoof_b": 4, "jump": 3, "land": 3, "dodge": 3,
	"hit_light": 2, "hit_heavy": 2, "hit_crit": 2,
	"parry": 2, "parry_reflect": 2, "sword_wave": 2,
}
const DUR_MIN := 0.05          ## 短于这个长度不可能是一次完整动作
const DUR_MAX := 1.50          ## 长于这个长度会拖住下一次触发
const PEAK_MAX_DB := -0.5      ## 削波余量
const SILENT_DB := -60.0       ## 低于此值判为"素材是空的"
## 响度对齐容差（dB）—— 峰值与窗口 RMS 分开定，因为"真实录音"和"合成噪波"的
## 波峰因数天然不同：真实脚步起音陡、尾巴短（波峰因数 ≈13 dB），合成的脚步是
## 密集滤噪（只有 ≈6 dB）。于是：
##   · 峰值必须贴齐（±4 dB）—— 耳朵靠起音瞬态判断"这一下踩实了没有"，
##     瞬态在混音里的位置不能动；
##   · 窗口 RMS 允许低（-9 dB）但不允许高（+4 dB）—— 要按 RMS 拉平就得把起音
##     压掉约 7 dB（限幅器重压），而那一压恰好把脚步声里唯一"像人"的地方压没了。
##   密集的素材（马蹄 / 重步 / 打击，波峰因数与合成音色接近）自然两个口径都会贴齐。
const TOL_PEAK_DB := 4.0
const TOL_RMS_LO := -9.0
const TOL_RMS_HI := 4.0
const RNG_SEED := 20241014     ## 合成音色复现用的固定种子（响度对种子不敏感）

func _initialize() -> void:
	_run()

func _run() -> void:
	var fail: Array[String] = []
	_check_assets(fail)
	await _check_runtime(fail)
	if fail.is_empty():
		print("[录音素材自检] PASS：%d 个动作 / %d 个变体，规格与响度均与合成音色对齐（峰值 ±%.1f dB，窗口 RMS %+.1f~%+.1f dB）" % [
			EXPECT.size(), SfxFoley.total_variants(), TOL_PEAK_DB, TOL_RMS_LO, TOL_RMS_HI])
		quit(0)
	else:
		print("[录音素材自检] FAIL：")
		for f in fail:
			print("      - " + f)
		quit(1)

## 素材层：清单 / 变体数 / 规格 / 与合成音色的响度对照
func _check_assets(fail: Array[String]) -> void:
	if not SfxFoley.is_ready():
		SfxFoley.load_all()
	var missing := SfxFoley.missing()
	if not missing.is_empty():
		fail.append("缺失变体 %d 个：%s" % [missing.size(), str(missing.slice(0, 6))])

	print("[录音素材自检] 清单：%d 个动作 / %d 个变体（缺失 %d）" % [
		SfxFoley.SETS.size(), SfxFoley.total_variants(), missing.size()])
	print("[录音素材自检] 加载耗时 %d ms" % SfxFoley.load_ms())

	var rows: Array = []
	for id in SfxFoley.SETS.keys():
		var sid := String(id)
		var want := int(EXPECT.get(sid, 1))
		var arr := SfxFoley.variants_of(sid)
		if arr.is_empty():
			fail.append("%s 一个变体都没挂上（对应动作仍在用合成音色）" % sid)
			continue
		if arr.size() < want:
			fail.append("%s 只有 %d 个变体（期望 ≥ %d）" % [sid, arr.size(), want])
		# 该动作替换掉的合成音色（用固定种子重建，取响度）
		var rng := RandomNumberGenerator.new()
		rng.seed = RNG_SEED
		var synth := SfxSynth.build(sid, rng)
		var ss := _stats(synth)
		# 录音变体：逐个查规格，响度取全部 take 的中位数（避免单个 take 拉偏结论）
		var peaks: Array[float] = []
		var rms: Array[float] = []
		var dur_min := 1e9
		var dur_max := 0.0
		for st in arr:
			var w := st as AudioStreamWAV
			var s := _stats(w)
			if w.stereo:
				fail.append("%s：素材是立体声，3D/2D 定位播放要求单声道" % sid)
			if w.mix_rate != 44100:
				fail.append("%s：采样率 %d != 44100" % [sid, w.mix_rate])
			if s.dur < DUR_MIN or s.dur > DUR_MAX:
				fail.append("%s：时长 %.3fs 超出 %.2f~%.2fs" % [sid, s.dur, DUR_MIN, DUR_MAX])
			if s.peak_db > PEAK_MAX_DB:
				fail.append("%s：峰值 %.2f dB 已削波（上限 %.1f）" % [sid, s.peak_db, PEAK_MAX_DB])
			if s.wrms_db < SILENT_DB:
				fail.append("%s：窗口 RMS %.1f dB，素材等于静音" % [sid, s.wrms_db])
			peaks.append(s.peak_db)
			rms.append(s.wrms_db)
			dur_min = minf(dur_min, s.dur)
			dur_max = maxf(dur_max, s.dur)
		peaks.sort()
		rms.sort()
		# 显式标注类型：Array[float] 的下标访问静态分析会退化成 Variant，
		# 用 := 推导会直接报 "Cannot infer the type"
		var pk: float = float(peaks[peaks.size() / 2])
		var wr: float = float(rms[rms.size() / 2])
		var d_pk: float = pk - float(ss.peak_db)
		var d_wr: float = wr - float(ss.wrms_db)
		# 校准建议：峰值对齐与 RMS 对齐的中点 —— 让两个口径的偏差各让一半
		var suggest: float = ((float(ss.peak_db) - pk) + (float(ss.wrms_db) - wr)) * 0.5
		if absf(d_pk) > TOL_PEAK_DB or d_wr > TOL_RMS_HI or d_wr < TOL_RMS_LO:
			fail.append("%s：与合成音色偏离过大（峰值 %+.1f dB，容差 ±%.1f；窗口 RMS %+.1f dB，容差 %+.1f~%+.1f）→ 建议增益 %+.1f dB" % [
				sid, d_pk, TOL_PEAK_DB, d_wr, TOL_RMS_LO, TOL_RMS_HI, suggest])
		rows.append({
			"id": sid, "n": arr.size(), "dur": "%.3f~%.3f" % [dur_min, dur_max],
			"pk": pk, "wr": wr, "spk": ss.peak_db, "swr": ss.wrms_db,
			"dpk": d_pk, "dwr": d_wr, "sug": suggest,
		})

	print("[录音素材自检] 规格与响度对照（录音素材 vs 合成音色）：")
	print("      %-14s %5s %13s %9s %9s %9s %9s %9s %8s" % [
		"动作", "变体", "时长(s)", "峰值", "窗口RMS", "合成峰值", "合成RMS", "Δ峰值", "ΔRMS"])
	for r in rows:
		print("      %-14s %5d %13s %9.2f %9.1f %9.2f %9.1f %+9.1f %+8.1f" % [
			r.id, r.n, r.dur, r.pk, r.wr, r.spk, r.swr, r.dpk, r.dwr])

	# 只在**真的越界**时给建议：两条真实录音的脚步是有意做成"峰值贴齐、平均能量偏低"的，
	# 那种情况下每跑一次都提示"再加 2 dB"只会变成噪音。
	var off: Array = []
	for r in rows:
		if absf(float(r.dpk)) > TOL_PEAK_DB or float(r.dwr) > TOL_RMS_HI or float(r.dwr) < TOL_RMS_LO:
			off.append("%s=%+.1f" % [r.id, float(r.sug)])
	if not off.is_empty():
		print("[录音素材自检] 校准建议（填进 build_foley.ps1 的 $match 表后重建）：")
		print("      " + ", ".join(off))

## 游戏真正走的那条路：Sfx.setup() 建（或读缓存）音色库时，会把录音变体挂到音色条目上。
## 只查 SfxFoley 是不够的 —— 素材齐全、但 _attach_foley 没跑（或被缓存路径漏掉）时，
## 前面所有断言都会通过，而游戏里仍然在放合成音色。
func _check_runtime(fail: Array[String]) -> void:
	var host := Node.new()
	host.name = "SfxFoleyCheckHost"
	root.add_child(host)
	var t0 := Time.get_ticks_msec()
	await Sfx.setup(host)
	var ms := Time.get_ticks_msec() - t0
	if not Sfx.cfg().enabled:
		# 关音频时不建库也不播放，这条路径无从判定：明确报 SKIP，而不是假装通过。
		print("[录音素材自检] SKIP 运行时挂载：AudioConfig.enabled = false（音效已关闭）")
		host.free()
		return
	if not Sfx.foley_ready():
		fail.append("Sfx 建库后 SfxFoley 仍未就绪（素材层没被播放层拉起来）")
	var hung := 0
	for id in EXPECT.keys():
		var sid := String(id)
		var n := Sfx.entry_foley_count(sid)
		if n < int(EXPECT[sid]):
			fail.append("%s：音色条目上只挂了 %d 个录音变体（期望 ≥ %d）—— 该动作实际仍在播合成音色" % [
				sid, n, int(EXPECT[sid])])
		else:
			hung += n
	print("[录音素材自检] 运行时挂载：音色库 %d 个条目 / %d 个录音变体已挂上 / 建库 %d ms" % [
		Sfx.bank_size(), hung, ms])
	host.free()

## 峰值 dB 与"最大 10ms 窗口 RMS" dB —— 后者比整体 RMS 更贴近听感上的"有多响"，
## 对脚步 / 打击这类短促素材尤其如此（整体 RMS 会被尾巴的静音稀释）。
func _stats(s: AudioStreamWAV) -> Dictionary:
	var d: PackedByteArray = s.data
	var ch := 2 if s.stereo else 1
	var frames := int(d.size() / (2 * ch))
	var peak := 0.0
	for i in frames * ch:
		var a := absf(float(d.decode_s16(i * 2)) / 32768.0)
		if a > peak:
			peak = a
	var rate := maxi(1, s.mix_rate)
	var w := maxi(1, int(round(float(rate) * 0.01)))
	var best := 0.0
	var f := 0
	while f + w <= frames:
		var sum := 0.0
		for i in w:
			var v := float(d.decode_s16((f + i) * ch * 2)) / 32768.0
			sum += v * v
		var r := sqrt(sum / float(w))
		if r > best:
			best = r
		f += w
	return {
		"dur": float(frames) / float(rate),
		"peak_db": linear_to_db(maxf(peak, 1e-7)),
		"wrms_db": linear_to_db(maxf(best, 1e-7)),
	}
