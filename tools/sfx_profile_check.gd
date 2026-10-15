## =============================================================================
##  sfx_profile_check —— 音效调音台（SfxProfile）运行时自检（**不参与游戏运行**）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --script res://tools/sfx_profile_check.gd
##
##  网页调音台（tools/sfx_studio）改的是 user:// 下的一份 JSON。页面好看不等于游戏真的听，
##  这一层逐条验的是"游戏侧到底认不认"：
##    1) 没有配置文件时完全惰性（不关音、不改音量）
##    2) **关闭 = 真的不播**：Sfx.play() 连播放计数都不加（_peek 直接丢弃）
##    3) 单条 / 分类 / 总音量偏移精确叠加到 Sfx.volume_db_of()
##    4) 越界钳制、非法类型忽略、未知 id 忽略（音色被删掉也不炸）
##    5) 十条记录上限（保存淘汰最旧 + 读盘也截到十条）、回滚精确还原、越界不崩
##    6) JSON 坏掉 / 顶层不是对象 / 路径指到目录 → 惰性降级（不崩、不生效）
##    7) WARBAND_SFX_PROFILE=0 时整层不生效（门禁验的是"工程默认"那条路径）
##    8) 网页端真正写出的文件形状（含网页独有的 undo 字段）能被游戏直接读
##
##  只写 user://sfx_profile_check_tmp.json，绝不碰真实配置。
##  退出码 0 = 全部通过；1 = 有断言失败
## =============================================================================
extends SceneTree

const TMP := "user://sfx_profile_check_tmp.json"
const ENV := "WARBAND_SFX_PROFILE"

var host: Node
var cfg: AudioConfig
var fails: Array = []
var checks := 0
var base: Dictionary = {}      ## 工程默认下的基线，用来算"偏移了多少"
var env_saved := ""

func _initialize() -> void:
	_watchdog()          # 兜底协程：脚本中途报错也不会让引擎挂死在那儿
	_run()

## 看门狗：本检查不依赖帧，正常几秒跑完；只有脚本中途报错没走到 quit() 才可能触发
func _watchdog() -> void:
	for i in 3600:
		await process_frame
	print("[音效配置] FAIL：看门狗超时（3600 帧未跑完，多半是脚本中途报错）")
	quit(1)

func _run() -> void:
	print("[音效配置] SfxProfile 运行时自检（临时文件 %s）" % TMP)
	env_saved = OS.get_environment(ENV)
	OS.set_environment(ENV, "1")     # 门禁默认设 0；本检查要先验"生效"那条路径
	_rm(TMP)
	SfxProfile.set_profile_path(TMP)
	cfg = AudioConfig.create()
	host = Node.new()
	host.name = "SfxProfileCheckHost"
	root.add_child(host)
	# _initialize() 里 add_child 之后节点要到下一帧才真正入树。不 await 的话播放池会在
	# "不在树上"的状态下建出来，第一声 play() 直接报 ERROR（门禁对 ERROR 零容忍）。
	await process_frame
	await Sfx.setup(host, cfg)      # setup 是协程（冷启动合成分片），必须等它真跑完
	print("[音效配置] 就绪：音色 %d 条 / 录音变体 %d 个 / 播放池 %d 个 / 覆盖路径 %s" % [
		Sfx.bank_size(), Sfx.foley_total(), Sfx.pool_size(), SfxProfile.path()])

	_sc_inert()
	_sc_sparse()
	_sc_categories()
	_sc_limits()
	_sc_records()
	_sc_broken()
	_sc_env_off()
	_sc_web_contract()

	_rm(TMP)
	SfxProfile.reset()
	OS.set_environment(ENV, env_saved)
	host.free()
	if fails.is_empty():
		print("[音效配置] PASS：%d 项断言全部通过（惰性 / 关闭=不播 / 偏移精确 / 十条记录 / 回滚 / 降级 / 网页契约）" % checks)
		quit(0)
	else:
		for f in fails:
			print("[音效配置] 失败项：%s" % String(f))
		print("[音效配置] FAIL：%d / %d 项未通过" % [fails.size(), checks])
		quit(1)

