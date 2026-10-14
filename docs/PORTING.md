# 参考项目补齐：计划与进度看板

> **对照对象**：`F:\aigc_code\godot_ai_test`（**只读参考**：不修改、不提交、不 import 任何资源）。
> **唯一例外（2026-10-14 用户明确授权）**：第 ③ 批的 4 个 CC0 GLB 建筑模型**复用**该仓库里
> 已经转好的 `assets/world/models/*.glb`（KayKit Medieval Hexagon，CC0 1.0，贴图内嵌）。
> 授权范围仅限这 4 个文件，且是**复制到我方仓库**，参考仓库仍只读 —— 见 §六 的豁免行与 ROADMAP §17.5。
> **用户原始要求**：「先罗列差异，再慢慢补进来」——先给差距清单，然后**一批一批**地搬，
> 每批都以「跑满门禁 + 提交推送」收尾，不做大爆炸式改动。
>
> **本文与 `docs/ROADMAP.md` 的分工**：
> - **本文 = 计划 + 进度看板 + 开工/收尾清单**（要动手时看这一份）。
> - `ROADMAP.md` §17 = **逐批详细记账**（改了什么、为什么、踩了什么坑、实测数字），
>   动手前想深挖某一段的背景就去那里；§16 = 尺寸推导 / 世界换到 4096 m 的历史。
> - `docs/HANDOFF.md` 是**第三轮的旧快照，已过期**，不要拿它当现状（见文末「文档债」）。

最后更新：2026-10-14（第 ③-2 批交付后）

---

## 一、当前状态卡

| 项 | 现状 |
|---|---|
| 出货默认世界 | **4096 m**（`map_seed = 20250929`） |
| 门禁世界 | **1024 m**（`run_checks.ps1` 默认设 `WARBAND_MAP_SIZE=1024`；4096 m 生成一次 ~25 s，会拖垮门禁） |
| 一键门禁 | `powershell -File tools\run_checks.ps1` → **exit 0，28 项全绿，≈70 s**（不带性能 WARN 行时 28 项，带则 29 项，**别把项数当固有常量**） |
| 生成指纹 | `958433c2f04c0e39…`（`tools/gen_fingerprint.json`）—— ① ② ③-2 三批都**一字未动** |
| 生成统计 | 定居点 18 / 桥梁 7 / 植被 5150 |
| 分批进度 | ① ✅ · ② ✅ · **③-2 ✅（村庄已换真模型）** · ③-3 ⏸ · ④⑤⑥ 排后面 |
| 下一步入口 | **③-3**：城镇/城堡换真模型 + **一次性显式重基线**（见 §4.3） |
| 待用户拍板的观感取舍 | 默认俯角是否压低、地面细节强度（见 §4.2） |

进度条：`① 点击交互 ██████████ ② 观感提亮 ██████████ ③ 资产+真模型 ████░░░░░░ ④ 动作绑定 ░░░░░░░░░░ ⑤ 玩家面板 ░░░░░░░░░░ ⑥ 商店+菜单+存档 ░░░░░░░░░░`

> ③ 内部拆成三段：**③-1 资产管线骨架 ✅ · ③-2 村庄换真模型 ✅ · ③-3 城镇/城堡 + 一次性重基线 ⏸**。
> 拆分的理由见 §4.3：「先可证伪、后重基线」，重基线只付一次成本。

---

## 二、批次总览

