## =============================================================================
##  visual_check —— NPR 观感层的**接线**定式（不渲染、不建世界，只在命令行用）
##
##  用法：
##    Godot_v4.7-stable_win64_console.exe --headless --path <工程> \
##        --fixed-fps 60 --script res://tools/visual_check.gd
##
##  ---- 这一步为什么存在 ----
##  美术风格的失败方式是**不报错、不崩、指纹不变**：地形换了配色但树还是旧绿、
##  材质建出来了但 gradient_map 忘了赋（Godot 静默用默认值，于是阶梯变回连续渐变）、
##  描边挂上了 next_pass 但宽度是 0、相机改了正交但俯角还跟着缩放联动……
##  这些都只能靠"接线断言"在 headless 下抓住（像素要开窗，见 tools/visual_shot.gd）。
##
##  第十五轮把这一节整体改写成 **NPR 契约**：
##    · 阶梯贴图必须是**恰好 3 档**、硬边、单调、并且四个世界材质拿到的是同一张；
##    · 调色板必须是**高饱和纯色**（柠檬黄 / 苹果绿 / 松石青 / 纯白 / 湖蓝），
##      而且 MaterialFactory 真的把这些值写进了地形材质（不是只写在常量里）；
##    · 闭合几何体（建筑 / 部队 / 植被 / 真模型）必须挂反向外壳描边 next_pass，
##      地形必须**没有**（开放曲面没有背面可膨胀，挂了会得到一片空洞）；
##    · 相机必须是**正交 + 固定等距俯角**，滚轮只改 cam.size、不改俯角；
##    · 光照必须是**硬阴影**（角径 0 / 模糊 0）、线性色调映射、无 SSAO / 无辉光；
##    · 昼夜两条曲线（night_amount / day_amount）仍然推得出去。
##
##  与 tools/visual_shot.gd 的分工：那个拍 PNG（要开窗、人眼判），这个断接线（headless、机器判）。
##
##  退出码：0 = 全部通过；1 = 有断言失败
## =============================================================================
extends SceneTree

## 阶梯贴图的采样容差：8 位通道 → 1/255 的量化误差
const EPS8 := 1.0 / 255.0
## 正交尺寸换算的容差（米）
const EPS_M := 0.01

var _fails: Array[String] = []
var _total: int = 0
## 本工具造的 Node：**必须 free**，否则退出时报 "ObjectDB instances leaked"（门禁当失败）
var _nodes: Array[Node] = []
## 只跑一帧：见 _process 的说明
var _ran: bool = false

## 注意：**不要**在 _initialize() 里跑断言。
## SceneTree._initialize() 执行时 root 还没 enter_tree，此时 add_child() 出来的节点
## 不在场景树里 —— Camera3D.global_position / look_at 会报 "Node not inside tree"，
## 而门禁把 ERROR 行当失败（这两个错在 headless 下还不会中断脚本，最容易漏）。
## 放到第一帧 _process 里，树已就绪，行为与开窗运行时完全一致。
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true

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
	print("[VISUAL] NPR 观感层接线定式（不跑地图生成、不开窗）")
	var ramp := _check_ramp()
	_check_palette()
	_check_materials(ramp)
	_check_camera()
	_check_lighting()
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	print("")
	if _fails.is_empty():
		print("PASS：NPR 观感层接线定式全部通过（%d 项断言）" % _total)
		quit(0)
	else:
		print("FAIL：%d/%d 项断言未通过 —— %s" % [_fails.size(), _total, "; ".join(_fails)])
		quit(1)

# ---------------------------------------------------------------- 阶梯贴图
func _check_ramp() -> ImageTexture:
	print(" · 三阶阶梯贴图（gradient_map）")
	var tex := ToonStyle.gradient_map()
	_ok(tex != null, "阶梯贴图生成出来了")
	if tex == null:
		return null
	_ok(tex.get_width() == ToonStyle.RAMP_WIDTH and tex.get_height() == 1,
			"尺寸 %d×1（x = N·L，y 无所谓）" % ToonStyle.RAMP_WIDTH)
	_ok(not tex.get_image().has_mipmaps(),
			"没有 mipmap（有 mip 的话远处的阶梯会互相渗透，等于又变回连续渐变）")
	_ok(is_same(tex, ToonStyle.gradient_map()), "重复取用返回同一实例（进程内缓存生效）")

	# 逐像素扫一遍：必须只有 3 个不同值，且正好是 RAMP_BANDS，且单调不减
	var img := tex.get_image()
	var values: Array[float] = []
	var distinct: Array[float] = []
	var monotonic := true
	var prev := -1.0
	for x in tex.get_width():
		var v := img.get_pixel(x, 0).r
		values.append(v)
		if v < prev - EPS8:
			monotonic = false
		prev = v
		var seen := false
		for d in distinct:
			if absf(d - v) <= EPS8:
				seen = true
				break
		if not seen:
			distinct.append(v)
	_ok(monotonic, "从左到右单调不减（N·L 越大越亮）")
	_ok(distinct.size() == ToonStyle.RAMP_BANDS.size(),
			"恰好 %d 档（实测 %d 档：%s）" % [ToonStyle.RAMP_BANDS.size(), distinct.size(), str(distinct)])
	var bands_ok := true
	for i in ToonStyle.RAMP_BANDS.size():
		if i >= distinct.size() or not _near(float(distinct[i]), float(ToonStyle.RAMP_BANDS[i]), EPS8 + 0.002):
			bands_ok = false
	_ok(bands_ok, "三档取值与 ToonStyle.RAMP_BANDS 一致：%s" % str(ToonStyle.RAMP_BANDS))
	return tex

