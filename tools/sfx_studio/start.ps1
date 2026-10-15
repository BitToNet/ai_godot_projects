#Requires -Version 5.1
<#
  音效调音台 · 一键启动
  ---------------------------------------------------------------------------
  做三件事，然后停在服务上（Ctrl+C 结束）：
    1) 缺试听音频就生成（tools/sfx_tool.gd -- --wav → audio_preview/*.wav）
    2) 导出清单（tools/sfx_studio_export.gd → tools/sfx_studio/manifest.json）
    3) 起本地服务并打开浏览器（serve.py，静态站点 + user:// 配置读写）

  用法：
    pwsh -File tools\sfx_studio\start.ps1
    powershell -ExecutionPolicy Bypass -File tools\sfx_studio\start.ps1 -Port 8790
#>
[CmdletBinding()]
param(
    [int]$Port = 8787,
    [string]$Engine = '',
    [switch]$NoOpen,
    [switch]$SkipExport
)

$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not (Test-Path (Join-Path $Root 'project.godot'))) {
    Write-Host "[X] 这里不是工程根目录：$Root" -ForegroundColor Red
    exit 1
}

# 引擎：-Engine 参数 > 环境变量 GODOT_BIN > 本机既定路径（用户全局约定）
if (-not $Engine) { $Engine = $env:GODOT_BIN }
if (-not $Engine) { $Engine = 'G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe' }
if (-not (Test-Path $Engine)) {
    Write-Host "[X] 找不到 Godot 引擎：$Engine" -ForegroundColor Red
    Write-Host "    用 -Engine '<引擎路径>' 或设置 `$env:GODOT_BIN 指定" -ForegroundColor Yellow
    exit 1
}

function Invoke-GodotStep {
    param([string]$Label, [string[]]$Extra)
    Write-Host "    `$ godot $($Extra -join ' ')" -ForegroundColor DarkGray
    $godotArgs = @('--headless', '--path', $Root) + $Extra
    $out = & $Engine @godotArgs 2>&1
    $code = $LASTEXITCODE
    foreach ($line in $out) { Write-Host "    $line" -ForegroundColor DarkGray }
    return $code
}

# ---------------------------------------------------------------- 1) 试听音频
$probe = Join-Path $Root 'audio_preview\hit_light.wav'
if (-not (Test-Path $probe)) {
    Write-Host "[1/3] 生成试听音频（第一次会慢一点）..." -ForegroundColor Cyan
    $c = Invoke-GodotStep -Label '合成试听 wav' -Extra @('--script', 'res://tools/sfx_tool.gd', '--', '--wav')
    if ($c -ne 0) {
        Write-Host "[X] 试听音频生成失败（exit $c）" -ForegroundColor Red
        exit $c
    }
} else {
    Write-Host "[1/3] 试听音频已就绪，跳过（audio_preview\*.wav）" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- 2) 清单
if ($SkipExport) {
    Write-Host "[2/3] 跳过清单导出（-SkipExport）" -ForegroundColor DarkGray
} else {
    Write-Host "[2/3] 导出清单 manifest.json ..." -ForegroundColor Cyan
    $c = Invoke-GodotStep -Label '导出清单' -Extra @('--script', 'res://tools/sfx_studio_export.gd')
    if ($c -ne 0) {
        Write-Host "[!] 清单导出失败（exit $c）：页面会用上一次的清单，音色表可能不是最新的" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------- 3) 服务
$py = ''
foreach ($cand in @('python', 'py')) {
    if (Get-Command $cand -ErrorAction SilentlyContinue) { $py = $cand; break }
}
if (-not $py) {
    Write-Host "[X] 找不到 Python（serve.py 只用标准库，Python 3 即可）" -ForegroundColor Red
    Write-Host "    装了之后确认 python 在 PATH 上，或直接双击 index.html 用降级模式。" -ForegroundColor Yellow
    exit 1
}

Write-Host "[3/3] 启动本地服务（下面的地址就是调音台，Ctrl+C 结束）" -ForegroundColor Cyan
$serveArgs = @((Join-Path $PSScriptRoot 'serve.py'), '--port', "$Port")
if ($NoOpen) { $serveArgs += '--no-open' }
& $py @serveArgs
exit $LASTEXITCODE