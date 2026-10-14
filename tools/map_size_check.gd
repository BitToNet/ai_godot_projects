## =============================================================================
##  map_size_check —— 「地图尺寸适配」定式自检（**不参与游戏运行**）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/map_size_check.gd
##
##  为什么需要它：ROADMAP §12.5 把「换一张更大的地图」清点成一张表，其中 #3（相机远裁剪）
##  与 #4（heightmap_res 的导出上限）是纯数值型假设 —— 它们的失败方式**不是报错，而是**
##  在 4096 m 图上「地形被裁掉 / 编辑器里调不上去」，而 1024 m 图上一切正常，
##  所以门禁里那 25 项一条都抓不到。这一条把「按尺寸推导」这层关系本身钉住。
##
##  它断言的是**数值关系**，不建世界、不建相机、不渲染：
##    1) 1024 m 图（当前世界）的推导结果必须**逐位等于**改造前的旧常量（行为不变）；
##    2) 4096 m 图（目标世界）的推导结果必须覆盖对角线（地形不被裁掉）；
##    3) heightmap_res 的 @export_range 上限必须放得下 2049，且步进仍只产生奇数分辨率。
##  它**不**证明渲染效果、也不证明拾取在地形上真的命中 —— 那些属于实机观察，见 §12.5 的说明。
##
##  退出码：0 = 全部通过；1 = 有断言失败
## =============================================================================
extends SceneTree

const TARGET_SIZE := 4096.0   ## ROADMAP §12.5 的目标地图尺寸
const LEGACY_FAR := 5000.0    ## 改造前 CameraRig 的 cam.far（1024 m 时代）
const LEGACY_RAY := 4000.0    ## 改造前 ray_to_terrain 的最远推进距离

var _fails: Array[String] = []
var _total: int = 0

func _initialize() -> void:
	_run()

func _ok(cond: bool, what: String) -> void:
	_total += 1
	if not cond:
		_fails.append(what)

## 与 ROADMAP 同口径：对角线 = sqrt(2) * 边长
func _diagonal(size: float) -> float:
	return sqrt(2.0) * size

