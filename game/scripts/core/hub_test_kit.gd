class_name HubTestKit
extends RefCounted
## The tool-only `--hub` flag: open the real Free Market (910000000) with a test character, so the spec #33 scroll shops
## can be tried by hand without playing a round:
##
##   bash scripts/run.sh -- --hub [--character=<absolute CharacterSnapshot JSON>] [--mesos=N]
##
## Nothing here touches the player's real save (user://save.json): SceneFlow.start_hub puts the character into a slot of
## a throwaway save file (SAVE_PATH, recreated on every launch) and continues it, so the hub behaves exactly as in real
## play. Pure static helpers: flag parsing, character loading (format 1 migrates), the test kit and the throwaway save.
##
## The test kit (all of it is the constants below): mesos, a stack of every rate of the scroll families the F/P
## fixture's gear and spare equipment take, and a few spare equipment items with their plain WZ stats.

## The throwaway save (tool-only name, deleted and recreated by every `--hub` launch).
const SAVE_PATH := "user://tool_hub_save.json"
## The character used when `--character` is not given: the gear of a real F/P bot character (format 3, job 212).
## Tool-only fixture; tests are excluded from exported builds.
const DEFAULT_CHARACTER := "res://tests/fixtures/characters/fp_arch_mage.json"
## Mesos the kit gives (`--mesos=N` overrides).
const DEFAULT_MESOS := 500000 # tier C: ours (owner brief)
## Scrolls per stack in the kit.
const SCROLL_COUNT := 10 # tier C: ours
## The kit's scroll stacks, every rate of each family (scrolls.json ids: 100%, 60%, 10%, dark 70%, dark 30%): wand
## Magic Att. (the worn wand), hat INT, top DEF (the worn top; v83 has no INT scroll for tops) and gloves Magic Att.
## 20 stacks, inside the Use tab's 24 slots for scrolls.
const KIT_SCROLLS := [ # tier C: ours
	2043700, 2043701, 2043702, 2043704, 2043705,
	2040024, 2040025, 2040026, 2040012, 2040013,
	2040400, 2040401, 2040402, 2040404, 2040405,
	2040818, 2040817, 2040816, 2040814, 2040815,
]
## Spare equipment put in the inventory to sell and wear: a hat, a staff, gloves and a top (plain WZ stats).
const KIT_EQUIPMENT := [1002001, 1382001, 1082002, 1040004]
## Name of the throwaway character.
const CHARACTER_NAME := "HubTester"


## {} unless the args hold `--hub`; else {"character": res:// or absolute JSON path, "mesos": int >= 0}.
static func parse_args(list: PackedStringArray) -> Dictionary:
	var flags := SceneFlow.parse_flags(list)
	if not flags.has("hub") or String(flags.hub) == "0":
		return {}
	var path := String(flags.get("character", ""))
	var mesos := DEFAULT_MESOS
	if flags.has("mesos") and String(flags.mesos).is_valid_int():
		mesos = maxi(0, int(flags.mesos))
	return {"character": path if path != "" and path != "1" else DEFAULT_CHARACTER, "mesos": mesos}


## {"character": format-3 CharacterSnapshot (the "_doc" note dropped; formats 1 and 2 migrated), "error": ""} from a JSON file,
## or {"character": {}, "error": message}. `img_loader` (path -> img root) gives migrated items their stats.
static func load_character(path: String, img_loader: Callable) -> Dictionary:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(path, errors)
	if not errors.is_empty():
		return {"character": {}, "error": "; ".join(errors)}
	character.erase("_doc")
	return {"character": SceneFlow.migrated_character(character, img_loader), "error": ""}


## A copy of the format-3 `character` with the test kit: `mesos`, every tier unlocked (so map select shows them all), the
## KIT_SCROLLS stacks (SCROLL_COUNT each, on top of what it holds, within the Use tab) and the KIT_EQUIPMENT items created
## from `img_loader` info.
static func apply(character: Dictionary, mesos: int, img_loader: Callable) -> Dictionary:
	var out := character.duplicate(true)
	out.mesos = mesos
	out.tiers_unlocked = maxi(int(out.get("tiers_unlocked", 1)), SceneFlow.tiers().size())
	var limit := Shop.use_stack_limit()
	for id: int in KIT_SCROLLS:
		Scrolls.add(out.scrolls, id, SCROLL_COUNT, 0, limit)
	var infos := DataRepo.equipment_info(PackedInt32Array(KIT_EQUIPMENT), img_loader)
	for id: int in KIT_EQUIPMENT:
		out.equipment.inventory.append(Equipment.create(id, infos.get(id, {})))
	return out


## A save over `path` with no slots, bests or history: any earlier file there (and its .bak / .tmp) is deleted first.
static func fresh_save(path: String = SAVE_PATH) -> SaveData:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	return SaveData.new(path)


## Where `--hub` puts the character on the Free Market floor (x): midway between the second and third scroll NPC of
## `shops` (shops.json; Barun and Tulcus), so every shop is a short walk away. tier C: ours.
static func spawn_x(shops: Dictionary) -> float:
	var npcs: Array = shops.get("npcs", [])
	if npcs.is_empty():
		return 0.0
	if npcs.size() < 3:
		return float(npcs[0].x)
	return (float(npcs[1].x) + float(npcs[2].x)) / 2.0


## One console line when NPC Chat has no key (`events`: InputMap.action_get_events("npc_chat")), else "".
static func npc_chat_hint(events: Array) -> String:
	if not events.is_empty():
		return ""
	return "--hub: NPC Chat has no key (Space is bound to another action in your settings): double-click an NPC or rebind NPC Chat in Key Config."
