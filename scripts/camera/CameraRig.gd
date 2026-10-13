## =============================================================================
##  CameraRig —— 骑砍式战略相机
##  · 始终注视「玩家部队 + 平移偏移」的地面点，默认俯角 55°
##  · 滚轮缩放高度 18~400 米，俯角联动：越近越平视(26°)，越远越俯瞰(72°)
##  · 鼠标中键 / 右键拖拽旋转；手柄右摇杆或 Q / E 也能转（左右改朝向，上下改俯角）
##  · move_* 动作平移（WASD / 方向键 / 左摇杆 / 十字键）+ 屏幕边缘平移；focus_party 回到玩家部队
##  · 键位不写死：滚轮 / L1 / R1 / Back 等全部来自 project.godot 的 [input] 段
##  · 高度超过 strategic_view_height 进入「战略视图」（通知 Main 放大标签、剔除植被）
##  · 提供 ray_to_terrain()：屏幕坐标 → 地形世界坐标（供点击移动 / 悬停提示）
## =============================================================================
class_name CameraRig
extends Node3D

signal strategic_changed(is_strategic: bool)

var cam: Camera3D
var data: MapData
var cfg: MapConfig
var player: Node3D

var yaw: float = 0.0
var zoom_height: float = 90.0
var pitch_deg: float = 55.0
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
	cam.fov = 52.0
	cam.near = 0.5
	cam.far = 5000.0
	add_child(cam)
	zoom_height = cfg.cam_default_height
	_update_pitch_from_zoom()
	_apply()

func _process(delta: float) -> void:
	if cam == null:
		return
	var pan := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# 右摇杆 / Q E 旋转与俯仰。摇杆力度是模拟量，所以按「每秒」标定：
	# cam_rotate_speed 是「每像素」的鼠标灵敏度，乘 300 换算成满杆每秒的弧度。
	var rot := Input.get_axis("cam_rotate_left", "cam_rotate_right")
	if absf(rot) > 0.01:
		yaw -= rot * cfg.cam_rotate_speed * 300.0 * delta
	var tilt := Input.get_axis("cam_rotate_up", "cam_rotate_down")
	if absf(tilt) > 0.01:
		pitch_deg = clampf(pitch_deg + tilt * 70.0 * delta, 12.0, 86.0)
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
		# 按相机朝向平移，速度随高度缩放（越高移动越快）
		var speed := cfg.cam_pan_speed * clampf(zoom_height / 90.0, 0.35, 4.0) * delta
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
		if absf(event.relative.y) > 0.0:
			pitch_deg = clampf(pitch_deg + event.relative.y * cfg.cam_rotate_speed * 90.0, 12.0, 86.0)
		return
	# 缩放与回中走动作表：滚轮 / 手柄 L1 R1 / Back 键都在 project.godot 的 [input] 段里定义
	if event.is_action_pressed("zoom_in"):
		zoom_height = clampf(zoom_height * 0.88, cfg.cam_min_height, cfg.cam_max_height)
		_update_pitch_from_zoom()
	elif event.is_action_pressed("zoom_out"):
		zoom_height = clampf(zoom_height / 0.88, cfg.cam_min_height, cfg.cam_max_height)
		_update_pitch_from_zoom()
	elif event.is_action_pressed("focus_party"):
		recenter()

func _update_pitch_from_zoom() -> void:
	var h := zoom_height
	var mid := maxf(cfg.cam_default_height, cfg.cam_min_height + 1.0)
	if h <= mid:
		var t := (h - cfg.cam_min_height) / maxf(1.0, mid - cfg.cam_min_height)
		pitch_deg = lerpf(cfg.cam_pitch_near, 55.0, clampf(t, 0.0, 1.0))
	else:
		var t := (h - mid) / maxf(1.0, cfg.cam_max_height - mid)
		pitch_deg = lerpf(55.0, cfg.cam_pitch_far, clampf(t, 0.0, 1.0))

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

	var strategic := zoom_height >= cfg.strategic_view_height
	if strategic != _strategic:
		_strategic = strategic
		strategic_changed.emit(strategic)

func is_strategic() -> bool:
	return _strategic

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
	while t < 4000.0 and guard < 4000:
		guard += 1
		t += step
		step = minf(step * 1.06, 22.0)
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
