## =============================================================================
##  Heightmap —— 高度场容器 + 快速查询
##  存储 (res x res) 采样点，世界坐标范围 [0, size] x [0, size]。
##  提供双线性插值高度、法线、坡度查询，是所有系统（地形网格 / 寻路 /
##  植被投放 / 部队贴地）的唯一地面数据源。
## =============================================================================
class_name Heightmap
extends RefCounted

var res: int
var cell: float          ## 采样间距（米）
var size: float          ## 世界尺寸（米）
var data: PackedFloat32Array

func _init(p_res: int, p_size: float) -> void:
	res = maxi(2, p_res)
	size = p_size
	cell = size / float(res - 1)
	data = PackedFloat32Array()
	data.resize(res * res)

func idx(x: int, z: int) -> int:
	return z * res + x

func get_h(x: int, z: int) -> float:
	return data[clampi(z, 0, res - 1) * res + clampi(x, 0, res - 1)]

func set_h(x: int, z: int, v: float) -> void:
	if x >= 0 and x < res and z >= 0 and z < res:
		data[z * res + x] = v

## 双线性插值采样（世界坐标，米）
func height_at(wx: float, wz: float) -> float:
	var fx := wx / cell
	var fz := wz / cell
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var xa := clampi(x0, 0, res - 1)
	var xb := clampi(x0 + 1, 0, res - 1)
	var za := clampi(z0, 0, res - 1)
	var zb := clampi(z0 + 1, 0, res - 1)
	var h00 := data[za * res + xa]
	var h10 := data[za * res + xb]
	var h01 := data[zb * res + xa]
	var h11 := data[zb * res + xb]
	var a := lerpf(h00, h10, tx)
	var b := lerpf(h01, h11, tx)
	return lerpf(a, b, tz)

## 解析法线（中央差分）——比从网格算更平滑
func normal_at(wx: float, wz: float) -> Vector3:
	var d := cell
	var hl := height_at(wx - d, wz)
	var hr := height_at(wx + d, wz)
	var hd := height_at(wx, wz - d)
	var hu := height_at(wx, wz + d)
	return Vector3(hl - hr, 2.0 * d, hd - hu).normalized()

## 坡度：0 = 完全水平，1 = 垂直
func slope_at(wx: float, wz: float) -> float:
	return 1.0 - clampf(normal_at(wx, wz).y, 0.0, 1.0)

func is_water(wx: float, wz: float, sea_level: float) -> bool:
	return height_at(wx, wz) <= sea_level

## 3x3 均值模糊（生成后做一遍，去掉噪声毛刺，便于寻路与建造）
func blur(passes: int = 1) -> void:
	var tmp := PackedFloat32Array()
	tmp.resize(data.size())
	for _p in passes:
		tmp = data.duplicate()
		for z in range(1, res - 1):
			var row := z * res
			var row_up := (z - 1) * res
			var row_dn := (z + 1) * res
			for x in range(1, res - 1):
				var s := tmp[row_up + x - 1] + tmp[row_up + x] + tmp[row_up + x + 1] \
					+ tmp[row + x - 1] + tmp[row + x] + tmp[row + x + 1] \
					+ tmp[row_dn + x - 1] + tmp[row_dn + x] + tmp[row_dn + x + 1]
				data[row + x] = s / 9.0

## 以 (cx,cz) 为中心做半径内的高斯式平整（定居点地基、湖泊凹地）
func flatten(cx: float, cz: float, radius: float, target: float, blend: float, strength: float = 1.0) -> void:
	var r := radius + blend
	var x0 := maxi(0, int((cx - r) / cell))
	var x1 := mini(res - 1, int((cx + r) / cell) + 1)
	var z0 := maxi(0, int((cz - r) / cell))
	var z1 := mini(res - 1, int((cz + r) / cell) + 1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := float(x) * cell
			var wz := float(z) * cell
			var d := Vector2(wx - cx, wz - cz).length()
			if d > r:
				continue
			var w := 1.0 - smoothstep(radius, r, d)
			var i := z * res + x
			data[i] = lerpf(data[i], target, w * strength)
