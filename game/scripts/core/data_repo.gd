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
}
const PHYSICS_IMG := "Map.wz/Physics.img"
const MOB_SKILL_IMG := "Skill.wz/MobSkill.img"
## tier C: starter loadout selection, matching AvatarRenderer.DEFAULT_LOOK and the two starting weapons.
const STARTER_EQUIPMENT := {
	1040002: "Character.wz/Coat/01040002.img", 1060002: "Character.wz/Pants/01060002.img",
	1072001: "Character.wz/Shoes/01072001.img", 1302000: "Character.wz/Weapon/01302000.img",
	1372005: "Character.wz/Weapon/01372005.img",
}


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


## Cache path of a map img: "Map.wz/Map/Map1/104040000.img" (the folder digit is the first of the 9-digit id).
static func map_img_path(map_id: int) -> String:
	var s := "%09d" % map_id
	return "Map.wz/Map/Map%s/%s.img" % [s[0], s]


## Cache path of a Skill.wz book img: "Skill.wz/000.img".
static func skill_img_path(book: String) -> String:
	return "Skill.wz/%s.img" % book


## Every mob id used by any keyframe pool of the stage, ascending.
static func stage_mob_ids(data: Dictionary, stage_key: String) -> PackedInt32Array:
	var ids := PackedInt32Array()
	var stage: Dictionary = data.get("stages", {}).get("stages", {}).get(stage_key, {})
	for kf: Dictionary in stage.get("keyframes", []):
		for k: String in kf.get("pool", {}):
			var id := int(k)
			if not (id in ids):
				ids.append(id)
	ids.sort()
	return ids


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
	var mob_imgs := {}
	for id in stage_mob_ids(data, stage_key):
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
	for id: int in STARTER_EQUIPMENT:
		var equip: Variant = img_loader.call(STARTER_EQUIPMENT[id])
		if equip is Dictionary and equip.get("info") is Dictionary:
			equipment_info[id] = equip.info
		else:
			missing.append(STARTER_EQUIPMENT[id])
	var mob_skill: Variant = img_loader.call(MOB_SKILL_IMG)
	if not (mob_skill is Dictionary) or mob_skill.is_empty():
		missing.append(MOB_SKILL_IMG)
		mob_skill = {}
	var body: Dictionary = img_loader.call("Character.wz/00002000.img")
	if body.is_empty():
		missing.append("Character.wz/00002000.img")
	var afterimages := {}
	for name: String in ["swordOL", "mace"]:
		var path := "Character.wz/Afterimage/%s.img" % name
		var image: Dictionary = img_loader.call(path)
		if image.is_empty():
			missing.append(path)
		afterimages[name] = image
	return {
		"map_img": map_img,
		"physics_img": physics,
		"mob_imgs": mob_imgs,
		"skill_imgs": skill_imgs,
		"equipment_info": equipment_info,
		"body_img": body,
		"afterimage_imgs": afterimages,
		"mob_skill_img": mob_skill,
		"data": data,
		"stage": stage_key,
		"seed": p_seed,
		"view_size": view_size,
	}
