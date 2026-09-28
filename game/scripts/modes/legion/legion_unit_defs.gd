class_name LegionUnitDefs
extends RefCounted

## 军团单位定义（Data）：legion_data 的中文数值表 → Wc3DefStore 本局叠加行 + 本局伤害表。
## 叠加顺序：地图 slk（<map_dir>/slk，模型、比例等原图字段）→ 按模板克隆一行 → 军团表数值覆盖。
## 模板取 <map_dir>/legion_models.json（tools/map-parse/src/export-legion-slk.js 生成）；
## 没有该文件时按「表里有同 id 行」→ model_id 列。都没有时模型为空，场上显示胶囊体。
## 自定规格：系统怪按波次用合成 id w001–w030，国王 id lkng；护甲值一律 0（表里只有护甲类型）。

const OVERLAY_ID := "legiontd"
const KING_ID := "lkng"
const MODELS_FILE := "legion_models.json"

const ATTACK_TYPES := {
	"普通": "normal", "穿刺": "pierce", "攻城": "siege", "魔法": "magic",
	"法术": "spells", "混乱": "chaos", "国王": "hero",
}
const ARMOR_TYPES := {
	"轻甲": "small", "中甲": "medium", "重甲": "large", "魂甲": "fort", "城甲": "normal",
	"英雄": "hero", "国王": "hero", "王甲": "hero", "神圣": "divine", "无甲": "none",
}

## 模板缺字段时的兜底（UnitData / UnitBalance / UnitWeapons / UnitUI）
const _DATA_DEFAULTS := {"race": "other", "movetp": "foot", "turnRate": 0.6, "targType": "ground", "death": 3.0}
const _BALANCE_DEFAULTS := {"spd": 270, "collision": 16, "sight": 1000, "nsight": 800}
const _WEAPON_DEFAULTS := {
	"acquire": 600, "weapTp1": "normal", "dmgpt1": 0.3, "backSw1": 0.3, "RngBuff1": 250,
	"targs1": "ground,structure,debris,item,ward",
}
const _UI_DEFAULTS := {"modelScale": 1.0, "scale": 1.0}


class Spec:
	extends RefCounted
	var id: String = ""
	var name: String = ""
	## unit / hire / wave / king
	var kind: String = ""
	var template: String = ""
	var gold: int = 0
	var wood: int = 0
	var food: int = 0
	var hp: int = 1
	var atk_min: int = 0
	var atk_max: int = 0
	var cooldown: float = 1.0
	var attack_range: float = 100.0
	## SLK 键（normal / pierce …）
	var attack_type: String = "normal"
	## SLK 键（small / medium …）
	var armor_type: String = "none"
	var regen: float = 0.0
	var upgrade: String = ""
	## 命令格图标（asset-converted 逻辑路径 .png）；空 = 文字按钮
	var icon: String = ""


class WaveRow:
	extends RefCounted
	var wave: int = 0
	var unit_id: String = ""
	var count: int = 0
	var interval: float = 8.0
	var force: int = 0


class KingUpgrade:
	extends RefCounted
	var wood: int = 80
	var income: int = 3
	var hp_delta: int = 80
	var atk_delta: int = 4
	var regen_delta: float = 1.0


var specs: Dictionary[String, Spec] = {}
## 一阶兵（units.txt 里 kind=unit 且不是别人的升级目标），按表序；「造当前兵」按钮用
var base_units: Array[String] = []
var waves: Array[WaveRow] = []
var king_upgrade: KingUpgrade = KingUpgrade.new()
## atk → { def → 倍率 }，形同 CombatDamageTable._TFT
var damage_table: Dictionary = {}
## 找不到模板的 id（窗口里是胶囊体）
var missing_templates: PackedStringArray = PackedStringArray()


static func wave_id(wave: int) -> String:
	return "w%03d" % wave


