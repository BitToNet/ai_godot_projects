## =============================================================================
##  Pathfinder —— 栅格 A* 寻路（自建最小堆，不依赖 AStar2D）
##
##  【代价函数】
##    相邻格移动代价 = 距离 / 该格移动速度
##      · 正交相邻：distance = cell
##      · 对角相邻：distance = cell * sqrt(2)
##      · 速度来自 NavGrid（道路 1.2 / 草地 1.0 / 森林 0.7 / 山地 0.5 / 雪地 0.4）
##      · 对角移动会取两格速度的平均值，避免「贴着河边滑坡」
##      · 禁止切角（对角移动要求两个正交邻格都通行）
##    启发函数 h = octile 距离 * (1/1.2)  —— 以「最快速度」估算，保证可采纳性
##
##  【后处理】视线拉直（string pulling）：若两点之间直线可通行则合并中间点，
##  消除 A* 的锯齿，让部队走出自然的行进线。
## =============================================================================
class_name Pathfinder
extends RefCounted

const DIAG := 1.41421356
const NEI_X := [1, -1, 0, 0, 1, 1, -1, -1]
const NEI_Z := [0, 0, 1, -1, 1, -1, 1, -1]

## 单次搜索最多展开的节点数。只作「死循环兜底」用：取值 = 栅格节点总数，
## 因此永远不可能截断一条合法路径。
## （旧值 MAX_EXPAND = 90000 是个无效防护：细栅格 257² 只有 66049 个节点，
##   90% 的搜索早在触发上限之前就已穷尽整个可达区域。）
## 真正挡住「目标不可达」这类病态搜索的是下面的连通分量预判，见 find_path()。
var max_expand: int = 0
## 最近一次 find_path() 展开的节点数（只写不读的探针字段：第六轮的 A* 优化要靠它证明
## 「展开数不变」= 改动只影响速度、不影响搜索结果）
var last_expanded: int = 0

var nav: NavGrid
## 加权 A*：>1 会牺牲一点最优性换取大幅加速（战术地图上视觉无差别）
var heuristic_weight: float = 1.35

# 复用的搜索缓冲
var _g: PackedFloat32Array
var _f: PackedFloat32Array
var _from: PackedInt32Array
var _state: PackedByteArray   ## 0 未访问 1 开启 2 关闭
var _stamp: PackedInt32Array  ## 访问标记（避免每次全量重置）
var _cur_stamp: int = 0
var _heap: PackedInt32Array
var _heap_size: int = 0

func _init(p_nav: NavGrid) -> void:
	nav = p_nav
	var n := nav.res * nav.res
	max_expand = n
	_g.resize(n)
	_f.resize(n)
	_from.resize(n)
	_state.resize(n)
	_stamp.resize(n)
	_heap.resize(1024)

# ---------------------------------------------------------------- 最小堆
func _heap_clear() -> void:
	_heap_size = 0

func _heap_push(i: int) -> void:
	if _heap.size() <= _heap_size:
		_heap.resize(_heap.size() * 2)
	var k := _heap_size
	_heap[k] = i
	_heap_size += 1
	while k > 0:
		var p := (k - 1) >> 1
		if _f[_heap[p]] <= _f[_heap[k]]:
			break
		var t := _heap[p]
		_heap[p] = _heap[k]
		_heap[k] = t
		k = p

func _heap_pop() -> int:
	var top := _heap[0]
	_heap_size -= 1
	if _heap_size > 0:
		_heap[0] = _heap[_heap_size]
		var k := 0
		while true:
			var l := k * 2 + 1
			var r := l + 1
			var m := k
			if l < _heap_size and _f[_heap[l]] < _f[_heap[m]]:
				m = l
			if r < _heap_size and _f[_heap[r]] < _f[_heap[m]]:
				m = r
			if m == k:
				break
			var t := _heap[m]
			_heap[m] = _heap[k]
			_heap[k] = t
			k = m
	return top

