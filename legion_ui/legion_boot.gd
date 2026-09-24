extends Control

## 军团入口：打开继承自 game_main 的军团场景。资源、命令和底栏都走 GameHud，不读模拟器。

func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred("res://game/scenes/legion_main.tscn")
