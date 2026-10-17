class_name DataRepo
extends RefCounted
## Loads the survivor design data (`game/data/survivor/*.json`) and the canonical facts that are not in WZ
## (`game/data/canonical/*.json`) into the `data` Dictionary of a RunWorld setup (docs/ARCHITECTURE.md 4.4.1, 4.4.4),
## and assembles a whole setup from an img loader. Presentation/core code: it reads files; the sim never does.
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
	"jobs": "canonical/jobs.json",
	"exp_table": "canonical/exp_table.json",
}
const PHYSICS_IMG := "Map.wz/Physics.img"
const MOB_SKILL_IMG := "Skill.wz/MobSkill.img"
const POTION_IMG := "Item.wz/Consume/0200.img"
const SCROLL_IMG := "Item.wz/Consume/0204.img"


## Every data file parsed, keyed as in setup.data. A missing or malformed file gives {} for its key and is listed in
## `errors` (when given).
static func load_all(root: String = DATA_ROOT, errors: PackedStringArray = PackedStringArray()) -> Dictionary:
	var out := {}
	for key: String in FILES:
		var path := root.path_join(FILES[key])
		var v: Variant = load_json(path)
		if v is Dictionary:
			out[key] = v
		else:
			out[key] = {}
			errors.append("cannot read %s" % path)
	return out


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
static func character_look(character: Dictionary, data: Dictionary) -> Dictionary:
	var look := AvatarRenderer.DEFAULT_LOOK.duplicate(true)
	look.merge(character.get("look", {}), true)
	if character.get("equipment") is Dictionary:
		look.equips = Equipment.worn_ids(character.equipment.get("worn", {}))
	else:
		look.equips = CharacterSnapshot.held_item_ids(character, _jobs(data))
	return look


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
			if (name.begins_with("inc") or name in ["success", "cursed", "slotMax"]) and (value is int or value is float):
				kept[name] = int(value)
		out[int(id)] = kept
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
		"data": data,
		"stage": stage_key,
		"seed": p_seed,
		"view_size": view_size,
	}
	if not character.is_empty():
		setup["character"] = character
	return setup
