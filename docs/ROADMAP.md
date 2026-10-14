# 开发路线图（Roadmap）

> 本文件是 `ai_godot_projects` 的开发计划与进度台账，由 DSH 会话在只读分析后落档。
> 约定：**不写没验证过的结论**；每完成一项就在第五节更新状态、在第七节记录变更与实测结果。
> 所有行号对应落档时的代码；改动后行号会漂移，以函数名 / 标记注释为准。

- 落档时间：2026-10-12
- 引擎：`G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe`（4.7 stable，GDScript）
- 状态图例：`待办` / `进行中` / `已完成` / `搁置（附原因）`

---

## 一、进度快照（实测基线）

以下数字均为本机实跑所得，可复现；命令见第六节。

| 项目 | 实测值 | 备注 |
|---|---|---|
| 主场景 headless 运行 | **exit 0，无 ERROR / 无脚本报错** | `--headless --fixed-fps 60 --quit-after 900` |
| 地图生成耗时 | **7634 ms / 8682 ms**（两次） | README 声称 3.0 s（Apple M4），口径需统一 |
| 音效合成耗时 | **1709 ms**（28 音色 / 24 路池） | README「1.6~2 s」、`Sfx.gd:60`「≈1.3 秒」、`Main.gd:77`「约 2 秒」三处不一致 |
| 生成内容 | 定居点 18 / 桥梁 7 / 植被实例 5163 | 由 `map_seed = 20250929` 决定 |
| 音效联调（战斗） | **PASS**，19 种音效、累计 57 次播放 | `tools/sfx_battle_check.gd` |
| 音效联调（大地图） | **PASS**，号角 2 / 马蹄 19 / 遭遇 1 | `tools/sfx_map_check.gd` |
| 代码规模 | **51 个 `.gd` / 10545 行 + 4 个 shader / 369 行** | 落档时数值（README:8 的「45 脚本 / 9200 行」已过期）；第一轮后复测为 10725 行 |

> 第一轮改动后的复测见第七节：主场景 exit 0、生成 8133 ms、战斗联调 58 次播放、生成内容统计不变。
| 场景资源 | 1 个 `.tscn`（6 行）、**0 个 `.tres`** | 全部由代码构建 |
| 工程配置 | `project.godot` 33 行，无 `[input]` / `[audio]` / `[autoload]` / `[internationalization]` | 键位全为 `physical_keycode` 硬编码 |
| 仓库卫生 | 工作区干净、`.githooks/post-commit` 生效、`audio_preview/` 零文件入库 | 无外部美术 / 音频资源，「全程序化」为真 |

> 计数注意：统计行数请用 `(Get-Content $f).Count`，**不要**用 `Measure-Object -Line` —— 后者把空行算作 0 行，会少算约 10%。

> 第四轮 4c 改完（2026-10-13）复测（同一口径：`git ls-files -co` 列文件 + `ReadAllLines` 数行，
> 含尚未入库的新文件）：
> **84 个 `.gd` / 16584 行**（`scripts/` 72 / 13243，`tools/` 12 / 3341）+ 4 个 shader / 369 行；
> `project.godot` 仍 **217 行**（本批不加动作）；最大脚本 `BattleScene.gd` 760 / `tools/encounter_check.gd` 575 /
> `SfxSynth.gd` 564（新自检一上来就是第二大脚本 —— 117 项断言都写在一处）。
> 相对 4b-2（83 / 15597）+1 文件 / +987 行：新文件是 `tools/encounter_check.gd`（575 行），
> 其余是遭遇系统的四条分支 + `EncounterDialog` 重写（`tools/` 侧 +661 行）。
>
> 第四轮 4b-2 改完（2026-10-13）复测（同一口径：`git ls-files -co` 列文件 + `ReadAllLines` 数行）：
> **83 个 `.gd` / 15597 行**（`scripts/` 72 / 12917，`tools/` 11 / 2680）+ 4 个 shader / 369 行；
> `project.godot` **211 → 217 行**（`[input]` 段多了 `interact`：29 个动作）；
> 最大脚本 `BattleScene.gd` 760 / `SfxSynth.gd` 564 / `HeightmapGenerator.gd` 555。
> 相对 4b-1（82 / 15072）+1 文件 / +525 行 —— 新文件只有 `scripts/ui/SettlementDialog.gd`（172 行），
> 其余是界面接线与交互键（`tools/` 侧 +219 行：两个自检的断言扩充）。
>
> 第四轮 4b-1 改完（2026-10-13）复测（同一口径：`git ls-files -co` 列文件 + `ReadAllLines` 数行，
> 含尚未入库的新文件）：
> **82 个 `.gd` / 15072 行**（`scripts/` 71 / 12611，`tools/` 11 / 2461）+ 4 个 shader / 369 行；
> `project.godot` 仍 211 行；最大脚本 `BattleScene.gd` 760 / `SfxSynth.gd` 564 / `HeightmapGenerator.gd` 555。
> 相对 4a（80 / 14047）+2 文件 / +1025 行 —— 正是 `SettlementSystem.gd`（逻辑层）与
> `tools/settlement_check.gd`（92 项断言）。
>
> 第四轮 4a 改完（2026-10-13）复测（同一口径：`git ls-files` 列文件 + `ReadAllLines` 数行）：
> **80 个 `.gd` / 14047 行**（`scripts/` 70 / 12047，`tools/` 10 / 2000）+ 4 个 shader / 369 行；
> `project.godot` 仍 211 行；最大脚本 `BattleScene.gd` 760 / `SfxSynth.gd` 564 / `HeightmapGenerator.gd` 555。
> 相对第三轮（77 / 13466）+3 文件 / +581 行 —— 多出来的正是 `EconomyRules.gd` / `CampaignState.gd` /
> `tools/economy_check.gd`。
>
> 第三轮改完（2026-10-13）复测：**77 个 `.gd` / 12872 行 + 4 个 shader / 369 行**；`project.godot` 211 行（多了 `[input]` 段：28 个动作）；`Main.gd` **854 → 191 行**，当前最大的脚本依次是 `BattleScene.gd` 760 / `HeightmapGenerator.gd` 555 / `PlayerFighter.gd` 541 / `SettlementBuilder.gd` 531 / `SfxSynth.gd` 514。

> 工具链注意：本工作区位于 **exFAT** 卷（`F:`，卷标 T7），**不支持硬链接**，因此依赖硬链接式原子写的写文件工具会报 `EISDIR`。新建文件请用 `Set-Content -Encoding utf8`，改已有文件用逐处替换式编辑（rename 在 exFAT 上正常）。
>
> 编码注意（踩过一次）：PowerShell 5.1 的 `Set-Content -Encoding utf8` / `Out-File -Encoding UTF8` 写出的文件**带 UTF-8 BOM**。用它写 `git commit -F <文件>` 的信息文件，会让 commit subject 首字节变成 `EF BB BF`（`git log --oneline` 看着像多了个不可见字符，按 `^(feat|fix|…)` 解析的工具会失配）。**信息文件必须无 BOM 写入**：
> `[System.IO.File]::WriteAllText($p, $txt, (New-Object System.Text.UTF8Encoding($false)))`。同理，提交前用 `[System.IO.File]::ReadAllBytes()` 抽查前 3 字节确认没有 `EF BB BF`。
>
> 提交信息编码：本机 `git commit -m "中文"` 会被 PowerShell 的 argv 编码破坏，**一律用 `-F <无 BOM 文件>`**。

---

## 二、已确认缺陷清单

每条都经回读代码验证。`轮次` 列指出在第五节哪一轮处理。

> ⚠ **行号是历史坐标**：本节（以及第三 / 四节）里的 `Main.gd:NNN` 都是**拆分前**的位置 ——
> 第三轮把 `Main.gd` 从 854 行拆到 191 行（见 9.5），那些代码现在住在
> `WorldGenPipeline.gd` / `TimeFlowController.gd` / `EncounterSystem.gd` / `BattleLauncher.gd` /
> `InputRouter.gd` / `OverworldView.gd` 等文件里。要改的时候按**符号名**搜，别按行号跳。

### 2.1 缺陷（Bug / 无效防护）

| ID | 缺陷 | 证据 | 影响 | 轮次 |
|---|---|---|---|---|
| B1 | `play_2d` / `play_3d` 的 fallback 路径 **100% 丢音**：`_entry()` 被调用两次，第二次被同毫秒 gap 检查拦下 | `Sfx.gd:129` → `Sfx.gd:133` → `Sfx.gd:117` → `Sfx.gd:179` | 该分支静默无声，且计数虚增（污染 F3 面板与自检数据） | 一 |
| B2 | `AudioConfig.enabled = false` 时 `is_ready()` **永久为 false**（`_bank` 保持空） | `Sfx.gd:35-36` vs `Sfx.gd:46-48`；消费方 `tools/sfx_map_check.gd:33-37` | 文档（`AudioConfig.gd:13`、README:25）推荐的「关音频省启动」会**必然弄坏自检工具**（超时 exit 1） | 一 |
| B3 | 小地图**吞掉右上角 332×348 区域的左键** → 点地不行军 | `MinimapView.gd:22` `MOUSE_FILTER_STOP` + `HUD.gd:96-106` 的 `PanelContainer`；点击寻路走 `Main.gd:572-583` 的 `_unhandled_input` | 真实可玩性 bug。对照：`HUD.gd:112` 对 tooltip 已正确设 IGNORE | 一 |
| B4 | `MAX_EXPAND = 90000` **形同虚设**（细栅格仅 66049 格） | `Pathfinder.gd:20` vs `Main.gd:100` | 防护永不触发；目标不可达时 A* 会展开整个可达区域后才失败 | 一 |
| B5 | 强盗追击**旁路了重寻路节流**：条件为 `repath_timer <= 0` **或** 目标移动 > 22 m | `AIParty.gd:70-75`；玩家 46 m/s（`MapConfig.gd:61`）→ 约每 0.5 s 成立一次 | 实际 ~2 次 A*/秒/部队；7 支强盗同时追击即寻路风暴 | 一 |
| B6 | 植被候选格被**重复筛 5 遍**（水上 / 道路 / 坡度 / 定居点排除与种类无关） | `VegetationScatter.gd:46-50` + `_scatter:66-92` | 1024 图 10.7 万次候选评估（应 2.1 万）；4096 图 171 万次 → 第一道墙 | 六 |
| B7 | 每帧对 **33 个 Label3D** 写 `pixel_size`，而缩放因子只在滚轮变化 | `Main.gd:491-502`；`f` 仅由 `camera_rig.zoom_height` 决定 | 稳态下全是白工；同值写入也会标脏标签网格 | 一 |

> 第一轮已修：**B1 / B2 / B3 / B4 / B5 / B7**（改动要点与实测见第七节）。**B6**（植被候选重复筛选）属第六节的规模优化，本轮未动。

### 2.2 工程设施缺口

| ID | 缺口 | 证据 | 轮次 |
|---|---|---|---|
| G1 | **无经济系统**：战利品算出后只弹 toast，没有「钱袋」接住；`garrison` 只显示不变 | `Main.gd:769`、`Settlement.gd:16` | 四 |
| G2 | **无存档**：全仓库无写文件的 `FileAccess` / `ConfigFile` | 唯一写盘者是 `tools/sfx_tool.gd --wav` | 四 |
| G3 | ~~**无 `InputMap`**：键位硬编码；零 `grab_focus()` / `focus_neighbor` → 遭遇框键盘 / 手柄无法作答~~ **已解决（第三轮）**：24 个动作 + 4 个对话框动作进 `project.godot` 的 `[input]` 段，`InputRouter` 统一分发，遭遇框可键盘 / 手柄作答（见第九节） | `project.godot`、`InputRouter.gd`、`EncounterDialog.gd` | 三 ✅ |
| G4 | **无音频总线**：仅 `Sfx.gd:56` 一处 `bus = "Master"`，零 `AudioServer` 调用 | 无 `default_bus_layout.tres` | 五 |
| G5 | ~~**无回归测试**：三个 tools 只打印不比对；README 的「单一种子可复现」承诺零验证~~ **已解决（第二轮）**：`tools/gen_fingerprint.gd` 逐项指纹 + `tools/gen_fingerprint.json` 存档比对 + `tools/run_checks.ps1` 一键门禁（含反向验证，见第八节） | `MapConfig.gd:83-88` 依赖 `hash(str)` | 二 ✅ |
| G6 | 无主菜单 / 设置 / i18n / CI / `export_presets.cfg` / 版本号 | `project.godot:19` 主场景直指 Main | 三 / 六 |

### 2.3 次要问题（记录备查）

- `DayNightCycle.gd:96` 三元表达式两分支相同（注释声称 `night_glow` 与 `night_amount` 不同），且 `DayNightCycle.gd:182-183` 每帧把两者赋成同一个值 ——「两套夜间曲线」的设计没落地，注释误导。第一轮顺手修正注释与死分支。
- `AIParty.gd:30-31` `rng.seed = p_seed` 紧接被 `rng.state = ...` 覆盖，seed 那行是死代码。
- `sfx_battle_check.gd:22` 的 `KEY_IDS` 里 `"land"` 重复两遍；另有 5 个音色（`proj_impact` / `parry_reflect` / `battle_start` / `result_lose` / `ui_back`）从未被任何自动检查断言。
- `PlayerParty.set_destination` 在无路径时静默 `return`（`PlayerParty.gd:72-73`），玩家点不可达位置**没有任何反馈**。
- 死代码清单（第一轮清理）：`HUD._hover_label`、`Main._label_base`、`VegetationScatter._flags` / `_flag_res`、`CameraRig.pitch_manual` / `prev_diff`、`MapData.party_positions`、`PartyBase.remaining_distance()`。
- `terrain.gdshader` 的 `lod_fade` 只用作 `mix` 权重，远场仍全量计算 `vnoise`（约 11 次/片元）。
- `proj_impact` 是 28 个音色里**唯一没有任何 `Sfx.play*` 调用点**的（其余 27 个都能在代码里找到调用处）——要么补上「抛射物命中」音，要么删掉这个音色（可省约 1/28 合成耗时）。
- 自检覆盖缺口分两类。① **四个场景音色**：`battle_start` / `parry_reflect` / `result_lose` / `ui_back` 有真实调用点，但剧本触发不到（需要开战 / 弹反抛射物 / 战败 / 界面返回四个场景）—— 第二轮仍只以「提示」形式打印、不做断言，**这四个仍未覆盖**。② 第二轮实际补上的是另外两类更隐蔽的缺口：`hit_crit` / `parry`（剧本自身有 bug，从来就没测到过，见第八节）与 `warn_danger` / `step_heavy`（覆盖与否取决于 Boss 的随机招式表，已改为直接压接线点，不再随 RNG 流漂移）。
- 迷雾叠加语义**已确认不是 bug**：`FogOfWar` 的 A 通道 = 1 − 已探索度，`MinimapView.gd:37` 用 `Color(0.02, 0.02, 0.06, 1.0)` 去调制它，效果就是「按迷雾浓度给底图压暗」；R 通道（已探索度）目前是留给 Shader 的冗余信息。
- `Main.gd:614` 的注释声称「战略视图里定居点标签再放大一档」，但 `_on_strategic_changed()` 只打了一条日志 —— 注释与实现不符（而且改动前每帧的 `_update_label_scale()` 会立刻覆盖任何手工放大，等于这条设计本来就落不了地）。属待实现功能。
- HUD 其余装饰面板（`_panel()` 返回的 `PanelContainer` 默认 `MOUSE_FILTER_STOP`）同样会吞掉其覆盖区域的左键：第一轮只修了小地图外框。**已在第三轮随 `HUD.gd` 拆分解决** —— 装饰面板一律走 `UiTheme.panel_style(..., decorative = true)`（顺带把 `mouse_filter` 设成 IGNORE），现在只有加载遮罩与遭遇框保留 STOP（它们本来就该挡点击）。
- `DayNightCycle._apply()` 每帧仍会写 `sky_mat` / `env` / `sun` 的十余个属性 —— 这些确实随时间连续变化，属于正常开销；若将来昼夜成为热点，可再按「天色量化 + 插值」优化。

---

## 三、玩法扩展路线图

判断标准：**能不能形成「打 → 赚 → 变强 → 打更强」的循环**，而不是「能不能加更多特效」。

### 阶段 1：闭合核心循环（优先级最高）

1. **`CampaignState` 战役状态层**（新文件，Resource，可序列化）：钱 / 粮 / 士气 / 声望 / 天数 / 势力关系。
   落点：`EncounterSystem.on_battle_finished` 里那笔 `spoils` 真正入账（拆分前在 `Main.gd:769-773`）。**这是所有玩法扩展的地基。**
2. **城镇 / 村庄交互面板**：进城 → 招募（扣钱 + 消耗村庄人口）/ 补给 / 交易 / 打听情报（揭示附近部队）。
   可复用：`Settlement.gd` 已有 `garrison` / `parent_town` / `neighbors`；`HUD.gd` 的 Panel 构建代码与 `NameForge.gd` 可直接用。
3. **遭遇选项 2 → 5~6 个**：攻击 / 撤退 / 要求通行费 / 劝降（按兵力差与士气判定）/ 贿赂 / 追击。
   落点：`EncounterSystem.resolve`（选项处理）+ `ui/EncounterDialog.gd`（按钮表），做成数据驱动。**单点改动即可显著提升策略密度。**
4. **战斗结果真正影响战略层**：现在只有兵力增减（`EncounterSystem.on_battle_finished`）。加声望（打强盗 +、打商队 −）、领主关系、势力通缉度。
5. **存档 / 读档**：`user://save_0.cfg` 存 `map_seed` + `CampaignState` + 玩家位置 / 兵力 + AI 部队状态 + `cooldowns`。
   本工程「一切由种子生成」，**存种子 + 增量状态**即可，成本很低。**没有它，上面 4 条的进度都留不住。**

### 阶段 2：让战略层「活」起来

6. **势力战争 `CampaignDirector`**：领主互相交战、围城、占领定居点、版图随时间变化。
   现状：`AIParty.gd:92-143` 只是巡逻 / 往返 / 游荡，AI 之间零互动（README 第 3 条已承认）。
   建议把 `AIParty` 的简单分支升级为 **Utility 评分**（距离 / 兵力差 / 目标价值），再接全局外交-战争 tick。
7. **战斗层的「第二阶段」：小兵单位**。现在场上只有 1v1，兵力只折算 Boss 血量。
   架构已就绪：`Fighter.gd` 是通用基类（`PlayerFighter` / `BossFighter` 只覆写状态机）、`BattleScene.gd:136-153` 用 `payload` 传参、`resolve_hit()` 通用。新增 `MinionFighter`（接近 → 挥砍 → 后退）承接 3~6 个小兵，**不必动现有骨架**。
   设计建议：小兵不清空血条，而是给 Boss 提供破防抗性，逼玩家先清场 —— 既保留 Boss 决斗手感，又让兵力数字有战场意义。
8. **玩家成长：武器 = 招式表**。`BattleConfig.gd:99` 的 `player_attacks` 已是数据驱动，「换武器」天然等于「换整套 `BattleMove`」（长枪 = 突刺远 / 双刀 = 快而弱 / 巨剑 = 慢而重）。再加等级、护甲、技能（弹反窗口 +、闪避距离 +、剑气穿透 +）。**投入产出比最高的内容扩展方式。**
9. **攻城战 / 据点战**：复用 `BattleScene.gd:89-124` 的 `_build_arena`（已是参数化平台列表），换 `payload.terrain` 与布局即可。
10. **任务 / 委托系统**：村庄送信、剿灭指定强盗团、护送商队 —— 用现有 `NameForge` + `AIParty` 就能生成。

### 阶段 3：内容与表现

11. **BGM / 环境音**：前置条件 = 音频总线（G4）+ `_wav(loop_mode = ...)`（现在 `SfxSynth` 从不设循环点，做不了无缝 BGM）。落点：`SfxMusic` / `SfxAmbience` + `Sfx.duck()`。
12. **天气与季节**：雨雪雾影响移动速度与士气。`DayNightCycle.gd` 已有完整氛围插值框架，加一套天气权重即可。
13. **战斗扩展**：多敌人同屏（见第 7 条）、三阶段 Boss、三类头目各自独立的行为脚本（现在是同一状态机 + 不同招式表）。
14. 难度选项、成就 / 统计、战术暂停（骑砍的「命令菜单」）。

### 推荐执行顺序

**存档 + 经济 + 城镇交互 + 遭遇选项**（四件互相咬合，且几乎都是新文件、对现有代码风险最低）→ 骨架立起来后再谈 AI 战争与部队会战。

---

## 四、代码优化路线图

### A 节 · 立即修（低风险、收益确定，合计 < 1 天）→ 第一轮

| # | 项 | 位置 | 预期收益 |
|---|---|---|---|
| A1 | 修 B1 丢音（拆 `_peek` / `_commit`） | `Sfx.gd:114-183` | 消除 100% 丢音路径 |
| A2 | 修 B2 `is_ready()` 语义 | `Sfx.gd:35-36` | 关音频不再破坏工具链 |
| A3 | 修 B3 小地图吞键 | `MinimapView.gd:22` | 修真实可玩性 bug |
| A4 | 修 B4 寻路防护（连通分量预判） | `Pathfinder.gd:20`、`NavGrid.gd` | 不可达目标 O(1) 失败，且不截断合法长路径 |
| A5 | 修 B5 重寻路节流 + 失败退避 | `AIParty.gd:70-75`、`112-113` | 消除寻路风暴 |
| A6 | 标签缩放量化早退 | `Main.gd:491-502` | 33 次/帧无效写入 → 0 |
| A7 | 昼夜量化推送（灯 + 材质） | `DayNightCycle.gd:174-183` | 消除每帧 18 盏灯的 RS 写入 |
| A8 | 小地图重绘节流 10 Hz | `MinimapView.gd:24-26` | 绘制量 −85%~90% |
| A9 | 迷雾常驻 Image + 脏矩形 + 早退 | `FogOfWar.gd:59-69` | 静止时纹理上传 5 次/秒 → 0 |
| A10 | 高度图烘焙直传 `hm.data` | `MapTextureBaker.gd:131-141` | 省 26 万次双线性采样 |
| A11 | 死代码清理 | 见 2.3 清单 | 减少误导 |

### B 节 · 结构重构（1~2 周）→ 第三轮

- **B-1 拆 `Main.gd`（818 行 / 21 段职责）** ✅ **已完成（第三轮，见 9.5）** → `WorldGenPipeline`（只碰 RefCounted，天然可无头单测）/ `MaterialFactory` / `PartySpawner` / `TimeFlowController` / `EncounterSystem`（只发信号）/ `BattleLauncher` + `EncounterRules`（数值进 Resource）/ `OverworldView` / `HoverInspector` / `InputRouter` / `GameState`。目标 Main ≈ 200 行 —— **实际 191 行**。
  顺带消除：玩家初始兵力 **37 硬编码两处**（`Main.gd:278,280`）、部队类型中文名表**重复三份**（531 / 640 / 642）、`set_meta("player_ref")` 弱类型侧信道（`Main.gd:281` → `AIParty.gd:58`）。
- **B-2 拆 `HUD.gd`（323 行 / 9 件事）** → LoadingOverlay / TopBar / EncounterDialog / TransientMessages / DebugStatsPanel + `Theme.tres`。**性价比最高的重构**，也是引入 `.tscn` 的最佳落点（3D 与特效继续代码构建）。
- **B-3 类型化**：`TerrainManager._chunks` 的 Dictionary → 内部类 `Chunk`；`MapData` 拆 `WorldGenResult` / `WorldQueries` / `RuntimeRefs`（typed，替掉 `set_meta`）；统一 RNG 派生入口（现在 `MapConfig.make_rng`、`AIParty` 的 seed+state、`Main.randi_range_seed` 三套并存）。
- **B-4 引入 `InputMap` + 输入路由**：一举解决手柄支持、键位重映射、遭遇框键盘无法作答（G3）。**已完成（第三轮，见第九节）**：28 个动作（24 个游戏动作 + 4 个对话框动作）写进 `[input]` 段，`InputRouter` 只把输入翻译成语义信号（`order_move` / `cycle_speed_requested` / …），界面上的键位文字一律从 `InputMap` 现读。

### C 节 · 性能与规模（按需，取决于要做多大）→ 第六轮

- **植被**：单遍筛选（**注意会改变现有种子的布局语义**，需显式决定是否接受）→ 估算生成 −60%~70%；实例发射改 `RenderingServer.multimesh_set_buffer` 批量写 → 估算 5~15×；桶尺寸 128 m → 256 m。
- **地形**：`_apply_lod` 把「缓存命中」提到预算判断之前（缓存切换本该免费）；按距离排序建块；法线用本地高度差分替代每顶点 4 次 `height_at`（**每顶点 5 次采样 → 1 次**）；LOD2/3 关阴影。现状每 0.25 s 允许建 2 块、单块 3~6 ms → 尖峰 5~10 ms。
- **A\***：把 `blocked` / `speed` / `res` 提到局部变量并内联邻居判定（省每邻居 1~3 次脚本方法调用，**本体 2~4×**）；全局寻路请求队列 + 每帧预算；长距离用「道路骨架拓扑 + 首尾各一段栅格 A*」（HPA* 思路）。
- **4096 地图前置条件**：所有写死分辨率必须与 `map_size` 绑定 —— `nav_fine = 257`（`WorldGenPipeline.gd`，4096 图下变 15.9 m/格，比道路还宽）、`SPLAT_RES = 512`、`MINIMAP_RES = 256`、`MapData.TERR_RES = 128`、`FogOfWar.RES = 128`，以及 `MapTextureBaker.gd:55` 硬编码的 460 m 领地半径。**不绑定的后果是功能静默失真（道路消失、迷雾糊化），比崩溃更难查。**
- **100 部队前置条件**：标签量化早退（第一轮已完成）+ 寻路队列 + 部队渲染 MultiMesh 化（现在每支部队一个新建 ArrayMesh）。

### D 节 · 工程质量（持续，让上面所有改动「敢做」）→ 第二 / 五 / 六轮

1. **`tools/gen_determinism_check.gd`（最高价值）**：固定 `map_seed` 生成两次 / 对比基线 JSON —— 高度场 CRC、定居点名与位、道路点数、桥梁数、植被数。README 的核心承诺，目前零守护。
2. **战斗数值回归**：HP / 破防 / 战利品公式抽成纯函数后断言（顺带把数值从 `Main` 搬进 Resource）。
3. **性能基准**：`--fixed-fps 60` 跑 600 帧，采样 `Performance` 的 FPS / draw call / 三角形 + `_gen_ms`，断言上界。README 的「185~206 draw call / 144 FPS」目前是手工记录、无法回归。
4. **无 ERROR 断言 + CI**：headless 运行包一层「stderr 不含 ERROR」；CI 第一条命令固定 `--headless --editor --quit` 建缓存（消除 README 描述的「克隆后第一次必报错」）。
5. **音频**：先拆开合成用的共享 `_rng`（现在 `Sfx.gd:45,67,192` 一个 RNG 同时喂合成与音高抖动 → **插入新音色会改变其后所有音色的噪声**，缓存键也不稳定）→ 再做 `user://` PCM 缓存（679 KB，热启动 < 50 ms）或后台线程与地形生成重叠；顺手消灭 `_biquad` 扫频路径**每样本一次 `_coef()`（cos + sin + 新建 5 元素 Array）**这个最大热点。
6. **i18n**：先把散落的中文文案抽成 `Strings.gd` 常量表（成本极低），再上 Translation CSV。
7. 补 `export_presets.cfg` + `config/version`、LICENSE、分级日志（现在全是 `print()`）。

---

## 五、轮次计划与执行状态

