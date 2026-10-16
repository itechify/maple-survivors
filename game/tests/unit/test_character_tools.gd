extends TestCase
## The committed real-bot character and balance tool's public --character file boundary.

const FIXTURE := "res://tests/fixtures/characters/lv35_magician_2nd.json"


func test_fixture_is_complete_second_job_magician_character() -> void:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(FIXTURE, errors)
	assert_eq(errors, PackedStringArray())
	if character.is_empty():
		return
	assert_between(float(character.level), 33.0, 39.0, "approximately level 35")
	assert_true(int(character.job_id) in [210, 220, 230])
	assert_true(character.skills.size() > 1)
	assert_eq(character._doc.seed, 1)
	assert_eq(character._doc.policy, "bot")
	assert_eq(character._doc.outcome, "CLEARED")
	assert_eq(String(character._doc.revision).length(), 40)


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
		"--stage=henesys_hg1", "--seed=2", "--cap=0.016666667", "--character=" + path], output, true)
	assert_eq(status, 0)
	var record := {}
	for line: String in "\n".join(output).split("\n"):
		if line.begins_with("BALANCE "):
			record = JSON.parse_string(line.substr(8))
	assert_false(record.is_empty(), "balance tool produced a record")
	if record.is_empty():
		return
	var character: Dictionary = DataRepo.load_json(FIXTURE)
	assert_eq(int(record.level), int(character.level))
	assert_eq(int(record.job), int(character.job_id))
	for key: String in character.skills:
		assert_eq(int(record.skills.get(key, 0)), int(character.skills[key].rank))
	for kind: String in ["hp", "mp"]:
		assert_eq(int(record.potions_start[kind]), int(character.potions[kind].count))
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
