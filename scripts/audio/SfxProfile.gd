## =============================================================================
##  SfxProfile —— 「音效调音台」配置层
##
##  给谁用：`tools/sfx_studio/`（网页调音台）。在浏览器里逐个试听 / 调音量 / 开关
##  每一条音效，点保存就落到 **`user://sfx_profile.json`**，游戏按这份配置发声 ——
##  「关闭」是真的不播（Sfx.play 直接丢弃），不是把音量拉到最小。
##
##  为什么单独一层、而不是往 AudioConfig 里塞 28 个 @export：
##   · AudioConfig 是**工程默认值**（作者调的基准，随代码走），这份配置是**当前这台机器
##     上的覆盖**（随存档目录走）。两者混在一起，就没法回答「这条音色本来该多响」和
##     「我这里把它调成了多少」这两个不同的问题。
##   · 覆盖是**稀疏**的：只记你真正动过的那几条。没动过的条目在 JSON 里根本不出现，
##     于是新增音色 / 改基准音量时，老配置不会把它按 0 dB 钉死。
##
##  三层音量（自检 tools/sfx_profile_check.gd 逐层验）：
##     最终 dB = master_db（Master 总线，见 AudioBus）
##             + 分类 dB（AudioConfig.combat_db … 这五档）
##             + 音色基准 dB（SfxSynth.SPECS 里每条的设计音量）
##             + 本层单条偏移（SfxProfile.sfx_db）
##  前两档 + 单条偏移都是"可覆盖项"：本层加载时把前两档**写回 AudioConfig**，
##  单条偏移留在本层（Sfx._final_db 里相加）。这样 AudioBus / Bgm 都不用改，
##  覆盖也天然稀疏。
##
##  十条保存记录（`records`）：
##   · 每次保存 = 一份**完整快照**（state）+ 时间 + 名字 + 与上一条的差异摘要；
##   · 只留最近 `MAX_RECORDS` = 10 条，第 11 条进来自动淘汰最旧的那条（明确取舍：
##     十条之外的"更早一步"没有存档价值，而无限增长会把 JSON 变成日志文件）；
##   · 回滚 = 把某条记录的 state 整份套回当前状态。因为每条都是完整快照而不是增量补丁，
##     所以可以来回滚、也可以在中间某条被淘汰之后照样回到任何一个还在的版本。
##
##  关掉这套覆盖：环境变量 `WARBAND_SFX_PROFILE=0`（tools/run_checks.ps1 就是这样跑的 ——
##  门禁必须验"工程默认"这条路径，不能让某台机器上的调音结果把它判红）。
## =============================================================================
class_name SfxProfile
extends RefCounted

const SCHEMA := "warband.sfx_profile"
const VERSION := 1
const MAX_RECORDS := 10
const ENV_OPT_OUT := "WARBAND_SFX_PROFILE"
const DEFAULT_PATH := "user://sfx_profile.json"

## 分类音量字段（键必须与 AudioConfig.category_db() 认的五个分类一致）
const CATEGORY_FIELDS := {
	"combat": "combat_db",
	"parry": "parry_db",
	"move": "move_db",
	"voice": "voice_db",
	"ui": "ui_db",
}
## 背景音乐：曲目 id -> AudioConfig 里的单曲偏移字段（bgm_db 本身走 Music 总线）
const BGM_FIELDS := {"map": "bgm_map_db", "battle": "bgm_battle_db"}

## 音量上下限（dB）。上限刻意收得紧：调音台不是放大器，+12 dB 已经能把 0.92 峰值的
## 音色推到削波，再往上只会烧掉整条混音，不是"更响"。
const MASTER_MIN := -60.0
const MASTER_MAX := 24.0
const CATEGORY_MIN := -40.0
const CATEGORY_MAX := 24.0
const SFX_MIN := -40.0
const SFX_MAX := 12.0

