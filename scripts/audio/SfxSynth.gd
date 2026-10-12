## =============================================================================
##  SfxSynth —— 程序化音效合成器（工程保持"零外部音频资源"）
##
##  所有音效都在运行时用「振荡器 + 噪声 + 包络 + 滤波器」算出 PCM，
##  再封装成 AudioStreamWAV 交给 Sfx.gd 播放。没有任何 .wav / .ogg 文件。
##
##  四种基础配方（每个音效都是它们的叠加）：
##   · 打击声  = 宽带噪声瞬态（冲击）+ 下滑低频正弦（身体）+ 少量非谐泛音（金属味）
##   · 打铁声  = 一组非谐金属泛音 + 成对失谐产生的拍频 + 极短起振噪声 + 铁砧低频
##   · 挥砍/闪避 = 噪声过带通，中心频率随时间从高扫到低（或反过来 = 吸入感）
##   · 脚步/马蹄 = 十几毫秒噪声 + 低频"咚" + 一点点空腔共振，两只脚音高不同
##
##  音高与音量的随机抖动由 Sfx.gd 负责（pitch_jitter），这里只产出"基准音色"。
## =============================================================================
class_name SfxSynth
extends RefCounted

const RATE := 22050            ## 采样率：足够覆盖金属泛音，合成又快（低多边形画风）
const NYQ := RATE * 0.5        ## 奈奎斯特频率
const TAB_N := 4096            ## 正弦查表长度（查表 + 线性插值，比 sin() 快得多）

const F_LP := 0                ## _biquad 模式：低通
const F_HP := 1                ## _biquad 模式：高通
const F_BP := 2                ## _biquad 模式：带通

## id -> [分类, 基准音量 dB, 同音最短间隔（秒）, 基准音高]
## 分类用于叠加 AudioConfig 里的分类音量：combat / parry / move / voice / ui
const SPECS := {
	# ---------------- 打击 ----------------
	"hit_light":     ["combat", -1.0, 0.020, 1.00],   ## 玩家剑命中
	"hit_heavy":     ["combat", -0.5, 0.020, 1.00],   ## 重击 / Boss 命中玩家
	"hit_crit":      ["combat",  0.5, 0.020, 1.00],   ## 会心 / 反击斩
	"proj_impact":   ["combat", -3.0, 0.030, 1.00],   ## 投射物命中
	# ---------------- 弹反（打铁声）----------------
	"parry":         ["parry",   0.0, 0.050, 1.00],   ## 弹反成功：铁砧 + 非谐泛音
	"parry_reflect": ["parry",   0.0, 0.050, 1.15],   ## 弹返飞斧/投射物
	# ---------------- 闪避 ----------------
	"dodge":         ["move",    0.0, 0.050, 1.00],   ## 闪避：布料破风
	"perfect_dodge": ["combat",  1.0, 0.150, 1.00],   ## 完美闪避：吸入 + 上行铃声
	# ---------------- 移动 ----------------
	"step_a":        ["move",   -1.0, 0.090, 1.00],   ## 跑步脚步（左脚）
	"step_b":        ["move",   -1.0, 0.090, 1.00],   ## 跑步脚步（右脚，音高略低）
	"step_heavy":    ["move",   -2.0, 0.140, 1.00],   ## Boss 的沉重脚步
	"jump":          ["move",   -2.0, 0.080, 1.00],   ## 起跳
	"land":          ["move",   -2.0, 0.080, 1.00],   ## 落地
	"hoof_a":        ["move",   -1.5, 0.055, 1.00],   ## 大地图马蹄（前蹄）
	"hoof_b":        ["move",   -1.5, 0.055, 1.00],   ## 大地图马蹄（后蹄）
	# ---------------- 人声 / 战斗反馈 ----------------
	"hurt":          ["voice",  -1.0, 0.050, 1.00],   ## 玩家受击闷哼
	"roar":          ["voice",  -3.0, 0.400, 1.00],   ## 二阶段怒吼
	"poise_break":   ["combat",  1.0, 0.250, 1.00],   ## 破防
	"sword_wave":    ["combat", -1.5, 0.040, 1.00],   ## 剑气 / 飞斧出手
	"charge_full":   ["combat",  0.0, 0.250, 1.00],   ## 蓄力蓄满
	"warn_parry":    ["ui",     -5.0, 0.120, 1.00],   ## 出招预警：可弹反（清脆）
	"warn_danger":   ["ui",     -5.0, 0.120, 1.00],   ## 出招预警：不可弹反（低沉）
	# ---------------- 大地图 / UI ----------------
	"encounter":     ["ui",      0.0, 0.200, 1.00],   ## 遭遇对话框弹出
	"order":         ["ui",     -2.0, 0.400, 1.00],   ## 下达行军命令（号角）
	"battle_start":  ["ui",      2.0, 0.500, 1.00],   ## 进入 Boss 战
	"result_win":    ["ui",     -1.0, 0.500, 1.00],   ## 胜利
	"result_lose":   ["ui",     -3.0, 0.500, 1.00],   ## 战败
	"ui_back":       ["ui",     -1.0, 0.300, 1.00],   ## 撤退 / 返回大地图
}

