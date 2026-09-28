class_name LegionMatchMode
extends MatchMode

## 军团战争对局模式（Game Logic）。
## 阶段 0：军团开局库存 + 镜头对准本方建造区。
## 阶段 1：seats.txt 席位表；GM 面板「军团标定」页（叠层、点选坐标、连通检查、重载表）。
## 方案与自定规格：基于godot_war3实现军团战争.md。

## 策划案 5.7
const START_GOLD := 300
const START_LUMBER := 114
## 策划案写主城提供 7 人口
const START_FOOD_CAP := 7

@export var rts_camera: RtsCamera
@export var game_hud: GameHud
@export var director: GameDirector
## 本地玩家席位（seats.txt 的 seat 列）
@export var local_seat: int = 0

var _session: GameSession = null
var _cells: Array[Dictionary] = []
var _seats: LegionSeats = null
var _calibration: LegionCalibration = null
var _overlay: LegionDebugOverlay = null
var _overlay_on: bool = false
var _pick_on: bool = false
var _gm_report: Label = null


func create_session(map_dir: String, local_player: int) -> GameSession:
	var session := GameSession.new()
	session.map_dir = map_dir
	session.local_player = clampi(local_player, 0, 15)
	session.local_race = "human"
	var stock := PlayerStock.new()
	stock.set_all(START_GOLD, START_LUMBER, 0, START_FOOD_CAP)
	session.set_stock(session.local_player, stock)
	return session


func begin(session: GameSession) -> void:
	_session = session
	if rts_camera == null:
		rts_camera = get_node_or_null("../RtsCamera") as RtsCamera
	if game_hud == null:
		game_hud = get_node_or_null("../GameHud") as GameHud
	if director == null:
		director = get_node_or_null("../GameDirector") as GameDirector
	_reload_tables()
	var region := _local_region()
	var center := LegionTables.region_center(_cells, region)
	if center == Vector2.INF:
		AppLog.warn(AppLog.Layer.GAME, "LegionMatchMode", "席位 %d 的区域 %s 不在 cells.txt" % [local_seat, region])
	elif rts_camera != null:
		var world := Wc3Coords.wc3_xy_to_godot(center.x, center.y)
		rts_camera.snap_to(world)
		rts_camera.focus_on_position(world, 0.35)
	if game_hud != null and session != null:
		var s := session.local_stock()
		game_hud.set_status(
			"军团战争 · %s · 金%d 木%d 人口%d/%d"
			% [region, s.gold, s.lumber, s.food_used, s.food_cap]
		)
	_attach_gm_section()


func _reload_tables() -> void:
	_cells = LegionTables.read_rows(LegionTables.CELLS_FILE)
	_seats = LegionSeats.load_table()
	_calibration = null


func _local_region() -> String:
	if _seats == null:
		return ""
	var s: LegionSeats.Seat = _seats.get_seat(local_seat)
	return s.region if s != null else ""


# —— GM「军团标定」页 ——

## GmDebugPanel 由 GameDirector 延迟挂接，等它 ready 再加分节。
func _attach_gm_section() -> void:
	for _i in range(60):
		var gm := get_node_or_null("../GmDebugPanel") as GmDebugPanel
		if gm != null and gm.is_node_ready():
			_build_gm_section(gm)
			return
		await get_tree().process_frame
	AppLog.warn(AppLog.Layer.GM, "LegionMatchMode", "未找到 GmDebugPanel，标定页未挂")


func _build_gm_section(gm: GmDebugPanel) -> void:
	var box := gm.add_section("军团标定（seats.txt）")
	if box == null:
		return
	var overlay_check := CheckBox.new()
	overlay_check.text = "显示建造格 / 出怪 / 漏怪 / 国王"
	overlay_check.toggled.connect(_on_overlay_toggled)
	box.add_child(overlay_check)
	var pick_check := CheckBox.new()
	pick_check.text = "左键点选坐标（复制到剪贴板）"
	pick_check.toggled.connect(func(on: bool) -> void: _pick_on = on)
	box.add_child(pick_check)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	_add_button(row, "检查连通", _on_check_pressed)
	_add_button(row, "重载 seats.txt", _on_reload_pressed)
	_gm_report = Label.new()
	_gm_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gm_report.custom_minimum_size = Vector2(280, 0)
	_gm_report.text = "绿菱形出怪点，橙菱形漏怪点，红框国王；青线连通，品红线不连通。"
	box.add_child(_gm_report)


func _add_button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)


func _on_overlay_toggled(on: bool) -> void:
	_overlay_on = on
	_refresh_overlay()


func _on_check_pressed() -> void:
	_calibration = LegionCalibration.run(_seats, director.get_path_query() if director != null else null)
	_set_report("\n".join(_calibration.lines))
	_refresh_overlay()


func _on_reload_pressed() -> void:
	_reload_tables()
	_set_report("已重载 seats.txt：%d 个席位，启用 %d 个" % [_seats.seats.size(), _seats.enabled_seats().size()])
	_refresh_overlay()


func _refresh_overlay() -> void:
	if not _overlay_on:
		if _overlay != null:
			_overlay.clear()
		return
	if _overlay == null:
		_overlay = LegionDebugOverlay.new()
		_overlay.name = "LegionDebugOverlay"
		add_child(_overlay)
		_overlay.setup(director.get_heightfield() if director != null else null)
	var enabled_regions: Dictionary = {}
	for s in _seats.enabled_seats():
		if s.has_region():
			enabled_regions[s.region] = true
	_overlay.redraw(_cells, enabled_regions, _seats, _calibration.paths if _calibration != null else [])


func _set_report(text: String) -> void:
	if _gm_report != null:
		_gm_report.text = text


# —— 点选坐标 ——

func _input(event: InputEvent) -> void:
	# 左键点选必须走 _input：UnitSelector 在 _input 里会把左键标成已处理，_unhandled_input 收不到。
	# 本节点在场景树末尾，_input 先于选择器。
	if not _pick_on or director == null:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	# 点在 GM 面板等界面上时交给控件，否则点选会把「检查连通」和叠层开关一起吃掉。
	if get_viewport().gui_get_hovered_control() != null:
		return
	var wc3 := director.ground_wc3_at_screen(mb.position)
	if wc3 == Vector2.INF:
		return
	var text := "点击 (%d,%d)" % [roundi(wc3.x), roundi(wc3.y)]
	var pq := director.get_path_query()
	if pq != null and pq.is_ready():
		text += " · %s" % ("可走" if pq.can_walk_wc3(wc3.x, wc3.y) else "不可走")
	var cell := LegionTables.nearest_cell(_cells, wc3)
	if not cell.is_empty():
		text += " · %s 列%s 行%s 格心(%s,%s)" % [
			cell.get("region", ""), cell.get("col", ""), cell.get("row", ""), cell.get("x", ""), cell.get("y", ""),
		]
	DisplayServer.clipboard_set("%d,%d" % [roundi(wc3.x), roundi(wc3.y)])
	_set_report(text)
	if game_hud != null:
		game_hud.set_status(text)
	get_viewport().set_input_as_handled()
