## =============================================================================
##  bgm_check —— 背景音乐联调自检（**不参与游戏运行**，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/bgm_check.gd
##
##  检查四件事，每件都真的驱动一次游戏流程（不是只看文件在不在）：
##    1) 两首 Ogg 都能 load，且循环开关是开的
##    2) Loading 收起后大地图主题真的开始响（淡入完成，播放器 playing）
##    3) 触发一场真实遭遇 → 选"攻击"进 Boss 战：切到战斗曲；结算后淡回大地图主题
##    4) M 键静音（Sfx.set_muted）能把音乐压下去、取消后恢复播放
##
##  退出码 0 = 全部通过；1 = 音频缺失或状态不对
## =============================================================================
extends SceneTree

var main: Node
var fails: Array = []

func _initialize() -> void:
	_watchdog()          # 兜底协程：脚本中途报错也不会让引擎挂死在那儿
	_run()

## 看门狗：headless 下 --fixed-fps 60 让帧数跑得比真实时间快，7200 帧远超本检查所需
## （正常全程 1000 帧以内）。只在 _run() 异常中断、没走到 quit() 时才可能触发。
func _watchdog() -> void:
	for i in 7200:
		await process_frame
	print("[BGM联调] FAIL：看门狗超时（7200 帧未跑完，多半是脚本中途报错）")
	quit(1)

