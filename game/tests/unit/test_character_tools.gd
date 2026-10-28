extends TestCase
## The committed real-bot character and balance tool's public --character file boundary.

const FIXTURE := "res://tests/fixtures/characters/fp_arch_mage.json"


func test_fixture_is_a_format_three_arch_mage_with_the_tier_one_kit() -> void:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(FIXTURE, errors)
	assert_eq(errors, PackedStringArray())
	if character.is_empty():
		return
	assert_eq(int(character.format), 3)
	assert_eq(int(character.job_id), 212)
	assert_eq(int(character.tiers_unlocked), 2, "tier 2 is unlocked")
	for gone: String in ["level", "exp", "skills", "skill_order", "card_ranks", "player_mods", "earned_ap", "attributes", "base_hp"]:
		assert_false(character.has(gone), "a format-3 character keeps no " + gone)
	assert_eq(String(character._doc.revision).length(), 40)
	assert_eq(character._doc.kit.map(func(id: Variant) -> int: return int(id)),
		[1382002, 1002013, 1072019, 1082019, 1040002, 1060002], "_doc names the kit ids the tool reproduces it from")
	assert_eq(Equipment.worn_ids(character.equipment.worn), [1002013, 1040002, 1060002, 1072019, 1082019, 1382002],
		"the starter top and bottom and the tier-1 staff, hat, shoes and gloves are worn")
	assert_eq(character.equipment.inventory, [], "nothing spare")
	for slot: String in ["weapon", "hat", "shoes", "gloves"]:
		assert_eq(int(character.equipment.worn[slot].scrolls), 0, slot + " is unscrolled")
	assert_eq(int(character.mesos), 0)
	assert_eq(character.scrolls, {})


func test_balance_character_flag_uses_fixture_in_one_off_round() -> void:
	if not require_cache():
		return
	# Space-containing absolute paths exercise argument boundaries as well as the JSON reader.
	var path := ProjectSettings.globalize_path(test_dir("carried character.json"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE), path)
	var output: Array = []
	var status := OS.execute(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", "res://tools/balance_run.gd", "--",
		"--stage=henesys", "--seed=2", "--cap=0.016666667", "--character=" + path], output, true)
	assert_eq(status, 0)
	var record := {}
	for line: String in "\n".join(output).split("\n"):
		if line.begins_with("BALANCE "):
			record = JSON.parse_string(line.substr(8))
	assert_false(record.is_empty(), "balance tool produced a record")
	if record.is_empty():
		return
	var character: Dictionary = DataRepo.load_json(FIXTURE)
	var start: Dictionary = record.start_character
	assert_eq(int(start.format), 3)
	assert_eq(int(start.job_id), int(character.job_id), "report captures the actual starting boundary")
	assert_eq(start.equipment, JSON.parse_string(JSON.stringify(character.equipment)), "the same gear")
	assert_eq(int(start.tiers_unlocked), 2)
	assert_eq(record.missing, [])
	assert_eq(int(record.job), int(character.job_id))
	assert_eq(int(record.start_character.mesos), 0)
	assert_false(record.has("potions_start"))
	assert_false(record.start_character.has("potions"))
	assert_eq(record.warnings, [])


func test_balance_explicit_empty_character_flag_is_an_error() -> void:
	if not require_cache():
		return
	var output: Array = []
	var status := OS.execute(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", "res://tools/balance_run.gd", "--",
		"--cap=0.016666667", "--character="], output, true)
	assert_eq(status, 1)
	assert_true("\n".join(output).contains("balance_run: character"))
	assert_false("\n".join(output).contains("BALANCE "))