| 轮次 | 内容 | 状态 |
|---|---|---|
| **第一轮** | A 节全部修复项 + 死代码清理 + 本路线图落档 | **已完成**（2026-10-12；改动与实测见第七节） |
| **第二轮** | 安全网：`tools/gen_fingerprint.gd`（原计划名 `gen_determinism_check.gd`）+ `tools/perf_probe.gd` 性能基准 + 一键门禁 `tools/run_checks.ps1` | **已完成**（2026-10-12；改动与实测见第八节） |
| 第三轮 | 拆 `Main.gd` + 拆 `HUD.gd` + 引入 `InputMap` | ✅ **已完成**：`HUD.gd` 拆分（`eddd8c2`）、`InputMap` / `InputRouter`（`8063a9e`）、`Main.gd` 拆分四批（`a54d9d5` / `f9a09a8` / `951d3b2` / 本批，**854 → 191 行**，见 9.5）；另修掉门禁挂死隐患（工具脚本调用已改名方法 + 每步 180 s 硬超时） |
| 第四轮 | 玩法闭环：`CampaignState` 经济 + 城镇交互 + 遭遇多选项 + 存档 | 🔄 **进行中**：4a 经济（钱袋 / 军费 / 士气 / 战利品 / HUD）已完成并通过门禁，见 §10.1–10.5；4b-1 城镇交互**逻辑层**（服务表 / 繁荣度定价 / 招募 / 贸易 / 驻军）已完成并通过门禁，见 §10.6；4b-2 进城**菜单界面 + 交互键**（G / 手柄 A、灰条目带原因、到地提示）已完成并通过门禁，见 §10.7；4c 遭遇**多选项**（选项表数据驱动 + 四条路各自的效果与代价 + 结算台账）已完成并通过门禁，见 §10.8；4d 存档待办 |
| 第五轮 | 音频总线 + PCM 缓存 + 合成热点 + BGM 接口 | ✅ **已完成**（2026-10-14）：5a 音频总线（`default_bus_layout.tres` + `AudioBus` + 扇子音 duck + `audio_check`）已完成并通过门禁，见 §11.1；5b 合成热点（先装体检器再改，合成 −28% 且音色逐字节不变 + 音色指纹入门禁）已完成，见 §11.2–11.3；5c PCM 缓存（`SfxCache`：679 KB，`Sfx.setup()` 1.35 秒 → 9 毫秒，音色逐字节不变 + 77 项自检进 9d 步，15 → 16 步）已完成并推送（`597bc63`），见 §11.4 |
| 第六轮 | 规模扩展（植被 / 地形 / 寻路）+ i18n + 导出预设与 CI | 🔄 **进行中**：6a 规模热点探针（门禁 7b 步，16 → 17 步）✅ §12.1；6c 地形建块 3.06×、顶点位置与索引逐位不变 ✅ §12.2；6d 前半 A* 内联 1.20~1.45×、搜索结果逐对不变 ✅ §12.3，**后半请求队列待做**；6b 植被筛选段 2.06× 且**布局逐位不变** ✅ §12.4（会改布局的「单遍筛选」仍待显式决定，建议并入 ④ 4096 地图一起做）；6b 后半 植被分桶 128 → 256 m（节点 212 → 67，perf `nodes` −29%）+ MultiMesh 批量写实测**否决** ✅ §12.7；6d 后半 全局寻路请求队列 `PathQueue`（每帧预算 2000 µs、单请求峰值 53.2 ms、结果与同步 `find_path` 逐点相同）+ 门禁 5b 新项 ✅ §12.8；⑦ LICENSE（MIT，素材来源已核实：只有本地 CC0 渲染的 BGM + icon.svg）+ `config/version=0.6.0` + `export_presets.cfg`（预设合法、被引擎认得）+ 分级日志 `Log.gd`（19 项断言、门禁 5c）✅ §12.9；⑧ CI 门 `.github/workflows/ci.yml`（建缓存 + 跑门禁）+ `GODOT_BIN` 接线 ✅ §12.10；⑥ i18n 起步 `Strings.gd`（9 条常量，迁 TopBar 后 `hud_check` 68/68 PASS）+ `tools/i18n_check.gd` 棘轮（基线 `ui_total=26`，迁移前 34）✅ §12.12；④/⑤ 4096 m 与 100 部队硬编码清单（15 项、4 处拦路虎）✅ §12.5；⑥ i18n 收尾：`scripts/ui` 六个界面全部迁进 `Strings.gd`，硬编码中文 **26 → 0**，棘轮基线收紧到 `ui_total=0` ✅ §14.2。**本批另接了一步门禁**：§13 的录音素材自检进门禁第 9e 步（24 → 25 项）✅ §14.1。**剩余**：④/⑤ 4096 m 地图与 100 部队（§12.5 的 **16 项**清单已就绪，**#3/#4/#16 已于 §16.1 做掉**，剩 #1 寻路格距 / #2 植被单遍筛选 / #5 `CHUNK_SIZE` 三处拦路虎）、6b「单遍筛选」（约定与 ④ 一起做一次性重基线化）、⑥ 其它目录的文案（`scripts/core` 等 631 条，**本轮明确不做**，见 §14.2 的口径说明） |

> 第四轮之后按「内容产能」推进：小兵单位 → 武器招式表 → 势力战争。
>
> 第五轮收尾时回看 §四.5 的预估：它写的是「`user://` PCM 缓存（679 KB，热启动 < 50 ms）」——
> 实际落地 679 KB、热启动 9 ms，预估准确；它同时点出的「共享 `_rng`」问题也一并解决了（抖动改用 `_jit`）。

---

## 六、验证方式（可复现命令）

```powershell
$GODOT = "G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe"
$PROJ  = "F:\aigc_code\ai_godot_projects"

# 0) 【推荐】一键跑完全部门禁（17 步 / 20~21 项断言，约 42~44 秒）—— 本工程唯一需要的命令
#    （项数在 20~21 之间浮动，差的那一项是 perf_probe / scale_probe 偶尔给出的 WARN 提示行，不判失败）
#    （5c 之后门禁反而快了：PCM 缓存让 sfx_map_check / bgm_check / main_scene_900 都走热启动）
powershell -File tools\run_checks.ps1
#    ⚠ 必须用 powershell 而不是 pwsh：本机只有 Windows PowerShell 5.1，没有 pwsh 7

# 1) 主场景完整跑一遍（看是否有 ERROR / 生成耗时 / 生成内容统计）
& $GODOT --headless --path $PROJ --fixed-fps 60 --quit-after 900

# 2) Boss 战音效联调（exit 0 = 关键音效全部触发）
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/sfx_battle_check.gd
# 3) 大地图音效联调
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/sfx_map_check.gd
# 4) 音色体检（含总合成耗时）
& $GODOT --headless --path $PROJ --script res://tools/sfx_tool.gd
# 4-1) 音色指纹（28 个音色 PCM 逐字节比对 tools/sfx_pcm.json）
#      —— 「这次改动没动音色」的证明手段：合成优化后指纹必须一模一样
& $GODOT --headless --path $PROJ --script res://tools/sfx_tool.gd -- --check
#     有意改过音色后必须更新基线，否则门禁会红：
# & $GODOT --headless --path $PROJ --script res://tools/sfx_tool.gd -- --write-baseline
# 4-2) 合成热点体检（外层算子耗时表 + 逐采样算子次数表）
& $GODOT --headless --path $PROJ --script res://tools/sfx_tool.gd -- --profile
# 4-3) PCM 缓存自检（冷启动落盘 → 热启动逐字节一致 → 六种坏缓存自愈 → Sfx.setup 命中 → 关缓存不碰盘）
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/audio_cache_check.gd
# 4-4) 规模热点探针（第六轮改前基线：植被筛选 / 地形建块 / A* 寻路）
#      —— 结构量（实例数 / 区块数 / 变换指纹 / 展开节点数）与 tools/scale_baseline.json 精确比对，
#      耗时超 1.6x 记 WARN、超 2.5x 判失败。改完热点后回它对账，才知道「快了」是真快了
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/scale_probe.gd
#     有意改变了规模 / 优化了热点后更新基线：
# & $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/scale_probe.gd -- --write-baseline

# 4b) 输入层回归（[input] 动作表是否真进了 InputMap / InputRouter 分发与让路 /
#     遭遇框能否用键盘与手柄作答）—— 「按了没反应」这类问题以前只能点开游戏按一按
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/input_check.gd

# 4c) 经济定式（军费 / 士气 / 编制 / 招募 / 撤退代价的公式形状 + 42 天收支时间轴）
#     —— 这条回路（工资→欠薪→士气→逃兵→兵力→工资）在 900 帧里连一天都跑不完
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/economy_check.gd

# 4d) 城镇交互定式（价格 / 招募 / 贸易套利 / 驻军与军费联动 / 五类边界 / 菜单行数）
#     —— 进城菜单的分支同样在 900 帧里一个都走不到，而它是经济闭环的入口
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/settlement_check.gd
# 4e) 遭遇选项表定式（四条路的定价 / 可用条件 / 各自效果、不合法动作静默拒绝、
#     撤退或买路之后时间锁有没有真的解开、战斗结算台账）—— 主场景里玩家不动，
#     一次遭遇都不会触发，这张表在 900 帧里同样是死的
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/encounter_check.gd

# 4f) 存档定式（存档格式 / 三道身份门（版本 / magic / 种子+实体 id）/ 坏数据钳制 /
#     读档后的引用修复 / 文件读写与往返稳定性）—— 900 帧里没人去按 F5 / F9
#     （存读档要玩家触发），而且地图重建要 6~7 秒，整条存档链只能靠定式验
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/save_check.gd

# 4g) 音频总线定式（布局是否真被引擎加载 / AudioBus 写回与降级 / Sfx 与 Bgm 的路由与
#     「总音量只算一次」/ duck 的触发与到点恢复 / 静音走增益淡出）—— 900 帧里玩家
#     不按键、不切曲，总线挂错、总音量算两遍这类问题它一条都抓不到
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/audio_check.gd

# 4h) BGM 联调（两首 Ogg 真的加载并循环 / 大地图曲起播 / 遭遇→Boss 战→结算的切曲 /
#     M 键静音与恢复 / stop()）—— 它跑一遍真主场景，约 7 秒
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/bgm_check.gd

# 5) 生成物指纹（确定性自检；与 tools/gen_fingerprint.json 存档比对）
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/gen_fingerprint.gd
#    有意改动生成后，用下面这条更新存档（否则门禁会红）
# & $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/gen_fingerprint.gd -- --write-baseline

# 6) 性能基准（与 tools/perf_baseline.json 比对；超出容差 exit 1，漂移只 WARN）
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/perf_probe.gd
# & $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/perf_probe.gd -- --write-baseline

# 7) 代码规模（不要用 Measure-Object -Line，会漏算空行）
Get-ChildItem -Recurse -File -Include *.gd,*.gdshader |
  ForEach-Object { [pscustomobject]@{ L = (Get-Content $_.FullName).Count; P = $_.FullName } } |
  Sort-Object L -Descending
```

**判定标准**：① 主场景无 `ERROR` / `SCRIPT ERROR`；② 两个联调脚本 `exit 0` 且输出 `PASS`；③ 生成物指纹与 `tools/gen_fingerprint.json` 存档一致（**只比两次跑得一样是不够的**，两次跑出同一个新指纹同样说明生成被改了），且生成内容统计（定居点 18 / 桥梁 7 / 植被 5163）与基线一致。

> 例外：若 `AudioConfig.enabled = false`（关音频省启动），两个联调脚本会输出 `SKIP` 并 `exit 0` —— 这**不算通过**，只是「本次不适用」；要在关音频的前提下判音效，请先把它改回 `true`。

---

## 七、第一轮变更记录

改动文件与要点（详细 diff 见对应提交）：

| 文件 | 改动 |
|---|---|
| `docs/ROADMAP.md` | 新增：本路线图与进度台账 |
| `scripts/audio/Sfx.gd` | 拆出 `_peek()`（查表 + 节流判定，**不写状态**）与 `_commit()`（记时刻 + 计数），新增 `_play_plain()`；`play` / `play_2d` / `play_3d` 改为 `_peek → _commit → 播放`，退化路径复用已取到的条目（不再被二次节流吞掉）；`is_ready()` 改为「已 setup 且（关音频 或 音色库非空）」 |
| `scripts/ui/MinimapView.gd` | `mouse_filter` STOP → IGNORE（不再吞右上角左键）；`_process` 加 0.1 s（10 Hz）重绘节流；删死字段 `zoom` |
| `scripts/ui/HUD.gd` | 小地图外框 `PanelContainer` 也设为 IGNORE（否则子控件放行了、父容器照样吞点击）；删死控件 `_hover_label`（声明 / 构建 / 置隐三处） |
| `scripts/nav/NavGrid.gd` | 新增 `component[]` + `rebuild_components()`（8 向 + 对角禁切角，与 A* 规则完全一致）+ `same_component()` |
| `scripts/nav/Pathfinder.gd` | `find_path` 先做连通分量 O(1) 预判，不可达立即返回空；`MAX_EXPAND` 常量改为按栅格规模推导的实例上限 `max_expand`（只作死循环兜底，不再截断合法长路径，也不再是个 90000 > 66049 的无效防护） |
| `scripts/world/RoadNetwork.gd` | `build()` 末尾重建两张栅格的连通分量（此时道路与桥梁已写回，栅格才最终定型） |
| `scripts/parties/AIParty.gd` | 追击重寻路只按 1.4 s 节流触发（删掉 `last_goal.distance_to(pd) > 22.0` 旁路 —— 玩家 46 m/s，22 米约 0.5 秒就走完，它才是「≈2 次 A*/秒/部队」的元凶）；三条寻路路径统一走 `_repath_to()`，失败按 3→6→12→24→60 s 指数退避并记忆失败的目标格；随机数抽取位置不变（保持确定性）；删死代码 `rng.seed = p_seed` |
| `scripts/core/Main.gd` | `_update_label_scale` 量化到 1/64 + 早退（原来每帧对 33 个 Label3D 写 `pixel_size`，会标脏并重建字形网格）；删死字段 `_label_base` |
| `scripts/env/DayNightCycle.gd` | `night_amount` 量化到 1/512，仅跨档时推送 18 盏 OmniLight3D 与全部材质；`register_*` 里置 `_night_pushed = -1` 保证新注册对象仍会被初始化；修正 `register_shader` 的无意义三元表达式与误导注释 |
| `scripts/env/FogOfWar.gd` | 常驻 `Image` + 常驻字节缓冲（不再每次 `Image.create_from_data` + 16k 次脚本循环）；`reveal` 就地写字节并置脏标记；无脏标记时**不上传纹理**；删 `_to_bytes()` |
| `scripts/world/MapTextureBaker.gd` | `bake_height` 直接复用 `hm.data`（省 26 万次双线性采样）；删已无用的 `HEIGHT_RES` 常量 + 注释订正 |
| `scripts/camera/CameraRig.gd` | 删死字段 `pitch_manual`、`prev_diff` |
| `scripts/core/MapData.gd` | 删死字段 `party_positions` |
| `scripts/world/VegetationScatter.gd` | 删死字段 `_flags`、`_flag_res`（注意 `SettlementBuilder._water_flags` 是活的，未动） |
| `scripts/parties/PartyBase.gd` | 删无调用方的 `remaining_distance()` |
| `tools/sfx_battle_check.gd` | `KEY_IDS` 去掉重复的 `"land"`；新增 `OTHER_SCENE_IDS` 未覆盖提示；`AudioConfig.enabled = false` 时明确报 SKIP（退出码 0），不再假 PASS / 假失败 |
| `tools/sfx_map_check.gd` | 同上：关音频时明确报 SKIP |

**实测结果**（2026-10-12，`--fixed-fps 60`，命令见第六节）

| 项 | 结果 |
|---|---|
| 主场景 headless `--quit-after 900` | **exit 0**，无 `ERROR` / `SCRIPT ERROR`；`[Warband] 地图生成完成：8133 ms   定居点 18   桥梁 7   植被实例 5163` |
| `tools/sfx_battle_check.gd` | **exit 0 / PASS**；28 个音色 / 合成 1515 ms / 音效池 24；累计播放 58 次、触发过 19 种音色 |
| `tools/sfx_map_check.gd` | **exit 0 / PASS**；就绪等待 42 帧；生成 8066 ms；行军号角 / 马蹄 / 遭遇提示音全部触发过 |
| 与基线一致性 | 定居点 18 / 桥梁 7 / 植被实例 5163 —— 与改动前**完全相同**（未破坏种子确定性，符合 AGENTS 对地图生成的要求） |
| 已知无害噪声 | 两个自检脚本退出时仍有 `WARNING: N ObjectDB instances were leaked at exit`（改动前即存在；连跑三次得到 10 / 12 / 16，每次不同，与本次改动无关）。若要根治，需在后续轮次排查静态 `Sfx` 的持有链 |

- [x] 主场景 headless：exit 0，无 ERROR
- [x] `sfx_battle_check`：PASS
- [x] `sfx_map_check`：PASS
- [x] 生成内容统计与基线一致（18 / 7 / 5163）

---

## 八、第二轮变更记录（安全网）

**目标**：README 承诺「单一随机种子可复现」，但此前**没有任何验证手段** —— 任何人把 `randf()` 的调用顺序挪一下，整张地图会静默改变且无法察觉。本轮把这句话变成可执行的门禁。

改动文件与要点：

| 文件 | 改动 |
|---|---|
| `tools/gen_fingerprint.gd` | 新增。加载 `Main.tscn` → 关音频、注入固定 `MapConfig` → 冻结 `_process`/`_physics_process` → 对 11 类生成物（settlements / bridges / roads / vegetation / heightmap / territory / nav_coarse / nav_fine / nav_road / parties）逐项算 SHA-256 并汇总成一个 `FINGERPRINT=`。退出码 0 = 与存档一致，1 = 不一致，2 = 未就绪。`-- --write-baseline` 更新存档、`-- --print-only` 只打印 |
| `tools/gen_fingerprint.json` | 新增。基线存档：种子 20250929，`FINGERPRINT=19d42d35…f826`，计数 18 / 7 / 5163 |
| `tools/perf_probe.gd` | 新增。300 帧采样 idle 与行军两种状态，输出 `frame_ms` / `nodes` / `objects` / `static_mb` / `draw_calls` 的 avg·p95·max。**放弃 `Performance.TIME_PROCESS`**（见下） |
| `tools/perf_baseline.json` | 新增。性能基线存档 |
| `tools/run_checks.ps1` | 新增。一键门禁：指纹 A → 指纹 B（跨进程）→ 指纹 vs 存档 → 性能 → 两个音效联调 → 主场景 900 帧 + 生成统计比对。任何一步退出码不符、超时、或输出里出现 `ERROR:` / `SCRIPT ERROR` / `Parse Error` 即判失败 |
| `scripts/battle/BossFighter.gd` | **修 bug**：选招用全局 `randf()` 改为 `battle.roll01()`。全局 RNG 每次进程启动都重新随机播种，导致 Boss 出招序列不可复现 —— 这是战斗自检偶发失败的根因 |
| `scripts/battle/BattleScene.gd` | 新增 `roll01()`：战斗内统一的随机入口（`rng` 由 `setup()` 的 `"seed"` 播种）。子节点不要再碰全局 `randf()` |
| `tools/sfx_battle_check.gd` | **修自检缺陷**（见下两条）+ 剧本改为「进攻段 / 防守段」两段式 |
| `scripts/core/Main.gd` | 新增公开字段 `gen_done`（程序化生成**彻底**结束后置 true）。此前工具只能靠 `_gen_ms != 0` 猜测生成结束，而它是在收尾 `await` **之前**写入的 —— 工具一 free 场景就会触发 `Resumed function '_step()' after await, but class instance is gone` |

### 本轮揪出的三个真问题

1. **`Performance.TIME_PROCESS` 在 headless 下是陈旧常数**。加 `--fixed-fps 60` 后连续读 12 次完全相同，idle 报 1150.154 ms/帧，而墙钟只有 0.841 ms/帧（是某一帧慢生成的残留值）。`Engine.get_frames_per_second()` 同样被冻结。改用 `Time.get_ticks_usec()` 的逐帧差值；`--fixed-fps 60` 会关掉实时同步（帧能跑多快跑多快），因此墙钟值就是真实 CPU 开销。
2. **战斗自检本身不可复现**（`BossFighter` 用全局 `randf()`）：同一命令连跑 4 次，1 次 FAIL、1 次 PASS 且播放次数在 54~63 之间漂。修掉后缺失集合稳定。
3. **`hit_crit` / `parry` 两种音效从来就没被真正测到过**。原剧本每 25 帧点一次攻击（0.417 s），而连段窗口只开在**后摇的前 70%**（attack1 是起手后 0.17~0.31 s）——窗口早关了、招式也已结束（`combo_index` 归零），永远连不到第 3 段，而 `crit_mult = 1.3` 只写在第 3 段上；同时 89% 的时间都在出招，弹反输入被攻击状态吃掉，且原反应规则按「预警剩 0.05 s」按下，对 cleave（0.22 s）与 axe（0.19 s）**必然**超出 0.15 s 弹反窗口。改为：进攻段按 14 帧节拍连打（落在窗口内）；防守段完全不按攻击，并按「距判定帧还有多久 ≤ 0.12 s」来按弹反。
   - 另有两个音色（`warn_danger`、`step_heavy`）的覆盖同样依赖 Boss 的随机招式表，改用已有的测试钩子 `start_move_for_test("charge")` 与直接压 `on_boss_warn()` 来保证覆盖 —— 否则「换一条 RNG 流」就会让自检莫名其妙地少覆盖两种音色。

### 验收：门禁本身也做了反向验证

故意在 `MapConfig.make_rng()` 里多抽一次随机数（验证后已撤销，`git diff` 归零）：

| 检查项 | 扰动后结果 | 说明 |
|---|---|---|
| 跨进程双跑（A = B） | **仍然 PASS** | 两次都跑出同一个**新**指纹 —— 证明只比 A=B 是个**假安全网** |
| 指纹 vs 存档 | **FAIL** `3bb8cca5…` ≠ `19d42d35…` | 真正拦住问题的是这一条 |
| 生成统计 | **FAIL** 18/3/5184 ≠ 18/7/5163 | 计数与指纹互为冗余 |
| 性能 / 两个音效联调 | PASS | 失败被正确隔离在生成侧 |

### 实测结果（2026-10-12，`powershell -File tools\run_checks.ps1`）

| 项 | 结果 |
|---|---|
| 一键门禁 | **exit 0，9 项全绿，用时 42.4 s** |
| 生成指纹 | `19d42d358f8d5495adeb1946ad91a9a034fb878e510e309561f247bfd0d7f826`（跨进程两次一致，且与存档一致）；生成 29 帧 / 约 5.4~6.1 s；定居点 18 / 桥梁 7 / 植被 5163 |
| 性能基线（idle） | `frame_ms` avg 0.847 / p95 5.995 / max 13.485；nodes 446；static 128.85 MB |
| 性能基线（行军 148/300 帧在移动） | `frame_ms` avg 1.100 / p95 6.057 / max 16.179；static 129.24 MB |
| 性能容差 | avg 1.5 倍、p95 1.8 倍；三次复测 idle avg 0.817 / 0.822 / 0.748（基线 0.847），余量充足 |
| `sfx_battle_check` | **exit 0 / PASS**；28 个音色 / 合成约 1.6 s / 音效池 24；19 种关键音色**全部**触发（含此前从未覆盖的 `hit_crit` / `parry`）；缺失集合连续 4 次完全一致 |
| `sfx_map_check` | **exit 0 / PASS** |
| `draw_calls` | 恒为 0 —— headless 下 `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME` 不统计，该指标在无窗口环境无意义，仅保留字段 |

- [x] 建立生成物指纹基线并跨进程验证可复现
- [x] 指纹与存档比对（而非只比 A=B）
- [x] 性能基线可复现、容差有实测余量
- [x] 主场景 / 两个音效联调零 `ERROR`，且三者的 ERROR 断言已排除 PowerShell 5.1 的 stderr 包装误判
- [x] 一键门禁 `tools/run_checks.ps1` 跑通，并做过反向验证（改了 RNG 顺序确实会红）

> 编码坑（已写进 `run_checks.ps1` 头部注释）：本机只有 Windows PowerShell 5.1。① `.ps1` 必须存成**带 BOM 的 UTF-8**，否则中文注释按 GBK 解码直接语法报错；② `Get-Content -Raw` 读 Godot 写出的**无 BOM** JSON 会乱码并使 `ConvertFrom-Json` 失败（表现为基线被静默读成 0/0/0）；③ 原生命令只要往 stderr 写一个字节，PS 5.1 就会包成含 `FullyQualifiedErrorId : NativeCommandError` 的 ErrorRecord —— 所以 ERROR 断言必须用大小写敏感的 `ERROR:|SCRIPT ERROR|Parse Error`，否则 Godot 退出时的 `WARNING: N ObjectDB instances were leaked` 会把整步判失败。

---

## 九、第三轮变更记录（HUD 拆分 + `InputMap` + 拆 `Main.gd`）

第三轮三件事全部完成：B-2 拆 `HUD.gd`（`eddd8c2`）、B-4 `InputMap` + 输入路由（`8063a9e`）、B-1 拆 `Main.gd`（四批：`a54d9d5` / `f9a09a8` / `951d3b2` / 本批，见 9.5）。

### 9.1 HUD 拆分：`HUD.gd` 323 行 → 115 行外观层 + 7 个组件

| 组件 | 行数 | 职责 |
|---|---|---|
| `TopBar.gd` | 54 | 天数 / 时间流速 / 当前地形 / 暂停徽标 |
| `MinimapView.gd` | （已有） | 右上角小地图 |
| `LoadingOverlay.gd` | 48 | 全屏加载遮罩，`z_index = 100` 盖住所有面板 |
| `HoverTooltip.gd` | 29 | 跟随鼠标的地形提示 |
| `ToastLabel.gd` | 39 | 底部淡出提示条（`mouse_filter = IGNORE`） |
| `HelpPanel.gd` | 41 | 左下操作说明 |
| `DebugStatsPanel.gd` | 31 | F3 性能面板 |
| `EncounterDialog.gd` | 109 | 遭遇对话框（唯一该挡点击的 UI 之一） |

`HUD.gd` 只留外观层接口：`setup / bind / set_loading / hide_loading / set_terrain_text / show_toast / show_tooltip / clear_tooltip / show_encounter / hide_encounter / is_encounter_open` + 信号 `encounter_choice(action)`；`hud_check` 用 29 条断言把这份接口钉住。

**顺手修掉两个从第一轮就存在、但直到截图才暴露的老 bug**：

1. **加载遮罩 / 遭遇框缩成 0×0 且贴在左上角**。根因是 `set_anchors_preset()` 只改锚点、**保留当前矩形**，对 0×0 的 Control 调用后 offsets 变成 `(0, 0, -1600, -900)` —— 遮罩黑底完全看不见、`MOUSE_FILTER_STOP` 也挡不住点击。正确写法是 `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`。
2. **面板画在黑遮罩之上**：给 `LoadingOverlay` 加 `z_index = 100`，并用截图 + 亮度采样确认遮罩期间看不到任何 HUD。

> 教训：这类「能编译、断言全过、界面已塌」的问题，只有真实渲染截图能发现 —— `tools/hud_shot.gd` 因此被保留为常规手段（三张图：加载中 / 正常 / 遭遇框+提示条）。

### 9.2 `InputMap`：键位从代码搬进 `project.godot`

- `[input]` 段共 **28 个动作**：24 个游戏动作（`move_*` / `zoom_*` / `cam_rotate_*` / `focus_party` / `time_flow` / `cycle_speed` / `toggle_vegetation` / `toggle_mute` / `faction_labels_1..3` / `battle_*` / `debug_toggle`）+ 4 个对话框动作（`dialog_confirm` / `dialog_cancel` / `dialog_next` / `dialog_prev`）。
- `InputRouter`（173 行）只做一件事：把输入翻译成语义信号 —— `order_move(goal)` / `cycle_speed_requested` / `toggle_vegetation_requested` / `toggle_mute_requested` / `faction_labels_requested(id)`。`Main.gd` 里原来的 `_unhandled_input`（一段长长的 `KEY_*` match）整体删除，`CameraRig._process` 的平移 / 旋转 / 缩放改读 `Input.get_vector(...)` / `get_axis(...)`，`BattleScene._read_input()` 同理。
- **遭遇框能用键盘与手柄作答了**（G3）：打开即 `grab_focus()`；`dialog_cancel` → 撤退；`dialog_confirm` → 按下当前焦点按钮；`dialog_next/prev` → 切换焦点；`UiTheme` 新增 `focus` 描边样式块，焦点在哪一眼可见。
- **界面文字不再硬编码按键**：`InputRouter.action_keys_text()`（完整绑定）与 `action_hint_text()`（键盘 + 手柄各一个，用于一行提示）都从 `InputMap` 现读，`HelpPanel` / `TopBar` 暂停徽标 / 遭遇框提示行 / 静音 toast 全部跟着 `[input]` 段走。
- 目录里已只剩 `InputRouter._key_name()` 一张 `KEY_*` 表（把键码翻译成中文名），其余 `scripts/` 下再无 `KEY_*` / `is_physical_key_pressed`，也无 `InputMap` 之外的键位来源。
- 鼠标手势（左键点地行军、中键 / 右键拖拽旋转）**故意不做成动作**：它们按坐标处理，不是「按一下」的语义；对应说明写在 `HelpPanel` 里。

