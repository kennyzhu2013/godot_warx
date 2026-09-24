extends Control

## 军团入口只打开 godot_war3 的对战场景。资源、命令和底栏都走 GameHud，不读模拟器。

func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred("res://game/scenes/game_main.tscn")
