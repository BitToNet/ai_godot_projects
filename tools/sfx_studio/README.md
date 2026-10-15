# 音效调音台（tools/sfx_studio）

浏览器里调这只游戏**全部音效**的小工具：逐条试听、拉音量、开关，存成游戏真正会读的配置，
并且留 10 条保存记录随时回滚。

它不是"另一个音效系统"，而是**给现有的 `SfxSynth`(28 条程序化音色) + `SfxFoley`(40 条录音素材)
加了一层可写覆盖**。游戏侧的读取层是 `scripts/audio/SfxProfile.gd`。

---

## 怎么开

```powershell
powershell -ExecutionPolicy Bypass -File tools\sfx_studio\start.ps1
```

它会按顺序做三件事（已就绪的步骤会跳过）：

1. 缺 `audio_preview/*.wav` 就先用 `tools/sfx_tool.gd -- --wav` 导一份试听音频
2. 跑 `tools/sfx_studio_export.gd` 生成 `manifest.json`（把代码里的音色表导成前端能读的清单）
3. 起本地服务并自动打开 <http://127.0.0.1:8787/tools/sfx_studio/>

常用参数：

| 参数 | 作用 |
|---|---|
| `-Port 8790` | 换端口（默认 8787，被占用会自动往后找最多 20 个） |
| `-NoOpen` | 不自动开浏览器（服务器照常起） |
| `-SkipExport` | 跳过前两步（清单没变时省几秒） |
| `-Engine <路径>` | 换 Godot 可执行文件（默认走全局规则 2 的 4.7 控制台版） |

**必须通过这个服务打开页面**：浏览器不允许网页读本地文件，直接双击 `index.html`
（`file://`）连 `manifest.json` 都读不到，只会看到一条提示让你去跑 `start.ps1`。
用别的静态服务器也行（`python -m http.server`），但那样"保存"只会进浏览器 localStorage，
写不进游戏的配置文件。

---

## 界面上有什么

- **逐条**：试听（▶）、音量滑杆、开关（开/关）、单条复位（↺）。滑杆右边那列 `实际` 是
  这一声**最终会以多少 dB 播出**（分类 + 基准 + 你的偏移），超过 0 dB 会标红 —— 游戏里
  Master 总线没有限幅器，正数就是有削波风险。
- **录音变体**：13 个动作类音效有多个 take（`audio/sfx/foley/*.wav`），游戏播放时随机取一个。
  点变体小标签可以单独试听某个 take。
- **分类音量**：5 个分类（打击 / 弹反 / 移动 / 人声 / 界面）各一条，叠在该分类每条音色的基准之上。
- **总音量 / 背景音乐**：总音量落 Master 总线（音乐一起听令）；两首 BGM 各有开关与偏移。
- **批量**：全部打开 / 全部关闭 / 恢复工程默认（含音量）。
- **搜索与筛选**：按 id 或中文名搜；`只看被关闭的`、`只看调过音量的`。
- **保存记录**：最多 10 条，超出自动淘汰最旧的一条；每条都带一句差异摘要
  （关了哪几条、调了哪几条、总音量动了几 dB）。点`回滚`把那一份整份套回来**并立刻写入游戏**；
  回滚本身不占记录名额，撤销回滚有一档。
- **导出 / 导入 JSON**：不想用服务、或者要把一套配置发给别人时用。
---

## 它写的到底是什么

保存 = 往 `user://sfx_profile.json` 写一份 JSON（Windows 上是
`%APPDATA%\Godot\app_userdata\Warband Strategic Map\sfx_profile.json`，页面顶部横幅里
会显示这次实际写入的绝对路径）。结构：

```json
{
  "schema": "warband.sfx_profile",
  "version": 1,
  "saved_at": "2026-10-15 12:00:00",
  "generator": "tools/sfx_studio (web)",
  "records": [ { "id": "...", "saved_at": "...", "name": "压低环境音",
                 "summary": "音量 3 条（…）；总音量 -2.0 dB", "state": { } } ],
  "undo":    { "at": "...", "state": { } },
  "state":   { "master_db": -2.0, "categories": { }, "bgm": { }, "sfx": { } }
}
```

四条规则（游戏侧一一对应，`tools/sfx_profile_check.gd` 逐条验过）：