### 9.3 本轮踩到的五个坑（都已修，且都写进了代码注释）

1. **测试事件的 `device` 必须是 0**。给 `InputEventKey` 设 `device = -1`（`DEVICE_ID_EMULATION`）后，`[input]` 段里 `device = -1` 的动作照样匹配，但**引擎内建 `ui_*` 动作（device = 0）一律不匹配** —— 表现为「明明按了 Esc，对话框却没反应」。实测规则：动作事件 `device = -1` 匹配任意来源事件，`device = 0` 只匹配 `device = 0` 的事件。**这是测试代码的错，不是游戏的错**（真机键盘事件 device = 0）。
2. **内建 `ui_accept` / `ui_cancel` 没有手柄事件**（`InputMap.action_get_events()` dump 出来只有 Enter / 小键盘回车 / 空格 与 Escape）——「手柄按 A 确认」根本不会触发 `ui_accept`。所以对话框没有复用内建动作，而是自己声明了 4 个带手柄绑定的动作；`input_check` 直接断言「手柄 A → 攻击、手柄 B → 撤退、十字键 →/← 切换焦点」。
3. **新建 `class_name` 脚本需要一次 `--import` 才进类缓存**。`.godot/global_script_class_cache.cfg` 在 headless 运行时**不会**被扫描更新，`InputRouter` 作为类型注解（`var router: InputRouter`）在缓存里缺席时无法解析。实测：`--import` 前缓存里没有 `InputRouter`，之后有了（`--import` 会短暂拉起编辑器完成扫描）。
4. **`edit` 工具会吃掉 `run_checks.ps1` 的 BOM**。PS 5.1 读无 BOM 的 UTF-8 会按 GBK 解码 —— 本次改完头部注释后直接报了 19 条语法错误（`Unexpected token '鍩虹嚎'`，即「基线」的 GBK 乱码）。凡改动带 BOM 的文件，之后必须用 `[System.IO.File]::WriteAllText($p, $txt, (New-Object System.Text.UTF8Encoding($true)))` 把 BOM 写回去；`.gd` / `.md` / `project.godot` 本来就无 BOM，不受影响（已逐一比对 HEAD 确认）。
5. **方向键 / 十字键同时是 `move_*`（平移视角）与对话框的选项切换键**：遭遇框打开时若不冻结相机，按 → 切选项会连带把镜头拖走。`Main._set_camera_active(false)` 在弹出遭遇框时冻结相机（Boss 战期间也走同一条路），关闭时恢复。

### 9.4 验收

| 项 | 结果 |
|---|---|
| 一键门禁 | **exit 0，12 项全绿，用时 46.8 s**（新增 `input_check` 一步） |
| `input_check` | **exit 0 / PASS，108 条断言**：动作表与关键键位、手柄覆盖、绑定文本、`InputRouter` 分发与让路（遭遇框打开 / 战斗中 / 点海面）、遭遇框焦点与键盘·手柄作答 |
| 生成指纹 | 与存档一致 `19d42d358f8d5495…`（本轮不碰生成，RNG 抽取顺序未变） |
| 生成统计 | 定居点 18 / 桥梁 7 / 植被 5163（与基线一致） |
| 截图 | `hud_loading` / `hud_normal` / `hud_dialog` 三张（1600×900）：遮罩铺满、遭遇框居中 + 变暗背景 + 焦点描边 + 键位提示行 |

### 9.5 B-1 拆 `Main.gd`：全部做完，`854 → 191` 行

`Main.gd` 从 854 行降到 **191 行**，剩下的只有三件事：装配、每帧循环（`_process`）、
以及三个只改自身字段的 UI 回调。字段即对外接口（`tools/` 下的自检脚本、各系统都按这些名字取用）。

**已搬出（四批，`a54d9d5` → `f9a09a8` → `bd44382` → `951d3b2` → 本批，每批都跑满门禁、指纹不变）**：

| 新文件 | 行数 | 搬走了什么 |
|---|---|---|
| `world/MaterialFactory.gd` | 40 | 4 个世界着色器材质的唯一构造点（`_make_materials`） |
| `parties/PartySpawner.gd` | 148 | 开局摆部队：玩家 + 领主 / 商队 / 强盗（`_spawn_*` / `_add_ai` / `_random_town` / `_random_wilderness` / `randi_range_seed`） |
| `core/GameState.gd` | 17 | 玩家初始兵力 37（原来硬编码两处）、势力名兜底文案三份拷贝 |
| `core/OverworldView.gd` | 58 | 标签缩放量化早退、战略视图剔除植被、进 Boss 战整体隐藏大地图 |
| `core/HoverInspector.gd` | 64 | 悬停提示（部队 → 定居点 → 空地）+ 0.1 s 节流 |
| `core/InputRouter.gd` | 173 | 键位翻译成语义信号（见 9.2） |
| `core/TimeFlowController.gd` | 73 | 时间流动状态机（`enum State` / `game_paused` / 流速档位 / 长按空格 / 强制锁 + `evaluate` / `order_move` / `cycle_speed` / `lock` / `unlock`） |
| `core/EncounterRules.gd` | 74 | 遭遇与 Boss 战的全部数值（触发余量、三种冷却、推开距离、Boss HP / 破防公式、战利品与损失率、缴获物称呼） |
| `core/WorldContext.gd` | 30 | 各系统共享的世界句柄 + `set_camera_active()`（遭遇框与 Boss 战都要的相机输入开关） |
| `core/EncounterSystem.gd` | 138 | 遭遇检测、对话框、冷却、退避、战后结算（战利品 / 兵力损失 / 战败回城） |
| `core/BattleLauncher.gd` | 78 | 进出 2D Boss 战（payload 拼装、隐藏大地图、冻结时间与输入、打完复位） |
| `core/WorldGenPipeline.gd` | 294 | `_ready` 里那串 `await` 生成编排（7 步）+ 表现层装配 + 系统接线 |

顺手拆掉一处弱类型侧信道：`data.set_meta("player_ref", player)` + `AIParty` 每帧 `get_meta` → `AIParty.player_target`（typed，由 `PartySpawner` 注入）。

**确定下来的拆分纪律**（`PartySpawner` / `WorldGenPipeline` 文件头也写了）：

1. **不碰生成侧的调用顺序**。指纹由「谁先抽随机数」决定，所以 `_ready` 里的 `await _step(...)` 序列与各级生成器的先后顺序一律不动；`PartySpawner` 之所以能安全搬走，是因为它内部的随机数全部来自「自己新建的 `RandomNumberGenerator`」（`randi_range_seed` / `_random_wilderness`），不抽全局流，而部队种子取自 `ai_parties.size()` —— 只要「谁先被造出来」不变就行。
2. **每批都跑一遍完整门禁再看指纹**，不看 A=B（那是假安全网，见第八节的反向验证）。
3. **新的 `class_name` 要跑一次 `--import`** 才进类缓存（见 9.3 第 3 条）。

**互相回调的四块怎么断环**（这是第三轮最费思量的一处）：

- 遭遇 / Boss 战是**互相**调用的：开战要停时间、战败要把玩家推开、推开又要重新下达行军令。
  正解不是互相持有引用，而是 **信号 + 一个只读上下文**：
  `encounters.attack_requested → battler.start`、`battler.finished → encounters.on_battle_finished`，
  两根线在 `WorldGenPipeline` 末尾接一次。
- 共享的那份东西（`cfg` / `data` / `hud` / `camera` / `router` / `time` / `rules` / `view` /
  `player` / `parties`）放进 `WorldContext`，只放**引用**、不放状态机。
- 结算的归属按「谁的数据谁管」分：战利品 / 损失 / 回城归 `EncounterSystem`（它管冷却），
  场景的进出场归 `BattleLauncher`（它管 `BattleScene` 生命周期）。
- 生成期的临时产物（4 份材质、`TerrainManager`、`WaterBuilder`、`NightLights` 容器、`PartySpawner`）
  **不再挂到 `Main` 上**：生成完就没人再看它们，只把最后的关系（`day_night.register_shader`、
  fog 的 shader 参数、`view.nodes`）在流水线里一次接完。

**⚠ 工具脚本与 `Main` 字段是一份隐形契约**：`tools/` 下的自检脚本直接读 `main.data` / `main.player` /
`main.hud` / `main.ai_parties` / `main.vegetation` / `main.camera_rig` / `main.audio` / `main.config` /
`main.time` / `main.encounters` / `main.battler` / `main._gen_ms` / `main.gen_done`，
所以**搬字段必须同一次提交改工具**（本轮 `main.cooldowns` → `main.encounters.cooldowns`、
`main.encounters_enabled` → `main.encounters.enabled`、`main.battle` → `main.battler.battle`、
`main._on_encounter_choice(...)` → `main.encounters.resolve(...)`）。

**验收（2026-10-13）**：门禁 12 项全绿（36.3 s）；指纹基线 `19d42d358f8d5495…` 不变；
生成统计 定居点 18 / 桥梁 7 / 植被 5163 不变；额外手工跑 `tools/bgm_check.gd`（遭遇 → 攻击 →
Boss 战 → 结算整条链，257 兵领主：HP 583 / 破防 147 / 缴获 154 / 损失 30，与 `EncounterRules` 完全一致）
与 `tools/hud_shot.gd`（三张截图正常，Loading 遮罩仍满屏）。

---

## 十、第四轮变更记录（玩法闭环：经济 / 城镇 / 遭遇多选项 / 存档）

**设计依据**：`G:\warband_docs`（对 `mb_warband.exe` 的逆向笔记：610 个 script / 36 740 op /
1 072 兵种 / 620 物品 / 180 定居点）。那份文档的三级证据标准（**【实证】/【推断】/【未解】**）本轮
**照用**：能从脚本还原的公式就照搬，并在代码注释里写清出处章节；原文档标【未解】的
（城镇菜单条目、遭遇面板选项、食物营养值、招募刷新率……）**一律不编**，改为**显式的本地化设计决策**，
并在 10.3 逐条记账。外部数值是**参考而非照搬** —— 骑砍的金币量级、地图规模、部队规模与本工程
都不同，直接抄数字必然失衡（例如照搬「每人 30 金」的战利品，一场 50 人匪帮就是 1500 金 ≈ 30 周军费）。

### 10.1 本批（4a）交付：钱袋 / 军费 / 士气 / 战利品入账

| 文件 | 改动 |
|---|---|
| `scripts/core/EconomyRules.gd` | **新增**：经济与军费数值表（`Resource`）。每条公式上方标注骑砍出处与本地化理由 |
| `scripts/core/CampaignState.gd` | **新增**：一局游戏的**可变状态**（钱袋 / 补给 / 士气 / 声望 / 兵员档次 / 欠薪周数 / 天数）+ 日结与周结。纯 `RefCounted`、不碰任何场景节点，所以能 headless 直接跑 |
| `scripts/core/GameState.gd` | 补开局常量：`START_DENARS` / `START_SUPPLIES` / `START_MORALE` / `START_RENOWN` / `START_TIER` / `DAYS_PER_WAGE_CYCLE` |
| `scripts/core/WorldContext.gd` | 加 `economy` / `campaign` 两个共享句柄 |
| `scripts/core/WorldGenPipeline.gd` | 建经济状态（**不抽 RNG、不 await → 指纹安全**）；接 `day_night.day_changed → campaign.on_day_changed`、`campaign.day_settled → Main._on_day_settled` |
| `scripts/core/Main.gd` | 挂 `economy` / `campaign` 两个公开字段（工具契约）；新增 `_on_day_settled(report)`，只负责把日结报告说给玩家，**不播音效**（否则会打乱 `sfx_*` 的次数断言） |
| `scripts/core/EncounterSystem.gd` | 胜：战利品进钱袋 + 声望；败：溃散 2/5 兵力并被劫走 1/4 钱财；战斗中撤出：按 `retreat_morale_penalty` 扣士气 |
| `scripts/core/EncounterRules.gd` | 新增 `retreat_morale_penalty()`：**照搬** 01 §5.8 的复合式（两个比例的乘积，整数截断） |
| `scripts/core/BattleLauncher.gd` | 玩家血量 = `campaign.combat_hp()` = 基准 × 兵力 × 档次倍率 ÷ 开局兵力。**开局倍率恰为 1.0** → 不改变现有手感，只让「招兵 / 升档」买到战力 |
| `scripts/ui/TopBar.gd` | 左上栏加「钱袋 / 粮 / 士气 / 声望 / 档次 / 兵力编制」一行：4 Hz 节流 + 值不变不写回 + 接 `changed` 信号即时刷新 |
| `scripts/ui/HUD.gd` | `bind_campaign()`（与 `bind()` 分开，保住 `hud_check` 的旧签名） |
| `tools/economy_check.gd` | **新增**：48 项断言 + 42 天收支时间轴（门禁第 5 步） |
| `tools/hud_check.gd` | 加 7 项钱袋行断言（未绑留空 / 绑定显示 / 变化跟随 / 欠薪 / 解绑清空）|
| `tools/run_checks.ps1` | 8 步 → 9 步 |

**三个结构决定**：

1. **结算挂在 `day_changed` 上，不挂在 `_process` 里**。`DayNightCycle._process` 在跨日那一刻
   `emit day_changed(day)` 恰好一次，所以「时间暂停 / ×1 / ×2 / ×4 / Boss 战锁时间」全部自动正确，
   不需要在任何地方判「今天结过没有」。`Main._process` 里加计时器反而是错的。
2. **`CampaignState` 是 `RefCounted` 而不是 Node**：它是纯数据 + 纯算术，没有一处需要进场景树。
   代价为零，收益是 `tools/economy_check.gd` 可以只 `new()` 一个没有标签的 `PlayerParty` 就跑完整结算
   —— 经济回路因此第一次变成可断言的东西（而不是「开游戏打两天看看」）。
3. **两种状态分家**：`GameState` 只管「第一次进游戏时是多少」（常量），`CampaignState` 管
   「这一局现在是多少」（可变、将来要被存档序列化）。混在一起的话，读档会连开局值一起覆盖。

### 10.2 照搬的公式（【实证】部分）

| 量 | 骑砍原文（出处） | 本工程 |
|---|---|---|
| 单兵周薪 | `(等级+3)²/25`（01 §2.3 `game_get_troop_wage`，**平方**，社区流传的 `(l+3)·l/25` 是错的） | 三档代用等级 4 / 12 / 22 → **1 / 9 / 25** 金/人/周 |
| 领导力折扣 | `×(100 − 5×领导力)/100`，领导力上限 10 | `声望/100` 钳到 0..10（声望 1000 = 过半，工资减半）|
| 部队周薪 | Σ 单兵周薪 × 人数（`calculate_weekly_party_wage`）| 同式；7 天结一次 |
| 士气 | `50 + 领导力×12 − 部队人数 + 食物加成 − 断粮30 − 欠薪罚`，钳 [0,100]（01 §3.3）| 同式 |
| 欠薪罚 | `clamp(欠薪×10/周薪, 1, 31)` | 简化为 `clampi(欠薪周数×10, 1, 31)`（本工程只有周粒度欠薪）|
| 撤退士气 | `((我方阵亡×100 ÷ 双方阵亡) × 我方阵亡 ÷ 我方总数) × −30/100`（01 §5.8）| **原式照抄**（含截断：小队只死 2 人时这会截断成 0 —— 这是原式的性质，不是 bug）|
| 战利品分档 | 不同类型的敌人收益不同（01 §2.9 的商品掷骰）| 沿用第三轮 `EncounterRules.loot_rate(kind)` 的分档，乘每人基准金 |
| 全员等级表 | 1 072 个兵种的等级分布：新兵 1 金/周、骑士 63 金/周、中位数 2、均值 12.53 | 三档 1 / 9 / 25，量级对齐（新兵档低、精锐档高、平均值接近）|

### 10.3 本地化取舍（原文档【未解】或量级不匹配的部分，逐条记账）

| # | 事项 | 原文状态 | 本工程取值与理由 |
|---|---|---|---|
| 1 | 军费结算周期 | 只还原出「周薪」，**调用者【未解】** | 固定 **7 天**（1 天 = 2 分钟 → 约 14 分钟一次），并且**显式声明这是选择**，不假装是实证 |
| 2 | 兵员档次 → 等级 | 1072 个兵种各有等级 | 三档取代表等级 **4 / 12 / 22**（对应新兵 / 正规军 / 精锐）|
| 3 | 食物营养值 | `item_get_slot(item,1)` 的实际值 **【未解】** | 每件补给 **+1.5 士气、封顶 +15**（量级对齐原文 `×3/2` 求和的口径）|
| 4 | 补给消耗率 | `consume_food` 的调用者与频率 **【未解】** | 每 **10 兵每天 1 件**，至少 1 件 |
| 5 | 逃兵规则 | 原文只有士气阈值，**没有逃兵逻辑** | **本地化新增**：士气 < 20 时按 `(20−士气)/20 × 25%` 减员（上界 25%，不会一夜崩光）|
| 6 | 战利品每人基准金 | 30 金/人是**物品掷骰权重 × 市价**，不是现金流 | **6 金/人**：一场 50 人匪帮 ≈ 255 金 ≈ 1.8 周军费；否则一场匪帮能养半年 |
| 7 | 档次战斗力倍率 | 档次差异体现在兵种属性 / 装备 / 升级树 | **1.0 / 1.35 / 1.8**：没有它「升档」是纯支出，没有任何玩家会选 |
| 8 | 开局声望 | 存于 exe，**【未解】** | **120**：让 37 人开局落在「士气 40（中性）、编制 51（留 14 个补兵位）」|
| 9 | 城镇菜单 / 遭遇面板选项 / 城堡被价格归一化跳过 / 村庄 ×5/4 等原版怪癖 | 菜单条目与选项**【未解】**；怪癖是【实证】 | 怪癖记入 10.5，留给 4b 参考；菜单与选项 4b / 4c 作为**显式设计决策**实现（遭遇选项的定价与门槛记在 §10.8） |

### 10.4 本批实测（2026-10-13）

- **门禁 9 步 / 13 项全绿，用时 43.0 s**（新增 `economy_check` 一步，其余时长不变）。
- **指纹基线 `19d42d358f8d5495…` 不变**，生成统计 定居点 18 / 桥梁 7 / 植被 5163 不变
  —— 经济接线只做纯算术与信号连接，不抽 RNG、不 await。
- `tools/economy_check.gd`：**48 项断言全通过**。42 天收支时间轴（每 5 天一场 50 人匪帮、
  粮 <15 就补、第 15 天升档）：足额发薪 6 次 / 欠薪 0 次 / 断粮 0 天 / 最低钱袋 336（初始 400）。
- `tools/hud_check.gd`：**38 项断言全通过**（第三轮是 31 项 + 本轮钱袋行 7 项）。
- `tools/hud_shot.gd` 三张截图目视：左上栏第五行为
  「钱袋 400 金 · 粮 35 件 · 士气 40 · 声望 120 · 民兵 37/51」，无裁切、无错位。
- **临时端到端探针**（跑完即删，未进仓库）：真实场景下达行军令 → `DayNightCycle` 自己跨日 →
  `[日结] 第 2 天：兵力 37，粮 32（吃 3），士气 40，钱 400` → HUD 钱袋行同一帧变成「粮 32 件」。
  这一条补上了自检的盲区：`economy_check` 是**直调** `on_day_changed`，验不了
  「信号有没有真的接上」。
- 性能基准：钱袋行**第一版是每帧刷新**（每帧重建字符串 + 每帧 `add_theme_color_override`），
  门禁立刻报 **2 条 WARN**（`idle avg 1.498 ms > 基线 0.847 × 1.5`、`march 1.672 > 1.100 × 1.5`）。
  改成「**4 Hz 节流 + 值不变不写回**」（`add_theme_color_override` 会脏掉 Label 的样式缓存、
  把它标成需要重绘）之后复跑：**WARN 回到 1 条**，即第三轮的常态水平。这也是本轮唯一一处
  由性能门禁抓出来的真问题 —— 阈值内不判失败，但它把「每帧白干活」显出来了。

### 10.5 欠账与后续

- **4b 城镇交互**（下一步）：进城菜单（补给 / 招募 / 贸易 / 驻军）、`Settlement` 补繁荣度与志愿者池、
  市场按繁荣度定价。参考要点已记：城镇 = 5 项服务、城堡 = 1 项（管家）、村庄 = 1 项（长老）；
  招募 **10 金/人**、名额写回 **−1**（不是 0）；关系按 **×100 整数**存（float 直接存会退化成 0）；
  城堡在原版里被价格归一化的两个阶段跳过（这是**原版行为**，不是简化）。
- **4c 遭遇多选项**：选项表数据驱动（原文档此处【未解】，本工程按设计决策给出并标注），
  同时把 Boss 战结束时的伤亡账本（`p_temp_casualties` 等）补上 —— 原版 BattleEnd 清理是必须的。
- **4d 存档**：`CampaignState` + 玩家位置 + `day_night` 状态序列化。（**已交付**，见 10.9 —— 第四轮四件到此闭环）
- **经济平衡的已知短板**：匪帮被清光后不会再生（`PartySpawner` 只在开局生成），
  一旦地图上 12 支匪帮全灭，收入就只剩商队与领主 —— 需要一条「匪帮再生 / 商队贸易」的
  持续收入线，候选放进第五轮。
- 第四轮的**城镇交互还需要一个 InputMap 动作**（进城交互键）：加动作后必须同步扩
  `tools/input_check.gd`，否则门禁里那条「动作表 ↔ InputMap 一致」的断言会红。
  （4b-1 只做逻辑层，动作与菜单面板一起放在 4b-2。）

### 10.6 本批（4b-1）交付：城镇交互的**逻辑层**（补给 / 招募 / 贸易 / 驻军）

先落逻辑、再落界面：菜单能不能点、点了扣多少钱、钱不够时会怎样 —— 这些是这条价值链的
真正风险点，而它们全都可以在没有窗口的情况下断言。界面（面板 + 交互键）放 4b-2。

| 文件 | 改动 | 职责 |
|---|---|---|
| `scripts/world/Settlement.gd` | 改 | +`prosperity` / `volunteers` / `volunteers_cap` / `good_bias`；`service_ids()`（服务表数据驱动）、`has_service()`、`prosperity_name()`（五档）、`interact_radius()` |
| `scripts/core/EconomyRules.gd` | 改 | +4 种货物的基准价、繁荣度价格系数、买/卖价、补给价、招募单价、志愿者上限与回流间隔、卖价回收率 |
| `scripts/core/CampaignState.gd` | 改 | +货物背包（`goods` / `goods_of` / `add_goods` / `take_goods`）、`take_troops()`（驻军取回，受编制限制）、`add_supplies()` |
| `scripts/core/SettlementSystem.gd` | **新** | 位置判定 / 进城出城（时间锁）/ 菜单条目 / 四类交易 / 志愿者回流 / `assign_environment()` |
| `scripts/core/WorldGenPipeline.gd`·`Main.gd` | 改 | 接线：`settlements` 字段、`day_changed → on_day_changed` |
| `tools/settlement_check.gd` | **新** | 92 项断言：价格定式、五类边界、贸易套利、驻军与军费联动、菜单行数、进城出城 |
| `tools/run_checks.ps1` | 改 | 新增第 6 步（10 步 / 14 项） |

**三个结构决策：**

1. **菜单是数据，不是控件** —— `menu_entries()` 回过 `[{id, label, enabled, hint}]`，
   HUD 只照着画、不做任何「能不能做」的判断。于是「钱不够 / 编制满 / 池子里没人 /
   城里没兵 / 没货可卖」这 5 类边界全部可以 headless 直测（4b-2 的面板因此薄得只有渲染）。
   灰掉的条目也**必须**给出 `hint`：玩家得看得见「为什么不能点」，而不是对着灰按钮发呆。
2. **`SettlementSystem` 一行 UI 节点都不碰** —— 反馈走 `ctx.hud.show_toast()`，`hud == null`
   时静默（自检里就没有 HUD）。这与 `CampaignState` 不弹提示、只回 `report` 是同一条原则。
3. **刻意不给 `WorldContext` 加 `settlements` 字段** —— 本系统已经持有 `ctx`，再加一条反向
   引用就是一个 **RefCounted 引用环**（两个对象互持、引用计数永不归零）。这不是纸上担心：
   第一版正是这么写的，门禁立刻有 **6 步变红**：

   ```
   ERROR: 3 RID allocations of type '…DummyTexture' were leaked at exit.
   ERROR: 19 resources still in use at exit (run with --verbose for details).
   ```

   纹理是跟着 `ctx → data` 一起被环吊住的。去掉那条反向引用后立刻回到全绿，
   取用方（`Main` / `tools/`）直接拿 `pipeline.settlements`。这条约定写进了
   `WorldContext.gd` 的文件头。**这是本轮唯一一个由门禁抓出来的真问题。**

**照搬的公式（【实证】）：**

| 项 | 出处 | 本工程 |
|---|---|---|
| 村庄招募 `min(志愿者池, 编制余位, 金/人)`、单价 10 金 | 01 §2.7 | 原样（`CampaignState.recruit` 管编制与钱，`SettlementSystem.recruit` 管池子） |
| 招募后志愿者池**按人数写回扣减**（each −1，不是清零） | 01 §2.7 | 原样：招 3 个 → 池子 −3 |
| 买价 ÷100、卖价 ÷(100+penalty) 的**不对称**（商人吃差价） | 01 §? | 形状保留，本地化成一个固定回收率 60% |
| 价格按繁荣度归一化；繁荣度按 20 一档分 5 级 | 05 §? | 原样（五档名：荒废 / 萧条 / 平常 / 富庶 / 繁荣） |
| 货物基准价与价格区间 [100, 10000] | 02 §3.3.1 | 形状保留，量级本地化（见下表） |

**本地化取舍（原文档【未解】或量级不匹配的部分）：**

| 项 | 原文档情况 | 本工程取值 | 理由 |
|---|---|---|---|
| 菜单条目清单 | **【未解】**（没有发行文件可查） | 城堡 `补给/驻军`、村庄 `补给/招募`、城镇四样齐全 | 按「这地方该有什么」的设计决策；城堡是军事据点，不赶集不招兵 |
| 城堡的 1 项「管家」服务 | 05 §? 提到 | 不单独做 NPC | 本工程没有 NPC 对话系统，服务直接落在菜单上 |
| 货物种类与基准价 | 34 种、基准 250 | 4 种（8/15/24/38 金） | 金币量级小两个数量级；保留「基准 × 繁荣系数 × 本地价差」形状 |
| 本地价差 | 原文是市场收敛后的结果 | 每种货 ±15%，生成期一次性定死 | 让「这儿的盐便宜」有确定性；也是贸易路线成立的前提 |
| 志愿者刷新率 | **【未解】** | 每 2 天每地 +1，上限 村庄 12 / 城镇 20 / 城堡 0 | 需要一条「待几天就能再招」的节奏 |
| 驻军来源与作用 | **【未解】**（只说有驻军） | 只能「存 / 取」，不参与战斗；存入至少留 5 人 | 意义在**工资按人数算**：养不起时先把人存起来（断言里专门锁了「存兵后周薪下降」） |
| 繁荣度的生成 | 原文由经济模拟演化 | 生成期用 `make_rng("settlement_economy")` 一次定好（以类型为底 ±25） | 独立随机流 ⇒ 不消耗主生成流、不动生成顺序 ⇒ **指纹不变** |

**实测（2026-10-13）：**

- **门禁 10 步 / 14 项全绿，用时 43.2 s**（新增 `settlement_check` 0.6 s）。
- **指纹 `19d42d358f8d5495…` 与生成统计 18 / 7 / 5163 均不变**；`perf_probe` 仍是 1 条 WARN（常态）。
- `tools/settlement_check.gd`：**92 项断言全通过**。代表性几条：
  繁荣地 5 金买入 → 荒废地 6 金卖出（一趟 10 件赚 50 金）；招募 3 人后池子 5 → 2；
  驻军 10 人后周薪 35 → 25；存到极限仍留 5 人看家。
