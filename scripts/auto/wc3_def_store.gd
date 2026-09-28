extends Node

## SLK 导出 JSON 的静态定义表缓存（Autoload）。
## 只负责：注册表 → 加载 → 按主键查询。具体行类型由 definitions/* 提供。
## 属 Catalog/定义库，不是地图 heightfield Data。
##
## 注册：
##   Wc3DefStore.register_table("CliffTypes", "TerrainArt/CliffTypes.json", "cliffID", CliffTypeDef.from_slk_record)
## 查询：
##   var d: CliffTypeDef = Wc3DefStore.get_row("CliffTypes", "CLdi") as CliffTypeDef
##   var ids: Array[String] = Wc3DefStore.get_ids("CliffTypes")
##
## 注意：autoload 名 "Wc3DefStore" 与 GDScript class_name 互斥，本脚本不写
## class_name。building_visual.gd 等静态调用 Wc3DefStore 在 GDScript 4 编译
## 阶段通过 autoload 全局变量注册解析，**前提是 editor 启动时已 import**。
## 单元测试（--headless 启动）若报 "Identifier not found: Wc3DefStore"，
## 通常是 .godot/global_script_class_cache.cfg 缺失导致 autoload 全局
## 注册延迟，触发首次 selftest 跑 import 后再跑即恢复。

## table_name → { path, key_field, factory: Callable }
var _registry: Dictionary[String, Dictionary] = {}
## table_name →（主键 → Resource）
var _tables: Dictionary[String, Dictionary] = {}
## table_name → 主键顺序（与 JSON records 顺序一致）
var _orders: Dictionary[String, Array] = {}
## table_name →（主键 → 原始 SLK 记录）。叠加层按字段合并时要用原始记录，行 Resource 不可逆。
var _raw: Dictionary[String, Dictionary] = {}
## overlay_id →（table_name →（主键 → OverlayPrior））：叠加前的状态，clear_overlay 用来还原。
var _overlay_priors: Dictionary[String, Dictionary] = {}


class OverlayPrior:
	extends RefCounted
	var row: Resource = null
	var raw: Dictionary = {}
	## 叠加前表里没有这一行
	var was_absent: bool = true


func _ready() -> void:
	_register_builtin_tables()
	# TerrainArt 四表较小，启动预加载；其它目录表可懒加载 ensure_table
	for table_name in [
		CliffTypeDef.TABLE_NAME,
		TerrainTileDef.TABLE_NAME,
		WaterTypeDef.TABLE_NAME,
		WeatherEffectDef.TABLE_NAME,
	]:
		ensure_table(table_name)


## TerrainArt 内置表注册（Units 定义表一并挂上，懒加载）。
func _register_builtin_tables() -> void:
	CliffTypeDef.register_to(self)
	TerrainTileDef.register_to(self)
	WaterTypeDef.register_to(self)
	WeatherEffectDef.register_to(self)
	# Units/
	ItemDef.register_to(self)
	UnitDataDef.register_to(self)
	UnitBalanceDef.register_to(self)
	UnitUiDef.register_to(self)
	UnitAbilitiesDef.register_to(self)
	UnitWeaponsDef.register_to(self)
	AbilityDataDef.register_to(self)
	AbilityMetaDataDef.register_to(self)
	DestructableDataDef.register_to(self)
	DestructableMetaDataDef.register_to(self)
	MiscMetaDataDef.register_to(self)
	UnitMetaDataDef.register_to(self)
	UpgradeDataDef.register_to(self)
	UpgradeMetaDataDef.register_to(self)
	UpgradeEffectMetaDataDef.register_to(self)
	# Doodads/
	DoodadDataDef.register_to(self)
	DoodadMetaDataDef.register_to(self)
	# Splats/
	UberSplatDef.register_to(self)


## 注册一张 SLK 表。
## [param table_name] 逻辑表名（如 "CliffTypes"）
## [param slk_rel_path] 相对 slk-exported 的路径（如 "TerrainArt/CliffTypes.json"）
## [param primary_key_field] JSON 记录主键字段名（如 "cliffID"）
## [param row_factory] Callable(Dictionary) -> Resource
func register_table(table_name: String, slk_rel_path: String, primary_key_field: String, row_factory: Callable) -> void:
	if table_name.is_empty() or not row_factory.is_valid():
		AppLog.warn(AppLog.Layer.CATALOG, "DefStore", "register_table 参数无效: %s" % table_name)
		return
	_registry[table_name] = {
		"path": slk_rel_path,
		"key_field": primary_key_field,
		"factory": row_factory,
	}

