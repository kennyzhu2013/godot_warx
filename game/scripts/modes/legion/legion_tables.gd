class_name LegionTables
extends RefCounted

## 军团表读取（Data）。legion_data/*.txt 是逗号分隔、首个非注释行为表头的文本表；
## 以 # 开头的行是来源说明，跳过。值一律保留字符串，由调用方按列转换。

const DATA_DIR := "res://legion_data"
const CELLS_FILE := "cells.txt"


## 读一张表 → 每行 {列名: 字符串}。文件缺失或为空时返回空数组。
static func read_rows(file_name: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var text := RuntimeAssets.read_utf8_text(DATA_DIR.path_join(file_name))
	if text.is_empty():
		AppLog.warn(AppLog.Layer.DATA, "LegionTables", "缺少或为空: %s" % file_name)
		return rows
	var header := PackedStringArray()
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var cols := line.split(",")
		if header.is_empty():
			header = cols
			continue
		var row: Dictionary = {}
		for i in range(mini(header.size(), cols.size())):
			row[header[i].strip_edges()] = cols[i].strip_edges()
		rows.append(row)
	return rows


## cells.txt 中某建造区域所有格中心的外包框中心（WC3 XY）。区域不存在时返回 Vector2.INF。
static func region_center(cells: Array[Dictionary], region: String) -> Vector2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for row in cells:
		if str(row.get("region", "")) != region:
			continue
		var p := Vector2(float(row.get("x", "0")), float(row.get("y", "0")))
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	if lo.x == INF:
		return Vector2.INF
	return (lo + hi) * 0.5
