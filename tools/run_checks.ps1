# =============================================================================
#  run_checks.ps1 —— 一键回归检查（本仓库的“CI 门”）
#
#  用法：
#    powershell -File tools/run_checks.ps1
#    （本机只有 Windows PowerShell 5.1，没有 pwsh 7，不要写成 pwsh）
#
#  依次执行下列步骤（25 项，约 58~72 秒）；性能若超软容差会**额外**追加一行「性能基准 注意…」，
#  所以汇总里的项数偶尔是 26 —— 别把某一跑的行数当成脚本的固有常量。
#  任何一步「退出码不在预期内」「超时」「输出里出现 ERROR: / SCRIPT ERROR /
#  Parse Error」都会记为失败：
#    1) 生成指纹 A（跨进程双跑之一）
#    2) 生成指纹 B —— 必须与 A 的 FINGERPRINT= 完全一致（同种子可复现）
#       2b) 指纹 A 还必须与 tools/gen_fingerprint.json 里存档的指纹一致
#       —— 只比 A=B 挡不住"两次跑出同一个新指纹"，那说明生成结果已经变了
#    3) HUD 对外接口冒烟（tools/hud_check.gd）—— 主场景 900 帧里玩家不动、不触发遭遇，
#       UI 的交互路径（遭遇框开关 / 提示抑制 / 提示条淡出）那一步是覆盖不到的
#    4) 输入层回归（tools/input_check.gd）—— [input] 动作表是否真的进了 InputMap、
#       InputRouter 的分发与让路、遭遇框能否用键盘 / 手柄作答。这类「按了没反应」的问题
#       以前只能靠点开游戏按一按，且第三轮之前根本没有可改的键位表
#    5) 经济定式（tools/economy_check.gd）—— 军费 / 士气 / 招募 / 撤退代价的公式形状，
#       外加一条 42 天的收支时间轴。这条回路（工资→欠薪→士气→逃兵→兵力→工资）在
#       900 帧里连一天都跑不完，没有它就只能靠开游戏看几天才发现经济是坏的
#    5b) 寻路队列契约（tools/path_queue_check.gd）—— 第六轮 6d 后半：结果与同步 find_path
#        逐点相同 / 严格 FIFO / 预算为 0 时每帧仍前进一个 / 失效 Callable 不崩不少记账。
#        队列算错的表现是「部队偶尔站着不动」，900 帧主场景里很难稳定复现，只能直接对契约下断言
#    5c) 分级日志契约（tools/log_check.gd）—— 第六轮 ⑦：默认级别必须仍是 INFO（门禁按默认
#        级别解析输出），ERROR 必须仍以 "ERROR: " 开头走 stderr（门禁靠它兜底抓失败）
#    5d) i18n 棘轮（tools/i18n_check.gd）—— 第六轮 ⑥：scripts/ui 里含中文的字符串字面量条数
#        与 tools/i18n_baseline.json 比，只许变小（新文案请放进 scripts/core/Strings.gd）
#    6) 城镇交互定式（tools/settlement_check.gd）—— 补给 / 招募 / 贸易 / 驻军的价格、
#       边界（钱不够 / 编制满 / 池子空 / 城里没兵）与「低买高卖」是否真的有利可图。
#       菜单的分支同样在 900 帧里一个都走不到，而它是整个经济闭环的入口
#    6b) 遭遇选项表定式（tools/encounter_check.gd）—— 攻击 / 花钱买路 / 索要买路钱 / 撤退
#        四条路的定价、可用性与代价，外加「不合法动作一律静默拒绝」与时间锁有没有解开。
#        这张表同样在 900 帧里走不到：主场景里玩家不动，一次遭遇都不会触发
#    7) 性能基准采样（tools/perf_probe.gd）
#    7b) 规模热点探针（tools/scale_probe.gd）—— 第六轮的三条主线：植被筛选 / 地形建块 /
#        A* 寻路。结构量（实例数 / 区块数 / 变换指纹 / 展开节点数）与 tools/scale_baseline.json
#        精确比对，耗时只做上界比对（1.6x 记 WARN / 2.5x 判失败）。它一上来就证伪了路线图
#        的一条预估：植被的实例发射只占 2.2 ms / 917 ms，「改 multimesh_set_buffer」
#        几乎省不下时间（详见 ROADMAP §12.1）
#    7c) 地图尺寸适配定式（tools/map_size_check.gd）—— 第六轮 §15 第 ① 批：把「相机远裁剪面 /
#        拾取最远距离 / heightmap_res 导出上限」这类**纯数值**假设钉住。它们的失败方式不是报错，
#        而是在 4096 m 图上「地形被裁掉 / 编辑器里根本调不上去」，而 1024 m 图上门禁全绿 ——
#        只有「按尺寸推导」这层关系本身的断言抓得到。它不建世界、不渲染，跑得很快
#    7d) 4096 m 世界实测（tools/big_map_probe.gd）—— **可选**：$env:WARBAND_BIG_MAP = '1' 才跑。
#        它不进默认流程：跑一次要 80~120 秒（真的建一个 4096 m 世界）。想换世界之前先看它
#    6c) 存档定式（tools/save_check.gd）—— 存档格式 / 三道门（版本 / 种子 / 实体 id）/
#        坏数据钳制 / 读档后的引用修复 / 文件读写（不建世界，纯定式）
#    6d) 音频总线定式（tools/audio_check.gd）—— default_bus_layout.tres（Master → Music / Sfx）
#        是否真被引擎加载、AudioBus 的写回与降级、Sfx / Bgm 的路由与「总音量只算一次」、
#        duck 的触发与到点恢复、静音走增益淡出（不建世界、纯读对象，也没有 Main）
#    8) Boss 战音效联调（tools/sfx_battle_check.gd）
#    9) 大地图音效联调（tools/sfx_map_check.gd）
#    9b) BGM 联调（tools/bgm_check.gd）—— 两首 Ogg 的加载 / 循环开关、大地图曲淡入、
#        遭遇 → Boss 战 → 结算的切曲、M 键静音与恢复、stop()。它要真跑一遍主场景，
#        所以是门禁里最贵的一步（≈7 s），但「音乐切错曲子 / 静音没淡下去」只有它能抓到
#    9c) 音色 PCM 指纹（tools/sfx_tool.gd --check）—— 28 个音色的 16bit PCM 逐字节
#        比对 tools/sfx_pcm.json。第五轮的合成优化（去函数调用 / 去临时分配 / 省 pow）
#        全是「输出必须一模一样」的类型，这条就是它的证明；有意改音色必须显式更新基线
#    9d) PCM 缓存自检（tools/audio_cache_check.gd）—— 冷启动合成落盘 → 热启动逐字节一致
#        → 六种坏缓存各自静默退回冷启动并自愈 → Sfx.setup 真的走缓存 → 关缓存不碰盘
#    9e) 录音素材自检（tools/sfx_foley_check.gd）—— 移动 / 打击类音效的录音素材层
#        （audio/sfx/foley/*.wav）：清单与变体齐全、单声道 44.1 kHz、不削波、非静音，
#        **且响度与它替换掉的那条合成音色对齐**（峰值 ±4 dB / 窗口 RMS −9~+4 dB）。
#        最后一条是关键：素材换成录音之后，混音平衡只能靠它守 —— 只做统一归一化
#        会让录音比合成音色低 8~13 dB，听起来就像「音效丢了」（见 ROADMAP §13.3）
#    10) 主场景跑 900 帧 —— 无 ERROR，且生成统计与 tools/gen_fingerprint.json 基线一致
#
#  为什么是这些：本工程「一切由种子生成 + 运行时合成音效 + 纯代码 UI」，
#  一旦 RNG 抽取顺序、音色触发路径或主场景初始化被改坏，靠肉眼很难发现。
#  基线变化时必须是有意为之，并同步跑 `--write-baseline` 更新存档。
#  退出码：0 = 全绿；1 = 有失败项。
#
#  ⚠ 本文件必须保存为「带 BOM 的 UTF-8」：本机只有 Windows PowerShell 5.1，
#    它读取 .ps1 时若没有 BOM 就按系统 ANSI(GBK) 解码，中文注释会变成乱码并直接
#    引发语法错误（第一次运行就是这么炸的）。改动本文件后请确认 BOM 仍在。
# =============================================================================
$ErrorActionPreference = 'Continue'

