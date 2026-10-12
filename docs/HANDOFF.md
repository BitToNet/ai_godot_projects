# 交接状态卡（可续跑的最小状态）

> 用途：把「继续这个项目所需的最小事实」压缩到一页。上下文被压缩 / 换会话后先读本文件，
> 完整计划与台账读 `docs/ROADMAP.md`。本文件只记录**当前状态与硬约束**，不重复路线图内容。
> 每次收尾时更新第 4/5 节。

## 1. 仓库与引擎

- 工程：`F:\aigc_code\ai_godot_projects`（Godot 4.7 stable / GDScript / Forward+ / 1600×900 canvas_items）
- 引擎（全局规则 2，**不要另找、另下、另装**）：
  `G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe`
- 主场景 `scenes/Main.tscn`（`project.godot` 主场景直指 Main），全部 UI 由代码构建
- 分支 `main` → `origin/main`；`.githooks/post-commit` 自动推送（`GIT_AUTO_PUSH=0` 可临时豁免）
- 世界生成唯一入口：`map_seed = 20250929`（`MapConfig`），`MapConfig.make_rng(tag)` 派生各阶段随机流

## 2. 硬约束（违反即返工）

- **禁止访问 `I:\` 与 `J:\`**（用户全局规则 1，含 shell / 子代理 / MCP 等一切间接路径）
- **不得改变地图生成的 RNG 抽取顺序**：定居点 18 / 桥梁 7 / 植被实例 5163 是回归基线；
  改动若使这些数字或生成指纹变化，必须是有意为之并在提交信息里说明
- `F:` 是 **exFAT**（不支持硬链接）：`write` 类原子写工具会报 `EISDIR` —— 新建文件先 shell 建占位再逐处替换
- 提交信息文件**必须无 BOM** 写入（`[System.IO.File]::WriteAllText($p,$t,(New-Object System.Text.UTF8Encoding($false)))`），
  否则 commit subject 首字节是 `EF BB BF`；中文提交一律 `git commit -F <文件>`
- 只 `git add` 本轮路径（G5）；`.godot/` 永不入库

## 3. 验证命令

```powershell
$G = 'G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe'
$P = 'F:\aigc_code\ai_godot_projects'
powershell -File tools\run_checks.ps1      # 【首选】一键跑完全部门禁（9 项，约 45 秒）
#    ⚠ 是 powershell 不是 pwsh —— 本机只有 Windows PowerShell 5.1，没有 pwsh 7
& $G --headless --path $P --fixed-fps 60 --quit-after 900            # 主场景：必须 exit 0 且无 ERROR
& $G --headless --path $P --fixed-fps 60 --script res://tools/sfx_battle_check.gd
& $G --headless --path $P --fixed-fps 60 --script res://tools/sfx_map_check.gd
& $G --headless --path $P --fixed-fps 60 --script res://tools/gen_fingerprint.gd
& $G --headless --path $P --fixed-fps 60 --script res://tools/perf_probe.gd
```

计数注意：统计行数用 `(Get-Content $f).Count`，**不要**用 `Measure-Object -Line`（漏算空行约 10%）。

**PowerShell 5.1 编码三坑**（都已在 `run_checks.ps1` 头部注释里写明，改脚本前先读）：
1. `.ps1` 必须存成**带 BOM 的 UTF-8**，否则中文注释按系统 GBK 解码 → 直接语法报错。
   在本仓库里 `edit` 工具会**剥掉 BOM**，所以每次改完 `.ps1` 都要补回：
   `[System.IO.File]::WriteAllText($p,[System.IO.File]::ReadAllText($p,(New-Object System.Text.UTF8Encoding($false))),(New-Object System.Text.UTF8Encoding($true)))`
2. `Get-Content -Raw` 读 Godot 写出的**无 BOM** JSON（`gen_fingerprint.json` / `perf_baseline.json`）
   会乱码并使 `ConvertFrom-Json` 失败 —— 表现为基线被静默读成 `0/0/0`。必须显式按 UTF-8 读。
3. 原生命令只要往 stderr 写一个字节，PS 5.1 就包成含 `FullyQualifiedErrorId : NativeCommandError`
   的 ErrorRecord。所以 ERROR 断言只能用大小写敏感的 `ERROR:|SCRIPT ERROR|Parse Error`，
   否则 Godot 退出时的 `WARNING: N ObjectDB instances were leaked` 会把整步误判为失败。

## 4. 当前进度

- **第一轮（已完成并推送）**：A 节缺陷修复 B1–B5 / B7 + 死代码清理 + 性能项 + `docs/ROADMAP.md` 落档。
  提交：`7f5a58a`（fix）、`554bb07`（docs）。
- **第二轮（本轮完成）**：安全网落地。
  - 新增 `tools/gen_fingerprint.gd` + `gen_fingerprint.json`（逐项 SHA-256 汇总指纹，与存档比对）
  - 新增 `tools/perf_probe.gd` + `perf_baseline.json`（墙钟 `frame_ms` 口径，容差 avg 1.5 / p95 1.8）
  - 新增 `tools/run_checks.ps1` 一键门禁：9 项全绿约 45 秒；并做过**反向验证**（故意多抽一次
    随机数 → 确实变红；同时暴露了「只比 A=B」是假安全网，故补上「指纹 vs 存档」一条）
  - 顺带修掉三个真问题：`Performance.TIME_PROCESS` 在 headless 下是陈旧常数；
    `BossFighter` 用全局 `randf()` 导致战斗不可复现（新 `BattleScene.roll01()`）；
    `sfx_battle_check` 剧本连段节拍错（`hit_crit` / `parry` 从来测不到）+ 两个音色覆盖随 RNG 漂
  - 详见 `docs/ROADMAP.md` 第八节
- 第三轮及以后见 `docs/ROADMAP.md` 第五节。

## 5. 下一步（第三轮任务清单）

1. 拆 `Main.gd`（822+ 行）：生成流水线 / 相机 / 输入 / UI 装配分离
2. 拆 `HUD.gd`；顺手把其余装饰 `PanelContainer` 的 `mouse_filter` 改 IGNORE（第一轮只修了小地图外框）
3. 引入 `InputMap`，补 `grab_focus()` / `focus_neighbor`，让遭遇框能用键盘 / 手柄作答
4. 每步结束后跑 `powershell -File tools\run_checks.ps1`：纯重构**不应**改变生成指纹与生成统计

## 6. 关键数字（2026-10-12 实测，本机）

| 项 | 值 |
|---|---|
| 生成物指纹 | `19d42d358f8d5495adeb1946ad91a9a034fb878e510e309561f247bfd0d7f826` |
| 生成内容 | 定居点 18 / 桥梁 7 / 植被实例 5163（**回归基线，勿动**） |
| 地图生成耗时 | ≈ 5.4–6.1 s（本轮实测 29 帧跑完；首轮记 8.1 s —— 随机器负载波动，别当硬指标） |
| 性能基线（idle） | `frame_ms` avg 0.847 / p95 5.995 / max 13.485；nodes 446；static 128.85 MB |
| 性能基线（行军） | `frame_ms` avg 1.100 / p95 6.057 / max 16.179；static 129.24 MB |
| 门禁全绿耗时 | ≈ 42–46 s（9 项） |
| 音效 | 28 音色 / 24 路播放池，合成约 1.5–1.7 s |
| 代码规模 | 51 个 `.gd` / 10725 行 + 4 个 shader / 369 行 |
| 最大文件 | `scripts/core/Main.gd` 822 行（第三轮计划拆分） |

## 7. 已知无害噪声 / 待查

- 工具脚本退出时偶发 `WARNING: N ObjectDB instances were leaked at exit`（改动前即存在，N 每次不同；
  根因是静态 `Sfx` 的持有链，未查）
- `sfx_battle_check` 的**播放次数**每次不同（54~62）——因为 `Sfx` 的节流用真实毫秒时间戳，而
  `--fixed-fps 60` 下帧跑得比墙钟快。**断言不受影响**（缺失集合已做到每次完全一致），别去"修"这个数字
- 自检仍未覆盖的音色：`battle_start` / `parry_reflect` / `result_lose` / `ui_back`
  （需开战 / 弹反抛射物 / 战败 / 界面返回四个场景；第二轮只补了 `hit_crit` / `parry` / `warn_danger` / `step_heavy`）
- `proj_impact` 是 28 个音色里唯一没有调用点的（要么补抛射物命中音，要么删）
- `draw_calls` 指标在 headless 下恒为 0（`Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME` 不统计），
  字段保留但无意义
- 工作区里 `icon.svg.import` 长期显示为 ` M`，但 `git diff` 内容为 0 行（`core.autocrlf=true` 的 eol 假象），
  与代码改动无关，不要顺手提交