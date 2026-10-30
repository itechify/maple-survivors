class_name HubTestKit
extends RefCounted
## The tool-only `--hub` flag: open the real Free Market (910000000) with a test character, so the spec #33 scroll shops
## can be tried by hand without playing a round:
##
##   bash scripts/run.sh -- --hub [--job=<id>] [--character=<absolute CharacterSnapshot JSON>] [--mesos=N]
##
## Nothing here touches the player's real save (user://save.json): SceneFlow.start_hub puts the character into a slot of
## a throwaway save file (SAVE_PATH, recreated on every launch) and continues it, so the hub behaves exactly as in real
## play. Pure static helpers: flag parsing, character loading (format 1 migrates), the test kit and the throwaway save.
##
## Class tool kits come from jobs/<line>.json hub_kit through JobTree.lineage_value.
## Jobs without a kit use the configured default job’s kit.

## The throwaway save (tool-only name, deleted and recreated by every `--hub` launch).
const SAVE_PATH := "user://tool_hub_save.json"
## Mesos the kit gives (`--mesos=N` overrides).
const DEFAULT_MESOS := 500000 # tier C: ours (owner brief)
## Scrolls per stack in the kit.
const SCROLL_COUNT := 10 # tier C: ours


## Class-owned tool configuration, resolved through the same job lineage as other job data.
static func _kit(job: int) -> Dictionary:
	var jobs := DataRepo.jobs(DataRepo.load_all())
	var kit: Dictionary = jobs.lineage_value(job, "hub_kit", {})
	return kit if not kit.is_empty() else jobs.lineage_value(jobs.default_job(), "hub_kit", {})


## The default job’s fixture when the tool names no character.
static func default_character() -> String:
	return String(_kit(-1).get("fixture", ""))


## Diagnostic weapon when a round produced no equipment drop.
static func fallback_item(job: int) -> int:
	return int(_kit(job).get("fallback_item", 0))


## Name of the throwaway character.
const CHARACTER_NAME := "HubTester"


## {} unless the args hold `--hub`; else {"character": res:// or absolute JSON path, "mesos": int >= 0}, plus "job" (the id of
## `--job=<id>`, -1 when it is not a whole number) when the flag is given. Without `--character` the character is the fixture
## of `--job` (hub_kit.fixture), else the F/P one.
static func parse_args(list: PackedStringArray) -> Dictionary:
	var flags := SceneFlow.parse_flags(list)
	if not flags.has("hub") or String(flags.hub) == "0":
		return {}
	var out := {}
	var job := -2
	if flags.has("job"):
		job = JobTree.parse_job(String(flags.job))
		out["job"] = job
	var path := String(flags.get("character", ""))
	var mesos := DEFAULT_MESOS
	if flags.has("mesos") and String(flags.mesos).is_valid_int():
		mesos = maxi(0, int(flags.mesos))
	out["character"] = path if path != "" and path != "1" else String(_kit(job).get("fixture", ""))
	out["mesos"] = mesos
	return out


## Why a `--hub --job=<id>` request cannot open ("" when it can): the job is not a whole playable job id, or the character
## (`character`, format 3) is of another job.
static func job_error(request: Dictionary, character: Dictionary, jobs: JobTree) -> String:
	if not request.has("job"):
		return ""
	var job := int(request.job)
	if job < 0:
		return "--job is not a job id"
	var error := jobs.job_error(job)
	if error != "":
		return error
	if int(character.get("job_id", -1)) != job:
		return "--job=%d does not match the character's job %d" % [job, int(character.get("job_id", -1))]
	return ""


## The job’s configured scroll stacks, or the default job’s kit.
static func kit_scrolls(job: int) -> Array:
	return (_kit(job).get("scrolls", []) as Array).map(func(id: Variant) -> int: return int(id))


## The job’s configured spare equipment, or the default job’s kit.
static func kit_equipment(job: int) -> Array:
	return (_kit(job).get("equipment", []) as Array).map(func(id: Variant) -> int: return int(id))


## {"character": format-3 CharacterSnapshot (the "_doc" note dropped; formats 1 and 2 migrated), "error": ""} from a JSON file,
## or {"character": {}, "error": message}. `img_loader` (path -> img root) gives migrated items their stats.
static func load_character(path: String, img_loader: Callable) -> Dictionary:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(path, errors)
	if not errors.is_empty():
		return {"character": {}, "error": "; ".join(errors)}
	character.erase("_doc")
	return {"character": SceneFlow.migrated_character(character, img_loader), "error": ""}


## A copy of the format-3 `character` with the test kit: `mesos`, every progression region cleared (so map select shows them all open), the
## kit_scrolls stacks (SCROLL_COUNT each, on top of what it holds, within the Use tab) and the kit_equipment items created
## from `img_loader` info, of the character's job (kit_scrolls, kit_equipment).
static func apply(character: Dictionary, mesos: int, img_loader: Callable) -> Dictionary:
	var out := character.duplicate(true)
	out.mesos = mesos
	var cleared: Array = out.get("cleared_regions", []).duplicate()
	for key: Variant in SceneFlow.progression():
		if key not in cleared:
			cleared.append(key)
	cleared.sort()
	out.cleared_regions = cleared
	out.erase("tiers_unlocked")
	var limit := Shop.use_stack_limit()
	var job := int(out.get("job_id", 0))
	for id: int in kit_scrolls(job):
		Scrolls.add(out.scrolls, id, SCROLL_COUNT, 0, limit)
	var spare := kit_equipment(job)
	var infos := DataRepo.equipment_info(PackedInt32Array(spare), img_loader)
	for id: int in spare:
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
