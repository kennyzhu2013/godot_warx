class_name LegionDebugOverlay
extends Node3D

## 军团标定叠层（Present）：建造格、出怪点、漏怪点、国王、标定路径，贴地画线。
## 只画传入的数据；数据来自 LegionTables / LegionSeats / LegionCalibration。

const LINE_Y_BIAS := 0.15
## 格子描边半边长（WC3；格距 128，留缝便于看清每格）
const CELL_HALF := 56.0
const MARK_HALF := 96.0
const KING_HALF := 192.0

const COLOR_CELL_ON := Color(0.35, 1.0, 0.45, 0.8)
const COLOR_CELL_OFF := Color(0.6, 0.65, 0.7, 0.35)
const COLOR_CELL_BAD := Color(1.0, 0.25, 0.25, 0.9)
const COLOR_SPAWN := Color(0.2, 1.0, 0.3, 1.0)
const COLOR_LEAK := Color(1.0, 0.6, 0.1, 1.0)
const COLOR_KING := Color(1.0, 0.15, 0.15, 1.0)
const COLOR_PATH_OK := Color(0.2, 0.9, 1.0, 0.95)
const COLOR_PATH_FAIL := Color(1.0, 0.2, 0.8, 0.95)

var _heightfield: Wc3Heightfield = null
var _mi: MeshInstance3D = null
var _mats: Dictionary = {}


func setup(heightfield: Wc3Heightfield) -> void:
	_heightfield = heightfield
	if _mi == null:
		_mi = MeshInstance3D.new()
		_mi.name = "LegionOverlayLines"
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mi)


## cells：cells.txt 行；enabled_regions：启用席位的 region 集合（region → true）；
## paths：LegionCalibration.paths。
func redraw(cells: Array[Dictionary], enabled_regions: Dictionary, seats: LegionSeats, paths: Array) -> void:
	if _mi == null:
		return
	var mesh := ImmediateMesh.new()
	var cells_on := PackedVector2Array()
	var cells_off := PackedVector2Array()
	var cells_bad := PackedVector2Array()
	for row in cells:
		var c := Vector2(float(row.get("x", "0")), float(row.get("y", "0")))
		var sq := _square(c, CELL_HALF)
		if str(row.get("walk", "0")) != "1" or str(row.get("build", "0")) != "1":
			cells_bad.append_array(sq)
		elif enabled_regions.has(str(row.get("region", ""))):
			cells_on.append_array(sq)
		else:
			cells_off.append_array(sq)
	_emit_segments(mesh, cells_off, COLOR_CELL_OFF)
	_emit_segments(mesh, cells_on, COLOR_CELL_ON)
	_emit_segments(mesh, cells_bad, COLOR_CELL_BAD)
	for s in seats.seats:
		if s.spawn != Vector2.INF:
			_emit_segments(mesh, _diamond(s.spawn, MARK_HALF), COLOR_SPAWN if s.enabled else COLOR_CELL_OFF)
		if s.leak != Vector2.INF:
			_emit_segments(mesh, _diamond(s.leak, MARK_HALF), COLOR_LEAK if s.enabled else COLOR_CELL_OFF)
		if s.king != Vector2.INF:
			var k := _square(s.king, KING_HALF)
			k.append_array(PackedVector2Array([
				s.king + Vector2(-KING_HALF, -KING_HALF), s.king + Vector2(KING_HALF, KING_HALF),
				s.king + Vector2(-KING_HALF, KING_HALF), s.king + Vector2(KING_HALF, -KING_HALF),
			]))
			_emit_segments(mesh, k, COLOR_KING)
	for item in paths:
		var pts: Array = item.get("points", [])
		var seg := PackedVector2Array()
		for i in range(pts.size() - 1):
			seg.append(pts[i])
			seg.append(pts[i + 1])
		_emit_segments(mesh, seg, COLOR_PATH_OK if bool(item.get("ok", false)) else COLOR_PATH_FAIL)
	_mi.mesh = mesh


func clear() -> void:
	if _mi != null:
		_mi.mesh = null


## 成对的 WC3 点 → 一段 PRIMITIVE_LINES
func _emit_segments(mesh: ImmediateMesh, pairs: PackedVector2Array, color: Color) -> void:
	if pairs.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _mat(color))
	for p in pairs:
		mesh.surface_add_vertex(_to_godot(p))
	mesh.surface_end()


func _square(c: Vector2, h: float) -> PackedVector2Array:
	var a := c + Vector2(-h, -h)
	var b := c + Vector2(h, -h)
	var d := c + Vector2(h, h)
	var e := c + Vector2(-h, h)
	return PackedVector2Array([a, b, b, d, d, e, e, a])


func _diamond(c: Vector2, h: float) -> PackedVector2Array:
	var n := c + Vector2(0, h)
	var e := c + Vector2(h, 0)
	var s := c + Vector2(0, -h)
	var w := c + Vector2(-h, 0)
	return PackedVector2Array([n, e, e, s, s, w, w, n, n, s, w, e])


func _to_godot(wc3: Vector2) -> Vector3:
	var z := 0.0
	if _heightfield != null and _heightfield.is_valid():
		z = _heightfield.interpolated_height(wc3.x, wc3.y)
	var g := Wc3Coords.wc3_xy_to_godot(wc3.x, wc3.y, z)
	g.y += LINE_Y_BIAS
	return g


func _mat(color: Color) -> StandardMaterial3D:
	if _mats.has(color):
		return _mats[color]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 40
	_mats[color] = m
	return m
