## =============================================================================
##  i18n_check —— 「还剩多少硬编码中文」的棘轮（第六轮 ⑥，门禁第 5d 步）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/i18n_check.gd [-- --write-baseline]
##
##  为什么是「棘轮」而不是「迁移完成度」：i18n 起步要能**量**。本工具数的是
##  `scripts/ui/**` 里「含中日韩统一表意文字（U+4E00–U+9FFF）的字符串字面量」条数，
##  基线存 tools/i18n_baseline.json，规则只有一条：**只许变小，不许变大**。
##  新写的界面文案请放进 scripts/core/Strings.gd；确实要调高基线时，显式跑一次
##  `-- --write-baseline` 并在 ROADMAP 变更记录里写清理由（和规模基线同一套规矩）。
##
##  计数口径说明（【推断】级精度，够用即可）：逐字符扫描，单引号/双引号都算，跳过反斜杠转义；
##  只数「字符串里出现过表意文字」的字面量个数，不数出现次数，也不管那串字是给玩家看的
##  还是内部 id。
##
##  退出码：0 = 达标；1 = 有文件超出基线或 Strings.gd 表本身有问题
## =============================================================================
extends SceneTree

const UI_DIR := "res://scripts/ui"
const ALL_DIR := "res://scripts"
const BASELINE_PATH := "res://tools/i18n_baseline.json"
const STRINGS_PATH := "res://scripts/core/Strings.gd"
const MIN_CONSTANTS := 8

var _fails: Array[String] = []
var _total: int = 0
var _write_baseline := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a) == "--write-baseline":
			_write_baseline = true
	_run()

func _ok(cond: bool, what: String) -> void:
	_total += 1
	if not cond:
		_fails.append(what)

func _is_cjk(c: String) -> bool:
	var o := c.unicode_at(0)
	return o >= 0x4E00 and o <= 0x9FFF

## 数一个源文件里「含表意文字的字符串字面量」条数
func _count_cjk_literals(src: String) -> int:
	var n := 0
	var i := 0
	var in_str := false
	var has_cjk := false
	var quote := ""
	while i < src.length():
		var c := src[i]
		if in_str:
			if c == "\\":
				i += 2
				continue
			if c == quote:
				if has_cjk:
					n += 1
				in_str = false
				has_cjk = false
			elif _is_cjk(c):
				has_cjk = true
		elif c == "\"" or c == "'":
			in_str = true
			quote = c
		i += 1
	return n

func _scan_dir(dir: String) -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(dir):
		if not String(f).ends_with(".gd"):
			continue
		var fa := FileAccess.open(dir.path_join(String(f)), FileAccess.READ)
		if fa == null:
			continue
		var src := fa.get_as_text()
		fa.close()
		out[String(f)] = _count_cjk_literals(src)
	return out

func _sum(d: Dictionary) -> int:
	var s := 0
	for k in d:
		s += int(d[k])
	return s