## 读 legion_data 与 <map_dir>/legion_models.json；不改 Wc3DefStore。
static func load_tables(map_dir: String) -> LegionUnitDefs:
	var defs := LegionUnitDefs.new()
	var models: Dictionary = RuntimeAssets.read_json_dict(map_dir.path_join(MODELS_FILE)).get("units", {})
	var upgrade_targets: Dictionary = {}
	var unit_rows := LegionTables.read_rows("units.txt")
	for row in unit_rows:
		upgrade_targets[str(row.get("upgrade", ""))] = true
	for row in unit_rows:
		if str(row.get("kind", "unit")) != "unit":
			continue
		var s := defs.add_spec_from_row(row, "unit", models)
		s.gold = int(row.get("gold", "0"))
		s.wood = int(row.get("wood", "0"))
		s.food = int(row.get("food", "0"))
		s.upgrade = str(row.get("upgrade", ""))
		if not upgrade_targets.has(s.id):
			defs.base_units.append(s.id)
	for row in LegionTables.read_rows("hires.txt"):
		var h := defs.add_spec_from_row(row, "hire", models)
		h.wood = int(row.get("wood", "0"))
	for row in LegionTables.read_rows("waves.txt"):
		var n := int(row.get("wave", "0"))
		if n <= 0:
			continue
		var wrow := row.duplicate()
		wrow["id"] = wave_id(n)
		wrow["name"] = "第%d波" % n
		wrow["atk_min"] = row.get("atk", "0")
		wrow["atk_max"] = row.get("atk", "0")
		defs.add_spec_from_row(wrow, "wave", models)
		var w := WaveRow.new()
		w.wave = n
		w.unit_id = wave_id(n)
		w.count = int(row.get("count", "0"))
		w.interval = float(row.get("interval", "8"))
		w.force = int(row.get("force", "0"))
		defs.waves.append(w)
	var king_rows := LegionTables.read_rows("king.txt")
	if not king_rows.is_empty():
		var krow := king_rows[0].duplicate()
		krow["id"] = KING_ID
		krow["name"] = "国王"
		var k := defs.add_spec_from_row(krow, "king", models)
		k.regen = float(krow.get("regen", "0"))
		var up := defs.king_upgrade
		up.wood = int(krow.get("wood", str(up.wood)))
		up.income = int(krow.get("income", str(up.income)))
		up.hp_delta = int(krow.get("hp_delta", str(up.hp_delta)))
		up.atk_delta = int(krow.get("atk_delta", str(up.atk_delta)))
		up.regen_delta = float(krow.get("regen_delta", str(up.regen_delta)))
	defs.damage_table = damage_table_from_rows(LegionTables.read_rows("armor.txt"))
	return defs


## armor.txt（攻击类型 × 护甲类型，百分比）→ SLK 键倍率表。
static func damage_table_from_rows(rows: Array[Dictionary]) -> Dictionary:
	var table: Dictionary = {}
	for row in rows:
		var atk := str(ATTACK_TYPES.get(str(row.get("atk", "")), ""))
		if atk.is_empty():
			continue
		var by_def: Dictionary = {}
		for col in row.keys():
			var def := str(ARMOR_TYPES.get(str(col), ""))
			if def.is_empty():
				continue
			by_def[def] = float(row[col]) / 100.0
		table[atk] = by_def
	return table


## 一行军团表 → Spec（登记到 specs）。列：id,name,hp,atk_min,atk_max,as,rng,at,df[,model_id]。
func add_spec_from_row(row: Dictionary, kind: String, models: Dictionary) -> Spec:
	var s := Spec.new()
	s.id = str(row.get("id", "")).strip_edges()
	s.name = str(row.get("name", s.id))
	s.kind = kind
	s.hp = maxi(int(row.get("hp", "1")), 1)
	s.atk_min = int(row.get("atk_min", "0"))
	s.atk_max = maxi(int(row.get("atk_max", "0")), s.atk_min)
	s.cooldown = maxf(float(row.get("as", "1.0")), 0.1)
	s.attack_range = maxf(float(row.get("rng", "100")), 16.0)
	s.attack_type = str(ATTACK_TYPES.get(str(row.get("at", "")), "normal"))
	s.armor_type = str(ARMOR_TYPES.get(str(row.get("df", "")), "none"))
	var m: Variant = models.get(s.id)
	if typeof(m) == TYPE_DICTIONARY:
		s.template = str((m as Dictionary).get("template", ""))
		s.icon = str((m as Dictionary).get("icon", ""))
	if s.template.is_empty():
		s.template = str(row.get("model_id", "")).strip_edges()
	specs[s.id] = s
	return s


func get_spec(id: String) -> Spec:
	return specs.get(id) as Spec


