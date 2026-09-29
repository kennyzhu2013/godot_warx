class_name LegionMatchMode
extends MatchMode

## 军团战争对局模式（Game Logic）。
## 阶段 0：军团开局库存 + 镜头对准本方建造区。
## 阶段 1：seats.txt 席位表；GM 面板「军团标定」页（叠层、点选坐标、连通检查、重载表）。
## 阶段 2：单位叠加行 + 本局伤害表 + 阵营表；命令格造兵 / 强化国王生命 / 出售；两座国王；系统怪走到国王面前。
## 方案与自定规格：基于godot_war3实现军团战争.md。

## 策划案 5.7
const START_GOLD := 300
const START_LUMBER := 114
## 策划案写主城提供 7 人口
const START_FOOD_CAP := 7
## 阶段 2 还没有回合时钟，出售按「本回合」算
const STAGE2_ROUND := 1
## GM 信息刷新间隔（秒）
const GM_INFO_INTERVAL := 0.25

@export var rts_camera: RtsCamera
@export var game_hud: GameHud
@export var director: GameDirector
## 本地玩家席位（seats.txt 的 seat 列），也是本地 owner
@export var local_seat: int = 0

var _session: GameSession = null
var _cells: Array[Dictionary] = []
var _seats: LegionSeats = null
var _calibration: LegionCalibration = null
var _overlay: LegionDebugOverlay = null
var _overlay_on: bool = false
var _pick_on: bool = false
var _gm_report: Label = null

var _defs: LegionUnitDefs = null
var _board: LegionBoard = null
var _king: LegionKing = LegionKing.new()
var _economy: LegionEconomy = LegionEconomy.new()
var _spawner: LegionSpawner = null
var _round: int = STAGE2_ROUND
## 正在放置的兵（命令格点了建造按钮后）；空 = 不在放置
var _placing_id: String = ""
var _primary: Node3D = null
var _gm_wave: SpinBox = null
var _gm_info: Label = null
var _gm_info_acc: float = 0.0


func create_session(map_dir: String, _local_player: int) -> GameSession:
	_resolve_refs()
	var session := GameSession.new()
	session.map_dir = map_dir
	session.local_player = clampi(local_seat, 0, 15)
	session.local_race = "human"
	var stock := PlayerStock.new()
	stock.set_all(START_GOLD, START_LUMBER, 0, START_FOOD_CAP)
	session.set_stock(session.local_player, stock)
	_install_match_data(map_dir)
	return session


func begin(session: GameSession) -> void:
	_session = session
	_resolve_refs()
	_reload_tables()
	_board = LegionBoard.from_rows(_cells)
	var region := _local_region()
	# 这张图 war3map 的 cameraBounds 只包住中心一小块（约 ±2200），
	# 八个建造区在界外。不放开的话 Home 会被夹在角上，到不了本方格子。
	_expand_camera_bounds()
	_focus_home()
	_spawn_kings()
	_spawner = LegionSpawner.new()
	_spawner.name = "LegionSpawner"
	add_child(_spawner)
	_spawner.configure(director, _seats)
	_set_status("军团战争 · %s · 左键命令格造兵，K 强化国王" % region)
	if director != null:
		director.refresh_selection_hud()
	_attach_gm_section()


func _expand_camera_bounds() -> void:
	if rts_camera == null:
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for row in _cells:
		var p := Vector2(float(row.get("x", "0")), float(row.get("y", "0")))
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	if _seats != null:
		for s in _seats.seats:
			if s.king != Vector2.INF:
				lo = Vector2(minf(lo.x, s.king.x), minf(lo.y, s.king.y))
				hi = Vector2(maxf(hi.x, s.king.x), maxf(hi.y, s.king.y))
	if lo.x == INF:
		return
	var margin := 1600.0
	lo -= Vector2(margin, margin)
	hi += Vector2(margin, margin)
	var scale := Wc3Coords.WORLD_SCALE
	var min_xz := Vector2(lo.x * scale, -hi.y * scale)
	var max_xz := Vector2(hi.x * scale, -lo.y * scale)
	rts_camera.set_boundaries(
		Vector2(minf(min_xz.x, max_xz.x), minf(min_xz.y, max_xz.y)),
		Vector2(maxf(min_xz.x, max_xz.x), maxf(min_xz.y, max_xz.y))
	)


func _focus_home() -> void:
	var region := _local_region()
	var center := LegionTables.region_center(_cells, region)
	if center == Vector2.INF:
		AppLog.warn(AppLog.Layer.GAME, "LegionMatchMode", "席位 %d 的区域 %s 不在 cells.txt" % [local_seat, region])
		return
	if rts_camera == null:
		return
	var world := Wc3Coords.wc3_xy_to_godot(center.x, center.y)
	rts_camera.snap_to(world)
	rts_camera.focus_on_position(world, 0.35)


