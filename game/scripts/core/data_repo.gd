class_name DataRepo
extends RefCounted
## Loads the survivor design data (`game/data/survivor/*.json`) and the canonical facts that are not in WZ
## (`game/data/canonical/*.json`) into the `data` Dictionary of a RunWorld setup (docs/ARCHITECTURE.md 4.4.1, 4.4.4),
## and assembles a whole setup from an img loader. Presentation/core code: it reads files; the sim never does.
## Skills, upgrades, equipment drops, scrolls and shops are a base file plus per-job-line fragments
## (`survivor/<name>/<line>.json`) merged by `load_split` (SPLIT, lines(); docs/ARCHITECTURE.md 4.4.4).
##
##   var data := DataRepo.load_all()
##   var setup := DataRepo.build_setup(data, "henesys", 12345, Vector2(800, 600),
##       func(p: String) -> Dictionary: return Assets.img(p).root if Assets.img(p) != null else {},
##       func(id: int) -> Dictionary: return Assets.mob_root(id))

const DATA_ROOT := "res://data"
## Legacy saved/tool stage keys; unknown keys pass through for synthetic stages and future regions.
const STAGE_ALIASES := {"henesys_hg1": "henesys", "tree_that_grew_1": "ellinia", "dark_cave": "sleepywood"}


## Canonical region key for saved stages and tool flags.
static func canonical_stage_key(key: String) -> String:
	return STAGE_ALIASES.get(key, key)


## setup.data key -> file under DATA_ROOT.
const FILES := {
	"skills": "survivor/skills.json",
	"upgrades": "survivor/upgrades.json",
	"stages": "survivor/stages.json",
	"balance": "survivor/balance.json",
	"mobs": "survivor/mobs.json",
	"equipment_drops": "survivor/equipment_drops.json",
	"jobs_survivor": "survivor/jobs.json",
	"scrolls": "survivor/scrolls.json",
	"shops": "survivor/shops.json",
	"jobs": "canonical/jobs.json",
	"exp_table": "canonical/exp_table.json",
	"cash_items": "survivor/cash_items.json",
	"ammo": "survivor/ammo.json",
	"level_curve": "survivor/level_curve.json",
}
## Adventurer lines retain their historical merge order; class lines retain append-only registration order.
const ADVENTURER_LINES: PackedStringArray = ["common", "beginner", "warrior", "magician", "bowman", "thief", "pirate"]


## Append each shipped class here; existing entries never move (tier C: deterministic fragment order).
const CLASS_LINES: PackedStringArray = ["hero", "il_arch_mage", "bowmaster", "bishop", "paladin", "dark_knight", "buccaneer"]


## All present fragments: fixed Adventurers, registered classes, then unregistered names sorted for diagnostics.
static func lines(root: String = DATA_ROOT) -> PackedStringArray:
	var classes := PackedStringArray()
	for key: String in SPLIT:
		var dir := DirAccess.open(root.path_join(String(FILES[key]).trim_suffix(".json")))
		if dir == null:
			continue
		for file in dir.get_files():
			var line := file.trim_suffix(".json")
			if file.ends_with(".json") and line not in ADVENTURER_LINES and line not in classes:
				classes.append(line)
	classes.sort()
	var out := ADVENTURER_LINES.duplicate()
	for line in CLASS_LINES:
		if line in classes:
			out.append(line)
			classes.remove_at(classes.find(line))
	out.append_array(classes)
	return out


