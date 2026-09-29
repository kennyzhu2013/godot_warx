class_name LegionMatchMode
extends MatchMode

## 军团战争对局模式（Game Logic）。
## 阶段 0：军团开局库存 + 镜头对准本方建造区。
## 阶段 1：seats.txt 席位表；GM 面板「军团标定」页（叠层、点选坐标、连通检查、重载表）。
## 阶段 2：单位叠加行 + 本局伤害表 + 阵营表；命令格造兵 / 强化国王生命 / 出售；两座国王；系统怪走到国王面前。
## 阶段 3：LegionRoundClock 准备 → 战斗 → 结算；怪攻击移动，防守兵在战斗阶段自动索敌（拴在格子上），
## 结算发收入、防守兵回格回满血、战死的重新摆出；国王原地攻击，战斗中每秒回复。
## 方案与自定规格：基于godot_war3实现军团战争.md。

## 策划案 5.7
const START_GOLD := 300
const START_LUMBER := 114
## 策划案写主城提供 7 人口
const START_FOOD_CAP := 7
## GM / 顶栏信息刷新间隔（秒）
const GM_INFO_INTERVAL := 0.25
## 自定规格：防守兵战斗中离自己格子超过这个距离就回格（CAMP_CREEP 拴绳）
const DEFENDER_LEASH_WC3 := 600.0

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
var _clock: LegionRoundClock = LegionRoundClock.new()
## 上一次结算的结果，下一回合准备提示里一起显示
var _settle_note: String = ""
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
	_spawner.attack_move = true
	_spawner.king_of_side = _king.king_of
	var king_spec := _defs.get_spec(LegionUnitDefs.KING_ID)
	_king.regen_per_sec = king_spec.regen if king_spec != null else 0.0
	_clock.last_round = mini(LegionRoundClock.TEST_WAVES, maxi(_defs.waves.size(), 1))
	_clock.phase_changed.connect(_on_phase_changed)
	_set_status("军团战争 · %s · 左键命令格造兵，K 强化国王" % region)
	if director != null:
		director.refresh_selection_hud()
	_attach_gm_section()
	_clock.start(1)


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
	_focus_wc3(center)


func _focus_king(side: String = "") -> void:
	if side.is_empty():
		side = _local_side()
	var king := _seats.king_of(side) if _seats != null else Vector2.INF
	if king != Vector2.INF:
		_focus_wc3(king)


func _focus_wc3(wc3: Vector2) -> void:
	if rts_camera == null:
		return
	var world := Wc3Coords.wc3_xy_to_godot(wc3.x, wc3.y)
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
		# 国王不移动，只打射程内的怪
		var router := director.get_command_router()
		if router != null:
			router.issue_hold([unit], UnitOrder.Source.UNKNOWN)
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
	if _clock.phase != LegionRoundClock.Phase.PREP:
		_set_status("只能在准备阶段造兵（现在是%s）" % _clock.phase_name())
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
	if _clock.phase != LegionRoundClock.Phase.PREP:
		_cancel_placing("只能在准备阶段造兵（现在是%s）" % _clock.phase_name())
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
	var unit := director.spawn_mode_unit(s.id, cell.center, local_seat, _defender_facing(local_seat))
	if unit == null:
		stock.add_gold(s.gold)
		stock.add_lumber(s.wood)
		_set_status("摆放失败：%s" % s.id)
		return
	stock.add_food_used(s.food)
	_make_passive(unit)
	_board.place(unit, cell, local_seat, _clock.round_no, s.gold, s.food)
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
	if _clock.phase != LegionRoundClock.Phase.PREP:
		_set_status("只能在准备阶段出售（现在是%s）" % _clock.phase_name())
		return
	var stock := _local_stock()
	var refund := LegionBoard.sell_refund(unit, _clock.round_no)
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


## 准备阶段的防守兵与国王：不索敌、不反击。
func _make_passive(unit: Node3D) -> void:
	var ai := UnitAI.of(unit)
	if ai != null:
		ai.set_profile(UnitAI.Profile.PASSIVE)
		ai.yield_to_player()


func _defender_facing(seat: int) -> float:
	var lane: LegionSeats.Seat = _seats.get_seat(seat) if _seats != null else null
	if lane != null and lane.spawn != Vector2.INF and lane.leak != Vector2.INF:
		var d := lane.spawn - lane.leak
		return atan2(d.y, d.x)
	return deg_to_rad(90.0)


