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

> 工具链注意：本工作区位于 **exFAT** 卷（`F:`，卷标 T7），**不支持硬链接**，因此依赖硬链接式原子写的写文件工具会报 `EISDIR`。新建文件请用 `Set-Content -Encoding utf8`，改已有文件用逐处替换式编辑（rename 在 exFAT 上正常）。

---

## 二、已确认缺陷清单

每条都经回读代码验证。`轮次` 列指出在第五节哪一轮处理。

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
| G3 | **无 `InputMap`**：键位硬编码；零 `grab_focus()` / `focus_neighbor` → 遭遇框键盘 / 手柄无法作答 | `Main.gd:585-599`、`BattleScene.gd:235-260` | 三 |
| G4 | **无音频总线**：仅 `Sfx.gd:56` 一处 `bus = "Master"`，零 `AudioServer` 调用 | 无 `default_bus_layout.tres` | 五 |
| G5 | **无回归测试**：三个 tools 只打印不比对；README 的「单一种子可复现」承诺零验证 | `MapConfig.gd:83-88` 依赖 `hash(str)` | 二 |
| G6 | 无主菜单 / 设置 / i18n / CI / `export_presets.cfg` / 版本号 | `project.godot:19` 主场景直指 Main | 三 / 六 |

### 2.3 次要问题（记录备查）

- `DayNightCycle.gd:96` 三元表达式两分支相同（注释声称 `night_glow` 与 `night_amount` 不同），且 `DayNightCycle.gd:182-183` 每帧把两者赋成同一个值 ——「两套夜间曲线」的设计没落地，注释误导。第一轮顺手修正注释与死分支。
- `AIParty.gd:30-31` `rng.seed = p_seed` 紧接被 `rng.state = ...` 覆盖，seed 那行是死代码。
- `sfx_battle_check.gd:22` 的 `KEY_IDS` 里 `"land"` 重复两遍；另有 5 个音色（`proj_impact` / `parry_reflect` / `battle_start` / `result_lose` / `ui_back`）从未被任何自动检查断言。
- `PlayerParty.set_destination` 在无路径时静默 `return`（`PlayerParty.gd:72-73`），玩家点不可达位置**没有任何反馈**。
- 死代码清单（第一轮清理）：`HUD._hover_label`、`Main._label_base`、`VegetationScatter._flags` / `_flag_res`、`CameraRig.pitch_manual` / `prev_diff`、`MapData.party_positions`、`PartyBase.remaining_distance()`。
- `terrain.gdshader` 的 `lod_fade` 只用作 `mix` 权重，远场仍全量计算 `vnoise`（约 11 次/片元）。
- `proj_impact` 是 28 个音色里**唯一没有任何 `Sfx.play*` 调用点**的（其余 27 个都能在代码里找到调用处）——要么补上「抛射物命中」音，要么删掉这个音色（可省约 1/28 合成耗时）。
- 自检覆盖缺口：`battle_start` / `parry_reflect` / `result_lose` / `ui_back` 有真实调用点，但两个自检脚本的剧本都触发不到。现已在 `sfx_battle_check.gd` 里以「提示」形式打印（不做断言），第二轮的回归脚本应补上开战 / 弹反抛射物 / 战败 / 界面返回四个场景。
- 迷雾叠加语义**已确认不是 bug**：`FogOfWar` 的 A 通道 = 1 − 已探索度，`MinimapView.gd:37` 用 `Color(0.02, 0.02, 0.06, 1.0)` 去调制它，效果就是「按迷雾浓度给底图压暗」；R 通道（已探索度）目前是留给 Shader 的冗余信息。
- `Main.gd:614` 的注释声称「战略视图里定居点标签再放大一档」，但 `_on_strategic_changed()` 只打了一条日志 —— 注释与实现不符（而且改动前每帧的 `_update_label_scale()` 会立刻覆盖任何手工放大，等于这条设计本来就落不了地）。属待实现功能。
- HUD 其余装饰面板（`_panel()` 返回的 `PanelContainer` 默认 `MOUSE_FILTER_STOP`）同样会吞掉其覆盖区域的左键：第一轮只修了小地图外框，左侧信息面板 / 左下操作说明建议在第三轮随 `HUD.gd` 拆分一起改成 IGNORE。
- `DayNightCycle._apply()` 每帧仍会写 `sky_mat` / `env` / `sun` 的十余个属性 —— 这些确实随时间连续变化，属于正常开销；若将来昼夜成为热点，可再按「天色量化 + 插值」优化。

---

## 三、玩法扩展路线图

判断标准：**能不能形成「打 → 赚 → 变强 → 打更强」的循环**，而不是「能不能加更多特效」。

### 阶段 1：闭合核心循环（优先级最高）

1. **`CampaignState` 战役状态层**（新文件，Resource，可序列化）：钱 / 粮 / 士气 / 声望 / 天数 / 势力关系。
   落点：`Main.gd:769-773` 的 `spoils` 真正入账。**这是所有玩法扩展的地基。**
2. **城镇 / 村庄交互面板**：进城 → 招募（扣钱 + 消耗村庄人口）/ 补给 / 交易 / 打听情报（揭示附近部队）。
   可复用：`Settlement.gd` 已有 `garrison` / `parent_town` / `neighbors`；`HUD.gd` 的 Panel 构建代码与 `NameForge.gd` 可直接用。
3. **遭遇选项 2 → 5~6 个**：攻击 / 撤退 / 要求通行费 / 劝降（按兵力差与士气判定）/ 贿赂 / 追击。
   落点：`Main.gd:535-537` + `_on_encounter_choice`，做成选项表数据驱动。**单点改动即可显著提升策略密度。**