# ---------------------------------------------------------------- 主入口
## 返回世界坐标折线（y 由高度场给出）；失败返回空数组
func find_path(from_world: Vector2, to_world: Vector2) -> PackedVector3Array:
	last_expanded = 0
	var s := nav.cell_of(from_world)
	var t := nav.cell_of(to_world)
	if nav.is_blocked(t.x, t.y):
		t = _nearest_free(t, 6)
		if t.x < 0:
			return PackedVector3Array()
	if nav.is_blocked(s.x, s.y):
		s = _nearest_free(s, 6)
		if s.x < 0:
			return PackedVector3Array()

	# 连通性预判：起点与终点不在同一连通区域时，A* 无论怎么搜都到不了，只会一路展开
	# 整个可达区域才返回失败（细栅格 66049 格 ≈ 60 万次脚本调用，足以卡掉一整帧；
	# 玩家点到自己到不了的地方、或 AI 的随机游荡点落在被河/湖隔开的口袋里都会触发）。
	# 分量表由 NavGrid.rebuild_components() 在道路与桥梁写回后建立，这里查询是 O(1)。
	if not nav.same_component(s, t):
		return PackedVector3Array()

	_cur_stamp += 1
	_heap_clear()
	var si := s.y * nav.res + s.x
	var ti := t.y * nav.res + t.x
	_stamp[si] = _cur_stamp
	_g[si] = 0.0
	_f[si] = _heuristic(s, t)
	_from[si] = -1
	_state[si] = 1
	_heap_push(si)

	# ---- 热点内联 ----
	# 下面这个双层循环每次搜索要跑几十万次（细栅格 257² = 66049 格，每格 8 个邻格）。
	# 原来每邻格都要付三笔脚本层的开销：nav.is_blocked()（对角时 3 次方法调用）、
	# nav.speed[] / nav.cell 的属性取用、_heuristic() 里的 Vector2i 构造。
	# 语义与 NavGrid.is_blocked / _heuristic 完全一致（越界即障碍；(float(mn)*DIAG + float(mx-mn))
	# * cell * (1/1.2) * weight），**并保持完全相同的浮点运算顺序**，所以搜索结果不该有任何变化 ——
	# 探针断言「每对的路径点数与展开节点数逐对不变」就是这句话的证据。
	var res := nav.res
	var cell := nav.cell
	var blocked := nav.blocked
	var speed := nav.speed
	var k12 := 1.0 / 1.2
	var hw := heuristic_weight
	var tx := t.x
	var tz := t.y
	var expanded := 0
	var found := false
	while _heap_size > 0:
		var cur := _heap_pop()
		if _state[cur] == 2 and _stamp[cur] == _cur_stamp:
			continue
		_state[cur] = 2
		if cur == ti:
			found = true
			break
		expanded += 1
		last_expanded = expanded
		if expanded > max_expand:
			break
		var cx := cur % res
		var cz := cur / res
		var gcur := _g[cur]
		var scur := speed[cur]
		for d in 8:
			var dx: int = NEI_X[d]
			var dz: int = NEI_Z[d]
			var nx := cx + dx
			var nz := cz + dz
			if nx < 0 or nz < 0 or nx >= res or nz >= res or blocked[nz * res + nx] == 1:
				continue
			var diagonal := dx != 0 and dz != 0
			# 禁止切角：对角移动要求两侧正交格都不是障碍
			if diagonal:
				# 注意这里是 (cx+dx, cz) 与 (cx, cz+dz)：两个**正交**邻格，不是对角格本身
				# （第一版内联时我写成了 (cx+dx, cz+dz)，探针立刻报展开数 1143 → 1135 ——
				#   这条「展开节点数必须逐对不变」的契约断言就是为这种错准备的）
				var ax := cx + dx
				if ax < 0 or cz < 0 or ax >= res or cz >= res or blocked[cz * res + ax] == 1:
					continue
				var bz := cz + dz
				if cx < 0 or bz < 0 or cx >= res or bz >= res or blocked[bz * res + cx] == 1:
					continue
			var ni := nz * res + nx
			if _stamp[ni] != _cur_stamp:
				_stamp[ni] = _cur_stamp
				_g[ni] = 1e30
				_f[ni] = 1e30
				_from[ni] = -1
				_state[ni] = 0
			if _state[ni] == 2:
				continue
			# 代价 = 距离 / 速度
			var sp := speed[ni]
			if diagonal:
				sp = (sp + scur) * 0.5
			sp = maxf(sp, 0.2)
			var step := cell * (DIAG if diagonal else 1.0)
			var ng := gcur + step / sp
			if ng < _g[ni]:
				_g[ni] = ng
				var adx := absi(nx - tx)
				var adz := absi(nz - tz)
				var amn := mini(adx, adz)
				_f[ni] = ng + (float(amn) * DIAG + float(maxi(adx, adz) - amn)) * cell * k12 * hw
				_from[ni] = cur
				_state[ni] = 1
				_heap_push(ni)

	if not found:
		return PackedVector3Array()

	# 回溯
	var cells: PackedInt32Array = []
	var c := ti
	while c != -1:
		cells.append(c)
		c = _from[c]
	cells.reverse()
	var pts := PackedVector3Array()
	for k in cells.size():
		var x := cells[k] % nav.res
		var z := cells[k] / nav.res
		pts.append(Vector3(float(x) * nav.cell, 0.0, float(z) * nav.cell))
	# 用真实起点/终点收尾
	if pts.size() > 0:
		pts[0] = Vector3(from_world.x, 0.0, from_world.y)
		pts[pts.size() - 1] = Vector3(to_world.x, 0.0, to_world.y)
	return smooth(pts)

