class_name LegionMatchMode
extends MatchMode

## 军团战争对局模式（Game Logic）。当前实现阶段 0：军团开局库存 + 镜头对准本方建造区。
## 方案与自定规格：基于godot_war3实现军团战争.md。

## 策划案 5.7
const START_GOLD := 300
const START_LUMBER := 114
## 策划案写主城提供 7 人口
const START_FOOD_CAP := 7

@export var rts_camera: RtsCamera
@export var game_hud: GameHud
## 本地玩家的建造区域（cells.txt 的 region 列）。阶段 1 起改由 seats.txt 按席位给出。
@export var local_region: String = "RctPlayer_0"


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
	var center := LegionTables.region_center(LegionTables.read_rows(LegionTables.CELLS_FILE), local_region)
	if center == Vector2.INF:
		AppLog.warn(AppLog.Layer.GAME, "LegionMatchMode", "cells.txt 中没有区域 %s" % local_region)
	elif rts_camera != null:
		var world := Wc3Coords.wc3_xy_to_godot(center.x, center.y)
		rts_camera.snap_to(world)
		rts_camera.focus_on_position(world, 0.35)
	if game_hud != null and session != null:
		var s := session.local_stock()
		game_hud.set_status(
			"军团战争 · %s · 金%d 木%d 人口%d/%d"
			% [local_region, s.gold, s.lumber, s.food_used, s.food_cap]
		)
