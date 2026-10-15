## =============================================================================
##  sfx_studio_export —— 导出网页调音台（tools/sfx_studio）要用的音效清单
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --script res://tools/sfx_studio_export.gd
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --script res://tools/sfx_studio_export.gd -- --check     # 只校验，不写盘
##
##  为什么要有这一步（而不是让网页自己"猜"）：
##   · 音效清单的**唯一真相**是 SfxSynth.SPECS（28 条：分类 / 基准 dB / 最短间隔 / 基准音高）
##     与 SfxFoley.SETS（13 个动作、40 个录音变体）。往网页里抄一份常量，改音色时必然走散。
##   · 网页要能"像游戏一样出声"，就得知道哪几条走录音素材、素材有几个变体 ——
##     这些也是从代码里导出来的，不是硬编码。
##   · 音量上下限 / 十条记录上限同样取自 SfxProfile 的常量，两边永远一致。
##
##  退出码：0 = 成功；1 = 失败（--check 时"清单与代码不一致"也算失败）
## =============================================================================
extends SceneTree

const OUT := "res://tools/sfx_studio/manifest.json"
const PREVIEW_DIR := "res://audio_preview"
const FOLEY_DIR := "res://audio/sfx/foley"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var check := args.has("--check")
	var text := JSON.stringify(_build(), "  ") + "\n"
	if check:
		quit(_check(text))
		return
	var dir := OUT.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		print("[调音台清单] FAIL：写不进 %s（错误码 %d）" % [OUT, FileAccess.get_open_error()])
		quit(1)
		return
	f.store_string(text)
	f.close()
	var n := SfxSynth.ids().size()
	var v := 0
	for id in SfxFoley.SETS:
		v += (SfxFoley.SETS[id] as Array).size()
	print("[调音台清单] PASS：已写 %s（%d 条音效 / %d 个录音变体 / %.1f KB）" % [
		OUT, n, v, float(text.length()) / 1024.0])
	quit(0)

## --check：清单必须与代码导出的一致。generated_at 每次都不同，比对前剔掉。
func _check(text: String) -> int:
	if not FileAccess.file_exists(OUT):
		print("[调音台清单] FAIL：%s 不存在（先不带 --check 跑一次）" % OUT)
		return 1
	var old_txt := FileAccess.get_file_as_string(OUT)
	var a: Variant = JSON.parse_string(old_txt)
	var b: Variant = JSON.parse_string(text)
	if not (a is Dictionary) or not (b is Dictionary):
		print("[调音台清单] FAIL：清单不是合法 JSON 对象")
		return 1
	(a as Dictionary).erase("generated_at")
	(b as Dictionary).erase("generated_at")
	var sa := JSON.stringify(_sorted(a))
	var sb := JSON.stringify(_sorted(b))
	if sa == sb:
		print("[调音台清单] PASS：manifest.json 与 SfxSynth.SPECS / SfxFoley.SETS 一致")
		return 0
	var da: Dictionary = a
	var db: Dictionary = b
	for key in ["schema", "version", "project", "sfx_rate", "record_limit", "limits", "defaults", "categories", "bgm"]:
		if JSON.stringify(_sorted(da.get(key))) != JSON.stringify(_sorted(db.get(key))):
			print("[调音台清单] 不一致的字段：%s" % key)
	var ka: Array = da.get("sfx", [])
	var kb: Array = db.get("sfx", [])
	if ka.size() != kb.size():
		print("[调音台清单] 音效条数不同：清单 %d ≠ 代码 %d" % [ka.size(), kb.size()])
	else:
		for i in ka.size():
			if JSON.stringify(_sorted(ka[i])) != JSON.stringify(_sorted(kb[i])):
				print("[调音台清单] 第 %d 条音效不同：%s" % [i, str((kb[i] as Dictionary).get("id", "?"))])
	print("[调音台清单] FAIL：清单已过期，请重跑导出（不带 --check）")
	return 1

## JSON.stringify 的键序取决于字典插入序，两边可能不同 —— 递归按键排序后再比
func _sorted(v: Variant) -> Variant:
	if v is Dictionary:
		var d := v as Dictionary
		var keys: Array = d.keys()
		keys.sort()
		var out := {}
		for k in keys:
			out[String(k)] = _sorted(d[k])
		return out
	if v is Array:
		var arr := v as Array
		var out_a: Array = []
		for x in arr:
			out_a.append(_sorted(x))
		return out_a
	return v