static var _path := DEFAULT_PATH
static var _path_locked := false       ## 显式 set_path() 之后不再听 AudioConfig 的路径
static var _cfg: AudioConfig = null
static var _loaded := false            ## load_into() 是否已经跑过（幂等用）
static var _active := false            ## 是否有真正生效的覆盖文件
static var _reason := "未加载"          ## 未生效的原因（自检 / 日志用，中文）
static var _state: Dictionary = {}     ## 当前状态（稀疏）
static var _records: Array = []        ## 保存记录，新 → 旧，≤ MAX_RECORDS
static var _sfx_on: Dictionary = {}    ## id -> bool（只有显式关闭的才在里面）
static var _sfx_db: Dictionary = {}    ## id -> dB 偏移（只有非 0 的才在里面）
static var _bgm_on: Dictionary = {}    ## 曲目 id -> bool（只有显式关闭的才在里面）
static var _save_count := 0            ## 累计保存次数（记录命名用，不随淘汰回退）
## 首次加载时记下的 AudioConfig 原始值。"重置为工程默认"要的是它，而不是"上一次覆盖过的值"。
static var _defaults: Dictionary = {}

# =============================================================== 查询
static func path() -> String:
	return _path

## 覆盖文件路径（自检用；改完记得 reset()，否则会带着铁锈跑后面的用例）
## 名字里带 profile 是必须的：Resource/Script 自己就有 set_path()，静态函数会被内置顶掉
## （同名不是"覆盖"，是**静默失效** —— 实测过，别再改回 set_path）。
static func set_profile_path(p: String) -> void:
	_path = p
	_path_locked = true
	_loaded = false

static func is_active() -> bool:
	return _active

static func status() -> Dictionary:
	return {
		"active": _active,
		"loaded": _loaded,
		"path": _path,
		"reason": _reason,
		"records": _records.size(),
		"sfx_off": disabled_ids().size(),
		"sfx_tuned": _sfx_db.size(),
	}

## 这条音效是否允许发声（**缺省允许** —— 没被显式关闭的一律照旧）
static func is_enabled(id: String) -> bool:
	if not _active:
		return true
	return bool(_sfx_on.get(id, true))

## 这条音效的单条音量偏移（dB，缺省 0）
static func sfx_db(id: String) -> float:
	if not _active:
		return 0.0
	return float(_sfx_db.get(id, 0.0))

## 某首背景音乐是否允许播放（缺省允许）
static func bgm_enabled(track: String) -> bool:
	if not _active:
		return true
	return bool(_bgm_on.get(track, true))

## 被显式关闭的音效 id（调试面板 / 自检报告用）
static func disabled_ids() -> Array:
	var a: Array = []
	for id in _sfx_on:
		if not bool(_sfx_on[id]):
			a.append(String(id))
	a.sort()
	return a

static func record_count() -> int:
	return _records.size()

## 保存记录（新 → 旧）。返回内部数组的**深副本**，调用方改不动本层状态。
static func records() -> Array:
	return _records.duplicate(true)
# =============================================================== 加载
## 把覆盖文件读进来并**写回 AudioConfig**（分类 / 总音量 / BGM 偏移）。
## 幂等：同一个进程里重复调用只读一次盘。返回是否生效。
static func load_into(cfg: AudioConfig = null) -> bool:
	if _loaded:
		return _active
	_loaded = true
	if cfg != null:
		_cfg = cfg
	if _cfg != null and not _path_locked and not _cfg.sfx_profile_path.is_empty():
		_path = _cfg.sfx_profile_path
	_capture_defaults()
	_reset_state()
	_records = []        # 重新读盘 = 历史以磁盘为准（_reset_state 自己不清记录，见那里的注释）
	if _cfg != null and not _cfg.use_sfx_profile:
		_reason = "AudioConfig.use_sfx_profile = false（工程里关掉了覆盖）"
		return false
	# 环境变量兜底：门禁要验"工程默认"那条路径，不能让本机的调音结果把它判红
	var env := OS.get_environment(ENV_OPT_OUT)
	if env == "0" or env.to_lower() == "false" or env.to_lower() == "off":
		_reason = "环境变量 %s=%s 已关闭覆盖" % [ENV_OPT_OUT, env]
		return false
	var data := read_file(_path)
	if data.is_empty():
		_reason = "没有覆盖文件（%s），走工程默认" % _path
		return false
	# 记录先读：历史（十条保存记录）与"当前状态是否可用"是两件事 ——
	# state 被手改坏时，不该连"能回滚到哪一条"也一起丢掉。
	var raw_records: Variant = data.get("records", [])
	if raw_records is Array:
		_records = _sanitize_records(raw_records)
	if not apply_state(data.get("state", {})):
		_reason = "覆盖文件内容不可用（%s）；%d 条保存记录已载入" % [_path, _records.size()]
		return false
	_active = true
	_write_back()
	_reason = "已生效：记录 %d 条 / 关闭 %d 条 / 调过 %d 条" % [
		_records.size(), disabled_ids().size(), _sfx_db.size()]
	return true