- 本批**只加逻辑**：主场景 900 帧行为与 4a 完全一致（没有任何东西会去调它）。

**本批踩到的坑（都已修）：**

1. **引用环泄漏**（见上，门禁 6 步红）——这是唯一一个真 bug。
2. `close()` 返回 `void`，`_ok(not sys.close(), …)` 直接在解析期就报
   `Cannot get return value of call to "close()"`：断言「重复关是空操作」得改成
   「关两次后 `current == null` 且时间锁是开的」。
3. 自检里的假世界**没有寻路栅格**，`PlayerParty.set_destination()` 会打在
   `data.path_fine` 上（`Nil`）——「让部队在行军」直接置 `moving = true` 即可。
4. 「没货时卖出行灰掉」这条断言原本查的是**村庄**菜单，而村庄根本没有市场那一行
   —— 断言自己错了，不是逻辑错了。
5. 志愿者池只写了向上回流、没写向下夹上限；补上夹位后才配得上「上限」这个词。

---

### 10.7 本批（4b-2）交付：进城菜单的**界面层**与交互键（第四轮 4b 收尾）

4b-1 已经把菜单做成「一份数据」，4b-2 只做三件事：把它画出来、给它一个键、让它跟世界对得上。
面板里**没有一行业务判断** —— 交易规则仍由 4b-1 的定式自检覆盖（本批只在同一份自检里加了
`tick` 提示与时间锁两条，92 → 104 项）。

| 文件 | 改动 | 职责 |
|---|---|---|
| `scripts/ui/SettlementDialog.gd` | **新** | 进城面板：每行 = 按钮 + **常显**原因小字；灰行移出焦点序列；打开即给第一个可用行焦点；Esc = 离开；**自己不关面板** |
| `scripts/ui/HUD.gd` | 改 | +`settlement_dialog` / `show_settlement_menu()` / `hide_settlement()` / `is_any_dialog_open()` 与 `settlement_action` 信号；悬停提示改用「任一面板在场」 |
| `scripts/core/InputRouter.gd` | 改 | +`interact_requested` 信号；让路条件由「遭遇框打开」放宽到「任一面板打开」 |
| `scripts/core/SettlementSystem.gd` | 改 | +`tick(delta)`（半秒一次：走到定居点旁提示一次交互键）、`open()` 拒绝在世界时间被锁时抢菜单 |
| `scripts/core/Main.gd` | 改 | `_process` 调 `settlements.tick()`；四个回调（交互键 / `opened` / `menu_changed` / `closed`）与 `_refresh_settlement_menu()` |
| `scripts/core/WorldGenPipeline.gd` | 改 | 接线：`hud.settlement_action → resolve`、三条系统信号 → Main、`router.interact_requested → Main`；补上 **`assign_environment()` 的调用**（4b-1 漏了，见坑 1）与一行环境概览打印 |
| `project.godot` | 改 | 新增 `interact` 动作（**G** + 手柄 A）：211 → **217** 行 |
| `scripts/ui/HelpPanel.gd` · `ToastLabel.gd` | 改 | 操作说明加「进城办事」一行；提示条 140 → **180**（原来正压在钱袋那一行上） |
| `tools/input_check.gd` | 改 | 断言 108 → **129**：`interact` 绑定、菜单让路、菜单焦点与按键作答 |
| `tools/hud_check.gd` | 改 | 断言 38 → **57**：菜单几何、条目数据、灰行带原因、点行转发、提示抑制 |
| `tools/settlement_check.gd` | 改 | 断言 92 → **104**：`tick` 提示与节流、时间锁下不抢菜单 |

**三个结构决策：**

1. **面板不认识业务，也不自己关** —— `show_settlement_menu(title, status, entries)` 收的是
   `SettlementSystem.menu_entries()` 的原样数据；点一行只发 `choice(action)`，**面板保持打开**
   （买完补给还要接着招兵）。何时关由业务层决定：`resolve("leave")` → `closed` → HUD 收起。
   于是 `hud_check` 不用建世界就能把面板单独测一遍，而「菜单该有几行、哪行该灰」永远只有一个来源。
2. **灰掉的条目必须说得出原因，并且拿不到焦点** —— 每行固定是「按钮 + 12 px 小字」两行结构，
   `enabled == false` 时不仅变灰、还带一句「钱不够（需 10 金）/ 没有志愿者 / 编制余位 0」，
   同时 `focus_mode = FOCUS_NONE`（焦点落在按不动的按钮上是死路一条）。
   实测：按 ↓ 会**跳过**灰行直接落到下一个可用行（内建焦点导航，未写一行自定义代码）。
3. **交互键是新动作，提示必须自己长出来** —— `SettlementSystem.tick()` 每 0.5 s 看一眼玩家脚下，
   只在「刚走到某个定居点旁」时弹一次 `G / 手柄A 进入 <地名>（类型）`。
   提示条文本里的键位来自 `InputRouter.action_hint_text("interact")`（改键不改代码），
   出城后清掉「已提示」记录（站在原地想再进去是常事）。**提示不发任何声音** ——
   `sfx_map_check` 断言的是精确播放次数，这里多一声就红。

**键位决策（为什么是 G + 手柄 A）：**

| 候选 | 结论 | 原因 |
|---|---|---|
| `E` | ✗ | 已被 `cam_rotate_right` 占用（`project.godot:85`） |
| 十字键上 / 下 | ✗ | 已被 `move_up` / `move_down` 占用（`joy 11` / `joy 12`） |
| `G` + 手柄 `A` | ✓ | G 空闲；A 在遭遇框里是「确认」，而两者的**输入域不重叠**：菜单 / 对话框打开时 `InputRouter` 整体让路，地图侧监听 `interact`、对话框侧监听 `dialog_confirm`，永远不会同时响应 |

**实测（2026-10-13）：**

- **门禁 10 步 / 14 项全绿，用时 43.1 s**（本轮共跑 3 遍，43.1~43.7 s）；指纹 `19d42d358f8d5495…` 与生成统计 18 / 7 / 5163 **均不变**
  （本批只加界面与一个输入动作，没碰生成）；`perf_probe` 仍是 1 条 WARN（常态）。
- 自检：`settlement_check` **104** 项、`input_check` **129** 项、`hud_check` **57** 项，全部通过。
- **真实场景端到端**（一次性截图探针，跑完即删）：走到「格兰集市」→ 提示条弹出 →
  **真按键 G** 进城（走完整 `InputMap → InputRouter → Main → SettlementSystem → HUD` 链路）→
  菜单 9 行、状态行「格兰集市 · 城镇 · 繁荣 62（富庶）· 驻军 139 人 · 志愿者 20 人」、
  首行拿到焦点 → `数量 ×1 → ×10`、买 10 件补给 + 10 件谷物（400 → 290 金、粮 35 → 45、货物 10 件）→
  **「卖出」那一行由灰变亮**（证明 `menu_changed → Main → HUD` 的刷新链路真的通）→ `Esc` 出城、时间锁解除。
  面板 rect：540×665 @ (530,117)，视口 1600×900（居中）；提示条移到 y=180 后与钱袋行不再重叠。
- 相对 4b-1：+1 文件 / +525 行（其中 `tools/` 侧 +219 行是断言），`project.godot` +6 行。

**本批踩到的坑（都已修）：**

1. **`assign_environment()` 在 4b-1 根本没被调用过** —— 逻辑层自测全绿（`settlement_check` 直接调它），
   但真实场景里每个定居点的繁荣度都是 0、志愿者池是空的、货物没有本地价差：菜单能开，
   内容却是死的。本批在 `WorldGenPipeline` 里补上调用，并加了一行环境概览打印，
   让「生成期确实赋值了」在门禁日志里看得见（自测只能证明函数本身对）。
2. **`HUD.is_any_dialog_open()` 在没有 `setup()` 时会崩** —— 它直接摸 `dialog.is_open()`，
   而 `dialog` 是 `setup()` 里建的。`settlement_check` 的 `StubHud extends HUD` 因此必须把
   `is_any_dialog_open()` 一起覆盖掉（替身只覆盖「自己会用到的方法」是不够的，
   还得覆盖那些会摸到未初始化字段的方法）。这也顺手说明了为什么 `tick()` 走
   `ctx.hud.is_any_dialog_open()` 而不是去问两个面板：业务层只该知道「屏幕被占了没有」。
3. **提示条压在钱袋行上**（`TOP_MARGIN 140`）：进城做买卖时提示条与钱袋**同时**在变，
   互相遮挡等于两条信息都看不见 —— 下移到 180，落在信息栏之下、地图之上。
4. 截图探针里 `resolve("buy")` 写错了动作名（真名是 `"supply"`），`resolve()` 的 `_` 分支静默忽略，
   于是「买补给扣钱加粮」这条断言失败 —— **静默忽略未知动作是对的**（HUD 不该靠拼错字符串改状态），
   但探针必须用真名；改成真名之后，`menu_changed → Main → HUD` 的刷新链路也一并得到了真实验证。
5. `%%` 只在**参与格式化**的字符串里才是转义：`settlement_check` 里有一条断言文字自带百分号
   却没用 `%` 格式化，结果屏幕上直接打出 `±15%%`。自检的输出也是给人看的，一样要收拾干净。
6. 一次性的截图探针跑完就删：`tools/` 只留长期有用的自检（判据是「改一行代码后它还该不该跑」）。

---

### 10.8 本批（4c）交付：遭遇的**多选项**（攻击 / 花钱买路 / 索要买路钱 / 撤退）

4a 让遭遇只有一条路（打），4b 让城镇能买东西，4c 把「在路上遇到人」本身变成一个决定：
**遭遇面板不再是两个写死的按钮，而是一张数据驱动的选项表**，每一行都有自己的条件、代价与收益。
4b-2 立下的两条规矩（面板不认识业务、面板自己不关）原样沿用，所以自检不用建 UI 就能把四条路跑一遍。

原文档 `G:\warband_docs` 里**「遭遇面板有哪些选项」是【未解】**（01 §5.8 只落档了撤退的士气公式，
菜单条目没有）；因此选项集合、定价与门槛是本批的**显式本地化设计决策**，逐条记账如下。

| 文件 | 改动 | 职责 |
|---|---|---|
| `scripts/core/EncounterRules.gd` | 改（+69） | 四项定价纯函数：`toll_per_man` / `can_toll` / `enemy_power` / `renown_discount` / `bribe_price` / `demand_gain` / `demand_need` / `demand_renown` |
| `scripts/core/EncounterSystem.gd` | 改（+176 −10） | `options()` 生成选项表；`resolve()` 由「攻击 else 撤退」改成四条分支 + `_do_retreat / _do_bribe / _do_demand`；`last_ledger` 台账；**修掉撤退不解时间锁**（见坑 1） |
| `scripts/ui/EncounterDialog.gd` | **重写**（+134 −44，208 行） | 数据驱动多行面板（与 `SettlementDialog` 同构）：每行 = 按钮 + **常显**原因小字；灰行移出焦点序列；打开即给第一个可用行焦点；**自己不关面板** |
| `scripts/ui/HUD.gd` | 改（+5 −2） | `show_encounter()` 多收一个 `entries`（不传则用兜底两行，老调用点全部保持可用） |
| `tools/encounter_check.gd` | **新**（575 行 / **117** 项断言） | 定价 / 选项表 / 四条路的效果 / 静默拒绝 / 时间锁 / 冷却 / 战斗结算台账 |
| `tools/hud_check.gd` | 改 | 断言 57 → **68**：条目顺序、可用性原样来自数据、灰行带原因且不进焦点链、点行转发、面板不自关 |
| `tools/input_check.gd` | 改 | 断言 129 → **135**：焦点改走 ↑↓（面板变竖排，见坑 2）、取消键不跟随光标、↓ 跳过灰行 |
| `tools/hud_shot.gd` | 改 | 截图探针改成取生产代码 `EncounterSystem.options()` 的真实输出（截出来的就是玩家会看到的那张表） |
| `tools/run_checks.ps1` | 改（+12） | 新增第 6b 步：10 步 / 14 项 → **11 步 / 15 项** |

**四条路（每条路的代价都不同 —— 这是本批的设计核心）：**

| 选项 | 可用条件 | 效果 | 依据 |
|---|---|---|---|
| 攻 击 | 永远可点 | 进 Boss 战：赢 → 战利品 + 声望；输 → 掉兵 40% + 被拿走 1/4 钱 + 回城 | 原版主路径（【实证】） |
| 花钱买路 | 强盗 / 商队 且 钱 ≥ 价码 | 扣钱、零伤亡、进冷却（14 s） | 【本地化】原文档只有「贿赂」概念，没有公式 |
| 索要买路钱 | 战力 ≥ 1.5 × 敌方当量 | +钱 +声望、零伤亡、进冷却 | 【本地化】把 4a 的编制成长兑现成「不战而屈人」 |
| 撤 退 | 永远可点 | 掉队 + 士气按伤亡比例下降 + 冷却（14 s） | 士气公式**照搬** 01 §5.8（含整数截断，见 10.2） |

**定价（全部本地化，量级对齐 4a 的经济基线：开局 400 金 / 37 人 / 周薪 35 金）：**

- `toll_per_man`：强盗 **3** / 商队 **5** / 领主 **0**（不收）。
- `bribe_price = max(10, 人数 × 每人 × (100 − 声望/20，封顶 30) / 100)` ——
  开局（声望 120 → 折扣 6%）实测：30 人强盗 **84 金**、78 人大盗 **219 金**、30 人商队 **141 金**。
  量级 ≈ 一周军费的 2~6 倍：买路明显比打一仗「贵」，但换的是零伤亡。
- `enemy_power = round(人数 × 0.8 / 1.0 / 1.4)`（强盗 / 商队 / 领主），
  `demand_need = ceil(1.5 × 当量)` —— 开局 37 战力能唬住 22~30 人的小股强盗（门槛 27~36），
  唬不住 78 人的大盗（门槛 93）；编制涨到 120 人时压得住（**4a 的成长在这里兑现**）。
- `demand_gain = round(无折扣价码 × 1.2)`（收的比交的多一点，你是主动方）、
  `demand_renown = max(1, 人数/20)`。

**四个结构决策：**

1. **面板只画数据，可行性只有一个来源** —— HUD 收 `options()` 的 `[{id, label, enabled, hint}]` 原样画，
   点一行只发 `encounter_choice`；算「谁亮谁灰」永远只有 `EncounterSystem.options()` 一处。
2. **不可点的行必须说得出原因** —— 领主那两行不仅灰掉，还写明「领主不收买路钱（军事贵族不吃这一套）」
   「领主宁死不交买路钱（讹诈只对强盗 / 商队有效）」；钱不够写「现有 400 金；声望折扣 −6%」；
   战力不够写「你的战力 37，需要 ≥ 93」。**灰行还写在按钮标题上**（「花钱买路（84 金）」），
   玩家不用点进去就知道要花多少。
3. **`resolve()` 对不合法动作一律静默拒绝** —— 保留 `current`、面板不关、时间仍锁着。
   面板不是权威：自检、控制台作弊、以及「开着面板时钱被别处扣掉」都会送进不可能的动作。
4. **每一次解决都留一本台账**（`last_ledger`）—— `{action, kind, ally_start/enemy_start,
   ally_dead/enemy_dead, ally_left, gold_delta, renown_delta}`。其中「战斗中途撤出」的敌方伤亡是
   **按损失率估的**（记为【推断】：Boss 战是单挑表现，没有逐兵伤亡），旧实现直接把「我方伤亡」
   复制一份当敌方伤亡（等于假定双方伤亡永远相当）—— 现在是台账里一个显式的估计。

**实测（2026-10-13）：**

- **门禁 11 步 / 15 项全绿，用时 49.1 s**（新增 `encounter_check` 0.7 s）；指纹 `19d42d358f8d5495…`
  与生成统计 18 / 7 / 5163 **均不变**（本批只动遭遇与界面，没碰生成）；`perf_probe` 仍是 1 条 WARN（常态）。
- 自检：`encounter_check` **117**（新）、`hud_check` **68**、`input_check` **135**、
  `settlement_check` 104、`economy_check` 48，全部通过。
- **真实渲染截图**（`tools/hud_shot.gd`，改成取生产代码的真实选项表）：78 人大盗那一屏是
  攻击（预计掉队 7 人）/ 花钱买路（**219 金**，现有 400 金；声望折扣 −6%）/
  **索要买路钱（281 金）灰掉**（你的战力 37，需要 ≥ 93）/ 撤退（掉队约 7 人，14 秒内它追不上来）；
  面板 rect **500×491 @ (550,204)**，视口 1600×900（居中，四行 + 小字不溢出）；
  标题与首行拿焦点框，页脚「回车 / 手柄A 确认　Esc / 手柄B 撤退　↑↓ 选择条目」由 `InputMap` 生成。
  截图在 `%TEMP%\warband_shots_r4c\`（`hud_dialog.png` / `hud_normal.png` / `hud_loading.png`）。
- 相对 4b-2：+1 文件 / +987 行（84 个 `.gd` / 16584 行；`tools/` 侧 +661 行，其中新自检 575 行）。

**本批踩到的坑（都已修）：**

1. **撤退之后世界时间会永久冻住**（真 bug，不是自检挑刺）：旧 `resolve()` 的撤退分支调的是
   `ctx.time.evaluate()` 而不是 `unlock()` —— `evaluate()` 看到 `time_lock == true` 就把状态判成
   `LOCKED`，于是**任何一次撤退之后时间再也不流动**（玩家会当成游戏卡死，只能重开）。
   4c 重写 `resolve()` 时才看出来：`unlock()` 全工程只有两处调用（遭遇空指针兜底、`BattleLauncher`
   战斗收尾），撤退那条路一直是漏的。现在三条「和平解决」的路（撤退 / 买路 / 索要）都在收尾时
   调 `ctx.time.unlock()`，`encounter_check` 有一条断言专门守着它，并且顺带断言解锁后状态回到
   `MARCHING`（行军途中时间照常流动）。
2. **面板从横排变竖排，输入自检跟着失效**：老版本是两个并排按钮，`input_check` 断言「按 → 把焦点移到
   撤退」；四行竖排之后 → 在几何上没有邻居，按下去焦点不动 —— 断言改成 ↑↓，并补了
   「取消键不跟随光标」（焦点在第几行，Esc 都等于撤退）与「↓ 跳过灰行」。
3. **实际掉的兵不能只在文案里估算**：撤退文案写「掉队 3 人」，但只剩 6 人时 `lose_troops()` 的
   5 人下限会让真实减员变成 1 人 —— 台账与士气公式必须用**真实**减员，否则士气会按一场没发生的
   伤亡扣。自检里用「6 人打 90 人领主」把这条钉死。
4. **自检的期望值不能写死开局数字**：初版断言写「士气 50 → 49」，而开局士气其实是 **40**
   （由补给 35 件 / 编制 51 推出来的）—— 一次 5 项失败全出在这一处；改成先读 `m0` 再比相对值。
   同理，78 人强盗的索要门槛是 **93**（先 `round(78×0.8)=62` 再 ×1.5），不是想当然的 94：
   断言里的数字要么从规则函数现算，要么就别写进文案。
5. **打赢分支会 `queue_free()` 那支部队**：自检把敌军挂在树根上（而不是造孤儿节点），
   否则 `queue_free()` 的节点在 `quit()` 前不一定真被释放，会留下
   `resources still in use at exit` 的 `ERROR:` 行 —— 门禁对 `ERROR:` 零容忍。结算之后补一帧
   `await process_frame` 让删除队列真的跑掉。

### 10.9 本批（4d）交付：快速存档 / 快速读档（第四轮收尾）

第四轮四件事到此闭环：**4a 让钱有意义 → 4b 让城镇能花钱 → 4c 让遭遇有得选 → 4d 让这一局能存下来**。
`F5` 存、`F9` 读，落在 `user://saves/quick.json`（真机路径
`%APPDATA%\Godot\app_userdata\Warband Strategic Map\saves\quick.json`）。

原文档 `G:\warband_docs` 里**「存档里有哪些字段、什么顺序」是【未解】**（整份文档没有任何 savegame 落档），
所以**格式本身是本批的显式本地化设计决策**；但原文有三条可以直接照用的**设计含义**，逐条落地并标注：

| 出处 | 原文事实（照抄的只有「含义」，不是数字） | 落到本工程的哪一行 |
|---|---|---|
| 04-数据字典 §17【实证】 | `compatible_savegame_module_version`（int，`0x08b8534`）：原版把「存档模块版本」写进存档、读取时比对 | `SaveGame.SAVE_VERSION` + `MAGIC` + `map_seed` + 定居点行数 + 部队 `spawn_id`：五道身份门，任一不合**拒绝读档**，不猜着读 |
| 02-玩法设计 §3.4.1【实证】 | `change_player_party_morale` 在加 delta **之前**先把读到的士气钳到 [0,100] | `CampaignState.add_morale` 改成预钳制；`SaveGame._clamp_warn` 对**每个**字段先钳再写，并把钳掉的值记成警告 |
| 02-玩法设计 §6.5【推断】 | `game_event_battle_end` 的收尾脚本必须清掉悬空引用 | `apply()` 结尾的「修引用」：清 `encounters.current` / `settlements.current`、收面板、作废旧寻路、解时间锁、按新 `instance_id` 重建冷却 |

**这三条为什么都不是形式主义：**

- **版本门**：读不懂的存档猜着读 = 把玩家的进度换成一份「看起来正常」的错状态。拒绝 + 说清原因，玩家至少知道该做什么。
- **预钳制**：只钳结果的话，坏士气 300 会一直**粘在 100**（300 − 5 → 295 → 钳 100，永远降不下来）。先钳读到的值：300 读进来就是 100，再减 5 就得到 95。`save_check` 第 4 节专门钉了这一条。
- **修引用**：读档后世界里「当前遭遇的那支部队」「进城菜单的那个定居点」都是**上一局的对象指针**；不清掉就是悬空引用（原版为此专门写了收尾脚本，不是顺手写的）。

**存档格式 v1（一个槽一个 JSON 文件）：** `magic / version / map_seed / saved_at` 四个身份字段，
外加 `campaign`（日 / 钱 / 粮 / 士气 / 声望 / 档次 / 欠薪周数 / 货物）、`time`（日 / 时刻 / 流速档）、
`player`（x / z / 兵力）、`settlements[]`（id / 繁荣度 / 志愿者 / 驻军）、`parties[]`（**spawn_id** / 兵种 /
兵力 / 位置 / 阵营 / 姓名 / 名号 / 是否重装 / 是否头目 / 遭遇冷却）。

| 文件 | 改动 | 职责 |
|---|---|---|
| `scripts/core/SaveGame.gd` | **新**（400 行） | 采集 / 五道门校验 / 写回 / 修引用 / 文件读写。**格式只此一处**（要升版就改这一个文件），系统只被写公共字段 |
| `scripts/parties/PartyBase.gd` | 改（+3） | 新增 `spawn_id`：生成顺序的序号，读档对齐实体的**稳定 id** |
| `scripts/parties/PartySpawner.gd` | 改（+2） | `_add_ai()` 写入 `spawn_id = parties.size()`（不消耗 RNG、不改生成顺序） |
| `scripts/core/CampaignState.gd` | 改（+8 −2） | `add_morale` 预钳制（02 §3.4.1【实证】） |
| `scripts/core/InputRouter.gd` | 改（+13） | `save_requested` / `load_requested` 两个信号，**刻意放在「对话框让路」之前**（能不能存由业务层判，不按了没反应） |
| `scripts/core/Main.gd` | 改（+70） | `_blocked_reason()` + `_on_quicksave_requested()` / `_on_quickload_requested()`：判定、提示、读档后揭迷雾 |
| `scripts/core/WorldGenPipeline.gd` | 改（+3） | 把两个新信号接到 `Main` |
| `scripts/ui/HelpPanel.gd` | 改（+4 −1） | 帮助面板 +2 行（共 16 行），面板长高 38 px（`-352 → -390`） |
| `project.godot` | 改（+10） | `quicksave` = **F5**、`quickload` = **F9**（**只绑键盘**，见取舍 5） |
| `tools/save_check.gd` | **新**（548 行 / **137** 项断言） | 格式 / 三道门 / 坏数据 / 修引用 / 打掉的不复活 / 文件层 / 往返稳定性 |
| `tools/run_checks.ps1` | 改（+12 −1） | 新增 **6c) save_check**（11 步 → 12 步） |

**五条本地化取舍（与原版不同、且必须记账）：**

1. **不存地图**：地图是「种子决定论」的产物（`map_seed` → 6~7 秒重建）。存整张地图只会把存档与生成版本绑死；
   存档只记种子，读档 = 重建世界 + 套状态。代价是读档要重跑一遍生成（单机、无联机需求，接受）。
2. **实体靠稳定 id 对齐，不靠数组顺序**：定居点用 `Settlement.id`，部队用 `AIParty.spawn_id`。
   部队**绝对不能**按数组下标存 —— 打赢一场 Boss 战会 `ctx.parties.erase()` 掉一格，之后全体错位。
   档案里有、世界里没有 → 拒绝读档；世界里没有、档案里也没有（= 已经被打掉的）→ 读档后保持消失（**不复活**）。
3. **面板状态不存**：读档会把遭遇框 / 进城菜单收起来；存档也只在「没有面板」时允许（`Main._blocked_reason()`）。
   面板开着存下来、读回去会得到「面板开着但对象已经换了」的错位。
4. **AI 的内部计时不存**（重寻路计时 / 追击计时 / 寻路失败退避 / 游荡锚点）：读档后按生成态重来。
   它们只影响「下一步往哪走」，存下来会让格式跟着 AI 实现的细节一起变。
5. **手柄不绑存读档**（只 F5 / F9）：手柄上按错键就是「把进度覆盖掉」，而 4d 没有二次确认对话框
   （见欠账）—— 宁可不便，也不要一键误伤。

**实测（2026-10-13）：**

- **门禁 12 步 / 16 项全绿，用时 42 s**（新增 `save_check` 0.6 s）；指纹 `19d42d358f8d5495…`
  与生成统计 18 / 7 / 5163 **均不变**（本批只加了一个 `spawn_id` 赋值，不消耗 RNG、不改生成顺序）；
  `perf_probe` 仍是 1 条 WARN（常态）。
- 自检：`save_check` **137**（新）、`encounter_check` 117、`hud_check` 68、`input_check` 135、
  `settlement_check` 104、`economy_check` 48，全部通过。
- **真机端到端探针**（临时脚本，验完即删：真 `Main.tscn` + 真生成的地图，18 定居点 / 14 支部队）：
  存档 **6480 字节**；写 → 回读 → 落地 `ok=true`、**0 条警告**；把世界改脏（金 888→1、士气 66→5、
  那支部队 41→3 人）之后读档，金 / 士气 / 日 / 坐标（x 300.25 / z 410.50）/ 那支部队（41 人）**全部回到存档值**；
  冷却按**当前实例 id** 重建（1 条）；同一份档连读两次都成立。
- 相对 4c：+2 个 `.gd` / **+1052 行**（86 个 `.gd` / 17636 行；tools/ 侧 +548 行 = 新增的 `save_check.gd`），
  另补 3 个 4c 漏提交的 `.gd.uid`（那批 `--import` 生成的，本次一并入库）。

**本批踩到的坑（都已修）：**

1. **自检的假世界把 `ctx.host` 设成 `get_root()` 直接编译不过** —— `WorldContext.host` 的类型是 `Node3D`，
   而 `SceneTree.root` 是 `Window`。教训：假世界的字段必须**照着真实类型**造，编不过反而是好事（早暴露）；
   读档用不到 `host`，去掉即可。
2. **`JSON.parse_string` 失败时会 `ERR_PRINT`** —— 门禁对 `ERROR:` 零容忍，所以「故意写坏一个存档」这条自检
   会把门禁搞红。改用实例版 `JSON.new().parse()`：不打印，而且能拿到**行号 + 原因**，正好写进给玩家看的提示。
