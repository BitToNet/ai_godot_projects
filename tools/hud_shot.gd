## =============================================================================
##  hud_shot —— 真实渲染截图（**不参与游戏运行**，只在命令行用；**必须开窗口跑**）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --path <工程> --fixed-fps 60 \
##        --script res://tools/hud_shot.gd -- --out <输出目录>
##    （不要加 --headless：headless 没有渲染，抓到的图是空的）
##
##  为什么需要它：UI 拆分 / 改布局这类改动，「能编译 + 接口断言全过」并不等于
##  「界面没塌」。脚本跑一遍真实主场景，截三张图供人眼确认：
##    hud_loading.png —— 开场加载遮罩（必须铺满全屏：它曾因只设 anchors 而缩成 0×0）
##    hud_normal.png  —— 正常大地图（左上信息栏 / 右上小地图 / 左下说明 / 右下性能）
##    hud_dialog.png  —— 遭遇对话框打开 + 提示条（第四轮 4c 起是四行选项表：
##                       验证遮挡层级、按钮布局、灰行与理由是否真的画出来了）
##
##  退出码：0 = 三张图都写出成功；1 = 有失败
## =============================================================================
extends SceneTree

const SCENE := "res://scenes/Main.tscn"
const WAIT_LIMIT := 6000
const SETTLE_FRAMES := 40

var _out_dir := "user://"
var _main: Node
var _fails: Array[String] = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			_out_dir = args[i + 1]
	_run()

func _run() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		print("FAIL：加载不了 %s" % SCENE)
		quit(1)
		return
	var main := packed.instantiate()
	_main = main
	get_root().add_child(main)

	# 先拍加载遮罩：生成要 6 秒，这几帧正是玩家看到遮罩的时刻。
	# 它曾经缩成 0×0（只调 set_anchors_preset 会保留当前矩形）—— 黑底完全看不见，
	# mouse_filter=STOP 也挡不住点击，而这条路径普通截图（生成完才拍）覆盖不到。
	for i in 8:
		await process_frame
	_shot("hud_loading.png")

	var waited := 0
	while not main.gen_done and waited < WAIT_LIMIT:
		await process_frame
		waited += 1
	if not main.gen_done:
		print("FAIL：等待 gen_done 超时（%d 帧）" % WAIT_LIMIT)
		quit(1)
		return
	for i in SETTLE_FRAMES:
		await process_frame

	_shot("hud_normal.png")

	# 第二张：遭遇对话框 + 提示条同时在场（验证层级：提示条应盖在对话框之上）。
	# 第四轮 4c 起遭遇框是**数据驱动的四行选项表**，所以这里直接取生产代码
	# EncounterSystem.options() 的真实输出 —— 截出来的就是玩家会看到的那张表
	# （挑 78 人的大盗：买路买得起、索要唬不住，一屏里既有亮行也有灰行与理由）。
	var foe := AIParty.new()
	foe.kind = AIParty.Kind.BANDIT
	foe.party_name = "大盗"
	foe.faction_id = -1
	foe.troop_count = 78
	foe.boss_title = "大盗头目"
	main.encounters.current = foe
	main.hud.show_encounter("遭遇 大盗",
		"强盗团伙 · 无阵营\n敌方首领：大盗头目\n兵力：78 人     你的兵力：37 人\n\n时间已暂停 —— 请决定行动。",
		Color(0.92, 0.86, 0.60),
		main.encounters.options())
	main.hud.show_toast("截图验证：提示条与遭遇框同时在场", 30.0)
	for i in 10:
		await process_frame
	_dump()
	_shot("hud_dialog.png")

	# 收尾：主动清理，否则会打印「resources still in use at exit」而被门禁的 ERROR 断言判失败
	main.encounters.current = null
	foe.free()
	main.hud.hide_encounter()
	main.free()

	print("")
	if _fails.is_empty():
		print("PASS：三张截图已写出到 %s" % _out_dir)
		quit(0)
	else:
		print("FAIL：%s" % "; ".join(_fails))
		quit(1)

## 把关键控件的实际 rect 打出来。截图只能看出「不对劲」，数字才能定位是谁没被撑开。
func _dump() -> void:
	var d: Control = _main.hud.dialog
	var cc: Control = d.get_child(1)
	var panel: Control = cc.get_child(0)
	print("[rect] viewport=%s" % get_root().size)
	print("[rect] 对话框      size=%s pos=%s" % [d.size, d.position])
	print("[rect] 遮罩ColorRect size=%s (应为 viewport 大小)" % (d.get_child(0) as Control).size)
	print("[rect] Center      size=%s pos=%s" % [cc.size, cc.position])
	print("[rect] 面板        size=%s pos=%s" % [panel.size, panel.position])
	print("[rect] 提示条      size=%s pos=%s" % [_main.hud._toast.size, _main.hud._toast.position])

func _shot(file_name: String) -> void:
	var dir := _out_dir
	if not dir.ends_with("/") and not dir.ends_with("\\"):
		dir += "/"
	var path := dir + file_name
	var img := get_root().get_texture().get_image()
	if img == null:
		_fails.append("%s：get_image() 返回 null（是不是加了 --headless？）" % file_name)
		return
	var err := img.save_png(path)
	if err != OK:
		_fails.append("%s：save_png 失败（错误码 %d）" % [file_name, err])
		return
	print("  [ok]   %s  %dx%d" % [file_name, img.get_width(), img.get_height()])
