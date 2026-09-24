class_name MatchMode
extends Node

## 对局模式基类（Game Logic）。场景里 GameDirector.match_mode 指向子类节点时，
## 由模式代替 Melee 开局创建 session；未绑定或 create_session 返回 null 时 Director 仍走 Melee。


## 地图加载后、PathQuery / CommandRouter 搭建前调用；返回本局 session。
func create_session(_map_dir: String, _local_player: int) -> GameSession:
	return null


## session_ready 之后调用；此时寻路、命令、战斗服务均已就绪。
func begin(_session: GameSession) -> void:
	pass