func _exit_tree() -> void:
	LegionUnitDefs.clear_store()
	CombatDamageTable.clear_match_table()
	CombatQuery.clear_owner_sides()


func _resolve_refs() -> void:
	if rts_camera == null:
		rts_camera = get_node_or_null("../RtsCamera") as RtsCamera
	if game_hud == null:
		game_hud = get_node_or_null("../GameHud") as GameHud
	if director == null:
		director = get_node_or_null("../GameDirector") as GameDirector


## 单位叠加行、本局伤害表、阵营表。要在 CommandRouter / 单位生成之前装好。
func _install_match_data(map_dir: String) -> void:
	_defs = LegionUnitDefs.load_tables(map_dir)
	_defs.apply_to_store(map_dir)
	if not _defs.missing_templates.is_empty():
		AppLog.warn(
			AppLog.Layer.GAME,
			"LegionMatchMode",
			"无模型模板（显示胶囊体）：%s" % ", ".join(_defs.missing_templates)
		)
	if director != null and director.map_root != null:
		director.map_root.get_id_catalog().load_default()
	CombatDamageTable.set_match_table(_defs.damage_table)
	_seats = LegionSeats.load_table()
	CombatQuery.set_owner_sides(_seats.side_table())


func _reload_tables() -> void:
	_cells = LegionTables.read_rows(LegionTables.CELLS_FILE)
	_seats = LegionSeats.load_table()
	CombatQuery.set_owner_sides(_seats.side_table())
	_calibration = null
	if _spawner != null:
		_spawner.configure(director, _seats)


func _local_region() -> String:
	var s := _local_seat_row()
	return s.region if s != null else ""


func _local_side() -> String:
	var s := _local_seat_row()
	return s.side if s != null else ""


func _local_seat_row() -> LegionSeats.Seat:
	if _seats == null:
		return null
	return _seats.get_seat(local_seat)


func _local_stock() -> PlayerStock:
	return _session.local_stock() if _session != null else null


func _set_status(text: String) -> void:
	if game_hud != null:
		game_hud.set_status(text)


# —— 国王 ——

func _spawn_kings() -> void:
	if director == null or _seats == null:
		return
	for s in _seats.seats:
		if not s.enabled or s.king == Vector2.INF or _king.king_of(s.side) != null:
			continue
		# 面朝本阵营的漏怪方向（地图中线 y 以上）
		var unit := director.spawn_mode_unit(LegionUnitDefs.KING_ID, s.king, s.seat, deg_to_rad(90.0))
		if unit == null:
			AppLog.warn(AppLog.Layer.GAME, "LegionMatchMode", "国王摆放失败：%s 阵营 @ %s" % [s.side, s.king])
			continue
		_make_passive(unit)
		_king.set_king(s.side, unit)


func _upgrade_king() -> void:
	var up := _defs.king_upgrade
	var side := _local_side()
	var err := _king.try_upgrade_hp(side, _local_stock(), _economy, local_seat, up)
	if not err.is_empty():
		_set_status("强化国王：%s" % err)
		return
	var king := _king.king_of(side)
	_set_status(
		"国王生命 +%d（第 %d 次）· 国王 %d/%d · 收入 %d"
		% [
			up.hp_delta, _king.hp_level(side),
			roundi(UnitLife.get_life(king)), roundi(UnitLife.get_max_life(king)),
			_economy.income_of(local_seat),
		]
	)
	director.refresh_selection_hud()


# —— 造兵 / 出售 ——

func _begin_placing(unit_id: String) -> void:
	var s := _defs.get_spec(unit_id)
	if s == null:
		return
	_placing_id = unit_id
	_set_status("放置 %s（%d 金）：左键点本方建造格；右键 / Esc 取消" % [s.name, s.gold])
	director.refresh_selection_hud()


func _cancel_placing(text: String = "已取消放置") -> void:
	if _placing_id.is_empty():
		return
	_placing_id = ""
	_set_status(text)
	director.refresh_selection_hud()


