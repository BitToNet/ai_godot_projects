## =============================================================================
##  sfx_foley_build.ps1 —— audio/sfx/foley 那 40 个 WAV 的**推导配方**（一次性脚本）
##
##  这不是游戏构建 / 门禁的一部分：SfxFoley.gd 运行时只读 audio/sfx/foley/*.wav，
##  本脚本只在需要**重新生成**那批素材时手工运行。来源与授权见
##  `audio/sfx/foley/CREDITS.md`（含每个源文件的 URL 与授权）。
##
##  运行前提：把源素材按下面的 ASCII 目录结构放到 -Scratch 指定的暂存目录
##  （ASCII 名字是必须的：Windows PowerShell 5.1 读无 BOM 的 .ps1 会按 ANSI 解码，
##   脚本里出现中文路径会直接变成乱码，所以用户提供的中文文件名先在暂存目录改名）：
##
##    <Scratch>\user\footsteps.wav    <- 需求方"荒野中的脚步声"录音
##    <Scratch>\user\hit.mp3          <- 需求方"击中"
##    <Scratch>\user\parry.wav        <- 需求方"弹反"
##    <Scratch>\user\attack.wav       <- 需求方"攻击"
##    <Scratch>\ex_impact-sounds\     <- Kenney Impact Sounds（CC0）
##    <Scratch>\ex_rpg-audio\         <- Kenney RPG Audio（CC0）
##    <Scratch>\x_oga_weapons-apparel\sfx\  <- OGA Fantasy Weapons and Apparel SFX（CC0）
##    <Scratch>\x_oga_qubodupImpact\qubodupImpact\ <- OGA qubodupImpact（CC0）
##    <Scratch>\oga_Trot.ogg          <- OGA Horse Trotting（CC0）
##
##  用法（改完素材记得重跑 tools/sfx_foley_check.gd 复核响度与规格）：
##    pwsh -File tools/sfx_foley_build.ps1 -Scratch <暂存目录> -OutDir <工程>\audio\sfx\foley
##
##  下面的注释块是这套素材的详细说明。
## =============================================================================
## =============================================================================
## build_foley.ps1 -- build the game's recorded-SFX layer (movement + impacts)
##
## Output: audio/sfx/foley/*.wav  (mono, 44100 Hz, 16-bit) -- one file per take.
## Names must match SfxFoley.SETS in scripts/audio/SfxFoley.gd exactly.
##
## Sources (staged under -Scratch with ASCII names; see audio/sfx/foley/CREDITS.md)
##   user\footsteps.wav   author-provided 18 s walking recording (cut into takes)
##   user\hit.mp3         author-provided impact
##   user\parry.wav       author-provided parry clang
##   user\attack.wav      author-provided attack swing
##   ex_impact-sounds\    Kenney "Impact Sounds"                        CC0
##   ex_rpg-audio\        Kenney "RPG Audio"                            CC0
##   x_oga_weapons-apparel\sfx\  OGA "Fantasy Weapons and Apparel SFX"  CC0
##   x_oga_qubodupImpact\ OGA "qubodupImpact"                           CC0
##   oga_Trot.ogg         OGA "Horse Trotting"                          CC0
##
## Every output uses one chain: slice -> mono 44.1k -> filters/pitch -> optional
## layer mix -> fade out -> loudness match -> 16-bit WAV.
##
## Loudness is matched on "max 10 ms window RMS" (a robust proxy for impulsive
## sounds) against ONE common target, so the per-id dB table in SfxSynth.SPECS
## keeps shaping the mix exactly as it did for the synthesized tones.
##
## ASCII-only on purpose: Windows PowerShell 5.1 reads .ps1 as ANSI when the file
## has no BOM, so non-ASCII literals here would be mangled.
## =============================================================================
param(
  [string]$Scratch = "F:\aigc_code\_sfx_scratch",
  [string]$OutDir = "F:\aigc_code\ai_godot_projects\audio\sfx\foley",
  [double]$TargetWindowRmsDb = -19.0,
  [double]$MaxPeakDb = -1.0,
  [switch]$NoWrite
)
$ErrorActionPreference = "Stop"
$ffmpeg = "C:\ffmpeg\bin\ffmpeg.exe"
$ffprobe = "C:\ffmpeg\bin\ffprobe.exe"