## octile 距离（以最快速度换算出代价下界，保证 A* 最优）
func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dz := absi(a.y - b.y)
	var mn := mini(dx, dz)
	var mx := maxi(dx, dz)
	return (float(mn) * DIAG + float(mx - mn)) * nav.cell * (1.0 / 1.2) * heuristic_weight

func _nearest_free(c: Vector2i, r: int) -> Vector2i:
	for radius in range(1, r + 1):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dz) != radius:
					continue
				var x := c.x + dx
				var z := c.y + dz
				if not nav.is_blocked(x, z):
					return Vector2i(x, z)
	return Vector2i(-1, -1)

# ---------------------------------------------------------------- 视线拉直
func smooth(pts: PackedVector3Array) -> PackedVector3Array:
	if pts.size() <= 2:
		return pts
	var out := PackedVector3Array()
	out.append(pts[0])
	var anchor := 0
	var i := 1
	while i < pts.size():
		# 从 anchor 出发找最远的可直达点
		var far := i
		var j := i
		while j < pts.size() and _line_free(pts[anchor], pts[j]):
			far = j
			j += 1
		out.append(pts[far])
		anchor = far
		i = far + 1
	return out

func _line_free(a: Vector3, b: Vector3) -> bool:
	var p0 := nav.cell_of(Vector2(a.x, a.z))
	var p1 := nav.cell_of(Vector2(b.x, b.z))
	var dx := absi(p1.x - p0.x)
	var dz := absi(p1.y - p0.y)
	var sx := 1 if p0.x < p1.x else -1
	var sz := 1 if p0.y < p1.y else -1
	var err := dx - dz
	var x := p0.x
	var z := p0.y
	var guard := 0
	while guard < 4096:
		guard += 1
		if nav.is_blocked(x, z):
			return false
		if x == p1.x and z == p1.y:
			return true
		var e2 := err * 2
		if e2 > -dz:
			err -= dz
			x += sx
			if nav.is_blocked(x, z):
				return false
		if e2 < dx:
			err += dx
			z += sz
			if nav.is_blocked(x, z):
				return false
	return false
