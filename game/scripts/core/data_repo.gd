class_name DataRepo
extends RefCounted
## Loads the survivor design data (`game/data/survivor/*.json`) and the canonical facts that are not in WZ
## (`game/data/canonical/*.json`) into the `data` Dictionary of a RunWorld setup (docs/ARCHITECTURE.md 4.4.1, 4.4.4),
## and assembles a whole setup from an img loader. Presentation/core code: it reads files; the sim never does.
## Skills, upgrades, equipment drops, scrolls and shops are a base file plus per-job-line fragments
## (`survivor/<name>/<line>.json`) merged by `load_split` (SPLIT, LINES; docs/ARCHITECTURE.md 4.4.4).
##
##   var data := DataRepo.load_all()
##   var setup := DataRepo.build_setup(data, "henesys_hg1", 12345, Vector2(800, 600),
##       func(p: String) -> Dictionary: return Assets.img(p).root if Assets.img(p) != null else {},
##       func(id: int) -> Dictionary: return Assets.mob_root(id))

const DATA_ROOT := "res://data"
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
}
## The job lines whose fragment files may exist, in merge order: common (job-neutral) first, then the job-line ids in
## ascending order (Beginner 0, Warrior 1, Magician 2, Bowman 3, Thief 4, Pirate 5). A class spec adds its line by
## creating `<name>/<line>.json` next to the base file; the loader probes exactly these names in this order (job-line
## order, not file-name order: it decides the order of the merged cards that the level-up roll walks), and
## test_data_repo_lines fails on any other file in a fragment directory.
const LINES: PackedStringArray = ["common", "beginner", "warrior", "magician", "bowman", "thief", "pirate"]
## setup.data key -> how the entries of its line fragments (survivor/<name>/<line>.json) merge into the base file
## (survivor/<name>.json): `entries` is the key the fragments fill, `merge` the rule (docs/ARCHITECTURE.md 4.4.4).
##   keys:      Dictionary, entry keys concatenated (skills)
##   ids:       Array of Dictionaries with a unique `id`, concatenated in line order (upgrade cards)
##   sorted:    Array of unique numbers, concatenated then sorted ascending (equipment drop ids)
##   values:    Array of unique values, concatenated in line order (shop weapon slots)
##   families:  Dictionary slot -> Dictionary family -> rates, merged per slot (scrolls)
const SPLIT := {
	"skills": {"entries": "skills", "merge": "keys"},
	"upgrades": {"entries": "cards", "merge": "ids"},
	"equipment_drops": {"entries": "items", "merge": "sorted"},
	"scrolls": {"entries": "families", "merge": "families"},
	"shops": {"entries": "weapon_slots", "merge": "values"},
}
const PHYSICS_IMG := "Map.wz/Physics.img"
const MOB_SKILL_IMG := "Skill.wz/MobSkill.img"
const POTION_IMG := "Item.wz/Consume/0200.img"
const SCROLL_IMG := "Item.wz/Consume/0204.img"


## Every data file parsed, keyed as in setup.data. A missing or malformed file gives {} for its key and is listed in
## `errors` (when given). The keys in SPLIT are the base file plus the merged line fragments (load_split).
static func load_all(root: String = DATA_ROOT, errors: PackedStringArray = PackedStringArray()) -> Dictionary:
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
	return out


## The data of a SPLIT key: its base file (`_doc` and the job-neutral config) with the entries of every existing line
## fragment `<name>/<line>.json` merged in LINES order, per SPLIT's rule. A duplicate entry across files is listed in
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
	for line in LINES:
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


## Files in the fragment directories whose name is not `<known line>.json` (e.g. "survivor/skills/rogue.json"). They
## would be ignored by load_all, so a unit test requires this to be empty. Lists directories: tools and tests only.
static func unknown_line_files(root: String = DATA_ROOT) -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in SPLIT:
		var dir_path := root.path_join(String(FILES[key]).trim_suffix(".json"))
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			if not (file.ends_with(".json") and file.trim_suffix(".json") in LINES):
				out.append(String(FILES[key]).trim_suffix(".json").path_join(file))
	out.sort()
	return out


static func _merge_fragment(out: Dictionary, frag: Dictionary, spec: Dictionary, path: String,
		errors: PackedStringArray) -> void:
	var entries_key: String = spec.entries
	for k: Variant in frag:
		var name := String(k)
		if name.begins_with("_"):
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


## Every mob id a stage needs, ascending (StageRoster.mob_ids): pool and boss ids from stages.json, plus the summon and
## revive ids the bosses' canonical data lists when their imgs (`mob_imgs`, {id: img root}) and MobSkill.img root are
## given. Without imgs only the ids stages.json names.
static func stage_mob_ids(data: Dictionary, stage_key: String, mob_imgs: Dictionary = {},
		mob_skill_img: Dictionary = {}) -> PackedInt32Array:
	var stage: Dictionary = data.get("stages", {}).get("stages", {}).get(stage_key, {})
	return StageRoster.mob_ids(stage, mob_imgs, mob_skill_img)


