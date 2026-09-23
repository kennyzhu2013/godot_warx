extends Control

## 阶段 0 验收窗口。规则只走 CommandApplier，界面上的标签是唯一读数。

var world: GameWorld
var _gold: Label
var _lumber: Label
var _income: Label
var _food: Label
var _force: Label
var _king: Label
var _phase: Label
var _log: Label
var _built_eid: int = -1
var _build_btn: Button
var _king_btn: Button
var _sell_btn: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.position = Vector2(48, 36)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = "军团战争  阶段 0"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	_gold = _stat(box, "金币")
	_lumber = _stat(box, "木材")
	_income = _stat(box, "收入")
	_food = _stat(box, "人口")
	_force = _stat(box, "兵力")
	_king = _stat(box, "国王")
	_phase = _stat(box, "阶段")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_build_btn = _button(row, "造豺狼蛮人", _on_build)
	_king_btn = _button(row, "强化国王生命", _on_king)
	_sell_btn = _button(row, "出售刚造的兵", _on_sell)
	_log = Label.new()
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.custom_minimum_size = Vector2(720, 160)
	box.add_child(_log)
	_open_match()


func _stat(parent: Node, caption: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var cap := Label.new()
	cap.text = caption
	cap.custom_minimum_size = Vector2(72, 0)
	cap.add_theme_font_size_override("font_size", 20)
	row.add_child(cap)
	var value := Label.new()
	value.text = "—"
	value.add_theme_font_size_override("font_size", 20)
	row.add_child(value)
	return value


func _button(parent: Node, caption: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = caption
	b.custom_minimum_size = Vector2(160, 40)
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


func _open_match() -> void:
	var tables := GameTables.new()
	tables.load_all({
		"armor": _read("res://legion_data/armor.txt"),
		"units": _read("res://legion_data/units.txt"),
		"hires": _read("res://legion_data/hires.txt"),
		"waves": _read("res://legion_data/waves.txt"),
		"king": _read("res://legion_data/king.txt"),
	})
	world = GameWorld.new()
	world.setup_match(tables)
	_note("对局已打开")
	_refresh()
	_walk_buttons()


func _walk_buttons() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_build_btn.pressed.emit()
	await get_tree().process_frame
	_king_btn.pressed.emit()
	await get_tree().process_frame
	_sell_btn.pressed.emit()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "d:/game2/rpg/mpqediten64/Work/godot/phase0_ui.png"
	var err := img.save_png(path)
	print("LEGION_UI_SHOT ", err, " ", path)
	print("LEGION_UI_DONE gold=", _gold.text, " lumber=", _lumber.text, " income=", _income.text, " king=", _king.text, " force=", _force.text, " food=", _food.text)
	await get_tree().create_timer(0.4).timeout
	get_tree().quit()


func _on_build() -> void:
	var code := world.apply_command(0, {"op": "Build", "uid": "h010", "cell": 0})
	if code == CommandApplier.ERR_OK:
		for eid in world.players[0]["units"]:
			_built_eid = int(eid)
	_note("造豺狼蛮人  结果 %d" % code)
	_refresh()


func _on_king() -> void:
	var code := world.apply_command(0, {"op": "King", "stat": "hp"})
	_note("强化国王生命  结果 %d" % code)
	_refresh()


func _on_sell() -> void:
	var code := world.apply_command(0, {"op": "Sell", "eid": _built_eid})
	_note("出售 %d  结果 %d" % [_built_eid, code])
	if code == CommandApplier.ERR_OK:
		_built_eid = -1
	_refresh()


func _refresh() -> void:
	var p: Dictionary = world.players[0]
	_gold.text = str(p["gold"])
	_lumber.text = str(p["lumber"])
	_income.text = str(p["income"])
	_food.text = "%d / %d" % [p["food_used"], p["food_cap"]]
	_force.text = str(Economy.force_of(p))
	_king.text = "%d / %d" % [p["king_hp"], p["king_hp_max"]]
	_phase.text = "%s  第 %d 波" % [world.phase, world.wave_index]


func _note(line: String) -> void:
	_log.text = line + "\n" + _log.text
	print("LEGION_UI ", line, " gold=", _gold.text, " lumber=", _lumber.text, " income=", _income.text, " king=", _king.text, " force=", _force.text, " food=", _food.text)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("打不开 " + path)
		return ""
	return f.get_as_text()
