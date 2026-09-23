extends Control

## 阶段 1 窗口。地形、路径、建造格都来自已解析的地图，不跑模拟器。

const X0 := -7200.0
const Y0 := -3200.0
const SPAN_X := 14400.0
const SPAN_Y := 9000.0
const CELL := 32.0

var _img: Image
var _tex: TextureRect
var _info: Label
var _cells: Array = []
var _match: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var title := Label.new()
	title.text = "军团战争  阶段 1  地图对位"
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 22)
	add_child(title)
	_tex = TextureRect.new()
	_tex.position = Vector2(16, 44)
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_tex)
	_info = Label.new()
	_info.position = Vector2(16, 360)
	_info.custom_minimum_size = Vector2(1240, 180)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 16)
	add_child(_info)
	_tex.gui_input.connect(_on_map_input)
	_build()
	_check_cell()
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	var path := "d:/game2/rpg/mpqediten64/Work/godot/phase1_ui.png"
	var err := shot.save_png(path)
	print("LEGION_MAP_SHOT ", err, " ", path)
	print("LEGION_MAP_DONE ", _match)
	await get_tree().create_timer(0.4).timeout
	get_tree().quit()


func _build() -> void:
	var pathing: Dictionary = _json("res://assets/map-parsed/legiontd/pathing.json")
	var hf: Dictionary = _json("res://assets/map-parsed/legiontd/terrain-heightfield.json")
	var raw: PackedByteArray = Marshalls.base64_to_raw(str(pathing["cellsBase64"]))
	var pw := int(pathing["width"])
	var ox := float(pathing["origin"]["x"])
	var oy := float(pathing["origin"]["y"])
	var flags: Array = hf["flagsPacked"]
	var layers: Array = hf["layerHeights"]
	var tw := int(hf["tilepointWidth"])
	var cx0 := float(hf["centerOffset"]["x"])
	var cy0 := float(hf["centerOffset"]["y"])
	var cols := int(SPAN_X / CELL)
	var rows := int(SPAN_Y / CELL)
	_img = Image.create(cols, rows, false, Image.FORMAT_RGB8)
	_img.fill(Color(0.02, 0.02, 0.02))
	var water_n := 0
	var cliff_n := 0
	var build_n := 0
	for y in rows:
		for x in cols:
			var wx := X0 + float(x) * CELL + 16.0
			var wy := Y0 + float(y) * CELL + 16.0
			var pi := int((wx - ox) / CELL)
			var pj := int((wy - oy) / CELL)
			var pf := 0
			if pi >= 0 and pj >= 0 and pi < pw and pj < int(pathing["height"]):
				pf = raw[pj * pw + pi]
			var tx := int((wx - cx0) / 128.0)
			var ty := int((wy - cy0) / 128.0)
			var water := false
			var cliff := false
			if tx >= 0 and ty >= 0 and tx < tw and ty < int(hf["tilepointHeight"]):
				var ti := ty * tw + tx
				water = (int(flags[ti]) & 1) != 0
				cliff = int(layers[ti]) != 2
			var c := Color(0.45, 0.42, 0.32)
			if water:
				c = Color(0.15, 0.35, 0.72)
				water_n += 1
				if cliff:
					cliff_n += 1
			elif cliff:
				c = Color(0.55, 0.28, 0.16)
				cliff_n += 1
			elif (pf & 2) != 0:
				c = Color(0.12, 0.12, 0.13)
			elif (pf & 8) == 0:
				c = Color(0.25, 0.55, 0.28)
				build_n += 1
			_img.set_pixel(x, rows - 1 - y, c)
	_paint_lanes(rows)
	_paint_starts(rows)
	var itex := ImageTexture.create_from_image(_img)
	_tex.texture = itex
	_tex.custom_minimum_size = Vector2(cols, rows)
	_tex.size = Vector2(cols, min(rows, 460))
	_cells = _load_cells()
	_info.text = "绿=可造空地  蓝=水  深色=不可走  黄点=w3i 开始点  白线=可走折线\n水面采样 %d，其中悬崖层 %d（本图悬崖层都在水下，没有干地悬崖）  可造采样 %d\n建造格 %d 个，全部来自 RctPlayer 区域。" % [water_n, cliff_n, build_n, _cells.size()]