# 引擎路径：CI 用环境变量 GODOT_BIN 覆盖；本机默认走用户全局规则 2 的固定路径
$GODOT = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe' }
$PROJ = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$BASELINE_JSON = Join-Path $PROJ 'tools\gen_fingerprint.json'
$fail = New-Object System.Collections.Generic.List[string]
$pass = New-Object System.Collections.Generic.List[string]
$swAll = [System.Diagnostics.Stopwatch]::StartNew()

function Invoke-GodotStep {
	param(
		[string]$Name,
		[string[]]$Extra,
		[int[]]$OkExit = @(0),
		[int]$TimeoutSec = 180
	)
	$log = Join-Path $env:TEMP ("warband_check_{0}.log" -f ($Name -replace '[^\w]', '_'))
	$all = @('--headless', '--path', $PROJ, '--fixed-fps', '60') + $Extra
	$sw = [System.Diagnostics.Stopwatch]::StartNew()
	# 每步都必须有硬超时。Godot 里的工具脚本一旦抛运行时错误（例如调用了已被删除的 Main 方法），
	# SceneTree 的协程会静默死掉、进程永不退出，表现为 100% CPU 空转 —— 没有超时就会把整条门禁
	# 挂住（2026-10-13 实测：perf_probe 挂在已删除的 main._order_move 上，15 分钟一步没动、零输出）。
	# 超时必须连子进程一起杀：console 版会再拉一个同名的 GUI 进程跑真正的游戏。
	$psi = New-Object System.Diagnostics.ProcessStartInfo
	$psi.FileName = $GODOT
	$psi.Arguments = (($all | ForEach-Object { '"' + $_ + '"' }) -join ' ')
	$psi.UseShellExecute = $false
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true
	$psi.CreateNoWindow = $true
	$proc = [System.Diagnostics.Process]::Start($psi)
	# 必须异步读：同步 ReadToEnd 会在管道写满时和 WaitForExit 互相死锁
	$outTask = $proc.StandardOutput.ReadToEndAsync()
	$errTask = $proc.StandardError.ReadToEndAsync()
	$timedOut = -not $proc.WaitForExit($TimeoutSec * 1000)
	if ($timedOut) {
		& taskkill /T /F /PID $proc.Id *>&1 | Out-Null
		$proc.WaitForExit()
	}
	$code = $proc.ExitCode
	$text = $outTask.Result + $errTask.Result
	[System.IO.File]::WriteAllText($log, $text, (New-Object System.Text.UTF8Encoding($true)))
	$sw.Stop()
	$lines = @($text -split "`r?`n")
	# 必须用大小写敏感(-cmatch)且带冒号的窄模式：PowerShell 5.1 会把原生命令写往 stderr 的
	# 任何内容（例如 Godot 退出时的 "WARNING: N ObjectDB instances were leaked"）包装成一个
	# ErrorRecord，其格式化文本里带有 "FullyQualifiedErrorId : NativeCommandError"。
	# 若用大小写不敏感的 'ERROR' 去匹配，这条纯噪声就会把整步判成失败。
	# Godot 自身的错误固定是 'ERROR: ' / 'SCRIPT ERROR: ' / 'Parse Error' 这几种写法。
	$errLines = @($lines | Where-Object { $_ -cmatch 'ERROR:|SCRIPT ERROR|Parse Error' })
	$secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
	$ok = ($OkExit -contains $code) -and ($errLines.Count -eq 0) -and (-not $timedOut)
	$detail = "exit=$code  用时 ${secs}s"
	if ($timedOut) {
		$detail = "$detail  超时 >${TimeoutSec}s（已强杀）"
	}
	if ($errLines.Count -gt 0) {
		$detail = "$detail  错误行 $($errLines.Count)"
	}
	if ($ok) {
		$pass.Add("$Name  PASS  $detail")
	} else {
		$fail.Add("$Name  FAIL  $detail")
		if ($timedOut) {
			$fail.Add("        > 超过 ${TimeoutSec}s 未退出，已连子进程强杀 —— 典型原因是工具脚本在 Godot 里抛了运行时错误（协程静默死掉、进程不退）")
		}
		foreach ($e in ($errLines | Select-Object -First 8)) {
			$fail.Add("        > $e")
		}
		if (-not ($OkExit -contains $code)) {
			foreach ($e in ($lines | Where-Object { $_ -match 'FAIL|SKIP|超时|PASS' } | Select-Object -First 6)) {
				$fail.Add("        > $e")
			}
		}
	}
	return [pscustomobject]@{ Ok = $ok; Exit = $code; Lines = $lines; Log = $log; Secs = $secs }
}