## 重新读盘（调音台里改完文件后想当场听效果时用）
## 叫 reload_file 而不是 reload：Script 自己就有 reload()，静态函数会被内置顶掉
static func reload_file(cfg: AudioConfig = null) -> bool:
	_loaded = false
	return load_into(cfg)

## 清空内存状态（回到"没有任何覆盖"）。**保存记录也一起清掉** —— 这是"重置"该有的语义。
static func reset() -> void:
	_reset_state()
	_records = []
	_reason = "已重置（无覆盖）"

## 只清"当前覆盖"，**绝不动保存记录**：回滚（rollback_to）走的就是这条，
## 顺手清记录会让"点一次回滚，十条历史全没了" —— 历史是历史，覆盖是覆盖。
static func _reset_state() -> void:
	_active = false
	_state = {}
	_sfx_on = {}
	_sfx_db = {}
	_bgm_on = {}

# =============================================================== 状态读写
## 当前状态快照（可整份塞回 apply_state()，也是写进 JSON 的东西）。
## 一定是**完整**的：没被覆盖的字段补上工程默认值，所以两份快照可以直接逐字段比对。
static func state() -> Dictionary:
	var s := {"master_db": float(_state.get("master_db", _default_master()))}
	var cats_src: Dictionary = _state.get("categories", {})
	var cats := {}
	for cat in CATEGORY_FIELDS:
		cats[cat] = float(cats_src.get(cat, _default_category(String(cat))))
	s["categories"] = cats
	var bgm_src: Dictionary = _state.get("bgm", {})
	var bgm := {}
	for t in BGM_FIELDS:
		var one: Dictionary = bgm_src.get(t, {})
		bgm[t] = {
			"db": float(one.get("db", _default_bgm(String(t)))),
			"enabled": bool(one.get("enabled", _bgm_on.get(t, true))),
		}
	s["bgm"] = bgm
	var sfx := {}
	for id in SfxSynth.ids():
		var sid := String(id)
		var on: bool = bool(_sfx_on.get(sid, true))
		var db: float = float(_sfx_db.get(sid, 0.0))
		# 稀疏：默认状态的条目根本不出现（见文件头"覆盖是稀疏的"）
		if not on or not is_zero_approx(db):
			sfx[sid] = {"enabled": on, "db": db}
	s["sfx"] = sfx
	return s

## 把一份状态套进本层（并写回 AudioConfig）。返回是否至少有一个可用字段。
static func apply_state(raw: Variant) -> bool:
	if not (raw is Dictionary):
		return false
	var d := raw as Dictionary
	var any := false
	var master := _db_of(d.get("master_db"), MASTER_MIN, MASTER_MAX, NAN)
	if not is_nan(master):
		_state["master_db"] = master
		any = true
	var cats: Variant = d.get("categories")
	if cats is Dictionary:
		var cats_d := cats as Dictionary
		var out_c := {}
		for cat in CATEGORY_FIELDS:
			var v := _db_of(cats_d.get(cat), CATEGORY_MIN, CATEGORY_MAX, NAN)
			if not is_nan(v):
				out_c[cat] = v
				any = true
		if not out_c.is_empty():
			_state["categories"] = out_c
	var bgm: Variant = d.get("bgm")
	if bgm is Dictionary:
		var bgm_d := bgm as Dictionary
		var out_b := {}
		for t in BGM_FIELDS:
			var entry: Variant = bgm_d.get(t)
			if not (entry is Dictionary):
				continue
			var e := entry as Dictionary
			var db := _db_of(e.get("db"), MASTER_MIN, MASTER_MAX, NAN)
			if not is_nan(db):
				out_b[t] = {"db": db}
				any = true
			if e.has("enabled"):
				_bgm_on[t] = _as_bool(e.get("enabled"), true)
				any = true
		if not out_b.is_empty():
			_state["bgm"] = _merge_bgm(_state.get("bgm", {}), out_b)
	var sfx: Variant = d.get("sfx")
	if sfx is Dictionary:
		var sfx_d := sfx as Dictionary
		for key in sfx_d:
			var sid := String(key)
			if not SfxSynth.SPECS.has(sid):
				continue          # 未知 id（音色被删了？）直接忽略，不写进状态
			var e2: Variant = sfx_d[key]
			if e2 is bool:
				# 允许简写："hit_light": false 等价于 {"enabled": false}
				_sfx_on[sid] = bool(e2)
				any = true
				continue
			if not (e2 is Dictionary):
				continue
			var ed := e2 as Dictionary
			if ed.has("enabled"):
				_sfx_on[sid] = _as_bool(ed.get("enabled"), true)
				any = true
			var v2 := _db_of(ed.get("db"), SFX_MIN, SFX_MAX, NAN)
			if not is_nan(v2):
				_sfx_db[sid] = v2
				any = true
	return any