# =============================================================== 1) 惰性
func _sc_inert() -> void:
	_rm(TMP)
	SfxProfile.reload_file(cfg)
	_expect(not SfxProfile.is_active(), "没有配置文件 → 整层不生效")
	_expect(SfxProfile.path() == TMP, "覆盖路径可指定（自检只写临时文件）")
	_expect(SfxProfile.is_enabled("hit_light"), "缺省全开：没被点名的音效照旧")
	_expect(is_zero_approx(SfxProfile.sfx_db("hit_light")), "缺省单条偏移 0 dB")
	_expect(is_zero_approx(SfxProfile.sfx_db("一个不存在的 id")), "问未知 id 也返回 0（不崩）")
	_expect(SfxProfile.bgm_enabled("map") and SfxProfile.bgm_enabled("battle"), "缺省两首 BGM 都可播")
	_expect(SfxProfile.record_count() == 0, "缺省没有保存记录")
	base["hit_light"] = Sfx.volume_db_of("hit_light")
	base["hit_crit"] = Sfx.volume_db_of("hit_crit")
	base["parry"] = Sfx.volume_db_of("parry")
	print("[音效配置]   基线：hit_light %.2f dB / hit_crit %.2f dB / parry %.2f dB / Master %.2f dB" % [
		base["hit_light"], base["hit_crit"], base["parry"], AudioBus.master_db()])

# =============================================================== 2) 稀疏覆盖 + 关闭=不播
func _sc_sparse() -> void:
	_write_profile({"sfx": {"hit_light": false, "hit_crit": {"enabled": true, "db": 3.0}}})
	SfxProfile.reload_file(cfg)
	_expect(SfxProfile.is_active(), "稀疏覆盖文件被采纳")
	_expect(not SfxProfile.is_enabled("hit_light"), "被关闭的音效 is_enabled() = false")
	_expect(SfxProfile.disabled_ids() == ["hit_light"], "disabled_ids() 只报被关掉的那一条")
	_expect(SfxProfile.is_enabled("hit_crit"), "同时被调了音量、没被关的音效照旧开")
	_expect(is_equal_approx(SfxProfile.sfx_db("hit_crit"), 3.0), "单条偏移读回来是 +3.0 dB")
	var d: float = Sfx.volume_db_of("hit_crit") - float(base["hit_crit"])
	_expect(is_equal_approx(d, 3.0), "volume_db_of() 精确叠加 +3.0 dB（实测 %+.2f）" % d)
	_expect(is_equal_approx(Sfx.volume_db_of("hit_light"), float(base["hit_light"])),
		"被关闭的音效音量不动（关的是播不播，不是改音量）")
	# 关闭 = 真的不播：play() 走 _peek → 直接丢弃，连播放计数都不加
	Sfx.reset_counts()
	Sfx.play("hit_light")
	Sfx.play("hit_crit")
	var c: Dictionary = Sfx.counts()
	_expect(not c.has("hit_light"), "关闭的音效 play() 一声都不播（播放计数里没有它）")
	_expect(int(c.get("hit_crit", 0)) == 1, "没关闭的音效照常播放（计数 1）")
	_expect(Sfx.total_plays() == 1, "累计播放数只加了那一声")
	# 未知 id（音色被删 / 打错字）不许写进状态，也不许炸
	_write_profile({"sfx": {"not_a_real_sound": false, "hit_light": false}})
	SfxProfile.reload_file(cfg)
	_expect(SfxProfile.is_active() and SfxProfile.disabled_ids() == ["hit_light"],
		"未知音效 id 被忽略，不影响已知的那条")
# =============================================================== 3) 分类 / 总音量 / BGM
func _sc_categories() -> void:
	_write_profile({
		"master_db": -6.0,
		"categories": {"combat": -4.0, "ui": 2.0},
		"bgm": {"map": {"db": -3.0, "enabled": false}, "battle": {"enabled": false}},
	})
	SfxProfile.reload_file(cfg)
	_expect(SfxProfile.is_active(), "带分类音量的配置生效")
	_expect(is_equal_approx(cfg.master_db, -6.0), "总音量写回 AudioConfig.master_db = -6.0")
	_expect(is_equal_approx(AudioBus.master_db(), -6.0),
		"总音量当场落到 Master 总线（实测 %.2f dB）" % AudioBus.master_db())
	_expect(is_equal_approx(cfg.combat_db, -4.0), "分类音量写回 AudioConfig.combat_db = -4.0")
	_expect(is_equal_approx(cfg.ui_db, 2.0), "分类音量写回 AudioConfig.ui_db = +2.0")
	var d: float = Sfx.volume_db_of("hit_crit") - float(base["hit_crit"])
	_expect(is_equal_approx(d, -4.0), "分类偏移叠进每一声（combat -4.0 dB，实测 %+.2f）" % d)
	var dp: float = Sfx.volume_db_of("parry") - float(base["parry"])
	_expect(is_zero_approx(dp), "没被点名的分类不受影响（parry %+.2f dB）" % dp)
	_expect(not SfxProfile.bgm_enabled("map"), "背景音乐可以单独关掉（大地图）")
	_expect(not SfxProfile.bgm_enabled("battle"), "背景音乐可以单独关掉（战斗）")
	_expect(is_equal_approx(cfg.bgm_map_db, -3.0), "BGM 单曲偏移写回 AudioConfig（-3.0 dB）")
	var fresh := AudioConfig.create()
	_expect(is_equal_approx(cfg.bgm_db, fresh.bgm_db), "Music 总线音量没被误动（BGM 走单曲偏移）")