1. **`state` 是稀疏的** —— 只有被你动过的字段才出现，没出现的照旧用工程默认。
   所以"恢复工程默认"= 什么都不写，而不是把 28 条都写成 0。
2. **`sfx.<id>.enabled = false` 是闸门**：`Sfx.play()` 会在 `_peek()` 里直接丢弃，
   **连播放计数都不加**，也不记"上次播放时刻"。这就是"关闭 = 不使用这个音效"。
3. **`sfx.<id>.db` 是偏移**，叠在"分类音量 + 音色基准"之上；分类与总音量在载入时
   写回 `AudioConfig`（总音量落 Master 总线），不逐条算。
4. **`records` / `undo` 只是历史**，游戏侧只读 `state`；`undo` 是网页端独有的单级撤销，
   游戏读到会安静忽略（有断言守着，见 9f）。

## 游戏什么时候读它

- `Sfx.setup()` 里调一次 `SfxProfile.load_into(cfg())`，**启动时读，之后不再读盘**。
  所以：在网页上保存 → 回到游戏**重启一次**才生效（页面横幅也是这么写的）。
- `AudioConfig` 里有两个开关，不想用覆盖时把它们关掉即可：
  `use_sfx_profile = false`，或把 `sfx_profile_path` 指到别处。
- 环境变量 `WARBAND_SFX_PROFILE=0`（也认 `false` / `off`，大小写不敏感）整层不生效。
  一键门禁 `tools/run_checks.ps1` 就是用它跑"工程默认"那条路径的 —— 本机试听的结果
  不该影响门禁结论。

## 加一条新音效 / 改了音色表之后

1. 在 `scripts/audio/SfxSynth.gd` 的 `SPECS` 里加/改（`SfxFoley.SETS` 同理）。
2. 在 `tools/sfx_studio/app.js` 顶部的 `LABELS` 里加一行中文名（缺了就显示原始 id，不报错）。
3. 重跑 `start.ps1`（第 2 步会重新导出清单）。清单和代码不一致时
   `tools/sfx_studio_export.gd -- --check` 会报错，门禁里的 `sfx_pcm_check` 那类步骤也会红。
4. `audio_preview/*.wav` 是生成物，**不要提交**（`.gitignore` 已忽略，目录里有 `.gdignore`）；
   `manifest.json` 很小，**要提交**，这样净克隆之后不用跑导出也能直接开页面。

## 排错

| 现象 | 原因 / 办法 |
|---|---|
| 页面只有一条"打不开清单"的提示 | 直接 `file://` 打开了。跑 `start.ps1`，用 http 地址打开 |
| 右上角不是`本地服务已连接` | 服务器没起（或端口被占）。保存只会进 localStorage，游戏读不到 |
| 试听没声音 | 先点一下页面（浏览器要求用户交互后才允许出声）；确认 `audio_preview/` 有 wav，或重跑 `start.ps1` |
| 保存后游戏没变化 | 游戏只在启动时读一次，重启游戏；再确认横幅里的路径就是游戏真正在用的 `user://` |
| 某条音效试听是合成的、没有录音变体 | 那条还没有 foley 素材（正常，13 个动作类才有） |
| 改了音量但`实际`没变 | 单条偏移只在**开启**状态下才影响播放；关掉的条目仍然显示"如果开着会是多少" |

## 这一层不做什么

- 不调 `pitch_jitter` / 间隔节流 / `warn_cues` 这类**行为**参数 —— 它们是玩法节奏的一部分，
  放进来容易被顺手调坏。要改请直接改 `AudioConfig`（这些值仍以工程为准）。
- 不合成新音色、不裁剪素材：文件清单里有什么就用什么。
- 不改 `SfxSynth.SPECS` 里的**基准** dB（清单里的`基准`是只读参考值），偏移是额外一层。

## 文件清单

| 文件 | 作用 |
|---|---|
| `index.html` / `style.css` / `app.js` | 页面本体（纯静态，无依赖、无构建） |
| `manifest.json` | 由 `tools/sfx_studio_export.gd` 生成的音色清单（**提交**） |
| `serve.py` | 本地服务：静态文件 + `/api/health` + `/api/profile`（读/写配置，原子写） |
| `start.ps1` | 一键：导出试听音频 → 生成清单 → 起服务并开浏览器 |
| `tools/sfx_profile_check.gd` | 门禁第 9f 步：85 条断言，验游戏侧到底认不认这份配置 |