## setup.data key -> how the entries of its line fragments (survivor/<name>/<line>.json) merge into the base file
## (survivor/<name>.json): `entries` is the key the fragments fill, `merge` the rule (docs/ARCHITECTURE.md 4.4.4).
##   keys:      Dictionary, entry keys concatenated (skills)
##   ids:       Array of Dictionaries with a unique `id`, concatenated in line order (upgrade cards)
##   sorted:    Array of unique numbers, concatenated then sorted ascending (equipment drop ids)
##   values:    Array of unique values, concatenated in line order (shop weapon slots)
##   families:  Dictionary slot -> Dictionary family -> rates, merged per slot (scrolls)
const SPLIT := {
	"jobs_survivor": {"entries": "jobs", "merge": "keys"},
	"skills": {"entries": "skills", "merge": "keys"},
	"upgrades": {"entries": "cards", "merge": "ids"},
	"equipment_drops": {"entries": "items", "merge": "sorted"},
	"scrolls": {"entries": "families", "merge": "families"},
	"shops": {"entries": "weapon_slots", "merge": "values"},
}
const PHYSICS_IMG := "Map.wz/Physics.img"
const MOB_SKILL_IMG := "Skill.wz/MobSkill.img"
const SCROLL_IMG := "Item.wz/Consume/0204.img"


## A test seam (spec #296, H9 #305): a JSON-shaped patch deep-merged (Dictionaries key by key, anything else replaces)
## into what `load_all(DATA_ROOT)` returns while it is non-empty, so a test can mirror the shipped data with one job made
## playable (`{"jobs_survivor": {"jobs": {"112": {"playable": true}}}}`) and drive the creation page, SceneFlow and the
## tools through their own `DataRepo.load_all()` calls. Always empty in the game; a test that sets it clears it again.
static var patch := {}


## Every data file parsed, keyed as in setup.data. A missing or malformed file gives {} for its key and is listed in
## `errors` (when given). The keys in SPLIT are the base file plus the merged line fragments (load_split).
static func load_all(root: String = DATA_ROOT, errors: PackedStringArray = PackedStringArray()) -> Dictionary:
	var out := _load_all(root, errors)
	if root == DATA_ROOT and not patch.is_empty():
		merge_patch(out, patch)
	return out


## Deep-merges dictionaries; optional equal-length array patches merge entries and retain null slots (balance tools).
static func merge_patch(into: Dictionary, with: Dictionary, merge_arrays: bool = false) -> void:
	for k: Variant in with:
		if with[k] is Dictionary and into.get(k) is Dictionary:
			merge_patch(into[k], with[k], merge_arrays)
		elif merge_arrays and with[k] is Array and into.get(k) is Array and with[k].size() == into[k].size():
			for i in with[k].size():
				if with[k][i] is Dictionary and into[k][i] is Dictionary:
					merge_patch(into[k][i], with[k][i], true)
				elif with[k][i] != null:
					into[k][i] = with[k][i]
		else:
			into[k] = with[k].duplicate(true) if with[k] is Dictionary or with[k] is Array else with[k]


static func _load_all(root: String, errors: PackedStringArray) -> Dictionary:
	var out := {}
	for key: String in FILES:
		if SPLIT.has(key):
			out[key] = load_split(key, root, errors)
			continue
		var path := root.path_join(FILES[key])
		var v: Variant = load_json(path)
		if v is Dictionary:
			out[key] = v
		else:
			out[key] = {}
			errors.append("cannot read %s" % path)
	errors.append_array(skill_template_errors(out.get("skills", {})))
	# Class-owned balance rows enter through this single reader, after the shared defaults.
	for line in lines(root):
		var fragment: Variant = load_json(fragment_path("jobs_survivor", line, root))
		if fragment is Dictionary and fragment.get("balance") is Dictionary:
			merge_patch(out.balance, fragment.balance)
	errors.append_array(stage_label_errors(out.get("stages", {})))
	errors.append_array(stage_map_errors(out.get("stages", {})))
	if not out.get("level_curve", {}).is_empty(): # a missing file is already listed above
		errors.append_array(LevelScale.curve_errors(out.level_curve))
	errors.append_array(LevelScale.stage_errors(out.get("stages", {})))
	errors.append_array(Ammo.schedule_errors(out.get("ammo", {})))
	return out


