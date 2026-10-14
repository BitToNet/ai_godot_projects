# 参考项目补齐：计划与进度看板

> **对照对象**：`F:\aigc_code\godot_ai_test`（**只读参考**：不修改、不提交、不 import 任何资源）。
> **用户原始要求**：「先罗列差异，再慢慢补进来」——先给差距清单，然后**一批一批**地搬，
> 每批都以「跑满门禁 + 提交推送」收尾，不做大爆炸式改动。
>
> **本文与 `docs/ROADMAP.md` 的分工**：
> - **本文 = 计划 + 进度看板 + 开工/收尾清单**（要动手时看这一份）。
> - `ROADMAP.md` §17 = **逐批详细记账**（改了什么、为什么、踩了什么坑、实测数字），
>   动手前想深挖某一段的背景就去那里；§16 = 尺寸推导 / 世界换到 4096 m 的历史。
> - `docs/HANDOFF.md` 是**第三轮的旧快照，已过期**，不要拿它当现状（见文末「文档债」）。

最后更新：2026-10-14（第 ② 批交付后）

---

## 一、当前状态卡

| 项 | 现状 |
|---|---|
| 出货默认世界 | **4096 m**（`map_seed = 20250929`） |
| 门禁世界 | **1024 m**（`run_checks.ps1` 默认设 `WARBAND_MAP_SIZE=1024`；4096 m 生成一次 ~25 s，会拖垮门禁） |
| 一键门禁 | `powershell -File tools\run_checks.ps1` → **exit 0，28 项全绿，≈58 s**（不带性能 WARN 行时显示 27 项，**别把项数当固有常量**） |
| 生成指纹 | `958433c2f04c0e39…`（`tools/gen_fingerprint.json`）—— ① ② 两批都**一字未动** |
| 生成统计 | 定居点 18 / 桥梁 7 / 植被 5150 |
| 分批进度 | ① ✅ 已交付 · ② ✅ 已交付 · **③ 待开工（有前置问题）** · ④⑤⑥ 排后面 |
| 待回答的前置问题 | ③/④：GLB 模型**替换**还是**并存**于现有程序化几何？（见 §4.1） |

进度条：`① 点击交互 ██████████ ② 观感提亮 ██████████ ③ 资产+真模型 ░░░░░░░░░░ ④ 动作绑定 ░░░░░░░░░░ ⑤ 玩家面板 ░░░░░░░░░░ ⑥ 商店+菜单+存档 ░░░░░░░░░░`

---

## 二、批次总览

| 批次 | 内容 | 状态 | 风险 | 会动哪些基线 |
|---|---|---|---|---|
| **①** | **点单位交互**：屏幕空间拾取 / 选中面板 / 再点进城 / 追踪 | ✅ `421042e` | 低 | 无（零 RNG 抽取） |
| **②** | **纯观感提亮（零外部资产）**：天光环境光 + SSAO + glow + 雾 + `sky_clouds.gdshader` + 地形细节贴图 | ✅ `fbd8488` | 低（不动生成） | 无（细节贴图用自己的固定种子） |
| **③** | **资产管线 + 定居点用真模型**：CC0 GLB 入库 + `AssetManifest` / `ModelLibrary` + `SettlementBuilder` 改用 `settlement_layout` | ⏸ 待开工 | **中高** | **会动**：植被 / 定居点结构量、`scale_baseline`、`perf_baseline` ⇒ 必须**显式重基线** |
| **④** | **动作绑定位移 + 骑手插槽 + 分帧装配 + 染色/LOD**：`AnimationPlayer`、`anim_speed_reference`、`AssembleQueue`、`WeaponSocket`、`TintMaterial` | ⏸ 待开工 | **高** | 性能基线（100 支部队 × 骨骼动画，无 LOD 会崩） |
| **⑤** | **玩家面板 + 装备/物品**：`Hero` / `ItemCatalog` / `CharacterScreen` + `CampaignState` 扩展 + 6 处接线 | ⏸ 待开工 | 中 | 会碰**已校准的 AI 平衡**基线 |
| **⑥** | **商店 + 按 `kind` 分叉的城镇菜单 + 存档 v2**：`Shop` / `ShopPanel`、`SettlementSystem.menu_entries()`、`SaveGame` 加 `hero` / `shops` | ⏸ 待开工 | 中 | 存档格式要带版本门，**v1 旧档必须仍可读** |

> **③ 的关键位点**：新 `assets/`、`SettlementBuilder.gd`、新 `AssetManifest.gd` / `ModelLibrary.gd`。
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

---

## 四、下一步（③ 的开工前置）

### 4.1 必须先回答：GLB 模型**替换**还是**并存**

这一条决定 ③ 要不要保留「零外部资产」这条隐性承诺，以及性能基线怎么重设。
**没有这个决定之前不要动 `SettlementBuilder.gd`。**

- **替换**：定居点 / 部队模型全部换成 GLB ⇒ 程序化几何退役，观感与动画质量上限高，
  但引入素材授权 / 体积 / 加载三类新问题，且 ④ 的骨骼动画性能风险直接落地。
- **并存**：GLB 只用于"重要角色 / 地标建筑"，其余保持程序化 ⇒ 保住零资产承诺与现有基线，
  但要处理两套模型的 LOD / 染色 / 材质统一。

### 4.2 待用户确认的观感取舍

1. **默认相机视角是否压低**（现在 h=90 m / 俯角 55°，露出天空带需要 ≈12°）；
2. 地面细节强度两个旋钮：`detail_albedo 0.70`、`detail_strength_tex 0.95`（实机若觉得"像毛毡"就往回收）。

### 4.3 ③ 建议的开工顺序（按"先可证伪、后重基线"排）

1. 先做**资产管线骨架**（`AssetManifest` + `ModelLibrary`），只挂一两个模型、**不接** `SettlementBuilder`
   —— 这一步不动世界，可随时回退；
2. 再选**一个** `kind`（建议村庄）换成 GLB 布局，量一次植被 / 结构量 / 帧率的实际变化；
3. 确认方向后再扩到全部定居点，**与重基线一起**只付一次成本（与 §16.4 的纪律一致：
   *同一件事不要在两次重基线里各付一遍*）。

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
| **参考仓库** | `F:\aigc_code\godot_ai_test` **只读**：不修改、不提交、不 import 其资源 |
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
- §17.4 里列的 GPU 开销（SSAO / glow / 云）没有实机数据；
- `perf_baseline.json` 里的 `veg_instances 5163` 与 `nodes 446` 仍是旧值（现为 5150 / 322，属**软指标**，
  门禁只对 `frame_ms` 设阈值，所以一直没动它）—— 要么更新、要么在文件里注明"仅供参考"。