# ---------------------------------------------------------------- 调色板
func _check_palette() -> void:
	print(" · 高饱和调色板")
	var c_sand := ToonStyle.C_SAND
	var c_grass := ToonStyle.C_GRASS
	var c_rock := ToonStyle.C_ROCK
	var c_snow := ToonStyle.C_SNOW
	var c_deep := ToonStyle.C_WATER_DEEP
	# 柠檬黄：红绿高、蓝低
	_ok(c_sand.r > 0.90 and c_sand.g > 0.80 and c_sand.b < 0.60,
			"海滨浅滩是柠檬黄 %s（R/G 高、B 明显低）" % c_sand.to_html(false))
	# 苹果绿：绿主导，红略低于绿、蓝最低
	_ok(c_grass.g > c_grass.r and c_grass.g > c_grass.b and c_grass.g > 0.60,
			"低地是苹果绿 %s（G 主导且够亮）" % c_grass.to_html(false))
	# 松石青：绿蓝都高、红最低
	_ok(c_rock.g > 0.60 and c_rock.b > 0.55 and c_rock.r < minf(c_rock.g, c_rock.b),
			"高山是松石青 %s（G/B 高、R 最低）" % c_rock.to_html(false))
	# 纯白：三通道都 > 0.95 且彼此接近
	_ok(c_snow.r > 0.95 and c_snow.g > 0.95 and c_snow.b > 0.95,
			"雪顶是纯白 %s" % c_snow.to_html(false))
	# 深水：蓝主导，且比浅水暗（能分出深浅两档）
	_ok(c_deep.b > c_deep.r and c_deep.b > c_deep.g and c_deep.b > 0.55,
			"深水是饱和湖蓝 %s" % c_deep.to_html(false))
	_ok(c_deep.get_luminance() < ToonStyle.C_WATER_SHALLOW.get_luminance(),
			"深水比浅水暗（两档色带能分开）")
	# 描边不是纯黑：纯黑在大太阳下像抠图
	_ok(ToonStyle.OUTLINE_COLOR.get_luminance() < 0.08
			and ToonStyle.OUTLINE_COLOR.get_luminance() > 0.01,
			"描边色是近黑墨线 %s" % ToonStyle.OUTLINE_COLOR.to_html(false))