func _try_place(wc3: Vector2, keep_placing: bool) -> void:
	var s := _defs.get_spec(_placing_id)
	var stock := _local_stock()
	if s == null or stock == null or _board == null:
		_cancel_placing()
		return
	var cell := _board.cell_near(_local_region(), wc3)
	if cell == null:
		_set_status("只能造在本方建造区（%s）的格子上；Home 镜头回本方" % _local_region())
		return
	if not cell.buildable:
		_set_status("这一格不可造")
		return
	if not _board.is_free(cell.key):
		_set_status("这一格已有单位")
		return
	if not stock.can_afford_food(s.food):
		_set_status("人口不足（%d/%d，需要 %d）" % [stock.food_used, stock.food_cap, s.food])
		return
	if not stock.try_spend(s.gold, s.wood):
		_set_status("金币不足（需要 %d）" % s.gold)
		return
	var lane := _local_seat_row()
	var face := deg_to_rad(90.0)
	if lane != null and lane.spawn != Vector2.INF and lane.leak != Vector2.INF:
		var d := lane.spawn - lane.leak
		face = atan2(d.y, d.x)
	var unit := director.spawn_mode_unit(s.id, cell.center, local_seat, face)
	if unit == null:
		stock.add_gold(s.gold)
		stock.add_lumber(s.wood)
		_set_status("摆放失败：%s" % s.id)
		return
	stock.add_food_used(s.food)
	_make_passive(unit)
	_board.place(unit, cell, local_seat, _round, s.gold)
	if not keep_placing:
		_placing_id = ""
	_set_status(
		"已造 %s · 列%d 行%d · -%d 金 · 余 %d 金 · 人口 %d/%d"
		% [s.name, cell.col, cell.row, s.gold, stock.gold, stock.food_used, stock.food_cap]
	)
	director.refresh_selection_hud()


func _sell_primary() -> void:
	var unit: Node3D = _primary if is_instance_valid(_primary) else null
	if not LegionBoard.is_defender(unit) or LegionBoard.seat_of(unit) != local_seat:
		_set_status("只能出售本方防守兵")
		return
	var stock := _local_stock()
	var refund := LegionBoard.sell_refund(unit, _round)
	var name_s := _unit_name(unit)
	_board.release(unit)
	_primary = null
	director.remove_mode_unit(unit)
	if stock != null:
		stock.add_gold(refund)
	_set_status(
		"已出售 %s · +%d 金 · 余 %d 金 · 人口 %d/%d"
		% [name_s, refund, stock.gold if stock else 0, stock.food_used if stock else 0, stock.food_cap if stock else 0]
	)
	director.refresh_selection_hud()


## 阶段 2 不打：防守兵与国王不索敌、不反击（阶段 3 由回合时钟切换）。
func _make_passive(unit: Node3D) -> void:
	var ai := UnitAI.of(unit)
	if ai != null:
		ai.set_profile(UnitAI.Profile.PASSIVE)


func _unit_name(unit: Node) -> String:
	var tid := CombatQuery.type_id_of(unit)
	var s: LegionUnitDefs.Spec = _defs.get_spec(tid) if _defs != null else null
	return s.name if s != null else tid


# —— MatchMode：命令格 ——

func selection_changed(primary: Node3D, _selected: Array) -> void:
	_primary = primary
	_refresh_gm_info()


func command_card(primary: Node3D, _selected: Array) -> Array:
	if _defs == null:
		return []
	if LegionBoard.is_defender(primary) and LegionBoard.seat_of(primary) == local_seat:
		return LegionCommandCard.defender_card(_unit_name(primary), LegionBoard.sell_refund(primary, _round))
	return LegionCommandCard.main_card(_defs, _local_stock(), _placing_id)


func handle_command_action(action_id: String) -> bool:
	if action_id.begins_with(LegionCommandCard.ACTION_BUILD_PREFIX):
		_begin_placing(action_id.substr(LegionCommandCard.ACTION_BUILD_PREFIX.length()))
		return true
	match action_id:
		LegionCommandCard.ACTION_KING_HP:
			_upgrade_king()
		LegionCommandCard.ACTION_SELL:
			_sell_primary()
		LegionCommandCard.ACTION_CANCEL:
			_cancel_placing()
		_:
			return false
	return true


func blocks_unit_orders(selected: Array) -> bool:
	for n in selected:
		if LegionBoard.is_defender(n as Node):
			return true
	return false


# —— GM 面板 ——

## GmDebugPanel 由 GameDirector 延迟挂接，等它 ready 再加分节。
func _attach_gm_section() -> void:
	for _i in range(60):
		var gm := get_node_or_null("../GmDebugPanel") as GmDebugPanel
		if gm != null and gm.is_node_ready():
			_build_gm_section(gm)
			_build_gm_stage2_section(gm)
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