## 正弦查表（静态初始化一次）
static var _tab: PackedFloat32Array = _make_tab()

static func _make_tab() -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(TAB_N)
	for i in TAB_N:
		a[i] = sin(TAU * float(i) / float(TAB_N))
	return a

## 相位（单位：周期，0..1）查表求正弦，比 sin() 快 2~4 倍
static func _sin(p: float) -> float:
	var x: float = p - floor(p)
	var f: float = x * float(TAB_N)
	var i := int(f)
	var fr := f - float(i)
	var a := _tab[i & (TAB_N - 1)]
	var b := _tab[(i + 1) & (TAB_N - 1)]
	return a + (b - a) * fr

# =============================================================== 通用工具
static func ids() -> Array:
	var a: Array = SPECS.keys()
	a.sort()
	return a

static func meta(id: String) -> Array:
	return SPECS.get(id, ["combat", 0.0, 0.02, 1.0])

static func _samples(sec: float) -> int:
	return maxi(2, int(round(sec * float(RATE))))

static func _blank(sec: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(_samples(sec))
	a.fill(0.0)
	return a

## 起音/衰减包络：attack 秒线性起音，之后按 exp(-(t/tau)^curve) 衰减
static func _env(t: float, attack: float, tau: float, curve := 1.0) -> float:
	var a := 1.0
	if attack > 0.0 and t < attack:
		a = t / attack
	var x := maxf(0.0, t) / maxf(0.0005, tau)
	return a * exp(-pow(x, curve))

static func _noise_env(rng: RandomNumberGenerator, sec: float, attack: float, tau: float, curve := 1.0) -> PackedFloat32Array:
	var n := _samples(sec)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = rng.randf_range(-1.0, 1.0) * _env(float(i) / float(RATE), attack, tau, curve)
	return out

## 扫频正弦：f0 → f1（指数插值，听感更接近真实的音高下滑）
static func _tone(sec: float, f0: float, f1: float, attack: float, tau: float, curve := 1.0, harm := 0.0) -> PackedFloat32Array:
	var n := _samples(sec)
	var out := PackedFloat32Array()
	out.resize(n)
	var p := 0.0
	var gliss := absf(f1 - f0) > 0.01
	# 增量式扫频：每采样乘一个固定比值，避免每采样一次 pow()
	var r := 1.0
	if gliss:
		r = pow(maxf(0.0001, f1) / maxf(0.0001, f0), 1.0 / float(maxi(1, n - 1)))
	var f := f0
	for i in n:
		p += f / float(RATE)
		var v := _sin(p)
		if harm > 0.0:
			v += harm * _sin(p * 2.0)
		out[i] = v * _env(float(i) / float(RATE), attack, tau, curve)
		if gliss:
			f *= r
	return out

## 非谐金属泛音：每个分音由一对轻微失谐的正弦叠加 → 产生"打铁"特有的拍频嗡鸣
static func _metal(sec: float, base: float, ratios: Array, amps: Array, taus: Array, detune := 0.0035) -> PackedFloat32Array:
	var out := _blank(sec)
	var n := out.size()
	for k in ratios.size():
		var f: float = base * float(ratios[k])
		if f >= NYQ * 0.97:
			continue
		var amp := float(amps[k])
		var tau := maxf(0.004, float(taus[k]))
		var dec := exp(-1.0 / (tau * float(RATE)))
		for pair in [-1.0, 1.0]:
			var step: float = f * (1.0 + detune * float(pair)) / float(RATE)
			var p := 0.0
			var env := amp
			for i in n:
				out[i] += _sin(p) * env
				p += step
				env *= dec
	return out

## 铜管/号角音色：整数谐波叠加（幅度 1/n），可带轻微颤音
static func _brass(sec: float, base: float, attack: float, tau: float, harmonics := 6, vib := 0.0) -> PackedFloat32Array:
	var n := _samples(sec)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := PackedFloat32Array()
	ph.resize(harmonics)
	for i in n:
		var t := float(i) / float(RATE)
		var e := _env(t, attack, tau, 1.0)
		if e < 0.0004:
			continue
		var k := 1.0 + vib * _sin(t * 5.0)
		var v := 0.0
		for h in harmonics:
			var f := base * float(h + 1) * k
			ph[h] += f / float(RATE)
			v += _sin(ph[h]) / float(h + 1)
		out[i] = v * e
	return out

## 二阶 RBJ 双二阶滤波器（中心频率可从 f0 扫到 f1），比 SVF 稳、带真共振
static func _biquad(src: PackedFloat32Array, f0: float, f1: float, q: float, mode: int) -> PackedFloat32Array:
	var n := src.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var qq := maxf(0.05, q)
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	# 定频（大多数用途）：系数只算一次，快得多
	if absf(f1 - f0) <= 0.5:
		var c := _coef(clampf(f0, 20.0, NYQ * 0.97), qq, mode)
		var b0 := float(c[0])
		var b1 := float(c[1])
		var b2 := float(c[2])
		var a1 := float(c[3])
		var a2 := float(c[4])
		for i in n:
			var x := src[i]
			var y := b0 * x + b1 * x1 + b2 * x2 + a1 * y1 - a2 * y2
			x2 = x1
			x1 = x
			y2 = y1
			y1 = y
			out[i] = y
		return out
	# 扫频：系数逐采样更新
	var denom := float(maxi(1, n - 1))
	for i in n:
		var c2 := _coef(clampf(lerpf(f0, f1, float(i) / denom), 20.0, NYQ * 0.97), qq, mode)
		var b0b := float(c2[0])
		var b1b := float(c2[1])
		var b2b := float(c2[2])
		var x := src[i]
		var y := b0b * x + b1b * x1 + b2b * x2 + float(c2[3]) * y1 - float(c2[4]) * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		out[i] = y
	return out

## 返回已归一化的 [b0, b1, b2, a1, a2]
## 差分方程：y = b0*x + b1*x1 + b2*x2 + a1*y1 - a2*y2
static func _coef(fc: float, q: float, mode: int) -> Array:
	var w0 := TAU * fc / float(RATE)
	var cw := cos(w0)
	var sw := sin(w0)
	var alpha := sw / (2.0 * q)
	var a0 := 1.0 + alpha
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	match mode:
		F_HP:
			b0 = (1.0 + cw) * 0.5
			b1 = -(1.0 + cw)
			b2 = (1.0 + cw) * 0.5
		F_BP:
			b0 = alpha
			b1 = 0.0
			b2 = -alpha
		_:
			b0 = (1.0 - cw) * 0.5
			b1 = 1.0 - cw
			b2 = (1.0 - cw) * 0.5
	return [b0 / a0, b1 / a0, b2 / a0, (2.0 * cw) / a0, (1.0 - alpha) / a0]

static func _mix(dst: PackedFloat32Array, src: PackedFloat32Array, gain: float) -> void:
	var n := mini(dst.size(), src.size())
	for i in n:
		dst[i] += src[i] * gain

static func _mix_at(dst: PackedFloat32Array, src: PackedFloat32Array, gain: float, delay_sec: float) -> void:
	var d := int(round(delay_sec * float(RATE)))
	for i in src.size():
		var j := i + d
		if j >= dst.size():
			break
		dst[j] += src[i] * gain

## 软削波：给怒吼之类的音色加一点"过载"的脏感（不会真的削平）
static func _soft_clip(buf: PackedFloat32Array, drive: float) -> void:
	for i in buf.size():
		var v := buf[i] * drive
		buf[i] = v / (1.0 + absf(v))

## 归一化 + 首尾淡入淡出 + 转成 16bit PCM 的 AudioStreamWAV
static func _wav(s: PackedFloat32Array, norm := 0.92) -> AudioStreamWAV:
	var n := s.size()
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(s[i]))
	var g := norm / maxf(1e-6, peak)
	var fade := mini(n / 3, maxi(8, int(0.004 * float(RATE))))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var a := 1.0
		if i < fade:
			a = float(i) / float(fade)
		elif i >= n - fade:
			a = float(n - i) / float(fade)
		var v := clampf(s[i] * g * a, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(round(v * 32000.0)))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = bytes
	return st

