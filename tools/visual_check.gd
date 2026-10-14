## =============================================================================
##  visual_check —— 观感层的**接线**定式（不渲染、不建世界，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/visual_check.gd
##
##  ---- 为什么要有这一步 ----
##  第七轮 ② 把环境光换成天空来源、开了 SSAO、天空改成自写着色器、地形加了细节贴图。
##  这类改动的失败方式特别阴：**不报错、不崩、指纹不变**，只是「看着不对」——
##  而门禁跑在 headless 下（DummyRenderingServer 画不出像素），像素验不了。
##  能验的是**接线与契约**：
##    · 环境光到底还来不来天空、SSAO 有没有被谁关掉、雾的起始距离与天空影响系数还在不在；
##    · 天空材质的每个 uniform 是否**真的被赋过值**（Godot 的坑：没赋过的 uniform
##      get_shader_parameter 返回 null，shader 里会静默用默认值 —— 昼夜天色就白调了）；
##    · 云的 cloud_speed 是不是 0（环境光取自天空之后，云一动就得每帧重算天空辐照度，
##      环境光会跟着闪 —— 这是硬约定，不是审美偏好，所以钉在门禁里）；
##    · 细节贴图是不是「均值 ~1.0 的无缝图」（均值跑偏 = 整张地图被悄悄压暗/提亮，
##      接缝了 = 一圈规则网格线，两种都很难靠肉眼定位）；
##    · day_amount 这条新曲线推得出去（白天的 night_amount 恒为 0，
##      推送逻辑只看它的话，白昼权重涨起来也推不出去 —— 已修，这里焊死）。
##
##  与 tools/visual_shot.gd 的分工：那个拍 PNG（要开窗、人眼判），这个断接线（headless、机器判）。
##
##  退出码：0 = 全部通过；1 = 有断言失败
## =============================================================================
extends SceneTree

## 采样步长：贴图统计只取 1/2 的行列 —— 256² 全量 get_pixel 在 GDScript 里要几百毫秒，
## 而这个量级的统计（均值 / 值域 / 接缝落差）抽半张就够稳了。
const SAMPLE_STEP := 2
## 细节贴图的平铺档位与贴图尺寸（与 MaterialFactory 的常量对齐，改那边就要改这里）
const TEX_SIZE := 256
const TILE_A := 9.0
const TILE_B := 13.0
const TILE_MACRO := 70.0
## 细节贴图的值域映射（与 MaterialFactory 的 DETAIL_LO / DETAIL_HI 对齐）
const DETAIL_LO := 0.60
const DETAIL_HI := 1.40

var _fails: Array[String] = []
var _total: int = 0
## 本工具造的 Node（DayNightCycle 及其 sun / env 子节点）：**必须 free**，
## 否则退出时报 "ObjectDB instances leaked"，那行会被门禁当失败。
var _nodes: Array[Node] = []

func _initialize() -> void:
	_run()

func _ok(cond: bool, what: String) -> void:
	_total += 1
	if cond:
		print("  [ok]   %s" % what)
	else:
		_fails.append(what)
		print("  [FAIL] %s" % what)