func _run() -> void:
	var ui := _scan_dir(UI_DIR)
	var all := _scan_dir(ALL_DIR)
	# scripts/ui 下还有子目录时也要算进来（当前没有，写出来免得以后静默漏掉）
	for sub in DirAccess.get_directories_at(UI_DIR):
		var d := _scan_dir(UI_DIR.path_join(String(sub)))
		for k in d:
			ui[String(sub) + "/" + String(k)] = d[k]
	# 项目口径（含 core/battle 等）：只用于报告，不参与判定
	for sub in DirAccess.get_directories_at(ALL_DIR):
		if String(sub) == "ui":
			continue
		var d2 := _scan_dir(ALL_DIR.path_join(String(sub)))
		for k in d2:
			all[String(sub) + "/" + String(k)] = d2[k]

	var ui_total := _sum(ui)
	print("[i18n] scripts/ui 硬编码中文条数：%d" % ui_total)
	var rows := []
	for k in ui:
		if int(ui[k]) > 0:
			rows.append([String(k), int(ui[k])])
	rows.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	for r in rows:
		print("        %-26s %3d" % [r[0], r[1]])

	# ---- 1) Strings.gd 表本身 ----
	var f := FileAccess.open(STRINGS_PATH, FileAccess.READ)
	_ok(f != null, "能读到 %s" % STRINGS_PATH)
	var consts := {}
	if f != null:
		var src := f.get_as_text()
		f.close()
		_ok(src.contains("class_name Strings"), "Strings.gd 仍声明 class_name Strings")
		for line in src.split("\n"):
			if not line.begins_with("const "):
				continue
			var rest := line.substr(6)
			var sep := rest.find(" := ")
			if sep <= 0:
				continue
			var nm := rest.substr(0, sep)
			var val := rest.substr(sep + 4).strip_edges()
			consts[nm] = val
			var name_ok := nm.length() > 0
			for i in nm.length():
				var ch := nm[i]
				if not ((ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_"):
					name_ok = false
			_ok(name_ok, "常量名是 SCREAMING_SNAKE：%s" % nm)
			_ok(val.begins_with("\"") and val.ends_with("\"") and val.length() > 2,
				"常量 %s 是非空字符串字面量" % nm)
			_ok(not val.contains("\t"), "常量 %s 里没有制表符" % nm)
	_ok(consts.size() >= MIN_CONSTANTS, "常量表至少有 %d 条（当前 %d）" % [MIN_CONSTANTS, consts.size()])
	for need in ["PURSE_LINE", "DAY_LABEL", "TERRAIN", "NIGHT_BADGE"]:
		_ok(consts.has(need), "常量表里有 %s" % need)

	# ---- 2) 已迁过的界面必须真的干净了 ----
	_ok(int(ui.get("TopBar.gd", -1)) == 0,
		"TopBar.gd 已无硬编码中文（当前 %s）" % str(ui.get("TopBar.gd", "缺文件")))

	if _write_baseline:
		var payload := {
			"note": "i18n 棘轮基线：scripts/ui 下含表意文字的字符串字面量条数。只许变小；调高必须写进 ROADMAP。",
			"ui_total": ui_total,
			"ui_files": ui,
			"project_total": _sum(all),
		}
		var w := FileAccess.open(BASELINE_PATH, FileAccess.WRITE)
		if w == null:
			print("FAIL：写不进 %s" % BASELINE_PATH)
			quit(1)
			return
		w.store_string(JSON.stringify(payload, "\t") + "\n")
		w.close()
		print("[i18n] 已写入基线：ui_total=%d" % ui_total)
		quit(0)
		return

	# ---- 3) 与基线比：只许变小 ----
	var bf := FileAccess.open(BASELINE_PATH, FileAccess.READ)
	_ok(bf != null, "存在基线文件 %s" % BASELINE_PATH)
	if bf != null:
		var txt := bf.get_as_text()
		bf.close()
		var j := JSON.new()
		var perr := j.parse(txt)
		_ok(perr == OK, "基线 JSON 能解析（err=%d）" % perr)
		if perr == OK:
			var base: Dictionary = j.data
			var base_total := int(base.get("ui_total", -1))
			var base_files: Dictionary = base.get("ui_files", {})
			print("[i18n] 基线 ui_total=%d，当前 %d（差 %+d）" % [base_total, ui_total, ui_total - base_total])
			_ok(ui_total <= base_total,
				"scripts/ui 硬编码中文没有变多（基线 %d，当前 %d）——新文案请放进 Strings.gd，或显式重写基线" % [base_total, ui_total])
			for k in base_files:
				var now := int(ui.get(String(k), 0))
				_ok(now <= int(base_files[k]),
					"%s 没有变多（基线 %d，当前 %d）" % [str(k), int(base_files[k]), now])
			for k in ui:
				if int(ui[k]) > 0 and not base_files.has(String(k)):
					_ok(false, "%s 出现基线里没有的 %d 条硬编码中文" % [String(k), int(ui[k])])

	print("")
	if _fails.is_empty():
		print("PASS：i18n 棘轮达标（%d 项断言，ui_total=%d）" % [_total, ui_total])
		quit(0)
	else:
		print("FAIL：%d/%d 项断言未通过 —— %s" % [_fails.size(), _total, "; ".join(_fails)])
		quit(1)