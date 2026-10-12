## =============================================================================
##  gen_fingerprint —— 程序化生成的确定性自检（**不参与游戏运行**，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/gen_fingerprint.gd
##    # 有意改变了生成算法 / 换了种子时，更新基线：
##    ...--script res://tools/gen_fingerprint.gd -- --write-baseline
##    # 只想看指纹、不与基线比对：
##    ...--script res://tools/gen_fingerprint.gd -- --print-only
##
##  做两件事：
##    1) 用固定种子（MapConfig 默认 map_seed）完整跑一遍 Main.tscn 的程序化生成
##    2) 对生成物逐项算 SHA-256，拼成一条总指纹，与 tools/gen_fingerprint.json 比对
##
##  为什么需要它：本工程「一切由种子生成」，README 承诺「单一种子可复现」，
##  但在此之前这句话**零验证**。任何一次随手改动 RNG 抽取顺序（哪怕只是把两次
##  randf() 调换位置）都会静默改变整张地图 —— 而截图上看不出来。
##
##  设计取舍：
##    · 冻结世界（set_process/set_physics_process 关掉）后再取指纹：本自检只测
##      「生成」，不掺入「等了多少帧」这种非确定性输入。
##    · 关音频：与声音无关，跳过约 1.5 s 的 PCM 合成。
##    · 指纹按「项」拆分并逐项打印，不一致时能一眼看出是哪一类生成物变了。
##
##  退出码 0 = 与基线一致；1 = 不一致；2 = 超时 / 基线缺失或不可读
## =============================================================================
extends SceneTree

const SCENE := "res://scenes/Main.tscn"
const BASELINE := "res://tools/gen_fingerprint.json"
const WAIT_LIMIT := 6000          ## 等待生成完成的帧上限（--fixed-fps 下 6000 帧 = 100 秒）

var main: Node
var parts: Dictionary = {}        ## 名称 -> {hash, bytes, detail}

func _initialize() -> void:
	_run()

func _run() -> void:
	var user_args := OS.get_cmdline_user_args()
	var write_baseline := user_args.has("--write-baseline")
	var print_only := user_args.has("--print-only")

	var scene: PackedScene = load(SCENE)
	main = scene.instantiate()
	var ac := AudioConfig.new()
	ac.enabled = false
	main.audio = ac
	var mc := MapConfig.new()
	main.config = mc
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)

	var guard := 0
	var gen_frame := 0
	while guard < WAIT_LIMIT:
		guard += 1
		await process_frame
		if gen_frame == 0 and int(main._gen_ms) != 0:
			gen_frame = guard
		# 必须等到 gen_done：_gen_ms 置位时收尾协程还在 await，
		# 此刻 free() 会报「Resumed function '_step()' after await, but class instance is gone」
		if main.gen_done:
			break
	if not main.gen_done:
		print("[确定性] FAIL：等待地图生成超时（%d 帧）" % guard)
		quit(2)
		return

	print("[确定性] 就绪：种子 %d / 生成 %d 帧（%d ms）/ 收尾后共 %d 帧" % [
		mc.map_seed, gen_frame, int(main._gen_ms), guard])
	_collect(main)
	var fp := _total()
	print("[确定性] 生成物逐项指纹（SHA-256 前 16 位）：")
	var keys: Array = parts.keys()
	keys.sort()
	for k in keys:
		print("      %-12s %s  %s" % [String(k), String(parts[k]["hash"]).substr(0, 16), String(parts[k]["detail"])])
	print("[确定性] FINGERPRINT=%s" % fp)

	if print_only:
		main.free()
		quit(0)
		return

	if write_baseline:
		_write_baseline(fp, mc, guard)
		main.free()
		return

	var want := _read_baseline()
	if want.is_empty():
		print("[确定性] FAIL：基线缺失或不可读 -> %s" % BASELINE)
		print("      先跑一次：--script res://tools/gen_fingerprint.gd -- --write-baseline")
		main.free()
		quit(2)
		return
	var old_fp := String(want.get("fingerprint", ""))
	if old_fp == fp:
		print("[确定性] PASS：生成物指纹与基线一致（种子 %d）" % int(want.get("seed", -1)))
		main.free()
		quit(0)
		return
	print("[确定性] FAIL：生成物指纹与基线不一致")
	print("      基线(%s) = %s" % [str(want.get("seed", "?")), old_fp])
	print("      本次        = %s" % fp)
	var old_parts: Dictionary = want.get("parts", {})
	print("      逐项差异：")
	for k in keys:
		var a := String(old_parts.get(k, {}).get("hash", "(缺失)"))
		var b := String(parts[k]["hash"])
		if a != b:
			print("        %-12s 基线 %s -> 本次 %s" % [String(k), a.substr(0, 16), b.substr(0, 16)])
	print("      若这是有意改动（改生成算法 / 换种子），用 -- --write-baseline 更新基线，")
	print("      并在提交信息里说明「生成结果有意改变」；否则说明你不小心动了 RNG 抽取顺序。")
	main.free()
	quit(1)