static func _merge_bgm(old: Variant, new_parts: Dictionary) -> Dictionary:
	var out := {}
	if old is Dictionary:
		var old_d := old as Dictionary
		for k in old_d:
			var one: Variant = old_d[k]
			out[String(k)] = (one as Dictionary).duplicate() if one is Dictionary else {}
	for t in new_parts:
		var cur: Dictionary = out.get(t, {})
		var part: Dictionary = new_parts[t]
		for f in part:
			cur[f] = part[f]
		out[t] = cur
	return out

## 把当前状态写回 AudioConfig（分类 / 总音量 / BGM 偏移）并当场生效
static func _write_back() -> void:
	if _cfg == null:
		return
	var cats: Dictionary = _state.get("categories", {})
	var bgm: Dictionary = _state.get("bgm", {})
	_cfg.master_db = float(_state.get("master_db", _cfg.master_db))
	for cat in CATEGORY_FIELDS:
		if cats.has(cat):
			_cfg.set(String(CATEGORY_FIELDS[cat]), float(cats[cat]))
	for t in BGM_FIELDS:
		var one: Dictionary = bgm.get(t, {})
		if one.has("db"):
			_cfg.set(String(BGM_FIELDS[t]), float(one["db"]))
	AudioBus.apply(_cfg)   # 总音量 / 音乐音量当场生效，不用等下次启动
# =============================================================== 保存记录（十条）
## 保存一次：把当前状态整份记下来。返回这条记录（字典）。
## name 为空时自动命名「第 N 次保存」（N = 累计保存序号，不随淘汰回退，
## 所以第 12 条不会又叫「第 1 次保存」而让人对不上时间线）。
static func save_record(name := "") -> Dictionary:
	_save_count += 1
	var snap := state()
	var prev: Dictionary = {}
	if not _records.is_empty():
		prev = (_records[0] as Dictionary).get("state", {})
	var stamp := Time.get_datetime_string_from_system(false, true)
	var rec := {
		"id": "rec_%s_%d" % [stamp.replace(":", "").replace("-", "").replace(" ", "_"), _save_count],
		"saved_at": stamp,
		"name": name if not name.is_empty() else "第 %d 次保存" % _save_count,
		"summary": summarize(prev, snap),
		"state": snap,
	}
	_records.insert(0, rec)
	while _records.size() > MAX_RECORDS:
		_records.pop_back()
	return rec

## 回滚到某条记录（0 = 最新）。整份快照套回去，所以可以来回滚。
static func rollback_to(index: int) -> bool:
	if index < 0 or index >= _records.size():
		return false
	var st: Variant = (_records[index] as Dictionary).get("state", {})
	# 先把"当前覆盖"清空再套快照 —— 否则快照里没出现的旧调整会残留下来，
	# 回滚就变成了"合并"（点了 A 记录却还留着 B 记录的东西，最难查的那种不一致）
	_reset_state()
	if not apply_state(st):
		return false
	_active = true
	_write_back()
	return true

static func delete_record(index: int) -> bool:
	if index < 0 or index >= _records.size():
		return false
	_records.remove_at(index)
	return true