func _run() -> void:
	var cfg := MapConfig.new()

	# ---- 1) 当前世界（1024 m）的既有取值：本批改造不许动它 ----
	_ok(is_equal_approx(cfg.map_size, 1024.0), "默认地图尺寸仍是 1024 m（%.1f）" % cfg.map_size)
	_ok(cfg.heightmap_res == 513, "默认高度图分辨率仍是 513（%d）" % cfg.heightmap_res)
	var spacing_now := cfg.map_size / float(cfg.heightmap_res - 1)
	_ok(is_equal_approx(spacing_now, 2.0), "当前高度图间距是 2.0 m（%.4f）" % spacing_now)

	# 这两条是「行为不变」的正式证据：推导函数在 1024 m 下必须回落到旧常量本身
	_ok(CameraRig.far_for(cfg.map_size) == LEGACY_FAR,
		"1024 m 图的远裁剪面仍是旧值 %.1f（%.1f）" % [LEGACY_FAR, CameraRig.far_for(cfg.map_size)])
	_ok(CameraRig.ray_max_distance(cfg.map_size) == LEGACY_RAY,
		"1024 m 图的拾取最远距离仍是旧值 %.1f（%.1f）" % [LEGACY_RAY, CameraRig.ray_max_distance(cfg.map_size)])

	# ---- 2) heightmap_res 的导出范围必须放得下 4096 m 的 2 m 间距 ----
	var want_res := int(TARGET_SIZE / spacing_now) + 1      # 4096 m / 2 m + 1 = 2049
	_ok(want_res == 2049, "4096 m 保持 2 m 间距需要 2049 个采样点（%d）" % want_res)
	var rng := _range_of(cfg, "heightmap_res")
	_ok(not rng.is_empty(), "从 MapConfig 读到了 heightmap_res 的 @export_range")
	if not rng.is_empty():
		var lo: int = rng[0]
		var hi: int = rng[1]
		var st: int = rng[2]
		_ok(lo == 129, "@export_range 下限仍是 129（%d）" % lo)
		_ok(st == 2, "@export_range 步进仍是 2（只产生奇数分辨率）（%d）" % st)
		_ok(hi >= want_res, "@export_range 上限放得下 2049（当前上限 %d）" % hi)
		# 上限本身也必须落在步进的格点上，否则编辑器里最后能选到的值不是上限
		_ok((hi - lo) % st == 0, "上限落在步进格点上（(%d-%d) %% %d == %d）" % [hi, lo, st, (hi - lo) % st])
		_ok((want_res - lo) % st == 0, "2049 本身落在步进格点上（(%d-%d) %% %d == %d）" % [want_res, lo, st, (want_res - lo) % st])
	_ok(want_res % 2 == 1, "2049 是奇数（高度图分辨率必须为奇数）")

	# ---- 3) 4096 m 图：推导值必须覆盖对角线 ----
	var far_target := CameraRig.far_for(TARGET_SIZE)
	var ray_target := CameraRig.ray_max_distance(TARGET_SIZE)
	var diag := _diagonal(TARGET_SIZE)
	_ok(far_target >= diag,
		"4096 m 图的远裁剪面 %.0f ≥ 对角线 %.0f（否则站在一角看对角会看不到地形）" % [far_target, diag])
	_ok(ray_target >= diag,
		"4096 m 图的拾取最远距离 %.0f ≥ 对角线 %.0f（否则点不中远端的落点）" % [ray_target, diag])
	# 1024 m 图同样要成立（验收口径统一，不搞特例）
	for s in [1024.0, 2048.0, TARGET_SIZE]:
		_ok(CameraRig.far_for(s) >= _diagonal(s), "%.0f m 图的远裁剪面覆盖对角线（%.0f ≥ %.0f）"
			% [s, CameraRig.far_for(s), _diagonal(s)])

	# ---- 4) 单调性：地图变大，两个推导值都不许变小 ----
	var sizes := [512.0, 1024.0, 2048.0, TARGET_SIZE, 8192.0]
	var mono_far := true
	var mono_ray := true
	for i in range(1, sizes.size()):
		if CameraRig.far_for(sizes[i]) < CameraRig.far_for(sizes[i - 1]):
			mono_far = false
		if CameraRig.ray_max_distance(sizes[i]) < CameraRig.ray_max_distance(sizes[i - 1]):
			mono_ray = false
	_ok(mono_far, "远裁剪面对地图尺寸单调不减")
	_ok(mono_ray, "拾取最远距离对地图尺寸单调不减")

	# ---- 5) 拾取循环的迭代上限必须够走完推导出来的距离 ----
	# 步进是「每步 ×1.06、上限 RAY_STEP_MAX」，这里用最坏情况（全程按上限步进）估算。
	var need := int(ceil(CameraRig.ray_max_distance(TARGET_SIZE) / CameraRig.RAY_STEP_MAX)) + 64
	_ok(CameraRig.RAY_GUARD >= need,
		"RAY_GUARD %d 够走完 4096 m 的拾取距离（估算需要 %d 步）" % [CameraRig.RAY_GUARD, need])

	# ---- 6) 内存量级（只报告，不判定）：2049² float32 的高度图 ----
	# 用十进制 MB，跟 ROADMAP §12.5 #4 写的「≈16.8 MB」同口径（MiB 会显示成 16.0，容易被当成不一致）
	var bytes := want_res * want_res * 4
	print("[地图尺寸] 4096 m / %.0f m 间距 ⇒ 高度图 %d² × 4 B = %.1f MB"
		% [spacing_now, want_res, float(bytes) / 1000000.0])

	if _fails.is_empty():
		print("PASS：地图尺寸推导定式全部正常（%d 项断言）" % _total)
		quit(0)
	else:
		print("FAIL：%d/%d 项断言未通过 —— %s" % [_fails.size(), _total, "; ".join(_fails)])
		quit(1)

## 读一个 @export_range 变量的 [下限, 上限, 步进]；不是 range 导出就返回空数组。
## 注意：引擎给的 hint_string 是**小数**形式（如 "129.0,2049.0,2.0"），
## 用 is_valid_int() 判会全部落空（第一次就是这么写错的，门禁当场报了 1 项失败）。
func _range_of(res: Resource, prop: String) -> Array:
	for p in res.get_property_list():
		if String(p.get("name", "")) != prop:
			continue
		if int(p.get("hint", 0)) != PROPERTY_HINT_RANGE:
			return []
		var parts := String(p.get("hint_string", "")).split(",")
		if parts.size() < 2:
			return []
		if not (parts[0].is_valid_float() and parts[1].is_valid_float()):
			return []
		var step := 1
		if parts.size() >= 3 and parts[2].is_valid_float():
			step = int(parts[2].to_float())
		return [int(parts[0].to_float()), int(parts[1].to_float()), step]
	return []