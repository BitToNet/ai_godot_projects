## =============================================================================
##  Strings —— 界面文案常量表（第六轮 ⑥ i18n 起步）
##
##  为什么要有它：文案原本散落在各 UI 脚本里，改一处措辞要在多个文件里找，也没法一眼看出
##  「哪些字是给玩家看的」。集中到一张表里之后，后续加语言（第二语言 = 再开一张表）才有落点。
##
##  本轮的三条硬规则：
##   1. **值是逐字保真的**：迁移只改「字面量在哪」，不改「屏幕上是什么」。门禁里的断言
##      （例如 hud_check 直接断言 "钱袋 %d 金"）就是这条规则的守卫。
##   2. scripts/ui 下的界面文案已**全部**迁进本表（TopBar 起步，其余六个界面随后一批迁完）；
##      进度由 tools/i18n_check.gd 的棘轮数字钉着（现在 ui_total = 0，往后只许保持 0）。
##   3. 常量名用 SCREAMING_SNAKE；带格式符的常量由调用点自己 `% [...]`，本表不碰格式化。
## =============================================================================
class_name Strings
extends RefCounted

# ---- 顶栏（TopBar.gd）----
const PURSE_LINE := "钱袋 %d 金 · 粮 %d 件 · 士气 %d · 声望 %d · %s %d/%d"
const ARREARS := " · 欠薪 %d 周"
const DAY_LABEL := "第 %d 天   %s"
const SPEED_PAUSED := "暂停"
const SPEED_MULT := "×%d"
const SPEED_HINT := "时间流速：%s"
const PAUSE_BADGE := "⏸ 时间已暂停（长按 %s 流动 / 点击地图行军）"
const NIGHT_BADGE := "🌙 夜色降临，定居点点亮灯火"
const TERRAIN := "当前地形："

# ---- 操作说明（HelpPanel.gd）----
const HELP_TITLE := "【操作】"
const HELP_CLICK_MOVE := "左键点击地面：部队寻路移动（行军途中时间流动，抵达后立刻暂停）"
const HELP_SELECT := "左键点击地图上的定居点 / 部队：选中并看详情（面板上可前往 / 进入 / 追踪）"
const HELP_SELECT_AGAIN := "再点一次同一座城 = 进城；点空地 = 取消选中"
const HELP_INTERACT := "进城办事：走到村庄 / 城镇 / 城堡旁按（补给 / 招募 / 贸易 / 驻军）"
const HELP_TIME_FLOW := "长按 = 原地推进世界时间；行军途中按下 = 立刻停止前进并暂停"
const HELP_PAN := "平移视角（也可靠屏幕边缘移动鼠标）"
const HELP_ZOOM := "缩放：近处平视 / 远处俯瞰"
const HELP_ROTATE := "旋转视角：左右转向（鼠标中键 / 右键拖拽亦可）"
const HELP_FOCUS := "回到玩家部队"
const HELP_SPEED := "切换时间流速 ×1/×2/×4"
const HELP_VEGETATION := "显示 / 隐藏植被"
const HELP_MUTE := "音效 + 背景音乐静音 / 恢复"
const HELP_FACTION_1 := "只看某势力领地标签（其余势力见下方两行）"
const HELP_FACTION_2 := "另看一个势力的领地标签"
const HELP_FACTION_3 := "再看最后一个势力的领地标签"
const HELP_SAVE := "快速存档（没有面板 / 不在战斗时才允许）"
const HELP_LOAD := "快速读档（回到上次存档；会重跑一遍地图生成）"

# ---- 开场加载遮罩（LoadingOverlay.gd）----
const LOADING_TITLE := "骑马与砍杀 · 战略大地图"
const LOADING_SUBTITLE := "程序化生成中：地形 / 河流 / 植被 / 定居点 / 道路 / 部队"
const LOADING_PREPARING := "准备中…"

# ---- 遭遇对话框（EncounterDialog.gd）----
## 兜底两行：只有「没有数据来源」的调用点才会用到（截图脚本 / 只关心开关的自检）
const ENCOUNTER_ATTACK_LABEL := "攻 击"
const ENCOUNTER_ATTACK_HINT := "进入 Boss 战"
const ENCOUNTER_RETREAT_LABEL := "撤 退"
const ENCOUNTER_RETREAT_HINT := "不战而走（有代价）"
const ENCOUNTER_HINT_LINE := "%s 确认      %s 撤退      ↑↓ 选择条目"

# ---- 进城菜单（SettlementDialog.gd）----
const SETTLEMENT_HINT_LINE := "%s 确认      %s 离开      ↑↓ 选择条目"

# ---- 选中面板（SelectionPanel.gd / SelectionSystem.gd）----
## 标题 / 正文都吃系统给的数据（SelectionSystem 组好字符串），面板只照着画。
const SELECT_TITLE_SETTLEMENT := "%s　%s"
const SELECT_TITLE_PARTY := "[%s] %s"
const SELECT_BODY_SETTLEMENT := "类型：%s\n势力：%s\n繁荣度：%d（%s）　驻军：%d 人\n领地归属：%s\n距离：%d 米"
const SELECT_BODY_PARTY := "阵营：%s\n兵力：%d 人　状态：%s%s\n距离：%d 米"
const SELECT_BODY_PARTY_LEAD := "\n首领：%s"
const SELECT_ACT_TRAVEL := "前往"
const SELECT_ACT_TRAVEL_HINT := "部队自动寻路过去，抵达后停下"
const SELECT_ACT_ENTER := "进入"
const SELECT_ACT_ENTER_HINT := "进城办事：补给 / 招募 / 贸易 / 驻军"
const SELECT_ACT_ENTER_FAR := "距离 %d 米 —— 先过去，抵达后自动进城"
const SELECT_ACT_TRACK := "追踪"
const SELECT_ACT_TRACK_HINT := "跟着它走（它改向就重新寻路；我军一停下就解除）"
const SELECT_HINT_LINE := "%s 执行      %s 关闭选中      ↑↓ 切换条目"
const SELECT_CLOSE := "close"
## 动作执行结果的口头反馈（Main 用；「按了没反应」是最难查的一类问题）
const SELECT_TRAVEL_FIRST := "先前往 %s（还有 %d 米），抵达后自动进城"
const SELECT_TRAVEL_UNREACHABLE := "到不了 %s：那里无法通行"
const SELECT_ENTER_FAILED := "现在无法进城（世界时间被别人锁着）"
const SELECT_TRACK_ON := "追踪 %s"
const SELECT_TRACK_LOST := "追踪目标已不在地图上"

# ---- 性能面板（DebugStatsPanel.gd）----
const STATS_LINE := "FPS %d   绘制调用 %d   三角形 %.1f 万"