## =============================================================================
##  tools/fog_check.gd —— 战争迷雾「逐字节可复现」自检（第七轮 ① 新增）
##
##  为什么需要它：FogOfWar 在第七轮 ① 里做了两处性能改动 ——
##    (a) update() 整轮跳过「位置逐位不变」的点（世界暂停时 40k 格重扫 → 0）；
##    (b) reveal() 把 float(z)*cell、z*RES、radius*0.55 这三个每格重算的量提到循环外。
##  迷雾贴图会进地形 / 建筑 / 植被三个 shader，「看起来一样」不算数：这里把**改动前的原始循环**
##  原样抄进探针当参照实现，两个实现逐字节比对 explored（float32 数组）与 _bytes（RGBA8 字节）。
##
##  覆盖：三个世界尺寸（1024 / 2048 / 4096）× 三条轨迹（静止 / 直线行进 / 绕圈）
##        + 每轮把同一批点重复喂一遍（专门验证 (a) 的跳过路径不改变结果）。
##  不需要生成世界（reveal 只依赖 cfg.map_size），所以 <1 秒。
##
##  退出码：0 = 全部通过；1 = 有断言失败
## =============================================================================
extends SceneTree

var _oks: int = 0
var _fails: int = 0

func _init() -> void:
	_run()
	print("[迷雾] 世界尺寸 %d 个 / 轨迹 %d 条 / 断言 %d 项" % [_sizes.size(), 3, _oks + _fails])
	if _fails > 0:
		print("FAIL：迷雾逐字节自检有 %d 项未通过" % _fails)
		quit(1)
		return
	print("PASS：迷雾揭开与原始循环逐字节一致（%d 项断言）" % _oks)
	quit(0)

const _sizes: Array = [1024.0, 2048.0, 4096.0]
const ROUNDS := 8

func _ok(cond: bool, what: String) -> void:
	if cond:
		_oks += 1
		print("  ok   %s" % what)
	else:
		_fails += 1
		print("  FAIL %s" % what)

# ---------------------------------------------------------------- 参照实现
## 未优化前的原始循环，逐字抄自第七轮 ① 之前的 FogOfWar.reveal()。
## 它唯一的用途是当参照 —— 改这里等于把参照改坏，等于放弃这次自检。
func _reveal_reference(fog: FogOfWar, p: Vector2, radius: float) -> void:
	var cell := fog.cfg.map_size / float(FogOfWar.RES - 1)
	var cx := int(p.x / cell)
	var cz := int(p.y / cell)
	var cr := int(ceil(radius / cell)) + 1
	for dz in range(-cr, cr + 1):
		for dx in range(-cr, cr + 1):
			var x := cx + dx
			var z := cz + dz
			if x < 0 or z < 0 or x >= FogOfWar.RES or z >= FogOfWar.RES:
				continue
			var q := Vector2(float(x) * cell, float(z) * cell)
			var d := q.distance_to(p)
			if d > radius:
				continue
			var v := 1.0 - smoothstep(radius * 0.55, radius, d)
			var i := z * FogOfWar.RES + x
			if v > fog.explored[i]:
				fog.explored[i] = v
				fog._write_cell(i, v)

# ---------------------------------------------------------------- 轨迹
## 三条轨迹各 8 轮、每轮 4 个点（玩家 + 3 支部队），返回 Array[Array[Vector2]]
func _tracks(size: float) -> Dictionary:
	var base: Array = []
	for k in 4:
		base.append(Vector2(size * (0.28 + 0.14 * float(k)), size * (0.34 + 0.11 * float(k))))
	var still: Array = []
	var line: Array = []
	var circle: Array = []
	for r in ROUNDS:
		var a: Array = []
		var b: Array = []
		var c: Array = []
		for k in 4:
			var p: Vector2 = base[k]
			a.append(p)                                                   # 静止：逐位不变
			b.append(p + Vector2(9.0 * float(r), -6.0 * float(r)))        # 行进：每轮挪一格以上
			var ang := TAU * float(r) / float(ROUNDS)
			c.append(p + Vector2(cos(ang), sin(ang)) * (size * 0.03))     # 绕圈：小位移来回
		still.append(a)
		line.append(b)
		circle.append(c)
	return {"静止": still, "行进": line, "绕圈": circle}

func _run() -> void:
	for size in _sizes:
		var cfg := MapConfig.new()
		cfg.map_size = size
		cfg.heightmap_res = cfg.scaled_heightmap_res()
		var radius := cfg.fog_reveal_radius_m()
		var tracks := _tracks(size)
		for tag in tracks.keys():
			var rounds: Array = tracks[tag]
			# A 路：生产实现（update 会走「位置不变就跳过」的快路径）
			var fa := FogOfWar.new()
			fa.setup(cfg)
			# B 路：原始循环 + 不做任何跳过
			var fb := FogOfWar.new()
			fb.setup(cfg)
			var repeated_ok := true
			for i in rounds.size():
				var batch: Array = rounds[i]
				fa.update(0.2, batch)
				for p in batch:
					_reveal_reference(fb, p, radius)
				# 同一批点再喂一遍：位置逐位相同 ⇒ 必须整轮跳过、贴图一个字节都不许变
				var snap := fa._bytes.duplicate()
				fa.update(0.2, batch)
				if fa._bytes != snap:
					repeated_ok = false
			var label := "%.0f m / %s" % [size, String(tag)]
			_ok(fa.explored == fb.explored, "%s：explored 逐格一致（%d 格）" % [label, fa.explored.size()])
			_ok(fa._bytes == fb._bytes, "%s：RGBA 缓冲逐字节一致（%d 字节）" % [label, fa._bytes.size()])
			_ok(repeated_ok, "%s：重复喂同一批点不改变贴图" % label)
			var revealed := 0
			for v in fa.explored:
				if v > 0.0:
					revealed += 1
			_ok(revealed > 0, "%s：确有格子被揭开（%d 格）" % [label, revealed])
			# 静止轨迹必须真的走到跳过路径，否则这次自检没测到 (a)。
			# 计数：第 0 轮首次扫描不跳（没有上一轮位置）→ 紧随其后的重复调用跳 4 个；
			# 第 1~7 轮每轮跳两次（本轮 + 重复调用）各 4 个 ⇒ 4 + 7 × 8 = 60。
			if String(tag) == "静止":
				_ok(fa.skip_total == 4 + (ROUNDS - 1) * 8,
					"%s：静止点走跳过路径（累计跳过 %d 个点，期望 %d）" % [label, fa.skip_total, 4 + (ROUNDS - 1) * 8])
			else:
				_ok(fa.skip_total >= 4, "%s：重复喂的那一轮走跳过路径（累计 %d）" % [label, fa.skip_total])