# ---------------------------------------------------------------- 采集
func _collect(m: Node) -> void:
	var d: MapData = m.data
	_add("heightmap", d.hm.data.to_byte_array(), "res %d / %d float32" % [d.hm.res, d.hm.data.size()])
	_add("territory", d.territory, "%d bytes" % d.territory.size())
	_add("nav_fine", _nav_bytes(d.nav_fine), "res %d" % d.nav_fine.res)
	_add("nav_coarse", _nav_bytes(d.nav_coarse), "res %d" % d.nav_coarse.res)
	_add("nav_road", _nav_bytes(d.nav_road), "res %d" % d.nav_road.res)
	_add("settlements", _settlements_bytes(d), "%d 个" % d.settlements.size())
	_add("roads", _roads_bytes(d), "%d 条" % d.roads.size())
	_add("bridges", _bridges_bytes(d), "%d 座" % d.bridges.size())
	_add("vegetation", _veg_bytes(m.vegetation), "%d 实例 / %s" % [m.vegetation.total(), _counts_text(m.vegetation.counts)])
	_add("parties", _parties_bytes(m), "1 玩家 + %d AI" % m.ai_parties.size())

func _nav_bytes(g: NavGrid) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(g.blocked)
	out.append_array(g.speed.to_byte_array())
	out.append_array(g.road)
	out.append_array(g.forest)
	out.append_array(g.water)
	out.append_array(g.river)
	out.append_array(g.ford)
	out.append_array(g.bridge)
	out.append_array(g.component.to_byte_array())
	return out

func _settlements_bytes(d: MapData) -> PackedByteArray:
	# 按 id 排序，不依赖内部数组顺序
	var idx: Array = []
	for i in d.settlements.size():
		idx.append(i)
	idx.sort_custom(func(a, b): return d.settlements[a].id < d.settlements[b].id)
	var out := PackedByteArray()
	for i in idx:
		var s: Settlement = d.settlements[i]
		var nb: Array = s.neighbors.duplicate()
		nb.sort()
		out.append_array(("%d|%s|%d|%d|%.4f|%.4f|%.4f|%.2f|%d|%d|%s;" % [
			s.id, s.name, s.kind, s.faction_id, s.pos.x, s.pos.y, s.ground_h,
			s.radius, s.garrison, s.parent_town, str(nb)]).to_utf8_buffer())
	return out

func _roads_bytes(d: MapData) -> PackedByteArray:
	var out := PackedByteArray()
	for i in d.roads.size():
		var pts: PackedVector2Array = d.roads[i]
		out.append_array(("road%d:%d;" % [i, pts.size()]).to_utf8_buffer())
		for p in pts:
			out.append_array(("%.4f,%.4f;" % [p.x, p.y]).to_utf8_buffer())
	return out

func _bridges_bytes(d: MapData) -> PackedByteArray:
	var out := PackedByteArray()
	for i in d.bridges.size():
		var b: Dictionary = d.bridges[i]
		var pos: Vector2 = b["pos"]
		var dir: Vector2 = b["dir"]
		out.append_array(("%d|%.4f,%.4f|%.4f,%.4f|%.4f;" % [
			i, pos.x, pos.y, dir.x, dir.y, float(b["len"])]).to_utf8_buffer())
	return out