func _build_gm_stage2_section(gm: GmDebugPanel) -> void:
	var box := gm.add_section("军团阶段 2（造兵 / 国王 / 系统怪）")
	if box == null:
		return
	var wave_row := HBoxContainer.new()
	wave_row.add_theme_constant_override("separation", 6)
	box.add_child(wave_row)
	_gm_wave = SpinBox.new()
	_gm_wave.min_value = 1
	_gm_wave.max_value = maxf(_defs.waves.size() if _defs != null else 1, 1)
	_gm_wave.value = 1
	_gm_wave.prefix = "第"
	_gm_wave.suffix = "波"
	wave_row.add_child(_gm_wave)
	_add_button(wave_row, "刷怪", _on_gm_spawn_wave)
	_add_button(wave_row, "清怪", _on_gm_clear_creeps)
	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 6)
	box.add_child(res_row)
	_add_button(res_row, "+100 金", func() -> void: _gm_add(100, 0))
	_add_button(res_row, "+100 木", func() -> void: _gm_add(0, 100))
	_add_button(res_row, "镜头回本方", _focus_home)
	_gm_info = Label.new()
	_gm_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gm_info.custom_minimum_size = Vector2(280, 0)
	box.add_child(_gm_info)
	_refresh_gm_info()


func _add_button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)


func _on_gm_spawn_wave() -> void:
	if _spawner == null or _defs == null:
		return
	var n := int(_gm_wave.value) if _gm_wave != null else 1
	for w in _defs.waves:
		if w.wave == n:
			var queued := _spawner.spawn_wave(w)
			_set_status("第 %d 波：排队 %d 只（%s）" % [n, queued, w.unit_id])
			return


func _on_gm_clear_creeps() -> void:
	if _spawner != null:
		_spawner.clear()
		_set_status("已清除系统怪")


func _gm_add(gold: int, lumber: int) -> void:
	var stock := _local_stock()
	if stock == null:
		return
	stock.add_gold(gold)
	stock.add_lumber(lumber)
	director.refresh_selection_hud()


func _process(delta: float) -> void:
	_gm_info_acc += delta
	if _gm_info_acc < GM_INFO_INTERVAL:
		return
	_gm_info_acc = 0.0
	_refresh_gm_info()


func _refresh_gm_info() -> void:
	if _gm_info == null or not _gm_info.is_visible_in_tree():
		return
	var lines: PackedStringArray = []
	lines.append("选中：%s" % _describe_unit(_primary if is_instance_valid(_primary) else null))
	for side in ["L", "R"]:
		var k := _king.king_of(side)
		if k != null:
			lines.append(
				"国王 %s：%d/%d（强化 %d 次）"
				% [side, roundi(UnitLife.get_life(k)), roundi(UnitLife.get_max_life(k)), _king.hp_level(side)]
			)
	lines.append("本席 %d 收入 %d · 场上系统怪 %d" % [
		local_seat, _economy.income_of(local_seat), _spawner.creeps().size() if _spawner != null else 0,
	])
	_gm_info.text = "\n".join(lines)


func _describe_unit(unit: Node3D) -> String:
	if unit == null:
		return "无"
	var owner := CombatQuery.owner_of(unit)
	var side := CombatQuery.side_of_owner(owner)
	var who := "对方" if not side.is_empty() and side != _local_side() else "本方"
	var seat_kind := "电脑席" if _seats != null and _seats.get_seat(owner) != null and not _seats.get_seat(owner).has_region() else "玩家席"
	return "%s %s · owner %d（%s 阵营%s，%s）· 生命 %d/%d" % [
		CombatQuery.type_id_of(unit), _unit_name(unit), owner, side, seat_kind, who,
		roundi(UnitLife.get_life(unit)), roundi(UnitLife.get_max_life(unit)),
	]


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


# —— 地面点击：放置防守兵 / 点选坐标 ——

func _input(event: InputEvent) -> void:
	# 地面左键必须走 _input：UnitSelector 在 _input 里会把左键标成已处理，_unhandled_input 收不到。
	# 本节点在场景树末尾，_input 先于选择器。
	if director == null:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_HOME:
		_focus_home()
		get_viewport().set_input_as_handled()
		return
	if not _placing_id.is_empty():
		_input_placing(event)
		return
	if not _pick_on:
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
	_set_status(text)
	get_viewport().set_input_as_handled()


func _input_placing(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		_cancel_placing()
		get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	# 点命令格 / GM 面板时交给控件
	if get_viewport().gui_get_hovered_control() != null:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_placing()
		get_viewport().set_input_as_handled()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var wc3 := director.ground_wc3_at_screen(mb.position)
	if wc3 != Vector2.INF:
		_try_place(wc3, mb.shift_pressed)
	get_viewport().set_input_as_handled()
