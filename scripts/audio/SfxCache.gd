## =============================================================================
##  SfxCache —— 把合成好的 28 个音色 PCM 缓存到 user://（第五轮 5c）
##
##  为什么值得缓存：全库 34.7 万采样，冷启动合成 ≈ 1.1 秒（见 ROADMAP §11.2），
##  每次开游戏都要花一遍；命中缓存后只剩读盘 + 建 AudioStreamWAV（几十毫秒）。
##
##  三条硬性约束（都是权衡过的，不是随手写的）：
##    1) **整体命中 / 整体丢弃**，不做「单曲补合成」。噪声类音色共用同一条 RNG 流
##       （SfxSynth.build(id, rng) 按 ids() 顺序消耗随机数），跳过任何一个音色都会
##       让后面所有音色的噪声变样 —— 所以「只补一个」等于悄悄改了音色。
##    2) 缓存坏了是**正常情况**（断电、写盘中断、人工改过）：校验不过就静默丢弃、走冷启动。
##       绝不用 push_error、绝不打 ERROR 行 —— 门禁对 ERROR 零容忍，而且坏缓存不该惊动玩家。
##    3) 键必须覆盖「合成算法的全部输入」：RATE / TAB_N / SPECS / ids / 缓存格式版本 /
##       **SfxSynth.gd 自身的文件字节指纹**。最后一条让「改了合成代码但忘了 bump FORMAT」
##       也能自动失效；导出后若读不到源码，退化成只靠 FORMAT（见 _script_stamp）。
##
##  存放位置：user://sfx_cache/bank.bin + bank.json（**不进仓库**，每台机器自己生成）。
##  调试用：SfxCache.enabled = false 关掉缓存；SfxCache.clear() 清掉重来。
## =============================================================================
class_name SfxCache
extends RefCounted

const DIR := "user://sfx_cache"
const BLOB := "bank.bin"
const META := "bank.json"
const MAGIC := 0x43584653          ## "SFXC"（小端读出来是 S F X C 反过来，仅作魔数）
## 缓存格式版本。**改了任何影响输出的合成代码都要 +1**（例如 _wav 的归一化、_biquad 的算式、
## 某个 _snd_* 的配方）。正常情况下 _script_stamp() 会替你发现，但它只是第二道保险。
const FORMAT := 1

static var enabled := true
static var _stats: Dictionary = {
	"asks": 0, "hits": 0, "misses": 0, "last": "none", "reason": "",
	"load_ms": 0, "save_ms": 0, "bytes": 0,
}

# =============================================================== 键

## 缓存键（16 位十六进制）。ids() 顺序也在键里：合成顺序变了，噪声流就变了。
static func key() -> String:
	return key_of(FORMAT, SfxSynth.RATE, SfxSynth.TAB_N, str(SfxSynth.SPECS), _script_stamp())

## 参数化版本（自检用：验证"任何一项变了键就变"）
static func key_of(fmt: int, rate: int, tab: int, specs: String, stamp: String) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(("fmt=%d|rate=%d|tab=%d|ids=%s|stamp=%s|specs=%s" % [
		fmt, rate, tab, ",".join(SfxSynth.ids()), stamp, specs]).to_utf8_buffer())
	return c.finish().hex_encode().substr(0, 16)

## SfxSynth.gd 的文件字节指纹 —— 第二道保险：改合成代码而忘 bump FORMAT 时自动失效。
## 注释/BOM 改动也会让它变（代价只是重新合成一次，换来的是"绝不会用错老缓存"）。
static func _script_stamp() -> String:
	const P := "res://scripts/audio/SfxSynth.gd"
	if FileAccess.file_exists(P):
		var b := FileAccess.get_file_as_bytes(P)
		if not b.is_empty():
			return sha256(b).substr(0, 16)
	return "no-source"      ## 导出后源码被剥离时的退化路径：只靠 FORMAT + SPECS