3. **重写 `tools/run_checks.ps1` 时把 BOM 写成了双 BOM**（`EF BB BF EF BB BF`）：`UTF8.GetString()` **不剥** BOM，
   用 `UTF8Encoding($true)` 写回就再加一个。后果很阴 —— PowerShell 把第一行注释当成命令名报
   `The term '#' is not recognized`，但**脚本仍然跑完、门禁仍然全绿**，只看退出码发现不了。
   修法：写回前 `TrimStart([char]0xFEFF)`，写回后用字节核对「首三字节 = EF BB BF」。
4. **自检数据自己写错**：把「志愿者 2」放在**城堡**上（城堡 `volunteers_cap == 0`），钳位把 2 变成 0，
   于是 3 条断言红（含「干净存档零警告」）。**钳位是对的，错的是测试数据** —— 这反过来证明了钳位真的在钳。
5. **士气预钳制一开始只做在读档侧**：`_clamp_warn` 已经保证「坏值不漏进新状态」，但 `add_morale` 本身仍是
   `clampi(morale + delta, 0, 100)`。自检第 4 节点名要求「300 读进来 → 100，再减 5 必须到 **95**」，
   才逼出对 `add_morale` 本身的预钳制（02 §3.4.1 的原版写法防的就是这一类坏值）。

**本批欠账（记在账上，不装作没有）：**

- **读档没有二次确认**：`F9` 直接覆盖当前进度（4d 的显式欠账，第五轮候选）。
- 只有**一个快速槽**，没有多槽位 / 存档列表 / 自动存档 UI。
- 读档后**不检查落点是否在水里或城墙里**：位置来自同一张地图上的合法历史位置，生成期保证出生点合法；
  真要做「跨版本迁移」就必须补这一步。
- 读档要重建整张地图（6~7 秒），**没有增量读档**。
- 存档不含 AI 内部计时与 RNG 内部状态：读档后强盗的游荡方向会重来（刻意，见取舍 4）。

---

## 十一、第五轮变更记录（音频总线 / 合成热点 / PCM 缓存）

> 第五轮要解决的是音频从「能响」到「能调、能验、不卡」这三件事：
> **5a 总线**（谁听谁的、怎么临时让路）、**5b 合成热点**（28 个音色生成时最贵的那几处）、
> **5c PCM 缓存**（冷启动不必每次重新合成）。
> 外部设计文档（骑砍 / 原版）在这里只提供「该有什么」的清单，具体数值一律按本工程实测来定，不照搬。

### 11.1 5a 音频总线（`default_bus_layout.tres` + `AudioBus`）

**问题（缺陷 G4「无音频总线」）**：改动前全仓库只有 `Sfx.gd` 里一处 `bus = "Master"`、零 `AudioServer`
调用 —— 28 个音效与两首 BGM 全挤在 Master 上，只能靠「每条音各自的 `volume_db`」分别调，于是有两个实际后果：

1. **总音量管不住音乐**：`AudioConfig.master_db` 只逐声叠在音效上，BGM 完全不受它影响 ——
   把总音量拉到静音，背景音乐照样响。
2. **没有「让路」的手段**：号角 / 开战 / 结算这类**扇子音**想压住正在播的音乐时，只能去改每条 BGM
   播放器的音量，还得记住原值再改回来。

**方案**：三条总线 `Master → Music / Sfx`（`default_bus_layout.tres` 交给引擎自己
`generate_bus_layout()` 落盘，不手写 `.tres` —— 写错格式会让引擎在启动时打 `ERROR`，而门禁对 `ERROR` 零容忍），
新增 `scripts/audio/AudioBus.gd` 作为**唯一写入口**：

| 事项 | 改动前 | 改动后 |
|---|---|---|
| 总音量 `master_db` | 逐声叠在 `Sfx._final_db()` 里（**音乐不受影响**） | 写在 **Master 总线**上，音效与音乐一起听令 |
| 音乐音量 `bgm_db` | 逐条叠在 `Bgm` 播放器的 `volume_db` 上 | 写在 **Music 总线**上；播放器只留单曲偏移 × 淡入增益 |
| 分类音量（combat / parry / move / voice / ui） | 逐声相加 | **不动**：那五档是「音色设计」的一部分，不是混音台的推子 |
| 让路（duck） | 无 | `AudioBus.duck(db, sec)` 临时压低 Music 总线，`SceneTree` 定时器到点自动恢复 |
| 找不到总线时 | —— | `AudioBus.route()` 退 **Master**：降级而不是静音整场（老检出删了 `.tres` 也不会炸） |

**两个刻意的设计决定：**

- **扇子音名单写在代码里**（`Sfx.FANFARE` = `order` / `battle_start` / `result_win` / `result_lose`），
  只有深度与时长是配置项（`AudioConfig.fanfare_duck_db = -5.0` dB、`fanfare_duck_time = 1.6` s）：
  「谁是扇子音」属于混音行为，不该是玩家在设置里能改的东西。
- **静音走增益淡出，不用总线静音**：`Sfx.set_muted()` 保持原实现（逐播放器淡到 `SILENT_GAIN`），
  刻意**不**调 `set_bus_mute()` —— 总线静音是硬切，玩家按 M 想听到的是「淡下去」。
  自检把这条写成断言，防止以后有人「顺手优化」成总线静音。

**改动文件：**

| 文件 | 改动 |
|---|---|
| `default_bus_layout.tres` | **新**：引擎生成，Master → Music / Sfx |
| `scripts/audio/AudioBus.gd` | **新**（107 行）：总线名 / `apply()` / `route()` / `master_db()` / `music_db()` / `sfx_db()` / `duck()` / `stats()` / `reset()` |
| `scripts/audio/Sfx.gd` | 改（234 → 273 行）：池播放器挂 Sfx 总线、`_duck_for_fanfare()`、`set_master_db()` 立刻写总线、`_final_db()` 去掉 `master_db`、新增 `volume_db_of()` / `player_bus()` / `bank_size()` 三个自检访问器 |
| `scripts/audio/Bgm.gd` | 改（168 → 193 行）：播放器挂 Music 总线、`_base_db()` 去掉 `bgm_db`、`setup()` 里 `AudioBus.apply()`、新增 `bus_of()` / `db_of()` 自检访问器 |
| `scripts/audio/AudioConfig.gd` | 改（74 → 80 行）：`master_db` / `bgm_db` 注释改成「写在总线上」、新增 `fanfare_duck_db` / `fanfare_duck_time` |
| `tools/audio_check.gd` | **新**（187 行 / **46** 项断言） |
| `tools/run_checks.ps1` | 改（282 → 308 行）：新增 **6d) audio_check** 与 **9b) bgm_check**（12 步 → **14 步**） |
| `project.godot` | 改（−1 行）：编辑器顺手删掉的一处空行（与音频无关，同批入库） |

**实测（2026-10-13）：**

- **门禁 14 步全绿，用时 43.4 s**（新增 `audio_check` 1.5 s + `bgm_check` 7.2 s）；
  指纹 `19d42d358f8d5495…` 与生成统计（定居点 18 / 桥梁 7 / 植被 5163）**均不变** ——
  本批不碰 RNG、不碰生成顺序。
- 自检断言数：`audio_check` **46**（新）、`save_check` 137、`input_check` 135、`encounter_check` 117、
  `settlement_check` 104、`hud_check` 68、`economy_check` 48，全部通过；
  `sfx_battle_check` / `sfx_map_check` / `bgm_check` 三条联调仍是 PASS（音色触发路径没动）。
- `audio_check` 覆盖的是「读真对象」而不是「读常量」：布局是否真被引擎加载（`bus_count == 3`、
  `Music`/`Sfx` 的 `send` 指向 Master）、`route()` 的降级、**总音量只算一次**
  （`volume_db_of("hit_light") == combat_db + (−1.0)`，播放器里不再含 `master_db`）、
  BGM 播放器只留单曲偏移（`db_of("map") == bgm_map_db`）、duck 的触发 / 拒绝 / 到点恢复、
  静音期间 `play()` 既不计数也不压低音乐。

**本批踩到的坑：**

1. **同一个仓库里两种行尾**：`Sfx.gd` 是 CRLF，而 `Bgm.gd` / `AudioConfig.gd` / `SfxSynth.gd` 是 LF。
   用「带 `\r\n` 的字面量」批量打补丁时，同一个模式在一半文件里必然匹配 0 次 ——
   报错反而是好事，真正危险的是**不校验就 `.Replace()`**（静默不生效，改完像是做了事）。
2. **`class_name AudioBus` 不在全局类缓存里**：新脚本必须先 `--import` 一次，否则引用它的脚本一律
   `Parse Error: Identifier "AudioBus" not declared in the current scope`。
3. **自检里没有 `Main`，就没人调 `Bgm.tick()`**：第一次跑 `audio_check` 时「大地图曲已起播」120 帧都不过 ——
   淡入淡出是靠 `Main._process` 每帧驱动 `Bgm.tick(delta)` 的。自检必须**自己驱动**，
   这与 `bgm_check` 走真主场景的路线正好互补（一个验对象、一个验流程）。
4. **双 BOM 又踩了一次**（第一次是 4d 写 `run_checks.ps1`，见 §10.9 坑 3）：`UTF8.GetString()` 不剥 BOM，
   写回时 `UTF8Encoding($true)` 再加一个 → `EF BB BF EF BB BF`。症状一如既往地阴：PowerShell 报
   `The term '#' is not recognized`，但**门禁照样全绿**、退出码也是 0。修法固定为
   「写回前循环剥掉所有前导 `U+FEFF`，写回后核对首三字节 = `EF BB BF`」。

**本批欠账：**

- 只做了**路由**，没挂任何**效果器**：总线上没有 limiter / compressor / reverb。
  28 个音同时响时仍靠合成期的 `_soft_clip()` 削顶，总线侧动态控制等真需要时再上。
- 没有**音量设置界面**：`master_db` / `bgm_db` / 分类音量目前只有 API
  （`Sfx.set_master_db()` 至今没有 UI 调用方），玩家能用的只有 M 静音。
- `duck()` **不做嵌套计数**：两次 duck 重叠时，先到点的那个会提前恢复
  （当前扇子音间隔远大于 1.6 s，听不出来）。
- `AudioBus.apply()` 把 `bgm_db` 与 duck 深度**相加后**写进 Music 总线，没有独立的 duck 总线；
  若有别的模块再往 Music 上写 `volume_db`，两边会互相覆盖（约定：Music 总线只由 `AudioBus` 写）。
- 5b / 5c 待办：`SfxSynth._biquad()` 的扫频分支**每个采样分配一个 `Array`**（33 处调用里约 28 处走扫频）、
  `_env()` 的逐采样 `exp(pow())`，以及尚未开始的 PCM 缓存。
### 11.2 5b 合成热点（先装体检器，再动手改；音色逐字节不变）

**做法：先测，再改。** `SfxSynth.gd` 里加了 `prof_on` 开关与 `prof_add()` / `prof_op()`：
按「外层算子」记调用次数 / 采样数 / 耗时；逐采样算子（`_sin` / `_env`）**不进计时器**，
只由外层**推导**次数 —— 在它们内部插 `Time.get_ticks_usec()` 的话，计时开销会盖过被测代码本身。
`sfx_tool.gd -- --profile` 打印两张表。动手前那一版实测（合成 1529 ms / 34.7 万采样）：

| 外层算子 | 次数 | 采样 | ms | µs/采样 |
|---|---|---|---|---|
| `_metal` | 23 | 236818 | 414.7 | 1.751 |
| `_brass` | 6 | 100330 | 265.3 | 2.644 |
| `_biquad(扫频)` | 26 | 267027 | 222.4 | 0.833 |
| `_tone` | 26 | 285770 | 137.2 | 0.480 |
| `_noise_env` | 32 | 284447 | 80.3 | 0.282 |
| `_wav(归一化+编码)` | 28 | 347290 | 36.7 | 0.106 |
| `_mix` / `_mix_at` / `_biquad(定频)` / `_soft_clip` / `_blank` | 150 | 159.4 万 | 29.7 | — |
| **合计** | | | **1529** | |

推导出的逐采样算子次数：**`_sin` 280 万次**、`_env` 67.0 万次（其中 47.2 万次 `curve == 1.0`）、
滤波器系数 `cos`/`sin` 53.4 万次、`encode_s16` 34.7 万次。
**结论：热点不在数学上，在 GDScript 的「每次函数调用 / 每次装箱 / 每次临时分配」上。**

**三条改动（都不动算法，所以 PCM 必须逐字节不变）：**

| # | 改动 | 省下 |
|---|---|---|
| 1 | `_env()`：`curve == 1.0` 时跳过 `pow(x, 1.0)`（IEEE 规定结果就是 `x`，等价替换） | 47.2 万次 `pow`，实测只省几毫秒 —— `pow` 比预想便宜，照实记账 |
| 2 | `_biquad()` 扫频分支把 `_coef()` 的算式**内联**进循环 | 26.7 万次函数调用 + **26.7 万个 5 元素 `Array` 分配**：222 → 119 ms |
| 3 | `_metal()` / `_brass()` 内层循环**内联 `_sin()` 的查表** | 约 210 万次函数调用：`_metal` 415 → 185 ms、`_brass` 265 → 164 ms |

**结果（同一 `--profile` 口径）：合成 1529 → 1097 ms（−28%）；默认模式 1083~1093 ms。**
音色：`sfx_tool.gd -- --check` 报 **28 个音色 / 347290 采样与基线逐字节一致**。
按 id 看，收益集中在两类音色：铜管类（`roar` / `battle_start` / `order` / `result_win` / `result_lose`）
与金属类（`parry` / `parry_reflect` / `poise_break`）。

### 11.3 5b 的验证手段与门禁接入（音色指纹）

「音色不变」如果只是嘴上说，等于没验。加了 `tools/sfx_pcm.json` 基线 + `sfx_tool.gd` 的三个模式：

| 模式 | 作用 |
|---|---|
| `-- --hash` | 打印 28 个音色的 PCM SHA-256（前 16 位）与合计 |
| `-- --check` | 与 `tools/sfx_pcm.json` 逐字节比对（门禁用；不一致时点名是哪几个音色） |
| `-- --write-baseline` | 有意改音色后更新基线（与生成指纹 `--write-baseline` 同一套路） |

哈希内容 = `RATE` + 每个音色的（id 长度 / PCM 字节数 / id / PCM），带上 id 与长度是为了
「两个音色互换」这种错误也能被抓到。门禁新增 **9c) sfx_pcm_check**（15 步），
`run_checks.ps1` 只认「退出码 0 + 打印 PASS」。

**本批踩到的坑（都值得记）：**

1. **`PackedFloat32Array` 里的相位是「写回即截断到 float32」的**：原码 `ph[h] += f / RATE` 之后，
   是拿**截断过的** `ph[h]` 去查表。我第一版内联把没截断的中间值（double）直接送进查表，
   于是 4 个铜管音色（`battle_start` / `order` / `result_win` / `roar`）的 PCM 全变了 ——
   音色指纹当场点名（合计 `87aecb5d…` ≠ 基线 `55bd4464…`）。教训：**逐字节断言比"应该没变"可靠得多**。
2. **`floor()` 的返回类型是 Variant**：`var sx := p - floor(p)` 直接编译不过
   （`Cannot infer the type of "sx"`），必须写 `var sx: float = p - floor(p)` ——
   `_sin()` 原本就是这么写的，是我抄漏了注解。
3. **PowerShell 的 `+` 比 `,` 结合更紧**：`@($T2+"a", $T2+"b")` 得到的**不是一个两元素数组**，
   而是 `$T2 + ("a", $T2) + "b"` 拼成的一个字符串 —— 用变量拼多行补丁时会静默拼成一整行，
   然后「匹配 0 次」。多行数组必须给每个元素加括号：`@(($T2+"a"), ($T2+"b"))`。
4. 体检器的字符串键在 `prof_op()` 里被 `sort_custom` 的 lambda 用到一次（`Array.sort_custom`）——
   在 Godot 4.7 上没问题，但**排序 lambda 不能捕获外部局部变量**（用 `self` 成员或常量）。

**本批欠账：**

- 只改了 3 处。`_tone`（136 ms）与 `_noise_env`（80 ms）没动：把 `_sin` 也内联进去还能再省 ~25 ms，
  但代码重复的代价已经超过收益 —— 5c 的 PCM 缓存会让热路径彻底离开合成。
- 体检器的 `if prof_on:` 判断留在热路径上（每次外层调用判一次，关闭时开销可测为 0）。
  保留它是为了让 5c 之后能随时复测，但确实是「生产代码里带着调试开关」。
- `_sin()` 的查表算式现在有**三份拷贝**（`_sin()` / `_metal()` / `_brass()`），只靠注释互相提醒。
  改查表（例如换 `TAB_N`）必须三处同步 —— 已写进注释，但这是实打实的维护负担。

### 11.4 5c 音色 PCM 缓存（冷启动 1.3 秒 → 9 毫秒，音色逐字节不变）

**动机**：28 种音色全部在代码里合成（这是刻意的美术选择：不加载任何外部音频文件），代价是每次开游戏
都要花 1.1~1.3 秒合成 34.7 万采样。这部分是**纯计算、结果确定**，天生适合缓存 —— 但只有「结果逐字节
可复现」才敢缓存，5b 顺手做的音色指纹（§11.3）正好成了那个保险。

`scripts/audio/SfxCache.gd` 把 28 个音色的 16bit PCM 写进 `user://sfx_cache/`（约 679 KB），
下次启动直接读回来建 `AudioStreamWAV`：

| | 冷启动 | 热启动（命中缓存） |
|---|---|---|
| 合成 + 归一化 + 编码 | 1.09~1.35 秒 | — |
| 读盘 + 全量 SHA-256 校验 + 建流 | — | **5 毫秒** |
| `Sfx.setup()` 整体（含建播放池） | 1.35 秒 | **9 毫秒** |
| 门禁整体 | 41.3 秒（15 步时） | **36.8 秒（16 步）** |

**四条设计决定（每条都有代价权衡）：**

1. **整体命中 / 整体丢弃**，绝不「缺哪个补哪个」。噪声音色共用同一条 RNG 流（`build(id, rng)` 按
   `ids()` 顺序消耗随机数），跳过任何一个都会让后面所有音色的噪声变样 —— 「只补一个」看着聪明，
   实际会悄悄改掉一半音色。
2. **键 = 格式版本 `FORMAT` + `RATE` + `TAB_N` + `SPECS` + `ids()` 顺序 + `SfxSynth.gd` 的文件字节指纹**。
   最后一条是关键：改了合成代码却忘了 bump `FORMAT`，老缓存也会自动失效。代价是**改注释也会让缓存失效**
   （一次性多花 1.3 秒，换「绝不会用错老缓存」，值）。导出后源码被剥离时退化成只靠 `FORMAT`，已写进注释；
   开发态还有第三道保险 —— 自检会拿缓存指纹去比 `tools/sfx_pcm.json`。
3. **坏缓存是正常情况**：文件缺一个、被改一字节、被截断、JSON 坏了、键不符 —— 一律静默丢弃走冷启动，
   `load_bank()` 只返回空字典。**绝不用 `push_error`**：门禁对 `ERROR:` 零容忍，而且坏缓存不该在玩家
   日志里刷红字。
4. **播放期的音高抖动换成独立 RNG**（`Sfx._jit`）。合成消耗多少个随机数是实现细节（命中缓存时一个都
   不消耗），继续和 `_rng` 共用的话，同一份代码在「冷启动」和「命中缓存」两种开局下会得到不同的抖动
   序列 —— 听感不该取决于启动快慢。

**验证**（`tools/audio_cache_check.gd`，门禁 **9d) audio_cache_check**，**77 项断言 / 1.9 秒**）：
键的敏感性（格式版本 / 采样率 / 查表长度 / SPECS / 源码指纹，改任一项键就变）、冷启动落盘自洽、
**热启动逐字节一致**（28/28 个音色的 PCM 与流参数与冷启动完全相同）、与仓库基线 `tools/sfx_pcm.json`
一致、六种坏缓存各自未命中并给出原因、坏掉后自愈重合成仍与冷启动一致、`Sfx.setup()` 命中路径的音色库
与冷启动一致、关掉缓存时完全不碰磁盘。

**这一批踩到的两个坑：**

1. **自检脚本一直在悄悄依赖「`Sfx.setup()` 会让出帧」**。`--script` 模式下 `_initialize()` 早于
   SceneTree 的第一次迭代，此时把 host 加进 root 还**不算进树**；以前冷启动合成会让出几十帧，
   所以 `Bgm.tick()` 里的 `play()` 从来没出过事。缓存把这 1.3 秒省掉之后，`Sfx.setup()` 一次都不
   `await`，`audio_check` 立刻报 `ERROR: Playback can only happen when a node is inside the scene tree`
   —— 门禁的红不是缓存错了，是**检查脚本的隐式依赖被显式化了**。修法：自检里加一句显式 `await process_frame`
   （代码注释写清了缘由）。教训：**「碰巧能跑」的测试会在性能优化后立刻翻车**，让出一帧要写出来。
2. **`HashingContext.update()` 收到空数组会打 `ERROR: Condition "len == 0"` 并返回 FAILED**。
   缓存要把「PCM 字节」喂进哈希，空数组在坏缓存路径上是能构造出来的 —— 已统一走带守卫的 `SfxCache._upd()`，
   空数组直接跳过（哈希值不变）。

顺手做的去重：`tools/sfx_tool.gd` 原来自己写了一遍「RATE + 每音色 [id 长度, PCM 长度, id, PCM]」的哈希配方，
现在改成调 `SfxCache.total_of()` —— 两处各写一份的话，一旦悄悄漂移，「缓存指纹 == 仓库基线」这条断言会
莫名其妙地失灵。指纹值不变（`55bd4464d69ebf8e…`）。

**本批欠账：**

- 缓存只在 `user://`，**不进仓库**（一台机器一份就够，也避免把 679 KB 二进制塞进 git）。
  换机器 / 清 user 数据后第一次启动仍要 1.3 秒。
- 没有做「缓存预热进打包版本」（把 PCM 当资源随包发布）：那会引入一个二进制音频资产，与「音色全在代码里」
  的设定冲突，暂不采纳。
- `load_bank()` 每次全量 SHA-256（679 KB ≈ 2~3 毫秒）。想过只校验长度 + 抽样哈希，但 3 毫秒换「绝不读到
  坏数据」很划算，不做。
- 缓存没有上限 / 淘汰策略：键一变就是整份重写，旧文件被覆盖。目前只有一份，没有增长风险。
- **改合成代码必须 bump `FORMAT`**：开发态会被源码指纹与基线挡住，导出后只剩 `FORMAT` 一道 —— 这条规则
  写进了 `SfxCache.gd` 的注释与本节，但没有机制强制（GDScript 拿不到自身源码的语义指纹）。

---

## 十二、第六轮变更记录（规模扩展：植被 / 地形 / 寻路）

### 12.1 本批（6a）交付：先装体检器 —— 规模热点探针与改前基线

第六轮 C 节（§四.C）整段都是**估算**：「实例发射 5~15×」「单遍筛选 −60%~70%」「A* 本体 2~4×」
「地形单块 3~6 ms」。这一轮要动的正好是这些路径，而它们**以前一个都没量过** —— 所以本批不改任何
行为，只做一件事：把三条主线在**真实地图**上量出来，做成与 `gen_fingerprint` / `perf_probe`
同级的门禁项（`tools/scale_probe.gd` + `tools/scale_baseline.json`，门禁 **7b** 步）。

**测法与判据（为什么不是「跑一遍看看」）：**

- 用真实世界：实例化 `Main.tscn`、固定 `map_seed`、关音频与进程，等 `gen_done` —— 与 `gen_fingerprint.gd`
  同一入口，所以量到的就是玩家会遇到的规模（1024 m 图 / 18 定居点 / 5163 植被实例）。
- **结构量精确比对**（实例数 / 区块数 / 逐类计数 / 实例变换指纹 / 地形顶点数 / 位置与索引指纹 /
  每对的路径点数与展开节点数）：这些是确定性量，差一个就是错。它们同时是后面三批改动的**契约** ——
  6c / 6d 不许动它们；6b 若接受布局变化，则必须显式更新基线。
- **耗时只做上界比对**（基线 × 1.6 记 WARN，× 2.5 判失败），与 `perf_probe` 同一思路：机器抖动不该误报，
  但「悄悄变慢 60%」必须留痕。
- 探针**先自检**：植被重跑一次，逐类计数必须与主场景里那份一致 —— 探针自己不可信的话，后面所有数字都不作数。

**改前基线（2026-10-14，`--fixed-fps 60`，本机热缓存；种子 20250929）：**

| 项 | 实测 | 备注 |
|---|---|---|
| 植被 实例 / 区块 | 5163 / **212** | 落进 8×8 区块里非空的那些（不是 5×64 都非空） |
| 植被 `build()` 合计 | **911~917 ms** | 整图生成 3.72 s 的约 25% |
| 　├ 筛选段 | **909~915 ms** | 5 个类型各扫一遍 7 m 网格 |
| 　└ 发射段 | **2.2 ms** | ← 见下面的「证伪」 |
| 地形 LOD0 | 中位 **4.74 ms** / 最大 6.72 ms | 64 块全量 306 ms |
| 地形 LOD1 / 2 / 3 | 1.30 / 0.38 / 0.14 ms | 16 块抽样 |
| 采样原语 | `height_at` 0.80 µs / `normal_at` 3.29 µs | 建块每顶点现值 4.09 µs |
| A* 细栅格（12 对定居点） | 合计 38.1 ms / 单次最大 14.7 ms / 展开 1143 | |
| A* 粗栅格（同 12 对） | 合计 94.8 ms / 单次最大 **68.9 ms** / 展开 5184 | 单次 68.9 ms ≈ 4 帧 |

**结论 1（证伪 C 节的一条估算）**：C 节写「实例发射改 `multimesh_set_buffer` → 估算 5~15×」。
实测发射段只有 **2.2 ms / 917 ms（0.24%）** —— 就算优化到 0 也看不见。真正贵的是**筛选段 909 ms**：
5 个类型各扫一遍 7 m 网格，而「水面 / 河道 / 渡口 / 桥面 / 高度 / 坡度 / 定居点半径」这 7 项判定与类型
**完全无关**，被重复算了 5 遍。→ 6b 的关键不是换写法，而是**敢不敢改布局语义**。

**结论 2（证实，并给出可测预测）**：地形 LOD0 单块 4.74 ms 中位 / 6.72 ms 最大，与 C 节「3~6 ms」相符；
每顶点 4.09 µs 里有 **3.29 µs 花在 `normal_at`（= 4 次 `height_at`）**。→「法线改本地高度差分」的
可测预测是单顶点 **4.09 → 0.80 µs（−80%）**、LOD0 单块 4.74 → 约 1 ms。6c 改完必须回到本表对账。

**结论 3（把「优化项」升格为「必须项」）**：A* 粗栅格**单次最坏 68.9 ms（展开 3913 格）** ——
这不是「有点慢」，是一次调用吃掉 4 帧多；细栅格最坏 14.7 ms 也贴着 1 帧。→ C 节的
「全局寻路请求队列 + 每帧预算」从优化项变成必须项（AI 部队的随机游荡点落在长路径上就会触发）。

**6b 的显式决定（本项目第一次遇到「优化会改变世界」）**：C 节 ② 的「单遍筛选」能省掉 4/5 的公共判定
（估计 −700 ms，整图生成 3.72 s → 约 3.0 s，−19%），代价是**植被布局改变** —— `gen_fingerprint.json`
的植被项、统计里的 5163、以及本探针的 `veg_xform_hash` 全部要重新基线化，玩家存档里的地图也跟着变。
桶尺寸 128 m → 256 m 则**不动布局**（实例集合与变换不变，只是打包方式变），收益在 draw call 与剔除
（headless 测不到），代价是 `veg_chunks` 与 `veg_xform_hash` 要更新、远处剔除粒度变粗。
**这一条按路线图自己的要求需显式决定，未决前不动植被代码。**

**顺手做的**：`Pathfinder.last_expanded`（只写不读的探针字段）—— 6d 要证明「改动只影响速度、
不影响搜索结果」，靠的就是它：展开节点数与路径点数必须逐对不变。

**门禁接入**：7b) 步（16 → **17 步**；断言项数 19~20 → **20~21**，随 `perf_probe` / `scale_probe` 的 WARN 提示行浮动。热 42.2 s / 冷 43.2 s）。
结构量必须精确一致；耗时超 1.6× 记 WARN、超 2.5× 判失败。