function Get-Fingerprint([string[]]$Lines) {
	foreach ($l in $Lines) {
		if ($l -match 'FINGERPRINT=([0-9a-f]{64})') { return $Matches[1] }
	}
	return ''
}

Write-Host "== Warband 回归检查 ==" -ForegroundColor Cyan
Write-Host "工程：$PROJ"
Write-Host "引擎：$GODOT"
Write-Host ""

# ---- 基线（gen_fingerprint.json 由 Godot 写成「无 BOM 的 UTF-8」）----
# PowerShell 5.1 的 Get-Content -Raw 会按系统 ANSI(GBK) 解码它 → 中文 detail 变乱码、
# 整个 JSON 解析失败，表现为基线被静默读成 0/0/0。必须显式指定 UTF-8 读取。
$baseline = $null
if (-not (Test-Path $BASELINE_JSON)) {
	$fail.Add("基线  FAIL  缺失：$BASELINE_JSON（用 tools/gen_fingerprint.gd -- --write-baseline 生成）")
} else {
	$baseTxt = [System.IO.File]::ReadAllText($BASELINE_JSON, (New-Object System.Text.UTF8Encoding($false)))
	try { $baseline = ConvertFrom-Json -InputObject $baseTxt -ErrorAction Stop } catch { $baseline = $null }
	if ($null -eq $baseline -or $null -eq $baseline.fingerprint) {
		$fail.Add("基线  FAIL  无法解析：$BASELINE_JSON")
	}
}

