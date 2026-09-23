class_name CombatSim
extends RefCounted


static func step(world: GameWorld) -> void:
	_move_hostiles(world)
	_attacks(world)
	_regen_kings(world)
	_cull_dead(world)


static func _move_hostiles(world: GameWorld) -> void:
	for p in world.players:
		for u in p["units"].values():
			if u["kind"] != "creep" and u["kind"] != "hire":
				continue
			var side := int(u["side"])
			if side == 0:
				u["x"] = int(u["x"]) - TickConfig.CREEP_SPEED
				if int(u["x"]) <= 48:
					_hit_king(world, 0, u)
			else:
				u["x"] = int(u["x"]) + TickConfig.CREEP_SPEED
				if int(u["x"]) >= 752:
					_hit_king(world, 1, u)


static func _hit_king(world: GameWorld, side: int, u: Dictionary) -> void:
	var dmg := int(u["atk"])
	world.players[side]["king_hp"] -= dmg
	u["hp"] = 0
	if int(world.players[side]["king_hp"]) <= 0:
		world.players[side]["king_hp"] = 0
		world.winner = 1 - side
		world.phase = "gameover"


static func _attacks(world: GameWorld) -> void:
	var all: Array = []
	for p in world.players:
		for u in p["units"].values():
			all.append(u)
	for u in all:
		if int(u["hp"]) <= 0:
			continue
		if int(u.get("atk", 0)) <= 0:
			continue
		u["cd"] = int(u["cd"]) - 1
		if int(u["cd"]) > 0:
			continue
		var tgt := _nearest_enemy(world, u)
		if tgt.is_empty():
			continue
		var pct := world.tables.armor_pct(str(u["at"]), str(tgt["df"]))
		var dmg: int = int(int(u["atk"]) * pct / 100)
		if dmg < 1:
			dmg = 1
		tgt["hp"] = int(tgt["hp"]) - dmg
		u["cd"] = int(u["cd_max"])


static func _nearest_enemy(world: GameWorld, u: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1 << 30
	var rng := int(u["rng"])
	var my_side := int(u["side"])
	var hostile: bool = str(u["kind"]) == "creep" or str(u["kind"]) == "hire"
	for p in world.players:
		for o in p["units"].values():
			if int(o["hp"]) <= 0:
				continue
			if hostile:
				if str(o["kind"]) != "unit" and str(o["kind"]) != "farm":
					continue
				if int(o["side"]) != my_side:
					continue
			else:
				if int(o["side"]) == my_side:
					continue
				if str(o["kind"]) != "creep" and str(o["kind"]) != "hire":
					continue
			var dx := int(o["x"]) - int(u["x"])
			var dy := int(o["y"]) - int(u["y"])
			var d := dx * dx + dy * dy
			var r := rng * rng
			if d <= r and d < best_d:
				best_d = d
				best = o
	return best


static func _regen_kings(world: GameWorld) -> void:
	if world.tick % 20 != 0:
		return
	for p in world.players:
		if world.phase == "gameover":
			return
		p["king_hp"] = mini(int(p["king_hp_max"]), int(p["king_hp"]) + int(p["king_regen"]))


static func _cull_dead(world: GameWorld) -> void:
	for p in world.players:
		var dead: Array = []
		for eid in p["units"].keys():
			if int(p["units"][eid]["hp"]) <= 0:
				dead.append(eid)
		for eid in dead:
			p["units"].erase(eid)
		Economy.recap_food(p, world.tables)
