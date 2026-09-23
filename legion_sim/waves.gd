class_name WaveSpawner
extends RefCounted


static func start_wave(world: GameWorld) -> void:
	var wdef: Dictionary = world.tables.wave_def(world.wave_index)
	world.spawn_queue.clear()
	world.spawn_cd = 0
	if wdef.is_empty():
		return
	for side in [0, 1]:
		world.spawn_queue.append({
			"side": side,
			"left": int(wdef["count"]),
			"def": wdef,
		})
	_flush_hires(world)


static func _flush_hires(world: GameWorld) -> void:
	for p_i in range(world.players.size()):
		var p: Dictionary = world.players[p_i]
		var queued: Array = p["hire_queue"]
		p["hire_queue"] = []
		for h in queued:
			var hid := str(h)
			var hd: Dictionary = world.tables.hire_def(hid)
			if hd.is_empty():
				continue
			var foe := 1 - p_i
			world.spawn_hire(foe, hd, hid)


static func step(world: GameWorld) -> void:
	if world.spawn_queue.is_empty():
		return
	if world.spawn_cd > 0:
		world.spawn_cd -= 1
		return
	var interval := 6
	var spawned := false
	for q in world.spawn_queue:
		if int(q["left"]) <= 0:
			continue
		world.spawn_creep(int(q["side"]), q["def"])
		q["left"] = int(q["left"]) - 1
		interval = int(q["def"].get("interval", 6))
		spawned = true
	if spawned:
		world.spawn_cd = interval
	var any_left := false
	for q in world.spawn_queue:
		if int(q["left"]) > 0:
			any_left = true
			break
	if not any_left:
		world.spawn_queue.clear()