# ---- 1) 指纹 A ----
$r1 = Invoke-GodotStep -Name 'gen_fingerprint A' -Extra @('--script', 'res://tools/gen_fingerprint.gd')
$fpA = Get-Fingerprint $r1.Lines

# ---- 2) 指纹 B（跨进程双跑，验证同种子可复现）----
$r2 = Invoke-GodotStep -Name 'gen_fingerprint B' -Extra @('--script', 'res://tools/gen_fingerprint.gd')
$fpB = Get-Fingerprint $r2.Lines
if ($fpA -eq '' -or $fpB -eq '') {
	$fail.Add('跨进程双跑  FAIL  至少一次没打印出 FINGERPRINT=')
} elseif ($fpA -ne $fpB) {
	$fail.Add('跨进程双跑  FAIL  两次指纹不同（同种子不可复现！）')
	$fail.Add("        > A = $fpA")
	$fail.Add("        > B = $fpB")
} else {
	$pass.Add("跨进程双跑  PASS  两次指纹一致 $($fpA.Substring(0,16))…")
}

# ---- 2b) 指纹还必须与已存档的基线一致 ----
# 只比 A/B 是不够的：两次跑出**同一个新指纹**时 A=B 依然成立，但那说明生成结果已经变了。
# 真正能挡住"RNG 抽取顺序被悄悄改动"的是这一条与 gen_fingerprint.json 的比对。
if ($null -ne $baseline -and $null -ne $baseline.fingerprint -and $fpA -ne '') {
	if ($fpA -ne [string]$baseline.fingerprint) {
		$fail.Add("指纹基线  FAIL  本次 $($fpA.Substring(0,16))… ≠ 基线 $(([string]$baseline.fingerprint).Substring(0,16))…")
		$fail.Add('        > 生成结果变了：要么是有意改动（请同步跑 --write-baseline 更新基线），要么是 RNG 抽取顺序被动了')
	} else {
		$pass.Add('指纹基线  PASS  与 tools/gen_fingerprint.json 存档一致')
	}
}