# =============================================================== 4) 钳制 / 非法值
func _sc_limits() -> void:
	_write_profile({"master_db": 999.0, "categories": {"combat": -999.0},
		"sfx": {"hit_crit": {"db": 999.0}}})
	SfxProfile.reload_file(cfg)
	_expect(is_equal_approx(cfg.master_db, SfxProfile.MASTER_MAX), "总音量越界钳到 +24 dB")
	_expect(is_equal_approx(cfg.combat_db, SfxProfile.CATEGORY_MIN), "分类越界钳到 -40 dB")
	_expect(is_equal_approx(SfxProfile.sfx_db("hit_crit"), SfxProfile.SFX_MAX), "单条越界钳到 +12 dB")
	# 一个可用字段都没有 → 整份不生效（不是"当成 0"含糊过去）
	_write_profile({"sfx": {"hit_crit": {"db": "响一点"}}})
	SfxProfile.reload_file(cfg)
	_expect(not SfxProfile.is_active(), "全是非法字段 → 不生效（回工程默认）")
	_expect(is_zero_approx(SfxProfile.sfx_db("hit_crit")), "非法 dB 不残留")
	# 开关类型不对 → 按缺省（开）算，不崩
	_write_profile({"sfx": {"hit_light": {"enabled": "nope"}}})
	SfxProfile.reload_file(cfg)
	_expect(SfxProfile.is_active() and SfxProfile.is_enabled("hit_light"),
		"开关类型不对 → 按缺省（开）处理，不影响游戏")

# =============================================================== 5) 十条记录 + 回滚
func _sc_records() -> void:
	_write_profile({})
	SfxProfile.reload_file(cfg)
	_expect(not SfxProfile.is_active(), "空 state → 不生效（清场）")
	for i in 12:
		SfxProfile.apply_state({"sfx": {
			"hit_light": {"enabled": (i % 2 == 0)},
			"hit_crit": {"db": float(i) - 6.0},
		}})
		SfxProfile.save_record()
	_expect(SfxProfile.record_count() == SfxProfile.MAX_RECORDS,
		"连存 12 条只留 10 条（上限 %d）" % SfxProfile.MAX_RECORDS)
	var recs: Array = SfxProfile.records()
	_expect(String((recs[0] as Dictionary)["name"]) == "第 12 次保存", "最新一条排在最前（第 12 次保存）")
	_expect(String((recs[9] as Dictionary)["name"]) == "第 3 次保存", "最旧的被淘汰（第 1、2 次已出局）")
	var names: Array = []
	for r in recs:
		names.append(String((r as Dictionary)["name"]))
	_expect(not names.has("第 1 次保存"), "第 1 次保存确实不在列表里了")
	_expect(_all_have_summary(recs), "每条都带可追溯的差异摘要（summarize）")
	var want: Dictionary = {}
	for k in [0, 4, 9]:
		SfxProfile.rollback_to(k)
		want = (recs[k] as Dictionary)["state"]
		_expect(SfxProfile.state() == want, "回滚到 #%d 后 state() 与那条记录逐字段一致" % (k + 1))
	# 写盘 → 读回：十条上限在磁盘上来回也不破
	_expect(SfxProfile.save_to_disk(TMP), "save_to_disk() 写盘成功")
	var raw: Dictionary = SfxProfile.read_file(TMP)
	_expect((raw.get("records", []) as Array).size() == 10, "文件里就是 10 条记录")
	_expect(String(raw.get("schema", "")) == SfxProfile.SCHEMA, "文件带 schema 标记")
	SfxProfile.reload_file(cfg)
	_expect(SfxProfile.record_count() == 10, "重新读盘仍是 10 条")
	_expect(SfxProfile.state() == want, "重新读盘后状态与回滚后的那条一致")
	# 文件里被手塞了 14 条 → 读进来也得截到 10 条
	var many: Array = []
	for i in 14:
		var one: Dictionary = (recs[i % 10] as Dictionary).duplicate(true)
		one["id"] = "rec_many_%d" % i
		many.append(one)
	_write_profile(SfxProfile.state(), many)
	SfxProfile.reload_file(cfg)
	_expect(SfxProfile.record_count() == 10, "文件里塞 14 条 → 读进来截到 10 条")
	# 坏记录（state 一个可用字段都没有）丢掉，好记录留着
	_write_profile({"sfx": {"hit_light": false}}, [
		{"id": "bad", "name": "坏记录", "state": {"sfx": {"hit_crit": {"db": "响"}}}},
		{"id": "good", "name": "好记录", "state": {"sfx": {"hit_crit": {"db": 1.0}}}},
	])
	SfxProfile.reload_file(cfg)
	_expect(SfxProfile.record_count() == 1, "坏记录被丢掉（点了也回滚不出东西）")
	_expect(String((SfxProfile.records()[0] as Dictionary)["name"]) == "好记录", "好记录保留")
	_expect(SfxProfile.delete_record(0), "删除第 1 条记录")
	_expect(SfxProfile.record_count() == 0, "删完剩 0 条")
	_expect(not SfxProfile.rollback_to(99), "越界回滚返回 false（不崩）")
	_expect(not SfxProfile.delete_record(-1), "越界删除返回 false（不崩）")