| 批次 | 内容 | 状态 | 风险 | 会动哪些基线 |
|---|---|---|---|---|
| **①** | **点单位交互**：屏幕空间拾取 / 选中面板 / 再点进城 / 追踪 | ✅ `421042e` | 低 | 无（零 RNG 抽取） |
| **②** | **纯观感提亮（零外部资产）**：天光环境光 + SSAO + glow + 雾 + `sky_clouds.gdshader` + 地形细节贴图 | ✅ `fbd8488` | 低（不动生成） | 无（细节贴图用自己的固定种子） |
| **③-1** | **资产管线骨架**：4 个 CC0 GLB 入库 + `AssetManifest` / `ModelLibrary` / `settlement_model.gdshader` + `MaterialFactory` 模型染色 | ✅ 本轮 | 低（不接世界） | 无 |
| **③-2** | **村庄换真模型**：`SettlementBuilder` 走 `VILLAGE_LAYOUT`，程序化小屋降级为兜底；落位判据全部由 `asset_check` 静态断言 | ✅ 本轮 | 中 | 无（**几何不进指纹**，见 §4.1） |
| **③-3** | **城镇 / 城堡换真模型 + 程序化建筑去留 + 一次性重基线**：结算结构量 / 植被 / `scale_baseline` / `perf_baseline` | ⏸ 下一步 | **中高** | **会动**：结构量、`scale_baseline`、`perf_baseline` ⇒ 必须**显式重基线** |
| **④** | **动作绑定位移 + 骑手插槽 + 分帧装配 + 染色/LOD**：`AnimationPlayer`、`anim_speed_reference`、`AssembleQueue`、`WeaponSocket`、`TintMaterial` | ⏸ 待开工 | **高** | 性能基线（100 支部队 × 骨骼动画，无 LOD 会崩） |
| **⑤** | **玩家面板 + 装备/物品**：`Hero` / `ItemCatalog` / `CharacterScreen` + `CampaignState` 扩展 + 6 处接线 | ⏸ 待开工 | 中 | 会碰**已校准的 AI 平衡**基线 |
| **⑥** | **商店 + 按 `kind` 分叉的城镇菜单 + 存档 v2**：`Shop` / `ShopPanel`、`SettlementSystem.menu_entries()`、`SaveGame` 加 `hero` / `shops` | ⏸ 待开工 | 中 | 存档格式要带版本门，**v1 旧档必须仍可读** |

> **③ 的关键位点**：新 `assets/world/models/`、`SettlementBuilder.gd`、新 `AssetManifest.gd` / `ModelLibrary.gd`。
> **④**：`PartyModelBuilder.gd`。**⑤**：`CampaignState.gd`、新 `Hero.gd`。**⑥**：`SettlementSystem.gd`、`SaveGame.gd`。

---

## 三、已交付批次

### ① 点单位交互（`421042e`）

**做了什么**：点地图上的定居点/部队 → 选中并弹面板（可前往 / 进入 / 追踪）→ 再点同一座城 = 进城。

| 类型 | 文件 |
|---|---|
| 新增 | `scripts/core/MapPicker.gd`（屏幕投影拾取）、`scripts/core/SelectionSystem.gd`（选中状态 + 面板数据）、`scripts/ui/SelectionPanel.gd`（非模态面板，零中文字面量）、`tools/selection_check.gd` |
| 改动 | `InputRouter`（新增 `pick_requested` + 可选 `picker`）、`Main`（解释动作）、`WorldGenPipeline`（装配）、`Strings` / `GameState` / `HoverInspector` / `HUD` / `HelpPanel` / `PlayerParty`（新增 `arrived`） |

**关键口径**（细节见 ROADMAP §17.2）：
- 拾取是**屏幕空间**的（不是射线）：半径 = `clampf(span + 6, 14, 90)` px，部队 ×0.85、让先 6 px
  —— 因为领主 AI 会**站在城里**，一律"城优先"会让这些部队永远点不动。
- 第一次点城 = 选中，再点 = 进城（防误触）；「进入」按钮不灰，太远就自动先旅行、到了自动进城。
- 选中面板**不进** `is_any_dialog_open()`（键盘热键照常可用），Esc 让给真模态面板。

**新增门禁**：第 **5e** 步 `tools/selection_check.gd`，66 项断言，0.7 s，不建世界不渲染。

**验收**：门禁 26 项全绿 55.6 s；指纹与统计未变。

**自己踩到的两个坑**（都已写进代码注释）：面板里造了提示 `Label` 却不入树 ⇒ 退出报
`ObjectDB instances leaked`；自检闭包捕获被观察者自己 ⇒ 引用环，RefCounted 永不释放。

### ② 纯观感提亮（`fbd8488`）

**做了什么**：零外部素材，只做颜色 / 光照 / 细节工程（§17.1 的结论是那边的"好看"来自这些，不是 GLB）。

| 分项 | 内容 | 文件 |
|---|---|---|
| ②-a 光照 | 环境光改**天空来源**（`sky_contribution 0.60`，昼 0.90 / 夜 0.36）+ SSAO + glow + 深度雾 420→2600 m + `fog_sky_affect 0.10` / 空气透视 0.35 + FILMIC 曝光 4.0 | `scripts/env/DayNightCycle.gd` |
| ②-b 天空 | 新 `sky_clouds.gdshader`（体积云 + 5 倍频 fbm + 太阳辉光 + 霞光）；`sky_mat` 从 `ProceduralSkyMaterial` 换成 `ShaderMaterial`；黄昏窗口 ±0.14 → **±0.45** | `shaders/sky_clouds.gdshader`（+ `.uid`） |
| ②-c 地表 | 三张细节层（9 m 法线 / 13 m 反照率 MUL / 70 m 大色斑）+ 地面自发光地板 + 线性空间饱和度补偿；程序化烘两张 256² 无缝贴图（环面映射，带 mipmap） | `shaders/terrain.gdshader`、`scripts/world/MaterialFactory.gd` |
| ②-d 推送 | 新增**日间权重** `day_amount` 并推给 shader（原来只有 `night_amount`） | `DayNightCycle.gd`、`WorldGenPipeline.gd` |
| 工具 | `tools/visual_shot.gd`（开窗拍 7 张世界图 + 亮度/饱和/近黑统计，含两个"压平到 12°"才看得到天空的机位）、`tools/visual_check.gd` | `tools/` |

