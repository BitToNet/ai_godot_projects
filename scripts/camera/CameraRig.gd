## =============================================================================
##  CameraRig —— 骑砍式战略相机（第十五轮改为**正交等距**）
##  · 始终注视「玩家部队 + 平移偏移」的地面点
##  · **正交投影（PROJECTION_ORTHOGONAL）**：没有近大远小，远近物体一样大，
##    这就是微缩沙盒 / 手办感最核心的一条 —— 透视会把远景压扁，正交不会。
##  · 俯角**固定 35.264°**（真正的等距角，atan(1/√2)）：等距视角的关键是"所有方向
##    等缩"，俯角一旦随缩放联动就不再是等距了。所以旧的「越近越平视、越远越俯瞰」
##    被删除；滚轮改为调**正交尺寸** cam.size（可视高度，米）。
##  · 滚轮缩放的视觉尺度与旧版一致：size = zoom_height × 1.19，默认 90 m 高度 →
##    可视高度 ≈ 107 m（旧版 fov 52° / 俯角 55° / 高 90 m 时算出来也是 107 m）。
##    因此 zoom_height 仍然可以当"缩放级别"用：标签缩放、平移速度、战略视图阈值
##    全部沿用旧口径，一处没改。
##  · 中键 / 右键拖拽、Q/E、手柄右摇杆：**只转朝向（yaw）**，不再改俯角。
##  · 高度超过 strategic_view_height_m() 进入「战略视图」（通知 Main 放大标签、剔除植被）
##  · 提供 ray_to_terrain()：屏幕坐标 → 地形世界坐标（供点击移动 / 悬停提示）。
##    正交下射线是平行的，逐步推进 + 二分的算法不变，仍然收敛。
## =============================================================================
class_name CameraRig
extends Node3D

signal strategic_changed(is_strategic: bool)

## 拾取射线的步进上限（米/步）与迭代上限（防死循环）。两者必须自洽：
## 迭代上限要够走完 ray_max_distance() 推导出的距离 —— tools/map_size_check.gd 会算给你看。
const RAY_STEP_MAX := 22.0
const RAY_GUARD := 4000

## 正交等距的固定俯角：atan(1/√2) = 35.264°，斜 45° + 俯 35.264° 才是 1:1:1 等距
const ISO_PITCH_DEG := 35.264
## 默认朝向：45° 让地块呈菱形铺开（等距的标志性构图）
const ISO_YAW_DEG := 45.0
## 缩放高度 → 正交可视高度（米）的换算：与旧版 fov 52°/俯角 55° 的观感对齐
const ORTHO_SIZE_PER_HEIGHT := 1.19

var cam: Camera3D
var data: MapData
var cfg: MapConfig
var player: Node3D

var yaw: float = 0.0
var zoom_height: float = 90.0
## 俯角：默认锁在等距角。**不要**在缩放路径里改它 —— 改了就不是等距了。
## 保留成成员变量是因为 tools/visual_shot.gd 的机位表要能指定俯角拍对比图。
var pitch_deg: float = ISO_PITCH_DEG
var pan_offset: Vector2 = Vector2.ZERO

var _dragging: bool = false
var _drag_button: int = -1
var _strategic: bool = false
var _focus: Vector3 = Vector3.ZERO

func setup(p_cfg: MapConfig, p_data: MapData, p_player: Node3D) -> void:
	cfg = p_cfg
	data = p_data
	player = p_player
	cam = Camera3D.new()
	cam.name = "StrategicCamera"
	# 正交投影：微缩沙盒的"平"来自这里（透视会让远处的山缩成一点）
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT   # size = 可视高度（米），宽度按窗口比例自动推
	cam.near = 0.5
	cam.far = far_for(cfg.map_size)
	add_child(cam)
	yaw = deg_to_rad(ISO_YAW_DEG)
	zoom_height = cfg.cam_default_height_m()
	pitch_deg = ISO_PITCH_DEG
	_apply_projection()
	_apply()

func _process(delta: float) -> void:
	if cam == null:
		return
	var pan := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# 右摇杆 / Q E 旋转。摇杆力度是模拟量，所以按「每秒」标定：
	# cam_rotate_speed 是「每像素」的鼠标灵敏度，乘 300 换算成满杆每秒的弧度。
	# 上下（cam_rotate_up / down）在等距视角下不再改俯角 —— 那是旧版的自由机位行为。
	var rot := Input.get_axis("cam_rotate_left", "cam_rotate_right")
	if absf(rot) > 0.01:
		yaw -= rot * cfg.cam_rotate_speed * 300.0 * delta
	# 屏幕边缘平移
	var vp := get_viewport()
	var mouse := vp.get_mouse_position()
	var wsz := Vector2(vp.get_visible_rect().size)
	if vp.get_window() != null and vp.get_window().has_focus():
		var m := 10.0
		if mouse.x >= 0.0 and mouse.y >= 0.0 and mouse.x <= wsz.x and mouse.y <= wsz.y:
			if mouse.x < m:
				pan.x -= 1.0
			elif mouse.x > wsz.x - m:
				pan.x += 1.0
			if mouse.y < m:
				pan.y -= 1.0
			elif mouse.y > wsz.y - m:
				pan.y += 1.0
	if pan.length_squared() > 0.0:
		pan = pan.normalized()
		# 按相机朝向平移，速度随缩放缩放（越高移动越快）
		var speed := cfg.cam_pan_speed_m() * clampf(zoom_height / cfg.cam_default_height_m(), 0.35, 4.0) * delta
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		pan_offset += Vector2((fwd.x * -pan.y + right.x * pan.x) * speed, (fwd.z * -pan.y + right.z * pan.x) * speed)
		_clamp_pan()
	_apply()