func _near(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps

func _run() -> void:
	print("[VISUAL] 观感层接线定式（不跑地图生成、不开窗）")
	_check_textures()
	_check_material()
	_check_environment()
	_check_dusk_and_night()
	_check_push()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	print("")
	if _fails.is_empty():
		print("PASS：观感层接线定式全部通过（%d 项断言）" % _total)
		quit(0)
	else:
		print("FAIL：%d/%d 项断言未通过 —— %s" % [_fails.size(), _total, "; ".join(_fails)])
		quit(1)

# ---------------------------------------------------------------- 细节贴图内容
func _check_textures() -> void:
	print(" · 无缝细节贴图")
	var det := MaterialFactory.seamless_detail_texture()
	var nrm := MaterialFactory.seamless_normal_texture()
	_ok(det != null and nrm != null, "两张细节贴图都生成出来了")
	_ok(det.get_width() == TEX_SIZE and det.get_height() == TEX_SIZE,
			"细节贴图 %d²（与平铺推导对齐）" % TEX_SIZE)
	_ok(det.get_image().has_mipmaps() and nrm.get_image().has_mipmaps(),
			"带 mipmap（世界里 1.4 m 一份，没有 mipmap 远处必起摩尔纹）")
	# 同一张图第二次拿必须是同一个实例：生成成本整局只付一次
	_ok(is_same(det, MaterialFactory.seamless_detail_texture()),
			"重复取用返回同一实例（进程内缓存生效）")

	var st := _image_stats(det.get_image())
	# 贴图里存的是**原始高度 0~1**（值域映射在 shader 里做）：8 位通道存不下 1.0 以上，
	# 直接把 [0.60, 1.40] 烘进去会被静默钳到 1.0，提亮那一半全丢、均值掉到 0.958
	_ok(st.mean > 0.45 and st.mean < 0.55,
			"细节图均值 %.3f ≈ 0.5（原始高度；映射到 [%.2f, %.2f] 之后均值正好是 1.0）"
			% [st.mean, DETAIL_LO, DETAIL_HI])
	# 值域不追求铺满 0~1：4 倍频 fbm 本来就很少到极值。要的是「跨得够开」——
	# 太窄就是一张灰纸（细节白加），太贴边又说明噪声被削平了。
	_ok(st.hi - st.lo > 0.55,
			"细节图值域跨度 %.2f（%.2f~%.2f → 映射后 %.2f~%.2f，够撑起颗粒感）"
			% [st.hi - st.lo, st.lo, st.hi,
				lerpf(DETAIL_LO, DETAIL_HI, st.lo), lerpf(DETAIL_LO, DETAIL_HI, st.hi)])
	_ok(st.seam_x <= st.inside_x * 4.0 + 0.02 and st.seam_y <= st.inside_y * 4.0 + 0.02,
			"细节图首尾接得上（横向 接缝 %.4f / 内部 %.4f，纵向 %.4f / %.4f）"
			% [st.seam_x, st.inside_x, st.seam_y, st.inside_y])

	var ns := _image_stats(nrm.get_image())
	_ok(_near(ns.mean_r, 0.5, 0.05) and _near(ns.mean_g, 0.5, 0.05),
			"法线图 R/G 均值 %.3f / %.3f ≈ 0.5（切线空间法线的编码方式）" % [ns.mean_r, ns.mean_g])
	_ok(ns.mean_b > 0.85, "法线图 B 均值 %.3f → +Z 朝外（没写反）" % ns.mean_b)
	_ok(ns.seam_x <= ns.inside_x * 4.0 + 0.02 and ns.seam_y <= ns.inside_y * 4.0 + 0.02,
			"法线图同样无缝（横向 接缝 %.4f / 内部 %.4f）" % [ns.seam_x, ns.inside_x])

# ---------------------------------------------------------------- 地形材质接线
func _check_material() -> void:
	print(" · 地形材质接线")
	var cfg := MapConfig.new()
	cfg.map_size = 1024.0
	var mf := MaterialFactory.new()
	mf.build(cfg, _make_data())
	var t: ShaderMaterial = mf.terrain
	_ok(t != null and t.shader != null
			and t.shader.resource_path == "res://shaders/terrain.gdshader",
			"地形材质指向 terrain.gdshader")
	_ok(t.get_shader_parameter("splat_map") != null, "splat_map 已接线")
	var det = t.get_shader_parameter("detail_map")
	var nrm = t.get_shader_parameter("detail_normal")
	_ok(det is ImageTexture and nrm is ImageTexture, "detail_map / detail_normal 都是贴图")
	_ok(is_equal_approx(float(t.get_shader_parameter("detail_tile_a")), TILE_A)
			and is_equal_approx(float(t.get_shader_parameter("detail_tile_b")), TILE_B)
			and is_equal_approx(float(t.get_shader_parameter("detail_tile_macro")), TILE_MACRO),
			"三档平铺尺寸 %s / %s / %s 米（A、B 不整除才不叠出规则图案）"
			% [TILE_A, TILE_B, TILE_MACRO])
	_ok(float(t.get_shader_parameter("detail_lo")) < 1.0
			and float(t.get_shader_parameter("detail_hi")) > 1.0,
			"细节值域映射 [%.2f, %.2f] 在 shader 侧（含提亮的一半）"
			% [float(t.get_shader_parameter("detail_lo")), float(t.get_shader_parameter("detail_hi"))])
	_ok(float(t.get_shader_parameter("ground_emission_energy")) > 0.0,
			"地面自发光地板有能量（最暗处不至于死黑）")
	_ok(float(t.get_shader_parameter("albedo_saturation")) >= 1.0,
			"底色饱和度补偿 ≥ 1.0（补回被蓝色天光洗掉的那一档）")
	_ok(float(t.get_shader_parameter("map_size")) == 1024.0, "map_size 随配置走")
	# 换一张不同尺寸的世界重建：贴图实例必须还是同一张（内容与世界尺寸无关）
	var cfg2 := MapConfig.new()
	cfg2.map_size = 4096.0
	var mf2 := MaterialFactory.new()
	mf2.build(cfg2, _make_data())
	_ok(is_same(mf2.terrain.get_shader_parameter("detail_map"), det)
			and float(mf2.terrain.get_shader_parameter("map_size")) == 4096.0,
			"换世界尺寸后贴图复用、不重建（细节贴图与世界尺寸 / 种子无关）")

# ---------------------------------------------------------------- 环境 / 天空
func _check_environment() -> void:
	print(" · 环境与天空接线")
	var cycle := _make_cycle(12.0)
	var env: Environment = cycle.env
	_ok(env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY,
			"环境光取自天空（不再是固定灰）")
	_ok(_near(env.ambient_light_sky_contribution, DayNightCycle.AMBIENT_SKY_CONTRIBUTION),
			"天空贡献 %.2f" % env.ambient_light_sky_contribution)
	_ok(env.ssao_enabled, "SSAO 开着（模型与地面的接触阴影全靠它）")
	_ok(env.fog_mode == Environment.FOG_MODE_DEPTH and _near(env.fog_depth_begin, 420.0),
			"雾是深度雾、起始 420 m（视距量，不随地图尺寸缩放）")
	_ok(_near(env.fog_sky_affect, 0.10) and _near(env.fog_aerial_perspective, 0.35),
			"雾对天空只轻微影响（0.10）、保留空气透视（0.35）")
	_ok(env.glow_enabled and env.tonemap_mode == Environment.TONE_MAPPER_FILMIC,
			"glow + filmic 色调映射")

	_ok(cycle.sky_mat is ShaderMaterial
			and cycle.sky_mat.shader != null
			and cycle.sky_mat.shader.resource_path == DayNightCycle.SKY_SHADER,
			"天空材质是自写着色器 %s" % DayNightCycle.SKY_SHADER)
	var missing: Array[String] = []
	for k in DayNightCycle.SKY_CONSTANTS:
		if cycle.sky_mat.get_shader_parameter(k) == null:
			missing.append(String(k))
	_ok(missing.is_empty(),
			"SKY_CONSTANTS 全部赋过值（没赋过的 uniform 读回 null，shader 里静默用默认值）%s"
			% ("" if missing.is_empty() else " 缺：" + ", ".join(missing)))
	_ok(_near(float(cycle.sky_mat.get_shader_parameter("cloud_speed")), 0.0),
			"cloud_speed = 0（环境光取自天空后，云一动就得每帧重算辐照度 → 环境光闪）")

# ---------------------------------------------------------------- 时段曲线
func _check_dusk_and_night() -> void:
	print(" · 昼夜曲线与天色")
	var cycle := _make_cycle(12.0)
	_ok(_near(cycle.night_amount, 0.0) and _near(cycle.day_amount, 1.0),
			"正午：night_amount 0 / day_amount 1")
	var top: Color = cycle.sky_mat.get_shader_parameter("sky_top")
	var sun_dir: Vector3 = cycle.sky_mat.get_shader_parameter("sun_direction")
	_ok(top != null and top.b > top.r, "正午天色偏蓝（sky_top 的 B > R）")
	_ok(_near(float(cycle.sky_mat.get_shader_parameter("day_factor")), 1.0),
			"正午 day_factor = 1（云与太阳辉光全开）")
	_ok(sun_dir != null and sun_dir.y > 0.9, "正午太阳方向朝天顶（y=%.2f）" % sun_dir.y)

	# 日落：霞光权重必须真的起来，而且地平线要暖 —— 这是 ② 里被修掉的「看不到晚霞」
	cycle.time_of_day = 17.9 / 24.0
	cycle._apply()
	var dusk: float = cycle.sky_mat.get_shader_parameter("dusk_factor")
	var hor: Color = cycle.sky_mat.get_shader_parameter("sky_horizon")
	_ok(dusk > 0.9, "17:54 霞光权重 %.2f（旧斜率 5.0 在这里只有 0.09，等于没有晚霞）" % dusk)
	_ok(hor != null and hor.r > hor.b, "日落地平线变暖（R %.2f > B %.2f）" % [hor.r, hor.b])
	# 17:54 太阳还在地平线上方一点点：白昼权重已经很低，但 night_amount 也还没起来
	# （night 要等太阳真正落下去才涨）—— 这两个数一起说明「正在日落，不是已经入夜」
	_ok(cycle.day_amount < 0.2 and cycle.night_amount < 0.3,
			"日落：白昼权重已很低、还没算入夜（day %.2f / night %.2f）"
			% [cycle.day_amount, cycle.night_amount])

	# 深夜：天文太阳必须在地平线下 —— 这里若照抄 sun.global_transform，
	# 拿到的会是「当月光用」那行覆盖后的月亮方位（y ≈ -0.79，会错判成还没落山）
	cycle.time_of_day = 23.0 / 24.0
	cycle._apply()
	var ntop: Color = cycle.sky_mat.get_shader_parameter("sky_top")
	var nsun: Vector3 = cycle.sky_mat.get_shader_parameter("sun_direction")
	_ok(_near(cycle.night_amount, 1.0) and _near(cycle.day_amount, 0.0),
			"23:00：night_amount 1 / day_amount 0")
	_ok(ntop != null and ntop.v < 0.12, "深夜天色很暗（sky_top 明度 %.3f）" % ntop.v)
	_ok(nsun != null and nsun.y < -0.9, "深夜太阳方向在地平线下（y=%.3f，月亮的 -0.79 会露馅）" % nsun.y)

# ---------------------------------------------------------------- 推送契约
func _check_push() -> void:
	print(" · 昼夜向 shader 推送")
	var cycle := _make_cycle(12.0)
	# 用真地形材质：它同时声明 night_amount 与 day_amount
	var mf := MaterialFactory.new()
	mf.build(MapConfig.new(), _make_data())
	var mat: ShaderMaterial = mf.terrain
	cycle.register_shader(mat, "night_amount")
	cycle.register_shader(mat, "day_amount", "day")
	# 先在正午推一次：此后 night_amount 已经是 0，白天它一个数都不再变
	cycle._apply()
	_ok(_near(float(mat.get_shader_parameter("day_amount")), 1.0),
			"注册后立刻推一次（不等下一帧）")
	cycle.time_of_day = 7.0 / 24.0
	cycle._apply()
	var early: float = mat.get_shader_parameter("day_amount")
	_ok(early < 0.95,
			"白天 night_amount 恒为 0，day_amount 0.83 照样推得出去（修好的那个 bug：%0.2f 而不是 1.0）" % early)
	cycle.time_of_day = 23.0 / 24.0
	cycle._apply()
	_ok(_near(float(mat.get_shader_parameter("day_amount")), 0.0)
			and _near(float(mat.get_shader_parameter("night_amount")), 1.0),
			"深夜两条曲线各自到位（day 0 / night 1）")

# ---------------------------------------------------------------- 工具
func _make_cycle(hour: float) -> DayNightCycle:
	var cfg := MapConfig.new()
	cfg.start_hour = hour
	var cycle := DayNightCycle.new()
	cycle.setup(cfg, MapData.new())
	_nodes.append(cycle)
	return cycle

## MaterialFactory 只读 data.splat_texture，所以给个 4² 的真贴图就够（不生成世界）
func _make_data() -> MapData:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(0.5, 0.5, 0.5))
	var data := MapData.new()
	data.splat_texture = ImageTexture.create_from_image(img)
	return data

