extends TestCase
## Creation reads canonical-shaped MakeCharInfo rather than a second table of allowed IDs.

const RF := preload("res://tests/fixtures/run_fixtures.gd")


func test_options_follow_each_gender_in_wz_order_and_exclude_premium() -> void:
	var male := {}
	var female := {}
	for i in 8:
		male[str(i)] = {"1": 900 + i, "0": 100 + i}
		female[str(i)] = {"0": 200 + i}
	var model := CharacterCreation.new({"Info": {"CharMale": male, "CharFemale": female},
		"PremiumCharMale": {"0": {"0": 9999}}})
	for i in 8:
		assert_eq(model.options(0, CharacterCreation.FIELDS[i]), [100 + i, 900 + i])
		assert_eq(model.options(1, CharacterCreation.FIELDS[i]), [200 + i])
	assert_eq(model.options(0, "gender"), [0, 1])
	assert_eq(model.look(1, {}), {"skin": 203, "face": 200, "hair": 403,
		"equips": [204, 205, 206]})
	assert_eq(model.weapon(1, {}), 207)


func test_shared_drawing_keeps_the_look_and_replaces_only_the_weapon() -> void:
	var data := DataRepo.load_all()
	var character := {"job_id": 0, "beginner_weapon": 1322005,
		"look": {"skin": 3, "face": 21002, "hair": 31057, "equips": [1041011, 1061008, 1072038, 1302000]}}
	assert_eq(DataRepo.character_look(character, data), {"skin": 3, "face": 21002, "hair": 31057,
		"equips": [1041011, 1061008, 1072038, 1322005]})
	character.job_id = 220
	assert_eq(DataRepo.character_look(character, data).equips, [1041011, 1061008, 1072038, 1372005])
	assert_eq(character.look.equips, [1041011, 1061008, 1072038, 1302000], "drawing never mutates the snapshot")
	assert_eq(DataRepo.character_look({}, data), {"skin": 0, "face": 20000, "hair": 30030,
		"equips": [1040002, 1060002, 1072001, 1302000]})


func test_creation_choices_become_worn_equipment_and_are_what_is_drawn() -> void:
	# Synthetic img roots shaped like Character.wz items (stats invented).
	var imgs := {}
	for spec: Array in [[1041011, {"incPDD": 3, "tuc": 7}], [1061008, {"incPDD": 2, "tuc": 7}],
			[1072038, {"incPDD": 2, "tuc": 5}], [1372005, {"incPAD": 15, "incMAD": 23, "tuc": 7}]]:
		imgs[AvatarRenderer.part_img_path(spec[0])] = {"info": spec[1]}
	var loader := func(path: String) -> Dictionary: return imgs.get(path, {})
	var character := SceneFlow.new_character({"skin": 3, "face": 21002, "hair": 31057,
		"equips": [1041011, 1061008, 1072038]}, 212, loader)
	assert_eq(CharacterSnapshot.validation_error(character), "")
	assert_eq(character.look, {"skin": 3, "face": 21002, "hair": 31057})
	assert_eq(character.equipment.worn.weapon, {"id": 1372005, "stats": {"incPAD": 15, "incMAD": 23}, "slots": 7,
		"scrolls": 0}, "the job's creation weapon, with its plain WZ stats")
	assert_eq(character.job_id, 212)
	assert_eq(character.cleared_regions, [])
	assert_eq(character.equipment.worn.shoes.slots, 5)
	assert_eq(character.equipment.inventory, [])
	assert_eq(character.mesos, 0)
	assert_eq(DataRepo.character_look(character, DataRepo.load_all()), {"skin": 3, "face": 21002, "hair": 31057,
		"equips": [1041011, 1061008, 1072038, 1372005]}, "the creation items look exactly as before")
	var world_setup := RF.setup("quiet", 1, RF.quiet_data())
	world_setup.character = character
	var world := RunWorld.new(world_setup)
	assert_eq(world.weapon_id(), 1372005)
	assert_eq(world.player_state.pdd, 7.0, "the creation outfit's own W.DEF")
	var plain := SceneFlow.new_character({}, 212, loader)
	assert_eq(Equipment.worn_ids(plain.equipment.worn),
		Equipment.DEFAULT_OUTFIT.slice(0, 3) + [1372005], "an empty look wears the default outfit and the job's wand")