**新增门禁**：第 **5f** 步 `tools/visual_check.gd`，41 项断言，0.5 s（headless 钉"接线与契约"：
天光来源 / SSAO / 每个天空 uniform 是否真赋过值 / `cloud_speed == 0` / 细节贴图均值 1.0 且无缝 /
昼夜推送契约）。**像素**验不了，只能用开窗探针人眼判（`tools/visual_shot.gd`）。

**自检抓到的三个真 bug**（本批最值钱的部分，详见 ROADMAP §17.4）：
1. 细节贴图烘进 **8 位通道**时 >1.0 被静默钳掉 ⇒ 提亮一半全丢、均值 1.0 → 0.958（整图被悄悄压暗）；
2. 地面自发光用 `night_amount` 加权，而它**整个白天恒为 0** ⇒ 黎明自发光全开，把晨雾冲平
   （近黑 31.6% → 3.2%）；改用 `day_amount`；
3. 推送门控只看 `night_amount` ⇒ 白天 `day_amount` 涨了也**推不出去**（已加回归断言）。

**验收**：门禁 **28 项全绿，57.8 s**；指纹 `958433c2f04c0e39…` 与统计均未变；
`perf_probe` 的 `frame_ms` 反而比基线好（idle 0.763 / march 0.992）。

**顺带记录的两件事**：
- **默认视角看不到天空**：俯角 55° + fov 52° ⇒ 画面顶端在地平线下 29°，云只在**压平视角**时直接可见；
  默认视角下天空是通过**环境光与雾色**间接起作用的。是否压低默认视角 = 手感取舍，未擅自动（见 §4.2）。
- **欠账**：SSAO / glow / 天空的 **GPU 开销没测**（headless 测不到），开窗角标显示看云时 ≈15 FPS
  （云是逐像素 5 倍频 fbm，真优化就把倍频降到 3~4）。

### ③-1 + ③-2 资产管线骨架 + 村庄换真模型（本轮）

**做了什么**：4 个 CC0 GLB 建筑入库 → 清单 / 库 / 着色器 / 染色 → 村庄改用真模型布局，
程序化小屋退为兜底。**零世界生成改动**（几何不进指纹，见 §4.1）。

| 类型 | 文件 |
|---|---|
| 新增资产 | `assets/world/models/bld_house_a/b/well/windmill.glb`（4 个，CC0）+ 4 张导入时抽出的图集 PNG + `ATTRIBUTION.md` / `LICENSE.txt` |
| 新增脚本 | `scripts/world/AssetManifest.gd`（清单 + 布局表 + 许可）、`scripts/world/ModelLibrary.gd`（加载/合并 AABB/倍率/接地/外接与内切半径/实例化/材质）、`tools/asset_check.gd`（105 项断言） |
| 新增着色器 | `shaders/settlement_model.gdshader`（势力染色 + 夜灯 + 雾） |
| 改动 | `MaterialFactory`（按势力色缓存模型材质）、`SettlementBuilder`（`_build_village_models` + 落位 `_place_one` + 杂物避让）、`WorldGenPipeline`（注册模型材质）、`tools/visual_shot.gd`（`--focus` + 真模型实例数诊断）、`tools/run_checks.ps1`（导入前置步 + `asset_check` 步） |

**口径与实测数字**（细节见 ROADMAP §17.5）：

- 村庄 = **8 栋**（house_a×4 / house_b×2 / well×1 / windmill×1，照搬参考项目 village 段），
  单村 **10 209 三角形**；9 个村庄 = **72 个 `MeshInstance3D` / 91 881 三角形**（+63 节点 / +63 绘制调用）。
- 落地尺寸是按「替换掉的那套程序化几何」对齐的（house_a 4.0 / house_b 4.6 / well 2.6 / windmill 6.0 米），
  4 个模型接地偏移实测**全为 +0.000**（不需要手工抬 y）。