# =============================================================== 6) 坏文件降级
func _sc_broken() -> void:
	_write(TMP, "{ 这不是 JSON")
	SfxProfile.reload_file(cfg)
	_expect(not SfxProfile.is_active(), "JSON 坏掉 → 惰性降级（不生效）")
	_expect(SfxProfile.is_enabled("hit_light"), "JSON 坏掉时音效照常开（不牵连游戏）")
	_write(TMP, "[1, 2, 3]")
	SfxProfile.reload_file(cfg)
	_expect(not SfxProfile.is_active(), "顶层是数组 → 不生效")
	_write(TMP, "")
	SfxProfile.reload_file(cfg)
	_expect(not SfxProfile.is_active(), "空文件 → 不生效")
	_write(TMP, "{\"schema\": \"warband.sfx_profile\", \"state\": \"不是对象\"}")
	SfxProfile.reload_file(cfg)
	_expect(not SfxProfile.is_active(), "state 不是对象 → 不生效")
	SfxProfile.set_profile_path("user://")
	SfxProfile.reload_file(cfg)
	_expect(not SfxProfile.is_active(), "路径指到目录 → 不生效且不崩")
	SfxProfile.set_profile_path(TMP)
	# state 坏了但记录完好 → 记录照样可追溯（历史与"当前是否生效"是两件事）
	_write_profile({}, [])
	_write(TMP, JSON.stringify({
		"schema": "warband.sfx_profile", "version": 1,
		"records": [{"id": "r1", "name": "还能回滚", "state": {"sfx": {"hit_light": false}}}],
		"state": {"sfx": {"hit_crit": {"db": "响"}}},
	}, "  "))
	SfxProfile.reload_file(cfg)
	_expect(not SfxProfile.is_active(), "state 不可用 → 不生效")
	_expect(SfxProfile.record_count() == 1, "但保存记录仍然载入（能查到历史）")

# =============================================================== 7) 环境变量
func _sc_env_off() -> void:
	_write_profile({"sfx": {"hit_light": false, "hit_crit": {"db": 4.0}}})
	OS.set_environment(ENV, "1")
	SfxProfile.reload_file(cfg)
	_expect(SfxProfile.is_active(), "环境变量为 1 时覆盖生效")
	OS.set_environment(ENV, "0")
	SfxProfile.reload_file(cfg)
	_expect(not SfxProfile.is_active(), "%s=0 → 整层不生效（门禁走的就是这条）" % ENV)
	_expect(SfxProfile.is_enabled("hit_light"), "环境变量关闭后音效全开")
	_expect(is_zero_approx(SfxProfile.sfx_db("hit_crit")), "环境变量关闭后偏移归零")
	OS.set_environment(ENV, "OFF")
	SfxProfile.reload_file(cfg)
	_expect(not SfxProfile.is_active(), "换成 OFF（大小写不敏感）同样关闭")
	OS.set_environment(ENV, "1")