# —— 回合 ——

func _on_phase_changed(phase: int, round_no: int) -> void:
	match phase:
		LegionRoundClock.Phase.PREP:
			_set_defenders_fighting(false)
			var prep := "第 %d 波准备：%d 秒后开战，可造兵 / 出售 / 强化国王" % [round_no, roundi(_clock.time_left)]
			_set_status(prep if _settle_note.is_empty() else "%s ｜ %s" % [_settle_note, prep])
			_settle_note = ""
		LegionRoundClock.Phase.BATTLE:
			_cancel_placing("")
			_set_defenders_fighting(true)
			_king.reset_regen_clock()
			var queued := _spawn_round_wave(round_no)
			_set_status("第 %d 波开战：系统怪 %d 只" % [round_no, queued])
		LegionRoundClock.Phase.SETTLE:
			_settle_round(round_no)
		LegionRoundClock.Phase.OVER:
			if _spawner != null:
				_spawner.clear()
			_set_defenders_fighting(false)
			_set_status("对局结束：%s" % _clock.over_reason)
	if director != null:
		director.refresh_selection_hud()
	_refresh_mode_info()


func _spawn_round_wave(round_no: int) -> int:
	if _spawner == null or _defs == null:
		return 0
	for w in _defs.waves:
		if w.wave == round_no:
			return _spawner.spawn_wave(w)
	return 0


## 战斗阶段：CAMP_CREEP（待机索敌 + 受击反击 + 拴在自己格子上）；否则 PASSIVE。
func _set_defenders_fighting(on: bool) -> void:
	if _board == null:
		return
	for u in _board.defenders():
		var ai := UnitAI.of(u)
		if ai == null:
			continue
		if not on:
			_make_passive(u)
			continue
		var cell := _board.get_cell(str(u.get_meta(LegionBoard.META_CELL, "")))
		ai.home_wc3 = cell.center if cell != null else Wc3Coords.godot_to_wc3_xy(u.global_position)
		ai.leash_wc3 = DEFENDER_LEASH_WC3
		ai.set_profile(UnitAI.Profile.CAMP_CREEP)


## 结算：超时残怪移除、发收入、防守兵复位。
func _settle_round(round_no: int) -> void:
	var left := 0
	if _spawner != null:
		left = _spawner.creeps().size()
		_spawner.clear()
	var income := _economy.income_of(local_seat)
	var stock := _local_stock()
	if stock != null:
		stock.add_gold(income)
	var restored := _reset_defenders()
	var text := "第 %d 波结算：+%d 金（收入）· 复位 %d · 重新摆出 %d" % [round_no, income, restored.x, restored.y]
	if _clock.timed_out and left > 0:
		text += " · 超时移除 %d 只" % left
	_settle_note = text
	_set_status(text)
	AppLog.info(AppLog.Layer.GAME, "LegionMatchMode", text)


## 活着的回格回满血，战死的在原格重新摆出。返回 (复位数, 重摆数)。
func _reset_defenders() -> Vector2i:
	var reset := 0
	var respawned := 0
	if _board == null or director == null:
		return Vector2i.ZERO
	for d in _board.records():
		_restore_dead_food(d)
		if d.is_alive():
			var u := d.unit_node()
			director.reset_mode_unit(u, d.cell.center)
			UnitLife.set_life(u, UnitLife.get_max_life(u))
			_make_passive(u)
			reset += 1
			continue
		var corpse := d.unit_node()
		if corpse != null:
			director.remove_mode_unit(corpse)
		var unit := director.spawn_mode_unit(d.unit_id, d.cell.center, d.seat, _defender_facing(d.seat))
		if unit == null:
			AppLog.warn(AppLog.Layer.GAME, "LegionMatchMode", "重新摆出失败 %s @ %s" % [d.unit_id, d.cell.key])
			continue
		_make_passive(unit)
		_board.attach(d, unit)
		respawned += 1
	return Vector2i(reset, respawned)


