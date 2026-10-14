## =============================================================================
##  Log —— 分级日志（第六轮 ⑦）
##
##  为什么要有它：工程里原本 21 处裸 print()，正式运行时没法降噪（生成 / 日结 / 读档全在刷屏），
##  也没法把「调试信息」和「真错误」分开。这里给四个级别：
##
##      DEBUG < INFO < WARN < ERROR
##
##  · 文本仍按本工程既有约定自带 [标签] 前缀（如 "[日结] …"），所以**迁移是逐字保真的**：
##    原来 print("[日结] …") 现在写 Log.info("[日结] …")，屏幕上一字不差。
##  · ERROR **必须**以 "ERROR: " 开头并走 printerr —— tools/run_checks.ps1 用
##    "ERROR: / SCRIPT ERROR / Parse Error" 兜底抓失败，不能把这张网漏掉。
##  · 级别来源（命令行优先于环境变量，默认 INFO）：
##        godot --headless --path . --script res://tools/xxx.gd -- --log-level=debug
##        set WARBAND_LOG=debug
##  · 被工具解析的输出（例如 Main 的「地图生成完成」那一行）**故意不走这里**，
##    免得有人把日志级别调高就把门禁的解析对象一起静音了。
## =============================================================================
class_name Log
extends RefCounted

enum Level { DEBUG, INFO, WARN, ERROR }

const NAMES := ["debug", "info", "warn", "error"]

static var level: int = Level.INFO

## 解析一个级别名；不认识返回 null（由调用方决定如何回退）
static func parse_level(s: String) -> Variant:
	var v := s.strip_edges().to_lower()
	if v == "warning":
		v = "warn"
	var i := NAMES.find(v)
	return null if i < 0 else i

## 从命令行参数 + 环境变量定级别，返回 [级别, 问题说明]（说明为空 = 一切正常）。
## 纯函数：tools/log_check.gd 直接对它下断言，不必去抓 stdout。
static func resolve_level(args: PackedStringArray, env_value: String) -> Array:
	for a in args:
		var s := String(a)
		var v := ""
		if s.begins_with("--log-level="):
			v = s.substr(12)
		elif s.begins_with("log-level="):
			v = s.substr(10)
		else:
			continue
		var p: Variant = parse_level(v)
		if p == null:
			return [Level.INFO, "无法识别的日志级别 %s（回退 info）" % v]
		return [int(p), ""]
	if env_value.strip_edges() != "":
		var p2: Variant = parse_level(env_value)
		if p2 == null:
			return [Level.INFO, "环境变量 WARBAND_LOG=%s 无法识别（回退 info）" % env_value]
		return [int(p2), ""]
	return [Level.INFO, ""]

## 启动时调一次（Main._ready 开头）。解析出问题就如实说，但不改级别语义。
static func setup(args: PackedStringArray) -> void:
	var r := resolve_level(args, OS.get_environment("WARBAND_LOG"))
	level = int(r[0])
	if String(r[1]) != "":
		warn("[日志] " + String(r[1]))

static func debug(msg: String) -> void:
	if level <= Level.DEBUG:
		print("[调试] " + msg)

static func info(msg: String) -> void:
	if level <= Level.INFO:
		print(msg)

static func warn(msg: String) -> void:
	if level <= Level.WARN:
		print("警告：" + msg)

## 错误：走 stderr 且必须以 "ERROR: " 开头（门禁的兜底网依赖这个前缀）
static func error(msg: String) -> void:
	if level <= Level.ERROR:
		printerr("ERROR: " + msg)