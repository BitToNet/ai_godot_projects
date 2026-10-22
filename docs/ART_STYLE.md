# 美术风格规范 · NPR 微缩手办（第十五轮迁移）

> 一句话：**《塞尔达传说：织梦岛》重制版 / 《信使》**式的自然起伏低多边形微缩沙盒 ——
> 高饱和纯色大色块、三阶硬光影、干净墨线轮廓、正交等距俯视。
> 这不是"写实风格的低配版"，而是一套**独立的美术规范**：任何让画面更像照片的改动都是回退。

---

## 1. 硬禁令（不可协商）

| 禁止 | 为什么 |
|---|---|
| **立方体 / 方块 / 体素**（NO Voxels, NO Cubes） | 地貌必须是连续起伏的曲面。一旦出现方块，"微缩沙盒"就变成"另一款体素游戏" |
| **Minecraft 式方块贴图 / 像素格** | 同上：格状纹理是最容易被认出来的方块语言 |
| **写实油贴图 / 照片纹理 / 法线细节贴图** | 旧版地形的 9 m 法线 + 13 m 反照率细节层已经**整层删除**；本规范靠大色块与硬光影成立 |
| 连续明暗渐变 | 光照只允许 3 档（见 §3）；连续渐变会立刻回到"写实塑料感" |
| 软阴影 / 大光角 | 影子必须是"一块色"，不是"一片晕" |

---

## 2. 术语对照：需求写法是 three.js，本工程是 Godot 4.7

需求里出现的 API 名字来自 three.js。本工程是 Godot 4.7 / GDScript，**逐条给出等价实现**：

| three.js 写法 | 本工程的 Godot 实现 | 落点 |
|---|---|---|
| `PlaneGeometry` + 连续分形 Perlin / Simplex | 高度场 `Heightmap` + `TerrainManager` 分块网格（本来就是连续 fBm，无方块） | `scripts/core/Heightmap.gd`、`scripts/terrain/TerrainManager.gd` |
| `geometry.toNonIndexed()` + `computeVertexNormals()` 做面着色 | **不真去索引**：片元里 `cross(dFdx(VERTEX), dFdy(VERTEX))` 把每个三角形拍平 | `shaders/terrain.gdshader`、`shaders/water.gdshader` |
| `MeshToonMaterial` + `gradientMap` | 自写 `shader_type spatial` + `light()` + 64×1 三阶阶梯贴图 | `scripts/world/ToonStyle.gd`、5 个世界 shader |
| 反向外壳 Inverted Hull（`BackSide` + 沿法线膨胀） | `next_pass` + `render_mode cull_front` + 平滑法线膨胀 + 近黑 | `shaders/toon_outline.gdshader` |
| `OrthographicCamera` | `Camera3D.PROJECTION_ORTHOGONAL` + 固定俯角 35.264° | `scripts/camera/CameraRig.gd` |
| `PCFShadowMap`（硬阴影） | 项目设置 `soft_shadow_filter_quality=1`（PCF5）+ 光角径 0 + 阴影模糊 0 + PSSM 4 级 | `project.godot`、`scripts/env/DayNightCycle.gd` |
| `DirectionalLight` + 柔和 `AmbientLight` | `DirectionalLight3D`（能量 0.90）+ `WorldEnvironment` 天空环境光（能量 0.26 / 0.20） | 同上 |

> **为什么地形不真去索引**：`toNonIndexed()` 会把 LOD0 每块网格从 1089 顶点涨到 6144，
> 建块耗时与显存一起翻几倍，用来买的只是"面法线"——而面法线在片元里用屏幕空间导数
> 一算就有，**逐像素结果完全相同**。更关键的是：几何不动，`scale_probe` 的
> `terrain_pos_hash` / `terrain_idx_hash` / `terrain_lod0_verts` 全部不需要重基线，
> 平滑法线也还在（反向外壳膨胀必须用它，见 §4）。

---

## 3. 五条渲染标准

### 3.1 地貌：平滑起伏 + 面着色