# =============================================================== 8) 网页端契约
## 这一节最重要：把 tools/sfx_studio/app.js 真正写出来的文件形状喂进来。
## 网页端会多写一个 undo 字段（单级撤销，游戏侧不认），必须被安静忽略。
func _sc_web_contract() -> void:
	var web_state: Dictionary = {
		"master_db": -2.5,
		"categories": {"move": -8.0},
		"bgm": {"battle": {"db": 1.5, "enabled": false}},
		"sfx": {"hit_light": {"enabled": false, "db": -3.0}, "parry": {"enabled": true, "db": 2.0}},
	}
	_write(TMP, JSON.stringify({
		"schema": "warband.sfx_profile",
		"version": 1,
		"saved_at": "2026-10-15 12:00:00",
		"generator": "tools/sfx_studio (web)",
		"undo": {"at": "2026-10-15 12:01:00", "state": {"master_db": 0.0}},
		"records": [{
			"id": "rec_20261015120000_1",
			"saved_at": "2026-10-15 12:00:00",
			"name": "整体压低",
			"summary": "关闭 1 条（hit_light）；音量 2 条（parry +0.0→+2.0）",
			"state": web_state.duplicate(true),
		}],
		"state": web_state,
	}, "  ") + "\n")
	SfxProfile.reload_file(cfg)
	_expect(SfxProfile.is_active(), "网页端写出的文件能直接被游戏读进来")
	_expect(not SfxProfile.is_enabled("hit_light"), "网页关掉的音效在游戏里真的关掉了")
	_expect(is_equal_approx(SfxProfile.sfx_db("parry"), 2.0), "网页调的 +2.0 dB 精确读回")
	_expect(is_equal_approx(SfxProfile.sfx_db("hit_light"), -3.0), "关掉的同时调的音量也读回（-3.0 dB）")
	_expect(is_equal_approx(cfg.master_db, -2.5), "网页调的总音量写回 AudioConfig")
	_expect(is_equal_approx(cfg.move_db, -8.0), "网页调的分类音量写回 AudioConfig")
	_expect(not SfxProfile.bgm_enabled("battle"), "网页关掉的战斗曲在游戏里真的不播")
	_expect(is_equal_approx(cfg.bgm_battle_db, 1.5), "网页调的 BGM 偏移写回 AudioConfig")
	_expect(SfxProfile.record_count() == 1, "网页保存的记录在游戏侧可追溯（1 条）")
	_expect(String((SfxProfile.records()[0] as Dictionary)["name"]) == "整体压低", "记录名字保留")
	_expect(not SfxProfile.state().has("undo"), "网页端独有的 undo 字段不会污染游戏侧状态")
	_expect(not SfxProfile.status().is_empty(), "status() 可用（调试面板 F3 的量）")
	_expect(SfxProfile.rollback_to(0), "能回到网页保存的那一条")
	_expect(not SfxProfile.is_enabled("hit_light") and is_equal_approx(SfxProfile.sfx_db("parry"), 2.0),
		"回滚后仍是网页保存的那一套（关闭 + 偏移）")
	# 全关（网页的「全部关闭」按钮）→ 28 条一声不响
	var all_off: Dictionary = {}
	for id in SfxSynth.ids():
		all_off[String(id)] = false
	_write_profile({"sfx": all_off})
	SfxProfile.reload_file(cfg)
	_expect(SfxProfile.disabled_ids().size() == SfxSynth.ids().size(),
		"全部关闭时 %d 条全被登记为关闭" % SfxSynth.ids().size())
	Sfx.reset_counts()
	for id in SfxSynth.ids():
		Sfx.play(String(id))
	_expect(Sfx.total_plays() == 0, "全部关闭后 play() 跑遍 28 条，一声都没播")

# =============================================================== 小工具
func _write(p: String, text: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		_expect(false, "写不进 %s（错误码 %d）" % [p, FileAccess.get_open_error()])
		return
	f.store_string(text)
	f.close()

## 造一份和网页端同形状的覆盖文件
func _write_profile(state: Dictionary, records: Array = []) -> void:
	_write(TMP, JSON.stringify({
		"schema": "warband.sfx_profile",
		"version": 1,
		"saved_at": "2026-01-01 00:00:00",
		"generator": "tools/sfx_profile_check.gd",
		"records": records,
		"state": state,
	}, "  ") + "\n")

func _rm(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func _all_have_summary(recs: Array) -> bool:
	for r in recs:
		if String((r as Dictionary).get("summary", "")).is_empty():
			return false
	return true

func _expect(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("[音效配置]   ✓ %s" % msg)
	else:
		fails.append(msg)
		print("[音效配置]   ✗ %s" % msg)