func _paint_lanes(rows: int) -> void:
	var text := FileAccess.get_file_as_string("res://legion_data/lanes.txt")
	var prev := Vector2i(-1, -1)
	var prev_lane := ""
	for line in text.split("\n"):
		if line.is_empty() or line.begins_with("#") or line.begins_with("lane,"):
			continue
		var p := line.split(",")
		if p.size() < 5 or p[4] != "1":
			continue
		var lane := p[0]
		var px := _px(float(p[2]), float(p[3]), rows)
		if lane == prev_lane and prev.x >= 0:
			_line(prev, px, Color(0.95, 0.95, 0.9))
		prev = px
		prev_lane = lane


func _paint_starts(rows: int) -> void:
	var text := FileAccess.get_file_as_string("res://legion_data/starts.txt")
	for line in text.split("\n"):
		if line.is_empty() or line.begins_with("#") or line.begins_with("player,"):
			continue
		var p := line.split(",")
		if p.size() < 7:
			continue
		var px := _px(float(p[4]), float(p[5]), rows)
		var col := Color(0.95, 0.85, 0.2) if p[6] != "NONE" else Color(0.9, 0.25, 0.2)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var x := px.x + dx
				var y := px.y + dy
				if x >= 0 and y >= 0 and x < _img.get_width() and y < _img.get_height():
					_img.set_pixel(x, y, col)


func _check_cell() -> void:
	var hit: Dictionary = {}
	for c in _cells:
		if str(c["region"]) == "RctPlayer_3" and int(c["col"]) == 0 and int(c["row"]) == 0:
			hit = c
			break
	var rows := _img.get_height()
	var px := _px(float(hit["x"]), float(hit["y"]), rows)
	var back := _world(px, rows)
	var nearest := _nearest(back)
	var same := str(nearest.get("region", "")) == "RctPlayer_3" and int(nearest.get("col", -1)) == 0 and int(nearest.get("row", -1)) == 0
	_match = "RctPlayer_3 格 0,0 文件 %s,%s 点击换算 %d,%d 最近格 %s %s,%s %s" % [
		str(hit["x"]), str(hit["y"]), int(back.x), int(back.y),
		str(nearest.get("region", "")), str(nearest.get("x", "")), str(nearest.get("y", "")),
		"一致" if same else "不一致",
	]
	_info.text += "\n" + _match
	print("LEGION_MAP ", _match)


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var rows := _img.get_height()
		var local := _tex.get_local_mouse_position()
		var sx := _img.get_width() / _tex.size.x
		var sy := _img.get_height() / _tex.size.y
		var px := Vector2i(int(local.x * sx), int(local.y * sy))
		var back := _world(px, rows)
		var nearest := _nearest(back)
		_info.text = "点击 %d,%d  最近建造格 %s 列 %s 行 %s  文件坐标 %s,%s" % [
			int(back.x), int(back.y), str(nearest.get("region", "")),
			str(nearest.get("col", "")), str(nearest.get("row", "")),
			str(nearest.get("x", "")), str(nearest.get("y", "")),
		]


func _nearest(world: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1.0e12
	for c in _cells:
		var dx := float(c["x"]) - world.x
		var dy := float(c["y"]) - world.y
		var d := dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = c
	return best


func _px(x: float, y: float, rows: int) -> Vector2i:
	return Vector2i(int((x - X0) / CELL), rows - 1 - int((y - Y0) / CELL))


func _world(px: Vector2i, rows: int) -> Vector2:
	return Vector2(X0 + float(px.x) * CELL + 16.0, Y0 + float(rows - 1 - px.y) * CELL + 16.0)


func _line(a: Vector2i, b: Vector2i, color: Color) -> void:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	if n <= 0:
		return
	for i in n + 1:
		var x := int(round(lerpf(float(a.x), float(b.x), float(i) / float(n))))
		var y := int(round(lerpf(float(a.y), float(b.y), float(i) / float(n))))
		if x >= 0 and y >= 0 and x < _img.get_width() and y < _img.get_height():
			_img.set_pixel(x, y, color)


func _load_cells() -> Array:
	var out: Array = []
	var text := FileAccess.get_file_as_string("res://legion_data/cells.txt")
	for line in text.split("\n"):
		if line.is_empty() or line.begins_with("#") or line.begins_with("region,"):
			continue
		var p := line.split(",")
		if p.size() < 5:
			continue
		out.append({"region": p[0], "col": int(p[1]), "row": int(p[2]), "x": int(p[3]), "y": int(p[4])})
	return out


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("打不开 " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