- 地形是连续分形高度场，**没有任何方块**；网格按 LOD 分块（32/16/8/4 四边形）。
- 面着色在片元里做：视图空间位置对 `x`/`y` 求导再叉积，得到**面法线**，再乘 `FRONT_FACING` 修正背面。
- 修边裙边（skirt）与 LOD 边界沿用旧逻辑，不参与造型。

### 3.2 着色管线：三阶硬阶梯

- 所有世界材质（地形 / 水面 / 植被 / 建筑 / 真模型）都吃同一张 `gradient_map`：
  64×1、3 档（`0.42 / 0.70 / 1.00`）、`filter_nearest`、**无 mipmap**。
- 采样坐标是 `N·L`，于是"亮 / 中 / 暗"是三块平色，而不是一条渐变。
- 阶梯定义只有一个源：`scripts/world/ToonStyle.gd` 的 `RAMP_BANDS`；
  shader 里的默认值只是兜底，`tools/visual_check.gd` 会断言两者一致。

### 3.3 描边：反向外壳（Inverted Hull）

- 做法：沿**平滑法线**把网格向外膨胀 `outline_width` 米，只渲染背面（`cull_front`），涂墨线色。
- 挂在主材质的 `next_pass` 上，**不复制节点**、不额外 MeshInstance，与主 pass 共享实例数据。
- 宽度（世界米，1 px ≈ 0.12 m）：植被 0.10 / 部队 0.14 / 建筑 0.16。
- 非等比缩放的 GLB 会除掉模型缩放，保证线宽不随建筑大小变粗。

**地形为什么没有描边**：反向外壳依赖"背面"。地形是一张**开放的**高度场曲面，从上方看没有背面，
膨胀后 `cull_front` 什么都不剩。地形的轮廓感由另外两件事表达：

1. 面着色的硬转折（山脊线天然是一道明暗分界）；
2. 海岸线：`|h - sea_level| < 0.7 m` 的一圈深柠檬湿沙（`color_tide`），把水陆分界"画"出来。

参考作品里被描边的也是树、房子、角色这些**闭合物体**，不是地面本身。

### 3.4 调色板：高饱和纯色

| 语义 | 常量（`ToonStyle`） | RGB | HEX |
|---|---|---|---|
| 海滨浅滩 | `C_SAND` | 0.96, 0.88, 0.44 | `#F5E070` |
| 水下浅滩 | `C_SEABED` | 0.42, 0.82, 0.72 | `#6BD1B8` |
| 低地（苹果绿） | `C_GRASS` | 0.45, 0.77, 0.29 | `#73C44A` |
| 低地背阴 | `C_GRASS_DARK` | 0.30, 0.60, 0.25 | `#4D9940` |
| 高山（松石青） | `C_ROCK` | 0.30, 0.72, 0.66 | `#4DB8A8` |
| 陡坡岩阴 | `C_ROCK_DARK` | 0.18, 0.53, 0.55 | `#2E878C` |
| 雪顶 | `C_SNOW` | 0.97, 0.99, 1.00 | `#F7FCFF` |
| 土路 | `C_ROAD` | 0.93, 0.82, 0.60 | `#EDD199` |
| 干旱带 | `C_DESERT` | 0.98, 0.86, 0.48 | `#FADB7A` |
| 浅水 | `C_WATER_SHALLOW` | 0.40, 0.88, 0.78 | `#66E0C7` |
| 深水 | `C_WATER_DEEP` | 0.10, 0.55, 0.72 | `#1A8CB8` |
| 浪花 | `C_WATER_FOAM` | 0.97, 1.00, 0.98 | `#F7FFFA` |
| 水面天色 | `C_WATER_SKY` | 0.55, 0.82, 0.98 | `#8CD1FA` |
| 墨线 | `OUTLINE_COLOR` | 0.075, 0.062, 0.105 | `#13101B` |

