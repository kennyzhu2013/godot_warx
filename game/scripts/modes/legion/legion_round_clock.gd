class_name LegionRoundClock
extends RefCounted

## 回合时钟（Logic）：回合的唯一权威。准备 → 战斗 → 结算 → 下一回合准备；到测试局波数或国王死亡时结束。
## 结算是瞬时的：模式在 phase_changed(SETTLE) 里发收入、复位防守兵，随后时钟自己进下一回合准备。
## 自定规格（第 5 节常量表）：准备 15 秒，战斗超时 90 秒，测试局 10 波。

signal phase_changed(phase: int, round_no: int)

enum Phase { PREP, BATTLE, SETTLE, OVER }

const PREP_SEC := 15.0
const BATTLE_TIMEOUT_SEC := 90.0
const TEST_WAVES := 10

var phase: int = Phase.PREP
## 当前回合（= 本回合要打的波次），从 1 起
var round_no: int = 1
var last_round: int = TEST_WAVES
## 本阶段剩余秒数；战斗阶段是离超时还剩多少
var time_left: float = PREP_SEC
var paused: bool = false
## 战斗是否因超时结束（结算时读）
var timed_out: bool = false
## OVER 的原因
var over_reason: String = ""


func start(first_round: int = 1) -> void:
	round_no = first_round
	_enter(Phase.PREP)


## battle_done：本波系统怪全部刷完并死亡。
func tick(delta: float, battle_done: bool) -> void:
	if phase == Phase.OVER:
		return
	if phase == Phase.BATTLE and battle_done:
		timed_out = false
		_settle()
		return
	if paused:
		return
	time_left -= delta
	if time_left > 0.0:
		return
	match phase:
		Phase.PREP:
			_enter(Phase.BATTLE)
		Phase.BATTLE:
			timed_out = true
			_settle()


## GM：跳过准备立即开战。
func force_battle() -> void:
	if phase == Phase.PREP:
		_enter(Phase.BATTLE)


## GM：立即结算（当作超时）。
func force_settle() -> void:
	if phase == Phase.BATTLE:
		timed_out = true
		_settle()


## GM：跳到第 n 波的准备阶段。
func jump_to(n: int) -> void:
	if phase == Phase.OVER:
		return
	round_no = clampi(n, 1, last_round)
	_enter(Phase.PREP)


func end_match(reason: String) -> void:
	if phase == Phase.OVER:
		return
	over_reason = reason
	_enter(Phase.OVER)


func phase_name() -> String:
	match phase:
		Phase.PREP:
			return "准备"
		Phase.BATTLE:
			return "战斗"
		Phase.SETTLE:
			return "结算"
	return "结束"


func _settle() -> void:
	_enter(Phase.SETTLE)
	if phase == Phase.OVER:
		return
	if round_no >= last_round:
		end_match("打完 %d 波" % last_round)
		return
	round_no += 1
	_enter(Phase.PREP)


func _enter(p: int) -> void:
	phase = p
	match p:
		Phase.PREP:
			time_left = PREP_SEC
		Phase.BATTLE:
			time_left = BATTLE_TIMEOUT_SEC
			timed_out = false
		_:
			time_left = 0.0
	phase_changed.emit(phase, round_no)
