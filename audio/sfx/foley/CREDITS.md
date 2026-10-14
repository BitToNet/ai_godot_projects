# 录音素材层（audio/sfx/foley）来源与授权

本目录下的 40 个 WAV 是 `scripts/audio/SfxFoley.gd` 加载的**录音素材**，用来替换
`SfxSynth.gd` 里对应动作的合成音色（脚步 / 马蹄 / 起跳落地 / 闪避 / 命中 / 弹反 / 挥砍）。
规格统一：**单声道 / 44100 Hz / 16-bit PCM**（Godot 导入时 `compress/mode=0`，不做有损压缩，
瞬态不糊）。整套共约 15.2 秒音频、约 1.2 MB。

## 一、需求方提供的录音（4 个源文件）

| 源文件（原始位置） | 用途 |
|---|---|
| `C:\Users\50257\Downloads\音效\荒野中的脚步声.wav` | 战斗脚步 `step_a_01..04` / `step_b_01..04` |
| `C:\Users\50257\Downloads\音效\击中.mp3` | 命中 `hit_light_*` / `hit_heavy_*` / `hit_crit_*` |
| `C:\Users\50257\Downloads\音效\弹反.wav` | 弹反 `parry_*` / `parry_reflect_*` |
| `C:\Users\50257\Downloads\音效\攻击.wav` | 挥砍 `sword_wave_*` |

这 4 个文件由需求方在本轮直接提供，**本工程不对其授权做任何声明**：仓库公开分发的是
加工后的片段，公开传播 / 商用前请需求方自行确认权利归属。若要改用其它授权素材替换，
只需替换本目录同名文件并重跑 `tools/sfx_foley_check.gd` 重新校准响度（见第四节）。

## 二、CC0 / 公有领域素材（可随本仓库公开分发）

以下素材均为 **CC0 1.0（公有领域奉献）**：作者已放弃著作权，不要求署名、允许商用与再分发。
这里仍然逐条列出，是为了可复核。

| 素材 | 来源页 | 授权 | 本工程用到的文件 |
|---|---|---|---|
| Kenney — Impact Sounds | https://kenney.nl/assets/impact-sounds | CC0 | `footstep_grass_000/001/002`、`impactSoft_heavy_000..004`、`impactWood_light_000..003`、`impactWood_medium_000..003` |
| Kenney — RPG Audio | https://kenney.nl/assets/rpg-audio | CC0 | `cloth1..4`、`drawKnife1..3` |
| OpenGameArt — Fantasy Weapons and Apparel SFX（`weapons-apparel.zip`） | https://opengameart.org/content/fantasy-weapons-and-apparel-sfx | CC0（压缩包内附 readme 写明 "Distributed under Creative Commons Zero"） | `boots-leather-jump-01..03`、`sword-knife-clash-13/15/20/29` |
| OpenGameArt — qubodupImpact（Black Lodge Games） | https://opengameart.org/content/impact | CC0 | `qubodupImpactMeat01/02` |
| OpenGameArt — Horse Trotting（`Trot.ogg`） | https://opengameart.org/content/horse-trotting | CC0 | `Trot.ogg`（切出 10 次蹄音） |

> 说明：Kenney 的素材页写明 "License: CC0 1.0 Universal"，不强制署名；上面列出作者与链接是自愿的。

### 下载了但**没有采用**的素材（避免误以为在用）

| 素材 | 未采用原因 |
|---|---|
| OpenGameArt 各版本马匹 **gallop**（奔跑）循环 | 授权为 CC-BY 3.0 / 4.0，需署名且与"尽量只用可自由分发的素材"的取向冲突；改用 CC0 的 `Trot.ogg` |
| `cloth_sounds.ogg` | CC-BY 3.0 |
| jute-dh-steps 系列 | GPL，与本仓库授权不兼容 |
| Kenney `footstep_concrete_*` / `footstep_wood_*`、`quiver-leather-*`、`boots-leather-step-*` | 已够用，本轮不需要（留作后续素材库） |
| OpenGameArt `swishes.zip`、`25-CC0-mud-sfx.zip`、`impact_-_starninjas.zip` | 挥砍 / 脚步已由需求方录音覆盖，未使用 |
| freesound.org / pixabay / sonniss 音频包 | 需要账号或明确禁止再分发（pixabay、sonniss 返回 403） |
| archive.org、Wikimedia Commons | 本轮抓取时不可达（HTTP 000） |

## 三、逐文件来源（40 个 WAV）

