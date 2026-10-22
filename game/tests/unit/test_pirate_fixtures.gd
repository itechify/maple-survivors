extends TestCase
## The committed Pirate second-job characters (spec #168 #195): one Brawler and one Gunslinger from real headless bot rounds
## made with the fixture tool's diagnostic aids (see each _doc). They must load, restore as the job, weapon path and weapon they
## claim, and play on the real map without warnings.

const BRAWLER := "res://tests/fixtures/characters/lv37_brawler_2nd.json"
const GUNSLINGER := "res://tests/fixtures/characters/lv36_gunslinger_2nd.json"


func _load(path: String) -> Dictionary:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(path, errors)
	assert_eq(errors, PackedStringArray(), path)
	return character


func test_docs_say_how_each_fixture_was_made() -> void:
	for spec: Array in [[BRAWLER, 510, "knuckle"], [GUNSLINGER, 520, "gun"]]:
		var character := _load(spec[0])
		var doc: Dictionary = character._doc
		assert_eq(int(doc.forced_branch), spec[1])
		assert_eq(doc.forced_path, spec[2])
		assert_eq(doc.policy, "bot")
		assert_eq(DataRepo.canonical_stage_key(String(doc.stage)), "henesys")
		assert_eq(int(doc.seed), 1)
		assert_eq(String(doc.revision).length(), 40)
		assert_true(String(doc.diagnostic).contains("RunWorld.god"), "the invulnerability aid is recorded")
		assert_true(String(doc.source).contains("cap"), "a capped round")
		assert_eq(int(character.format), CharacterSnapshot.FORMAT)
	assert_eq(float(_load(BRAWLER)._doc.exp_mult), 3.0, "the knuckle fixture records its EXP aid")
	assert_false(_load(GUNSLINGER)._doc.has("exp_mult"), "the gun fixture used natural EXP")


func test_snapshots_are_second_job_pirates_with_their_lv30_weapon_family() -> void:
	var brawler := _load(BRAWLER)
	assert_eq(int(brawler.job_id), 510)
	assert_eq(brawler.weapon_path, "knuckle")
	assert_between(float(brawler.level), 30.0, 45.0)
	assert_eq(WeaponInfo.family(int(brawler.equipment.worn.weapon.id)), WeaponInfo.family(1482000), "a knuckle")
	for key in ["flash_fist", "backspin_blow"]:
		assert_true(brawler.skills.has(key), key)
	var gunslinger := _load(GUNSLINGER)
	assert_eq(int(gunslinger.job_id), 520)
	assert_eq(gunslinger.weapon_path, "gun")
	assert_between(float(gunslinger.level), 30.0, 45.0)
	assert_eq(WeaponInfo.family(int(gunslinger.equipment.worn.weapon.id)), WeaponInfo.family(1492000), "a gun")
	for key in ["double_shot", "invisible_shot"]:
		assert_true(gunslinger.skills.has(key), key)


func test_fixtures_restore_and_play_on_the_real_map() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	for spec: Array in [[BRAWLER, 510], [GUNSLINGER, 520]]:
		var character := _load(spec[0])
		var missing := PackedStringArray()
		var setup := DataRepo.build_setup(DataRepo.load_all(), "henesys", 2, Vector2(800, 600),
			func(path: String) -> Dictionary: return lib.img(path).root if lib.img(path) != null else {},
			func(id: int) -> Dictionary: return lib.mob_root(id), missing, character)
		assert_eq(interim_missing(missing, setup.data, setup.stage), PackedStringArray())
		var w := RunWorld.new(setup)
		assert_eq(w.progression.job_id, spec[1])
		assert_eq(w.progression.level, int(character.level))
		assert_eq(w.weapon_path, character.weapon_path)
		assert_eq(w.weapon_id(), int(character.equipment.worn.weapon.id))
		for key: String in character.skills:
			assert_eq(w.loadout.rank(key), int(character.skills[key].rank), key)
		for i in 600:
			w.step(1.0 / 60.0, MoveInput.new())
		assert_eq(w.warnings, PackedStringArray())
	lib.free()
