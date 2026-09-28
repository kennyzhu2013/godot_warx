class_name LegionKing
extends RefCounted

## 阵营国王（Logic）：每边一座，归本阵营电脑席。强化加在国王单位上，花费与收入走购买者自己的库存。

var _kings: Dictionary[String, Node3D] = {}
## 阵营 → 已强化生命次数（GM / 底栏显示用）
var _hp_levels: Dictionary[String, int] = {}


func set_king(side: String, unit: Node3D) -> void:
	_kings[side] = unit
	_hp_levels[side] = 0


func king_of(side: String) -> Node3D:
	var u: Variant = _kings.get(side)
	return u as Node3D if u != null and is_instance_valid(u) else null


func hp_level(side: String) -> int:
	return int(_hp_levels.get(side, 0))


func all_kings() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for side in _kings.keys():
		var u := king_of(side)
		if u != null:
			out.append(u)
	return out


## 强化国王生命：扣木、加收入、加国王生命上限与当前生命。成功返回空串，否则返回原因。
func try_upgrade_hp(
	side: String, stock: PlayerStock, economy: LegionEconomy, buyer_seat: int, upgrade: LegionUnitDefs.KingUpgrade
) -> String:
	var king := king_of(side)
	if king == null or not CombatQuery.is_alive_in_world(king):
		return "国王不在场"
	if stock == null or not stock.try_spend(0, upgrade.wood):
		return "木材不足（需要 %d）" % upgrade.wood
	UnitLife.raise_max_life(king, float(upgrade.hp_delta))
	economy.add_income(buyer_seat, upgrade.income)
	_hp_levels[side] = hp_level(side) + 1
	return ""
