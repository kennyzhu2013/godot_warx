class_name GameTables
extends RefCounted

var armor: Dictionary = {}
var units: Dictionary = {}
var hires: Dictionary = {}
var waves: Array = []
var king: Dictionary = {}
var armor_cols: PackedStringArray = PackedStringArray()


static func parse_csv(text: String) -> Array:
	var rows: Array = []
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		rows.append(Array(line.split(",")))
	return rows


func load_all(files: Dictionary) -> void:
	_load_armor(files.get("armor", ""))
	_load_units(files.get("units", ""))
	_load_hires(files.get("hires", ""))
	_load_waves(files.get("waves", ""))
	_load_king(files.get("king", ""))


func _load_armor(text: String) -> void:
	armor.clear()
	var rows := parse_csv(text)
	if rows.is_empty():
		return
	var header: Array = rows[0]
	armor_cols = PackedStringArray()
	for i in range(1, header.size()):
		armor_cols.append(str(header[i]))
	for r in range(1, rows.size()):
		var row: Array = rows[r]
		var atk := str(row[0])
		var m: Dictionary = {}
		for i in range(1, mini(row.size(), header.size())):
			m[str(header[i])] = int(row[i])
		armor[atk] = m


func _load_units(text: String) -> void:
	units.clear()
	var rows := parse_csv(text)
	if rows.size() < 2:
		return
	var h: Array = rows[0]
	for r in range(1, rows.size()):
		units[_row_id(h, rows[r])] = _map_row(h, rows[r])


func _load_hires(text: String) -> void:
	hires.clear()
	var rows := parse_csv(text)
	if rows.size() < 2:
		return
	var h: Array = rows[0]
	for r in range(1, rows.size()):
		hires[_row_id(h, rows[r])] = _map_row(h, rows[r])


func _load_waves(text: String) -> void:
	waves.clear()
	var rows := parse_csv(text)
	if rows.size() < 2:
		return
	var h: Array = rows[0]
	for r in range(1, rows.size()):
		waves.append(_map_row(h, rows[r]))


func _load_king(text: String) -> void:
	king.clear()
	var rows := parse_csv(text)
	if rows.size() < 2:
		return
	king = _map_row(rows[0], rows[1])


func _row_id(header: Array, row: Array) -> String:
	return str(_cell(header, row, "id"))


func _map_row(header: Array, row: Array) -> Dictionary:
	var d: Dictionary = {}
	for i in range(mini(header.size(), row.size())):
		var key := str(header[i])
		var raw := str(row[i])
		if key in ["gold", "wood", "food", "hp", "atk_min", "atk_max", "rng", "wave", "count", "income", "interval", "food_cap", "hp_delta", "atk_delta", "regen_delta"]:
			d[key] = int(raw) if raw.is_valid_int() else 0
		elif key in ["as"]:
			d[key] = float(raw)
		else:
			d[key] = raw
	return d


func _cell(header: Array, row: Array, key: String) -> Variant:
	var idx := header.find(key)
	if idx < 0 or idx >= row.size():
		return ""
	return row[idx]


func armor_pct(atk: String, df: String) -> int:
	var df_key := df
	if df_key == "王甲" or df_key == "国王" or df_key == "英雄护甲":
		df_key = "英雄"
	var row: Dictionary = armor.get(atk, {})
	return int(row.get(df_key, 100))


func unit_def(uid: String) -> Dictionary:
	return units.get(uid, {})


func hire_def(hid: String) -> Dictionary:
	return hires.get(hid, {})


func wave_def(wave: int) -> Dictionary:
	if wave < 1 or wave > waves.size():
		return {}
	return waves[wave - 1]