# ---------------------------------------------------------------- 材质接线
## 造一个最小世界：平的高度场 + 空 splat 贴图 + 假的高度统计。
## 不用真跑生成（那要几秒），因为这里要验的是**赋值**，不是地形长什么样。
func _check_materials(ramp: ImageTexture) -> void:
	print(" · 世界材质接线")
	var cfg := MapConfig.new()
	var data := MapData.new()
	data.cfg = cfg
	data.hm = Heightmap.new(9, 64.0)   # 9×9 全 0：够 CameraRig 与材质工厂取值
	var gen := HeightmapGenerator.new(cfg)
	# 不跑 generate()（那要几百毫秒）：只把两条分位数线填成可用的值，
	# 因为这里验的是"材质有没有拿到并写进去"，不是地形长什么样。
	gen.h_rock_line = 88.0
	gen.h_snow_line = 118.0
	data.gen = gen
	data.splat_texture = ImageTexture.create_from_image(
			Image.create(4, 4, false, Image.FORMAT_RGBA8))

	var mf := MaterialFactory.new()
	mf.build(cfg, data)

	# 1) 四个材质都吃同一张阶梯贴图
	var mats := {
		"terrain": mf.terrain,
		"settlement": mf.settlement,
		"party": mf.party,
		"vegetation": mf.vegetation,
	}
	for k in mats:
		var m: ShaderMaterial = mats[k]
		_ok(m != null and m.shader != null, "%s 材质建出来了" % k)
		var got = m.get_shader_parameter("gradient_map")
		_ok(got != null and is_same(got, ramp), "%s 的 gradient_map 指向同一张阶梯贴图" % k)
	# 2) 地形：调色板逐条写进去（不是只写在 ToonStyle 常量里）
	var pairs := [
		["color_seabed", ToonStyle.C_SEABED],
		["color_sand", ToonStyle.C_SAND],
		["color_grass", ToonStyle.C_GRASS],
		["color_grass_dark", ToonStyle.C_GRASS_DARK],
		["color_rock", ToonStyle.C_ROCK],
		["color_rock_dark", ToonStyle.C_ROCK_DARK],
		["color_snow", ToonStyle.C_SNOW],
		["color_road", ToonStyle.C_ROAD],
		["color_desert", ToonStyle.C_DESERT],
	]
	var palette_ok := true
	for p in pairs:
		var got = mf.terrain.get_shader_parameter(String(p[0]))
		if got == null or not (got as Color).is_equal_approx(p[1]):
			palette_ok = false
			print("        缺 %s（读回 %s）" % [p[0], str(got)])
	_ok(palette_ok, "地形调色板 9 条全部显式写入")
	_ok(_near(float(mf.terrain.get_shader_parameter("beach_width")), MaterialFactory.BEACH_WIDTH),
			"沙滩带宽 = %.1f m" % MaterialFactory.BEACH_WIDTH)
	_ok(mf.terrain.next_pass == null,
			"地形**没有**描边 pass（开放高度场没有背面可膨胀，挂了只会得到空洞）")

	# 3) 闭合几何体必须挂反向外壳描边，宽度与常量一致
	var expect := {
		"settlement": ToonStyle.OUTLINE_W_SETTLEMENT,
		"party": ToonStyle.OUTLINE_W_PARTY,
		"vegetation": ToonStyle.OUTLINE_W_VEGETATION,
	}
	for k in expect:
		var m: ShaderMaterial = mats[k]
		var np := m.next_pass
		var ok := np != null and np is ShaderMaterial
		_ok(ok, "%s 挂了反向外壳描边 next_pass" % k)
		if not ok:
			continue
		var om := np as ShaderMaterial
		_ok(om.shader != null and String(om.shader.resource_path).ends_with("toon_outline.gdshader"),
				"%s 的描边用的是 toon_outline.gdshader" % k)
		_ok(_near(float(om.get_shader_parameter("outline_width")), float(expect[k])),
				"%s 的描边宽度 = %.2f m" % [k, float(expect[k])])
		_ok((om.get_shader_parameter("outline_color") as Color).is_equal_approx(ToonStyle.OUTLINE_COLOR),
				"%s 的描边色 = 墨线色" % k)

	# 4) 真模型材质（势力染色）同样要有阶梯 + 描边
	var mm := MaterialFactory.model_material(cfg, Color(0.4, 0.6, 1.0))
	_ok(mm.get_shader_parameter("gradient_map") != null, "真模型材质有 gradient_map")
	_ok(_near(float(mm.get_shader_parameter("posterize")), MaterialFactory.MODEL_POSTERIZE),
			"真模型图集色阶 = %.0f 档（写实明暗被压成平涂）" % MaterialFactory.MODEL_POSTERIZE)
	_ok(mm.next_pass != null, "真模型材质挂了描边")
	MaterialFactory.clear_model_materials()

# ---------------------------------------------------------------- 相机
func _check_camera() -> void:
	print(" · 正交等距相机")
	var cfg := MapConfig.new()
	var data := MapData.new()
	data.cfg = cfg
	data.hm = Heightmap.new(9, 64.0)
	var player := Node3D.new()
	_nodes.append(player)
	root.add_child(player)   # 必须在树里：CameraRig._apply() 要 global_position / look_at
	var rig := CameraRig.new()
	_nodes.append(rig)
	root.add_child(rig)
	rig.setup(cfg, data, player)
	_ok(rig.cam != null and rig.cam.projection == Camera3D.PROJECTION_ORTHOGONAL,
			"投影是**正交**（PROJECTION_ORTHOGONAL）")
	_ok(rig.cam.keep_aspect == Camera3D.KEEP_HEIGHT,
			"keep_aspect = KEEP_HEIGHT（cam.size = 可视高度）")
	_ok(_near(rig.pitch_deg, CameraRig.ISO_PITCH_DEG, 0.01),
			"俯角锁在等距角 %.3f°" % CameraRig.ISO_PITCH_DEG)
	_ok(_near(rad_to_deg(rig.yaw), CameraRig.ISO_YAW_DEG, 0.01),
			"默认朝向 %.1f°（菱形铺开）" % CameraRig.ISO_YAW_DEG)
	var want_size := cfg.cam_default_height_m() * CameraRig.ORTHO_SIZE_PER_HEIGHT
	_ok(_near(rig.cam.size, want_size, EPS_M),
			"默认可视高度 %.2f m（= 缩放高度 × %.2f）" % [want_size, CameraRig.ORTHO_SIZE_PER_HEIGHT])

	# 缩放只改尺寸、不改俯角 —— 这是"等距"的定义
	var pitch_before := rig.pitch_deg
	var size_before := rig.cam.size
	rig.zoom_height = clampf(rig.zoom_height * 0.5, cfg.cam_min_height_m(), cfg.cam_max_height_m())
	rig._apply_projection()
	_ok(_near(rig.pitch_deg, pitch_before, 1e-6), "缩放不改俯角（等距不联动）")
	_ok(rig.cam.size < size_before - 0.01, "缩放改了 cam.size（%.2f → %.2f）" % [size_before, rig.cam.size])