# =============================================================== 清单本体
func _build() -> Dictionary:
	var cfg := AudioConfig.create()
	var cats := []
	for cat in SfxProfile.CATEGORY_FIELDS:
		cats.append({
			"id": String(cat),
			"field": String(SfxProfile.CATEGORY_FIELDS[cat]),
			"rest_db": float(cfg.category_db(String(cat))),
		})
	var sfx := []
	# 按 SPECS 的**声明顺序**遍历（GDScript 字典保序）：网页列表的排列与代码里
	# "打击 / 弹反 / 闪避 / 移动 / 人声 / UI" 的分组顺序一致，而不是字典序打乱分组。
	for id in SfxSynth.SPECS.keys():
		var sid := String(id)
		var m := SfxSynth.meta(sid)
		var variants := []
		for base in SfxFoley.SETS.get(sid, []):
			variants.append("%s/%s.wav" % [_rel(FOLEY_DIR), String(base)])
		var preview := "%s/%s.wav" % [_rel(PREVIEW_DIR), sid]
		sfx.append({
			"id": sid,
			"order": sfx.size(),
			"cat": String(m[0]),
			"db": float(m[1]),
			"gap": float(m[2]),
			"pitch": float(m[3]),
			"preview": preview,
			"preview_exists": FileAccess.file_exists("res://" + preview),
			"variants": variants,
			"variants_missing": _missing_variants(variants),
		})
	var bgm := []
	for id in Bgm.TRACKS:
		var path := _rel(String(Bgm.TRACKS[id]))
		var db := cfg.bgm_map_db if String(id) == "map" else cfg.bgm_battle_db
		var fade := cfg.bgm_fade_in if String(id) == "map" else cfg.bgm_fade_battle
		bgm.append({
			"id": String(id),
			"path": path,
			"db": db,
			"fade": fade,
			"exists": FileAccess.file_exists("res://" + path),
		})
	var defaults := {
		"master_db": cfg.master_db,
		"bgm_db": cfg.bgm_db,
		"pitch_jitter": cfg.pitch_jitter,
		"polyphony": cfg.polyphony,
		"warn_cues": cfg.warn_cues,
		"step_interval": cfg.step_interval,
		"boss_step_interval": cfg.boss_step_interval,
		"hoof_interval": cfg.hoof_interval,
		"hoof_audible_range": cfg.hoof_audible_range,
		"fanfare_duck_db": cfg.fanfare_duck_db,
		"fanfare_duck_time": cfg.fanfare_duck_time,
		"bgm_fade_map": cfg.bgm_fade_map,
		"bgm_fade_battle": cfg.bgm_fade_battle,
	}
	return {
		"schema": "warband.sfx_studio.manifest",
		"version": 1,
		"generated_at": Time.get_datetime_string_from_system(false, true),
		"generator": "tools/sfx_studio_export.gd",
		"project": ProjectSettings.get_setting("application/config/name", ""),
		"engine": Engine.get_version_info().get("string", ""),
		"sfx_rate": SfxSynth.RATE,
		"profile_schema": SfxProfile.SCHEMA,
		"record_limit": SfxProfile.MAX_RECORDS,
		"limits": {
			"master": [SfxProfile.MASTER_MIN, SfxProfile.MASTER_MAX],
			"category": [SfxProfile.CATEGORY_MIN, SfxProfile.CATEGORY_MAX],
			"sfx": [SfxProfile.SFX_MIN, SfxProfile.SFX_MAX],
		},
		"fanfare": Sfx.FANFARE,
		"defaults": defaults,
		"categories": cats,
		"sfx": sfx,
		"bgm": bgm,
	}

func _missing_variants(paths: Array) -> Array:
	var miss := []
	for p in paths:
		if not FileAccess.file_exists("res://" + String(p)):
			miss.append(String(p))
	return miss

## res://xxx -> xxx（网页里的相对路径，服务端以工程根为静态根）
func _rel(path: String) -> String:
	return path.replace("res://", "")