## 防守兵战死时 GameDirector 已退人口；战死的兵结算会回来，人口要一直占着。
func _restore_dead_food(d: LegionBoard.Defender) -> void:
	if d.food_restored or d.food <= 0 or d.is_alive() or d.seat != local_seat:
		return
	var u := d.unit_node()
	if u != null and not bool(u.get_meta("food_released", false)):
		return
	var stock := _local_stock()
	if stock != null:
		stock.add_food_used(d.food)
	d.food_restored = true


func _watch_battle(delta: float) -> void:
	if _clock.phase != LegionRoundClock.Phase.BATTLE:
		return
	_king.regen_tick(delta)
	if _board != null:
		for d in _board.records():
			_restore_dead_food(d)
	var fallen := _king.fallen_side()
	if not fallen.is_empty():
		_clock.end_match("%s 阵营国王阵亡" % fallen)


func _refresh_mode_info() -> void:
	if game_hud == null:
		return
	var text := "第 %d/%d 波 · %s" % [_clock.round_no, _clock.last_round, _clock.phase_name()]
	if _clock.phase == LegionRoundClock.Phase.PREP or _clock.phase == LegionRoundClock.Phase.BATTLE:
		text += " %d 秒" % ceili(maxf(_clock.time_left, 0.0))
	if _clock.paused:
		text += "（暂停）"
	text += " · 收入 %d" % _economy.income_of(local_seat)
	game_hud.set_mode_info(text)


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
		return LegionCommandCard.defender_card(_unit_name(primary), LegionBoard.sell_refund(primary, _clock.round_no))
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
			_build_gm_round_section(gm)
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


func _build_gm_round_section(gm: GmDebugPanel) -> void:
	var box := gm.add_section("军团回合（造兵 / 国王 / 波次）")
	if box == null:
		return
	var wave_row := HBoxContainer.new()
	wave_row.add_theme_constant_override("separation", 6)
	box.add_child(wave_row)
	_gm_wave = SpinBox.new()
	_gm_wave.min_value = 1
	_gm_wave.max_value = maxf(_clock.last_round, 1)
	_gm_wave.value = 1
	_gm_wave.prefix = "第"
	_gm_wave.suffix = "波"
	wave_row.add_child(_gm_wave)
	_add_button(wave_row, "跳到该波", _on_gm_jump_wave)
	var round_row := HBoxContainer.new()
	round_row.add_theme_constant_override("separation", 6)
	box.add_child(round_row)
	_add_button(round_row, "立即开战", _clock.force_battle)
	_add_button(round_row, "立即结算", _clock.force_settle)
	var pause_check := CheckBox.new()
	pause_check.text = "暂停计时"
	pause_check.toggled.connect(func(on: bool) -> void:
		_clock.paused = on
		_refresh_mode_info()
	)
	round_row.add_child(pause_check)
	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 6)
	box.add_child(res_row)
	_add_button(res_row, "+100 金", func() -> void: _gm_add(100, 0))
	_add_button(res_row, "+100 木", func() -> void: _gm_add(0, 100))
	_add_button(res_row, "镜头回本方", _focus_home)
	_add_button(res_row, "镜头到国王", _focus_king)
	_add_button(res_row, "镜头到对面国王", func() -> void: _focus_king(LegionSeats.opposite(_local_side())))
	var test_row := HBoxContainer.new()
	test_row.add_theme_constant_override("separation", 6)
	box.add_child(test_row)
	var lane_check := CheckBox.new()
	lane_check.text = "只刷本方路"
	lane_check.tooltip_text = "对面路不出怪，对面国王不挨打，对局不会因它阵亡提前结束（下一波起生效）"
	lane_check.toggled.connect(func(on: bool) -> void:
		if _spawner != null:
			_spawner.only_lane_seat = local_seat if on else -1
	)
	test_row.add_child(lane_check)
	_add_button(test_row, "击杀一个本方兵", _on_gm_kill_defender)
	_add_button(test_row, "国王回满血", _on_gm_heal_kings)
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


## 选中的是本方防守兵就杀它，否则杀名册里第一个活着的本方兵；结算时应在原格重新摆出。
func _on_gm_kill_defender() -> void:
	if _board == null or director == null:
		return
	var target: Node3D = null
	var sel: Node3D = _primary if is_instance_valid(_primary) else null
	if LegionBoard.is_defender(sel) and LegionBoard.seat_of(sel) == local_seat and CombatQuery.is_alive_in_world(sel):
		target = sel
	else:
		for d in _board.records():
			if d.seat == local_seat and d.is_alive():
				target = d.unit_node()
				break
	if target == null:
		_set_status("没有活着的本方防守兵")
		return
	var name_s := _unit_name(target)
	director.kill_mode_unit(target)
	_set_status("GM 击杀 %s：结算时应在原格重新摆出，人口不变" % name_s)