**本批踩到的坑（两条，都是工具链的）：**

1. **基线一过 JSON 就变类型**：`JSON.stringify` 写出的 `5163` 读回来是 **float** `5163.0`，字典键序也可能变。
   结构量比对若用 `str()` 直接对，8 个整数项会全报「不符」。→ 统一走按数值递归的 `_same()`
   （数字比数值、数组逐元素、字典逐键）。
2. **`run_checks.ps1` 的 BOM 会被写重**：用 `UTF8Encoding($true)` 写回前必须先剥掉读出来的 U+FEFF，
   否则文件开头变成**两个 BOM**，PowerShell 会把 `﻿#` 当命令名，报
   `The term '# ' is not recognized as the name of a cmdlet`。→ 写入前 `TrimStart([char]0xFEFF)`。

---

### 12.2 本批（6c）交付：地形建块 3.06×（顶点位置与索引逐位不变）

6a 的探针把地形的账算清楚了：LOD0 单块中位 4.75 ms、每顶点 4.09 µs，其中 **3.17 µs** 花在
`Heightmap.normal_at()` —— 它内部是 4 次 `height_at`（±cell 中心差分）。本批按 C 节的四条逐条落地：

1. **`_apply_lod` 把「缓存命中」提到预算判断之前**：换级本该是免费的（网格早在内存里），原来缓存命中也被
   `_rebuild_budget` 挡着 —— 相机一动就要等好几帧才换级（远处先糊、近处才清）。现在只有**新建**吃预算。
2. **`_update_lods` 改成按距离从近到远处理**：每 0.25 s 只有 2 次新建机会，原来按数组（行）顺序发，
   远处块会把机会抢走；现在先算出「想换到哪一级」，再按距离排序后依次处理。
3. **法线改用已算好的高度格做中心差分**：每块先把（含一圈外环的）高度算进 `PackedFloat64Array`，
   顶点与法线都从格点读 —— 每顶点 1 次采样 + 4 次数组读，代替原来的 5 次采样。外环是为了让**边界顶点
   也能用中心差分**，否则块与块之间会出现光照缝。
4. **LOD2/3 关阴影投射**（远处地形的阴影本来也糊成一团）。

**实测（同一台机器，探针 6c 前 / 后）：**

| 项 | 6c 前 | 6c 后 | 倍数 |
|---|---|---|---|
| LOD0 单块中位 | 4.748 ms | 1.553 ms | **3.06×** |
| LOD0 单块最大 | 6.812 ms | 1.975 ms | 3.45× |
| LOD0 64 块合计 | 310.7 ms | 95.9 ms | 3.24× |
| LOD1 中位 | 1.212 ms | 0.258 ms | 4.70× |
| LOD2 中位 | 0.384 ms | 0.089 ms | 4.31× |
| LOD3 中位 | 0.127 ms | 0.040 ms | 3.18× |

整图生成 3.72 s → 3.61 s（地形只占生成的一小段：64 块 LOD3 + 焦点附近的 LOD0/1）。

**几何不变性（探针断言，不是「看着一样」）**：`terrain_pos_hash`（`5a2e59665239f171`）与
`terrain_idx_hash` **逐位不变** —— 顶点位置与三角形拓扑一个 bit 都没动。**只有法线变了**
（`terrain_norm_hash` `b57fe6faf9372a93` → `a712dd9038c7b2ef`）：差分步长从固定的高度图 cell
（本工程 `heightmap_res = 513` / 1024 m → **2 m**）换成了本级网格的步长（4 / 8 / 16 / 32 m）。
这是本批唯一有视觉含义的取舍 —— 法线不再「过采样」细于本级网格的起伏：近处略微平滑、远处明显更平
（远处本来也看不出，且 LOD2/3 已关阴影）。想连法线都逐位不变就得按 2 m 建格
（LOD0 一块 67×67 = 4489 次采样 ≈ 3.4 ms，比现在慢一倍多），不划算。法线方向由构造保证仍朝上
（y 分量恒为 `2s > 0`），不存在翻面风险。

**与 §12.1 预估对账**：预估是「单顶点 4.09 → 0.80 µs（−80%）、LOD0 单块 4.74 → 约 1 ms」。
实测单块 1.55 ms（3.06×，−67%）：采样那一项确实到了 −80%，但建块还有**与采样无关的固定成本**
（1089 顶点 + 512 裙边顶点的数组写入、`duplicate()`、`add_surface_from_arrays()`）—— 这部分一分没省，
所以整体倍数（3.06×）低于采样倍数（约 5×）。**预估值偏乐观，记在这里。**

**顺手修的探针稳定性问题（这条比数字更重要）**：LOD1~3（0.04~0.5 ms）与植被发射段（2~4 ms）
这种「小数字」单次测量会被分配器状态与定时器粒度带得上下翻倍 —— 实测同一份代码写完基线后
下一次跑就差 2~3 倍，门禁直接红。现在这两类都改成**每项跑 3 次取中位**；LOD0（64 块全量）靠
「合计」这个统计量本身已经稳（±2%），保持单次。改完连跑三次：三次全 PASS、0 条 WARN。

---

### 12.3 本批（6d 前半）交付：A* 热点内联 1.20~1.45×（搜索结果逐对不变）

C 节给 A* 开的是「本体 2~4×」。本批先把**不改变搜索结果**的那一半做完：把每邻格都要付的脚本层开销
内联掉 —— `nav.is_blocked()`（对角时 3 次方法调用）、`nav.speed[]` / `nav.cell` / `nav.res` 的属性取用、
`_heuristic()` 的 `Vector2i` 构造，全部换成局部变量与整数运算。

**证据（这次是契约断言救了我一次）**：探针的「每对路径点数 + 展开节点数逐对不变」是硬断言。
第一版内联我把禁切角的两个正交邻格写成了 `(cx+dx, cz+dz)`（对角格本身）而不是 `(cx+dx, cz)` 与
`(cx, cz+dz)` —— 探针立刻报 `path_fine_expanded 1143 → 1135`、`coarse 5184 → 4986`。
**这就是 6a 花力气做契约断言的意义**：一个看着毫无问题的坐标笔误，靠肉眼和「跑一遍没崩」是抓不到的。
改回正确坐标后：展开数 1143 / 5184 与路径点数**逐对完全一致**，只剩耗时变化。

**实测（探针，6d 前 → 6d 后）：**

| 项 | 6d 前 | 6d 后 | 倍数 |
|---|---|---|---|
| fine 12 对合计 | 38.5 ms | 32.0 ms | 1.20× |
| fine 单次最大 | 14.7 ms | 13.0 ms | 1.13× |
| coarse 12 对合计 | 89.4~94.8 ms | 61.7 ms | 1.45~1.54× |
| coarse 单次最大 | **68.9 ms** | **45.8 ms** | 1.50× |

**又是一条被实测否掉的估算**：C 节的「A* 本体 2~4×」偏乐观。内联掉的是「判定与启发」这层，
而 A* 的主要时间其实花在**自建堆的 push/pop 与 `PackedFloat32Array`/`PackedInt32Array` 的读写**上
（细栅格一次搜索要展开上千节点、每节点 8 邻格各 1~2 次写入）。要再快就得动数据结构，不是内联能解决的。

**6d 后半（请求队列 + 每帧预算）仍然是必须项，依据更硬了**：`AIParty.gd` 用的正是
`data.path_coarse.find_path()`（每支 AI 部队的游荡/行军都走粗栅格），而粗栅格单次最坏 **45.8 ms
≈ 2.75 帧（60 FPS）**。§12.1 结论 3 里「把优化项升格为必须项」成立，只是数字从 68.9 ms 降到 45.8 ms。
10 部队规模下 45.8 ms 的偶发卡顿仍然看得出来，队列要留到下一批做（改 `find_path` 为请求式接口，
每帧给寻路一个时间预算，超预算的请求排队到后续帧）。

---

### 12.4 本批（6b 路线 A）交付：植被筛选段 2.06×（**布局逐位不变**）

C 节给植被开的两条路里，「单遍筛选」会改变植被布局（路线图自己要求显式决定），所以本批走的是
**不改判定结果**的那条：把筛选循环里的脚本层开销摊平。这一段每次生成要跑 5 遍
（5 个类型各扫一遍 7 m 网格 = 5 × 85800 格），原来每格都要付三笔账：

| 原写法 | 每格代价 | 改成 |
|---|---|---|
| `nav.at(nav.ci(p.x), nav.ci(p.y))` | 3 次方法调用 + 各自的 `clampi`/`round` | 局部算术 + 一次 `clampi`（语义逐字照抄 `NavGrid.ci/at`）|
| `nav.water[ci]` / `road` / `ford` / `bridge` | 4 次属性取用 + 索引 | 循环外取一次数组引用 |
| `for s in data.settlements: p.distance_to(s.pos) < s.radius + 7.0` | 每格最多 18 次 Dictionary 取属性 + `sqrt` | 循环外摊平成三个 `PackedFloat64Array`（半径先 +7 再平方），格内只做平方比较 |
| `pow(forest, 1.4)` | 无林区也照算 | `forest == 0` 时直接返回 0（`pow(0, 1.4) ≡ 0`，结果逐位不变）|

**为什么布局能保证不变**：筛选段里唯一的随机性就是每格那**两次** `rng.randf_range(0, CELL)` 抽点
（抖动位置）和通过全部判定后的**一次** `rng.randf()`（密度接受）。三处 rng 调用都留在原位、原顺序、
原次数，其余全是纯计算 —— 所以 rng 序列一字不动，植被布局就不可能变。

**实测（探针，6b 前 → 后）：**

| 项 | 6b 前 | 6b 后 | 倍数 |
|---|---|---|---|
| 植被 `build()` 合计 | 937.5 ms | 454.8~510.4 ms | **1.84~2.06×** |
| 　└ 筛选段 | 935.4 ms | 453.1~508.9 ms | 1.84~2.06× |
| 　└ 发射段 | 2.08 ms | 1.5~1.7 ms | （噪声级，未动）|
| 整图生成 | 3.72 s | 3.55 s | −170 ms |

**布局不变的证据（探针硬断言，逐位比对）**：`veg_instances` **5163**、`veg_chunks` **212**、
`veg_xform_hash` **`df5b0d581cff76f2`** —— 三项与优化前**完全相同**；`gen_fingerprint` 与门禁的
「生成统计 定居点 18 / 桥梁 7 / 植被 5163」也一字未变。也就是说：**这次快了 2 倍，但世界一个比特都没动。**

**又一次和预估对账**：我给这条路线估的是「筛选段 −20~35%」，实测 **−51%** —— 明显好于预估。
原因是最贵的那一项不是我以为的 `nav.ci/at`，而是**定居点距离那 18 次 `distance_to()`**
（Dictionary 取属性 + `sqrt`，每格 5 个类型各来一遍）。这也解释了为什么「单遍筛选」的收益那么大：
它省的正是这段每格重复的公共判定。

**仍然留着的那条路（需显式决定）**：单遍筛选（5 个类型共用一次公共判定 + 一次抽点）能再省掉
约 4/5 的公共判定 —— 按现在的数据估计还能再快 **~300 ms**，代价是**植被布局改变**，
`gen_fingerprint` 植被项、统计 5163、`veg_xform_hash` / `veg_chunks` 全部要重新基线化。
本轮**不做**：整图生成已经从 3.72 s 降到 3.55 s，而它改动的是玩家看得见的地图。
建议与 ④（4096 m 地图）一起做 —— 那时地图尺寸本身就变了，布局本来就要重基线化，等于顺手拿掉这 300 ms。

---

### 12.5 本批（④ 前半）交付：4096 m 地图 / 100 部队的硬编码清单

「换一张更大的地图」听起来是改一个数，实际不是。本批把工程里**所有与地图尺寸、分辨率、部队数量
绑定的假设**清点成一张表（含每条的 4096 m 后果），并按「拦路虎 / 可接受 / 已通用」三档给结论。
本批**只清点，不实施**（实施见第六轮后续）。

**已经通用的部分（不用改）**：`MapConfig.map_size` 是唯一真源，地形分块数
`ceil(map_size / CHUNK_SIZE)`、植被区块、`territory_cell = map_size / (TERR_RES - 1)`、
四个着色器的 `map_size` uniform（`MaterialFactory` / `WaterBuilder` 都用 `cfg.map_size` 覆盖）、
`Pathfinder._heap` 动态增长、`A* max_expand = res²` —— 都是按尺寸推导的，换 4096 自动成立。

**清点表（★ = 4096 m 下的拦路虎）**

| # | 位置 | 现值 | 4096 m 下的后果 | 处理 |
|---|---|---|---|---|
| 1 ★ | `WorldGenPipeline.gd:90-94` `NavGrid.new(257/129/129, …)` | 硬编码**分辨率**，不是按尺寸缩放 | 保持 4 m/格需 1025²（**105 万节点**，A* 最坏从 13 ms 涨到约 200 ms，粗栅格 45.8 → 约 730 ms）；不缩放则细栅格变 16 m/格，部队走路「跳格」 | 改成「按目标格距算分辨率」，并**同时**做 6d 后半的请求队列 + 每帧预算 |
| 2 ★ | `VegetationScatter.gd:28` `const CELL := 7.0` | 采样格距固定 | 格数 85800 → **137 万（16×）**，筛选段 455 ms × 16 ≈ **7.3 s**（这还只是 5 遍里的一遍的量级） | 4096 必须把 6b 里没做的**单遍筛选**做掉，并把 CELL 放到 10~14 m |
| 3 ★ | `CameraRig.gd:39` `cam.far = 5000.0` | 相机远裁剪面 | 4096 m 地图对角线 **5792 m**，站在一角看对角会**直接裁掉地形**（不是变糊，是没有） | 提到 ≥ 6500，或按 `map_size * 1.5` 推导 |
| 4 ★ | `MapConfig.gd:14` `@export_range(129, 1025, 2) heightmap_res` | 上限 1025 | 4096 m 想保持 2 m 间距需要 **2049**，被导出范围**挡住**（编辑器里调不上去） | 上限提到 2049（内存 `2049² × 4 B ≈ 16.8 MB`，可接受） |
| 5 | `TerrainManager.gd:17` `CHUNK_SIZE := 128.0` | 128 m 分块 | 块数 64 → **1024**，LOD0 全量建块 96 ms → 约 1.5 s，节点数 16× | `CHUNK_SIZE` 随尺寸提到 256 m（块数仍是 256，可控）✅ 本批已改成按尺寸推导（1024 m 下仍是 128），见 §16.2 |
| 6 | ~~`VegetationScatter.gd:27` `CHUNK := 128.0`~~ → **已做（第六轮 ②，§12.7）**：`VegetationScatter.gd:30` `CHUNK := 256.0` | 植被区块 | 若仍按 128 m：4096 m 下区块 212 → 约 **3400** 个 `MultiMeshInstance3D`（draw call 爆炸） | 已提到 256 m（1024 m 图节点 212 → 67）✅；4096 m 时按同比例约 850 个，届时再评估是否 512 m |
| 7 | `MapConfig.gd:60` `ai_party_count := 14` | 部队数 | 100 部队 → 寻路请求量 ×7，叠加 #1 的 45.8~730 ms 单次开销 | 单点可改，但**必须**先有请求队列 + 每帧预算 |
| 8 | `NavGrid.gd:18,20` `res = 257` / `size = 1024.0` | 成员默认值 | 构造时都会被传入覆盖，**当前无害** | 建议改成必需参数，避免以后忘传就静默用 1024 |
| 9 | 4 个 `.gdshader` 的 `uniform float map_size = 1024.0` | uniform 默认值 | 运行期都被覆盖，**无害** | 保留默认值即可（漏设时兜底） |
| 10 | `MapData.gd:29` `TERR_RES := 128` + `MapTextureBaker` 512² 贴图 | 势力网格 / 领地贴图 | 每格从 8 m 变 32 m（势力边界变粗） | 可接受；要更细就把 `TERR_RES` 提到 256 |
| 11 | `DayNightCycle.gd:77` `shadow_max_distance = 340.0` | 阴影覆盖半径 | 覆盖范围不变（远景无阴影） | 可接受 |
| 12 | `tools/gen_fingerprint.json`、`perf_baseline.json`、`scale_baseline.json` | 全部是 1024 m 的基线 | 换尺寸后三个探针全红 | 机制已有：三个探针各自 `--write-baseline`，属于**显式接受**的新世界 |
| 13 | `MapTextureBaker.gd:12` `SPLAT_RES := 512` | 生态 splat 贴图分辨率（`scale = (res-1)/map_size`，按尺寸推导） | 每纹素从 2 m 变 **8 m**，生态色边界变粗；烘焙循环次数不变（固定 512²） | 可接受；要保精度就提到 1024（RGBA 1024² = 4 MB） |
| 14 | `MapTextureBaker.gd:13` `MINIMAP_RES := 256` | 小地图贴图 | 每像素从 4 m 变 **16 m** | 可接受（纯 UI，不改世界） |
| 15 | `FogOfWar.gd:10` `RES := 128` | 迷雾**格数**（格距 = `map_size/(RES-1)`，按尺寸推导）；揭开半径来自 `cfg.fog_reveal_radius * 1.4`（**米**） | 每格从 8 m 变 **32 m**：雾边界变方；`cr = ceil(radius/cell)` 随之变小，**每次揭开反而更便宜**；覆盖范围按米算，不缩水 | 可接受；要细就 RES=256（128 KB） |
| 16 ★ | `CameraRig.gd:159` `while t < 4000.0`（拾取射线的最远推进距离） | 硬编码**距离** | 4096 m 的对角线 5792 m：战略视图下点远端地面时射线提前放弃，落点被算成射线末端（点哪都不对，且**不报错**） | 本批已改成 `ray_max_distance(map_size)`（1024 m 下仍是 4000）✅ §16.1 |
| 17 ★ | `TerrainManager.gd:18` `LOD_QUADS := [32,16,8,4]`（每级四边形数 ⇒ **顶点间距**） | 硬编码**网格精度** | 只把 #5 的分块提到 256 m 而不同步放大它，LOD0 顶点间距就从 4 m 变 **8 m**：对 2 m 高度图的欠采样从 2× 变 4×；而 `SKIRT`（8 m 裙边）与 `LOD_DIST`（220/400/660 m）都是按 4 m 间距调出来的 —— 等于同时改三件事 | 本批已改成随分块等比放大（间距恒 4 m）✅ §16.2 |

> #16 / #17 都是**清点时漏掉的一条**（分别在改 #3 与 #5 时才在同一个文件里发现）。
> 记在这里而不是悄悄修掉 —— 说明"清点表自称完整"这件事本身也需要一次动手来检验。

**结论：4096 m 不是「改一个数」，而是「一次换世界」** —— 它同时踩中 #1（寻路精度 vs 性能）、
#2（植被 16× 采样）、#3（相机裁掉地形）、#4（导出范围挡住高度图）四处硬编码（外加清点时漏掉的
#16：拾取射线的最远距离、#17：地形网格顶点间距，见下表末两行），并且必然让三个基线全部
重新生成。合理的顺序是：**先做 6d 后半（请求队列 + 每帧预算）→ 再改 #3/#4 这类单点 → 然后 #5/#6 分块尺寸
→ 最后连同 6b 的单遍筛选一起切 4096，一次性重基线化**。整个链条留到第六轮后续批次。

> 进度：#3 / #4 / #16 已在第七轮后续第 ① 批做掉（§16.1），并新增了一条把它们钉住的门禁第 7c 步。

---

### 12.6 本批（① 收尾）交付：规模探针从「绝对耗时」改成「双信号耗时」

**这一批是被一次真实的门禁变红逼出来的，完整记录一下。**

门禁在做完 6b 后突然报 `[规模] FAIL：2 项不符`。看引擎日志：**耗时项全部等比变慢 2.0~2.5×，
而所有结构量（实例数 / 区块 / 三条地形指纹 / 每对路径点数与展开节点数 1143、5184）一字不变**：

| 项 | 基线 | 那次 | 原始倍数 |
|---|---|---|---|
| 植被 build 合计 | 448.5 ms | 1024.1 ms | 2.28× |
| 地形 LOD0 中位 | 0.977 ms | 2.482 ms | 2.54× |
| 地形 LOD1 中位 | 0.282 ms | 0.791 ms | 2.80× |
| A* fine 合计 | 19.0 ms | 46.2 ms | 2.43× |
| 采样原语 height_at | 0.529 µs | 1.249 µs | 2.36× |

结构量一字不变 + 耗时全部等比 ⇒ 这是**环境漂移，不是代码回归**；而当时的判据是绝对耗时 × 2.5 判失败，
所以必然误报。修法分三层：

1. **同机标尺**：新增 `_calibrate()` —— 3 次 × 20 万次纯算术循环（`x = x*1.000001 + 0.5; acc += sqrt(…)`，
   不碰本工程的任何函数与数组）取中位，写进基线（`calib_ms`）。耗时项先除以它，得到「归一化倍数」。
2. **双信号判失败**：`FAIL` 要求**原始倍数**与**归一化倍数**同时超 2.5×；只有原始超 1.6× 记 WARN。
   理由见下面这条【未解】—— 单靠归一化会漏报。
3. **原语微基准也取中位**：`prim_height_at_us` / `prim_normal_at_us` 原来单跑 2 万次，亚微秒量级会被
   分配器状态带偏；现在各跑 3 次取中位。`calib_sink` 与 `prim_acc` 一样不进基线。

**【未解】标尺只反映 CPU 频率，反映不了内存/IO 漂移。** 修好后的第一次验证里，标尺报「整机比基线
**快** 0.82~1.27×」，而同一跑的世界生成时间是 **5.7~6.2 s**（基线状态下约 3.5 s）—— 说明当时慢在
内存/分配/IO 子系统，CPU 单核算术反而更快。归一化在这种情况下会**把真实变慢掩盖掉**（把 2.5× 压成
0.9×）。所以：**（a）判失败必须两个信号都同意；（b）绝对耗时永远只是参考量，探针的硬契约只能是结构量。**
这条不标「已解」：目前还没有能同时覆盖 CPU 与内存漂移的同机标尺。若以后要更硬的耗时契约，方向是
在同一跑里再插一段「内存型」标尺（大量小对象分配 + PackedArray 读写），取两者几何平均。

**验证**：改完连跑 **3 次全部 PASS、0 条 WARN**；完整门禁 `== 全部通过（21 项，用时 59.1s）==`，exit 0。
标尺自身开销 12~20 ms，相对整条探针可忽略。

**与 perf_probe 的政策对齐**：`perf_probe` 早就是「默认只 WARN，加 `--strict` 才判失败」；本批把
`scale_probe` 调成「双信号才失败」，两者口径一致 —— **计时项不能让机器噪声把门禁弄红，
但两个信号都同意的真实回归必须红。**

---

### 12.7 本批（② 植被）交付：分桶 128 → 256 m 拿了 −29% 节点；批量写**实测否决**

② 规划里有两件事，结果一件成了、一件被自己的测量否掉。

#### （a）分桶 128 m → 256 m：节点数 −29%，世界内容一字未动

`VegetationScatter.CHUNK` 128.0 → 256.0（现 `VegetationScatter.gd:30`）。1024 m 图上每类 4×4=16 桶。

| 指标 | 128 m | 256 m | 变化 |
|---|---|---|---|
| `veg_chunks`（scale_probe） | 212 | **67** | −68.4% |
| idle `nodes`（perf_probe） | 446 | **315** | −29.4% |
| idle `objects` | 2599.8 | **2453.6** | −5.6% |
| march `nodes` | 446 | **321** | −28.0% |
| march `objects` | 2608.5 | **2482.7** | −4.8% |

**「布局没动」的正式证据**：变换指纹 `6df28ca8fc5f8fc7` 在 **128 m（212 节点）与 256 m（67 节点）
两次独立测量里逐位相同** —— 5163 个实例的 12 个 float（三个基向量 + 原点）**集合**完全一致，
换掉的只是「按多大一块装桶」。这个证明能成立，靠的是本批同时做的判据升级（见 (c)）。

**生成指纹的变化是显式接受的**：`gen_fingerprint.json` 逐段对比，**10 段里只有 `vegetation` 一段变**
（`53c61521…` → `6ea6a9c9…`），其余 heightmap / nav_fine / nav_coarse / nav_road / settlements /
roads / bridges / parties / territory **逐字节相同**；植被段自己的 detail 也一字未变
（`5163 实例 / broadleaf=2132 cactus=257 conifer=1952 deadtree=211 rock=611`）。
即：变的是「场景按多大一块装桶」，不是世界内容 —— 这属于第 12.5 节 #12 说的「显式接受」。
门禁因此重跑基线一次（`gen_fingerprint.json` 的 `fingerprint` 段）。

**诚实的代价**：剔除粒度变粗 —— 256 m 的块只要有**一角**在视锥里就整块绘制。
headless 量不到剔除开销（`draw_calls` 恒为 0，要开窗另测），所以这里**能证明的只有「节点/对象数下降」**，
剔除效率仍是【未解】。若将来开窗测得剔除反而更费，回退只需改回 `CHUNK := 128.0`（布局不受影响）。

#### （b）批量写：正确，但**更慢** —— 否决

按规划试了 `RenderingServer.multimesh_set_buffer`：每实例 12 个 float（3 行 × 4 列行主序矩阵，
三个基向量各一行、第 4 列是原点）。**正确性没问题** —— 探针能从场景逐个读回 `Transform3D` 再哈希
（中间有一次布局写错，立刻被它抓住，见 (c)）。但**发射段 2.6 → 5.4 ms（约 2× 更慢）**：
在 GDScript 里逐实例填 12 个 float 的脚本开销，大于 5163 次 `set_instance_transform` 的调用开销；
每桶只有约 80 个实例，这个规模根本不值得。

结论：**改回逐实例写**，否决理由写进 `_emit_chunks` 的代码注释，数据留在这里。
**【实证】在这个规模上「少调 API」不等于「更快」，脚本侧搬运数据的代价才是大头。**
这又是一次「估计偏乐观」（同 6c、6d 前半）：上一轮把批量写当顺手就能拿的分，实测是负收益。

#### （c）判据升级：变换指纹从「分组敏感」改成「分组无关」

旧 `_veg_hash` 按「类名 → 区块名 → 实例序号」喂 SHA-256：分桶一变，节点名与分组就变，指纹跟着变。
于是它同时存在两种失效 —— **既会在布局写错时报警（有用），也会在只换分桶时报警（噪声）**，
两者混在一个值里，谁也分不清。这正是本批一开始被绊住的地方。

现在改成：每个实例各算一个 12 float 摘要 → **排序** → 合成总指纹。它只回答一个问题：
**实例落点有没有变。** 分桶、节点命名、创建顺序都不再影响它 —— 后面 4096 m 那轮反复要用这条判据。

**验证**：完整门禁 `== 全部通过（20 项，用时 58.9s）==`，exit 0；
`scale_baseline.json` 显式重写（`veg_chunks 67` / 指纹 `6df28ca8fc5f8fc7` / `calib_ms 15.33` /
`veg_emit_ms 3.49`）；`perf_baseline.json` **未动**（本机当前偏慢，此时重写只会把上界放宽）。

---

### 12.8 本批（6d 后半）交付：全局寻路请求队列 + 每帧预算

**为什么必须先做它**：4096 m / 100 部队时单次 A* 是 200~730 ms（§12.5 拦路虎 #1），
而它现在是**同步**调用 —— 一次寻路就是一次帧冻结。所以「请求队列 + 每帧预算」是切 4096 的**前置条件**，
不是可选项。

**做法**：新增 `scripts/nav/PathQueue.gd`（`class_name PathQueue`）：

- 所有 AI 寻路请求入一条 FIFO 队列；`Main._process` 每帧 `pump(PATH_BUDGET_US)`，默认预算 **2000 µs**（16.6 ms 的 12%）。
- **先完成再判预算** ⇒ 预算比单个请求还小时，每帧仍恰好前进一个（饿死保护）。
- `AIParty._repath_to` 改走队列，回调里调新的 `_apply_path()` —— **同步与队列共用同一段结算代码**，
  所以两条路的成功/失败行为（含「失败目标格指数退避」）严格一致。