- 开窗探针实测：`真模型：72 栋 / 9 个村庄`（0 就代表悄悄回退了 —— 这条诊断就是为它加的）；
  村庄机位 `绘制调用 340 / 三角形 194.3 万`。
- **FPS 本轮没测**：`--fixed-fps` 下 `Engine.get_frames_per_second()` 不可用，窗口失焦又被
  系统限帧（角标显示 7）⇒ 真·实时帧率留到 ③-3 与「要不要上 MultiMesh」一起决策（见 §4.3）。
- 门禁 **28 项全绿 69.9 s**；指纹 `958433c2f04c0e39…` 与统计（18 / 7 / 5150）**一字未动**。

**自检与目视抓到的四个真问题**（本批最值钱的部分）：
1. **纯随机角度 + 纯随机半径摆不满**：9 个村只摆下 **62/72 栋**（「随机丢盘子」在 84% 占空比下必然卡住），
   而且摆下的那些里出现过**屋檐插进墙里**（`v3v_near_noon.png` 目视可见）；
   ⇒ 改「角度分槽 + 内切半径判据 + 候选全不合格时取最宽松的」，保证 8 栋一栋不少。
2. **判据用错半径**：拿外接半径（对角线上界）当间距判据，等于要求两栋都按最坏朝向转 45° 也算得出来，
   面积上根本放不下 8 栋；⇒ 改用**内切半径 + 1.1 米余量**，并把「墙体在任何朝向下都不会相交」
   降级成 `asset_check` 的**逐对断言**（最苛刻那对是 house_b↔windmill，余量 0.06 米）。
3. **静态断言当场抓到一个错**：windmill 的 `radius_max 8.5` 让外沿伸到 11.36 米 > 台地平整半径 11.05 米
   —— 人眼看不出来（房子在坡上看着也「站住了」），断言直接红。
4. **杂物会插进真模型**：干草堆 / 木车原来在 ±8 / ±9 米里随机撒点，跟环上的房子必然相撞；
   ⇒ 真模型路径改用同一套判据在**环内侧空当**落位，挑不到就不放（少一个草堆没人看得出来）。

**工具踩坑**：`visual_shot.gd` 的 `_focus_settlement()` 第一版插在 `_run()` **中间**，`_run()` 被从中间截断、
后半截（截图循环）变成它的函数体 ⇒ 被判成协程 ⇒ 整个脚本 Parse Error（已写进代码注释）。

**本轮欠账**（都记着，不含糊）：实时帧率未测；农场色块是**平白亮片**（程序化遗留，见 §七）；
4 个 GLB 各自内嵌**同一张** 1024² 图集（sha256 实测相同），引擎按 4 份上传 ≈5.3 MB，实际 1 份就够
（③-3 若做「合并图集 / 共享纹理」再销账）。

---

## 四、下一步（③-3 的开工前置）

### 4.1 已定：GLB 模型**替换**程序化几何（村庄先行）

**用户 2026-10-14 的决定**：

1. **素材来源 = 复用参考仓库已转好的 CC0 GLB**（KayKit Medieval Hexagon，CC0 1.0，贴图内嵌），
   **不是**从上游 FBX 自己转 —— 上游只发 FBX + 共享图集，转一次的成本对 4 个文件不值得。
   这是一次**显式豁免**（§六「参考仓库只读」那条）：参考仓库仍只读，只是把 4 个文件**复制**进我方仓库。
2. **模型策略 = 替换**：真模型**取代**程序化定居点几何；程序化构造器本轮**保留为兜底**，
   ③-3 再决定去留。
3. **本轮范围 = 村庄**：只动 `kind == VILLAGE`（9 个村）。城镇 / 城堡 + 一次性重基线留在 ③-3。

**为什么 ③-2 不用重基线（这条最容易看错，写清楚）**：生成指纹只覆盖
导航网格 / 定居点数据（`id/name/kind/faction_id/pos/ground_h/radius/garrison/parent_town/neighbors`）
/ 道路 / 桥 / 植被 / 部队，**不含定居点几何**。本轮只换了「摆出来的房子长什么样」，
而且几何 RNG 是按 `cfg.make_rng("settle_geom|%d" % s.id)`（按 id 派生）抽的，
`place_all()` / `_flatten_all()` / `_assign_garrisons()` 与 `radius` / `ground_h` / `garrison` 全都没碰
⇒ 指纹实测一字未变。**后果要记住**：城/堡的程序化几何在 ③-3 之前会**重排一次**（门禁无感、玩家可见），
反正 ③-3 就要把它们换掉。

