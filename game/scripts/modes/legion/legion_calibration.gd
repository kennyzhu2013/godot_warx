class_name LegionCalibration
extends RefCounted

## 席位标定检查（Logic）：出怪点 / 漏怪点 / 国王是否可走，出怪→漏怪、漏怪→国王是否连通。
## 只读 PathQuery，不改地图。结果交给 LegionDebugOverlay 画线、GM 面板显示文字。

## 检查结果
var lines: PackedStringArray = []
## [{points: Array[Vector2], ok: bool}]，WC3 XY；不连通时 points 为起终点直线
var paths: Array = []
var failures: int = 0


static func run(seats: LegionSeats, path_query: PathQuery) -> LegionCalibration:
	var r := LegionCalibration.new()
	r.check(seats, path_query)
	return r


func check(seats: LegionSeats, path_query: PathQuery) -> void:
	lines.clear()
	paths.clear()
	failures = 0
	if path_query == null or not path_query.is_ready():
		_fail("寻路未就绪")
		return
	for side in ["L", "R"]:
		var king := seats.king_of(side)
		if king == Vector2.INF:
			_fail("%s 国王：seats.txt 未填" % side)
		elif not path_query.can_walk_wc3(king.x, king.y):
			_fail("%s 国王 (%d,%d) 不可走" % [side, king.x, king.y])
		else:
			lines.append("%s 国王 (%d,%d) 可走" % [side, king.x, king.y])
	for s in seats.enabled_seats():
		if not s.has_region():
			continue
		_check_point(path_query, "席位%d 出怪点" % s.seat, s.spawn)
		_check_point(path_query, "席位%d 漏怪点" % s.seat, s.leak)
		_check_path(path_query, "席位%d 出怪→漏怪" % s.seat, s.spawn, s.leak)
		_check_path(path_query, "席位%d 漏怪→国王" % s.seat, s.leak, seats.king_of(s.side))
	lines.insert(0, "全部通过" if failures == 0 else "%d 项未通过" % failures)


func _fail(text: String) -> void:
	lines.append(text)
	failures += 1


func _check_point(pq: PathQuery, label: String, p: Vector2) -> void:
	if p == Vector2.INF:
		_fail("%s：未填" % label)
	elif not pq.can_walk_wc3(p.x, p.y):
		_fail("%s (%d,%d) 不可走" % [label, p.x, p.y])


func _check_path(pq: PathQuery, label: String, from: Vector2, to: Vector2) -> void:
	if from == Vector2.INF or to == Vector2.INF:
		return
	var res := pq.find_path(from, to, 0, 0, true)
	if not bool(res.get("ok", false)):
		_fail("%s 不连通（%s）" % [label, str(res.get("reason", "?"))])
		paths.append({"points": [from, to], "ok": false})
		return
	var pts: Array = [from]
	pts.append_array(res.get("waypoints", []))
	paths.append({"points": pts, "ok": true})
	lines.append("%s 连通，%d 个路点" % [label, pts.size()])
