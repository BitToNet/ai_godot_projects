## =============================================================================
##  visual_shot —— 把大地图截成 PNG（**只在开窗运行时有效**，headless 拿不到画面）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --path <工程> --resolution 1600x900 \
##        --audio-driver Dummy --fixed-fps 60 \
##        --script res://tools/visual_shot.gd -- --tag=before
##    # 输出目录也可显式给（与 hud_shot.gd 同一套写法）：
##    ...--script res://tools/visual_shot.gd -- --out user://shots --tag=after
##
##  ---- 为什么要有这个探针 ----
##  门禁里的 26 项全是数值断言：它们能证明「几何没变、指纹没动、没有报错」，
##  **不能**证明「好不好看」。而观感类改动（环境光 / 雾 / 天空 / 细节贴图）恰恰是
##  「改完不许用眼睛确认」最容易翻车的一类 —— 数值全绿而画面过曝 / 发灰 / 全黑。
##  所以这里把画面固化成 PNG：同一套机位、同一套时间点，前后两张直接对比。
##
##  与 tools/hud_shot.gd 的分工（两个都是开窗截图，别混）：
##    · hud_shot  —— 拍 **UI**：加载遮罩 / 常规 HUD / 遭遇对话框三种状态
##    · visual_shot —— 拍 **世界**：5 组机位×时刻，看地形 / 天空 / 光照 / 雾
##  它俩都不进 tools/run_checks.ps1：门禁必须能在无人值守的 headless 下跑，
##  而 headless 的 DummyRenderingServer 画不出像素。
##
##  ---- 口径（照 perf_probe 的定式，别另起一套）----
##  · 等 main.gen_done 而不是 main._gen_ms（后者置位时收尾协程还在 await）
##  · 关掉音频（--audio-driver Dummy），本探针不出声
##  · 环境变量 WARBAND_MAP_SIZE 由调用方决定；不给就是出货默认的 4096 m
##  · 每张图前把 pan_offset 归零：开窗运行鼠标不在窗口中央，会持续触发屏幕边缘平移
##
##  退出码：0 = 全部写出；1 = 在 headless 下运行（拿不到画面）；2 = 等待生成超时 / 写盘失败
## =============================================================================
extends SceneTree

const SCENE := "res://scenes/Main.tscn"
const OUT_DIR := "user://shots"
## 生成完成的等待上限（帧）：4096 m 图管线实测 23~29 s，--fixed-fps 60 下约 1800 帧
const WAIT_LIMIT := 12000
## 生成完成后先等几帧：Loading 遮罩收场、地形首块建好、天空辐照度算出来
const SETTLE_FRAMES := 60
## 换完机位 / 时间之后再等几帧：SSAO、glow、阴影贴图都要跨一两帧才稳定
const WARM_FRAMES := 8

## 机位表：{name, height(米), pitch(俯角°), yaw, hour(游戏内小时)}
## 挑的都是「玩家真会看到的那几个视角」：
##   wide   —— 默认高度 90 m：日常行军视角（俯角 55°，画面顶端在地平线下 29°）
##   near   —— 压到最低 20 m：俯角 26°，画面顶端正好落在海平线上，天空带最宽
##   sky    —— 手动压平到俯角 12°：画面顶端在地平线上 14°，**唯一能看见天空和云**的机位。
##            没有它，天空 Shader 的改动在这套探针里看都看不到（默认俯角下天空占 0 像素）
##   dusk / night —— 同一机位换时间，看天色 / 环境光 / 灯火
const SHOTS := [
	{"name": "wide_noon", "height": 90.0, "pitch": 55.0, "yaw": 0.0, "hour": 12.0},
	{"name": "near_noon", "height": 20.0, "pitch": 26.0, "yaw": 0.0, "hour": 12.0},
	{"name": "sky_noon", "height": 24.0, "pitch": 12.0, "yaw": 40.0, "hour": 12.0},
	{"name": "sky_dusk", "height": 24.0, "pitch": 12.0, "yaw": 250.0, "hour": 17.9},
	{"name": "wide_dusk", "height": 90.0, "pitch": 55.0, "yaw": 0.0, "hour": 19.4},
	{"name": "wide_night", "height": 90.0, "pitch": 55.0, "yaw": 0.0, "hour": 23.0},
	{"name": "near_dawn", "height": 24.0, "pitch": 28.0, "yaw": 135.0, "hour": 6.2},
]

var main: Node
var tag: String = "shot"
var out_abs: String = ""
var out_uri: String = OUT_DIR

