class_name Economy
extends RefCounted


static func force_of(p: Dictionary) -> int:
	var total := 0
	for u in p["units"].values():
		if u["kind"] == "unit" or u["kind"] == "farm":
			total += int(u["gold_cost"])
	return total


static func recap_food(p: Dictionary, tables: GameTables) -> void:
	var cap := TickConfig.START_FOOD
	for u in p["units"].values():
		if u["kind"] == "farm":
			var d: Dictionary = tables.unit_def(u["uid"])
			cap = maxi(cap, int(d.get("food_cap", 0)))
	p["food_cap"] = cap
	var used := 0
	for u in p["units"].values():
		if u["kind"] == "unit":
			used += int(u["food"])
	p["food_used"] = used


static func payout(world: GameWorld) -> void:
	for p in world.players:
		p["gold"] += int(p["income"])
		p["king_hp"] = mini(int(p["king_hp_max"]), int(p["king_hp"]) + int(p["king_regen"]))
		p["ready"] = false
		for u in p["units"].values():
			u["built_this_wave"] = false
