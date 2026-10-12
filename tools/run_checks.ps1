# =============================================================================
#  run_checks.ps1 —— 一键回归检查（本仓库的“CI 门”）
#
#  用法：
#    powershell -File tools/run_checks.ps1
#    （本机只有 Windows PowerShell 5.1，没有 pwsh 7，不要写成 pwsh）
#
#  依次执行 6 步；任何一步「退出码不在预期内」「超时」「输出里出现 ERROR: / SCRIPT ERROR /
#  Parse Error」都会记为失败：
#    1) 生成指纹 A（跨进程双跑之一）
#    2) 生成指纹 B —— 必须与 A 的 FINGERPRINT= 完全一致（同种子可复现）
#    3) 指纹 A 还必须与 tools/gen_fingerprint.json 里存档的指纹一致
#       —— 只比 A=B 挡不住"两次跑出同一个新指纹"，那说明生成结果已经变了
#    4) 性能基准采样（tools/perf_probe.gd）
#    5) Boss 战音效联调（tools/sfx_battle_check.gd）
#    6) 大地图音效联调（tools/sfx_map_check.gd）
#    7) 主场景跑 900 帧 —— 无 ERROR，且生成统计与 tools/gen_fingerprint.json 基线一致
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

$GODOT = 'G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe'
$PROJ = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$BASELINE_JSON = Join-Path $PROJ 'tools\gen_fingerprint.json'
$fail = New-Object System.Collections.Generic.List[string]
$pass = New-Object System.Collections.Generic.List[string]
$swAll = [System.Diagnostics.Stopwatch]::StartNew()

function Invoke-GodotStep {
	param(
		[string]$Name,
		[string[]]$Extra,
		[int[]]$OkExit = @(0)
	)
	$log = Join-Path $env:TEMP ("warband_check_{0}.log" -f ($Name -replace '[^\w]', '_'))
	$all = @('--headless', '--path', $PROJ, '--fixed-fps', '60') + $Extra
	$sw = [System.Diagnostics.Stopwatch]::StartNew()
	& $GODOT @all *>&1 | Set-Content -Path $log -Encoding UTF8
	$code = $LASTEXITCODE
	$sw.Stop()
	$lines = @(Get-Content -Path $log)
	# 必须用大小写敏感(-cmatch)且带冒号的窄模式：PowerShell 5.1 会把原生命令写往 stderr 的
	# 任何内容（例如 Godot 退出时的 "WARNING: N ObjectDB instances were leaked"）包装成一个
	# ErrorRecord，其格式化文本里带有 "FullyQualifiedErrorId : NativeCommandError"。
	# 若用大小写不敏感的 'ERROR' 去匹配，这条纯噪声就会把整步判成失败。
	# Godot 自身的错误固定是 'ERROR: ' / 'SCRIPT ERROR: ' / 'Parse Error' 这几种写法。
	$errLines = @($lines | Where-Object { $_ -cmatch 'ERROR:|SCRIPT ERROR|Parse Error' })
	$secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
	$ok = ($OkExit -contains $code) -and ($errLines.Count -eq 0)
	$detail = "exit=$code  用时 ${secs}s"
	if ($errLines.Count -gt 0) {
		$detail = "$detail  错误行 $($errLines.Count)"
	}
	if ($ok) {
		$pass.Add("$Name  PASS  $detail")
	} else {
		$fail.Add("$Name  FAIL  $detail")
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

# ---- 3) 性能基准 ----
$r3 = Invoke-GodotStep -Name 'perf_probe' -Extra @('--script', 'res://tools/perf_probe.gd')
$warn3 = @($r3.Lines | Where-Object { $_ -match 'WARN' })
if ($r3.Ok -and $warn3.Count -gt 0) {
	# 超容差才判失败；只是漂移就提示出来，别让"长期贴着容差上限"悄悄变成新常态
	$pass.Add("性能基准  注意  有 $($warn3.Count) 条 WARN（未超容差，不判失败）")
}

# ---- 4) / 5) 音效联调 ----
$r4 = Invoke-GodotStep -Name 'sfx_battle_check' -Extra @('--script', 'res://tools/sfx_battle_check.gd')
$r5 = Invoke-GodotStep -Name 'sfx_map_check' -Extra @('--script', 'res://tools/sfx_map_check.gd')
foreach ($r in @($r4, $r5)) {
	$hasPass = @($r.Lines | Where-Object { $_ -match 'PASS' }).Count -gt 0
	$hasSkip = @($r.Lines | Where-Object { $_ -match 'SKIP' }).Count -gt 0
	if ($hasSkip -and -not $hasPass) {
		$fail.Add("音效联调  FAIL  出现 SKIP（AudioConfig.enabled=false 时不算通过）")
	}
}

# ---- 6) 主场景 900 帧 + 生成统计比对基线 ----
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