## 是否已注册表
## [param table_name] 逻辑表名（如 "CliffTypes"）
## [return bool] 是否已注册
func has_table(table_name: String) -> bool:
	return _registry.has(table_name)

## 列出所有已注册表
## [return PackedStringArray] 已注册表名数组
func list_tables() -> PackedStringArray:
	var out := PackedStringArray()
	for table_name in _registry.keys():
		out.append(str(table_name))
	out.sort()
	return out

## 确保表已加载；可重复调用。未注册则 no-op。
## [param table_name] 逻辑表名（如 "CliffTypes"）
func ensure_table(table_name: String) -> void:
	if is_table_loaded(table_name):
		return
	load_table(table_name)

## 是否已加载表
## [param table_name] 逻辑表名（如 "CliffTypes"）
## [return bool] 是否已加载表
func is_table_loaded(table_name: String) -> bool:
	return _tables.has(table_name) and not (_tables[table_name] as Dictionary).is_empty()


## 强制（重新）加载；返回行数。未注册返回 -1。
## [param table_name] 逻辑表名（如 "CliffTypes"）
## [return int] 行数
func load_table(table_name: String) -> int:
	if not _registry.has(table_name):
		AppLog.warn(AppLog.Layer.CATALOG, "DefStore", "未注册表: %s" % table_name)
		return -1
	var spec: Dictionary = _registry[table_name]
	var path := RuntimeAssets.slk_path(str(spec["path"]))
	var key_field := str(spec["key_field"])
	var factory: Callable = spec["factory"]
	var by_id: Dictionary = {}
	var order: Array[String] = []
	var raw_by_id: Dictionary = {}
	_tables[table_name] = by_id
	_orders[table_name] = order
	_raw[table_name] = raw_by_id
	if not FileAccess.file_exists(path):
		AppLog.warn(AppLog.Layer.CATALOG, "DefStore", "缺少 %s" % path)
		return 0
	for rec_dict in _read_records(path):
		var id := str(rec_dict.get(key_field, "")).strip_edges()
		if id.is_empty():
			continue
		var row: Variant = factory.call(rec_dict)
		if row == null:
			continue
		by_id[id] = row
		raw_by_id[id] = rec_dict
		order.append(id)
	AppLog.info(
		AppLog.Layer.CATALOG,
		"DefStore",
		"loaded %s count=%d" % [table_name, by_id.size()]
	)
	return by_id.size()


## 主键 → Dictionary（只读视图；勿直接改写）。
## [param table_name] 逻辑表名（如 "CliffTypes"）
## [return Dictionary] 表数据
func get_table(table_name: String) -> Dictionary:
	ensure_table(table_name)
	if not _tables.has(table_name):
		return {}
	return _tables[table_name] as Dictionary


## 按主键获取行
## [param table_name] 逻辑表名（如 "CliffTypes"）
## [param id] 主键
## [return Resource] 行
func get_row(table_name: String, id: String) -> Resource:
	var table := get_table(table_name)
	return table.get(id) as Resource

## 是否已存在行
## [param table_name] 逻辑表名（如 "CliffTypes"）
## [param id] 主键
## [return bool] 是否已存在行
func has_row(table_name: String, id: String) -> bool:
	return get_row(table_name, id) != null

## 列出所有主键（顺序）
## [param table_name] 逻辑表名（如 "CliffTypes"）
## [return Array[String]] 主键顺序数组
func get_ids(table_name: String) -> Array[String]:
	ensure_table(table_name)
	if not _orders.has(table_name):
		return []
	return (_orders[table_name] as Array[String]).duplicate()

## 获取表行数
## [param table_name] 逻辑表名（如 "CliffTypes"）
## [return int] 行数
func count(table_name: String) -> int:
	return get_table(table_name).size()


## 原始 SLK 记录的副本（字段名同 JSON）；没有时返回空字典。叠加层拿它当模板克隆新行。
func get_record(table_name: String, id: String) -> Dictionary:
	ensure_table(table_name)
	var raw_by_id: Dictionary = _raw.get(table_name, {})
	var rec: Variant = raw_by_id.get(id)
	if typeof(rec) != TYPE_DICTIONARY:
		return {}
	return (rec as Dictionary).duplicate(true)


