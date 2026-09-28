class_name LegionCommandCard
extends RefCounted

## 军团命令格（Logic）：12 格条目，形同 CommandCard.for_unit，由 GameDirector 交给 GameHud。
## 主卡：一阶兵建造（上两行）+ 强化国王生命；选中己方防守兵：出售。

const ACTION_BUILD_PREFIX := "legion_build:"
const ACTION_KING_HP := "legion_king_hp"
const ACTION_SELL := "legion_sell"
const ACTION_CANCEL := "legion_cancel"

const _BUILD_KEYS := [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_A, KEY_S, KEY_D, KEY_F]
const _BUILD_KEY_LABELS := ["Q", "W", "E", "R", "A", "S", "D", "F"]
const SLOT_KING_HP := 8
const SLOT_SELL := 11
const SLOT_CANCEL := 11


static func empty_card() -> Array[Dictionary]:
	var card: Array[Dictionary] = []
	card.resize(12)
	for i in range(12):
		card[i] = {}
	return card


## placing_id 非空时：该兵按钮高亮，右下角是取消。
static func main_card(defs: LegionUnitDefs, stock: PlayerStock, placing_id: String) -> Array[Dictionary]:
	var card := empty_card()
	var n := mini(defs.base_units.size(), _BUILD_KEYS.size())
	for i in range(n):
		var s := defs.get_spec(defs.base_units[i])
		if s == null:
			continue
		var affordable := stock != null and stock.gold >= s.gold and stock.lumber >= s.wood and stock.can_afford_food(s.food)
		card[i] = _entry(
			ACTION_BUILD_PREFIX + s.id,
			s.name,
			"%s（|cffffcc00%s|r）\n%d 金 · %d 人口\n生命 %d · 攻击 %d-%d · 射程 %d"
			% [s.name, _BUILD_KEY_LABELS[i], s.gold, s.food, s.hp, s.atk_min, s.atk_max, int(s.attack_range)],
			s.icon,
			_BUILD_KEYS[i],
			_BUILD_KEY_LABELS[i],
			i,
			affordable,
			placing_id == s.id,
		)
	var up := defs.king_upgrade
	card[SLOT_KING_HP] = _entry(
		ACTION_KING_HP,
		"强化国王",
		"强化国王生命（|cffffcc00K|r）\n%d 木材 · 收入 +%d\n国王生命上限 +%d" % [up.wood, up.income, up.hp_delta],
		"ReplaceableTextures/CommandButtons/BTNStrengthOfTheWild.png",
		KEY_K,
		"K",
		SLOT_KING_HP,
		stock != null and stock.lumber >= up.wood,
		false,
	)
	if not placing_id.is_empty():
		card[SLOT_CANCEL] = _entry(
			ACTION_CANCEL,
			"取消",
			"取消放置（|cffffcc00ESC|r）",
			"ReplaceableTextures/CommandButtons/BTNCancel.png",
			KEY_ESCAPE,
			"ESC",
			SLOT_CANCEL,
			true,
			false,
		)
	return card


static func defender_card(unit_name: String, refund: int) -> Array[Dictionary]:
	var card := empty_card()
	card[SLOT_SELL] = _entry(
		ACTION_SELL,
		"出售",
		"出售 %s（|cffffcc00X|r）\n返还 %d 金" % [unit_name, refund],
		"ReplaceableTextures/CommandButtons/BTNReturnGoods.png",
		KEY_X,
		"X",
		SLOT_SELL,
		true,
		false,
	)
	return card


static func _entry(
	id: String, text: String, tooltip: String, icon: String, hotkey: int, hotkey_label: String,
	slot: int, enabled: bool, executing: bool
) -> Dictionary:
	# 图标没转出来时退成文字按钮，免得一格空白
	if not icon.is_empty() and not RuntimeAssets.file_exists(RuntimeAssets.converted_path(icon)):
		icon = ""
	var disabled_icon := ""
	if not icon.is_empty():
		disabled_icon = icon.replace("CommandButtons/BTN", "CommandButtonsDisabled/DISBTN")
	return {
		"id": id,
		"text": text if icon.is_empty() else "",
		"tooltip": tooltip,
		"hotkey": hotkey,
		"hotkey_label": hotkey_label,
		"icon": icon,
		"icon_disabled": disabled_icon,
		"executing": executing,
		"enabled": enabled,
		"slot": slot,
	}