## 与另一份状态的差异摘要（人类可读，中文）。用于记录的"可追溯"那一栏。
static func summarize(before: Variant, after: Variant) -> String:
	var a_d: Dictionary = before if (before is Dictionary) else {}
	var b_d: Dictionary = after if (after is Dictionary) else {}
	var a_sfx: Dictionary = a_d.get("sfx", {})
	var b_sfx: Dictionary = b_d.get("sfx", {})
	var parts: Array = []
	var off: Array = []
	var on: Array = []
	for id in SfxSynth.ids():
		var sid := String(id)
		var a_one: Dictionary = a_sfx.get(sid, {})
		var b_one: Dictionary = b_sfx.get(sid, {})
		var was: bool = bool(a_one.get("enabled", true))
		var now: bool = bool(b_one.get("enabled", true))
		if was != now:
			if now:
				on.append(sid)
			else:
				off.append(sid)
	if not off.is_empty():
		parts.append("关闭 %d 条（%s）" % [off.size(), ", ".join(_short(off))])
	if not on.is_empty():
		parts.append("打开 %d 条（%s）" % [on.size(), ", ".join(_short(on))])
	var tuned: Array = []
	for id in SfxSynth.ids():
		var sid2 := String(id)
		var a_one2: Dictionary = a_sfx.get(sid2, {})
		var b_one2: Dictionary = b_sfx.get(sid2, {})
		var d0: float = float(a_one2.get("db", 0.0))
		var d1: float = float(b_one2.get("db", 0.0))
		if not is_equal_approx(d0, d1):
			tuned.append("%s %+.1f→%+.1f" % [sid2, d0, d1])
	if not tuned.is_empty():
		parts.append("音量 %d 条（%s）" % [tuned.size(), ", ".join(_short(tuned))])
	var dm: float = float(b_d.get("master_db", 0.0)) - float(a_d.get("master_db", 0.0))
	if not is_zero_approx(dm):
		parts.append("总音量 %+.1f dB" % dm)
	var dc := _count_cat_changes(a_d, b_d)
	if dc > 0:
		parts.append("分类音量 %d 档" % dc)
	var dg := 0
	var a_bgm: Dictionary = a_d.get("bgm", {})
	var b_bgm: Dictionary = b_d.get("bgm", {})
	for t in BGM_FIELDS:
		var a_t: Dictionary = a_bgm.get(t, {})
		var b_t: Dictionary = b_bgm.get(t, {})
		if bool(a_t.get("enabled", true)) != bool(b_t.get("enabled", true)):
			dg += 1
		elif not is_equal_approx(float(a_t.get("db", 0.0)), float(b_t.get("db", 0.0))):
			dg += 1
	if dg > 0:
		parts.append("背景音乐 %d 项" % dg)
	if parts.is_empty():
		return "与上一条相同"
	return "；".join(parts)

static func _short(arr: Array) -> Array:
	if arr.size() <= 3:
		return arr
	return [arr[0], arr[1], "…共 %d 条" % arr.size()]

static func _count_cat_changes(a: Dictionary, b: Dictionary) -> int:
	var n := 0
	var ca: Dictionary = a.get("categories", {})
	var cb: Dictionary = b.get("categories", {})
	for cat in CATEGORY_FIELDS:
		if not is_equal_approx(float(ca.get(cat, 0.0)), float(cb.get(cat, 0.0))):
			n += 1
	return n
# =============================================================== 磁盘
## 读一份配置文件的原始结构（不做校验）。文件不存在 / 读不出 / JSON 坏 → 返回 {}
static func read_file(p: String) -> Dictionary:
	if p.is_empty() or not FileAccess.file_exists(p):
		return {}
	var txt := FileAccess.get_file_as_string(p)
	if txt.is_empty():
		return {}
	var parsed: Variant = null
	# 用 JSON.new().parse() 而不是 JSON.parse_string()：后者解析失败会往日志里打 ERROR，
	# 玩家手改坏一个配置文件不该在游戏日志里刷红字（门禁也要求零 ERROR）。
	var j := JSON.new()
	if j.parse(txt) == OK:
		parsed = j.data
	if not (parsed is Dictionary):
		return {}
	return parsed as Dictionary