## 植被：种类计数 + 每个 MultiMesh 的实例数与实例位置（内容级校验，不只是数量）
func _veg_bytes(v: VegetationScatter) -> PackedByteArray:
	var out := PackedByteArray()
	var kinds: Array = v.counts.keys()
	kinds.sort()
	for k in kinds:
		out.append_array(("%s=%d;" % [String(k), int(v.counts[k])]).to_utf8_buffer())
	if v.root == null:
		return out
	var kids: Array = v.root.get_children()
	kids.sort_custom(func(a, b): return String(a.name) < String(b.name))
	for n in kids:
		if not (n is MultiMeshInstance3D):
			continue
		var mm: MultiMesh = n.multimesh
		if mm == null:
			continue
		out.append_array(("%s#%d;" % [String(n.name), mm.instance_count]).to_utf8_buffer())
		for i in mm.instance_count:
			var o := mm.get_instance_transform(i).origin
			out.append_array(PackedFloat32Array([o.x, o.y, o.z]).to_byte_array())
	return out

func _parties_bytes(m: Node) -> PackedByteArray:
	var out := PackedByteArray()
	_party_line(out, m.player, 0)
	for i in m.ai_parties.size():
		_party_line(out, m.ai_parties[i], i + 1)
	return out

func _party_line(out: PackedByteArray, p: PartyBase, idx: int) -> void:
	if p == null or not is_instance_valid(p):
		out.append_array(("slot%d:null;" % idx).to_utf8_buffer())
		return
	out.append_array(("slot%d|%s|%d|%d|%.4f|%.4f|%.4f|%s;" % [
		idx, p.party_name, p.faction_id, p.troop_count,
		p.position.x, p.position.y, p.position.z, str(p.is_player)]).to_utf8_buffer())

func _counts_text(counts: Dictionary) -> String:
	var keys: Array = counts.keys()
	keys.sort()
	var bits: Array = []
	for k in keys:
		bits.append("%s=%d" % [String(k), int(counts[k])])
	return " ".join(bits)

# ---------------------------------------------------------------- 哈希 / 基线
func _add(name: String, bytes: PackedByteArray, detail: String) -> void:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(bytes)
	var h: PackedByteArray = c.finish()
	parts[name] = {"hash": h.hex_encode(), "bytes": bytes.size(), "detail": detail}

func _total() -> String:
	var keys: Array = parts.keys()
	keys.sort()
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	for k in keys:
		var key := String(k)
		c.update(key.to_utf8_buffer())
		c.update(("=" + String(parts[key]["hash"]) + ";").to_utf8_buffer())
	var h: PackedByteArray = c.finish()
	return h.hex_encode()

func _read_baseline() -> Dictionary:
	if not FileAccess.file_exists(BASELINE):
		return {}
	var f := FileAccess.open(BASELINE, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _write_baseline(fp: String, mc: MapConfig, guard: int) -> void:
	var flat: Dictionary = {}
	var keys: Array = parts.keys()
	keys.sort()
	for k in keys:
		flat[String(k)] = {"hash": String(parts[k]["hash"]), "detail": String(parts[k]["detail"])}
	var obj := {
		"note": "由 tools/gen_fingerprint.gd --write-baseline 生成；指纹变化 = 生成结果变化（多半是 RNG 抽取顺序被动了）",
		"seed": mc.map_seed,
		"map_size": mc.map_size,
		"fingerprint": fp,
		"counts": {
			"settlements": main.data.settlements.size(),
			"bridges": main.data.bridges.size(),
			"vegetation": main.vegetation.total(),
		},
		"parts": flat,
	}
	var f := FileAccess.open(BASELINE, FileAccess.WRITE)
	if f == null:
		print("[确定性] FAIL：无法写入基线 %s（错误码 %d）" % [BASELINE, FileAccess.get_open_error()])
		main.free()
		quit(2)
		return
	f.store_string(JSON.stringify(obj, "\t") + "\n")
	f.close()
	print("[确定性] 已写入基线：%s（种子 %d，生成 %d ms，等待 %d 帧）" % [
		BASELINE, mc.map_seed, int(main._gen_ms), guard])
	print("[确定性] FINGERPRINT=%s" % fp)
	quit(0)
