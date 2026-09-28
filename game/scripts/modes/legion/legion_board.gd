class_name LegionBoard
extends RefCounted

## 建造格占用与防守兵记录（Logic）。格子来自 cells.txt；一格一个防守兵。
## 防守兵 meta（复位、出售、兵力都读）：席位、格子键、建造回合、累计投入金币。
## 出售规则（策划案 5.4）：本回合建造退 100% 投入，旧单位退 50%。

const META_SEAT := "legion_seat"
const META_CELL := "legion_cell"
const META_BUILD_ROUND := "legion_build_round"
const META_INVESTED := "legion_invested_gold"

const OLD_UNIT_REFUND := 0.5
## 点击到格心的最大距离（格宽 128）
const PICK_RADIUS := 96.0


class Cell:
	extends RefCounted
	var key: String = ""
	var region: String = ""
	var col: int = 0
	var row: int = 0
	var center: Vector2 = Vector2.ZERO
	var buildable: bool = true


var _cells_by_region: Dictionary[String, Array] = {}
var _cells_by_key: Dictionary[String, Cell] = {}
## 格子键 → 防守兵
var _occupant: Dictionary[String, Node3D] = {}


static func from_rows(rows: Array[Dictionary]) -> LegionBoard:
	var board := LegionBoard.new()
	for r in rows:
		var c := Cell.new()
		c.region = str(r.get("region", ""))
		c.col = int(r.get("col", "0"))
		c.row = int(r.get("row", "0"))
		c.center = Vector2(float(r.get("x", "0")), float(r.get("y", "0")))
		c.buildable = str(r.get("build", "1")) == "1" and str(r.get("walk", "1")) == "1"
		c.key = "%s:%d:%d" % [c.region, c.col, c.row]
		board.add_cell(c)
	return board


func add_cell(c: Cell) -> void:
	_cells_by_key[c.key] = c
	if not _cells_by_region.has(c.region):
		_cells_by_region[c.region] = []
	_cells_by_region[c.region].append(c)


## 区域内离 wc3 最近的格（≤ PICK_RADIUS）；没有时 null。
func cell_near(region: String, wc3: Vector2) -> Cell:
	var best: Cell = null
	var best_d := PICK_RADIUS
	for c in _cells_by_region.get(region, []):
		var cell := c as Cell
		var d := cell.center.distance_to(wc3)
		if d <= best_d:
			best_d = d
			best = cell
	return best


func get_cell(key: String) -> Cell:
	return _cells_by_key.get(key) as Cell


func occupant(key: String) -> Node3D:
	var u: Variant = _occupant.get(key)
	if u == null:
		return null
	if not is_instance_valid(u):
		_occupant.erase(key)
		return null
	return u as Node3D


func is_free(key: String) -> bool:
	return occupant(key) == null


## 登记防守兵并写 meta。
func place(unit: Node3D, cell: Cell, seat: int, build_round: int, invested_gold: int) -> void:
	_occupant[cell.key] = unit
	unit.set_meta(META_SEAT, seat)
	unit.set_meta(META_CELL, cell.key)
	unit.set_meta(META_BUILD_ROUND, build_round)
	unit.set_meta(META_INVESTED, invested_gold)


func release(unit: Node3D) -> void:
	if unit == null:
		return
	var key := str(unit.get_meta(META_CELL, ""))
	if not key.is_empty() and _occupant.get(key) == unit:
		_occupant.erase(key)


func defenders() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for key in _occupant.keys():
		var u := occupant(key)
		if u != null:
			out.append(u)
	return out


static func is_defender(unit: Node) -> bool:
	return unit != null and is_instance_valid(unit) and unit.has_meta(META_CELL)


static func seat_of(unit: Node) -> int:
	return int(unit.get_meta(META_SEAT, -1)) if unit != null else -1


static func sell_refund(unit: Node, current_round: int) -> int:
	if not is_defender(unit):
		return 0
	var invested := int(unit.get_meta(META_INVESTED, 0))
	if int(unit.get_meta(META_BUILD_ROUND, -1)) == current_round:
		return invested
	return int(floor(invested * OLD_UNIT_REFUND))