## 本局叠加一组行（按对局装入、结束时 clear_overlay 还原；不叠加时表与 slk-exported 一致）。
## 同主键：与现有原始记录逐字段合并，新值覆盖，再经行工厂重建；新主键追加到表尾。
## 同一 overlay_id 可多次调用，后调用的字段覆盖先调用的。返回写入行数。
func apply_overlay_records(overlay_id: String, table_name: String, records: Array) -> int:
	if overlay_id.is_empty() or not _registry.has(table_name):
		AppLog.warn(AppLog.Layer.CATALOG, "DefStore", "叠加参数无效: %s / %s" % [overlay_id, table_name])
		return 0
	ensure_table(table_name)
	var spec: Dictionary = _registry[table_name]
	var key_field := str(spec["key_field"])
	var factory: Callable = spec["factory"]
	var by_id: Dictionary = _tables[table_name]
	var order: Array = _orders[table_name]
	var raw_by_id: Dictionary = _raw[table_name]
	var priors_by_table: Dictionary = _overlay_priors.get_or_add(overlay_id, {})
	var priors: Dictionary = priors_by_table.get_or_add(table_name, {})
	var written := 0
	for rec in records:
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var id := str((rec as Dictionary).get(key_field, "")).strip_edges()
		if id.is_empty():
			continue
		var merged: Dictionary = (raw_by_id.get(id, {}) as Dictionary).duplicate(true)
		merged.merge(rec as Dictionary, true)
		merged[key_field] = id
		var row: Variant = factory.call(merged)
		if row == null:
			continue
		if not priors.has(id):
			var prior := OverlayPrior.new()
			prior.was_absent = not by_id.has(id)
			if not prior.was_absent:
				prior.row = by_id[id] as Resource
				prior.raw = raw_by_id.get(id, {}) as Dictionary
			priors[id] = prior
		if not by_id.has(id):
			order.append(id)
		by_id[id] = row
		raw_by_id[id] = merged
		written += 1
	return written


## 从一棵与 slk-exported 同构的目录（如 map-parsed/<图>/slk）叠加指定表；缺文件的表跳过。
## 返回 表名 → 写入行数。
func apply_overlay_dir(overlay_id: String, root: String, table_names: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for table_name in table_names:
		if not _registry.has(table_name):
			continue
		var path := root.path_join(str(_registry[table_name]["path"]))
		if not FileAccess.file_exists(RuntimeAssets.project_abs(path)):
			continue
		out[table_name] = apply_overlay_records(overlay_id, table_name, _read_records(path))
	return out


## 撤掉一个叠加层，还原叠加前的行。
func clear_overlay(overlay_id: String) -> void:
	if not _overlay_priors.has(overlay_id):
		return
	var priors_by_table: Dictionary = _overlay_priors[overlay_id]
	for table_name in priors_by_table.keys():
		if not _tables.has(table_name):
			continue
		var by_id: Dictionary = _tables[table_name]
		var order: Array = _orders[table_name]
		var raw_by_id: Dictionary = _raw[table_name]
		var priors: Dictionary = priors_by_table[table_name]
		for id in priors.keys():
			var prior := priors[id] as OverlayPrior
			if prior.was_absent:
				by_id.erase(id)
				raw_by_id.erase(id)
				order.erase(id)
			else:
				by_id[id] = prior.row
				raw_by_id[id] = prior.raw
	_overlay_priors.erase(overlay_id)


func has_overlay(overlay_id: String) -> bool:
	return _overlay_priors.has(overlay_id)


func _read_records(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var text := RuntimeAssets.read_utf8_text(path)
	if text.is_empty():
		return out
	var data: Variant = RuntimeAssets.parse_json_text(text)
	if typeof(data) != TYPE_DICTIONARY:
		return out
	for rec in (data as Dictionary).get("records", []):
		if typeof(rec) == TYPE_DICTIONARY:
			out.append(rec as Dictionary)
	return out


## 按谓词筛主键。predicate: Callable(id: String, row: Resource) -> bool
## [param table_name] 逻辑表名（如 "CliffTypes"）
## [param predicate] 谓词
## [return PackedStringArray] 符合谓词的主键数组
func find_ids(table_name: String, predicate: Callable) -> PackedStringArray:
	var out := PackedStringArray()
	if not predicate.is_valid():
		return out
	for id in get_ids(table_name):
		var row := get_row(table_name, id)
		if row != null and bool(predicate.call(id, row)):
			out.append(id)
	return out