## HashingContext.update() 收到**空数组**时会打 `ERROR: Condition "len == 0"` 并返回 FAILED，
## 而门禁对 ERROR 零容忍 —— 所以所有喂哈希的地方都走这里，空数组直接跳过（哈希值不变）。
static func _upd(c: HashingContext, b: PackedByteArray) -> void:
	if not b.is_empty():
		c.update(b)

static func sha256(data: PackedByteArray) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	_upd(c, data)
	return c.finish().hex_encode()

## 音色库 PCM 总指纹：与 tools/sfx_tool.gd 的 --hash 共用同一套配方
## （RATE + 每个音色的 [id 长度, PCM 字节数, id, PCM]），这样两边算出来的值可以直接对。
static func total_of(datas: Dictionary) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	_upd(c, str(SfxSynth.RATE).to_utf8_buffer())
	for id in SfxSynth.ids():
		var sid := String(id)
		var d: PackedByteArray = datas.get(sid, PackedByteArray())
		var lb := PackedByteArray()
		lb.resize(8)
		lb.encode_u32(0, sid.length())
		lb.encode_u32(4, d.size())
		_upd(c, lb)
		_upd(c, sid.to_utf8_buffer())
		_upd(c, d)
	return c.finish().hex_encode()

# =============================================================== 统计

static func stats() -> Dictionary:
	return _stats.duplicate()

static func reset_stats() -> void:
	_stats = {
		"asks": 0, "hits": 0, "misses": 0, "last": "none", "reason": "",
		"load_ms": 0, "save_ms": 0, "bytes": 0,
	}

# =============================================================== 读

## 命中返回 **{id: AudioStreamWAV}**（裸流，不是 Sfx._bank 的条目结构 ——
## 分类/音量/间隔那些元数据来自 SPECS，本来就不该进缓存）；
## 任何异常（缺文件 / 键不符 / 校验和不符 / 被截断）都返回空字典，调用方直接走冷启动。
static func load_bank() -> Dictionary:
	_stats["asks"] = int(_stats["asks"]) + 1
	if not enabled:
		_stats["last"] = "off"
		return {}
	var t0 := Time.get_ticks_msec()
	var meta := _read_json(META)
	if meta.is_empty():
		return _miss("元数据缺失或不是合法 JSON")
	if String(meta.get("key", "")) != key():
		return _miss("键不匹配（合成算法或采样率变了）")
	var count := int(meta.get("count", -1))
	if count != SfxSynth.ids().size():
		return _miss("音色个数不符")
	var blob := _read_bytes(BLOB)
	if blob.is_empty():
		return _miss("PCM 文件缺失")
	if sha256(blob) != String(meta.get("total", "")):
		return _miss("PCM 校验和不符（缓存被改坏）")
	# ---- 解包（所有长度都先验界，绝不越界读；decode_* 越界会 ERR_PRINT）----
	var hashes: Dictionary = meta.get("ids", {})
	var p := 0
	if blob.size() < 12 or blob.decode_u32(0) != MAGIC:
		return _miss("魔数不符")
	if blob.decode_u32(4) != FORMAT:
		return _miss("格式版本不符")
	p = 8
	var n := int(blob.decode_u32(p))
	p += 4
	if n != count:
		return _miss("文件头音色个数不符")
	var out := {}
	var samples := 0
	for i in n:
		if p + 4 > blob.size():
			return _miss("文件被截断（读名字长度）")
		var nl := int(blob.decode_u32(p))
		p += 4
		if p + nl + 4 > blob.size():
			return _miss("文件被截断（读名字）")
		var name := blob.slice(p, p + nl).get_string_from_utf8()
		p += nl
		var dl := int(blob.decode_u32(p))
		p += 4
		if dl <= 0 or p + dl > blob.size():
			return _miss("文件被截断（%s 的 PCM）" % name)
		var data := blob.slice(p, p + dl)
		p += dl
		if sha256(data) != String(hashes.get(name, "")):
			return _miss("音色 %s 的 PCM 与元数据不符" % name)
		out[name] = _make_stream(data)
		samples += dl / 2
	if out.size() != count:
		return _miss("解出来的音色个数不符（有重名？）")
	_stats["hits"] = int(_stats["hits"]) + 1
	_stats["last"] = "cache"
	_stats["reason"] = ""
	_stats["load_ms"] = Time.get_ticks_msec() - t0
	_stats["bytes"] = blob.size()
	_stats["samples"] = samples
	return out