func _initialize() -> void:
	_run()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("[截图] FAIL：当前是 headless（DummyRenderingServer 画不出像素）。")
		print("[截图] 去掉 --headless 再跑；本探针只在开窗运行时有效。")
		quit(1)
		return

	var out_dir := OUT_DIR
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out_dir = String(args[i + 1])
		elif String(args[i]).begins_with("--tag="):
			tag = String(args[i]).substr(6)

	out_abs = ProjectSettings.globalize_path(out_dir)
	out_uri = out_dir
	if DirAccess.make_dir_recursive_absolute(out_abs) != OK and not DirAccess.dir_exists_absolute(out_abs):
		print("[截图] FAIL：无法创建输出目录 %s" % out_abs)
		quit(2)
		return

	var scene: PackedScene = load(SCENE)
	if scene == null:
		print("[截图] FAIL：加载不了 %s" % SCENE)
		quit(2)
		return
	main = scene.instantiate()
	var ac := AudioConfig.new()
	ac.enabled = false
	main.audio = ac
	main.config = MapConfig.new()
	root.add_child(main)

	var guard := 0
	while guard < WAIT_LIMIT:
		guard += 1
		await process_frame
		if main.gen_done:
			break
	if not main.gen_done:
		print("[截图] FAIL：等待地图生成超时（%d 帧）" % guard)
		quit(2)
		return
	for _i in SETTLE_FRAMES:
		await process_frame

	var vp := root.get_visible_rect().size
	print("[截图] 环境：种子 %d / 世界 %.0f m / 生成 %d ms / 植被 %d / AI 部队 %d / 视口 %d×%d" % [
		main.config.map_seed, main.config.map_size, int(main._gen_ms),
		main.vegetation.total(), main.ai_parties.size(), int(vp.x), int(vp.y)])

	var written: Array[String] = []
	for shot in SHOTS:
		var path := await _shot(shot)
		if path == "":
			print("[截图] FAIL：%s 写盘失败" % String(shot["name"]))
			main.free()
			quit(2)
			return
		written.append(path)
	print("[截图] PASS：写出 %d 张 -> %s" % [written.size(), out_abs])
	for p in written:
		print("        %s" % p)
	# 主动清理：不 free 的话退出时会打印「N ObjectDB instances were leaked at exit」，
	# 那行按门禁口径等同 ERROR（hud_shot.gd 收尾处同样 free）
	main.free()
	quit(0)

func _shot(shot: Dictionary) -> String:
	var name := "%s_%s" % [tag, String(shot["name"])]
	# 时间：先定时刻再 _apply()，否则第一帧还是上一个时刻的天色
	main.day_night.time_of_day = float(shot["hour"]) / 24.0
	main.day_night._apply()
	# 机位：CameraRig._process 每帧末尾都会 _apply()，所以改完字段等帧即可
	main.camera_rig.zoom_height = float(shot["height"])
	main.camera_rig.pitch_deg = float(shot["pitch"])
	main.camera_rig.yaw = deg_to_rad(float(shot["yaw"]))
	for _i in WARM_FRAMES:
		# 开窗运行时针会一直往屏幕边缘推镜头，这里每帧按住
		main.camera_rig.pan_offset = Vector2.ZERO
		await process_frame
	main.camera_rig.pan_offset = Vector2.ZERO
	main.camera_rig._apply()
	await process_frame
	RenderingServer.force_draw(false)
	var img := root.get_texture().get_image()
	if img == null or img.is_empty():
		return ""
	var path := "%s/%s.png" % [out_uri, name]
	if img.save_png(path) != OK:
		return ""
	var st := _stats(img)
	print("[截图] %-18s %4.0f m / 俯角 %2.0f° / %4.1f 时 -> %s.png（%d×%d）" % [
		String(shot["name"]), float(shot["height"]), float(shot["pitch"]),
		float(shot["hour"]), name, img.get_width(), img.get_height()])
	# 亮度/饱和度统计：截图只能看出「不对劲」，数字才能挡住「过曝 / 发灰」这类回归。
	# 均值抬 15% 或 5% 分位压到近黑，都是肉眼扫一眼容易放过的量级。
	print("        亮度 均 %.1f / p05 %.1f / p50 %.1f / p95 %.1f   饱和 %.2f   近黑 %.1f%%   近白 %.1f%%" % [
		st["luma_mean"], st["luma_p05"], st["luma_p50"], st["luma_p95"],
		st["sat_mean"], st["dark_pct"], st["blown_pct"]])
	return ProjectSettings.globalize_path(path)

## 采样亮度 / 饱和度分布（每 3 像素取一个：1600×900 下约 16 万样本，够稳又快）
func _stats(img: Image) -> Dictionary:
	# 视口贴图可能是 HDR 浮点格式（线性空间）；先转回 sRGB 再谈「亮度」
	var fmt := img.get_format()
	var linear := fmt == Image.FORMAT_RGBAH or fmt == Image.FORMAT_RGBAF \
			or fmt == Image.FORMAT_RGBH or fmt == Image.FORMAT_RGBF
	var lumas := PackedFloat32Array()
	var sum_s := 0.0
	var sum_l := 0.0
	var dark := 0
	var blown := 0
	var n := 0
	var y := 0
	while y < img.get_height():
		var x := 0
		while x < img.get_width():
			var c := img.get_pixel(x, y)
			if linear:
				c = c.linear_to_srgb()
			var l := c.get_luminance() * 255.0
			lumas.append(l)
			sum_l += l
			sum_s += c.s
			if l < 8.0:
				dark += 1
			elif l > 247.0:
				blown += 1
			n += 1
			x += 3
		y += 3
	if n == 0:
		return {"luma_mean": 0.0, "luma_p05": 0.0, "luma_p50": 0.0, "luma_p95": 0.0,
			"sat_mean": 0.0, "dark_pct": 0.0, "blown_pct": 0.0}
	lumas.sort()
	return {
		"luma_mean": sum_l / float(n),
		"luma_p05": lumas[int(float(n) * 0.05)],
		"luma_p50": lumas[n / 2],
		"luma_p95": lumas[mini(int(float(n) * 0.95), n - 1)],
		"sat_mean": sum_s / float(n),
		"dark_pct": 100.0 * float(dark) / float(n),
		"blown_pct": 100.0 * float(blown) / float(n),
	}
