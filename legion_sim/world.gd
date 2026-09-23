class_name GameWorld
extends RefCounted

var tables: GameTables
var tick: int = 0
var phase: String = "prep"
var phase_ticks_left: int = TickConfig.PREP_TICKS
var wave_index: int = 1
var winner: int = -1
var players: Array = []
var spawn_queue: Array = []
var spawn_cd: int = 0
var prep_ticks: int = TickConfig.PREP_TICKS
var rng := DetRng.new()
var _next_eid: int = 1


func setup_match(t: GameTables) -> void:
	tables = t
	tick = 0
	phase = "prep"
	phase_ticks_left = prep_ticks
	wave_index = 1
	winner = -1
	spawn_queue.clear()
	spawn_cd = 0
	_next_eid = 1
	rng.seed_value(1)
	players = [_make_player(0), _make_player(1)]


func _make_player(side: int) -> Dictionary:
	return {
		"side": side,
		"gold": TickConfig.START_GOLD,
		"lumber": TickConfig.START_LUMBER,
		"income": TickConfig.START_INCOME,
		"food_used": 0,
		"food_cap": TickConfig.START_FOOD,
		"king_hp": TickConfig.START_KING_HP,
		"king_hp_max": TickConfig.START_KING_HP,
		"king_atk": TickConfig.START_KING_ATK,
		"king_regen": TickConfig.START_KING_REGEN,
		"king_hp_lv": 0,
		"king_atk_lv": 0,
		"king_regen_lv": 0,
		"ready": false,
		"cmd_seq": 0,
		"units": {},
		"hire_queue": [],
	}


func alloc_eid() -> int:
	var e := _next_eid
	_next_eid += 1
	return e


func cell_xy(side: int, cell: int) -> Vector2i:
	var col := cell % TickConfig.COLS
	var row := int(cell / TickConfig.COLS)
	var y := 48 + row * 48
	if side == 0:
		return Vector2i(72 + col * 28, y)
	return Vector2i(728 - col * 28, y)


func cell_taken(side: int, cell: int) -> bool:
	for u in players[side]["units"].values():
		if int(u.get("cell", -1)) == cell:
			return true
	return false


func spawn_defender(side: int, uid: String, d: Dictionary, cell: int, built_now: bool) -> int:
	var xy := cell_xy(side, cell)
	var eid := alloc_eid()
	var cd_max := maxi(1, int(round(float(d.get("as", 1.0)) / TickConfig.TICK_SEC)))
	var u := {
		"eid": eid,
		"uid": uid,
		"side": side,
		"x": xy.x,
		"y": xy.y,
		"hp": int(d.get("hp", 1)),
		"hp_max": int(d.get("hp", 1)),
		"atk": int((int(d.get("atk_min", 0)) + int(d.get("atk_max", 0))) / 2),
		"rng": int(d.get("rng", 100)) / TickConfig.RNG_SCALE,
		"at": str(d.get("at", "普通")),
		"df": str(d.get("df", "轻甲")),
		"cd": 0,
		"cd_max": cd_max,
		"gold_cost": int(d.get("gold", 0)),
		"food": int(d.get("food", 0)),
		"kind": str(d.get("kind", "unit")),
		"cell": cell,
		"built_this_wave": built_now,
	}
	players[side]["units"][eid] = u
	return eid


func spawn_creep(side: int, wdef: Dictionary) -> void:
	var eid := alloc_eid()
	var y := 96 + (eid % 3) * 24
	var x := 280 if side == 0 else 520
	var cd_max := maxi(1, int(round(float(wdef.get("as", 1.2)) / TickConfig.TICK_SEC)))
	var u := {
		"eid": eid,
		"uid": "creep_w%d" % wave_index,
		"side": side,
		"x": x,
		"y": y,
		"hp": int(wdef.get("hp", 40)),
		"hp_max": int(wdef.get("hp", 40)),
		"atk": int(wdef.get("atk", 4)),
		"rng": int(wdef.get("rng", 90)) / TickConfig.RNG_SCALE,
		"at": str(wdef.get("at", "普通")),
		"df": str(wdef.get("df", "轻甲")),
		"cd": 0,
		"cd_max": cd_max,
		"gold_cost": 0,
		"food": 0,
		"kind": "creep",
		"cell": -1,
		"built_this_wave": false,
	}
	players[side]["units"][eid] = u


func spawn_hire(foe_side: int, hd: Dictionary, hid: String) -> void:
	var eid := alloc_eid()
	var y := 72 + (eid % 4) * 24
	var x := 300 if foe_side == 0 else 500
	var cd_max := maxi(1, int(round(float(hd.get("as", 1.2)) / TickConfig.TICK_SEC)))
	var u := {
		"eid": eid,
		"uid": hid,
		"side": foe_side,
		"x": x,
		"y": y,
		"hp": int(hd.get("hp", 210)),
		"hp_max": int(hd.get("hp", 210)),
		"atk": int((int(hd.get("atk_min", 0)) + int(hd.get("atk_max", 0))) / 2),
		"rng": int(hd.get("rng", 100)) / TickConfig.RNG_SCALE,
		"at": str(hd.get("at", "普通")),
		"df": str(hd.get("df", "重甲")),
		"cd": 0,
		"cd_max": cd_max,
		"gold_cost": 0,
		"food": 0,
		"kind": "hire",
		"cell": -1,
		"built_this_wave": false,
	}
	players[foe_side]["units"][eid] = u


func apply_command(side: int, cmd: Dictionary) -> int:
	var seq := int(cmd.get("cmdSeq", 0))
	var p: Dictionary = players[side]
	if seq != 0 and seq <= int(p["cmd_seq"]):
		return CommandApplier.ERR_OK
	if seq != 0:
		p["cmd_seq"] = seq
	return CommandApplier.apply(self, side, cmd)


func step() -> void:
	if phase == "gameover":
		return
	tick += 1
	match phase:
		"prep":
			phase_ticks_left -= 1
			var both := bool(players[0]["ready"]) and bool(players[1]["ready"])
			if both or phase_ticks_left <= 0:
				_enter_combat()
		"combat":
			WaveSpawner.step(self)
			CombatSim.step(self)
			if winner >= 0:
				phase = "gameover"
			elif _combat_clear():
				_enter_settle()
		"settle":
			phase_ticks_left -= 1
			if phase_ticks_left <= 0:
				_after_settle()


func _enter_combat() -> void:
	phase = "combat"
	players[0]["ready"] = false
	players[1]["ready"] = false
	WaveSpawner.start_wave(self)


func _combat_clear() -> bool:
	if not spawn_queue.is_empty():
		return false
	for p in players:
		for u in p["units"].values():
			if u["kind"] == "creep" or u["kind"] == "hire":
				return false
	return true


func _enter_settle() -> void:
	phase = "settle"
	phase_ticks_left = TickConfig.SETTLE_TICKS
	Economy.payout(self)


func _after_settle() -> void:
	if wave_index >= TickConfig.MAX_WAVE:
		phase = "gameover"
		if winner < 0:
			if int(players[0]["king_hp"]) == int(players[1]["king_hp"]):
				winner = -1
			elif int(players[0]["king_hp"]) > int(players[1]["king_hp"]):
				winner = 0
			else:
				winner = 1
		return
	wave_index += 1
	phase = "prep"
	phase_ticks_left = prep_ticks


func fingerprint() -> String:
	var s := "%d|%s|%d|%d|" % [tick, phase, wave_index, winner]
	for p in players:
		s += "%d,%d,%d,%d,%d;" % [p["gold"], p["lumber"], p["income"], p["king_hp"], Economy.force_of(p)]
	return s
