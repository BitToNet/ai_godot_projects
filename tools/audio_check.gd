## =============================================================================
##  audio_check —— 音频总线定式自检（**不参与游戏运行**，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/audio_check.gd
##
##  检查六件事（每一项都读真实对象，不是看常量）：
##    1) default_bus_layout.tres 真被引擎加载：三条总线、Music / Sfx 都 send 到 Master
##    2) AudioBus 写回：master_db → Master 总线、bgm_db → Music 总线；没有的总线退 Master
##    3) Sfx 池：24 个播放器全在 Sfx 总线上；逐声音量里**不再**含 master_db（否则会算两遍）
##    4) Bgm：播放器在 Music 总线上，播放器上只留单曲偏移（bgm_db 只在总线上算一次）
##    5) duck：手动压低 → 到点自动恢复；扇子音（order）自动触发、普通音不触发、正增益被拒
##    6) 静音走增益淡出而不是总线静音（M 键的听感是"淡下去"而不是"硬切"）
##
##  这个脚本**不建世界、不生成地图**（不需要 Main），所以只花掉合成 28 个音色的时间；
##  它同时是 SfxSynth → Sfx → AudioBus 这条链的冒烟测试：合成出来的音色真的能挂上总线。
##
##  退出码 0 = 全部通过；1 = 有断言不通过（或看门狗超时）
## =============================================================================
extends SceneTree

var host: Node
var fails: Array = []
var n_ok := 0

func _initialize() -> void:
	_watchdog()
	_run()

## 看门狗：headless 下 --fixed-fps 60 让帧跑得比真实时间快，3600 帧远超本检查所需
func _watchdog() -> void:
	for i in 3600:
		await process_frame
	print("[音频总线] FAIL：看门狗超时（3600 帧未跑完，多半是脚本中途报错）")
	quit(1)

