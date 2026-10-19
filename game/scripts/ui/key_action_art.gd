class_name KeyActionArt
extends RefCounted
## The icon and display name of each bindable action: one lookup shared by the Key Config window (keyboard keys and tray)
## and the HUD quick slot, so both always show the same picture for an action.
##
## Icons: tier A v83 KeyConfig icons for jump (53 JUMP), Equip (0 EQUIPMENT), Item (1 ITEMS), Stat (2 ABILITY, the v83
## Stat window key), Skill (3 SKILL) and NPC Chat (54 NPC CHAT); the potions show Red / Blue Potion (Item.wz 2000000 /
## 2000003). A learned manual skill (Teleport, Dash) shows its own skill icon and name, given as a skill-key info
## `{action, name, icon}` (RunWorld.manual_skill_keys, tier C: a skill key follows the skill, #188).

const ART := "UI.wz/UIWindow.img/KeyConfig/"
## Action -> icon path (see the class doc).
const ICONS := {"jump": ART + "icon/53", "drink_hp": "Item.wz/Consume/0200.img/02000000/info/icon",
	"drink_mp": "Item.wz/Consume/0200.img/02000003/info/icon",
	"equip_window": ART + "icon/0", "item_window": ART + "icon/1", "stat_window": ART + "icon/2",
	"skill_window": ART + "icon/3", "npc_chat": ART + "icon/54"}
## Action -> tooltip name.
const NAMES := {"jump": "Jump", "drink_hp": "HP Potion", "drink_mp": "MP Potion",
	"equip_window": "Equip", "item_window": "Item", "stat_window": "Stat", "skill_window": "Skill",
	"npc_chat": "NPC Chat"}


## The WZ path of `action`'s icon: the learned skill's own icon when `skill_info` is that skill key's entry, else the
## fixed icon ("" for an unknown action).
static func icon_path(action: String, skill_info: Dictionary = {}) -> String:
	if not skill_info.is_empty():
		return String(skill_info.get("icon", ""))
	return String(ICONS.get(action, ""))


## The display name of `action` (the learned skill's own name for a skill key, the action id when unknown).
static func display_name(action: String, skill_info: Dictionary = {}) -> String:
	if not skill_info.is_empty():
		return String(skill_info.get("name", action))
	return String(NAMES.get(action, action))