## 贴图统计：均值 / 值域 / 通道均值 / 相邻采样落差（内部 vs 首尾接缝）
func _image_stats(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var sum := 0.0
	var sum_r := 0.0
	var sum_g := 0.0
	var sum_b := 0.0
	var lo := 1.0
	var hi := 0.0
	var n := 0
	for y in range(0, h, SAMPLE_STEP):
		for x in range(0, w, SAMPLE_STEP):
			var c := img.get_pixel(x, y)
			sum += c.r
			sum_r += c.r
			sum_g += c.g
			sum_b += c.b
			lo = minf(lo, c.r)
			hi = maxf(hi, c.r)
			n += 1
	# 接缝落差：内部相邻列/行 vs 首尾相接处。环面映射的来源就是「首尾一样连续」
	var inside_x := 0.0
	var inside_y := 0.0
	var cnt_x := 0
	var cnt_y := 0
	for y in range(0, h, SAMPLE_STEP):
		for x in range(0, w - SAMPLE_STEP, SAMPLE_STEP):
			inside_x += absf(img.get_pixel(x, y).r - img.get_pixel(x + SAMPLE_STEP, y).r)
			cnt_x += 1
	for x in range(0, w, SAMPLE_STEP):
		for y in range(0, h - SAMPLE_STEP, SAMPLE_STEP):
			inside_y += absf(img.get_pixel(x, y).r - img.get_pixel(x, y + SAMPLE_STEP).r)
			cnt_y += 1
	var seam_x := 0.0
	var seam_y := 0.0
	var sx := 0
	var sy := 0
	for y in range(0, h, SAMPLE_STEP):
		seam_x += absf(img.get_pixel(w - 1, y).r - img.get_pixel(0, y).r)
		sx += 1
	for x in range(0, w, SAMPLE_STEP):
		seam_y += absf(img.get_pixel(x, h - 1).r - img.get_pixel(x, 0).r)
		sy += 1
	return {
		"mean": sum / maxf(1.0, float(n)),
		"mean_r": sum_r / maxf(1.0, float(n)),
		"mean_g": sum_g / maxf(1.0, float(n)),
		"mean_b": sum_b / maxf(1.0, float(n)),
		"lo": lo,
		"hi": hi,
		"inside_x": inside_x / maxf(1.0, float(cnt_x)),
		"inside_y": inside_y / maxf(1.0, float(cnt_y)),
		"seam_x": seam_x / maxf(1.0, float(sx)),
		"seam_y": seam_y / maxf(1.0, float(sy)),
	}