# ---------------------------------------------------------------- 光照 / 环境
func _check_lighting() -> void:
	print(" · 硬阴影 + 环境")
	var cfg := MapConfig.new()
	var data := MapData.new()
	data.cfg = cfg
	data.hm = Heightmap.new(9, 64.0)
	var dn := DayNightCycle.new()
	_nodes.append(dn)
	dn.setup(cfg, data)

	_ok(dn.sun != null and dn.sun.shadow_enabled, "太阳开着阴影")
	_ok(_near(dn.sun.light_angular_distance, 0.0, 1e-6), "光角径 = 0（硬阴影，不是软阴影）")
	_ok(_near(dn.sun.shadow_blur, 0.0, 1e-6), "阴影模糊 = 0（边缘像刀切）")
	_ok(dn.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
			"阴影用 PSSM 四级联（**不是 SHADOW_ORTHOGONAL**：正交相机下那条路径会让"
			+ "硬阴影沿等高线出麻点，实测整片草坡像等高线地图）")
	_ok(dn.sun.directional_shadow_max_distance >= 320.0,
			"阴影覆盖 %.0f m（正交拉远后脚下也有影子）" % dn.sun.directional_shadow_max_distance)
	_ok(dn.sun.shadow_normal_bias >= 0.8,
			"法线偏移 %.2f（硬阴影抗自阴影麻点）" % dn.sun.shadow_normal_bias)
	# 正午太阳要被"封顶"：不封顶时 N·L ≈ 1，三阶光影全落进亮档，整图一块死平
	dn.time_of_day = 0.5
	dn._apply()
	var noon_elev := -rad_to_deg(dn.sun.rotation.x)
	_ok(noon_elev <= DayNightCycle.SUN_ELEV_CAP_DEG + 0.01,
			"正午光照高度角 %.1f° ≤ 封顶 %.0f°（永远留一点斜光，影子不会缩到脚下）"
			% [noon_elev, DayNightCycle.SUN_ELEV_CAP_DEG])

	var env := dn.env
	_ok(env.tonemap_mode == Environment.TONE_MAPPER_LINEAR, "线性色调映射（不把高饱和色拉灰）")
	_ok(not env.ssao_enabled, "SSAO 关闭（AO 的脏边会弄脏平涂色块）")
	_ok(not env.glow_enabled, "辉光关闭（白雪花不会被 bloom 糊掉）")
	_ok(env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY,
			"环境光仍来自天空（NPR 也要有方向感，不能拍成死平）")
	_ok(_near(env.ambient_light_sky_contribution, DayNightCycle.AMBIENT_SKY_CONTRIBUTION),
			"天空占比 %.2f（其余用逐时颜色兜底）" % DayNightCycle.AMBIENT_SKY_CONTRIBUTION)
	_ok(env.fog_depth_begin >= 600.0,
			"雾起始 %.0f m（微缩沙盒要看清楚每一块地的颜色）" % env.fog_depth_begin)

	# 昼夜推送：两条曲线都要推得出去（白天的 night_amount 恒为 0 —— 只看它的话
	# day_amount 涨起来也推不出去，旧版踩过这个坑，这里焊死）
	var probe := ShaderMaterial.new()
	probe.shader = load("res://shaders/terrain.gdshader")
	dn.register_shader(probe, "night_amount")
	dn.register_shader(probe, "day_amount", "day")
	dn.time_of_day = 0.5      # 正午
	dn._apply()
	var day_noon := float(probe.get_shader_parameter("day_amount"))
	dn.time_of_day = 0.0      # 午夜
	dn._apply()
	var day_midnight := float(probe.get_shader_parameter("day_amount"))
	var night_midnight := float(probe.get_shader_parameter("night_amount"))
	_ok(day_noon > 0.95, "正午 day_amount = %.2f（白昼权重推得出去）" % day_noon)
	_ok(day_midnight < 0.05, "午夜 day_amount = %.2f（跟着天黑归零）" % day_midnight)
	_ok(night_midnight > 0.90, "午夜 night_amount = %.2f（夜间压暗推得出去）" % night_midnight)