## 把当前状态 + 记录写回磁盘（游戏内保存时用；网页调音台走自己的服务端写同一个文件）
static func save_to_disk(p := "") -> bool:
	var target := p if not p.is_empty() else _path
	if target.is_empty():
		return false
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		push_warning("SfxProfile：写不进 %s（错误码 %d）" % [target, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(serialize(), "  ") + "\n")
	f.close()
	return true

## 完整的可写结构（state + records + 头信息）
static func serialize() -> Dictionary:
	return {
		"schema": SCHEMA,
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"generator": "SfxProfile.gd（Godot 侧）",
		"records": _records.duplicate(true),
		"state": state(),
	}

# =============================================================== 内部小工具
## 校验磁盘上的记录：坏记录（空壳 / 不是字典 / state 里一个可用字段都没有）直接丢，
## 不留"点了回滚却什么都没发生"的陷阱。**不改动当前状态** —— 试算前先把内部状态存下来。
static func _sanitize_records(raw: Array) -> Array:
	var out: Array = []
	for item in raw:
		if out.size() >= MAX_RECORDS:
			break
		if not (item is Dictionary):
			continue
		var r := item as Dictionary
		var keep := _snapshot_internals()
		_reset_state()
		var ok := apply_state(r.get("state", {}))
		var st := state() if ok else {}
		_restore_internals(keep)
		if not ok:
			continue
		out.append({
			"id": String(r.get("id", "rec_%d" % out.size())),
			"saved_at": String(r.get("saved_at", "")),
			"name": String(r.get("name", "未命名")),
			"summary": String(r.get("summary", "")),
			"state": st,
		})
	return out

static func _snapshot_internals() -> Array:
	return [
		_state.duplicate(true), _sfx_on.duplicate(), _sfx_db.duplicate(),
		_bgm_on.duplicate(), _active,
	]

static func _restore_internals(s: Array) -> void:
	_state = s[0]
	_sfx_on = s[1]
	_sfx_db = s[2]
	_bgm_on = s[3]
	_active = bool(s[4])

## 首次加载时把 AudioConfig 的原始值抄一份，供"工程默认"使用
static func _capture_defaults() -> void:
	if _cfg == null or not _defaults.is_empty():
		return
	_defaults["master_db"] = _cfg.master_db
	var cats := {}
	for cat in CATEGORY_FIELDS:
		cats[cat] = float(_cfg.get(String(CATEGORY_FIELDS[cat])))
	_defaults["categories"] = cats
	var bgm := {}
	for t in BGM_FIELDS:
		bgm[t] = float(_cfg.get(String(BGM_FIELDS[t])))
	_defaults["bgm"] = bgm

## 工程默认值（网页调音台的"重置"按钮对着它；也是记录的基准）
static func defaults() -> Dictionary:
	_capture_defaults()
	return _defaults.duplicate(true)

static func _default_master() -> float:
	if _defaults.has("master_db"):
		return float(_defaults["master_db"])
	return _cfg.master_db if _cfg != null else 0.0

static func _default_category(cat: String) -> float:
	var cats: Dictionary = _defaults.get("categories", {})
	if cats.has(cat):
		return float(cats[cat])
	if _cfg == null or not CATEGORY_FIELDS.has(cat):
		return 0.0
	return float(_cfg.get(String(CATEGORY_FIELDS[cat])))

static func _default_bgm(track: String) -> float:
	var bgm: Dictionary = _defaults.get("bgm", {})
	if bgm.has(track):
		return float(bgm[track])
	if _cfg == null or not BGM_FIELDS.has(track):
		return 0.0
	return float(_cfg.get(String(BGM_FIELDS[track])))

## 取一个数并夹到区间；不是数 / NaN / Inf / bool → 返回 fallback
static func _db_of(v: Variant, lo: float, hi: float, fallback: float) -> float:
	if v is bool or v == null:
		return fallback
	if not (v is float or v is int):
		return fallback
	var x := float(v)
	if is_nan(x) or is_inf(x):
		return fallback
	return clampf(x, lo, hi)

static func _as_bool(v: Variant, fallback: bool) -> bool:
	if v is bool:
		return bool(v)
	if v is float or v is int:
		return float(v) != 0.0
	if v is String:
		var s := (v as String).to_lower()
		if s == "true" or s == "1" or s == "on":
			return true
		if s == "false" or s == "0" or s == "off":
			return false
	return fallback