func test_name_validation_explains_length_symbols_and_living_duplicate() -> void:
	var path := test_dir("creation/save.json")
	var save := SaveData.new(path)
	assert_true(save.name_error("abc").contains("4"))
	assert_true(save.name_error("abcdefghijklm").contains("12"))
	assert_true(save.name_error("map!e").contains("letters"))
	assert_true(save.name_error("Maplé").contains("letters"))
	var character := RunWorld.new({"data": DataRepo.load_all()}).character_snapshot()
	assert_eq(save.create_slot({"name": "Maple70", "character": character, "created": "2026-10-16",
		"rounds_played": 0}), 0)
	assert_true(save.name_error("maple70").contains("already"))
	assert_eq(save.name_error("Maple71"), "")


func test_imported_creation_options_have_every_renderable_variant_and_canonical_weapon_info() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var model := CharacterCreation.new(lib.img(CharacterCreation.IMG).root)
	assert_true(model.available())
	for gender in 2:
		for field: String in ["face", "top", "bottom", "shoes", "weapon"]:
			for id: int in model.options(gender, field):
				assert_true(lib.img(AvatarRenderer.part_img_path(id)) != null, "%s %d" % [field, id])
		for hair: int in model.options(gender, "hair"):
			for colour: int in model.options(gender, "hair_colour"):
				assert_true(lib.img(AvatarRenderer.part_img_path(hair + colour)) != null)
		for skin: int in model.options(gender, "skin"):
			assert_true(lib.img(AvatarRenderer.part_img_path(2000 + skin)) != null)
			assert_true(lib.img(AvatarRenderer.part_img_path(12000 + skin)) != null)
	var setup := DataRepo.build_setup(DataRepo.load_all(), "henesys", 70, Vector2(800, 600),
		func(path: String) -> Dictionary: return lib.img(path).root if lib.img(path) != null else {},
		func(id: int) -> Dictionary: return lib.mob_root(id))
	# tier A: checked directly in original v83 Character.wz; no tuning copies in survivor data.
	for spec: Array in [[1302000, 17, 4], [1322005, 19, 5], [1312004, 17, 5]]:
		assert_eq(int(setup.equipment_info[spec[0]].incPAD), spec[1])
		assert_eq(int(setup.equipment_info[spec[0]].attackSpeed), spec[2])
	# Equipment.DEFAULT_OUTFIT is MakeCharInfo's first CharMale top, bottom, shoes and weapon.
	assert_eq(Equipment.DEFAULT_OUTFIT, ["top", "bottom", "shoes", "weapon"].map(
		func(field: String) -> int: return int(model.options(0, field)[0])))
	for gender in 2:
		for field: String in ["top", "bottom", "shoes", "weapon"]:
			for id: int in model.options(gender, field):
				assert_true(setup.equipment_info.has(id), "every creation choice can be worn: %d" % id)
				assert_ne(Equipment.slot_of(id), "")
	# tier A: the Wooden Wand's v83 info (Character.wz/Weapon/01372005.img).
	assert_eq(Equipment.create(1372005, setup.equipment_info[1372005]),
		{"id": 1372005, "stats": {"incPAD": 15, "incMAD": 23}, "slots": 7, "scrolls": 0})
	assert_eq(int(setup.equipment_info[1372005].reqLevel), 8)
	var fresh := RunWorld.new(setup)
	assert_eq(fresh.player_state.pdd, 7.0, "the default outfit's W.DEF 3 + 2 + 2")
	assert_true(lib.sound(WeaponInfo.sound_path(WeaponReach.BARE_HANDS)) != null, "the bare-handed punch sound")
	assert_eq(lib.missing, PackedStringArray())
	lib.free()
