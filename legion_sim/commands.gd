class_name CommandApplier
extends RefCounted

const ERR_OK := 0
const ERR_PHASE := 1
const ERR_GOLD := 2
const ERR_LUMBER := 3
const ERR_FOOD := 4
const ERR_CELL := 5
const ERR_UNIT := 6
const ERR_DEF := 7
const ERR_UPGRADE := 8


static func apply(world: GameWorld, side: int, cmd: Dictionary) -> int:
	var op := str(cmd.get("op", ""))
	match op:
		"Ready":
			if world.phase != "prep":
				return ERR_PHASE
			world.players[side]["ready"] = true
			return ERR_OK
		"Build":
			return _build(world, side, cmd)
		"Upgrade":
			return _upgrade(world, side, cmd)
		"Hire":
			return _hire(world, side, cmd)
		"King":
			return _king(world, side, cmd)
		"Sell":
			return _sell(world, side, cmd)
		_:
			return ERR_UNIT


static func _build(world: GameWorld, side: int, cmd: Dictionary) -> int:
	if world.phase != "prep":
		return ERR_PHASE
	var uid := str(cmd.get("uid", ""))
	var cell := int(cmd.get("cell", -1))
	var d: Dictionary = world.tables.unit_def(uid)
	if d.is_empty():
		return ERR_DEF
	if cell < 0 or cell >= TickConfig.CELLS_PER_SIDE:
		return ERR_CELL
	if world.cell_taken(side, cell):
		return ERR_CELL
	var p: Dictionary = world.players[side]
	if int(p["gold"]) < int(d.get("gold", 0)):
		return ERR_GOLD
	if int(p["lumber"]) < int(d.get("wood", 0)):
		return ERR_LUMBER
	var kind := str(d.get("kind", "unit"))
	if kind == "unit" and int(p["food_used"]) + int(d.get("food", 0)) > int(p["food_cap"]):
		return ERR_FOOD
	p["gold"] -= int(d.get("gold", 0))
	p["lumber"] -= int(d.get("wood", 0))
	world.spawn_defender(side, uid, d, cell, true)
	Economy.recap_food(p, world.tables)
	return ERR_OK


static func _upgrade(world: GameWorld, side: int, cmd: Dictionary) -> int:
	if world.phase != "prep":
		return ERR_PHASE
	var eid := int(cmd.get("eid", -1))
	var p: Dictionary = world.players[side]
	if not p["units"].has(eid):
		return ERR_UNIT
	var u: Dictionary = p["units"][eid]
	if str(u["kind"]) != "unit" and str(u["kind"]) != "farm":
		return ERR_UNIT
	var cur: Dictionary = world.tables.unit_def(u["uid"])
	var next_id := str(cur.get("upgrade", ""))
	var want := str(cmd.get("uid", next_id))
	if next_id.is_empty() or want != next_id:
		return ERR_UPGRADE
	var nd: Dictionary = world.tables.unit_def(next_id)
	if nd.is_empty():
		return ERR_DEF
	var dg := int(nd.get("gold", 0)) - int(cur.get("gold", 0))
	var dw := int(nd.get("wood", 0)) - int(cur.get("wood", 0))
	if dg < 0:
		dg = 0
	if dw < 0:
		dw = 0
	var df := int(nd.get("food", 0)) - int(u["food"])
	if int(p["gold"]) < dg:
		return ERR_GOLD
	if int(p["lumber"]) < dw:
		return ERR_LUMBER
	if str(nd.get("kind", "unit")) == "unit" and int(p["food_used"]) + df > int(p["food_cap"]):
		return ERR_FOOD
	p["gold"] -= dg
	p["lumber"] -= dw
	u["uid"] = next_id
	u["gold_cost"] = int(nd.get("gold", 0))
	u["food"] = int(nd.get("food", 0))
	u["hp"] = int(nd.get("hp", 1))
	u["hp_max"] = int(nd.get("hp", 1))
	u["atk"] = int((int(nd.get("atk_min", 0)) + int(nd.get("atk_max", 0))) / 2)
	u["rng"] = int(nd.get("rng", 100)) / TickConfig.RNG_SCALE
	u["at"] = str(nd.get("at", "普通"))
	u["df"] = str(nd.get("df", "轻甲"))
	u["cd_max"] = _cd_max(float(nd.get("as", 1.0)))
	u["kind"] = str(nd.get("kind", "unit"))
	u["built_this_wave"] = true
	Economy.recap_food(p, world.tables)
	return ERR_OK


static func _hire(world: GameWorld, side: int, cmd: Dictionary) -> int:
	if world.phase != "prep":
		return ERR_PHASE
	var hid := str(cmd.get("hid", ""))
	var hd: Dictionary = world.tables.hire_def(hid)
	if hd.is_empty():
		return ERR_DEF
	var p: Dictionary = world.players[side]
	var wood := int(hd.get("wood", 0))
	if int(p["lumber"]) < wood:
		return ERR_LUMBER
	p["lumber"] -= wood
	p["income"] += int(hd.get("income", 0))
	p["hire_queue"].append(hid)
	return ERR_OK


static func _king(world: GameWorld, side: int, cmd: Dictionary) -> int:
	if world.phase != "prep":
		return ERR_PHASE
	var p: Dictionary = world.players[side]
	var k: Dictionary = world.tables.king
	var wood := int(k.get("wood", 80))
	if int(p["lumber"]) < wood:
		return ERR_LUMBER
	p["lumber"] -= wood
	p["income"] += int(k.get("income", 3))
	var stat := str(cmd.get("stat", "hp"))
	match stat:
		"atk":
			p["king_atk"] += int(k.get("atk_delta", 4))
			p["king_atk_lv"] += 1
		"regen":
			p["king_regen"] += int(k.get("regen_delta", 1))
			p["king_regen_lv"] += 1
		_:
			p["king_hp_max"] += int(k.get("hp_delta", 80))
			p["king_hp"] += int(k.get("hp_delta", 80))
			p["king_hp_lv"] += 1
	return ERR_OK


static func _sell(world: GameWorld, side: int, cmd: Dictionary) -> int:
	if world.phase != "prep":
		return ERR_PHASE
	var eid := int(cmd.get("eid", -1))
	var p: Dictionary = world.players[side]
	if not p["units"].has(eid):
		return ERR_UNIT
	var u: Dictionary = p["units"][eid]
	if str(u["kind"]) != "unit" and str(u["kind"]) != "farm":
		return ERR_UNIT
	var cost := int(u["gold_cost"])
	var refund: int = int(cost / 2)
	if bool(u.get("built_this_wave", false)):
		refund = cost
	p["gold"] += refund
	p["units"].erase(eid)
	Economy.recap_food(p, world.tables)
	return ERR_OK


static func _cd_max(atk_speed: float) -> int:
	if atk_speed <= 0.01:
		atk_speed = 1.0
	return maxi(1, int(round(atk_speed / TickConfig.TICK_SEC)))