func _clamp_pan() -> void:
	var lim := cfg.map_size * 0.62
	pan_offset.x = clampf(pan_offset.x, -lim, lim)
	pan_offset.y = clampf(pan_offset.y, -lim, lim)

func recenter() -> void:
	pan_offset = Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
			_drag_button = event.button_index if event.pressed else -1
			return
	if event is InputEventMouseMotion and _dragging:
		yaw -= event.relative.x * cfg.cam_rotate_speed
		# 竖直拖拽不再改俯角：等距视角的俯角是构图的一部分，不该被手滑改掉
		return
	# 缩放与回中走动作表：滚轮 / 手柄 L1 R1 / Back 键都在 project.godot 的 [input] 段里定义
	if event.is_action_pressed("zoom_in"):
		zoom_height = clampf(zoom_height * 0.88, cfg.cam_min_height_m(), cfg.cam_max_height_m())
		_apply_projection()
	elif event.is_action_pressed("zoom_out"):
		zoom_height = clampf(zoom_height / 0.88, cfg.cam_min_height_m(), cfg.cam_max_height_m())
		_apply_projection()
	elif event.is_action_pressed("focus_party"):
		recenter()

## 把 zoom_height 换算成正交可视高度。缩放只改这一个数，不改俯角 —— 这就是"等距"。
## 函数名保留 _update_pitch_from_zoom 的历史调用点已全部改掉，现在是语义准确的 _apply_projection。
func _apply_projection() -> void:
	if cam == null:
		return
	cam.size = maxf(1.0, zoom_height * ORTHO_SIZE_PER_HEIGHT)

func _apply() -> void:
	if player == null:
		return
	var focus2 := Vector2(player.position.x, player.position.z) + pan_offset
	# 允许稍微看地图外（海面 / 迷雾边界）
	focus2.x = clampf(focus2.x, -160.0, cfg.map_size + 160.0)
	focus2.y = clampf(focus2.y, -160.0, cfg.map_size + 160.0)
	var fh := data.hm.height_at(focus2.x, focus2.y)
	_focus = Vector3(focus2.x, maxf(fh, cfg.sea_level), focus2.y)
	var pr := deg_to_rad(pitch_deg)
	var horiz := zoom_height / maxf(0.25, tan(pr))
	var off := Vector3(sin(yaw) * horiz, zoom_height, cos(yaw) * horiz)
	var target := _focus + off
	# 相机不要钻进山里
	var ground := data.hm.height_at(target.x, target.z)
	if target.y < ground + 3.0:
		target.y = ground + 3.0
	cam.global_position = target
	cam.look_at(_focus, Vector3.UP)

	var strategic := zoom_height >= cfg.strategic_view_height_m()
	if strategic != _strategic:
		_strategic = strategic
		strategic_changed.emit(strategic)

func is_strategic() -> bool:
	return _strategic

## 远裁剪面：按地图尺寸推导 —— 4096 m 图的对角线是 5792 m，站在一角看对角必须是
## 「看得见」而不是被裁掉；下限 5000 是 1024 m 图时代的既有取值，所以换尺寸之前行为一位不变。
static func far_for(map_size: float) -> float:
	return maxf(5000.0, map_size * 1.5)

## 屏幕拾取射线的最远推进距离：同样按尺寸推导，1024 m 图下**仍是**原来的 4000 m。
static func ray_max_distance(map_size: float) -> float:
	return maxf(4000.0, map_size * 1.5)

## 屏幕坐标 → 地形世界坐标（对高度场做步进求交 + 二分细化）
func ray_to_terrain(screen_pos: Vector2) -> Vector3:
	if cam == null:
		return Vector3.ZERO
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var t := 0.0
	var step := 2.0
	var prev := origin
	var guard := 0
	var max_t := ray_max_distance(cfg.map_size)
	while t < max_t and guard < RAY_GUARD:
		guard += 1
		t += step
		step = minf(step * 1.06, RAY_STEP_MAX)
		var p := origin + dir * t
		# 打到地图外太远就停
		if p.x < -700.0 or p.z < -700.0 or p.x > cfg.map_size + 700.0 or p.z > cfg.map_size + 700.0:
			break
		var diff := p.y - data.hm.height_at(p.x, p.z)
		if diff <= 0.0:
			# 二分细化
			var lo := prev
			var hi := p
			for _i in 12:
				var mid := (lo + hi) * 0.5
				if mid.y - data.hm.height_at(mid.x, mid.z) > 0.0:
					lo = mid
				else:
					hi = mid
			return hi
		prev = p
	return Vector3(origin.x + dir.x * t, 0.0, origin.z + dir.z * t)

func focus_point() -> Vector3:
	return _focus