- 水体半透明：浅水 alpha 0.52、深水 0.80，底色透出浅滩的柠檬黄 / 水下青绿。
- 水体三档分界按**本图的水深分布**定：1.5 m / 6.0 m（不是写实水体的 3 / 11 m）。
- 外海**不刷浪花**（`WaterBuilder` 给海洋传 `foam_strength = 0`）：这张地图的海岸是一整片潟湖
  （海底 0~0.2 m 铺出去上百米），任何基于水深的浪花判据都会把整片浅滩算成水线，
  结果要么全白、要么满海白斑。浪花只留给有真实坡度的河流与湖泊（岸边浪花按
  **海底坡度** + 噪声判据生成，`shore = 浅 × 陡`）。
- 水面 `light()` **不乘 `ATTENUATION`**：水面不吃投影，否则树影会在水面上变成一块块深色油斑。
- 色带边界一律用 `step()` 硬切，禁止 `smoothstep` 羽化（羽化 = 渐变 = 写实）。

### 3.5 光影与视角：正交等距 + 硬阴影

| 项 | 值 | 说明 |
|---|---|---|
| 投影 | `PROJECTION_ORTHOGONAL` | 没有近大远小，远近物体同尺寸 —— 手办感的核心 |
| 俯角 | 固定 **35.264°**（`atan(1/√2)`） | 真正等距；**不再随缩放联动** |
| 默认朝向 | 45° | 地块呈菱形铺开 |
| 缩放 | `cam.size = zoom_height × 1.19` | 默认 90 m → 可视高度 107 m（与旧透视机位观感对齐） |
| 太阳 | `DirectionalLight3D`，角径 0，模糊 0，`shadow_bias 0.06` / `normal_bias 1.4` | 硬阴影，边缘像刀切；bias 只用来压树冠 / 屋顶的自阴影 |
| 阴影覆盖 | 360 m，`SHADOW_PARALLEL_4_SPLITS` | 正交相机配 `SHADOW_ORTHOGONAL` 会沿等高线出"梯田"麻点，**必须**用 PSSM |
| 地形投影 | **关闭**（只接收） | 高度场是开放曲面，自阴影在缓坡上就是成片梯田；树 / 屋 / 部队的影子照旧落在地上 |
| 环境光 | 天空 0.60 + 逐时颜色，能量 0.26 / 0.20 | 再高会把高饱和平色洗成白色（实测） |
| 色调映射 | `TONE_MAPPER_LINEAR`、曝光 1.0 | filmic 会把高饱和色拉灰 |
| 后处理 | SSAO **关**、glow **关** | AO 脏边与 bloom 都会糊掉平色块 |
| 雾 | 700 → 3400 m，密度 0.70 | 只用来藏地图切边 |

> **正午压角度（`SUN_ELEV_CAP_DEG = 58°`）**：太阳真的爬到 90° 时，所有法线都接近"朝上"，
> 三档光影会塌成同一档，影子也缩到脚底 —— 画面立刻变回一块平涂。所以光的方向封顶在 58°，
> 而天空球的 `sun_direction` 仍用真实高度角（日落的天色不受影响）。
> 这是"观感优先"的取舍，不是物理正确的太阳。

---

## 4. 数据流与不变量

```
MapConfig / MapData
   └─ MaterialFactory.build()
        ├─ ToonStyle.gradient_map()  ← 唯一的阶梯贴图（进程内缓存）
        ├─ terrain   = terrain.gdshader + 调色板 9 条 + splat / 雾 / 昼夜
        ├─ settlement/party = settlement.gdshader + next_pass(描边 0.16/0.14 m)
        ├─ vegetation = vegetation.gdshader + next_pass(描边 0.10 m)
        └─ model_material(tint) = settlement_model.gdshader + next_pass(描边 0.16 m)
   └─ DayNightCycle.register_shader()  → night_amount / day_amount / night_glow
   └─ FogOfWar                        → fog_map / fog_enabled / fog_darkness
```

仍然必须保持的接口（改名会让昼夜 / 迷雾 / 资产检查**静默**失效）：

- 昼夜：`night_amount`（地形 / 植被 / 水面）、`day_amount`（地形）、`night_glow`（建筑 / 部队 / 真模型）
- 迷雾：`fog_map`、`fog_enabled`、`fog_darkness`、`map_size`
- 真模型材质：`albedo_tex`、`tint`、`tint_strength`、`night_glow`、`map_size`、`fog_enabled`（`asset_check` 逐条断言）