func _on_gm_heal_kings() -> void:
	for k in _king.all_kings():
		if CombatQuery.is_alive_in_world(k):
			UnitLife.set_life(k, UnitLife.get_max_life(k))


## 跳到第 N 波准备：清场上系统怪、防守兵复位，不发收入。
func _on_gm_jump_wave() -> void:
	if _clock.phase == LegionRoundClock.Phase.OVER:
		return
	var n := int(_gm_wave.value) if _gm_wave != null else 1
	if _spawner != null:
		_spawner.clear()
	_reset_defenders()
	_clock.jump_to(n)


func _gm_add(gold: int, lumber: int) -> void:
	var stock := _local_stock()
	if stock == null:
		return
	stock.add_gold(gold)
	stock.add_lumber(lumber)
	director.refresh_selection_hud()


func _process(delta: float) -> void:
	if _session != null:
		_clock.tick(delta, _spawner == null or _spawner.is_idle())
		_watch_battle(delta)
	_gm_info_acc += delta
	if _gm_info_acc < GM_INFO_INTERVAL:
		return
	_gm_info_acc = 0.0
	_refresh_mode_info()
	_refresh_gm_info()


func _refresh_gm_info() -> void:
	if _gm_info == null or not _gm_info.is_visible_in_tree():
		return
	var lines: PackedStringArray = []
	var phase_line := "第 %d/%d 波 · %s" % [_clock.round_no, _clock.last_round, _clock.phase_name()]
	if _clock.phase == LegionRoundClock.Phase.PREP or _clock.phase == LegionRoundClock.Phase.BATTLE:
		phase_line += " 剩 %.1f 秒" % maxf(_clock.time_left, 0.0)
	elif _clock.phase == LegionRoundClock.Phase.OVER:
		phase_line += "（%s）" % _clock.over_reason
	lines.append(phase_line)
	if _board != null:
		lines.append("防守兵：名册 %d · 在场 %d" % [_board.records().size(), _board.defenders().size()])
	lines.append("选中：%s" % _describe_unit(_primary if is_instance_valid(_primary) else null))
	for side in ["L", "R"]:
		var k := _king.king_of(side)
		if k != null:
			lines.append(
				"国王 %s：%d/%d（强化 %d 次）"
				% [side, roundi(UnitLife.get_life(k)), roundi(UnitLife.get_max_life(k)), _king.hp_level(side)]
			)
	lines.append("本席 %d 收入 %d" % [local_seat, _economy.income_of(local_seat)])
	if _spawner != null:
		var sm := _spawner.summary()
		lines.append(
			"系统怪：排队 %d · 去漏怪点 %d · 去国王 %d · 已站定 %d（离国王最远 %d）"
			% [sm.pending, sm.to_leak, sm.to_king, sm.done, roundi(sm.done_max_king_dist)]
		)
		var owners: Dictionary = sm.owners
		for owner_id in owners:
			lines.append("  owner %d（%s）× %d" % [owner_id, _describe_owner(owner_id), owners[owner_id]])
	_gm_info.text = "\n".join(lines)


func _describe_unit(unit: Node3D) -> String:
	if unit == null:
		return "无"
	var owner := CombatQuery.owner_of(unit)
	return "%s %s · owner %d（%s）· 生命 %d/%d" % [
		CombatQuery.type_id_of(unit), _unit_name(unit), owner, _describe_owner(owner),
		roundi(UnitLife.get_life(unit)), roundi(UnitLife.get_max_life(unit)),
	]


func _describe_owner(owner_id: int) -> String:
	var side := CombatQuery.side_of_owner(owner_id)
	var who := "对方" if not side.is_empty() and side != _local_side() else "本方"
	var seat: LegionSeats.Seat = _seats.get_seat(owner_id) if _seats != null else null
	var seat_kind := "电脑席" if seat != null and not seat.has_region() else "玩家席"
	return "%s 阵营%s，%s" % [side, seat_kind, who]


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
