## =============================================================================
##  ToonStyle —— NPR（卡通渲染 / 微缩手办）美术规范的**唯一数值源**
##
##  为什么要有这个类：这套观感的成败全在「一小组颜色 + 一条阶梯曲线 + 圈线宽度」上，
##  而它们会被三个地方用到 —— 3D 着色器（由 MaterialFactory 接线）、2D 战斗场景的
##  角色配色（RigPoses）、以及门禁（tools/visual_check.gd 要断言"这条阶梯还是 3 阶"）。
##  散着写就会出现「地形换了配色、树还是旧绿」这种半截迁移，而且没有地方能断言它一致。
##
##  ---- 三条硬约定（改了要重跑第 15 节清单 + tools/visual_check.gd）----
##  1. **禁止立方体 / 方块 / 体素 / 像素格贴图**。地貌一律是平滑起伏的低多边形网格
##     （地形是高度场，植被/建筑是低面数几何体），面着色在片元里用屏幕空间导数拍平。
##  2. **三阶灰度阶梯**：光照只允许出现 3 档亮度（暗 / 中 / 亮），由 gradient_map 决定。
##     不要改成连续渐变 —— 连续渐变立刻回到"写实塑料感"，这正是要摆脱的东西。
##  3. **反向外壳描边**只给"物体"（植被 / 建筑 / 部队），地形这类开放曲面没有背面可膨胀，
##     它的轮廓靠面着色 + 海岸带配色表达（详见 shaders/terrain.gdshader 头部说明）。
##
##  ---- 调色板来历 ----
##  参考坐标是《塞尔达传说：织梦岛》重制版与《信使》的微缩沙盒：海滨浅滩柠檬黄、
##  低地苹果绿、高山松石青、雪顶纯白、水体清透。全部是**高饱和纯色**，
##  不用任何写实贴图（旧版地形的细节贴图 / 法线贴图在这套规范里全部退场）。
## =============================================================================
class_name ToonStyle
extends RefCounted

# ---------------------------------------------------------------- 阶梯曲线
## 三档光照强度（乘法系数）：暗部不要压死（0.42 仍能看清形体），亮部给到 1.0。
const RAMP_BANDS := [0.42, 0.70, 1.00]
## 采样分辨率：64 已经足够（只有 3 个色块），太大只是白占显存
const RAMP_WIDTH := 64
## 门槛写在着色器里（1/3、2/3），这里只留一份给门禁与文档引用
const RAMP_THRESHOLDS := [1.0 / 3.0, 2.0 / 3.0]

# ---------------------------------------------------------------- 线稿
## 描边色：不是纯黑 —— 纯黑在大太阳下会"抠图感"很重，带一点紫的近黑更像墨线
const OUTLINE_COLOR := Color(0.075, 0.062, 0.105)
## 三类物体的圈线宽度（世界米）。1 像素 ≈ 0.12 m（1600×900、默认正交 size≈107 m）
const OUTLINE_W_VEGETATION := 0.10
const OUTLINE_W_SETTLEMENT := 0.16
const OUTLINE_W_PARTY := 0.14

# ---------------------------------------------------------------- 调色板
# 地表（terrain.gdshader 的默认值必须与这里一致，改一处就要改两处 —— 门禁会比对）
const C_SEABED := Color(0.42, 0.82, 0.72)      ## 水下浅滩：青绿透亮的沙底
const C_SAND := Color(0.96, 0.88, 0.44)        ## 海滨浅滩：柠檬黄
const C_GRASS := Color(0.45, 0.77, 0.29)       ## 低地：苹果绿
const C_GRASS_DARK := Color(0.30, 0.60, 0.25)  ## 背阴 / 高一点的低地绿
const C_ROCK := Color(0.30, 0.72, 0.66)        ## 高山：松石青
const C_ROCK_DARK := Color(0.18, 0.53, 0.55)   ## 陡坡 / 岩阴：深松石
const C_SNOW := Color(0.97, 0.99, 1.00)        ## 雪顶：纯白
const C_ROAD := Color(0.93, 0.82, 0.60)        ## 土路：暖奶黄（不是灰）
const C_DESERT := Color(0.98, 0.86, 0.48)      ## 干旱带：奶油黄
# 水体（water.gdshader 的默认值同样与这里一致）
const C_WATER_SHALLOW := Color(0.40, 0.88, 0.78) ## 浅水：清透薄荷
const C_WATER_DEEP := Color(0.10, 0.55, 0.72)    ## 深水：饱和湖蓝
const C_WATER_FOAM := Color(0.97, 1.00, 0.98)    ## 浪花：近白
const C_WATER_SKY := Color(0.55, 0.82, 0.98)     ## 水面反射的天色

## 阶梯贴图与描边材质的进程内缓存（内容与世界尺寸 / 种子无关，整局只建一次）
static var _ramp: ImageTexture = null
static var _outline_mats: Dictionary = {}

## 3 阶灰度阶梯贴图：x 轴 = N·L（0..1），y 轴无意义（取 0.5）。
## 用 filter_nearest 保证是**硬边**：线性过滤会把三档糊回连续渐变。
static func gradient_map() -> ImageTexture:
	if _ramp != null:
		return _ramp
	var img := Image.create(RAMP_WIDTH, 1, false, Image.FORMAT_RGB8)
	var n := RAMP_BANDS.size()
	for x in RAMP_WIDTH:
		var t := (float(x) + 0.5) / float(RAMP_WIDTH)
		var band := clampi(int(floor(t * float(n))), 0, n - 1)
		var v: float = RAMP_BANDS[band]
		img.set_pixel(x, 0, Color(v, v, v))
	# 不要 mipmap：只有 64×1，mip 会让远处的阶梯互相渗透（等于又变成渐变）
	_ramp = ImageTexture.create_from_image(img)
	return _ramp

## 描边材质（按宽度缓存）。挂在主材质的 next_pass 上。
static func outline_material(width_m: float) -> ShaderMaterial:
	var key := "%.3f" % width_m
	if _outline_mats.has(key):
		return _outline_mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/toon_outline.gdshader")
	m.set_shader_parameter("outline_color", OUTLINE_COLOR)
	m.set_shader_parameter("outline_width", width_m)
	_outline_mats[key] = m
	return m

## 给主材质挂上描边。幂等：重复调用只会换宽度。
static func attach_outline(mat: ShaderMaterial, width_m: float) -> void:
	if mat == null:
		return
	mat.next_pass = outline_material(width_m)

## 自检清场（一个进程里跑多个世界时避免串味）
static func clear_cache() -> void:
	_ramp = null
	_outline_mats.clear()