切片偏移量的权威定义在 `tools/sfx_foley_build.ps1` 的同一张表里（该脚本是这套素材的推导配方）。

| 输出文件 | 主素材（切片起点 / 长度） | 叠加层 | 处理 |
|---|---|---|---|
| `step_a_01..04` | 需求方脚步 0.420 / 3.190 / 5.780 / 16.190 s，0.32 s | — | 高通 70 + `afftdn` 降噪 + 2:1 压缩 |
| `step_b_01..04` | 需求方脚步 1.610 / 3.750 / 9.280 / 17.290 s，0.32 s | — | 同上 |
| `step_heavy_01..03` | Kenney `footstep_grass_00{0,1,2}` 0.45 s | `impactSoft_heavy_00{0,1,2}` −5 dB | 降调 0.85× |
| `hoof_a_01..04` | `Trot.ogg` 0.05 / 1.30 / 2.52 / 4.61 s，0.30 s | `impactWood_light_00{0..3}` −7 dB | 高通 70 |
| `hoof_b_01..04` | `Trot.ogg` 0.89 / 1.72 / 4.22 / 9.33 s，0.30 s | `impactWood_medium_00{0..3}` −7 dB | 降调 0.94× |
| `land_01..03` | `qubodupImpactMeat0{1,2,1}` 0.36 s | `impactSoft_heavy_00{0,1,2}` −4 dB | 第 3 个降调 0.93× |
| `jump_01..03` | `boots-leather-jump-0{1,2,3}` 0.42 s | `cloth{1,2,3}` −7 dB | 高通 90 |
| `dodge_01..03` | `drawKnife{1,2,3}` 0.32 s | `cloth{4,3,2}` −8 dB | 高通 140 |
| `hit_light_01/02` | 需求方击中 0.19 s / 0.26 s（0.36 / 0.32 s） | — | 高通 45 |
| `hit_heavy_01/02` | 需求方击中同上 | `impactSoft_heavy_00{3,4}` −6 dB | 降调 0.90× |
| `hit_crit_01/02` | 需求方击中同上 | `sword-knife-clash-15/29` −7 dB | 升调 1.12× |
| `parry_01/02` | 需求方弹反 0.72 / 0.50 s | — | 2 号升调 1.06× |
| `parry_reflect_01/02` | 需求方弹反 0.55 / 0.45 s | `sword-knife-clash-13/20` −9 dB | 升调 1.18× / 1.26× |
| `sword_wave_01/02` | 需求方攻击 0.44 / 0.42 s | — | 2 号升调 1.08× |

切片起点只落在**真实起音**上（脚步的 8 个切片按"处理后信噪比 ≥35 dB 且瞬态够强"筛过，
弱起音已剔除）。`step_a` / `step_b` 是两组 take，**不代表左右脚**，随机挑选即可。

## 四、响度是怎么定的（改素材后必须重跑）

`tools/sfx_foley_check.gd` 会把每个动作的录音素材与**它替换掉的合成音色**逐项对照，
打出峰值 dB 与"最大 10 ms 窗口 RMS" dB 两个口径的差值：

* 先用**同一个窗口 RMS 目标（−19 dB）**把 40 个文件拉齐，使 take 之间音量一致；
* 再按 `tools/sfx_foley_build.ps1` 里的 `$match` 表，把每个动作整体移到合成音色的响度上
  （峰值对齐与 RMS 对齐的中点），这样"换素材"不会顺手改掉整套混音的平衡。
  实测不加这一步，录音素材会整体低 8~13 dB，听起来就像"音效丢了"；
* `step_a` / `step_b` 例外：真实脚步的波峰因数（≈13 dB）是合成滤噪（≈6 dB）的两倍，
  两者无法同时贴齐，于是**只贴峰值**——起音瞬态落在原位，平均能量低 ≈7 dB，
  这是"录音本来就会衰减"的诚实结果（要按 RMS 拉平得把起音压掉 7 dB，人味就没了）。

因此自检对两个口径的容差不同：峰值 ±4 dB，窗口 RMS −9 ~ +4 dB（允许更低，不允许更高）。

## 五、重建配方

`tools/sfx_foley_build.ps1` 是这 40 个文件的**完整推导脚本**（ffmpeg 滤镜链 + 切片表 + 响度校准）。
它不是游戏构建的一部分，只在需要重新生成素材时手工运行：把上面第一、二节的源素材按脚本
`param` 段说明的 ASCII 目录结构放到暂存目录，再执行即可。运行时自检只认本目录的文件，
与脚本是否存在无关。