func _run() -> void:
	_check_assets()
	# ---- 启动游戏（完整程序化生成 + 音效合成 + BGM 起播）----
	var scene: PackedScene = load("res://scenes/Main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	var guard := 0
	while guard < 6000:
		guard += 1
		await process_frame
		if main.gen_done and main.data != null and main.player != null and Bgm.is_ready():
			break
	if main.data == null or main.player == null or not Bgm.is_ready():
		print("[BGM联调] FAIL：等待就绪超时（%d 帧）" % guard)
		quit(1)
		return
	print("[BGM联调] 就绪：等待 %d 帧 / 当前曲目 %s / 音量 %.1f dB（大地图 %+.1f / 战斗 %+.1f）/ 淡入 %.1f s 切战斗 %.1f s 回地图 %.1f s" % [
		guard, Bgm.current(), main.audio.bgm_db, main.audio.bgm_map_db, main.audio.bgm_battle_db,
		main.audio.bgm_fade_in, main.audio.bgm_fade_battle, main.audio.bgm_fade_map])

	# ---- 1) 大地图主题淡入 ----
	if await _wait_playing("map", 240):
		_pass("大地图主题「山河行旅」已起播")
	else:
		_fail("大地图主题没有起播（current=%s）" % Bgm.current())

	# ---- 2) 静音 / 恢复（M 键走的就是这一对调用）----
	Sfx.set_muted(true)
	if await _wait_silent("map", 180):
		_pass("静音后音乐停止发声")
	else:
		_fail("静音后音乐仍在播放")
	Sfx.set_muted(false)
	if await _wait_playing("map", 180):
		_pass("取消静音后音乐恢复")
	else:
		_fail("取消静音后音乐没有恢复")

	# ---- 3) 遭遇 → 进战斗 → 切战斗曲 ----
	if not await _force_encounter():
		_fail("没能弹出遭遇对话框（无法联调战斗切换）")
	else:
		main._on_encounter_choice("attack")
		var t := 0
		while t < 120 and main.battle == null:
			t += 1
			await physics_frame
		if main.battle == null:
			_fail("选了攻击却没有进入战斗场景")
		else:
			print("[BGM联调] 第 %d 帧进入 Boss 战：%s" % [t, Bgm.current()])
			if await _wait_playing("battle", 240):
				_pass("进入战斗后切到战斗曲「金戈铁马」")
			else:
				_fail("进入战斗后没有切到战斗曲（current=%s）" % Bgm.current())
			# ---- 4) 战斗结束 → 淡回大地图主题 ----
			main.battle._end_battle("win")
			var t2 := 0
			while t2 < 300 and main.battle != null:
				t2 += 1
				await physics_frame
			print("[BGM联调] 第 %d 帧结算完成：%s" % [t2, Bgm.current()])
			if await _wait_playing("map", 300):
				_pass("战斗结束后淡回大地图主题")
			else:
				_fail("战斗结束后没有回到大地图主题（current=%s）" % Bgm.current())

	# ---- 5) stop()：整首停掉（回标题界面那种用法）----
	Bgm.stop(0.2)
	if await _wait_silent("map", 120):
		_pass("stop() 能把音乐整首停下")
	else:
		_fail("stop() 之后音乐还在响")
	if Bgm.current() == "":
		_pass("stop() 之后 current() 回到空")
	else:
		_fail("stop() 之后 current() 应为空，实际是 %s" % Bgm.current())

	# ---- 汇总 ----
	print("[BGM联调] BGM 切换次数：%s" % str(Bgm.counts()))
	main.free()
	if fails.is_empty():
		print("[BGM联调] PASS：两首曲目加载 / 起播 / 战斗切换 / 静音全部正常")
		quit(0)
	else:
		for f in fails:
			print("[BGM联调] 失败项：%s" % String(f))
		print("[BGM联调] FAIL：%d 项未通过" % fails.size())
		quit(1)

# ------------------------------------------------------------------ 资源检查

func _check_assets() -> void:
	print("[BGM联调] 曲目资源：")
	for id in Bgm.TRACKS.keys():
		var path: String = Bgm.TRACKS[id]
		if not ResourceLoader.exists(path):
			_fail("音频缺失：%s" % path)
			print("      %-10s 缺失 %s" % [String(id), path])
			continue
		var stream: AudioStream = load(path)
		if stream == null:
			_fail("音频加载失败：%s" % path)
			continue
		var looping := false
		if stream is AudioStreamOggVorbis:
			looping = (stream as AudioStreamOggVorbis).loop
		elif stream is AudioStreamWAV:
			looping = (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
		var kb := 0.0
		if FileAccess.file_exists(path):
			kb = float(FileAccess.get_file_as_bytes(path).size()) / 1024.0
		print("      %-10s %6.1f 秒  %7.0f KB  循环=%s  %s" % [
			String(id), stream.get_length(), kb, str(looping), path])
		if not looping:
			_fail("%s 没有开启循环（导入设置里勾上 loop）" % path)

# ------------------------------------------------------------------ 小工具

func _pass(msg: String) -> void:
	print("[BGM联调]   ✓ %s" % msg)

func _fail(msg: String) -> void:
	fails.append(msg)
	print("[BGM联调]   ✗ %s" % msg)

## 等某一首曲目真正进入播放状态（淡入完成 + 播放器 playing）
func _wait_playing(id: String, max_frames: int) -> bool:
	for i in max_frames:
		await physics_frame
		if Bgm.current() == id and Bgm.is_playing(id):
			return true
	return false

## 等某一首曲目彻底停下来（静音淡出完成）
func _wait_silent(id: String, max_frames: int) -> bool:
	for i in max_frames:
		await physics_frame
		if not Bgm.is_playing(id):
			return true
	return false

## 把最近的 AI 部队挪到玩家身边，再下一次行军令让世界时间流动，等遭遇对话框弹出
func _force_encounter() -> bool:
	var nearest: AIParty = null
	var bd := 1e20
	for a in main.ai_parties:
		if a == null or not is_instance_valid(a):
			continue
		var d: float = a.distance_to_party(main.player)
		if d < bd:
			bd = d
			nearest = a
	if nearest == null:
		return false
	nearest.position = main.player.position + Vector3(6.0, 0.0, 0.0)
	main.cooldowns.clear()
	main.encounters_enabled = true
	var p := Vector2(main.player.position.x, main.player.position.z)
	main.time.order_move(Vector2(p.x + 60.0, p.y + 60.0))
	for i in 240:
		await physics_frame
		# 无头运行时鼠标恒在 (0,0)，会一直触发"屏幕边缘平移"把镜头推远 —— 手动按住镜头
		if main.camera_rig != null:
			main.camera_rig.pan_offset = Vector2.ZERO
		if main.hud.is_encounter_open():
			print("[BGM联调] 第 %d 帧弹出遭遇对话框：%s" % [i, nearest.party_name])
			return true
	return false