$U = "$Scratch\user\footsteps.wav"
$H = "$Scratch\user\hit.mp3"
$P = "$Scratch\user\parry.wav"
$A = "$Scratch\user\attack.wav"
$KI = "$Scratch\ex_impact-sounds\Audio"
$KR = "$Scratch\ex_rpg-audio\Audio"
$WA = "$Scratch\x_oga_weapons-apparel\sfx"
$QB = "$Scratch\x_oga_qubodupImpact\qubodupImpact"
$TR = "$Scratch\oga_Trot.ogg"

## Noise cleanup + gentling for the location recording; the kept takes measure
## 35-46 dB SNR after the first two stages.
## The compressor is what makes the recorded footsteps usable in a game mix: a raw
## location footstep measures a ~13 dB crest factor, while the dense filtered-noise
## "step" it replaces measures only ~6 dB, so at equal transient level the recording
## would sit ~7 dB lower in average energy. 2:1 above -30 dB lifts the body of the
## step without squashing the attack (the peak still leads the decay by ~9 dB).
$clean = "highpass=f=70,afftdn=nr=16:nf=-46,acompressor=threshold=-30dB:ratio=2:attack=5:release=120"

## Synth-match gain per action (dB), from tools/sfx_foley_check.gd.
## Stage 1 matches every file to one common window-RMS target; stage 2 then shifts
## each action to the loudness of the SYNTH tone it replaces (midpoint of peak
## alignment and window-RMS alignment). Without stage 2 the recorded layer would
## sit 8-13 dB under the tones and read as "sound gone missing".
## step_a / step_b are the exception: they are the raw location footsteps, whose
## crest factor (~13 dB) is twice that of the dense filtered-noise tone they replace
## (~6 dB), so the midpoint is unreachable without limiting the attack away. They
## are therefore aligned on PEAK only -- the transient lands exactly where it did,
## and the average energy stays ~8 dB lower, which is the honest consequence of a
## recording that actually decays.
$match = @{
  step_a = 3.7; step_b = 2.5; step_heavy = 10.1; jump = 10.2; land = 12.4
  dodge = 7.3; hoof_a = 10.0; hoof_b = 10.3
  hit_light = 5.1; hit_heavy = 7.6; hit_crit = 2.8
  parry = 8.1; parry_reflect = 8.7; sword_wave = 8.8
}

function New-Foley {
  param(
    [string]$Name, [hashtable]$Main,
    [array]$Layers = @(), [double]$GainDb = 0.0, [double]$FadeOut = 0.06
  )
  return [pscustomobject]@{
    name = $Name; main = $Main; layers = $Layers; gain_db = $GainDb; fade_out = $FadeOut
  }
}
$items = New-Object System.Collections.ArrayList