- 玩家点击仍走**同步** `find_path`（点击必须立刻有反应），这一条留在 `WorldGenPipeline` 的注释里。
- `data.path_queue` 为空时 `AIParty` 自动退回同步 ⇒ 直接 `new MapData` 的旧检查行为完全不变。

**确定性**：队列不抽任何随机数；RNG 抽取仍在各部队调用点、寻路**之前**完成 ⇒ 排队不改变任何抽签序列。
实测**生成指纹未变**（部队在 20~50 帧的采样窗口内还没到第一次重寻路），所以本批**不需要**重基线化。

**实测（`tools/path_queue_check.gd`，真实 1024 m 世界，23 项断言全过）**：

| 量 | 实测 | 含义 |
|---|---|---|
| 单请求均值（coarse） | **15.9 ms** | 100 个真实请求 1590.6 ms |
| 单请求峰值 | **53.2 ms** | 预算 2000 µs 挡不住它 ⇒ 饿死保护是必需的，不是保险 |
| 生成期累计完成 | 211 个 | 接线确实在真实生成流程里生效 |
| 100 个积压 | 100 次 pump | 每帧一个 = 100 帧（约 1.7 s） |
| 100 个积压的总算力 | 1590.6 ms | **按 2 ms/帧要 796 帧 ≈ 13.3 s** ⇒ 100 部队时预算必须调大 |

**由这张表直接推出的 4096 结论（写进 ④ 的交接）**：100 部队 × 15.9 ms 单次 ≈ 1.6 s 寻路算力/轮；
以 2 ms/帧摊开要 13 s —— 部队会「等路等到站着不动」。所以切 4096 时预算要跟着涨（8 ms/帧 ⇒ 约 3.3 s），
**且**必须先把粗栅格格距放大（§12.5 #1：4 m/格 ⇒ 1.05 M 节点）。两者缺一不可。

**门禁**：新增第 5b 步（`path_queue_check`）。它判的是契约而不是观感 —— 队列算错的表现是
「部队偶尔站着不动」，在 900 帧主场景里几乎不可能稳定复现。

---

### 12.9 本批（⑦）交付：LICENSE + config/version + 导出预设 + 分级日志

**(a) 素材来源先查清，再定 LICENSE**【实证】。`git ls-files` 逐一过一遍媒体/字体/模型：
仓库里只有 `audio/bgm/map_theme.ogg`、`audio/bgm/battle_theme.ogg`（`Bgm.gd` 注释写明是
XSXB-Band 本地工作室写谱 + 用**真实 CC0 录音乐器**渲染）与 `icon.svg`，**没有任何第三方字体 / 模型 / 贴图**。
⇒ 挑 MIT 是安全的（CC0 素材不带来署名义务）。`LICENSE` 里的版权署名取仓库归属 `BitToNet`
（如需改成别的署名，改这一行即可）。

**(b) 版本号与导出预设**。`project.godot` 补 `config/version="0.6.0"`（第六轮）；新增
`export_presets.cfg`（Windows Desktop / x86_64 / `build/warband.exe`，`build/` 本来就在 `.gitignore` 里）。

**(c) 分级日志 `scripts/core/Log.gd`**：DEBUG < INFO < WARN < ERROR 四档，
级别来自 `-- --log-level=debug` 或环境变量 `WARBAND_LOG`（默认 **INFO**）。迁移是**逐字保真**的：
`print("[日结] …")` → `Log.info("[日结] …")`，屏幕上一字不差，所以迁移不改变任何既有观感。
`Main` 里 6 处已迁移（日结 / 周结 ×2 / 存档失败 / 读档拒绝 / UI 标签）；**故意留 1 处裸 `print`**
（「地图生成完成」那一行被门禁与 `gen_fingerprint` 解析，不能受日志级别影响）；其余脚本里的
11 处裸 `print` 列入后续批次。

**(d) 两条周边契约写成断言**（`tools/log_check.gd`，19 项，门禁第 5c 步）：
① 默认级别必须是 INFO —— 否则门禁会因为「看不见」而变绿；② `Log.error` 必须仍以 `"ERROR: "` 开头走
stderr —— 门禁靠这个前缀兜底抓失败。第 ② 条在进程内抓不到 stdout，所以**改成对 `Log.gd` 源码字面量下断言**；
而且 `log_check` 自己**故意不真的调 `Log.error`**（门禁把输出里的 `ERROR: ` 一律记为失败）——
这条自检第一次跑就撞上了这个坑，写进注释留档。

**验证**【实证】：`--headless --editor --quit` exit 0 且生成 `global_script_class_cache.cfg`（⑧ 的 CI 第一步）；
`--export-release "Windows Desktop"` **认得这个预设**（报错只针对缺失的导出模板
`export_templates/4.7.stable/windows_{debug,release}_x86_64.exe`）。
**【未解】本机没有导出模板 ⇒ 「真的能导出一个能跑的 exe」这件事无法在此验证**，只能验证到「预设合法且被引擎接受」。

---

### 12.10 本批（⑧）交付：CI 门（建缓存 + 跑门禁）

新增 `.github/workflows/ci.yml`（`windows-latest`，因为门禁是 Windows PowerShell 5.1 脚本）：

1. 取固定版本 Godot（官方 release，`4.7-stable`，**不解析「最新版」**）+ 把路径写进 `GODOT_BIN`；
2. `--headless --path . --editor --quit` 建导入缓存，并断言类缓存文件确实出现；
3. `powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_checks.ps1`（即本地那道门）；
4. 失败时上传 `%TEMP%\warband_check_*.log` 作为 artifact。

为此 `tools/run_checks.ps1` 的引擎路径改成 `GODOT_BIN` 可覆盖（本机默认仍走用户全局规则 2 的固定路径）。

**验证**【实证】：把 `GODOT_BIN` 设成本机引擎后**跑完整门禁** —— 表头打印
`引擎：G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe`，即覆盖真的生效。
**【未解】工作流本身从未在真实 Runner 上跑过**（本机无法验证 GitHub Actions，也不能为此去装东西）：
`GODOT_URL` 按官方命名约定写死了资产名，第一次真跑若 404，改 workflow 里那一行即可。

---

### 12.11 下一步：⑥ i18n 起步（范围与验收标准，先写下来再开工）

**范围（"起步" = 抽表 + 迁一处真界面，不做语言切换）**：

1. 新增 `scripts/core/Strings.gd`（`class_name Strings`）：常量表，命名用 `SCREAMING_SNAKE`，
   **值是逐字保真的现有中文**（迁移不许改观感）。
2. 先只迁一个界面：`scripts/ui/*` 里文本量最大、且**已被门禁覆盖**的那一个（`hud_check` 68 项 /
   `settlement_check` 104 项会替我们守住"观感没变"）。其余文件的文案登记在表里，代码下一批再切。
3. 「还剩多少硬编码中文」必须**可量**：`tools/i18n_check.gd` 用正则扫 `scripts/ui/**` 里的中文字面量，
   记录条数并**只收紧不放松**（本轮先记录基线值，写进 `tools/i18n_baseline.json`）。
   这是本次 ⑥ 的**验收标准** —— 不是"做过迁移"，而是"数字变小且被门禁钉住"。

**为什么不一次全迁**【推断】：整库界面文案面广，而每条文案的观感都由门禁断言守着；
一次全迁会让失败面变成"几十处同时对不上"，定位成本远高于收益。分批迁 + 棘轮数字更划算。

---

### 12.12 本批（⑥）交付：i18n 起步（Strings.gd + 棘轮）

按 §12.11 定下的范围做，没有越界：

- 新增 `scripts/core/Strings.gd`（9 条常量），**值是逐字保真的**；本轮只迁 `TopBar`（顶栏 9 处字面量）。
- 迁它的理由【实证】：`tools/hud_check.gd` 的 68 项断言**直接按字面量断言顶栏文案**
  （`topbar._terrain_label.text == "当前地形：平原"`、`_purse_label.text.contains("钱袋 %d 金" % …)`）——
  门禁自己就是「观感没变」的守卫。迁完 `hud_check` **68/68 PASS**，迁移没有改变屏幕上任何一个字。
- 迁移只改「字面量在哪」，不改屏幕：`"钱袋 %d 金 · …"` → `Strings.PURSE_LINE`，
  格式化仍由调用点 `% [...]` 负责（本表不碰格式化）。
- 新增 `tools/i18n_check.gd`（门禁第 5d 步，49 项断言）+ `tools/i18n_baseline.json`：
  数 `scripts/ui/**` 里「含表意文字（U+4E00–U+9FFF）的字符串字面量」条数，规则只有一条 —— **只许变小**。
  当前基线 `ui_total = 26`（迁移前是 34；TopBar 的 8 条已清零）。剩余大头：HelpPanel 16 / EncounterDialog 5 /
  LoadingOverlay 3 / DebugStatsPanel 1 / SettlementDialog 1 —— 全部登记在基线里，下一批按界面继续迁。

**验收标准是「数字变小且被门禁钉住」，不是「做过迁移」**：`i18n_check` 会把当前条数与基线一起打印，
趋势肉眼可见；新文案请放进 `Strings.gd`，确实要调高基线时显式跑 `-- --write-baseline`
并在变更记录里写清理由（与规模基线同一套规矩）。计数口径是【推断】级的（逐字符扫描、只数出现过表意文字
的字面量个数、不区分是否给玩家看），够用即可，写在工具头部。

**本批踩到的两个坑（写下来免得重犯）**：
1. 迁移是整行替换，我第一次把 `if` 块内的两处缩进写成 1 个 tab，TopBar 立刻解析失败
   （`Expected indented block after "if" block`）—— `hud_check` 当场抓住。**改缩进敏感语言时，替换后必须重新编译。**
2. 新 `class_name`（`Strings` / 上一批的 `Log`）必须先 `--headless --import` 让类缓存认识它，
   否则引用它的脚本会连锁解析失败（`Could not parse global class`），而报错指向的是**引用方**，不是新文件。

## 十三、音频调整记录（BGM 换作者母带 → 打击/移动音效换录音素材）

> 与 §11（音频总线 / 合成 / 缓存）同一主题的后续三批，按发生顺序记账；这三批**没有**改动合成层，
> 只动了"素材从哪来"与"什么时候响"。

### 13.1 大地图点击静音（按需求去掉触发音）

- `TimeFlowController.order_move()` 里删掉 `Sfx.play("order", -4.0)`：大地图上点目标点下令行军**不再发声**。
- `Sfx.FANFARE` 里移除 `"order"`（它不再是扇子音，留着只会让人以为还有地方在播它）；
  `SfxSynth.SPECS` 里**保留** `order` 音色 —— 音色库整体命中/整体丢弃是缓存的设计前提，
  为一条没人播的音色改缓存结构不值得。
- 回归护栏：`tools/sfx_map_check.gd` 的 `SILENT_IDS = ["order"]`（响一次就 FAIL）+ `audio_check.gd`
  里"播放 `order` 不再 duck"。

### 13.2 BGM 换成作者提供的两首母带（`0547a98` / `5fb7d04`）