## Every item whose canonical info a setup loads, without duplicates: the default creation outfit
## (Equipment.DEFAULT_OUTFIT), the job weapon grants (balance.player.weapon_grants), every MakeCharInfo top, bottom,
## shoes and weapon option of both genders, every equipment_drops item, and everything `character` (a CharacterSnapshot,
## format 1 or 2) holds.
static func starter_equipment_ids(data: Dictionary, creation_img: Dictionary = {},
		character: Dictionary = {}) -> PackedInt32Array:
	var pb: Dictionary = data.get("balance", {}).get("player", {})
	var ids := PackedInt32Array()
	for id: Variant in Equipment.DEFAULT_OUTFIT + pb.get("weapon_grants", {}).values():
		_add_id(ids, int(id))
	# Weapon paths, branch grants (spec #151 #157) and grants.items of the jobs this build can play; an unplayable job's
	# items are not in the asset cache yet, so they load once its class spec makes it playable.
	var job_rows: Variant = data.get("jobs_survivor", {}).get("jobs", {})
	for row: Variant in job_rows.values() if job_rows is Dictionary else []:
		if row is Dictionary and bool(row.get("playable", false)):
			_add_id(ids, int(row.get("grant_item", 0)))
			var extra: Variant = row.get("grants", {}).get("items", []) if row.get("grants", {}) is Dictionary else []
			for item: Variant in extra if extra is Array else []:
				_add_id(ids, int(item))
			for path: Variant in row.get("paths", []) if row.get("paths", []) is Array else []:
				_add_id(ids, int(path.get("item_id", 0)) if path is Dictionary else 0)
	var creation := CharacterCreation.new(creation_img)
	for gender in CharacterCreation.GENDERS.size():
		for field: String in ["top", "bottom", "shoes", "weapon"]:
			for id: int in creation.options(gender, field):
				_add_id(ids, id)
	# Every item that can drop (survivor list), so a kill can pick by the real reqLevel/reqJob and roll the real stats.
	for id: Variant in data.get("equipment_drops", {}).get("items", []):
		_add_id(ids, int(id))
	if not character.is_empty():
		for id: Variant in CharacterSnapshot.held_item_ids(character, _jobs(data)):
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
		look.equips = CharacterSnapshot.held_item_ids(character, _jobs(data))
	if not worn_cash.is_empty():
		look["cash"] = worn_cash.duplicate()
	return look


## The cash equipment of `character` ({slot: id} from its snapshot `cash`) that the account owns (`owned`: item ids),
## the one rule for what any screen draws: the same filter the round applies (CashCatalog.resolve).
static func worn_cash(character: Dictionary, data: Dictionary, owned: Array) -> Dictionary:
	var cash: Dictionary = CharacterSnapshot.integers(character.get("cash", {}))
	return CashCatalog.from_data(data).resolve(cash, 0, owned).worn


static func _jobs(data: Dictionary) -> JobTree:
	return JobTree.from_data(data.get("jobs", {}), data.get("jobs_survivor", {}))


## Every potion item a run can hold, ascending: the balance.potions starters and every potion_tier card's required and
## target items (the survivor potion ladders). These are the Item.wz/Consume/0200.img entries a setup loads.
static func potion_item_ids(data: Dictionary) -> PackedInt32Array:
	var ids := PackedInt32Array()
	var potions: Dictionary = data.get("balance", {}).get("potions", {})
	for kind: String in PotionInventory.DEFAULT_ITEMS:
		_add_id(ids, int(potions.get(kind, {}).get("item_id", 0)))
	for c: Dictionary in data.get("upgrades", {}).get("cards", []):
		if String(c.get("kind", "")) == "potion_tier":
			_add_id(ids, int(c.get("item_id", 0)))
			for from: Variant in c.get("requires", {}).get("potions", {}).values():
				_add_id(ids, int(from))
	ids.sort()
	return ids


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
## Absent imgs are left out (RunWorld drops mobs without an img from the pools); `missing` lists them. A non-empty
## `character` (CharacterSnapshot) becomes setup.character, and the info of every item it holds is loaded.
static func build_setup(data: Dictionary, stage_key: String, p_seed: int, view_size: Vector2, img_loader: Callable,
		mob_loader: Callable, missing: PackedStringArray = PackedStringArray(),
		character: Dictionary = {}) -> Dictionary:
	var stage: Dictionary = data.get("stages", {}).get("stages", {}).get(stage_key, {})
	var map_path := map_img_path(int(stage.get("map_id", 0)))
	var map_img: Variant = img_loader.call(map_path)
	if not (map_img is Dictionary) or map_img.is_empty():
		missing.append(map_path)
		map_img = {}
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
		for id in stage_mob_ids(data, stage_key, mob_imgs, mob_skill):
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
	var item_info := {}
	var potion_img: Variant = img_loader.call(POTION_IMG)
	for id in potion_item_ids(data):
		var key := "%08d" % id
		if potion_img is Dictionary and potion_img.get(key) is Dictionary:
			item_info[id] = potion_img[key]
		else:
			missing.append(POTION_IMG + "/" + key)
	var setup := {
		"map_img": map_img,
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
