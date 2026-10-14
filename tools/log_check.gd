## =============================================================================
##  log_check —— 分级日志（Log）的契约自检（**不参与游戏运行**）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/log_check.gd
##
##  为什么需要它：日志级别本身没什么可错的，但**两条周边契约**一破就是事故：
##    1) 默认级别必须是 INFO —— tools/run_checks.ps1 与 gen_fingerprint 解析的输出
##       都按默认级别跑，默认一变高，门禁就「因为看不见」而变绿；
##    2) ERROR 必须仍然以 "ERROR: " 开头走 stderr —— 门禁靠这个前缀兜底抓失败。
##  第 2 条在进程内抓不到 stdout/stderr，所以直接读 Log.gd 的源码文本对字面量下断言。
##
##  退出码：0 = 全部通过；1 = 有断言失败
## =============================================================================
extends SceneTree

var _fails: Array[String] = []
var _total: int = 0

func _initialize() -> void:
	_run()

func _ok(cond: bool, what: String) -> void:
	_total += 1
	if not cond:
		_fails.append(what)

func _run() -> void:
	# ---- 1) 级别表与全序
	_ok(Log.NAMES.size() == 4, "级别表有 4 档（%d）" % Log.NAMES.size())
	_ok(Log.Level.DEBUG < Log.Level.INFO and Log.Level.INFO < Log.Level.WARN and Log.Level.WARN < Log.Level.ERROR,
		"级别是全序 DEBUG < INFO < WARN < ERROR")

	# ---- 2) 默认级别必须是 INFO（门禁按默认级别解析输出）
	_ok(Log.level == Log.Level.INFO, "默认级别是 INFO（当前 %s）" % Log.NAMES[Log.level])

	# ---- 3) 命令行解析
	var r1: Array = Log.resolve_level(PackedStringArray(), "")
	_ok(r1[0] == Log.Level.INFO and String(r1[1]) == "", "无参数无环境变量 ⇒ INFO 且无告警")
	var r2: Array = Log.resolve_level(PackedStringArray(["--log-level=debug"]), "")
	_ok(r2[0] == Log.Level.DEBUG and String(r2[1]) == "", "--log-level=debug ⇒ DEBUG")
	var r3: Array = Log.resolve_level(PackedStringArray(["log-level=WARN"]), "")
	_ok(r3[0] == Log.Level.WARN, "log-level=WARN（无前导 --、大写）⇒ WARN")
	var r4: Array = Log.resolve_level(PackedStringArray(["--log-level=warning"]), "")
	_ok(r4[0] == Log.Level.WARN, "warning 是 warn 的别名")
	var r5: Array = Log.resolve_level(PackedStringArray(["--log-level=error"]), "")
	_ok(r5[0] == Log.Level.ERROR, "--log-level=error ⇒ ERROR")

	# ---- 4) 不认识的值：回退 INFO 但必须留下说明（不静默）
	var r6: Array = Log.resolve_level(PackedStringArray(["--log-level=verbose"]), "")
	_ok(r6[0] == Log.Level.INFO and String(r6[1]) != "", "不认识的级别回退 INFO 且带说明（%s）" % str(r6[1]))
	var r7: Array = Log.resolve_level(PackedStringArray(), "??")
	_ok(r7[0] == Log.Level.INFO and String(r7[1]) != "", "环境变量不合法也回退 INFO 且带说明")

	# ---- 5) 命令行优先于环境变量
	var r8: Array = Log.resolve_level(PackedStringArray(["--log-level=debug"]), "error")
	_ok(r8[0] == Log.Level.DEBUG, "命令行优先于环境变量（得 %s）" % Log.NAMES[r8[0]])

	# ---- 6) 环境变量单独生效
	var r9: Array = Log.resolve_level(PackedStringArray(), "error")
	_ok(r9[0] == Log.Level.ERROR and String(r9[1]) == "", "环境变量 WARBAND_LOG=error ⇒ ERROR")
	var r10: Array = Log.resolve_level(PackedStringArray(), "  Debug  ")
	_ok(r10[0] == Log.Level.DEBUG, "环境变量两侧空白与大小写被容忍")

	# ---- 7) setup() 真能改级别，并且改回 INFO 不炸
	Log.setup(PackedStringArray(["--log-level=warn"]))
	_ok(Log.level == Log.Level.WARN, "setup() 生效（当前 %s）" % Log.NAMES[Log.level])
	Log.setup(PackedStringArray())
	_ok(Log.level == Log.Level.INFO, "setup() 无参数时回到 INFO")
	Log.info("[日志] 自检：这一行在 INFO 级别下应当可见")
	Log.debug("[日志] 自检：这一行在 INFO 级别下不应出现（若出现说明级别比较写反了）")
	Log.warn("[日志] 自检：警告前缀")
	# 注意：这里**故意不真的调 Log.error** —— 门禁把输出里的 "ERROR: " 一律记为失败，
	# 所以 ERROR 前缀这条契约改成对源码字面量下断言（见下面第 8 节）。

	# ---- 8) 门禁兜底网：ERROR 前缀必须还在源码里
	var f := FileAccess.open("res://scripts/core/Log.gd", FileAccess.READ)
	_ok(f != null, "能读到 scripts/core/Log.gd")
	if f != null:
		var src := f.get_as_text()
		f.close()
		_ok(src.contains('printerr("ERROR: " + msg)'), "Log.error 仍以 \"ERROR: \" 前缀走 printerr（门禁兜底网未破）")
		_ok(src.contains("static func info(msg: String) -> void:"), "info 接口签名未变")
		_ok(src.contains("enum Level { DEBUG, INFO, WARN, ERROR }"), "级别枚举未变")

	print("")
	if _fails.is_empty():
		print("PASS：分级日志契约全部成立（%d 项断言）" % _total)
		quit(0)
	else:
		print("FAIL：%d/%d 项断言未通过 —— %s" % [_fails.size(), _total, "; ".join(_fails)])
		quit(1)