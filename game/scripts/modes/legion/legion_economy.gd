class_name LegionEconomy
extends RefCounted

## 各席位收入（Logic）。收入只增不减，结算时发放（阶段 3）。PlayerStock 没有收入字段，放这里。
## 自定规格：开局收入 5，策划案没有明文。

const START_INCOME := 5

var _income: Dictionary[int, int] = {}


func income_of(seat: int) -> int:
	return int(_income.get(seat, START_INCOME))


func add_income(seat: int, amount: int) -> void:
	_income[seat] = income_of(seat) + maxi(amount, 0)
