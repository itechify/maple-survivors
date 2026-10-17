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
	"jobs_survivor": "survivor/jobs.json",
	"jobs": "canonical/jobs.json",
	"exp_table": "canonical/exp_table.json",
	"cash_items": "survivor/cash_items.json",
}
const PHYSICS_IMG := "Map.wz/Physics.img"
const MOB_SKILL_IMG := "Skill.wz/MobSkill.img"
const POTION_IMG := "Item.wz/Consume/0200.img"


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


## The starter outfit and every job weapon the run can wear (balance.player `equipment`, then `weapon_by_job` in job
## order), plus MakeCharInfo's Beginner weapons, without duplicates: the canonical info a setup loads.
static func starter_equipment_ids(data: Dictionary, creation_img: Dictionary = {}) -> PackedInt32Array:
	var pb: Dictionary = data.get("balance", {}).get("player", {})
	var ids := PackedInt32Array()
	for id: Variant in pb.get("equipment", []) + pb.get("weapon_by_job", {}).values():
		if int(id) > 0 and not (int(id) in ids):
			ids.append(int(id))
	var creation := CharacterCreation.new(creation_img)
	for gender in CharacterCreation.GENDERS.size():
		for id: int in creation.options(gender, "weapon"):
			_add_id(ids, id)
	return ids


## Shared player drawing for rounds, Free Market and slots. Empty look means AvatarRenderer.DEFAULT_LOOK.
## The character's outfit is carried verbatim; every old weapon is replaced by the simulation's weapon rule.
## `worn_cash` ({slot: id}, see worn_cash()) is the cash equipment drawn over the outfit; the look has a `cash` key
## only when it is not empty.
static func character_look(character: Dictionary, data: Dictionary, worn_cash: Dictionary = {}) -> Dictionary:
	var look := AvatarRenderer.DEFAULT_LOOK.duplicate(true)
	look.merge(character.get("look", {}), true)
	var equips: Array = look.equips.filter(func(id: Variant) -> bool:
		return WeaponInfo.type_of(int(id)) not in range(130, 171))
	var weapon := CharacterSnapshot.weapon_id(int(character.get("job_id", 0)),
		int(character.get("beginner_weapon", 0)), data.get("balance", {}).get("player", {}).get("weapon_by_job", {}),
		JobTree.from_data(data.get("jobs", {}), data.get("jobs_survivor", {})))
	if weapon > 0:
		equips.append(weapon)
	look.equips = equips
	if not worn_cash.is_empty():
		look["cash"] = worn_cash.duplicate()
	return look


## The cash equipment of `character` ({slot: id} from its snapshot `cash`) that the account owns (`owned`: item ids),
## the one rule for what any screen draws: the same filter the round applies (CashCatalog.resolve).
static func worn_cash(character: Dictionary, data: Dictionary, owned: Array) -> Dictionary:
	var cash: Dictionary = CharacterSnapshot.integers(character.get("cash", {}))
	return CashCatalog.from_data(data).resolve(cash, 0, owned).worn


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
## Absent imgs are left out (RunWorld drops mobs without an img from the pools); `missing` lists them.
static func build_setup(data: Dictionary, stage_key: String, p_seed: int, view_size: Vector2, img_loader: Callable,
		mob_loader: Callable, missing: PackedStringArray = PackedStringArray()) -> Dictionary:
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
	var equipment_info := {}
	var creation_img: Dictionary = img_loader.call(CharacterCreation.IMG)
	for id in starter_equipment_ids(data, creation_img):
		var equip_path := AvatarRenderer.part_img_path(id)
		var equip: Variant = img_loader.call(equip_path)
		if equip is Dictionary and equip.get("info") is Dictionary:
			equipment_info[id] = equip.info
		else:
			missing.append(equip_path)
	var body: Dictionary = img_loader.call("Character.wz/00002000.img")
	if body.is_empty():
		missing.append("Character.wz/00002000.img")
	# The afterimages the worn weapons name in their canonical info (Sword swordOL, Wand mace).
	var afterimages := {}
	for info: Dictionary in equipment_info.values():
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
	return {
		"map_img": map_img,
		"physics_img": physics,
		"mob_imgs": mob_imgs,
		"skill_imgs": skill_imgs,
		"equipment_info": equipment_info,
		"body_img": body,
		"afterimage_imgs": afterimages,
		"mob_skill_img": mob_skill,
		"item_info": item_info,
		"data": data,
		"stage": stage_key,
		"seed": p_seed,
		"view_size": view_size,
	}
