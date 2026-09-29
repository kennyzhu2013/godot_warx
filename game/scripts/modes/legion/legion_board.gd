class_name LegionBoard
extends RefCounted

## 建造格占用与防守兵名册（Logic）。格子来自 cells.txt；一格一个防守兵。
## 名册按格子记兵种、席位、建造回合、累计投入金币；单位战死后记录仍在，结算时照记录重新摆出。
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


class Defender:
	extends RefCounted
	var cell: Cell = null
	var unit_id: String = ""
	var seat: int = -1
	var build_round: int = 0
	var invested: int = 0
	var food: int = 0
	## 场上单位；战死并被移除后为 null（用 unit_node() 取，免得读到已释放对象）
	var unit: Variant = null
	## 战死时 GameDirector 已退掉人口，模式补回后置 true；重新摆出时清掉
	var food_restored: bool = false

	func unit_node() -> Node3D:
		if unit == null or not is_instance_valid(unit):
			return null
		return unit as Node3D

	func is_alive() -> bool:
		var u := unit_node()
		return u != null and CombatQuery.is_alive_in_world(u)


var _cells_by_region: Dictionary[String, Array] = {}
var _cells_by_key: Dictionary[String, Cell] = {}
## 格子键 → 名册记录
var _roster: Dictionary[String, Defender] = {}


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


## 区域格心的外接矩形（wc3）；没有格子时 Rect2()。
func region_rect(region: String) -> Rect2:
	var cells: Array = _cells_by_region.get(region, [])
	if cells.is_empty():
		return Rect2()
	var r := Rect2((cells[0] as Cell).center, Vector2.ZERO)
	for c in cells:
		r = r.expand((c as Cell).center)
	return r


func record_at(key: String) -> Defender:
	return _roster.get(key) as Defender


## 格子上的活单位；空格或兵已战死时 null。
func occupant(key: String) -> Node3D:
	var d := record_at(key)
	return d.unit_node() if d != null else null


## 名册里有记录就不算空（战死的兵结算时会回来）。
func is_free(key: String) -> bool:
	return not _roster.has(key)


## 登记防守兵并写 meta。
func place(unit: Node3D, cell: Cell, seat: int, build_round: int, invested_gold: int, food: int = 0) -> Defender:
	var d := Defender.new()
	d.cell = cell
	d.unit_id = CombatQuery.type_id_of(unit)
	d.seat = seat
	d.build_round = build_round
	d.invested = invested_gold
	d.food = food
	_roster[cell.key] = d
	attach(d, unit)
	return d


## 把（重新摆出的）单位挂回名册记录。
func attach(d: Defender, unit: Node3D) -> void:
	d.unit = unit
	d.food_restored = false
	unit.set_meta(META_SEAT, d.seat)
	unit.set_meta(META_CELL, d.cell.key)
	unit.set_meta(META_BUILD_ROUND, d.build_round)
	unit.set_meta(META_INVESTED, d.invested)


func release(unit: Node3D) -> void:
	if unit == null:
		return
	var key := str(unit.get_meta(META_CELL, ""))
	var d := record_at(key)
	if d != null and d.unit_node() == unit:
		_roster.erase(key)


func records() -> Array[Defender]:
	var out: Array[Defender] = []
	for d in _roster.values():
		out.append(d as Defender)
	return out


func defenders() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for d in _roster.values():
		var u := (d as Defender).unit_node()
		if u != null and (d as Defender).is_alive():
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