func _run() -> void:
	var cfg := AudioConfig.new()
	host = Node.new()
	host.name = "AudioCheckHost"
	root.add_child(host)

	# ---------------------------------------------------------------- 1) 布局
	_section("1) 总线布局（%s）" % AudioBus.LAYOUT)
	_ok(FileAccess.file_exists(AudioBus.LAYOUT), "布局文件存在")
	_ok(ResourceLoader.exists(AudioBus.LAYOUT), "布局文件可被 ResourceLoader 认得")
	_eqi(AudioServer.bus_count, 3, "总线数 = 3（Master + Music + Sfx）")
	_eqs(String(AudioServer.get_bus_name(0)), "Master", "0 号总线名 = Master")
	_ok(AudioBus.has_bus("Music"), "存在 Music 总线")
	_ok(AudioBus.has_bus("Sfx"), "存在 Sfx 总线")
	_eqs(String(AudioServer.get_bus_send(AudioServer.get_bus_index("Music"))), "Master", "Music → Master")
	_eqs(String(AudioServer.get_bus_send(AudioServer.get_bus_index("Sfx"))), "Master", "Sfx → Master")

	# ---------------------------------------------------------------- 2) 写回 / 降级
	_section("2) AudioBus 写回与降级")
	_eqs(AudioBus.route("Music"), "Music", "route(存在的总线) 原样返回")
	_eqs(AudioBus.route("NoSuchBus"), "Master", "route(不存在的总线) 退 Master（降级而不是静音）")
	_eqs(AudioBus.route("Master"), "Master", "route(Master) = Master")
	cfg.master_db = -6.0
	cfg.bgm_db = -2.0
	AudioBus.apply(cfg)
	_nearf(AudioBus.master_db(), -6.0, 0.001, "apply：master_db 落到 Master 总线")
	_nearf(AudioBus.music_db(), -2.0, 0.001, "apply：bgm_db 落到 Music 总线")
	_nearf(AudioBus.sfx_db(), 0.0, 0.001, "Sfx 总线保持 0 dB（分类音量仍在代码里逐声相加）")
	cfg.master_db = 0.0
	cfg.bgm_db = -2.0
	AudioBus.apply(cfg)
	_nearf(AudioBus.master_db(), 0.0, 0.001, "再 apply：Master 回到 0 dB（幂等）")

	# ---------------------------------------------------------------- 3) Sfx 路由
	_section("3) Sfx 池路由与逐声音量")
	await Sfx.setup(host, cfg)
	_ok(Sfx.is_ready(), "Sfx.setup 完成（音色库建好）")
	_eqi(Sfx.pool_size(), 24, "播放池 = 24 路（AudioConfig.polyphony 默认值）")
	var bad_bus := 0
	for i in Sfx.pool_size():
		if Sfx.player_bus(i) != "Sfx":
			bad_bus += 1
	_eqi(bad_bus, 0, "24 路池播放器全部在 Sfx 总线上")
	_eqi(Sfx.bank_size(), 28, "音色库 28 个音色")

	# 逐声音量里不能含 master_db —— 它在总线上；含了就是算两遍
	Sfx.set_master_db(-3.0)
	_nearf(AudioBus.master_db(), -3.0, 0.001, "Sfx.set_master_db 立刻写到 Master 总线")
	_nearf(Sfx.volume_db_of("hit_light"), cfg.combat_db + (-1.0), 0.001, "hit_light 逐声 dB = combat_db + 规格 dB（不含总音量）")
	_nearf(Sfx.volume_db_of("parry"), cfg.parry_db + 0.0, 0.001, "parry 逐声 dB = parry_db + 规格 dB")
	_nearf(Sfx.volume_db_of("no_such_id"), 0.0, 0.001, "未知 id 的逐声 dB = 0")
	Sfx.set_master_db(0.0)
	_nearf(AudioBus.master_db(), 0.0, 0.001, "总音量复位回 0 dB")

	# ---------------------------------------------------------------- 4) Bgm 路由
	_section("4) Bgm 路由与不重复计音量")
	Bgm.setup(host, cfg)
	# 注意：真实游戏里淡入淡出靠 Main._process 每帧调 Bgm.tick()，这里自己驱动
	Bgm.play("map", 0.1)
	var t := await _wait_bgm("map", true, 120)
	_ok(Bgm.is_playing("map"), "大地图曲已起播（%d 帧）" % t)
	for i in 15:                # 等 0.1 s 的淡入走完（没有 Main，得自己驱动 Bgm.tick）
		Bgm.tick(1.0 / 60.0)
		await process_frame
	_eqs(Bgm.bus_of("map"), "Music", "Bgm 播放器挂在 Music 总线上")
	_nearf(Bgm.db_of("map"), cfg.bgm_map_db, 0.2, "播放器上只留单曲偏移 bgm_map_db")
	_nearf(AudioBus.music_db(), cfg.bgm_db, 0.001, "bgm_db 只在 Music 总线上算一次（不会两边都算）")
	Bgm.stop(0.1)
	t = await _wait_bgm("map", false, 120)
	_ok(not Bgm.is_playing("map"), "Bgm.stop() 停掉音乐（%d 帧）" % t)

	# ---------------------------------------------------------------- 5) duck
	_section("5) duck：临时压低音乐")
	var ducks0 := int(AudioBus.stats()["ducks"])
	AudioBus.duck(cfg.fanfare_duck_db, 0.4)
	_nearf(AudioBus.music_db(), cfg.bgm_db + cfg.fanfare_duck_db, 0.001, "duck(-5) 后音乐正好低 5 dB")
	_eqi(int(AudioBus.stats()["ducks"]) - ducks0, 1, "duck 计入 stats")
	await _wait_frames(30)
	_nearf(AudioBus.music_db(), cfg.bgm_db, 0.001, "0.4 s 后自动恢复到 bgm_db")
	_nearf(AudioBus.duck_db(), 0.0, 0.001, "恢复后 duck_db 归零")
	var ducks1 := int(AudioBus.stats()["ducks"])
	AudioBus.duck(3.0, 0.5)
	_eqi(int(AudioBus.stats()["ducks"]) - ducks1, 0, "正增益被拒（这里不提供放大器）")
	_nearf(AudioBus.music_db(), cfg.bgm_db, 0.001, "被拒的 duck 没有改音量")
	AudioBus.duck(-4.0, 0.0)
	_eqi(int(AudioBus.stats()["ducks"]) - ducks1, 0, "时长为 0 的 duck 被拒")

	var ducks2 := int(AudioBus.stats()["ducks"])
	Sfx.play("order")
	_eqi(int(AudioBus.stats()["ducks"]) - ducks2, 1, "扇子音 order 自动触发 duck")
	_nearf(AudioBus.music_db(), cfg.bgm_db + cfg.fanfare_duck_db, 0.001, "扇子音期间音乐被压低")
	await _wait_frames(110)
	_nearf(AudioBus.music_db(), cfg.bgm_db, 0.001, "%.1f s 后音乐自动恢复" % cfg.fanfare_duck_time)
	var ducks3 := int(AudioBus.stats()["ducks"])
	Sfx.play("hit_light")
	_eqi(int(AudioBus.stats()["ducks"]) - ducks3, 0, "普通音（hit_light）不触发 duck")
	_nearf(AudioBus.music_db(), cfg.bgm_db, 0.001, "普通音期间音乐不受影响")

	# ---------------------------------------------------------------- 6) 静音语义
	_section("6) 静音：增益淡出，不是总线静音")
	var plays0 := Sfx.total_plays()
	Sfx.set_muted(true)
	_ok(Sfx.is_muted(), "set_muted(true) 生效")
	_ok(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Music 总线没有被总线静音（走增益淡出）")
	_ok(not AudioServer.is_bus_mute(0), "Master 总线没有被总线静音")
	Sfx.play("hit_light")
	_eqi(Sfx.total_plays(), plays0, "静音期间 play() 直接丢弃，不计数、不压低音乐")
	Sfx.set_muted(false)
	_ok(not Sfx.is_muted(), "取消静音")

	# ---------------------------------------------------------------- 汇总
	host.queue_free()
	await process_frame
	print("[音频总线] 断言 %d 项通过 / %d 项失败" % [n_ok, fails.size()])
	if fails.is_empty():
		print("[音频总线] PASS：总线布局 / 路由 / 写回 / duck / 静音全部正常")
		quit(0)
	else:
		for f in fails:
			print("[音频总线] 失败项：%s" % String(f))
		print("[音频总线] FAIL：%d 项未通过" % fails.size())
		quit(1)

# ------------------------------------------------------------------ 小工具

func _section(title: String) -> void:
	print("[音频总线] ---- %s" % title)

func _ok(cond: bool, msg: String) -> void:
	if cond:
		n_ok += 1
		print("[音频总线]   ✓ %s" % msg)
	else:
		fails.append(msg)
		print("[音频总线]   ✗ %s" % msg)

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

func _nearf(got: float, want: float, tol: float, msg: String) -> void:
	if absf(got - want) <= tol:
		_ok(true, msg)
	else:
		_ok(false, "%s（实际 %.3f，期望 %.3f）" % [msg, got, want])

func _wait_frames(n: int) -> void:
	for i in n:
		await process_frame

## 等某首曲子的播放状态翻转（同时替 Main 驱动 Bgm.tick —— 没有 Main 的检查里不能只等帧）
func _wait_bgm(id: String, want_playing: bool, max_frames: int) -> int:
	for i in max_frames:
		Bgm.tick(1.0 / 60.0)
		await process_frame
		if Bgm.is_playing(id) == want_playing:
			return i + 1
	return max_frames