# =============================================================== 各音效配方
static func _snd_hit_light(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := 0.26
	var out := _blank(sec)
	# 冲击瞬态：宽带噪声取高通（"啪"）
	_mix(out, _biquad(_noise_env(rng, sec, 0.0004, 0.012, 0.7), 900.0, 900.0, 0.7, F_HP), 0.75)
	# 身体：音高下滑的低频"咚"
	_mix(out, _tone(sec, 265.0, 118.0, 0.001, 0.075), 0.85)
	# 金属味：短促非谐泛音（砍在甲胄/兵器上）
	_mix(out, _metal(sec, 1730.0, [1.0, 1.44, 1.95], [0.16, 0.10, 0.06], [0.10, 0.07, 0.045], 0.004), 1.0)
	return out

static func _snd_hit_heavy(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := 0.42
	var out := _blank(sec)
	# 闷响瞬态（低通 → 像重物隔着甲胄砸进来）
	_mix(out, _biquad(_noise_env(rng, sec, 0.0006, 0.022, 0.8), 1500.0, 700.0, 0.8, F_LP), 0.8)
	# 低频主体 + 胸腔共鸣
	_mix(out, _tone(sec, 118.0, 48.0, 0.0015, 0.19), 1.0)
	_mix(out, _tone(sec, 62.0, 46.0, 0.003, 0.24), 0.5)
	# 甲片震颤
	_mix(out, _metal(sec, 980.0, [1.0, 1.55, 2.31], [0.13, 0.09, 0.05], [0.075, 0.05, 0.03], 0.006), 1.0)
	return out

static func _snd_hit_crit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := 0.46
	var out := _blank(sec)
	_mix(out, _biquad(_noise_env(rng, sec, 0.0004, 0.014, 0.7), 1200.0, 1200.0, 0.7, F_HP), 0.85)
	_mix(out, _tone(sec, 320.0, 140.0, 0.001, 0.10), 0.90)
	# 明亮的长金属鸣响 = "会心/反击斩"的听感标志
	_mix(out, _metal(sec, 2210.0, [1.0, 1.42, 2.0, 2.67], [0.22, 0.15, 0.10, 0.06], [0.30, 0.22, 0.15, 0.10], 0.003), 1.0)
	# 上扫的"锐"
	_mix(out, _tone(sec, 720.0, 2600.0, 0.004, 0.075), 0.22)
	return out

static func _snd_proj_impact(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := 0.32
	var out := _blank(sec)
	_mix(out, _biquad(_noise_env(rng, sec, 0.001, 0.16, 0.9), 3200.0, 700.0, 1.3, F_BP), 1.0)
	_mix(out, _tone(sec, 190.0, 88.0, 0.001, 0.11), 0.5)
	_mix(out, _metal(sec, 1420.0, [1.0, 1.7], [0.10, 0.06], [0.12, 0.08], 0.005), 1.0)
	return out

## 弹反的"打铁声"：铁砧低频 + 非谐泛音群（成对失谐 → 拍频嗡鸣）+ 起振噪声
static func _snd_parry(rng: RandomNumberGenerator, bright: float, tail: bool) -> PackedFloat32Array:
	var sec := 0.95 if tail else 0.85
	var out := _blank(sec)
	# 1) 锤击起振：只有几毫秒的宽带噪声
	_mix(out, _biquad(_noise_env(rng, sec, 0.0002, 0.005, 0.6), 2600.0, 2600.0, 0.6, F_HP), 0.90)
	# 2) 铁砧被砸中的低频"当"
	_mix(out, _tone(sec, 175.0 * bright, 92.0 * bright, 0.001, 0.06), 0.45)
	# 3) 金属泛音群（非谐比例 = 金属感；每对失谐 0.35% ≈ 数 Hz 拍频）
	_mix(out, _metal(sec, 523.25 * bright,
		[1.0, 2.35, 3.17, 4.62, 5.83, 7.41, 9.02, 11.30],
		[0.55, 0.42, 0.34, 0.26, 0.20, 0.15, 0.11, 0.08],
		[0.34, 0.27, 0.23, 0.19, 0.15, 0.12, 0.09, 0.07], 0.0035), 1.0)
	# 4) 弹返飞行物时额外的回旋风声
	if tail:
		_mix_at(out, _biquad(_noise_env(rng, 0.42, 0.03, 0.16, 1.0), 900.0, 3000.0, 1.1, F_BP), 0.35, 0.10)
	return out

static func _snd_dodge(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := 0.36
	var out := _blank(sec)
	# 破风：带通中心从 2400Hz 扫到 300Hz
	_mix(out, _biquad(_noise_env(rng, sec, 0.020, 0.085, 1.0), 2400.0, 300.0, 1.1, F_BP), 1.0)
	# 衣物低频层
	_mix(out, _biquad(_noise_env(rng, sec, 0.010, 0.12, 1.2), 520.0, 320.0, 0.9, F_LP), 0.45)
	_mix(out, _tone(sec, 420.0, 180.0, 0.010, 0.060), 0.10)
	return out

static func _snd_perfect_dodge(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := 0.95
	var out := _blank(sec)
	# 1) 反向上扫的"吸入感"（慢起音）
	_mix(out, _biquad(_noise_env(rng, 0.34, 0.10, 0.07, 1.0), 400.0, 2900.0, 1.2, F_BP), 0.55)
	# 2) 上行小铃声（三音错开起音 = 琶音）
	_mix_at(out, _metal(0.62, 1046.5, [1.0, 1.5], [0.40, 0.18], [0.30, 0.20], 0.002), 1.0, 0.000)
	_mix_at(out, _metal(0.58, 1568.0, [1.0, 1.5], [0.30, 0.14], [0.26, 0.18], 0.002), 1.0, 0.045)
	_mix_at(out, _metal(0.52, 2093.0, [1.0, 1.5], [0.24, 0.12], [0.22, 0.15], 0.002), 1.0, 0.090)
	# 3) 时间减速的下坠音（配合 slow_motion）
	_mix(out, _tone(sec, 1500.0, 420.0, 0.020, 0.34, 1.4), 0.16)
	# 4) 低频"心跳"
	_mix(out, _tone(0.30, 74.0, 52.0, 0.004, 0.10), 0.35)
	return out

static func _snd_step(rng: RandomNumberGenerator, f: float, tau: float) -> PackedFloat32Array:
	var sec := 0.16
	var out := _blank(sec)
	# 鞋底/地面摩擦：极短噪声（低通）
	_mix(out, _biquad(_noise_env(rng, sec, 0.0006, 0.014 * tau, 0.8), 2000.0, 900.0, 0.7, F_LP), 0.70)
	# 体重落地的低频"咚"
	_mix(out, _tone(sec, 150.0 * f, 78.0 * f, 0.001, 0.045 * tau), 0.80)
	# 一点点空腔共振（听起来像踩在土地上）
	_mix(out, _biquad(_noise_env(rng, sec, 0.001, 0.05 * tau, 1.0), 470.0 * f, 470.0 * f, 2.4, F_BP), 0.35)
	return out

static func _snd_step_heavy(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := 0.34
	var out := _blank(sec)
	_mix(out, _biquad(_noise_env(rng, sec, 0.001, 0.05, 0.85), 1100.0, 500.0, 0.8, F_LP), 0.65)
	_mix(out, _tone(sec, 92.0, 44.0, 0.002, 0.13), 1.0)
	_mix(out, _metal(sec, 560.0, [1.0, 1.63], [0.12, 0.07], [0.07, 0.045], 0.006), 1.0)
	return out

static func _snd_jump(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := 0.24
	var out := _blank(sec)
	_mix(out, _biquad(_noise_env(rng, sec, 0.012, 0.075, 1.0), 800.0, 2400.0, 1.0, F_BP), 0.75)
	_mix(out, _biquad(_noise_env(rng, sec, 0.005, 0.09, 1.2), 900.0, 600.0, 0.8, F_LP), 0.35)
	return out

static func _snd_land(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := 0.34
	var out := _blank(sec)
	_mix(out, _biquad(_noise_env(rng, sec, 0.001, 0.06, 0.9), 900.0, 420.0, 0.8, F_LP), 0.80)
	_mix(out, _tone(sec, 128.0, 54.0, 0.0015, 0.105), 1.0)
	_mix(out, _biquad(_noise_env(rng, sec, 0.020, 0.13, 1.2), 1500.0, 900.0, 1.0, F_BP), 0.22)
	return out

static func _snd_hoof(rng: RandomNumberGenerator, f: float, tau: float) -> PackedFloat32Array:
	var sec := 0.20
	var out := _blank(sec)
	# 马蹄铁敲地面的"嗒"
	_mix(out, _biquad(_noise_env(rng, sec, 0.0005, 0.018 * tau, 0.8), 2600.0, 1200.0, 0.7, F_LP), 0.80)
	# 空心木质共振
	_mix(out, _biquad(_noise_env(rng, sec, 0.001, 0.045 * tau, 1.0), 380.0 * f, 380.0 * f, 2.6, F_BP), 0.55)
	_mix(out, _tone(sec, 195.0 * f, 110.0 * f, 0.001, 0.040 * tau), 0.70)
	return out

static func _snd_hurt(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := 0.34
	var out := _blank(sec)
	# 用噪声当"声带源"，再挂三个共振峰 → 像一声闷哼
	var src := _noise_env(rng, sec, 0.004, 0.115, 1.15)
	_mix(out, _biquad(src, 260.0, 240.0, 3.0, F_BP), 0.70)
	_mix(out, _biquad(src, 520.0, 470.0, 4.0, F_BP), 1.00)
	_mix(out, _biquad(src, 1180.0, 1020.0, 5.0, F_BP), 0.55)
	# 音高下滑的基频
	_mix(out, _tone(sec, 165.0, 95.0, 0.003, 0.14), 0.30)
	return out

static func _snd_roar(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := 1.05
	var out := _blank(sec)
	# 低频多谐波（锯齿味）+ 颤音 = 兽吼的基音
	_mix(out, _brass(sec, 72.0, 0.05, 0.50, 12, 0.02), 1.0)
	# 噪声嘶吼层
	var nz := _biquad(_noise_env(rng, sec, 0.03, 0.42, 1.0), 320.0, 900.0, 1.4, F_BP)
	_mix(out, nz, 0.55)
	_mix(out, _biquad(nz, 180.0, 300.0, 1.0, F_LP), 0.35)
	_soft_clip(out, 1.6)
	return out

static func _snd_poise_break(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := 0.95
	var out := _blank(sec)
	# 碎裂高频
	_mix(out, _biquad(_noise_env(rng, sec, 0.0006, 0.22, 1.1), 3200.0, 2400.0, 0.8, F_HP), 0.70)
	# 金属崩坏（长鸣 + 下坠）
	_mix(out, _metal(0.80, 1560.0, [1.0, 1.51], [0.28, 0.16], [0.42, 0.30], 0.004), 1.0)
	_mix(out, _tone(0.90, 900.0, 220.0, 0.004, 0.32), 0.25)
	# 低频轰鸣
	_mix(out, _tone(sec, 78.0, 52.0, 0.010, 0.50), 0.80)
	return out

static func _snd_sword_wave(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := 0.42
	var out := _blank(sec)
	_mix(out, _biquad(_noise_env(rng, sec, 0.025, 0.115, 1.0), 620.0, 3100.0, 1.15, F_BP), 1.0)
	_mix(out, _tone(sec, 900.0, 2400.0, 0.020, 0.080), 0.14)
	_mix(out, _biquad(_noise_env(rng, sec, 0.010, 0.14, 1.3), 380.0, 900.0, 0.9, F_LP), 0.30)
	return out

static func _snd_charge_full(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := 0.80
	var out := _blank(sec)
	_mix(out, _metal(sec, 1318.5, [1.0, 1.5, 2.0, 3.0], [0.35, 0.22, 0.15, 0.08], [0.34, 0.26, 0.20, 0.13], 0.002), 1.0)
	_mix(out, _biquad(_noise_env(rng, sec, 0.020, 0.20, 1.0), 2000.0, 5000.0, 1.0, F_BP), 0.22)
	return out

## 出招预警：可弹反 = 清脆"叮"；不可弹反 = 低频嗡鸣（两音差频 4Hz 的拍）
static func _snd_warn(rng: RandomNumberGenerator, danger: bool) -> PackedFloat32Array:
	if danger:
		var sec := 0.50
		var out := _blank(sec)
		_mix(out, _tone(sec, 117.0, 112.0, 0.030, 0.28), 1.0)
		_mix(out, _tone(sec, 121.0, 116.0, 0.030, 0.28), 1.0)
		_mix(out, _tone(sec, 58.0, 54.0, 0.030, 0.30), 0.50)
		_mix(out, _biquad(_noise_env(rng, sec, 0.03, 0.20, 1.0), 240.0, 240.0, 1.2, F_BP), 0.15)
		return out
	var sec2 := 0.34
	var out2 := _blank(sec2)
	_mix(out2, _biquad(_noise_env(rng, sec2, 0.0004, 0.006, 0.7), 3000.0, 3000.0, 0.7, F_HP), 0.50)
	_mix(out2, _metal(sec2, 2489.0, [1.0, 1.48, 2.11], [0.35, 0.22, 0.12], [0.16, 0.12, 0.08], 0.003), 1.0)
	return out2

## 短促提示音（两三个音，谐波音色）
static func _snd_blip(freqs: Array, dur: float, gap: float, bright := 0.35) -> PackedFloat32Array:
	var sec := float(freqs.size()) * (dur + gap) + 0.06
	var out := _blank(sec)
	for i in freqs.size():
		var f := float(freqs[i])
		var tone := _metal(dur + 0.14, f, [1.0, 2.0, 3.0], [1.0, bright, bright * 0.4],
			[dur * 0.55, dur * 0.35, dur * 0.22], 0.001)
		_mix_at(out, tone, 0.85, float(i) * (dur + gap))
	return out

## 号角（基音 + 五度叠音）
static func _snd_horn(sec: float, base: float, attack: float, tau: float) -> PackedFloat32Array:
	var out := _brass(sec, base, attack, tau, 8, 0.004)
	_mix(out, _brass(sec, base * 1.5, attack * 1.2, tau * 0.9, 6, 0.004), 0.5)
	return out

static func _snd_battle_start(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := 1.15
	var out := _blank(sec)
	# 战鼓/踏地：开场一记低频冲击
	_mix(out, _tone(0.5, 96.0, 46.0, 0.002, 0.16), 0.85)
	_mix(out, _biquad(_noise_env(rng, 0.4, 0.001, 0.05, 0.9), 1200.0, 400.0, 0.8, F_LP), 0.35)
	# 号角：低音 + 五度
	_mix_at(out, _snd_horn(0.95, 147.0, 0.030, 0.55), 1.0, 0.06)
	return out

static func _snd_result_win(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _snd_blip([523.25, 659.25, 783.99], 0.18, 0.10, 0.45)
	_mix(out, _brass(0.5, 261.63, 0.02, 0.30, 4, 0.0), 0.35)
	return out

static func _snd_result_lose(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _snd_blip([392.00, 311.13, 233.08], 0.34, 0.16, 0.30)
	# 暗色低通 + 一层叹息般的低频
	out = _biquad(out, 1600.0, 800.0, 0.8, F_LP)
	_mix(out, _tone(1.2, 98.0, 74.0, 0.06, 0.45), 0.30)
	return out

# =============================================================== 构建入口
## 合成单个音效（每个音效独立随机流，保证音色可复现）
static func build(id: String, rng: RandomNumberGenerator) -> AudioStreamWAV:
	match id:
		"hit_light": return _wav(_snd_hit_light(rng))
		"hit_heavy": return _wav(_snd_hit_heavy(rng))
		"hit_crit": return _wav(_snd_hit_crit(rng))
		"proj_impact": return _wav(_snd_proj_impact(rng))
		"parry": return _wav(_snd_parry(rng, 1.0, false))
		"parry_reflect": return _wav(_snd_parry(rng, 1.18, true))
		"dodge": return _wav(_snd_dodge(rng))
		"perfect_dodge": return _wav(_snd_perfect_dodge(rng))
		"step_a": return _wav(_snd_step(rng, 1.00, 1.00), 0.80)
		"step_b": return _wav(_snd_step(rng, 0.88, 1.18), 0.80)
		"step_heavy": return _wav(_snd_step_heavy(rng))
		"jump": return _wav(_snd_jump(rng))
		"land": return _wav(_snd_land(rng))
		"hoof_a": return _wav(_snd_hoof(rng, 1.00, 1.00), 0.85)
		"hoof_b": return _wav(_snd_hoof(rng, 0.86, 1.15), 0.85)
		"hurt": return _wav(_snd_hurt(rng))
		"roar": return _wav(_snd_roar(rng))
		"poise_break": return _wav(_snd_poise_break(rng))
		"sword_wave": return _wav(_snd_sword_wave(rng))
		"charge_full": return _wav(_snd_charge_full(rng))
		"warn_parry": return _wav(_snd_warn(rng, false), 0.75)
		"warn_danger": return _wav(_snd_warn(rng, true), 0.75)
		"encounter": return _wav(_snd_blip([783.99, 587.33], 0.14, 0.09, 0.30), 0.85)
		"order": return _wav(_snd_horn(0.55, 196.0, 0.050, 0.22), 0.85)
		"battle_start": return _wav(_snd_battle_start(rng))
		"result_win": return _wav(_snd_result_win(rng))
		"result_lose": return _wav(_snd_result_lose(rng))
		"ui_back": return _wav(_snd_blip([659.25, 440.00], 0.12, 0.08, 0.22), 0.75)
	return _wav(_blank(0.05))
