class_name LegionSeats
extends RefCounted

## 席位表（Data）：legion_data/seats.txt → 带类型的席位。缺省坐标为 Vector2.INF。

const FILE := "seats.txt"


class Seat:
	extends RefCounted
	var seat: int = -1
	var side: String = ""
	## cells.txt 的 region；电脑席为 NONE
	var region: String = ""
	var enabled: bool = false
	var spawn: Vector2 = Vector2.INF
	var leak: Vector2 = Vector2.INF
	## 只有持有国王的电脑席有值
	var king: Vector2 = Vector2.INF

	func has_region() -> bool:
		return not region.is_empty() and region != "NONE"


var seats: Array[Seat] = []


static func load_table() -> LegionSeats:
	var t := LegionSeats.new()
	for row in LegionTables.read_rows(FILE):
		var s := Seat.new()
		s.seat = int(row.get("seat", "-1"))
		s.side = str(row.get("side", ""))
		s.region = str(row.get("region", ""))
		s.enabled = str(row.get("enabled", "0")) == "1"
		s.spawn = _xy(row, "spawn")
		s.leak = _xy(row, "leak")
		s.king = _xy(row, "king")
		t.seats.append(s)
	return t


static func _xy(row: Dictionary, prefix: String) -> Vector2:
	var xs := str(row.get(prefix + "_x", "")).strip_edges()
	var ys := str(row.get(prefix + "_y", "")).strip_edges()
	if xs.is_empty() or ys.is_empty():
		return Vector2.INF
	return Vector2(float(xs), float(ys))


func get_seat(seat_id: int) -> Seat:
	for s in seats:
		if s.seat == seat_id:
			return s
	return null


func enabled_seats() -> Array[Seat]:
	var out: Array[Seat] = []
	for s in seats:
		if s.enabled:
			out.append(s)
	return out


## 阵营国王坐标（持有国王的席位行）；没有时 Vector2.INF。
func king_of(side: String) -> Vector2:
	for s in seats:
		if s.side == side and s.king != Vector2.INF:
			return s.king
	return Vector2.INF


## 阵营电脑席（持有国王的那一行；没有国王行时取该阵营第一个无区域席）；没有时 -1。
func computer_seat_of(side: String) -> int:
	var fallback := -1
	for s in seats:
		if s.side != side or s.has_region():
			continue
		if s.king != Vector2.INF:
			return s.seat
		if fallback < 0:
			fallback = s.seat
	return fallback


## 另一个阵营（L ↔ R）。
static func opposite(side: String) -> String:
	return "R" if side == "L" else "L"


## 全部席位 → 阵营，注入 CombatQuery.set_owner_sides（owner 即席位号）。
func side_table() -> Dictionary[int, String]:
	var out: Dictionary[int, String] = {}
	for s in seats:
		if s.seat >= 0 and not s.side.is_empty():
			out[s.seat] = s.side
	return out