### 4.2 待用户确认的观感取舍

1. **默认相机视角是否压低**（现在 h=90 m / 俯角 55°，露出天空带需要 ≈12°）；
2. 地面细节强度两个旋钮：`detail_albedo 0.70`、`detail_strength_tex 0.95`（实机若觉得"像毛毡"就往回收）；
3. **新增**：模型势力染色强度 `MaterialFactory.MODEL_TINT_STRENGTH = 0.22`
   （0 = 建筑保持原色，只靠程序化几何那套旗子/营地读势力；1 = 染满）。
   本批取 0.22 是「一眼能分势力、又不把 KayKit 原色洗掉」的折中，**没有实机手感依据**。

### 4.3 ③-3 的开工顺序（按"先可证伪、后重基线"排）

1. **先量实时帧率**（开窗 + 抢占焦点，或临时关掉 `--fixed-fps`）：这是 ③-3 唯一的新增性能前置，
   因为 ③-2 没测出来（见 §三 的欠账）。若村庄机位的实时帧率已明显低于 ② 时的 45~60 FPS，
   **先**把 72 个 `MeshInstance3D` 换成按（模型 × 势力）的 `MultiMeshInstance3D`（最多 12 个绘制调用），
   再往城镇/城堡扩 —— 换法只动 `_build_village_models`，落位判据与 `asset_check` 都不用改。
2. 城镇 / 城堡照 ③-2 的定式扩（布局表 + 落位判据 + 断言），**不接**重基线；
3. 全部定居点确认无误后，**与重基线一起**只付一次成本（`scale_baseline` / `perf_baseline`；
   指纹**不该变** —— 若变了说明碰了 RNG 抽取，要停下来查）。与 §16.4 的纪律一致：
   *同一件事不要在两次重基线里各付一遍*。
4. 顺手的三笔小账（都可独立回退）：4 份重复图集 → 共享/合并；农场色块白片（§七）；
   程序化小屋构造器的去留（留着 = 兜底 + 12 KB 代码，删掉 = 少一条回退路径）。

---

## 五、每批的固定动作（开工 / 收尾清单）

**开工前**

- [ ] 确认工作区状态：`git status --short`（有**与本轮无关**的未提交改动 → 先问用户，别卷进来，规则 G5）
- [ ] 读 `ROADMAP.md` §17 里对应批次的段落 + 那边参考实现的**关键行**（§17.1 给了位置索引）

**动手时**

- [ ] 世界内容相关改动：先想清**是否改 RNG 抽取顺序**（顺序一变 ⇒ 指纹变 ⇒ 必须显式重基线）
- [ ] 观感类改动：先想清**怎么验证**（像素只能用 `tools/visual_shot.gd` 开窗看；接线加进 `visual_check.gd`）
- [ ] 新增断言 / 探针就进 `tools/run_checks.ps1`（并在文件头部的步骤表里补一行说明"为什么值得单独一步"）

**收尾（每批必须全做）**

- [ ] `powershell -File tools\run_checks.ps1` → 必须 `== 全部通过 ==`，零 `ERROR:` / 零 `SCRIPT ERROR`
- [ ] 若动了世界内容：显式重基线（`gen_fingerprint --write-baseline`、`scale_baseline`、`perf_baseline`）
      并在提交信息里说明"有意为之"
- [ ] 改过 `tools/run_checks.ps1` 后：**恢复 UTF-8 BOM**（`edit` 会剥掉它）
- [ ] 新 shader / 新脚本：**连 `.uid` 一起提交**
- [ ] `git add` 只加本轮路径（绝不加 `.godot/`、`icon.svg.import`、参考仓库里的任何东西）
- [ ] 提交信息用中文（`feat:` / `fix:` / `refactor:` / `chore:` / `docs:` / `art:`），
      **BOM-less** 写入临时文件后 `git commit -F`；确认钩子输出 `pushed …`
- [ ] `git rev-list --left-right --count origin/main...main` = `0  0`

**常用命令**

