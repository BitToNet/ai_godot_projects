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
| 第四轮 | 玩法闭环：`CampaignState` 经济 + 城镇交互 + 遭遇多选项 + 存档 | 🔄 **进行中**：4a 经济（钱袋 / 军费 / 士气 / 战利品 / HUD）已完成并通过门禁，见第十节；4b 城镇交互、4c 遭遇多选项、4d 存档待办 |
| 第五轮 | 音频总线 + PCM 缓存 + 合成热点 + BGM 接口 | 待办 |
| 第六轮 | 规模扩展（植被 / 地形 / 寻路）+ i18n + 导出预设与 CI | 待办 |

> 第四轮之后按「内容产能」推进：小兵单位 → 武器招式表 → 势力战争。

---

## 六、验证方式（可复现命令）

```powershell
$GODOT = "G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe"
$PROJ  = "F:\aigc_code\ai_godot_projects"

# 0) 【推荐】一键跑完全部门禁（9 步 / 13 项断言，约 40~50 秒）—— 本工程唯一需要的命令
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

# 4b) 输入层回归（[input] 动作表是否真进了 InputMap / InputRouter 分发与让路 /
#     遭遇框能否用键盘与手柄作答）—— 「按了没反应」这类问题以前只能点开游戏按一按
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/input_check.gd

# 4c) 经济定式（军费 / 士气 / 编制 / 招募 / 撤退代价的公式形状 + 42 天收支时间轴）
#     —— 这条回路（工资→欠薪→士气→逃兵→兵力→工资）在 900 帧里连一天都跑不完
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/economy_check.gd

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
| 9 | 城镇菜单 / 遭遇面板选项 / 城堡被价格归一化跳过 / 村庄 ×5/4 等原版怪癖 | 菜单条目与选项**【未解】**；怪癖是【实证】 | 怪癖记入 10.5，留给 4b 参考；菜单与选项 4b / 4c 作为**显式设计决策**实现 |

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
- **4d 存档**：`CampaignState` + 玩家位置 + `day_night` 状态序列化。
- **经济平衡的已知短板**：匪帮被清光后不会再生（`PartySpawner` 只在开局生成），
  一旦地图上 12 支匪帮全灭，收入就只剩商队与领主 —— 需要一条「匪帮再生 / 商队贸易」的
  持续收入线，候选放进第五轮。
- 第四轮的**城镇交互还需要一个 InputMap 动作**（进城交互键）：加动作后必须同步扩
  `tools/input_check.gd`，否则门禁里那条「动作表 ↔ InputMap 一致」的断言会红。