class_name CpuPlayer
extends RefCounted

## 右路/左路电脑：同一准备阶段里按固定顺序造农场、升级、补狼、雇一次、点一次王，然后准备。


static func act(world: GameWorld, side: int) -> void:
	var hired := false
	var kinged := false
	for _i in 12:
		if _try_farm(world, side):
			continue
		if _try_upgrade(world, side):
			continue
		if _try_build(world, side):
			continue
		if not hired and _try_hire(world, side):
			hired = true
			continue
		if not kinged and _try_king(world, side):
			kinged = true
			continue
		break
	world.apply_command(side, {"op": "Ready"})


static func _try_farm(world: GameWorld, side: int) -> bool:
	var p: Dictionary = world.players[side]
	var farm := _farm(p)
	if not farm.is_empty():
		var cur: Dictionary = world.tables.unit_def(str(farm["uid"]))
		var next_id := str(cur.get("upgrade", ""))
		if next_id.is_empty():
			return false
		var nd: Dictionary = world.tables.unit_def(next_id)
		if nd.is_empty():
			return false
		if int(p["gold"]) < int(nd.get("gold", 0)) or int(p["lumber"]) < int(nd.get("wood", 0)):
			return false
		return world.apply_command(side, {"op": "Upgrade", "eid": int(farm["eid"]), "uid": next_id}) == CommandApplier.ERR_OK
	if int(p["gold"]) < 24 or int(p["lumber"]) < 80:
		return false
	var cell := TickConfig.FARM_CELL
	if world.cell_taken(side, cell):
		cell = _empty_cell(world, side, false)
	if cell < 0:
		return false
	return world.apply_command(side, {"op": "Build", "uid": "farm1", "cell": cell}) == CommandApplier.ERR_OK


static func _try_upgrade(world: GameWorld, side: int) -> bool:
	var p: Dictionary = world.players[side]
	var eids: Array = p["units"].keys()
	eids.sort()
	for eid in eids:
		var u: Dictionary = p["units"][eid]
		if str(u["kind"]) != "unit":
			continue
		var cur: Dictionary = world.tables.unit_def(str(u["uid"]))
		var next_id := str(cur.get("upgrade", ""))
		if next_id.is_empty():
			continue
		var nd: Dictionary = world.tables.unit_def(next_id)
		if nd.is_empty():
			continue
		var dg := int(nd.get("gold", 0)) - int(cur.get("gold", 0))
		var dw := int(nd.get("wood", 0)) - int(cur.get("wood", 0))
		if dg < 0:
			dg = 0
		if dw < 0:
			dw = 0
		var df := int(nd.get("food", 0)) - int(u["food"])
		if int(p["gold"]) < dg or int(p["lumber"]) < dw:
			continue
		if str(nd.get("kind", "unit")) == "unit" and int(p["food_used"]) + df > int(p["food_cap"]):
			continue
		return world.apply_command(side, {"op": "Upgrade", "eid": int(eid), "uid": next_id}) == CommandApplier.ERR_OK
	return false


static func _try_build(world: GameWorld, side: int) -> bool:
	var p: Dictionary = world.players[side]
	if int(p["gold"]) < 10:
		return false
	if int(p["food_used"]) + 1 > int(p["food_cap"]):
		return false
	var cell := _empty_cell(world, side, true)
	if cell < 0:
		return false
	return world.apply_command(side, {"op": "Build", "uid": "h010", "cell": cell}) == CommandApplier.ERR_OK


static func _try_hire(world: GameWorld, side: int) -> bool:
	var p: Dictionary = world.players[side]
	var best := ""
	var best_wood := -1
	for hid in world.tables.hires.keys():
		var h: Dictionary = world.tables.hire_def(str(hid))
		if world.wave_index < int(h.get("min_wave", 1)):
			continue
		var wood := int(h.get("wood", 0))
		if wood <= best_wood:
			continue
		if int(p["lumber"]) < wood + 80:
			continue
		best = str(hid)
		best_wood = wood
	if best.is_empty():
		return false
	return world.apply_command(side, {"op": "Hire", "hid": best}) == CommandApplier.ERR_OK


static func _try_king(world: GameWorld, side: int) -> bool:
	var p: Dictionary = world.players[side]
	if int(p["lumber"]) < 80:
		return false
	if int(p["gold"]) >= 10 and int(p["food_used"]) < int(p["food_cap"]) and _empty_cell(world, side, true) >= 0:
		return false
	return world.apply_command(side, {"op": "King", "stat": "hp"}) == CommandApplier.ERR_OK


static func _farm(p: Dictionary) -> Dictionary:
	var found: Dictionary = {}
	var best := 1 << 30
	for u in p["units"].values():
		if str(u["kind"]) != "farm":
			continue
		if int(u["eid"]) < best:
			best = int(u["eid"])
			found = u
	return found


static func _empty_cell(world: GameWorld, side: int, reserve_farm: bool) -> int:
	for cell in TickConfig.CELLS_PER_SIDE:
		if reserve_farm and cell == TickConfig.FARM_CELL and not world.cell_taken(side, cell):
			continue
		if not world.cell_taken(side, cell):
			return cell
	return -1