## 装入本局叠加行：先清旧叠加，再叠地图 slk，再逐个 Spec 克隆模板并覆盖数值。返回写入的 Spec 数。
func apply_to_store(map_dir: String) -> int:
	var store := _store()
	if store == null:
		AppLog.warn(AppLog.Layer.DATA, "LegionUnitDefs", "Wc3DefStore 不可用，军团单位没有属性")
		return 0
	var tables := PackedStringArray([
		UnitUiDef.TABLE_NAME, UnitDataDef.TABLE_NAME, UnitBalanceDef.TABLE_NAME, UnitWeaponsDef.TABLE_NAME,
	])
	store.clear_overlay(OVERLAY_ID)
	var from_map: Dictionary = store.apply_overlay_dir(OVERLAY_ID, map_dir.path_join("slk"), tables)
	missing_templates = PackedStringArray()
	for s in specs.values():
		var spec := s as Spec
		var tpl := spec.template
		if tpl.is_empty() and store.has_row(UnitUiDef.TABLE_NAME, spec.id):
			tpl = spec.id
		if tpl.is_empty() or not store.has_row(UnitUiDef.TABLE_NAME, tpl):
			missing_templates.append(spec.id)
		store.apply_overlay_records(OVERLAY_ID, UnitUiDef.TABLE_NAME, [_ui_record(store, spec, tpl)])
		store.apply_overlay_records(OVERLAY_ID, UnitDataDef.TABLE_NAME, [_data_record(store, spec, tpl)])
		store.apply_overlay_records(OVERLAY_ID, UnitBalanceDef.TABLE_NAME, [_balance_record(store, spec, tpl)])
		store.apply_overlay_records(OVERLAY_ID, UnitWeaponsDef.TABLE_NAME, [_weapon_record(store, spec, tpl)])
	AppLog.info(
		AppLog.Layer.DATA,
		"LegionUnitDefs",
		"叠加 %d 个军团单位；地图 slk %s；无模板 %d" % [specs.size(), str(from_map), missing_templates.size()]
	)
	return specs.size()


static func clear_store() -> void:
	var store := _store()
	if store != null:
		store.clear_overlay(OVERLAY_ID)


static func _store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")


static func _from_template(store: Node, table: String, tpl: String, defaults: Dictionary) -> Dictionary:
	var rec: Dictionary = defaults.duplicate(true)
	if not tpl.is_empty():
		rec.merge(store.get_record(table, tpl), true)
	return rec


func _ui_record(store: Node, s: Spec, tpl: String) -> Dictionary:
	var rec := _from_template(store, UnitUiDef.TABLE_NAME, tpl, _UI_DEFAULTS)
	rec[UnitUiDef.PRIMARY_KEY] = s.id
	rec["name"] = s.name
	if tpl.is_empty():
		rec["file"] = ""
	return rec


func _data_record(store: Node, s: Spec, tpl: String) -> Dictionary:
	var rec := _from_template(store, UnitDataDef.TABLE_NAME, tpl, _DATA_DEFAULTS)
	rec[UnitDataDef.PRIMARY_KEY] = s.id
	return rec


func _balance_record(store: Node, s: Spec, tpl: String) -> Dictionary:
	var rec := _from_template(store, UnitBalanceDef.TABLE_NAME, tpl, _BALANCE_DEFAULTS)
	rec[UnitBalanceDef.PRIMARY_KEY] = s.id
	rec["HP"] = s.hp
	rec["realHP"] = s.hp
	rec["goldcost"] = s.gold
	rec["lumbercost"] = s.wood
	rec["fused"] = s.food
	rec["fmade"] = 0
	rec["def"] = 0
	rec["realdef"] = 0
	rec["defType"] = s.armor_type
	rec["regenHP"] = s.regen
	rec["regenType"] = "always" if s.regen > 0.0 else "none"
	rec["isbldg"] = 0
	# 模板若是英雄，去掉主属性，免得按英雄算生命 / 显示英雄面板
	rec["Primary"] = "_"
	return rec


func _weapon_record(store: Node, s: Spec, tpl: String) -> Dictionary:
	var rec := _from_template(store, UnitWeaponsDef.TABLE_NAME, tpl, _WEAPON_DEFAULTS)
	rec[UnitWeaponsDef.PRIMARY_KEY] = s.id
	if s.atk_max <= 0:
		rec["weapsOn"] = 0
		return rec
	# 魔兽伤害 = dmgplus + dice × d(sides)；dice=1 时 [min, max] 反推 sides / dmgplus
	rec["weapsOn"] = 1
	rec["atkType1"] = s.attack_type
	rec["cool1"] = s.cooldown
	rec["rangeN1"] = s.attack_range
	rec["dice1"] = 1
	rec["sides1"] = s.atk_max - s.atk_min + 1
	rec["dmgplus1"] = s.atk_min - 1
	rec["mindmg1"] = s.atk_min
	rec["maxdmg1"] = s.atk_max
	rec["avgdmg1"] = (s.atk_min + s.atk_max) * 0.5
	rec["acquire"] = maxf(float(rec.get("acquire", 600)), s.attack_range)
	if str(rec.get("weapTp1", "")).strip_edges().is_empty() or str(rec.get("weapTp1", "")) == "_":
		rec["weapTp1"] = "normal"
	return rec
