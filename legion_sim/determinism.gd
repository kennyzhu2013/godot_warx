class_name DetRng
extends RefCounted

var state: int = 1


func seed_value(s: int) -> void:
	state = s if s != 0 else 1


func next_int() -> int:
	state = int((state * 1103515245 + 12345) & 0x7fffffff)
	return state