```powershell
# 门禁（Windows PowerShell 5.1；本机没有 pwsh 7）
powershell -ExecutionPolicy Bypass -File tools\run_checks.ps1

# 世界观感截图（**会短暂开一个真窗口**；音频静音；PNG 只写在 user://shots，不在仓库里）
$env:WARBAND_MAP_SIZE="1024"
& "G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe" --path . `
    --resolution 1600x900 --audio-driver Dummy --fixed-fps 60 `
    --script res://tools/visual_shot.gd -- --tag=after

# UI 截图（加载遮罩 / 常规 HUD / 遭遇对话框）
& "G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe" --path . `
    --audio-driver Dummy --fixed-fps 60 --script res://tools/hud_shot.gd -- --tag=after

# 4096 m 大图实测（门禁步骤 7d，默认跳过，一次 80~120 s）
$env:WARBAND_BIG_MAP="1"; powershell -ExecutionPolicy Bypass -File tools\run_checks.ps1

# 单跑某个定式
& "G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe" --headless --path . `
    --fixed-fps 60 --script res://tools/visual_check.gd
```

---

## 六、不要动的东西（硬约束）

| 约束 | 说明 |
|---|---|
| **I 盘 / J 盘** | 全局长期规则：任何访问一律禁止（含搜索、探测、子代理、workflow 间接访问）；受此限制时**停下来告知用户** |
| **引擎** | 只用 `G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe`（4.7 stable）。不另找、不另下、不另装，不全盘搜 `godot*.exe` |
| **参考仓库** | `F:\aigc_code\godot_ai_test` **只读**：不修改、不提交、不 import 其资源。**唯一豁免**：`assets/world/models/bld_house_a/b/well/windmill.glb` 这 4 个 CC0 文件经用户 2026-10-14 明确授权**复制**进我方仓库（`assets/world/models/`，附 `ATTRIBUTION.md` + `LICENSE.txt`）；豁免不扩大、不推定，参考仓库本身仍只读 |
| **RNG 抽取顺序** | 是回归基线（指纹）。任何改变它的改动都必须**显式重基线**并在提交信息里说明"有意为之" |
| **基线文件** | `tools/gen_fingerprint.json` / `perf_baseline.json` / `scale_baseline.json` / `i18n_baseline.json` 都**只能有意更新**，不能"顺手"改 |
| **`SelectionSystem` / `SettlementSystem`** | 不许加 `ctx.settlements` 之类的反向引用（RefCounted 引用环 ⇒ RID 泄漏） |
| **门禁语法** | 只用 Windows PowerShell 5.1（没有 pwsh 7）；错误判定是 `-cmatch 'ERROR:\|SCRIPT ERROR\|Parse Error'`（**大小写敏感**） |
| **`.godot/`** | 引擎缓存，永不提交 |

---

## 七、文档债 / 相关文档

| 文档 | 状态 |
|---|---|
| `docs/PORTING.md`（本文） | 计划与进度看板 —— **要继续做这件事就看这一份** |
| `docs/ROADMAP.md` §17 | 逐批详细记账（改动、实测数字、踩坑），本文的展开版 |
| `docs/ROADMAP.md` §16 | 尺寸推导 / 换到 4096 m 世界的历史（含 `big_map_probe` 实测） |
| `docs/HANDOFF.md` | **第三轮旧快照，已过期**：里面的"当前状态"与"下一步"都不能直接用；要刷新就按现在的事实重写 |
| `README.md` | 玩法 / 操作 / 工程约定的总说明（门禁步骤表、目录结构等） |

**尚未回填的记账**（想做就做，不影响功能）：
- ③-2 的**实时帧率**没测（`--fixed-fps` + 窗口失焦，角标数字不可用）——已列为 ③-3 的第 0 步；
- §17.4 里列的 GPU 开销（SSAO / glow / 云）没有实机数据；
- `perf_baseline.json` 里的 `veg_instances 5163` 与 `nodes 446` 仍是旧值（现为 5150 / 322，属**软指标**，
  门禁只对 `frame_ms` 设阈值，所以一直没动它）—— 要么更新、要么在文件里注明"仅供参考"。

**已知但**不修**的观感债**（本轮目视新发现，下一轮观感批处理）：
- **农场色块是平白亮片**：`SettlementBuilder._farm_plot()` 的 WHEAT/GRASS_PLOT 色块是纯色四边形，
  正午像贴在地上的白纸、夜里**不跟着天黑**（雾与夜间压暗没作用到它）——程序化遗留，与 ③-2 无关，
  但旁边站了真模型之后非常显眼。要修就一起做：给农田一张垄沟纹理 + 接雾/夜色。
- 真模型是**不透明**几何（GLB 没有顶点 alpha），所以程序化小屋那点「窗洞透光」的夜灯效果没有了；
  `settlement_model.gdshader` 目前只能整体染色 + 微微提亮。