# ---- 3) HUD 对外接口冒烟 ----
$rHud = Invoke-GodotStep -Name 'hud_check' -Extra @('--script', 'res://tools/hud_check.gd')
$hudPass = @($rHud.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
if ($rHud.Ok -and -not $hudPass) {
	$fail.Add('HUD 冒烟  FAIL  退出码为 0 但没打印 PASS')
}

# ---- 4) 输入层回归 ----
# 断言都在 tools/input_check.gd 里；这里只确认「退出码 0 且打印了 PASS」，
# 免得将来有人把 quit(0) 写在断言之前。
$rInput = Invoke-GodotStep -Name 'input_check' -Extra @('--script', 'res://tools/input_check.gd')
$inputPass = @($rInput.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
if ($rInput.Ok -and -not $inputPass) {
	$fail.Add('输入层  FAIL  退出码为 0 但没打印 PASS')
}

# ---- 5) 经济定式（军费 / 士气 / 招募 / 收支时间轴）----
# 断言在 tools/economy_check.gd 里；这里同样只确认「退出码 0 且打印了 PASS」。
$rEco = Invoke-GodotStep -Name 'economy_check' -Extra @('--script', 'res://tools/economy_check.gd')
$ecoPass = @($rEco.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
if ($rEco.Ok -and -not $ecoPass) {
	$fail.Add('经济定式  FAIL  退出码为 0 但没打印 PASS')
}

# ---- 5b) 寻路队列契约（每帧预算 / FIFO / 与同步结果逐点相同）----
# 断言在 tools/path_queue_check.gd 里；这里同样只确认「退出码 0 且打印了 PASS」。
# 为什么值得单独一步：队列算错的表现是「部队偶尔站着不动」，900 帧主场景里很难稳定复现。
$rPq = Invoke-GodotStep -Name 'path_queue_check' -Extra @('--script', 'res://tools/path_queue_check.gd')
$pqPass = @($rPq.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
if ($rPq.Ok -and -not $pqPass) {
	$fail.Add('寻路队列  FAIL  退出码为 0 但没打印 PASS')
}

# ---- 5c) 分级日志契约（默认级别必须仍是 INFO / ERROR 前缀仍在）----
# 断言在 tools/log_check.gd 里。两条周边契约一破就是事故：默认级别一变高，门禁就
# 「因为看不见」而变绿；ERROR 前缀一改，门禁的兜底网就漏了。
$rLog = Invoke-GodotStep -Name 'log_check' -Extra @('--script', 'res://tools/log_check.gd')
$logPass = @($rLog.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
if ($rLog.Ok -and -not $logPass) {
	$fail.Add('分级日志  FAIL  退出码为 0 但没打印 PASS')
}

# ---- 5d) i18n 棘轮（scripts/ui 里还剩多少硬编码中文，只许变小）----
# 断言在 tools/i18n_check.gd 里；它会把当前条数与基线一起打印，趋势肉眼可见。
$rI18n = Invoke-GodotStep -Name 'i18n_check' -Extra @('--script', 'res://tools/i18n_check.gd')
$i18nPass = @($rI18n.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
if ($rI18n.Ok -and -not $i18nPass) {
	$fail.Add('i18n 棘轮  FAIL  退出码为 0 但没打印 PASS')
}

# ---- 6) 城镇交互定式（补给 / 招募 / 贸易 / 驻军）----
# 断言在 tools/settlement_check.gd 里；同样只确认「退出码 0 且打印了 PASS」。
$rStl = Invoke-GodotStep -Name 'settlement_check' -Extra @('--script', 'res://tools/settlement_check.gd')
$stlPass = @($rStl.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
if ($rStl.Ok -and -not $stlPass) {
	$fail.Add('城镇交互  FAIL  退出码为 0 但没打印 PASS')
}

# ---- 6b) 遭遇选项表定式（攻击 / 花钱买路 / 索要买路钱 / 撤退）----
# 断言在 tools/encounter_check.gd 里；同样只确认「退出码 0 且打印了 PASS」。
$rEnc = Invoke-GodotStep -Name 'encounter_check' -Extra @('--script', 'res://tools/encounter_check.gd')
$encPass = @($rEnc.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
if ($rEnc.Ok -and -not $encPass) {
	$fail.Add('遭遇选项  FAIL  退出码为 0 但没打印 PASS')
}

# ---- 6c) 存档定式（格式 / 校验 / 坏数据钳制 / 读档修引用）----
# 断言在 tools/save_check.gd 里；这里同样只确认「退出码 0 且打印了 PASS」。
# 门禁的 900 帧主场景不会去按 F5 / F9（存读档是要玩家触发的），所以整条存档链
# 必须靠这个不建世界的入口来验。
$rSave = Invoke-GodotStep -Name 'save_check' -Extra @('--script', 'res://tools/save_check.gd')
$savePass = @($rSave.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
if ($rSave.Ok -and -not $savePass) {
	$fail.Add('存档  FAIL  退出码为 0 但没打印 PASS')
}

# ---- 6d) 音频总线定式（布局 / 路由 / 写回 / duck / 静音语义）----
# 断言在 tools/audio_check.gd 里；同样只确认「退出码 0 且打印了 PASS」。
# 门禁的 900 帧主场景只跑 Master 这一条总线（玩家不按键、不切曲），总线是否真被引擎加载、
# Bgm 是否挂到 Music 上，都得靠这个入口来验。
$rBus = Invoke-GodotStep -Name 'audio_check' -Extra @('--script', 'res://tools/audio_check.gd')
$busPass = @($rBus.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
if ($rBus.Ok -and -not $busPass) {
	$fail.Add('音频总线  FAIL  退出码为 0 但没打印 PASS')
}

# ---- 7) 性能基准 ----
$r3 = Invoke-GodotStep -Name 'perf_probe' -Extra @('--script', 'res://tools/perf_probe.gd')
$warn3 = @($r3.Lines | Where-Object { $_ -match 'WARN' })
if ($r3.Ok -and $warn3.Count -gt 0) {
	# 超容差才判失败；只是漂移就提示出来，别让"长期贴着容差上限"悄悄变成新常态
	$pass.Add("性能基准  注意  有 $($warn3.Count) 条 WARN（未超容差，不判失败）")
}

# ---- 7b) 规模热点探针 ----
# 结构量必须与 tools/scale_baseline.json 精确一致；耗时超 1.6x 记 WARN、超 2.5x 判失败。
$r3b = Invoke-GodotStep -Name 'scale_probe' -Extra @('--script', 'res://tools/scale_probe.gd')
$warn3b = @($r3b.Lines | Where-Object { $_ -match 'WARN' })
if ($r3b.Ok -and $warn3b.Count -gt 0) {
	$pass.Add("规模热点  注意  有 $($warn3b.Count) 条 WARN（未超硬容差，不判失败）")
}

# ---- 7c) 地图尺寸适配定式（tools/map_size_check.gd）----
# 「换更大的地图」踩中的第一类坑是纯数值假设：相机远裁剪面裁掉地形、heightmap_res 的导出
# 上限挡住 2049。它们不报错、只在 4096 m 图上显形，所以断言的是推导关系本身（不建世界）。
$rSize = Invoke-GodotStep -Name 'map_size_check' -Extra @('--script', 'res://tools/map_size_check.gd')
$sizePass = @($rSize.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
if ($rSize.Ok -and -not $sizePass) {
	$fail.Add('地图尺寸  FAIL  退出码为 0 但没打印 PASS')
}

# ---- 7d) 4096 m 世界实测（tools/big_map_probe.gd）—— **可选**，默认跳过 ----
# 它是「换世界之前先量一遍」的测量工具，不是断言型检查：跑一次要 80~120 秒（生成 83 秒 + 复测），
# 塞进 70 秒的门禁里不划算。想看就 $env:WARBAND_BIG_MAP = '1' 后再跑本脚本。
if ($env:WARBAND_BIG_MAP -eq '1') {
	$rBig = Invoke-GodotStep -Name 'big_map_probe' -Extra @('--script', 'res://tools/big_map_probe.gd') -TimeoutSec 900
	$bigPass = @($rBig.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
	if ($rBig.Ok -and -not $bigPass) {
		$fail.Add('4096 m 实测  FAIL  退出码为 0 但没打印 PASS')
	}
}

# ---- 8) / 9) 音效联调 ----
$r4 = Invoke-GodotStep -Name 'sfx_battle_check' -Extra @('--script', 'res://tools/sfx_battle_check.gd')
$r5 = Invoke-GodotStep -Name 'sfx_map_check' -Extra @('--script', 'res://tools/sfx_map_check.gd')
foreach ($r in @($r4, $r5)) {
	$hasPass = @($r.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
	$hasSkip = @($r.Lines | Where-Object { $_ -match 'SKIP' }).Count -gt 0
	if ($hasSkip -and -not $hasPass) {
		$fail.Add("音效联调  FAIL  出现 SKIP（AudioConfig.enabled=false 时不算通过）")
	}
}

# ---- 9b) BGM 联调（加载 / 淡入 / 切曲 / 静音 / stop）----
# 断言在 tools/bgm_check.gd 里；它真的走一遍「大地图 → 遭遇 → Boss 战 → 结算 → 大地图」。
# 与 8) / 9) 一样：出现 SKIP 而没有 PASS 判失败（那是"关音频所以没验"的意思）。
$rBgm = Invoke-GodotStep -Name 'bgm_check' -Extra @('--script', 'res://tools/bgm_check.gd')
$bgmPass = @($rBgm.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
$bgmSkip = @($rBgm.Lines | Where-Object { $_ -match 'SKIP' }).Count -gt 0
if ($bgmSkip -and -not $bgmPass) {
	$fail.Add('BGM 联调  FAIL  出现 SKIP（AudioConfig.enabled=false 时不算通过）')
}

# ---- 9c) 音色 PCM 指纹（28 个音色逐字节比对 tools/sfx_pcm.json）----
# 合成优化的正确性证明：算法一字未改、只去掉函数调用与临时 Array，所以 PCM 必须逐字节相同。
# 指纹变了 = 音色真的被改了 —— 有意改就重跑 `sfx_tool.gd -- --write-baseline` 更新基线。
$rPcm = Invoke-GodotStep -Name 'sfx_pcm_check' -Extra @('--script', 'res://tools/sfx_tool.gd', '--', '--check')
$pcmPass = @($rPcm.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
if ($rPcm.Ok -and -not $pcmPass) {
	$fail.Add('音色指纹  FAIL  退出码为 0 但没打印 PASS')
}

# ---- 9d) 音色 PCM 缓存自检（tools/audio_cache_check.gd）----
# 5c 的证明：冷启动合成 → 落盘 → 热启动逐字节一致 → 坏缓存自愈 → Sfx.setup 命中 → 关缓存不碰盘。
# 它跑完会留下一份**有效**缓存，后面几步（sfx_map_check / bgm_check / main_scene_900）因此是热启动。
$rCache = Invoke-GodotStep -Name 'audio_cache_check' -Extra @('--script', 'res://tools/audio_cache_check.gd')
$cachePass = @($rCache.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
if ($rCache.Ok -and -not $cachePass) {
	$fail.Add('音色缓存  FAIL  退出码为 0 但没打印 PASS')
}

# ---- 9e) 录音素材自检（tools/sfx_foley_check.gd）----
# 素材层的契约：清单/变体齐全、规格统一、不削波，且响度与它替换掉的合成音色对齐。
# 响度那条是这一步存在的理由 —— 「素材都加载上了」这种检查抓不到"音效听不见了"。
$rFoley = Invoke-GodotStep -Name 'sfx_foley_check' -Extra @('--script', 'res://tools/sfx_foley_check.gd')
$foleyPass = @($rFoley.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
if ($rFoley.Ok -and -not $foleyPass) {
	$fail.Add('录音素材  FAIL  退出码为 0 但没打印 PASS')
}

# ---- 10) 主场景 900 帧 + 生成统计比对基线 ----
$r6 = Invoke-GodotStep -Name 'main_scene_900' -Extra @('--quit-after', '900')
$statLine = @($r6.Lines | Where-Object { $_ -match '地图生成完成' })
if ($statLine.Count -eq 0) {
	$fail.Add('主场景  FAIL  没等到“地图生成完成”那行输出')
} else {
	$m = [regex]::Match($statLine[0], '定居点\s+(\d+)\s+桥梁\s+(\d+)\s+植被实例\s+(\d+)')
	if (-not $m.Success) {
		$fail.Add("主场景  FAIL  解析生成统计失败：$($statLine[0])")
	} elseif ($null -eq $baseline -or $null -eq $baseline.counts) {
		$fail.Add("主场景  FAIL  基线缺失或不可用：$BASELINE_JSON")
	} else {
		$exp = $baseline.counts
		$got = @([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value)
		$want = @([int]$exp.settlements, [int]$exp.bridges, [int]$exp.vegetation)
		if (($got[0] -eq $want[0]) -and ($got[1] -eq $want[1]) -and ($got[2] -eq $want[2])) {
			$pass.Add("生成统计  PASS  定居点 $($got[0]) / 桥梁 $($got[1]) / 植被 $($got[2])（与基线一致）")
		} else {
			$fail.Add("生成统计  FAIL  本次 $($got -join '/')  ≠ 基线 $($want -join '/')（RNG 抽取顺序被动了？）")
		}
	}
}

# ---- 汇总 ----
Write-Host ""
foreach ($l in $pass) { Write-Host $l -ForegroundColor Green }
foreach ($l in $fail) { Write-Host $l -ForegroundColor Red }
$swAll.Stop()
$secsAll = [math]::Round($swAll.Elapsed.TotalSeconds, 1)
Write-Host ""
if ($fail.Count -eq 0) {
	Write-Host "== 全部通过（$($pass.Count) 项，用时 ${secsAll}s）==" -ForegroundColor Green
	exit 0
} else {
	Write-Host "== 有 $($fail.Count) 条失败（用时 ${secsAll}s），引擎日志在 %TEMP%\warband_check_*.log ==" -ForegroundColor Red
	exit 1
}