static func _miss(reason: String) -> Dictionary:
	_stats["misses"] = int(_stats["misses"]) + 1
	_stats["last"] = "miss"
	_stats["reason"] = reason
	return {}

# =============================================================== 写

## bank: {id: {"stream": AudioStreamWAV}}（就是 Sfx._bank 的结构）。
## 只要有任何一个音色缺 stream 就整体不落盘 —— 半个缓存比没有更危险。
static func save_bank(bank: Dictionary) -> bool:
	if not enabled:
		return false
	var t0 := Time.get_ticks_msec()
	var ids := SfxSynth.ids()
	var datas := {}
	for id in ids:
		var sid := String(id)
		var e: Dictionary = bank.get(sid, {})
		var st: AudioStreamWAV = e.get("stream", null)
		if st == null or st.data.is_empty():
			_stats["reason"] = "音色库不完整（缺 %s），不落盘" % sid
			return false
		datas[sid] = st.data
	var blob := PackedByteArray()
	var head := PackedByteArray()
	head.resize(12)
	head.encode_u32(0, MAGIC)
	head.encode_u32(4, FORMAT)
	head.encode_u32(8, ids.size())
	blob.append_array(head)
	var hashes := {}
	var samples := 0
	for id in ids:
		var sid := String(id)
		var d: PackedByteArray = datas[sid]
		hashes[sid] = sha256(d)
		samples += d.size() / 2
		var nl := sid.to_utf8_buffer()
		var lb := PackedByteArray()
		lb.resize(4)
		lb.encode_u32(0, nl.size())
		var db := PackedByteArray()
		db.resize(4)
		db.encode_u32(0, d.size())
		blob.append_array(lb)
		blob.append_array(nl)
		blob.append_array(db)
		blob.append_array(d)
	var doc := {
		"note": "音色 PCM 缓存（SfxCache 生成，删掉即重新合成；不进仓库）",
		"format": FORMAT,
		"key": key(),
		"rate": SfxSynth.RATE,
		"count": ids.size(),
		"samples": samples,
		"total": sha256(blob),
		"ids": hashes,
	}
	var ok_blob := _write_atomic(BLOB, blob)
	var ok_meta := ok_blob and _write_atomic(META, (JSON.stringify(doc, "  ") + "\n").to_utf8_buffer())
	_stats["save_ms"] = Time.get_ticks_msec() - t0
	_stats["bytes"] = blob.size()
	_stats["last"] = "save" if ok_meta else "save-failed"
	_stats["reason"] = "" if ok_meta else "写盘失败"
	return ok_meta

## 清掉缓存文件（自检 / 调试用）
static func clear() -> void:
	for n in [BLOB, META, BLOB + ".tmp", META + ".tmp"]:
		var p := ProjectSettings.globalize_path(DIR + "/" + n)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

# =============================================================== 小工具

static func _make_stream(data: PackedByteArray) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SfxSynth.RATE
	s.stereo = false
	s.data = data
	return s

static func _read_bytes(name: String) -> PackedByteArray:
	var p := DIR + "/" + name
	if not FileAccess.file_exists(p):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(p)

static func _read_json(name: String) -> Dictionary:
	var p := DIR + "/" + name
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	# 用实例版 parse：JSON.parse_string 失败时会 ERR_PRINT，而坏缓存不该打 ERROR
	var j := JSON.new()
	if j.parse(txt) != OK:
		return {}
	return j.data if j.data is Dictionary else {}

## 先写 .tmp 再改名 —— 写一半被打断时，旧的两份文件还在，load_bank 自然会判为不匹配
static func _write_atomic(name: String, bytes: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var tmp := DIR + "/" + name + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	var dst := DIR + "/" + name
	if FileAccess.file_exists(dst):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dst))
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(dst)) == OK