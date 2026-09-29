class_name LegionSpawner
extends Node

## 系统怪（Logic）：每个启用玩家席位的出怪点按间隔刷怪，分两段走：出怪点 → 漏怪点 → 本阵营国王面前。
## owner 是进攻方电脑席（打左路的怪归右电脑席），不用中立 owner。
## 阶段 2 只走路不打（attack_move = false，怪的 AI 设为 PASSIVE）；阶段 3 打开攻击移动。
## 自定规格：同波相邻两只间隔 SPAWN_GAP_SEC；到点半径 ARRIVE_RADIUS；
## 连续 STALL_SEC 几乎不动也算到点，被挡住时不会卡在第一段。

signal creep_spawned(unit: Node3D)

const SPAWN_GAP_SEC := 0.8
const SPAWN_JITTER := 32.0
const ARRIVE_RADIUS := 96.0
const STALL_SEC := 2.0
const STALL_DIST := 8.0
## 停在国王面前：沿国王 → 漏怪点方向离国王这么远
const KING_STAND_OFF := 160.0

enum Leg { TO_LEAK, TO_KING, DONE }


class Creep:
	extends RefCounted
	var unit: Node3D = null
	var lane: LegionSeats.Seat = null
	var leg: int = Leg.TO_LEAK
	var goal: Vector2 = Vector2.INF
	var last_pos: Vector2 = Vector2.INF
	var still: float = 0.0


class Pending:
	extends RefCounted
	var unit_id: String = ""
	var lane: LegionSeats.Seat = null
	var owner: int = -1
	var due: float = 0.0


var attack_move: bool = false
var _director: GameDirector = null
var _seats: LegionSeats = null
var _creeps: Array[Creep] = []
var _pending: Array[Pending] = []
var _clock: float = 0.0
var _rng := RandomNumberGenerator.new()


func configure(director: GameDirector, seats: LegionSeats) -> void:
	_director = director
	_seats = seats
	_rng.randomize()


## 按一行波次表给每条启用的玩家路排队刷怪；返回排队只数。
func spawn_wave(row: LegionUnitDefs.WaveRow) -> int:
	if _seats == null or row == null or row.count <= 0:
		return 0
	var queued := 0
	for lane in _seats.enabled_seats():
		if not lane.has_region() or lane.spawn == Vector2.INF:
			continue
		var owner := _seats.computer_seat_of(LegionSeats.opposite(lane.side))
		for i in range(row.count):
			var p := Pending.new()
			p.unit_id = row.unit_id
			p.lane = lane
			p.owner = owner
			p.due = _clock + i * SPAWN_GAP_SEC
			_pending.append(p)
			queued += 1
	return queued


func creeps() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in _creeps:
		if is_instance_valid(c.unit):
			out.append(c.unit)
	return out


## GM 读数：各段只数、按 owner 计数、已站定的怪离本路国王最远多少（wc3 单位）。
func summary() -> Dictionary:
	var legs: Dictionary[int, int] = {Leg.TO_LEAK: 0, Leg.TO_KING: 0, Leg.DONE: 0}
	var owners: Dictionary[int, int] = {}
	var done_max_king_dist := 0.0
	for c in _creeps:
		if not is_instance_valid(c.unit):
			continue
		legs[c.leg] += 1
		var owner_id := CombatQuery.owner_of(c.unit)
		owners[owner_id] = owners.get(owner_id, 0) + 1
		if c.leg == Leg.DONE and _seats != null:
			var king := _seats.king_of(c.lane.side)
			if king != Vector2.INF:
				var pos := Wc3Coords.godot_to_wc3_xy(c.unit.global_position)
				done_max_king_dist = maxf(done_max_king_dist, pos.distance_to(king))
	return {
		"pending": _pending.size(),
		"to_leak": legs[Leg.TO_LEAK],
		"to_king": legs[Leg.TO_KING],
		"done": legs[Leg.DONE],
		"owners": owners,
		"done_max_king_dist": done_max_king_dist,
	}


## 撤掉场上与排队中的全部系统怪。
func clear() -> void:
	_pending.clear()
	for c in _creeps:
		if is_instance_valid(c.unit) and _director != null:
			_director.remove_mode_unit(c.unit)
	_creeps.clear()


func _process(delta: float) -> void:
	_clock += delta
	if _director == null:
		return
	_spawn_due()
	_tick_creeps(delta)


func _spawn_due() -> void:
	var i := 0
	while i < _pending.size():
		var p := _pending[i]
		if p.due > _clock:
			i += 1
			continue
		_pending.remove_at(i)
		_spawn_one(p)


func _spawn_one(p: Pending) -> void:
	var at := p.lane.spawn + Vector2(_rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER), _rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER))
	var dir := p.lane.leak - p.lane.spawn
	var unit := _director.spawn_mode_unit(p.unit_id, at, p.owner, atan2(dir.y, dir.x))
	if unit == null:
		AppLog.warn(AppLog.Layer.GAME, "LegionSpawner", "刷怪失败 %s @ %s" % [p.unit_id, at])
		return
	if not attack_move:
		var ai := UnitAI.of(unit)
		if ai != null:
			ai.set_profile(UnitAI.Profile.PASSIVE)
	var c := Creep.new()
	c.unit = unit
	c.lane = p.lane
	_creeps.append(c)
	_issue_leg(c, Leg.TO_LEAK)
	creep_spawned.emit(unit)


func _tick_creeps(delta: float) -> void:
	var i := 0
	while i < _creeps.size():
		var c := _creeps[i]
		if not is_instance_valid(c.unit) or not CombatQuery.is_alive_in_world(c.unit):
			_creeps.remove_at(i)
			continue
		i += 1
		if c.leg == Leg.DONE:
			continue
		var pos := Wc3Coords.godot_to_wc3_xy(c.unit.global_position)
		if c.last_pos != Vector2.INF and pos.distance_to(c.last_pos) < STALL_DIST:
			c.still += delta
		else:
			c.still = 0.0
			c.last_pos = pos
		if pos.distance_to(c.goal) > ARRIVE_RADIUS and c.still < STALL_SEC:
			continue
		_issue_leg(c, Leg.TO_KING if c.leg == Leg.TO_LEAK else Leg.DONE)


func _issue_leg(c: Creep, leg: int) -> void:
	c.leg = leg
	c.still = 0.0
	c.last_pos = Vector2.INF
	match leg:
		Leg.TO_LEAK:
			c.goal = c.lane.leak
		Leg.TO_KING:
			c.goal = _king_front(c.lane)
		_:
			return
	var router := _director.get_command_router()
	if router == null or c.goal == Vector2.INF:
		c.leg = Leg.DONE
		return
	if attack_move:
		router.issue_attack_move([c.unit], c.goal, UnitOrder.Source.UNKNOWN)
	else:
		router.issue_move_to_wc3([c.unit], c.goal, UnitOrder.Source.UNKNOWN)


func _king_front(lane: LegionSeats.Seat) -> Vector2:
	var king := _seats.king_of(lane.side)
	if king == Vector2.INF:
		return Vector2.INF
	var away := lane.leak - king
	if away.length() < 1.0:
		return king
	return king + away.normalized() * KING_STAND_OFF
