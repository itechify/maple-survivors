extends TestCase
## Creation reads canonical-shaped MakeCharInfo rather than a second table of allowed IDs.


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


func test_name_validation_explains_length_symbols_and_living_duplicate() -> void:
	var path := test_dir("creation/save.json")
	var save := SaveData.new(path)
	assert_true(save.name_error("abc").contains("4"))
	assert_true(save.name_error("abcdefghijklm").contains("12"))
	assert_true(save.name_error("map!e").contains("letters"))
	assert_true(save.name_error("Maplé").contains("letters"))
	var character := RunWorld.new({"data": DataRepo.load_all()}).character_snapshot()
	assert_eq(save.create_slot({"name": "Maple70", "character": character, "created": "2026-10-16",
		"tier": 0, "phase": "map_select", "rounds_played": 0, "tiers_cleared": 0}), 0)
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
	var setup := DataRepo.build_setup(DataRepo.load_all(), "henesys_hg1", 70, Vector2(800, 600),
		func(path: String) -> Dictionary: return lib.img(path).root if lib.img(path) != null else {},
		func(id: int) -> Dictionary: return lib.mob_root(id))
	# tier A: checked directly in original v83 Character.wz; no tuning copies in survivor data.
	for spec: Array in [[1302000, 17, 4], [1322005, 19, 5], [1312004, 17, 5]]:
		assert_eq(int(setup.equipment_info[spec[0]].incPAD), spec[1])
		assert_eq(int(setup.equipment_info[spec[0]].attackSpeed), spec[2])
	assert_eq(lib.missing, PackedStringArray())
	lib.free()
