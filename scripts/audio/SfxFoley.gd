## =============================================================================
##  SfxFoley —— 移动 / 打击类音效的**录音素材**层
##  （脚步 / 马蹄 / 起跳落地 / 闪避 / 命中 / 弹反 / 挥砍）
##
##  为什么要单独一层：SfxSynth 是代码合成，做"金属"与"破风"这类音色够用，但
##  脚步这种东西靠"噪声 + 包络 + 一点点空腔共振"合成，听感就是电子味的"噗、噗"，
##  参数怎么调都不像真实的鞋底—地面摩擦；命中/弹反同理，合成出来的"刀剑交击"
##  缺少真实录音的瞬态细节（需求方要求参考《只狼》/《黑神话：悟空》的打击感，
##  并直接提供了三段打击素材）。所以这一层直接换真实录音素材：
##
##   · 每个动作 **2~4 个变体（take）**，播放时随机挑一个 —— 连续跑动 / 连续命中的
##     时候不会听出"同一段在循环"，这是和单条合成音色最大的听感差别；
##   · 再叠 Sfx.gd 的 ±音高抖动与分类音量（抖动逻辑不变，这里只管"素材本身"）；
##   · 素材 **缺失时静默降级**：对应动作继续用 SfxSynth 的合成音色，只 push_warning，
##     游戏照常跑（与 Bgm.gd 音频缺失时的处理一致）。
##
##  素材来源见 `audio/sfx/foley/CREDITS.md`：一部分是**需求方提供**的录音
##  （击中 / 弹反 / 攻击 / 荒野脚步），一部分是 CC0 公有领域素材（Kenney、
##  OpenGameArt）。CC0 部分可随本仓库公开分发；需求方提供的录音请自行确认权利。
##
##  响度：每个文件都不是随手归一化的，而是按 `tools/sfx_foley_check.gd` 的对照结果
##  与**它替换掉的合成音色**对齐（峰值与 10ms 窗口 RMS 两个口径各让一半），
##  这样换素材不会顺手改掉既有混音平衡。改素材后请重跑该自检重新校准。
##
##  为什么用 CACHE_MODE_IGNORE 加载：与 Bgm.gd 同一个坑 —— 走全局资源缓存的话，
##  引擎收尾时缓存还钉着这些流，headless 跑主场景会报
##  `ERROR: N resources still in use at exit`，而 tools/run_checks.ps1 对 ERROR 零容忍。
##  绕开缓存后这些流只有 Sfx 的音色库持有，退出时自然释放。
## =============================================================================
class_name SfxFoley
extends RefCounted

const DIR := "res://audio/sfx/foley"

## 动作 id -> [变体文件名（不含目录与扩展名）……]
##
## 刻意写成"显式清单"而不是扫描目录：导出后的 PCK 里不能保证列得出源文件，
## 而清单是确定性的，也能让自检直接对着它核对"缺了哪一个 take"。
## 清单顺序 = 变体顺序（随机挑选用下标，顺序本身不影响听感）。
const SETS := {
	## 战斗跑步（左右脚交替触发，见 PlayerFighter 的脚步节拍）
	"step_a":     ["step_a_01", "step_a_02", "step_a_03", "step_a_04"],
	"step_b":     ["step_b_01", "step_b_02", "step_b_03", "step_b_04"],
	## Boss 的沉重脚步（体型大 → 更低的落点 + 更多碎砂石）
	"step_heavy": ["step_heavy_01", "step_heavy_02", "step_heavy_03"],
	"jump":       ["jump_01", "jump_02", "jump_03"],
	"land":       ["land_01", "land_02", "land_03"],
	## 闪避：布料 + 短促破风（完美闪避的"铃声提示"仍由合成音色负责，见 SfxSynth）
	"dodge":      ["dodge_01", "dodge_02", "dodge_03"],
	## 大地图行军马蹄（前蹄 / 后蹄）
	"hoof_a":     ["hoof_a_01", "hoof_a_02", "hoof_a_03", "hoof_a_04"],
	"hoof_b":     ["hoof_b_01", "hoof_b_02", "hoof_b_03", "hoof_b_04"],
	## 命中 / 弹反 / 挥砍：需求方直接提供了这三段素材（击中 / 弹反 / 攻击），
	## 用它们替换合成音色；会心与弹返再叠一层 CC0 的刀剑交击，做出"更脆更亮"的层次。
	"hit_light":     ["hit_light_01", "hit_light_02"],
	"hit_heavy":     ["hit_heavy_01", "hit_heavy_02"],
	"hit_crit":      ["hit_crit_01", "hit_crit_02"],
	"parry":         ["parry_01", "parry_02"],
	"parry_reflect": ["parry_reflect_01", "parry_reflect_02"],
	"sword_wave":    ["sword_wave_01", "sword_wave_02"],
}

static var _variants: Dictionary = {}     ## id -> Array[AudioStream]
static var _missing: Array[String] = []   ## 找不到 / 读不出来的文件（自检与报告用）
static var _ready: bool = false
static var _load_ms: int = 0

# =============================================================== 查询（自检用）
static func is_ready() -> bool:
	return _ready

## 加载耗时（毫秒）。发生在 Loading 遮罩里，几十毫秒级。
static func load_ms() -> int:
	return _load_ms

## 缺失的文件清单（空数组 = 素材全部就位）
static func missing() -> Array[String]:
	return _missing

## 全部动作 id（= SETS 的键，顺序稳定）
static func ids() -> Array:
	return SETS.keys()

## 已挂上录音素材的动作 id
static func loaded_ids() -> Array:
	return _variants.keys()

static func variants_of(id: String) -> Array:
	var v: Variant = _variants.get(id)
	return v if v is Array else []

static func variant_count(id: String) -> int:
	return variants_of(id).size()

static func total_variants() -> int:
	var n := 0
	for id in _variants:
		n += (_variants[id] as Array).size()
	return n

# =============================================================== 加载
## 一次性加载全部变体（幂等）。在 Sfx.setup() 里调用一次。
## 体量：约 30 个短音效（每个 0.1~0.5 秒、44.1 kHz 单声道 16 bit）合计 < 1 MB，
## 冷盘加载 ≈ 几十毫秒，没必要像合成那样切片让帧 —— 实测值见 load_ms()。
static func load_all() -> void:
	if _ready:
		return
	var t0 := Time.get_ticks_msec()
	_variants.clear()
	_missing.clear()
	for id in SETS:
		var arr: Array = []
		for base in SETS[id]:
			var path := "%s/%s.wav" % [DIR, String(base)]
			if not ResourceLoader.exists(path):
				_missing.append(path)
				continue
			var st: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if st is AudioStream and (st as AudioStream).get_length() > 0.0:
				arr.append(st)
			else:
				_missing.append(path)
		if not arr.is_empty():
			_variants[String(id)] = arr
	_load_ms = Time.get_ticks_msec() - t0
	_ready = true
	if not _missing.is_empty():
		push_warning("SfxFoley：%d 个录音变体缺失，对应动作自动回退到合成音色（见 SfxFoley.missing()）" % _missing.size())