## The errors of the skill templates (`extends`, spec #319 M19, SkillTemplate) in the merged skills data. The data is
## left raw: SkillBook resolves it.
static func skill_template_errors(skills_file: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var skills: Variant = skills_file.get("skills")
	if skills is Dictionary:
		SkillTemplate.resolve(skills, errors)
	return errors


## The data of a SPLIT key: its base file (`_doc` and the job-neutral config) with the entries of every existing line
## fragment `<name>/<line>.json` merged in lines(root) order, per SPLIT's rule. A duplicate entry across files is listed in
## `errors` and the first value kept; an unreadable fragment, or a key in it that is neither `_`-prefixed nor the
## entries key, is listed too. `_`-prefixed keys of a fragment (its `_doc`, notes) are never merged. A missing or
## malformed base gives {} (and no fragments are read). The entries key always exists in the result.
static func load_split(key: String, root: String = DATA_ROOT, errors: PackedStringArray = PackedStringArray()) -> Dictionary:
	var base_path := root.path_join(FILES[key])
	var base: Variant = load_json(base_path)
	if not base is Dictionary:
		errors.append("cannot read %s" % base_path)
		return {}
	var spec: Dictionary = SPLIT[key]
	var entries_key: String = spec.entries
	var out: Dictionary = base
	var merge: String = spec.merge
	if not out.has(entries_key):
		out[entries_key] = {} if merge in ["keys", "families"] else []
	for line in lines(root):
		var path := fragment_path(key, line, root)
		if not FileAccess.file_exists(path):
			continue
		var frag: Variant = load_json(path)
		if not frag is Dictionary:
			errors.append("cannot read %s" % path)
			continue
		_merge_fragment(out, frag, spec, path, errors)
	if merge == "sorted":
		(out[entries_key] as Array).sort()
	return out


## Path of one line's fragment of a SPLIT key: `res://data/survivor/skills/magician.json` for ("skills", "magician").
static func fragment_path(key: String, line: String, root: String = DATA_ROOT) -> String:
	return root.path_join(String(FILES[key]).trim_suffix(".json")).path_join(line + ".json")


## Non-JSON files in fragment directories; every JSON name is a discovered line. Tools/tests only.
static func unknown_line_files(root: String = DATA_ROOT) -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in SPLIT:
		var dir_path := root.path_join(String(FILES[key]).trim_suffix(".json"))
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			if not file.ends_with(".json"):
				out.append(String(FILES[key]).trim_suffix(".json").path_join(file))
	out.sort()
	return out


static func _merge_fragment(out: Dictionary, frag: Dictionary, spec: Dictionary, path: String,
		errors: PackedStringArray) -> void:
	var entries_key: String = spec.entries
	for k: Variant in frag:
		var name := String(k)
		if name.begins_with("_") or (name == "balance" and entries_key == "jobs"):
			continue
		if name != entries_key:
			errors.append("%s: unexpected key '%s' (only '%s' and _-prefixed notes)" % [path, name, entries_key])
			continue
		var into: Variant = out[entries_key]
		var from: Variant = frag[k]
		match String(spec.merge):
			"keys":
				if not (from is Dictionary and into is Dictionary):
					errors.append("%s: '%s' must be an object" % [path, entries_key])
				else:
					_merge_keys(into, from, entries_key, path, errors)
			"families":
				if not (from is Dictionary and into is Dictionary):
					errors.append("%s: '%s' must be an object" % [path, entries_key])
				else:
					_merge_families(into, from, path, errors)
			_:
				if not (from is Array and into is Array):
					errors.append("%s: '%s' must be an array" % [path, entries_key])
				else:
					_merge_list(into, from, String(spec.merge) == "ids", entries_key, path, errors)


static func _merge_keys(into: Dictionary, from: Dictionary, label: String, path: String, errors: PackedStringArray) -> void:
	for k: Variant in from:
		if String(k).begins_with("_"):
			continue
		if into.has(k):
			errors.append("%s: duplicate %s entry '%s' (first kept)" % [path, label, k])
		else:
			into[k] = from[k]


static func _merge_families(into: Dictionary, from: Dictionary, path: String, errors: PackedStringArray) -> void:
	for slot: Variant in from:
		if String(slot).begins_with("_"):
			continue
		if not from[slot] is Dictionary:
			errors.append("%s: slot '%s' must be an object" % [path, slot])
			continue
		if not into.has(slot):
			into[slot] = {}
		for family: Variant in from[slot]:
			if String(family).begins_with("_"):
				continue
			if into[slot].has(family):
				errors.append("%s: duplicate family '%s' of slot '%s' (first kept)" % [path, family, slot])
			else:
				into[slot][family] = from[slot][family]


static func _merge_list(into: Array, from: Array, by_id: bool, label: String, path: String,
		errors: PackedStringArray) -> void:
	var seen := {}
	for e: Variant in into:
		seen[_list_key(e, by_id)] = true
	for e: Variant in from:
		var k: Variant = _list_key(e, by_id)
		if by_id and not (e is Dictionary and e.has("id")):
			errors.append("%s: a %s entry has no id" % [path, label])
		elif seen.has(k):
			errors.append("%s: duplicate %s entry '%s' (first kept)" % [path, label, k])
		else:
			seen[k] = true
			into.append(e)


static func _list_key(entry: Variant, by_id: bool) -> Variant:
	return entry.get("id") if by_id and entry is Dictionary else entry


## Parses one JSON file; null when missing or invalid.
static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return json.data


## Reads an explicit one-off character file. Invalid/missing files report an error; never substitute a Beginner.
static func load_character(path: String, errors: PackedStringArray) -> Dictionary:
	var value: Variant = load_json(path)
	var error := CharacterSnapshot.validation_error(value)
	if error != "":
		errors.append("character '%s': %s" % [path, error])
		return {}
	return value


## Cache path of a map img: "Map.wz/Map/Map1/104040000.img" (the folder digit is the first of the 9-digit id).
static func map_img_path(map_id: int) -> String:
	var s := "%09d" % map_id
	return "Map.wz/Map/Map%s/%s.img" % [s[0], s]


## Cache path of a Skill.wz book img: "Skill.wz/000.img".
static func skill_img_path(book: String) -> String:
	return "Skill.wz/%s.img" % book


## What the player sees as a stage's name (#221): {region, continent} of stage `stage_key` in the parsed stages.json
## (`stages_file`). The region is the town the stage belongs to, the continent the small line above it; both are survivor
## display data (tier C: owner choice, playtest 3), not WZ strings. A stage file without them falls back to its `name`
## as the region; an unknown stage gives empty strings.
static func stage_labels(stages_file: Dictionary, stage_key: String) -> Dictionary:
	stage_key = canonical_stage_key(stage_key)
	var st: Dictionary = stages_file.get("stages", {}).get(stage_key, {})
	return {"region": String(st.get("region", st.get("name", ""))), "continent": String(st.get("continent", ""))}


## The two stage lines of a run summary: [region, continent] (#221). A summary that carries a `region` keeps its own
## lines; one that predates the fields reads the stage's labels from stages.json, and a stage no longer in the file keeps
## the map and street name it was saved with.
static func summary_stage_lines(summary: Dictionary) -> Array[String]:
	var region := String(summary.get("region", ""))
	var continent := String(summary.get("continent", ""))
	if region.is_empty():
		var stages_file: Variant = load_json(DATA_ROOT.path_join(FILES.stages))
		var key := canonical_stage_key(String(summary.get("stage", "")))
		var known: Dictionary = {}
		if stages_file is Dictionary and (stages_file as Dictionary).get("stages", {}).has(key):
			known = stage_labels(stages_file, key)
		region = String(known.get("region", summary.get("map_name", key)))
		continent = String(known.get("continent", summary.get("street_name", "")))
	return [region, continent]


## One message per stage of the parsed stages.json that lacks a non-blank `region` or `continent`, in file order.
static func stage_label_errors(stages_file: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var all: Dictionary = stages_file.get("stages", {})
	for key: String in all:
		for field: String in ["region", "continent"]:
			if String((all[key] as Dictionary).get(field, "")).strip_edges().is_empty():
				errors.append("stage '%s' has no %s" % [key, field])
	return errors


## Ordered map entries for a region in setup.data.
static func stage_maps(data: Dictionary, stage_key: String) -> Array:
	stage_key = canonical_stage_key(stage_key)
	return data.get("stages", {}).get("stages", {}).get(stage_key, {}).get("maps", [])


## Reports missing/empty map lists and malformed entries through load_all's error list.
static func stage_map_errors(stages_file: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: String in stages_file.get("stages", {}):
		var maps: Variant = stages_file.stages[key].get("maps")
		if not maps is Array or maps.is_empty():
			errors.append("stage '%s' needs a non-empty maps list" % key)
			continue
		for i in maps.size():
			var entry: Variant = maps[i]
			if not entry is Dictionary or int(entry.get("map_id", 0)) <= 0 or not entry.get("boss") is Dictionary:
				errors.append("stage '%s' maps[%d] needs a map_id and boss" % [key, i])
				continue
			if entry.boss.has("skill_intervals") and not _valid_skill_intervals(entry.boss.skill_intervals):
				errors.append("stage '%s' maps[%d] boss skill_intervals needs {\"<mob skill id>\": seconds > 0}"
					% [key, i])
	return errors


## A boss entry's optional `skill_intervals` (spec #253, tier C): mob skill id strings -> positive seconds that replace
## that skill's WZ interval for this boss.
static func _valid_skill_intervals(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for skill: Variant in value:
		var seconds: Variant = value[skill]
		if not String(skill).is_valid_int() or int(String(skill)) <= 0:
			return false
		if not (seconds is float or seconds is int) or float(seconds) <= 0.0:
			return false
	return true


## Detached boss schedule with map provenance and curve offsets; live map arrivals are entry-relative.
static func stage_bosses(stage: Dictionary) -> Array:
	var bosses: Array = []
	for i in stage.get("maps", []).size():
		var entry: Dictionary = stage.maps[i]
		if not entry.get("boss") is Dictionary or entry.boss.is_empty():
			continue
		var boss: Dictionary = entry.boss.duplicate(true)
		boss["map_index"] = i
		boss["map_time"] = boss.get("time", 0)
		boss["time"] = i * float(stage.get("map_seconds", 0)) + float(boss.map_time)
		bosses.append(boss)
	return bosses


## Every mob id a stage needs, ascending (StageRoster.mob_ids): keyframe/explicit pool and every map's boss ids, plus summon and
## revive ids the bosses' canonical data lists when their imgs (`mob_imgs`, {id: img root}) and MobSkill.img root are
## given. `map_imgs` is index-aligned with stage.maps and adds its resolved ordinary life pools.
static func stage_mob_ids(data: Dictionary, stage_key: String, mob_imgs: Dictionary = {},
		mob_skill_img: Dictionary = {}, map_imgs: Array = []) -> PackedInt32Array:
	stage_key = canonical_stage_key(stage_key)
	var stage: Dictionary = data.get("stages", {}).get("stages", {}).get(stage_key, {})
	return StageRoster.mob_ids(stage, mob_imgs, mob_skill_img, map_imgs)


## Every item whose canonical info a setup loads, without duplicates: the default creation outfit
## (Equipment.DEFAULT_OUTFIT), every MakeCharInfo top, bottom,
## shoes and weapon option of both genders, every equipment_drops item, and everything `character` (a CharacterSnapshot,
## format 1 or 2) holds.
static func starter_equipment_ids(data: Dictionary, creation_img: Dictionary = {},
		character: Dictionary = {}) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for id: Variant in Equipment.DEFAULT_OUTFIT:
		_add_id(ids, int(id))
	var creation := CharacterCreation.new(creation_img)
	for gender in CharacterCreation.GENDERS.size():
		for field: String in ["top", "bottom", "shoes", "weapon"]:
			for id: int in creation.options(gender, field):
				_add_id(ids, id)
	# Every item that can drop (survivor list), so a kill can pick by the real reqLevel/reqJob and roll the real stats.
	for id: Variant in data.get("equipment_drops", {}).get("items", []):
		_add_id(ids, int(id))
	if not character.is_empty():
		for id: Variant in CharacterSnapshot.held_item_ids(character, jobs(data)):
			_add_id(ids, int(id))
	return ids


## The canonical Character.wz `info` node of each item id ({id: info}); ids whose img is absent are listed in
## `missing`. `img_loader.call(path) -> Dictionary` returns an img root ({} when absent), as for build_setup.
static func equipment_info(ids: PackedInt32Array, img_loader: Callable,
		missing: PackedStringArray = PackedStringArray()) -> Dictionary:
	var out := {}
	for id in ids:
		var equip_path := AvatarRenderer.part_img_path(id)
		var equip: Variant = img_loader.call(equip_path)
		if equip is Dictionary and equip.get("info") is Dictionary:
			out[id] = equip.info
		else:
			missing.append(equip_path)
	return out


## Shared player drawing for rounds, Free Market and slots. Empty look means AvatarRenderer.DEFAULT_LOOK's face/hair.
## `equips` is the worn equipment only (format 2), or for a format-1 / format-less dictionary what migration would
## wear (CharacterSnapshot.held_item_ids: its outfit plus the old weapon rule). Never mutates the snapshot.
## `worn_cash` ({slot: id}, see worn_cash()) is the cash equipment drawn over the worn equipment; the look has a `cash`
## key only when it is not empty.
static func character_look(character: Dictionary, data: Dictionary, worn_cash: Dictionary = {}) -> Dictionary:
	var look := AvatarRenderer.DEFAULT_LOOK.duplicate(true)
	look.merge(character.get("look", {}), true)
	if character.get("equipment") is Dictionary:
		look.equips = Equipment.worn_ids(character.equipment.get("worn", {}))
	else:
		look.equips = CharacterSnapshot.held_item_ids(character, jobs(data))
	if not worn_cash.is_empty():
		look["cash"] = worn_cash.duplicate()
	return look


## The cash equipment of `character` ({slot: id} from its snapshot `cash`) that the account owns (`owned`: item ids),
## the one rule for what any screen draws: the same filter the round applies (CashCatalog.resolve).
static func worn_cash(character: Dictionary, data: Dictionary, owned: Array) -> Dictionary:
	var cash: Dictionary = CharacterSnapshot.integers(character.get("cash", {}))
	return CashCatalog.from_data(data).resolve(cash, 0, owned).worn


## The canonical job tree with survivor flags and pools.
static func jobs(data: Dictionary) -> JobTree:
	return JobTree.from_data(data.get("jobs", {}), data.get("jobs_survivor", {}))


## Every potion item a run can use, ascending: the balance.potions starting item ids and every potions.schedule item
## (PotionSchedule). These are the Item.wz/Consume entries (`potion_img_path`) a setup loads.
static func potion_item_ids(data: Dictionary) -> PackedInt32Array:
	var ids := PackedInt32Array()
	var potions: Dictionary = data.get("balance", {}).get("potions", {})
	for kind: String in PotionInventory.DEFAULT_ITEMS:
		_add_id(ids, int(potions.get(kind, {}).get("item_id", 0)))
	for item: Variant in PotionSchedule.items(data.get("balance", {})):
		_add_id(ids, int(item))
	ids.sort()
	return ids


## The canonical node of every potion item a run can hold ({id: Consume node}); ids whose node is absent are listed in
## `missing`. A round's setup and the hub's inventory world (PotionInventory.upgrade needs the restore specs) share it.
static func potion_item_info(data: Dictionary, img_loader: Callable, missing: PackedStringArray = PackedStringArray()) -> Dictionary:
	var item_info := {}
	var potion_imgs := {} # Consume/0200.img (Red .. Mana Elixir, Ice Cream Pop) and 0202.img (Unagi, Pure Water): one read each
	for id in potion_item_ids(data):
		var key := "%08d" % id
		var img_path := potion_img_path(id)
		if not potion_imgs.has(img_path):
			potion_imgs[img_path] = img_loader.call(img_path)
		var potion_img: Variant = potion_imgs[img_path]
		if potion_img is Dictionary and potion_img.get(key) is Dictionary:
			item_info[id] = potion_img[key]
		else:
			missing.append(img_path + "/" + key)
	return item_info


## "Item.wz/Consume/0202.img" for a Consume item id (the img holds the ids of its 10000 block: 2022003 -> 0202).
@warning_ignore("integer_division")
static func potion_img_path(item_id: int) -> String:
	return "Item.wz/Consume/%04d.img" % (item_id / 10000)


static func _add_id(ids: PackedInt32Array, id: int) -> void:
	if id > 0 and not (id in ids):
		ids.append(id)


## Every scroll whose canonical info a setup loads, ascending: the roster (scrolls.json) and every stack `character`
## (a CharacterSnapshot) holds.
static func scroll_item_ids(data: Dictionary, character: Dictionary = {}) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for id: int in Scrolls.ids(data.get("scrolls", {})):
		_add_id(ids, id)
	for key: Variant in character.get("scrolls", {}):
		_add_id(ids, int(key))
	ids.sort()
	return ids


## The canonical `info` of each scroll id ({id: {success, cursed, slotMax, inc*}}, numbers only, as ints) from
## Item.wz/Consume/0204.img; ids whose node is absent are listed in `missing`. `img_loader` as for build_setup.
static func scroll_info(ids: Array, img_loader: Callable, missing: PackedStringArray = PackedStringArray()) -> Dictionary:
	var out := {}
	var img: Variant = img_loader.call(SCROLL_IMG)
	for id: Variant in ids:
		var key := "%08d" % int(id)
		var info: Variant = img[key].get("info") if img is Dictionary and img.get(key) is Dictionary else null
		if not info is Dictionary:
			missing.append(SCROLL_IMG + "/" + key)
			continue
		var kept := {}
		for field: Variant in info:
			var name := String(field)
			var value: Variant = info[field]
			if not (name.begins_with("inc") or name in ["success", "cursed", "slotMax", "price"]):
				continue
			# Some WZ nodes store the number as a string (hat Accuracy 10%: success "10").
			if value is String and (value as String).is_valid_int():
				kept[name] = int(value)
			elif value is int or value is float:
				kept[name] = int(value)
		out[int(id)] = kept
	return out


## The canonical facts of every ammo item survivor/ammo.json names ({id: {incPAD}}, tier A: Item.wz/Consume 0206 arrows,
## 0207 throwing stars, 0233 bullets; an item without incPAD, like Arrow for Bow, adds 0). Ids whose node is absent are
## listed in `missing` and left out. `img_loader` as for build_setup.
static func ammo_info(ammo: Dictionary, img_loader: Callable, missing: PackedStringArray = PackedStringArray()) -> Dictionary:
	var out := {}
	var imgs := {}
	for id in Ammo.item_ids(ammo):
		var path := Ammo.img_path(id)
		if not imgs.has(path):
			imgs[path] = img_loader.call(path)
		var img: Variant = imgs[path]
		var key := "%08d" % id
		if img is Dictionary and img.get(key) is Dictionary and img[key].get("info") is Dictionary:
			out[id] = {"incPAD": int(img[key].info.get("incPAD", 0))}
		else:
			missing.append(path + "/" + key)
	return out


## Every Skill.wz book named in skills.json ("000", "200", ...).
static func skill_books(data: Dictionary) -> PackedStringArray:
	var books := PackedStringArray()
	for key: String in data.get("skills", {}).get("skills", {}):
		var b := String(data.skills.skills[key].get("book", ""))
		if b != "" and not (b in books):
			books.append(b)
	return books


## A complete RunWorld setup for `stage_key`: `img_loader.call(path) -> Dictionary` returns an img root from the
## asset cache ({} when absent), `mob_loader.call(id) -> Dictionary` a mob img root with info/link followed.
## All map imgs are index-aligned in map_imgs (absent maps give {}); map_img remains map 0. Missing mob imgs are
## left out (RunWorld drops them from the pools); `missing` lists absent imgs. A non-empty
## `character` (CharacterSnapshot) becomes setup.character, and the info of every item it holds is loaded.
static func build_setup(data: Dictionary, stage_key: String, p_seed: int, view_size: Vector2, img_loader: Callable,
		mob_loader: Callable, missing: PackedStringArray = PackedStringArray(),
		character: Dictionary = {}) -> Dictionary:
	stage_key = canonical_stage_key(stage_key)
	var map_imgs: Array = []
	for entry: Dictionary in stage_maps(data, stage_key):
		var map_path := map_img_path(int(entry.get("map_id", 0)))
		var map_img: Variant = img_loader.call(map_path)
		if not map_img is Dictionary or map_img.is_empty():
			missing.append(map_path)
			map_img = {}
		map_imgs.append(map_img)
	var physics: Variant = img_loader.call(PHYSICS_IMG)
	if not (physics is Dictionary) or physics.is_empty():
		missing.append(PHYSICS_IMG)
		physics = {}
	var mob_skill: Variant = img_loader.call(MOB_SKILL_IMG)
	if not (mob_skill is Dictionary) or mob_skill.is_empty():
		missing.append(MOB_SKILL_IMG)
		mob_skill = {}
	# Two passes: the named pool/boss imgs first, then the summon/revive ids their canonical data lists.
	var mob_imgs := {}
	var tried := {}
	for _pass in 2:
		for id in stage_mob_ids(data, stage_key, mob_imgs, mob_skill, map_imgs):
			if tried.has(id):
				continue
			tried[id] = true
			var m: Variant = mob_loader.call(id)
			if m is Dictionary and not m.is_empty():
				mob_imgs[id] = m
			else:
				missing.append("Mob.wz/%07d.img" % id)
	var skill_imgs := {}
	for book in skill_books(data):
		var s: Variant = img_loader.call(skill_img_path(book))
		if s is Dictionary and not s.is_empty():
			skill_imgs[book] = s
		else:
			missing.append(skill_img_path(book))
	var creation_img: Dictionary = img_loader.call(CharacterCreation.IMG)
	var infos := equipment_info(starter_equipment_ids(data, creation_img, character), img_loader, missing)
	var body: Dictionary = img_loader.call("Character.wz/00002000.img")
	if body.is_empty():
		missing.append("Character.wz/00002000.img")
	# The afterimages the wearable weapons name in their canonical info (Sword swordOL, Wand mace).
	var afterimages := {}
	for info: Dictionary in infos.values():
		var name := WeaponInfo.afterimage_name(info)
		if name == "" or afterimages.has(name):
			continue
		var path := WeaponInfo.afterimage_img_path(name)
		var image: Dictionary = img_loader.call(path)
		if image.is_empty():
			missing.append(path)
		afterimages[name] = image
	var item_info := potion_item_info(data, img_loader, missing)
	var setup := {
		"map_imgs": map_imgs,
		"map_img": map_imgs[0] if not map_imgs.is_empty() else {},
		"physics_img": physics,
		"mob_imgs": mob_imgs,
		"skill_imgs": skill_imgs,
		"equipment_info": infos,
		"body_img": body,
		"afterimage_imgs": afterimages,
		"mob_skill_img": mob_skill,
		"item_info": item_info,
		"scroll_info": scroll_info(scroll_item_ids(data, character), img_loader, missing),
		"ammo_info": ammo_info(data.get("ammo", {}), img_loader, missing),
		"data": data,
		"stage": stage_key,
		"seed": p_seed,
		"view_size": view_size,
	}
	if not character.is_empty():
		setup["character"] = character
	return setup