# ------------------------------------------------- battle footsteps (author takes)
# onsets measured on the raw recording, then filtered by post-denoise SNR;
# step_a / step_b are two families of takes (NOT a left/right-foot claim).
$stepA = @(0.420, 3.190, 5.780, 16.190)
$stepB = @(1.610, 3.750, 9.280, 17.290)
for ($i = 0; $i -lt 4; $i++) {
  [void]$items.Add((New-Foley -Name ("step_a_{0:D2}" -f ($i + 1)) -Main @{ src = $U; start = $stepA[$i]; len = 0.32; filters = $clean } -FadeOut 0.07))
  [void]$items.Add((New-Foley -Name ("step_b_{0:D2}" -f ($i + 1)) -Main @{ src = $U; start = $stepB[$i]; len = 0.32; filters = $clean } -FadeOut 0.07))
}
# ------------------------------------------------------ boss heavy step (big body)
for ($i = 0; $i -lt 3; $i++) {
  [void]$items.Add((New-Foley -Name ("step_heavy_{0:D2}" -f ($i + 1)) `
        -Main @{ src = "$KI\footstep_grass_00${i}.ogg"; start = 0.0; len = 0.45; filters = "highpass=f=50,asetrate=44100*0.85,aresample=44100" } `
        -Layers @(@{ src = "$KI\impactSoft_heavy_00${i}.ogg"; start = 0.0; len = 0.35; filters = "highpass=f=35"; gain_db = -5.0 }) `
        -FadeOut 0.10))
}
# ------------------------------------------------------------- hooves (world map)
# real trot onsets (10 hoof impacts in the 12.45 s recording); a short wood knock
# is layered on for the hard "clop" of a shod hoof.
$trotA = @(0.05, 1.30, 2.52, 4.61)
$trotB = @(0.89, 1.72, 4.22, 9.33)
for ($i = 0; $i -lt 4; $i++) {
  [void]$items.Add((New-Foley -Name ("hoof_a_{0:D2}" -f ($i + 1)) `
        -Main @{ src = $TR; start = $trotA[$i]; len = 0.30; filters = "highpass=f=70" } `
        -Layers @(@{ src = "$KI\impactWood_light_00${i}.ogg"; start = 0.0; len = 0.20; filters = "highpass=f=180"; gain_db = -7.0 }) `
        -FadeOut 0.06))
  [void]$items.Add((New-Foley -Name ("hoof_b_{0:D2}" -f ($i + 1)) `
        -Main @{ src = $TR; start = $trotB[$i]; len = 0.30; filters = "highpass=f=80,asetrate=44100*0.94,aresample=44100" } `
        -Layers @(@{ src = "$KI\impactWood_medium_00${i}.ogg"; start = 0.0; len = 0.20; filters = "highpass=f=180"; gain_db = -7.0 }) `
        -FadeOut 0.06))
}
# ---------------------------------------------------------------------- landing
[void]$items.Add((New-Foley -Name "land_01" `
      -Main @{ src = "$QB\qubodupImpactMeat01.ogg"; start = 0.0; len = 0.36; filters = "highpass=f=40" } `
      -Layers @(@{ src = "$KI\impactSoft_heavy_000.ogg"; start = 0.0; len = 0.30; filters = "highpass=f=35"; gain_db = -4.0 }) -FadeOut 0.10))
[void]$items.Add((New-Foley -Name "land_02" `
      -Main @{ src = "$QB\qubodupImpactMeat02.ogg"; start = 0.0; len = 0.36; filters = "highpass=f=40" } `
      -Layers @(@{ src = "$KI\impactSoft_heavy_001.ogg"; start = 0.0; len = 0.30; filters = "highpass=f=35"; gain_db = -4.0 }) -FadeOut 0.10))
[void]$items.Add((New-Foley -Name "land_03" `
      -Main @{ src = "$QB\qubodupImpactMeat01.ogg"; start = 0.0; len = 0.36; filters = "highpass=f=40,asetrate=44100*0.93,aresample=44100" } `
      -Layers @(@{ src = "$KI\impactSoft_heavy_002.ogg"; start = 0.0; len = 0.30; filters = "highpass=f=35"; gain_db = -4.0 }) -FadeOut 0.10))
# ------------------------------------------------------------------------ jump
for ($i = 1; $i -le 3; $i++) {
  [void]$items.Add((New-Foley -Name ("jump_{0:D2}" -f $i) `
        -Main @{ src = "$WA\boots-leather-jump-0${i}.wav"; start = 0.0; len = 0.42; filters = "highpass=f=90" } `
        -Layers @(@{ src = "$KR\cloth${i}.ogg"; start = 0.0; len = 0.30; filters = "highpass=f=120"; gain_db = -7.0 }) `
        -FadeOut 0.08))
}
# ----------------------------------------------------------------------- dodge
$dodgeCloth = @(4, 3, 2)
for ($i = 1; $i -le 3; $i++) {
  [void]$items.Add((New-Foley -Name ("dodge_{0:D2}" -f $i) `
        -Main @{ src = "$KR\drawKnife${i}.ogg"; start = 0.0; len = 0.32; filters = "highpass=f=140" } `
        -Layers @(@{ src = "$KR\cloth$($dodgeCloth[$i - 1]).ogg"; start = 0.0; len = 0.25; filters = "highpass=f=120"; gain_db = -8.0 }) `
        -FadeOut 0.07))
}
# --------------------------------------------------------------------- impacts
[void]$items.Add((New-Foley -Name "hit_light_01" -Main @{ src = $H; start = 0.19; len = 0.36; filters = "highpass=f=45" }))
[void]$items.Add((New-Foley -Name "hit_light_02" -Main @{ src = $H; start = 0.26; len = 0.32; filters = "highpass=f=45" }))
[void]$items.Add((New-Foley -Name "hit_heavy_01" `
      -Main @{ src = $H; start = 0.19; len = 0.42; filters = "highpass=f=40,asetrate=44100*0.90,aresample=44100" } `
      -Layers @(@{ src = "$KI\impactSoft_heavy_003.ogg"; start = 0.0; len = 0.30; filters = "highpass=f=35"; gain_db = -6.0 }) -FadeOut 0.09))
[void]$items.Add((New-Foley -Name "hit_heavy_02" `
      -Main @{ src = $H; start = 0.26; len = 0.40; filters = "highpass=f=40,asetrate=44100*0.90,aresample=44100" } `
      -Layers @(@{ src = "$KI\impactSoft_heavy_004.ogg"; start = 0.0; len = 0.30; filters = "highpass=f=35"; gain_db = -6.0 }) -FadeOut 0.09))
[void]$items.Add((New-Foley -Name "hit_crit_01" `
      -Main @{ src = $H; start = 0.19; len = 0.40; filters = "highpass=f=60,asetrate=44100*1.12,aresample=44100" } `
      -Layers @(@{ src = "$WA\sword-knife-clash-15.wav"; start = 0.0; len = 0.30; filters = "highpass=f=300"; gain_db = -7.0 }) -FadeOut 0.07))
[void]$items.Add((New-Foley -Name "hit_crit_02" `
      -Main @{ src = $H; start = 0.26; len = 0.38; filters = "highpass=f=60,asetrate=44100*1.12,aresample=44100" } `
      -Layers @(@{ src = "$WA\sword-knife-clash-29.wav"; start = 0.0; len = 0.30; filters = "highpass=f=300"; gain_db = -7.0 }) -FadeOut 0.07))
# --------------------------------------------------------------- parry clangs
[void]$items.Add((New-Foley -Name "parry_01" -Main @{ src = $P; start = 0.0; len = 0.72; filters = "highpass=f=60" } -FadeOut 0.10))
[void]$items.Add((New-Foley -Name "parry_02" -Main @{ src = $P; start = 0.0; len = 0.50; filters = "highpass=f=60,asetrate=44100*1.06,aresample=44100" } -FadeOut 0.08))
[void]$items.Add((New-Foley -Name "parry_reflect_01" `
      -Main @{ src = $P; start = 0.0; len = 0.55; filters = "highpass=f=90,asetrate=44100*1.18,aresample=44100" } `
      -Layers @(@{ src = "$WA\sword-knife-clash-13.wav"; start = 0.0; len = 0.30; filters = "highpass=f=300"; gain_db = -9.0 }) -FadeOut 0.09))
[void]$items.Add((New-Foley -Name "parry_reflect_02" `
      -Main @{ src = $P; start = 0.0; len = 0.45; filters = "highpass=f=90,asetrate=44100*1.26,aresample=44100" } `
      -Layers @(@{ src = "$WA\sword-knife-clash-20.wav"; start = 0.0; len = 0.30; filters = "highpass=f=300"; gain_db = -9.0 }) -FadeOut 0.09))
# -------------------------------------------------------------- sword swings
[void]$items.Add((New-Foley -Name "sword_wave_01" -Main @{ src = $A; start = 0.0; len = 0.44; filters = "highpass=f=120" } -FadeOut 0.08))
[void]$items.Add((New-Foley -Name "sword_wave_02" -Main @{ src = $A; start = 0.0; len = 0.42; filters = "highpass=f=120,asetrate=44100*1.08,aresample=44100" } -FadeOut 0.08))

# ======================================================================= run
if (-not $NoWrite) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$tmpDir = Join-Path $env:TEMP ("foley_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

function Get-WindowRmsDb {
  param([string]$Path, [double]$WindowMs = 10.0, [int]$Rate = 8000)
  $raw = Join-Path $tmpDir ([guid]::NewGuid().ToString("N") + ".raw")
  & $ffmpeg -hide_banner -loglevel error -y -i $Path -ac 1 -ar $Rate -f s16le -acodec pcm_s16le $raw
  $bytes = [System.IO.File]::ReadAllBytes($raw); Remove-Item $raw -Force
  $n = [int]($bytes.Length / 2); $W = [int]($Rate * $WindowMs / 1000.0)
  $frames = [int][math]::Floor($n / $W)
  $best = -140.0
  for ($f = 0; $f -lt $frames; $f++) {
    $off = $f * $W; $sum = 0.0
    for ($i = 0; $i -lt $W; $i++) { $v = [BitConverter]::ToInt16($bytes, ($off + $i) * 2) / 32768.0; $sum += $v * $v }
    $d = 20.0 * [math]::Log10([math]::Sqrt($sum / $W) + 1e-9)
    if ($d -gt $best) { $best = $d }
  }
  return $best
}
function Get-PeakDb {
  param([string]$Path)
  ## Windows PowerShell 5.1 turns a native command's stderr into a terminating
  ## NativeCommandError while $ErrorActionPreference is "Stop" -- even when that
  ## stderr is redirected to a file. Ease the preference for this one call.
  $err = Join-Path $tmpDir ([guid]::NewGuid().ToString("N") + ".txt")
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  & $ffmpeg -hide_banner -nostats -i $Path -af volumedetect -f null - 2>$err
  $ErrorActionPreference = $prev
  $txt = [System.IO.File]::ReadAllText($err)
  Remove-Item $err -Force
  $m = [regex]::Match($txt, "max_volume:\s*(-?[0-9.]+) dB")
  if (-not $m.Success) { throw "volumedetect gave no max_volume for $Path" }
  return [double]$m.Groups[1].Value
}

$rows = @()
foreach ($it in $items) {
  $tmp = Join-Path $tmpDir ("$($it.name).wav")
  $final = Join-Path $OutDir ("$($it.name).wav")
  $fadeSt = [double]$it.main.len - [double]$it.fade_out
  if ($fadeSt -lt 0.0) { $fadeSt = 0.0 }
  $fade = "afade=t=out:st=$($fadeSt.ToString('0.###')):d=$(([double]$it.fade_out).ToString('0.###'))"
  $mf = [string]$it.main.filters
  if ($mf -eq "") { $mf = "anull" }
  $a = @("-hide_banner", "-loglevel", "error", "-y",
    "-ss", $it.main.start.ToString('0.######'), "-t", $it.main.len.ToString('0.######'), "-i", $it.main.src)
  foreach ($ly in $it.layers) {
    $a += @("-ss", $ly.start.ToString('0.######'), "-t", $ly.len.ToString('0.######'), "-i", $ly.src)
  }
  if ($it.layers.Count -eq 0) {
    $a += @("-af", "$mf,$fade")
  }
  else {
    $fc = "[0:a]$mf[a0]"
    $mix = "[a0]"
    $idx = 0
    foreach ($ly in $it.layers) {
      $idx++
      $lf = [string]$ly.filters
      if ($lf -eq "") { $lf = "anull" }
      $lg = [double]$ly.gain_db
      $fc += ";[${idx}:a]$lf,volume=$($lg.ToString('0.###'))dB[a${idx}]"
      $mix += "[a${idx}]"
    }
    $fc += ";${mix}amix=inputs=$($idx + 1):duration=longest:normalize=0,$fade[out]"
    $a += @("-filter_complex", $fc, "-map", "[out]")
  }
  $a += @("-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", $tmp)
  & $ffmpeg @a
  if (-not (Test-Path $tmp)) { throw "ffmpeg failed for $($it.name) ($($it.main.src))" }

  $wr = Get-WindowRmsDb -Path $tmp
  $pk = Get-PeakDb -Path $tmp
  $sid = $it.name -replace '_\d+$', ''
  $shift = [double]$match[$sid]
  if ($null -eq $match[$sid]) { $shift = 0.0 }
  $gain = $TargetWindowRmsDb - $wr + [double]$it.gain_db + $shift
  $capped = $false
  if ($pk + $gain -gt $MaxPeakDb) { $gain = $MaxPeakDb - $pk; $capped = $true }
  $dur = [double](& $ffprobe -v error -show_entries format=duration -of csv=p=0 $tmp)
  if (-not $NoWrite) {
    & $ffmpeg -hide_banner -loglevel error -y -i $tmp -af ("volume=" + $gain.ToString('0.###') + "dB") -ac 1 -ar 44100 -c:a pcm_s16le $final
  }
  Remove-Item $tmp -Force
  $rows += [pscustomobject]@{
    name = $it.name; dur = $dur; gain = $gain; peak = ($pk + $gain); wrms = ($wr + $gain)
    layers = $it.layers.Count; capped = $capped
  }
}
"=== foley build: {0} files -> {1} ===" -f $rows.Count, $OutDir
"{0,-18} {1,7} {2,8} {3,8} {4,7} {5,7} {6}" -f "name", "dur(s)", "gain(dB)", "peak(dB)", "wrms", "layers", "capped"
foreach ($r in $rows) {
  "{0,-18} {1,7:N3} {2,8:N1} {3,8:N2} {4,7:N1} {5,7} {6}" -f $r.name, $r.dur, $r.gain, $r.peak, $r.wrms, $r.layers, $r.capped
}
"total {0:N2}s of audio   target wrms {1:N1} dB   peak cap {2:N1} dB" -f (($rows | Measure-Object dur -Sum).Sum), $TargetWindowRmsDb, $MaxPeakDb
Remove-Item -Recurse -Force $tmpDir
