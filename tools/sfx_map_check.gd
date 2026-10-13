## =============================================================================
##  sfx_map_check —— 大地图音效联调自检（**不参与游戏运行**，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/sfx_map_check.gd
##
##  做三件事：
##    1) 真的启动 Main.tscn（完整程序化生成 + 音效合成）
##    2) 下达一次行军命令 → 检查"行军号角"与"行军马蹄"是否响起
##    3) 命令 AI 部队靠近并触发遭遇 → 检查"遭遇提示音"
##
##  退出码 0 = 关键音效全部触发过；1 = 有缺失
## =============================================================================
extends SceneTree

const KEY_IDS := ["order", "hoof_a", "hoof_b", "encounter"]

var main: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	# Main._ready() 是协程（生成地形 + 合成音效），等它就绪。
	# 判据用 gen_done（程序化生成**彻底**结束，time / view / hover 都已经装配好）——
	# 只判「data / player 非空」是不够的：那两样在生成中途就好了，而 time 要到收尾才建，
	# 此时下 main.time.order_move() 会抛 "Nonexistent function in base 'Nil'"，协程静默死掉、
	# 进程永不退出（门禁里表现为一步挂到超时）。
	var guard := 0
	while guard < 6000:
		guard += 1
		await process_frame
		if main.gen_done and main.time != null and Sfx.is_ready():
			break
	if not main.gen_done or main.time == null or not Sfx.is_ready():
		print("[大地图联调] FAIL：等待就绪超时（%d 帧）" % guard)
		quit(1)
		return
	if not Sfx.cfg().enabled:
		# 音效被 AudioConfig.enabled=false 关掉时既不合成也不播放，本自检无从判定：
		# 明确报 SKIP（退出码 0），而不是既不说"通过"也不说"失败"地留个假象。
		print("[大地图联调] SKIP：AudioConfig.enabled = false（音效已关闭），本次联调不适用")
		main.free()
		quit(0)
		return
	print("[大地图联调] 就绪：等待 %d 帧 / 音效库 %d 个音色 / 部队 %s" % [
		guard, SfxSynth.ids().size(), str(main.player.party_name)])
	Sfx.reset_counts()
	# ---- 行军命令：号角 + 马蹄 ----
	var p0 := Vector2(main.player.position.x, main.player.position.z)
	var goal := Vector2(p0.x + 160.0, p0.y + 120.0)
	main.time.order_move(goal)
	print("[大地图联调] 下达行军命令：%s -> %s（moving=%s）" % [str(p0.round()), str(goal.round()), str(main.player.moving)])
	for i in 420:                     # 7 秒行军（fixed-fps 60）
		await physics_frame
		# 无头运行时鼠标恒在 (0,0)，会一直触发"屏幕边缘平移"把镜头推走 —— 手动按住镜头
		if main.camera_rig != null:
			main.camera_rig.pan_offset = Vector2.ZERO
		if i % 60 == 0:
			_dbg(i)
		if not main.player.moving:
			print("[大地图联调] 第 %d 帧抵达目的地，世界时间随之暂停" % i)
			break
	# ---- 遭遇：把最近的 AI 部队挪到玩家身边，再下达一次行军让时间流动起来 ----
	var nearest: AIParty = null
	var bd := 1e20
	for a in main.ai_parties:
		if a == null or not is_instance_valid(a):
			continue
		var d: float = a.distance_to_party(main.player)
		if d < bd:
			bd = d
			nearest = a
	if nearest != null:
		nearest.position = main.player.position + Vector3(6.0, 0.0, 0.0)
		main.encounters.cooldowns.clear()
		main.encounters.enabled = true
		var p1 := Vector2(main.player.position.x, main.player.position.z)
		main.time.order_move(Vector2(p1.x + 60.0, p1.y + 60.0))
		for i in 120:
			await physics_frame
			if main.camera_rig != null:
				main.camera_rig.pan_offset = Vector2.ZERO
			if main.hud.is_encounter_open():
				print("[大地图联调] 第 %d 帧弹出遭遇对话框：%s" % [i, nearest.party_name])
				break
	_check()
	main.free()

func _dbg(i: int) -> void:
	var lp := Vector2(main.player.position.x, main.player.position.z)
	var cam_pos: Vector3 = main.camera_rig.cam.global_position if (main.camera_rig != null and main.camera_rig.cam != null) else Vector3.ZERO
	var counts: Dictionary = Sfx.counts()
	print("    [dbg %3d] moving=%s paused=%s hoof_t=%.3f 距相机=%.1f 半径=%.1f 蹄声=%d" % [
		i, str(main.player.moving), str(main.time.game_paused), float(main.player._hoof_t),
		lp.distance_to(Vector2(cam_pos.x, cam_pos.z)), float(Sfx.cfg().hoof_audible_range),
		int(counts.get("hoof_a", 0)) + int(counts.get("hoof_b", 0))])

func _check() -> void:
	var counts := Sfx.counts()
	var rows: Array = counts.keys()
	rows.sort()
	print("[大地图联调] 各音效触发次数：")
	for k in rows:
		print("      %-14s %d" % [String(k), int(counts[k])])
	var missing: Array = []
	for id in KEY_IDS:
		if int(counts.get(id, 0)) == 0:
			missing.append(id)
	if missing.is_empty():
		print("[大地图联调] PASS：行军号角 / 马蹄 / 遭遇提示音全部触发过")
		quit(0)
	else:
		print("[大地图联调] FAIL：以下音效没被触发过 -> %s" % str(missing))
		quit(1)