4. **战斗结果真正影响战略层**：现在只有兵力增减（`Main.gd:770`）。加声望（打强盗 +、打商队 −）、领主关系、势力通缉度。
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

- **B-1 拆 `Main.gd`（818 行 / 21 段职责）** → `WorldGenPipeline`（只碰 RefCounted，天然可无头单测）/ `MaterialFactory` / `PartySpawner` / `TimeFlowController` / `EncounterSystem`（只发信号）/ `BattleLauncher` + `EncounterRules`（数值进 Resource）/ `OverworldView` / `HoverInspector` / `InputRouter` / `GameState`。目标 Main ≈ 200 行。
  顺带消除：玩家初始兵力 **37 硬编码两处**（`Main.gd:278,280`）、部队类型中文名表**重复三份**（531 / 640 / 642）、`set_meta("player_ref")` 弱类型侧信道（`Main.gd:281` → `AIParty.gd:58`）。
- **B-2 拆 `HUD.gd`（323 行 / 9 件事）** → LoadingOverlay / TopBar / EncounterDialog / TransientMessages / DebugStatsPanel + `Theme.tres`。**性价比最高的重构**，也是引入 `.tscn` 的最佳落点（3D 与特效继续代码构建）。
- **B-3 类型化**：`TerrainManager._chunks` 的 Dictionary → 内部类 `Chunk`；`MapData` 拆 `WorldGenResult` / `WorldQueries` / `RuntimeRefs`（typed，替掉 `set_meta`）；统一 RNG 派生入口（现在 `MapConfig.make_rng`、`AIParty` 的 seed+state、`Main.randi_range_seed` 三套并存）。
- **B-4 引入 `InputMap` + 输入路由**：一举解决手柄支持、键位重映射、遭遇框键盘无法作答（G3）。

### C 节 · 性能与规模（按需，取决于要做多大）→ 第六轮

- **植被**：单遍筛选（**注意会改变现有种子的布局语义**，需显式决定是否接受）→ 估算生成 −60%~70%；实例发射改 `RenderingServer.multimesh_set_buffer` 批量写 → 估算 5~15×；桶尺寸 128 m → 256 m。
- **地形**：`_apply_lod` 把「缓存命中」提到预算判断之前（缓存切换本该免费）；按距离排序建块；法线用本地高度差分替代每顶点 4 次 `height_at`（**每顶点 5 次采样 → 1 次**）；LOD2/3 关阴影。现状每 0.25 s 允许建 2 块、单块 3~6 ms → 尖峰 5~10 ms。
- **A\***：把 `blocked` / `speed` / `res` 提到局部变量并内联邻居判定（省每邻居 1~3 次脚本方法调用，**本体 2~4×**）；全局寻路请求队列 + 每帧预算；长距离用「道路骨架拓扑 + 首尾各一段栅格 A*」（HPA* 思路）。
- **4096 地图前置条件**：所有写死分辨率必须与 `map_size` 绑定 —— `nav_fine = 257`（`Main.gd:100`，4096 图下变 15.9 m/格，比道路还宽）、`SPLAT_RES = 512`、`MINIMAP_RES = 256`、`MapData.TERR_RES = 128`、`FogOfWar.RES = 128`，以及 `MapTextureBaker.gd:55` 硬编码的 460 m 领地半径。**不绑定的后果是功能静默失真（道路消失、迷雾糊化），比崩溃更难查。**
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
| 第二轮 | `tools/gen_determinism_check.gd` + 性能基准 + 无 ERROR 断言（先立安全网，再谈重构） | 待办 |
| 第三轮 | 拆 `Main.gd` + 拆 `HUD.gd` + 引入 `InputMap` | 待办 |
| 第四轮 | 玩法闭环：`CampaignState` 经济 + 城镇交互 + 遭遇多选项 + 存档 | 待办 |
| 第五轮 | 音频总线 + PCM 缓存 + 合成热点 + BGM 接口 | 待办 |
| 第六轮 | 规模扩展（植被 / 地形 / 寻路）+ i18n + 导出预设与 CI | 待办 |

> 第四轮之后按「内容产能」推进：小兵单位 → 武器招式表 → 势力战争。

---

## 六、验证方式（可复现命令）

```powershell
$GODOT = "G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe"
$PROJ  = "F:\aigc_code\ai_godot_projects"

# 1) 主场景完整跑一遍（看是否有 ERROR / 生成耗时 / 生成内容统计）
& $GODOT --headless --path $PROJ --fixed-fps 60 --quit-after 900

# 2) Boss 战音效联调（exit 0 = 关键音效全部触发）
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/sfx_battle_check.gd
# 3) 大地图音效联调
& $GODOT --headless --path $PROJ --fixed-fps 60 --script res://tools/sfx_map_check.gd
# 4) 音色体检（含总合成耗时）
& $GODOT --headless --path $PROJ --script res://tools/sfx_tool.gd

# 5) 代码规模（不要用 Measure-Object -Line，会漏算空行）
Get-ChildItem -Recurse -File -Include *.gd,*.gdshader |
  ForEach-Object { [pscustomobject]@{ L = (Get-Content $_.FullName).Count; P = $_.FullName } } |
  Sort-Object L -Descending
```

**判定标准**：① 主场景无 `ERROR` / `SCRIPT ERROR`；② 两个联调脚本 `exit 0` 且输出 `PASS`；③ 生成内容统计（定居点 18 / 桥梁 7 / 植被 5163）与基线一致，说明没有破坏确定性。

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
