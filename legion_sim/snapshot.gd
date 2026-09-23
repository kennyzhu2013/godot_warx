class_name Snapshot
extends RefCounted


static func build(world: GameWorld) -> Dictionary:
	var plist: Array = []
	for p in world.players:
		plist.append({
			"gold": int(p["gold"]),
			"lumber": int(p["lumber"]),
			"income": int(p["income"]),
			"force": Economy.force_of(p),
			"food_used": int(p["food_used"]),
			"food_cap": int(p["food_cap"]),
			"king_hp": int(p["king_hp"]),
			"king_hp_max": int(p["king_hp_max"]),
			"king_atk": int(p["king_atk"]),
			"king_regen": int(p["king_regen"]),
			"ready": bool(p["ready"]),
		})
	var ulist: Array = []
	for p in world.players:
		for u in p["units"].values():
			ulist.append({
				"id": int(u["eid"]),
				"uid": str(u["uid"]),
				"side": int(u["side"]),
				"x": int(u["x"]),
				"y": int(u["y"]),
				"hp": int(u["hp"]),
				"hp_max": int(u["hp_max"]),
				"kind": str(u["kind"]),
				"cell": int(u.get("cell", -1)),
			})
	var creeps_left := 0
	for q in world.spawn_queue:
		creeps_left += int(q["left"])
	for p in world.players:
		for u in p["units"].values():
			if u["kind"] == "creep" or u["kind"] == "hire":
				creeps_left += 1
	return {
		"v": TickConfig.PROTOCOL,
		"tick": world.tick,
		"phase": world.phase,
		"phase_left": world.phase_ticks_left,
		"wave": world.wave_index,
		"winner": world.winner,
		"players": plist,
		"units": ulist,
		"creeps_left": creeps_left,
	}