**生成指纹不变**：以上全是观感层，`cfg.make_rng()` 的抽取顺序一处没动，
`3d2a1dd217ec…` 应保持一字不差。

---

## 5. 怎么验

| 工具 | 验什么 | 是否需要开窗 |
|---|---|---|
| `tools/visual_check.gd`（门禁 5f） | 阶梯恰好 3 档 / 调色板 9 条真写进材质 / 描边挂载与宽度 / 地形**无**描边 / 正交 + 固定俯角 / 硬阴影 + 线性色调 / 昼夜两条曲线推得出去（63 项断言） | 否 |
| `tools/visual_shot.gd` | 拍 PNG + 亮度 / 饱和度统计（人眼判构图与配色） | 是 |
| `tools/scale_probe.gd`（门禁 7b） | 地形顶点 / 索引 / 法线哈希与 LOD 分块 —— **本轮不需要重基线**（几何没动） | 否 |
| `tools/gen_fingerprint.gd` | 生成指纹 A/B 与归档值 | 否 |

---

## 6. 调参指南（想微调观感时改哪里）

| 想改 | 改哪里 | 注意 |
|---|---|---|
| 三档亮度 | `ToonStyle.RAMP_BANDS` | 改完 `visual_check` 会立刻比对；shader 默认值不用同步（不是它驱动的） |
| 地形配色 / 带子宽度 | `ToonStyle.C_*` + `MaterialFactory._apply_terrain_palette` | 两处必须一起改（门禁逐条比对） |
| 描边粗细 | `ToonStyle.OUTLINE_W_*` | 1 px ≈ 0.12 m；超过 0.30 m 会变成粗墨块 |
| 沙滩宽度 | `MaterialFactory.BEACH_WIDTH` | 6 m ≈ 默认视距 50 px |
| 陡坡转岩石 | `MaterialFactory.SLOPE_ROCK` | 0.42 ≈ 32.5° |
| 正交缩放手感 | `CameraRig.ORTHO_SIZE_PER_HEIGHT` | 1.19 对齐旧透视观感；改它会改变"滚一格看多远" |
| 等距俯角 | `CameraRig.ISO_PITCH_DEG` | 改它就不再是等距（构图会歪），只在拍对比图时用 `pitch_deg` 临时覆盖 |
| 硬阴影边界 | `project.godot` 的 `soft_shadow_filter_quality` + `DayNightCycle` 的角径 / 模糊 | 三处是同一件事，只改一边会被另一边糊回去 |
| 雾的远近 | `DayNightCycle` 的 `fog_depth_begin/end/density` | 太近会把山染灰，失去大色块 |
| 草色斑块 | `terrain.gdshader` 里 `vnoise(w_pos.xz * 0.025)` 那段 | 只影响低地；阈值 0.5 = 深浅各半，调大就变成整片深绿 |
| 正午太阳高度 | `DayNightCycle.SUN_ELEV_CAP_DEG`（58°） | 真 90° 正午会让三档光影塌成一档、影子也没了；只压**光的方向**，天空仍是真高度 |
| 水面浪花 | `WaterBuilder` 的 `_make_mat(..., foam, ...)` | 海洋传 0；河流 / 湖泊按海底坡度出白边 |

---

## 7. 刻意不做的事

- **不给地形加反向外壳**（几何上不成立，见 §3.3）。
- **不加屏幕空间描边 / 深度边缘后处理**：它会给每一条地形折痕都描边，
  在低多边形起伏上会变成"满屏网格线"，与"干净手办"相反。
- **不开 SSAO / bloom**：理由见 §3.5。
- **不恢复自由俯角**：等距是构图的一部分；`pitch_deg` 只留给截图工具临时覆盖。
- **不引入写实贴图**：真模型图集也只做 5 档色阶化（`MODEL_POSTERIZE`），
  让它服从平涂语言，而不是把写实材质带进场景。