- `audio/bgm/{map,battle}_theme.ogg` 换成《旧时日》/《降临 · The Descent》（44.1 kHz 立体声母带
  → ffmpeg 去尾部静音 → Ogg `-q:a 6`）；旧的 XSXB-Band 渲染版留在 git 历史与
  `F:\aigc_code\XSXB-Band\exports\`。
- **本项目从此不再是"零外部音频"**，README 的相应措辞已改（下一批又偏离了一次，见 13.3）。

### 13.3 移动 / 打击音效：新增录音素材层 `SfxFoley`（本轮）

**动机**：需求方反馈"走路和战斗时的动效太难听"，并要求参考《只狼》/《黑神话：悟空》的打击感，
随后直接提供了 4 段录音（击中 / 弹反 / 攻击 / 荒野中的脚步声），等于把范围从"移动"扩到"打击"。
合成层做噪声+包络的脚步、金属泛音的打铁，参数怎么调都是电子味；真实录音的瞬态与层次是合成不出来
的，而代价只是"外部音频素材"这条早就为 BGM 破过的约定。

**做法**：

| 层 | 文件 | 作用 |
|---|---|---|
| 素材 | `audio/sfx/foley/*.wav`（40 个，单声道 44.1 kHz 16-bit PCM，15.2 s / 1.2 MB） | 每动作 2~4 个 take，随机播放 |
| 加载 | `scripts/audio/SfxFoley.gd` | `SETS` 表 id→take 清单；缺失静默降级回合成音色 |
| 播放 | `scripts/audio/Sfx.gd` | 建库时把 take 挂到音色条目上（`_attach_foley`），播放取 `_stream_of(e)` 随机挑一个；**新增动作只需改 `SfxFoley.SETS`，不用动播放层** |
| 导入 | `*.wav.import` | `compress/mode=0`（**PCM 不压缩**）—— 默认导入是 QOA 有损，打击类瞬态会被糊 |
| 自检 | `tools/sfx_foley_check.gd` | 清单/变体数/单声道/44.1 kHz/时长/不削波/非静音 + **与合成音色的响度对照** |
| 配方 | `tools/sfx_foley_build.ps1` | 40 个文件的 ffmpeg 切片/滤镜/响度校准表（一次性脚本，不入门禁） |

**两个坑（都是本轮实测踩出来的）**：

1. **Godot 默认把 WAV 导入成 QOA 有损**（`compress/mode=2`）。症状很有迷惑性：自检读到的
   `data` 长度只有预期 1/5、峰值恒为 0.00 dB —— 因为我把压缩字节当 PCM16 解。改成 `mode=0` 后
   时长与峰值立刻对上。**打击类素材必须逐文件确认 `compress/mode`**。
2. **响度必须按"它替换掉的那条合成音色"校准，不能只做统一归一化**。实测统一拉到窗口 RMS −19 dB
   后，录音素材比合成音色低 8~13 dB（合成音色是密集噪波，峰值≈RMS），听起来就像"音效丢了"。
   做法见 13.4。

### 13.4 响度校准（可复现的判据）

- 阶段一：40 个文件统一归到"最大 10 ms 窗口 RMS = −19 dB"，峰值上限 −1.0 dBFS（take 之间音量一致）。
- 阶段二：按 `$match` 表把每个动作整体平移到合成音色的响度上 = **峰值对齐与窗口 RMS 对齐的中点**
  （两个口径各让一半；实测残差最大 1.6 dB）。数值由 `sfx_foley_check.gd` 打印，改素材后重跑重填。
- 例外：`step_a` / `step_b`（需求方的荒野脚步）**只贴峰值**。真实脚步的波峰因数 ≈13 dB，合成的
  脚步是密集滤噪 ≈6 dB，两者无法同时贴齐；按 RMS 拉平需要把起音压掉约 7 dB，正好把脚步声里
  唯一"像人"的部分压没。于是自检的容差也分开定：**峰值 ±4 dB，窗口 RMS −9~+4 dB**
  （允许平均能量更低，不允许更高）。
- 需求方脚步录音的 take 筛选：8 个切片按"处理后信噪比 ≥35 dB 且瞬态够强"选出（弱起音 t=5.53 /
  6.66 / 12.16 s 与过轻的 10.92 s 已剔除），链路 `highpass=70 + afftdn + 2:1 压缩`。

### 13.5 验收与遗留

- 新增并**已接进门禁**（第七轮 §14.1，第 9e 步）：
  `sfx_foley_check.gd` = **PASS**（14 个动作 / 40 个变体 / 缺失 0）；`audio_check.gd` 47 项、
  `audio_cache_check.gd` 77 项、`sfx_map_check.gd`、主场景 900 帧 smoke 全部 PASS。
- 仍是纯合成音色、**没有**录音素材的动作：`proj_impact` / `poise_break` / `hurt` / `roar` /
  `encounter` / `perfect_dodge`（完美闪避的铃音是玩法信号，故意保留合成音色）/ 预警音。
- 录音素材只有 2~4 个 take、来源是 CC0 库 + 需求方录音（不是商业音源库）；长时间连续触发仍可能
  听出重复。逐文件来源与授权见 `audio/sfx/foley/CREDITS.md`。

---

## 十四、第七轮变更记录（两件收尾：录音素材自检进门禁 + i18n 迁完）

> 本批只做"把已经做完的东西钉住"：§13.5 登记的门禁待办（`sfx_foley_check`），
> 以及 §12.11 定下的 i18n 棘轮把剩余五个界面迁完。**没有**改生成 / 玩法 / 音色 / 素材本身，
> 所以指纹与生成统计必须一字不变 —— 这也是本批的验收要点。

### 14.1 本批交付（§13.5 待办）：录音素材自检进门禁（新第 9e 步）

`tools/run_checks.ps1` 新增一步 `sfx_foley_check`（门禁项数 **24 → 25**，本机实测 60.6 s 全绿）。

**为什么它值得独占一步**：素材层别的方面坏掉都会自己报错（文件缺了 / 变体数不对 / 采样率不统一 /
削波），唯独**响度**不会 —— 40 个录音变体只要统一归一化，就会比它们替换掉的合成音色低 8~13 dB，
表现是"门禁全绿、进游戏却像音效丢了"。这条回归只有响度对齐断言抓得到，判据见 §13.4
（峰值 ±4 dB / 窗口 RMS −9~+4 dB），而这条判据本身又是逐条实测填出来的，不是拍脑袋定的。

**实测**：`sfx_foley_check` = **PASS**，14 个动作 / 40 个变体 / 缺失 0，加载 25 ms、建库 8 ms。

**素材与代码已先一步入库**：`7c4b2fb`（`SfxFoley.gd` + `audio/sfx/foley/**` 81 个文件 + `Sfx.gd` 接线）
与 `f44abb9`（README / §13 记录）。本批只补门禁这一步 —— 反过来做（先加门禁、素材还留在工作区）
会让任何干净检出上的门禁直接红。

### 14.2 本批交付（⑥ i18n 收尾）：`scripts/ui` 硬编码中文 26 → **0**

§12.12 把 `TopBar` 迁进 `Strings.gd` 后，棘轮钉着的剩余五个界面本批一次迁完：

| 文件 | 迁走 | 表里的常量 |
|---|---|---|
| `scripts/ui/HelpPanel.gd` | 16（15 行说明 + 标题「【操作】」） | `HELP_*` 16 条 |
| `scripts/ui/EncounterDialog.gd` | 5（兜底两行的标题 / 提示 + 键位提示行） | `ENCOUNTER_*` 5 条 |
| `scripts/ui/LoadingOverlay.gd` | 3（标题 / 副标题 / 准备中） | `LOADING_*` 3 条 |
| `scripts/ui/SettlementDialog.gd` | 1（键位提示行） | `SETTLEMENT_HINT_LINE` |
| `scripts/ui/DebugStatsPanel.gd` | 1（FPS 行） | `STATS_LINE` |

**逐字保真**，迁移只改"字面量在哪"：`hud_check` **77/77**、`encounter_check` 117/117、
`settlement_check` 104/104 全过，屏幕上一个字都没变。`HelpPanel.LINES` 那张表保留在界面文件里
（它表达的"哪一行配哪个动作"是界面的事），表里的**文案**换成 `Strings.HELP_*`。

**顺手把"观感守卫"补齐**：`hud_check` 原本只断言了 TopBar 的文案，`HelpPanel` / `LoadingOverlay` /
`DebugStatsPanel` 三块**一条文案断言都没有**（只有 `mouse_filter` 那种行为断言）——
那样的话"迁移没改观感"这句话在本批只是自述。所以补了 **9 条**断言（68 → 77），断的是
**渲染出来的字符串**：操作说明的标题与首末两行、开局遮罩的标题 / 副标题 / 初始进度行、
性能面板的整行格式（正则，因为数字每 0.25 s 变一次）、两个对话框的键位提示行。
它们**故意按字面量写**，不写 `Strings.X` —— 断常量等于断常量自己，什么都证明不了。

> 这条断言也顺带钉住一个时序细节：遮罩的初始进度行「准备中…」必须在 `set_loading()` 之前断，
> 因为那一步会把进度行覆盖掉（第一版写在后面，`hud_check` 当场报了 1 项失败）。
> 另外 `LoadingOverlay` 的标题 / 副标题从局部变量改成了成员 `_title` / `_sub` —— 断言要取得到，
> 否则只能按 `get_child(1).get_child(0)…` 这种一改布局就断的路径去摸。

**棘轮基线收紧**（`tools/i18n_baseline.json`）：`ui_total` **26 → 0**，`ui_files` 全部归零。

**两个口径说明（免得下次把数字看错）**：

1. `project_total`（只报告、不判定）**602 → 631**：迁移把 26 条从 `scripts/ui` 挪进了 `scripts/core`，
   所以 `ui_total` 下降必然伴随 `project_total` 上升；另外 +3 来自 §13 新增的 `SfxFoley.gd`
   （它也在 `scripts/` 下）。**看 i18n 进度要看 `ui_total`，不要看 `project_total`。**
2. 「`scripts/ui` 归零」**不等于 i18n 做完**：剩下 631 条分布在 `scripts/core` / `battle` / `audio` 等
   目录（含大量 `push_warning` / 日志 / 内部 id，不是给玩家看的）。本批**明确不做**，
   理由是 §12.11 的原话：界面的观感由门禁断言守着，其它目录的文案没有等价守门人，
   大范围迁移只会把"几十处同时对不上"变成定位成本。要做的话，正确顺序是
   **先给那个目录建一条与它对应的断言**，再迁。

### 14.3 验收（2026-10-14，`powershell -File tools\run_checks.ps1`）

| 项 | 结果 |
|---|---|
| 一键门禁 | **exit 0，25 项全绿**（新增 9e 步；两次实测 60.6 s / 69.3 s） |
| `i18n_check` | **PASS，ui_total = 0**（基线 26，差 −26） |
| `hud_check` / `encounter_check` / `settlement_check` | **77** / 117 / 104 项断言全过（`hud_check` 补了 9 条文案观感断言） |
| 生成指纹 | `d68cb1d2c0c2acae…`，与 `tools/gen_fingerprint.json` 一致 |
| 生成统计 | 定居点 18 / 桥梁 7 / 植被 5163（与基线一致） |
| `perf_probe` | 1 条 WARN（常态，未超硬容差） |

### 14.4 本批的两个坑

1. **`run_checks.ps1` 的 BOM 又被 `edit` 吃掉了**（§9.3 第 4 条记过一次）：本批改完头部注释后，
   用 `[System.IO.File]::ReadAllText` + `UTF8Encoding($true)` 写回才恢复；恢复后**必须再解析一次**
   （`[System.Management.Automation.Language.Parser]::ParseFile`）确认没有语法错误 ——
   本机是 Windows PowerShell 5.1，无 BOM 的 UTF-8 会按 GBK 解码，中文注释直接变成语法错误。
2. **跨脚本的 `const` 可以引用 `Strings.X`**（本批第一次这么用）：`HelpPanel.LINES` 是 `const`，
   里面放 `Strings.HELP_CLICK_MOVE` 编译通过 —— `class_name` 全局类的常量是编译期常量。
   但前提仍是那条老规矩：**新 `class_name` 必须先跑一次 `--headless --import` 进类缓存**；
   `Strings` 早已在缓存里，所以本批不需要。若哪天报 `Could not parse global class`，先查缓存，别查语法。

---

## 十五、第六轮剩余项（下一步的入口）

按 §12.5 的清单，第六轮还剩一条主线没动：**4096 m 地图 / 100 部队**。本批不碰它，但把入口写清楚：

1. 先做 §12.5 表里的单点项（相机远裁剪按 `map_size` 推导、`heightmap_res` 的 `export_range` 上限
   1025 → 2049）—— 这两项在 1024 m 世界下**行为完全不变**，可以单独一批做掉。✅ **已做，见 §16.1**
2. 再做分块尺寸（`CHUNK_SIZE` 128 → 256）—— 会改区块数与节点数，需要同步更新
   `tools/scale_baseline.json`（结构量基线）与 `tools/gen_fingerprint.json`（若 RNG 顺序受影响）。
   ✅ **已做，见 §16.2** —— 实际做成"带下限的推导"，1024 m 下**不需要**重基线（§15 的这条预估偏保守）。
3. 最后连同 6b 的「单遍筛选」一起切 4096，**一次性重基线化**并重新采样性能基线；
   理由是这两件事都会改植被布局，分两次做等于把"布局变了"这个事实付两遍定位成本。
   ⚠️ **这条计划已被实测改写，见 §16.4**：先量了一遍 4096 m 世界，发现 83 秒里 **71% 是地形高度场**
   （其中 `_build_biomes` 一个人占 44%），植被只占 18%。所以 ③b 重排为
   **③b-1 高度场提速 → ③b-2 植被（6b + CELL/CHUNK 按尺寸推导）→ ③b-3 换世界 + 一次重基线**。
   "只付一次重基线"这条原则不变，只是第一刀砍在了没人预料到的地方。

---

## 十六、第七轮后续批次记录（4096 m 链条，逐批记账）

> §15 把剩余工作排成 ①→②→③ 三批。从本节起按实际发生的批次记账，**每批都以"跑满门禁 + 提交推送"收尾**。

### 16.1 第 ① 批交付：尺寸推导单点项 + 「尺寸适配」定式自检
（对应 §15 第 1 步 / §12.5 的 #3、#4、#16）

**改了三处纯数值假设，全部按 `map_size` 推导，且在 1024 m 下逐位等于旧常量** ——
所以本批的验收标准不是"看起来对"，而是**指纹与生成统计一位不变**：

| 位置 | 旧值 | 新值 | 1024 m 下 |
|---|---|---|---|
| `CameraRig.gd` `cam.far` | `5000.0` | `maxf(5000.0, map_size * 1.5)` | 5000（不变） |
| `CameraRig.gd` 拾取最远距离 | `4000.0` | `maxf(4000.0, map_size * 1.5)` | 4000（不变） |
| `MapConfig.gd` `heightmap_res` 导出上限 | `1025` | `2049` | 默认值仍 513（不变） |

下限不是"保守的魔法数"，而是**旧常量本身**：写成 `maxf(旧值, 推导值)` 之后，"换尺寸前行为不变"
是一眼可验证的代数事实，而不是靠跑一遍才知道。4096 m 时远裁剪面 6144 m、
拾取最远 6144 m，都盖得住 5792 m 的对角线。

**顺手补上了清点表漏掉的 #16**（见 §12.5 表末行）：`ray_to_terrain()` 里 `while t < 4000.0`
是一条与相机无关、但同样与地图尺寸绑定的硬编码。它的失败方式和 #3 一样隐蔽 —— 1024 m 图下
永远走不满，4096 m 图下点远端地面会静默把落点算到射线末端。**是在改 #3 时顺手读同一文件才发现的**，
这也说明清点表不能靠"再读一遍"来保证完整，只能靠动手。

**新增门禁第 7c 步 `tools/map_size_check.gd`（21 项断言）**：这一批的坑全都不报错，
所以必须把"按尺寸推导"这层**关系**本身钉住：

- 1024 m 下的两个推导值必须**恰好等于**旧常量（把"行为不变"写成断言，而不是写在提交信息里）；
- 4096 m 下（以及 1024/2048/512/8192 的扫描）必须覆盖对角线，且对尺寸单调不减；
- `heightmap_res` 的 `@export_range` 上限要放得下 2049、步进仍是 2、上限本身落在步进格点上
  （否则编辑器里最后能选到的不是上限）；
- 拾取循环的迭代上限必须够走完推导出来的距离（`RAY_GUARD` × `RAY_STEP_MAX` 的自洽性）；
- 报告 2049² × 4 B ≈ 16.8 MB 的量级（只打印、不判定 —— "可不可接受"是人的决定）。

它**不**证明渲染效果、也不证明拾取真的命中地形：那些属于实机观察。这一步的价值边界写在文件头，
和 §12.6 的双信号耗时探针同一个态度。

**本批踩的坑（新探针当场抓到了自己）**：`@export_range` 的 `hint_string` 引擎是**小数**形式
（`"129.0,2049.0,2.0"`），我第一版用 `is_valid_int()` 解析，步进全线落空、断言报
"步进仍是 2（当前 1）"。**新写的探针第一次运行就报错**是好事 —— 它证明这条断言真的在跑，
而不是写了个恒真式。修法是 `is_valid_float()` + `to_float()`，并把这条坑写进了函数注释。

**验收（2026-10-14，`powershell -File tools\run_checks.ps1`）**

| 项 | 结果 |
|---|---|
| 一键门禁 | **exit 0，26 项全绿，用时 71.9 s**（新增 7c 步；`map_size_check` 0.4 s / 21 项断言） |
| 生成指纹 | `d68cb1d2c0c2acae…` **与基线一字不差**（本批行为中性） |
| 生成统计 | 定居点 18 / 桥梁 7 / 植被 5163（未变） |
| 其余 25 项 | 全绿（含 `hud_check` 77 项、`sfx_foley_check`、`main_scene_900`） |

### 16.2 第 ② 批交付：地形分块边长与网格精度都按尺寸推导
（对应 §15 第 2 步 / §12.5 的 #5、#17）

改法两条，都在 `TerrainManager`：

```gdscript
static func chunk_size_for(map_size: float) -> float:   # maxf(128, map_size / 16)
static func lod_quads_for(map_size: float) -> Array:    # 旧表 × (分块边长 / 128)
```

| 尺寸 | 分块边长 | 块数 | 每级四边形 | LOD0 顶点间距 | 单块 LOD0 三角形 |
|---|---|---|---|---|---|
| 1024 m（当前世界） | 128 m | 8×8 = 64 | 32 / 16 / 8 / 4 | 4 m | 2048 |
| 2048 m | 128 m（下限生效） | 16×16 = 256 | 32 / 16 / 8 / 4 | 4 m | 2048 |
| **4096 m（目标）** | 256 m | 16×16 = **256** | **64 / 32 / 16 / 8** | **4 m** | 8192 |

**为什么四边形数必须跟着放大（#17）**：`SKIRT`（8 m 裙边）、`LOD_DIST`（220/400/660 m）、
`heightmap_res`（2 m 采样）这三样都是围着"4 m 顶点间距"调出来的。只把分块提到 256 m 而不同步放大
四边形数，LOD0 间距就变成 8 m —— 对高度图的欠采样 2× → 4×，而裙边余量与 LOD 距离的失效方式是
**视觉接缝与跳变**，不是报错。等比放大之后，"换尺寸"动的只有分块的**粒度**，网格精度一位不变。

**与 §15 草案的一处不同，而且是更好的结果**：§15 预期"`CHUNK_SIZE` 128 → 256 会改区块数与节点数，
需要同步更新 `scale_baseline.json`"。做成"带下限的推导"以后，**1024 m 下一个数都不用重基线** ——
`scale_probe` 的 `terrain_chunks` 64、LOD0 顶点 1601、位置/索引/法线三条指纹全部与基线**逐位一致**。
重基线化因此推迟到第 ③ 批"世界真的变了"的那一次，只付一次定位成本（这正是 §15 第 3 步的本意）。

**探针同步改了，而且是必须改的**：`scale_probe` 原来直接用 `TerrainManager.CHUNK_SIZE` /
`LOD_QUADS` 算结构量。换尺寸后那两个常量算出来的是**这个工程根本不会建出来的块数**（4096 m 下
32×32 = 1024 块），基线就会拿一个不存在的东西当参照。现在探针调同一对推导函数（1024 m 下结果相同）。
顺带一提：报告函数里那处引用我第一版写成了 `_p_terrain()` 的局部变量，门禁当场
`Parse Error: Identifier "quads_by_lod" not declared`。

**`map_size_check` 扩到 43 项断言**（新增 22 条）：1024 m 下两个推导值必须逐位等于旧常量、
4096 m 下 256 块不超预算、四级间距依次 4/8/16/32 m、三角形密度恒为 8 m²/个、`LOD_DIST` 未被改动。

**本批第二个"自己抓到自己"**：第一版断言写的是"单块 LOD0 **顶点数**翻 4 倍"，实际 33² → 65²
只有 3.88 倍（顶点在块边界上不会跟着翻倍）。真正守恒的是**三角形数**翻 4 倍、
以及"每平方米三角形密度恒为 0.125 个"。改成断这两个量之后它才是一条有意义的守恒律 ——
错的断言比没有断言更危险，因为它会让人以为改对了。

**留一个明确没解决的观感问题（给第 ③ 批）**：LOD 切换的**粒度**跟着分块变成 256 m（今天是 128 m），
而 `LOD_DIST` 是绝对米数 —— 所以 4096 m 图里 LOD0 仍然只覆盖相机周围约 220 m（与今天同口径，这是对的），
但**一整块 256 m 会同时跳级**，跳变的面积是今天的 4 倍。可选修法：`LOD_DIST` 也按 `分块/128` 放大
（覆盖面 ×4、三角形 ×4），或给 LOD 表加一级。**本批故意不动它**：这是 4096 m 链条里唯一必须看画面
才能定的事，留给 ③ 在 4096 m 图上用 `main_scene_900` + `perf_probe` 实测后再定。

**验收（2026-10-14）**

| 项 | 结果 |
|---|---|
| 一键门禁 | **exit 0，26 项全绿，用时 71.2 s** |
| 生成指纹 | `d68cb1d2c0c2acae…` **与基线一字不差**（分块只影响网格，不影响世界内容） |
| `scale_probe` 结构量 | 块数 64 / LOD0 顶点 1601 / 位置·索引·法线三条指纹全部与基线一致 |
| `map_size_check` | 43 项断言全过（0.4 s）；并打印 4096 m 的推导结果供核对 |
| 生成统计 | 定居点 18 / 桥梁 7 / 植被 5163（未变） |

### 16.3 第 ③a 批交付：寻路栅格分辨率按目标格距推导（#1）
（对应 §12.5 的 #1；③ 链条拆成 ③a / ③b 两批，理由见本节末）

```gdscript
static func res_for(size: float, spacing: float) -> int:   # round(size / spacing) + 1
```

`WorldGenPipeline` 里的三个硬编码换成推导：细栅格 4 m/格、粗栅格 8 m/格、道路栅格 8 m/格。

| 尺寸 | 细栅格 | 粗 / 道路栅格 | 细栅格节点数 |
|---|---|---|---|
| 1024 m（当前世界） | 257（不变） | 129（不变） | 66049 |
| **4096 m（目标）** | **1025** | **513** | **1050625（105 万）** |

**为什么不能"不缩放"**：不做推导、让栅格分辨率固定 257，4096 m 图上每格就变成 16 m ——
部队会「跳格」走，路口、河岸、桥梁这些窄结构直接消失在地图里。反过来按格距推导，栅格**精度**
一位不变（4 m / 8 m 贯穿所有尺寸），代价是节点数按面积增长：4× 边长 ⇒ **16× 节点**。

**为什么 ③ 要拆成两批**：§15 第 3 步的本意是"6b 单遍筛选与 4096 m 一起做，只付一次重基线成本"。
但拆开看，本批（#1 寻路栅格）在 1024 m 下**逐位不变**，不需要任何重基线 ——
而 6b 的单遍筛选**必然**改变植被布局（原来 5 个植被类型共用一条 rng 流、穿插消费；
合并成一遍扫描后抽样顺序必然改变），它才是真正必须与 4096 m 绑定在一起的那件事。
所以：③a = 可以在 1024 m 下证伪/证真的部分（本批），③b = 一次性换世界 + 重基线（下一步）。

**#8 顺带核实了**：清点表担心 `NavGrid` 的成员默认值 `res = 257 / size = 1024.0` 会让人"忘传就静默用 1024"。
核对后确认 `_init(p_res, p_size)` 本来就没有默认参数，**没有那条静默路径**；只在成员处补了一句注释说明。
这类"清点时以为是坑、动手时发现不是"的条目同样值得记一笔 —— 否则下次还会有人重新担心一遍。

**`map_size_check` 扩到 57 项断言**（新增 14 条）：1024 m 下 257 / 129 逐位不变、4096 m 下 1025 / 513、
两种格距在三种尺寸下自洽、细栅格 1050625 节点、`Pathfinder.max_expand` 在两种尺寸下都等于 `res²`
（即"展开上限按尺寸推导，不会截断合法路径"这条承诺有断言兜着）。

**一个顺手纠正的记账错误**：门禁的项数不是固定 26 —— `性能基准 注意 有 N 条 WARN` 那行是
**额外追加**的一条（超软容差但不判失败时才有）。§16.1 的 26 项是那一跑恰好带了 WARN 行，
真实步骤数是 25。脚本头部已改回「25 项」，并注明"性能超软容差时会多一行注意"。**别把某一跑的
行数当成脚本的固有常量** —— 这类数字最容易被抄进文档之后就再也没人核对。

**验收（2026-10-14）**

| 项 | 结果 |
|---|---|
| 一键门禁 | **exit 0，25 个步骤全绿，用时 71.9 s**（本次跑性能带 1 条 WARN ⇒ 汇总显示「26 项」；同一脚本前一跑无 WARN 时显示「25 项」—— 这就是上面那条记账错误的现场） |
| 生成指纹 | `d68cb1d2c0c2acae…` **与基线一字不差**（本批在 1024 m 下行为中性） |
| `scale_probe` | PASS：A* 展开节点合计 fine 1143 / coarse 5184 与基线一致（栅格没变，搜索当然也没变） |
| `map_size_check` | 57 项断言全过，并打印 4096 m 的栅格与内存量级（细栅格 ≈15.8 MB） |
| 生成统计 | 定居点 18 / 桥梁 7 / 植被 5163（未变） |

### 16.4 第 ③ 批前置：换世界之前先量一遍（`big_map_probe`）—— 结论把 ③b 的计划改了
§15 第 3 步原本的假设是「6b 单遍筛选 + 4096 m 一起做，只付一次重基线成本」。动手前先按 §12.6 的
态度量了一次：**用生产代码**（`Main.tscn` + `WorldGenPipeline`，只在运行期把 `cfg.map_size` /
`heightmap_res` 换成 4096 / 2049）真建了一个 4096 m 世界，并把同一套测量在 1024 m 下重跑一遍做
同口径对照。新工具：`tools/big_map_probe.gd`（`-- --size=1024` 可切尺寸；门禁步骤 7d，**默认跳过**，
`$env:WARBAND_BIG_MAP=1` 才跑 —— 它一次要 80~120 秒）。

配套加了一个**只在需要时才说话**的钩子：`WorldGenPipeline` 的阶段计时，`WARBAND_STAGE_TIMING=1`
或 `-- --stage-timing` 打开。默认关闭，因为多出来的行会破坏「被工具解析的输出」的既有格式
（`log_check` 正守着这条约定）。没有它，「83 秒花在哪」就只能猜。

**阶段实测（同口径，两次跑都是同一台机、同一份代码）**

| 阶段 | 1024 m / 513² | 4096 m / 2049² | 倍数 |
|---|---|---|---|
| **地形高度场** | **3714 ms** | **58401 ms** | **15.7×** |
| 　└ 噪声采样（`_build_heights`） | 1215 ms | 19609 ms | 16.1× |
| 　└ 生物群系（`_build_biomes`） | **2321 ms** | **36324 ms** | 15.7× |
| 　└ 两次模糊 | 143 ms | 2281 ms | 16.0× |
| 植被筛选 / 发射 | 943 ms | 14544 ms | 15.4× |
| 寻路栅格（细+粗+道路） | ~290 ms | 4664 ms | ~16× |
| 道路网（A* 修路 + 架桥） | ~180 ms | 3400 ms | ~19× |
| 定居点选点 | ~90 ms | 1565 ms | ~17× |
| 烘焙地表 / 小地图 | ~80 ms | 1311 ms | ~16× |
| **生成总计** | **5481 ms** | **82268 ms** | **15.0×** |

**每采样点成本两边一样**：13.91 µs/点（4096）vs 14.11 µs/点（1024）—— 也就是**完全线性、没有超线性的
坑，也没有缓存悬崖**，纯粹是「采样点 ×16，常数太大」。所以「83 秒」不是一个可以靠微调糊过去的数。

**这次测量直接改掉了 ③b 的主体**：原本以为主体是「6b 单遍植被筛选 + 换世界」，实测下来
**高度场一个人就占 71%**（58401 / 82268 ms），而其中**生物群系一声不响占了 44%**（36324 ms，比
「噪声 + 模糊」加起来还多一倍）—— 这一项在 §12.5 清点表里根本没被点过名（清点表当时盯着植被的
16× 采样、寻路栅格的 105 万节点）。逐项看，`_build_biomes` 每点 8.8 µs：每点一次 `hm.slope_at`
（内部就是 4 次双线性 `height_at`）+ 5 次 FBM 噪声（`n_rock`×2 / `n_moist` / `n_forest`×2）+ 若干
`smoothstep`。**6c 在地形分块上做过的那件事（「每顶点 4 次 height_at」换成「用已算好的网格做中心差分」）
在这里完全没做** —— 这就是 ③b 的第一刀。

**其余实测事实（③b 的输入）**

| 项 | 1024 m | 4096 m | 说明 |
|---|---|---|---|
| 植被实例 | 5163 | **8420** | 4096 下**五类全部顶到 `target`**（2600/3200/700/420/1500 之和恰为 8420）；1024 下五类都低于 target |
| 植被区块 | 67 | **729** | 分块 256 m 没跟尺寸走 → 16×16 桶 × 5 类 |
| 每平方公里实例数 | 4919 | **501** | 密度掉到 1/9.8（同一份 target 摊到 16× 面积上） |
| 桥梁 | **7 座**（桥格 173） | **0 座**（桥格 0） | 道路都是 21 条、渡口格都是 92、18 个定居点都落在 1 个连通分量里 → **只差地图边长 ×4，架桥就整个失效** |
| 水格占比 | 28.9% | 26.3% | 地形形状量级一致（噪声按世界米采样） |
| 河道格数 | 1688 | 5311 | ≈4×（河数不变、河长 ×4、河宽按格固定） |
| 定居点包围盒 / 最近邻中位 | 754 m（74%）/ 71 m | 2083 m（51%）/ **73 m** | 「最近邻」在米上是同一个数 ⇒ 选点用的最小间距是绝对值，没出 bug；但 18 个定居点摊到 16× 面积上就是「一平方公里 1 个」的量级，属**玩法尺度决定**，不是缺陷 |
| 地形分块 | 128 m × 64 块，LOD0 单块 1601 顶点 | 256 m × 256 块，LOD0 单块 5249 顶点 | 与 §16.2 的推导**逐项吻合**（这次是真建出来量的，不是纸上推的） |
| 栅格重建 | 细 257² 232 ms / 粗 129² 54 ms | 细 1025² 3041 ms / 粗 513² 780 ms | 105 万节点 ≈3 秒，可接受但别在一帧里做两次 |
| A*（各取前 4 对相邻定居点） | 细 4.0 ms / 粗 1.2 ms | 细 7.6 ms / 粗 2.8 ms | 这些对都是「直线可达」（2 个路径点、走 = 直），**说明不了 105 万节点下的最坏情况**；真要判定得等换世界后用 `scale_probe` 的固定 12 对 |

**A* 那一行要特别小心**：探针取的 4 对是「数组里相邻的定居点」，4096 m 下它们的直线距离只有
99~244 m（18 个定居点里有一半成对贴着），所以 2 个路径点、展开一百多是**正常结果**，不是
「A* 坏了」，更不能拿它证明「4096 m 下寻路很便宜」。这正是「先量」也要量对地方的反面教材 ——
探针自己把「取样方式」印在报告里（并标注基线不可直接比），就是为了防止这种误读。

**③b 的计划因此重排**（原计划：6b 单遍筛选 + 换世界 + 一次重基线）

1. **③b-1 高度场提速**（新增，且升为第一优先）：先把 `_build_biomes` 的 `slope_at` 换成网格中心差分
   （照 6c 的做法），再看要不要把低频遮罩（`land_mask` / `desert_mask`）改成粗网格 + 双线性上采样，
   最后才考虑多线程。目标是把 13.9 µs/点压到 5 µs/点以内 —— 每压 1 µs，4096 m 就省 4.2 秒。
2. **③b-2 植被**：6b 单遍筛选 + `CELL` 按尺寸推导（否则光是它 14.5 秒）+ `CHUNK` 按尺寸推导
   （729 个 MultiMeshInstance3D 不是设计，是分块没跟着走）。
3. **③b-3 换世界 + 一次重基线**：等前两项把 83 秒压到大图可接受（目标 < 20 秒）之后再切
   `map_size = 4096`，同时解决「桥梁 0」与「定居点密度」这两个**内容**问题，然后一次性重基线。

**为什么把「桥梁 0」记在 ③b 而不是现在就修**：现在改的话，1024 m 世界的 7 座桥会跟着变，
指纹与规模基线全要重来 —— 而那时 ③b-2 的单遍筛选还会再翻一次布局。**同一件事不要在两次
重基线里各付一遍**；先把「为什么 4 倍尺度下架桥判定会失效」查清楚（候选：`RoadNetwork` 的过河
判定或展开预算带尺度相关阈值），跟换世界一起改、一起重基线。

**验收（2026-10-14）**

| 项 | 结果 |
|---|---|
| `big_map_probe`（4096 m） | exit 0，31 项数字，`PASS`：生成 82.3 s / 高度场 56.5 s / 植被 14.5 s / 栅格 3.0 s |
| `big_map_probe --size=1024` | exit 0，31 项数字，`PASS`：生成 5.48 s，与现网世界逐项一致（植被 5163、区块 67、桥 7） |
| 阶段计时 | 默认关闭；开 `WARBAND_STAGE_TIMING=1` 时才打印（不破坏工具解析格式） |
| 一键门禁 | **exit 0，25 个步骤全绿**（本批没动任何生产行为，7d 默认跳过） |

### 16.5 ③b-1a：高度场第一刀（网格坡度替换）—— 1024 m 下 `_build_biomes` 砍掉一半，指纹一字未动

§16.4 把 83 秒里的 44% 钉在了 `_build_biomes` 上。这一批专门砍它，并且**只砍一个点**：
`_build_biomes` 每采样点调一次 `hm.slope_at(wx, wz)`，而那个 `wx` **正好落在高度图网格点上**
（`wx = float(x) * hm.cell`）。

**为什么能换、而且逐位相同**：`slope_at` → `normal_at` → 4 次 `height_at`；`height_at` 在采样点
正好落在网格上时，双线性权重 tx = tz = 0，返回的就是该点自己的数据。于是「±1 格中心差分」与
「±cell 双线性」拿到的是**同一批数字**，后面 `Vector3(...).normalized()`、`clampi`、`clampf` 也是
同一串运算 —— 省掉的只有插值本身。新增 `Heightmap.grid_slope(x, z)` 就是这件直白的事。

它必须逐位相同，因为坡度喂给 `forest_mask` / `biome_rock` → 植被密度与岩石掩码 → **世界布局**。
`tools/map_size_check.gd` 因此加了 4 条断言（57 → 61）：两种尺寸下都先钉前提「cell 精确等于 2.0」
（`map_size / (res-1)`，本项目恒为 2.0），再拿一张同 cell 的 65² 图把**所有**采样点（含 x/z = 0 与
res-1 那圈靠 clampi 折回的边界）与 `slope_at` 逐个 `!=` 比一遍。真实世界那一侧由**生成指纹不变**兜底。

**A/B 实测（1024 m / 513²，同一进程交替跑 3 轮，看的是管线自己的 `[高度场]` 行）**

| 分件 | `slope_at`（改造前） | `grid_slope`（改造后） | 变化 |
|---|---|---|---|
| 生物群系 | 1388 / 1342 / 1316（均值 **1349**） | 651 / 655 / 698（均值 **668**） | **−50%** |
| 噪声 | 674 / 717 / 673（均值 688） | 673 / 641 / 685（均值 666） | 没动（本来就与坡度无关，这行是「没伤到别处」的对照） |
| 高度场阶段 | 2183 / 2205 / 2088（均值 **2159**） | 1422 / 1395 / 1487（均值 **1435**） | **−33%** |

**4096 m 前后对照（两边都是「管线自己的第一次调用」，位置一致）**

| 阶段 | 改造前 | 改造后 | 变化 |
|---|---|---|---|
| 地形高度场 | 56518 ms | **40678 ms** | −28% |
| 　└ 生物群系 | 36324 ms | **19925 ms** | **−45%** |
| 　└ 噪声采样 | 19609 ms | 18294 ms | −7%（这行没改代码，属跑与跑之间的波动，不记为战果） |
| 　└ 两次模糊 | 2281 ms | 2275 ms | 持平 |
| 植被筛选 / 发射 | 14544 ms | 14202 ms | 持平 |
| 寻路栅格 | 4664 ms | 4602 ms | 持平 |
| 道路网 | 3400 ms | 3206 ms | 持平 |
| 定居点 | 1565 ms | 1423 ms | 持平 |
| 烘焙 | 1311 ms | 1286 ms | 持平 |
| **生成总计** | 82268 ms | **65679 ms** | **−20%** |

改造后 4096 m 的账本变成：高度场 40.7 s（62%）、植被 14.2 s（22%）、栅格 4.6 s、道路 3.2 s、
定居点 1.4 s、烘焙 1.3 s。**高度场仍然是头号，但它从「一个没人预料到的黑洞」变成了「两个可以
分别处理的大块」**：生物群系 19.9 s + 噪声 18.3 s。
按 §16.4 立的那把尺子算，每采样点成本 **13.91 → 9.69 µs/点**（4 198 000 点），离那一段定的 5 µs/点
还差一半 —— 下一刀（并行）正是冲着这个差值去的。

**门禁侧还有一个旁证**：`gen_fingerprint` 这一项自己的用时从 6.3 / 7.1 s 掉到 5.6 / 5.5 s ——
它每跑一次就建一个 1024 m 世界，正好等于上表 1024 m 那一刀（≈0.7 s）。整跑 70.4 s → **62.0 s**。

**这一批修掉的一个「测量工具本身有问题」**：上一批的探针是在世界建好之后**把 `generate()` 的顺序
重写一遍**来分件的。这次换完坡度就露馅了 —— 同一份代码，管线自己的阶段值 1512 ms，复测值 2707 ms
（1.8×），而且**六个分件一律慢 1.8~1.9 倍，包括这次一行没碰的噪声与模糊**。也就是说那个倍数来自
**机器状态（进程内的第一次调用 vs 后段调用，CPU 降频）**，不是代码差异；拿它做前后对比就会得出
「生物群系只剩 90 ms」这种自相矛盾的结论。
修法不是调参数，而是**让分件从生产路径里流出来**：`HeightmapGenerator.generate(timing := false)`
自己在原地给六件计时（默认 false，一个字都不多打；管线在 `WARBAND_STAGE_TIMING=1` 时传 true），
于是分件之和**必然等于**那一阶段的耗时，没有跨路径对不上的余地。探针改成直接调 `generate(true)`，
不再重写那段顺序。**A/B 一律交替跑或同位置跑** —— 这一批的结论就是这么得出的。

> 顺带更正 §16.4 表里的一个数字出处：那张表 4096 m 的「高度场 58401 ms」用的是**探针复测的和**，
> 管线自己的阶段值其实是 56518 ms。结论（高度场占 ~70%、生物群系是最大单项）不受影响，
> 但数字该来自哪条路径，到这里才算说清楚。

**③b-1 还剩什么**：高度场 40.7 s 里，生物群系 19.9 s + 噪声 18.3 s + 模糊 2.3 s。第一反应是把这两个
**每采样点独立**的循环并行掉（噪声对象只读、各点只写自己的下标 → 调度顺序不影响任何一个点的值，
指纹仍能当证据）。**实测这条路是负的**，见下面 §16.6；所以剩下的手段只能是**减少采样点数**或
**减少每点运算**，两者都会改世界，一律留到 ③b-3 与换世界、重基线一起做。

**验收（2026-10-14）**

| 项 | 结果 |
|---|---|
| 一键门禁 | **exit 0，26 行全 PASS，62.0 s**（改造前同一脚本 70.4 s） |
| 生成指纹 | `d68cb1d2c0c2acae…` **与基线一字不差**（逐位中性，不需要重基线） |
| `map_size_check` | 61 项断言全过（新增 4 条 `grid_slope` 逐位等价，含边界） |
| `scale_probe` | PASS：结构量与 A* 展开节点与基线一致 |
| 4096 m 阶段计时 | 总计 82.3 s → **65.7 s**；高度场 56.5 s → **40.7 s**（生物群系 36.3 s → 19.9 s） |










### 16.6 ③b-1b：并行化实测为负 —— 两个循环都更慢，已回退（顺带保留两处逐位不变的提级）

顺着 §16.5 的想法，把 `_build_heights` 与 `_build_biomes` 改成 `WorkerThreadPool.add_group_task`
按**行区间**分派（`OS.get_processor_count()` = 20 → 20 个任务，每任务约 `res/20` 行）。
共享写入的边界写死在注释里：① 每个任务只写自己的行区间；② 目标要么是本对象自己的成员
（`biome_*` / `forest_mask`），要么走 `hm.set_h()`；③ 所有目标在任务开始前 resize 完毕；
④ 只读的 `hm.data` 才允许取局部别名。**正确性没问题** —— 生成指纹 `d68cb1d2c0c2acae…` 一字未动。

但**速度是负的**，两种尺寸都是：

| 尺寸 | 分件 | 串行（§16.5 实测量级） | 并行 | 结论 |
|---|---|---|---|---|
| 1024 m | 高度场阶段 | 1422 / 1395 / 1487（A/B 三轮） | **2411 ms** | 慢 68% |
| 1024 m | 　└ 噪声 | 673 / 641 / 685 | 954 ms | 慢 43% |
| 1024 m | 　└ 生物群系 | 651 / 655 / 698 | 1303 ms | 慢 95% |
| 4096 m | 高度场阶段 | 40678 ms | **43578 ms** | 慢 7% |
| 4096 m | 　└ 噪声 | 18294 ms | 17643 ms | 持平（本来就没改它） |
| 4096 m | 　└ 生物群系 | 19925 ms | 23480 ms | 慢 18% |

**怎么读这张表**：噪声那件在 4096 m 基本持平、生物群系一致变慢，而且 1024 m 连**纯计算**的噪声件都比
串行慢 43% —— 说明瓶颈不在「单核算力」，而在**被所有线程共享的东西**上：GDScript 每采样点要做
Variant 噪声调用与 Packed 成员写入，这些在 VM / 分配器 / 内存子系统上的开销不会因为多开线程而变小，
反而要再付一份任务分派与 join 的钱。「这个循环看起来是可并行的」与「并行能在这里变快」是两件事，
中间隔着引擎的执行模型。**这条负面结论写下来就是为了不再重走** —— 除非先有证据说明瓶颈换了
（比如哪天这些循环改成了纯 `PackedFloat32Array` 数值运算），否则不要重复。

回退时**保留**了两处与并行无关、逐位不变的提级：`hm.cell` 与只读的 `hm.data` 都提到行外，
省掉每个采样点的跨对象成员读取（收益小，但方向确定）。回退后实测 1024 m 高度场
**1525 / 1558 ms**、指纹不变。

**对 ③b-1 计划的改写**：同精度、同采样点数的加速到此为止（网格坡度那一刀已拿走 −28%）。
4096 m 的高度场要再降，只能从**采样点数**下手：

- **`heightmap_res` 在 4096 m 下取 1025（4 m 采样）**。这不是「为了快牺牲精度」：§16.2 已经把地形
  网格顶点间距按尺寸推导成 4 m，也就是说 2049² 的高度图相对网格**本来就是 2× 过采样**。
  改成 1025² 是「高度图与网格同分辨率」，采样量 4× 下来，按 9.69 µs/点 估 **40.7 s → ~10.2 s**。
- 低频遮罩粗网格化（`land_mask` / `desert_mask` 每点都在算 smoothstep 与噪声）留作备选，
  改数值、收益也小。
- 两项都**会改世界**，按 §16.4 的纪律并入 ③b-3，与换世界一起**只重基线一次**。

**验收（2026-10-14）**

| 项 | 结果 |
|---|---|
| 结论 | 并行版**不保留**（两种尺寸都更慢）；回退并保留两处提级 |
| 并行的正确性 | 指纹 `d68cb1d2c0c2acae…` 一字未动（负的是速度，不是数值） |
| 回退后 1024 m | 高度场阶段 **1525 / 1558 ms**（串行 + 网格坡度一档），指纹与基线一致 |
| 4096 m 参照 | 并行版 43578 ms 弃用；回退到 40678 ms 那一档（代码只差两处提级，未重测） |
| 一键门禁 | **exit 0，25 项全 PASS，用时 63.4 s**（这次性能基准没带 WARN；带 1 条 WARN 时汇总显示 26 项） |

