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


## 选中变化时先通知模式（在 command_card 之前）。
func selection_changed(_primary: Node3D, _selected: Array) -> void:
	pass


## 模式自己的命令格（12 格，形同 CommandCard.for_unit）；返回空数组表示用 Director 默认命令格。
func command_card(_primary: Node3D, _selected: Array) -> Array:
	return []


## 命令格按钮 / 热键；返回 true 表示模式已处理，Director 不再分派。
func handle_command_action(_action_id: String) -> bool:
	return false


## 右键智能指令是否被模式拦下（例如军团防守兵不能被玩家移动）。
func blocks_unit_orders(_selected: Array) -> bool:
	return false
