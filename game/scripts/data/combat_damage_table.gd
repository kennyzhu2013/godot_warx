class_name CombatDamageTable
extends RefCounted

## WC3 TFT 攻防倍率表 + 护甲减伤（Logic · 纯数据）。
## SLK defType: small/medium/large/fort/hero/divine/none
## SLK atkType: normal/pierce/siege/magic/chaos/hero/spells

## atk → { def → multiplier }
const _TFT: Dictionary = {
	"normal": {"small": 1.0, "medium": 1.5, "large": 1.0, "fort": 0.7, "hero": 1.0, "none": 1.0, "divine": 0.05},
	"pierce": {"small": 2.0, "medium": 0.75, "large": 1.0, "fort": 0.35, "hero": 0.5, "none": 1.5, "divine": 0.05},
	"siege": {"small": 1.0, "medium": 0.5, "large": 1.0, "fort": 1.5, "hero": 0.5, "none": 1.5, "divine": 0.05},
	"magic": {"small": 1.25, "medium": 0.75, "large": 2.0, "fort": 0.35, "hero": 0.5, "none": 1.0, "divine": 0.05},
	"chaos": {"small": 1.0, "medium": 1.0, "large": 1.0, "fort": 1.0, "hero": 1.0, "none": 1.0, "divine": 1.0},
	"spells": {"small": 1.0, "medium": 1.0, "large": 1.0, "fort": 1.0, "hero": 0.7, "none": 1.0, "divine": 0.05},
	"hero": {"small": 1.0, "medium": 1.0, "large": 1.0, "fort": 0.5, "hero": 1.0, "none": 1.0, "divine": 0.05},
}

## 本局倍率表（同 _TFT 形状）；空 = 用 TFT。对局模式开局装入、结束清掉。
static var _match_table: Dictionary = {}


static func set_match_table(table: Dictionary) -> void:
	_match_table = table.duplicate(true)


static func clear_match_table() -> void:
	_match_table = {}


static func has_match_table() -> bool:
	return not _match_table.is_empty()


## 归一化攻击类型
static func normalize_atk(atk: String) -> String:
	var a := atk.strip_edges().to_lower()
	if a == "piercing":
		return "pierce"
	if a.is_empty():
		return "normal"
	return a

## 归一化护甲类型
static func normalize_def(def: String) -> String:
	var d := def.strip_edges().to_lower()
	# 别名：Light/Heavy/Unarmored/Fortified（文档名）→ SLK
	match d:
		"light":
			return "small"
		"heavy":
			return "large"
		"unarmored", "unarmoured":
			return "none"
		"fortified":
			return "fort"
		"":
			return "none"
		_:
			return d

## 攻防倍率
static func multiplier(atk_type: String, def_type: String) -> float:
	var atk := normalize_atk(atk_type)
	var def := normalize_def(def_type)
	var table: Dictionary = _match_table if not _match_table.is_empty() else _TFT
	var row: Variant = table.get(atk, table.get("normal", {}))
	if typeof(row) != TYPE_DICTIONARY:
		return 1.0
	return float((row as Dictionary).get(def, 1.0))

## WC3 护甲减伤：factor = 1 - 0.06*armor / (1 + 0.06*|armor|)
static func armor_factor(armor: float) -> float:
	var a := armor
	var denom := 1.0 + 0.06 * absf(a)
	if denom <= 0.0:
		return 1.0
	return 1.0 - (0.06 * a) / denom

## 护甲减伤
static func apply_armor(raw_after_type: float, armor: float) -> float:
	return maxf(0.0, raw_after_type * armor_factor(armor))
