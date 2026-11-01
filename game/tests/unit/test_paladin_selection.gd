extends TestCase
## Shipped Paladin (122) through the tools (spec #308, P9 #317): run flags, balance_run, fixture generation, mismatched characters
## and the Paladin fixture starting a round with Power Strike in slot 1 and Rush learned. A disabling patch keeps the refusal
## tests meaningful now that 122 ships playable.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const PATCH := {"jobs_survivor": {"jobs": {"122": {"playable": false}}}}
const FP_FIXTURE := "res://tests/fixtures/characters/fp_arch_mage.json"
const PALADIN_FIXTURE := "res://tests/fixtures/characters/paladin_t2.json"

var work_dir := TestCase.test_dir("paladin_selection")


func before_each() -> void:
	TestCase.remove_tree(work_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(work_dir))
	DataRepo.patch = {}


func after_each() -> void:
	DataRepo.patch = {}


## Absolute path of a file with `text` in the test directory.
func _file(file_name: String, text: String) -> String:
	var path := ProjectSettings.globalize_path(work_dir.path_join(file_name))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


## A Paladin (122) character file in the creation outfit with synthetic item stats.
func _paladin_file() -> String:
	var imgs := {}
	for id: int in [1040002, 1060002, 1072001, 1322000]:
		imgs[AvatarRenderer.part_img_path(id)] = {"info": {"tuc": 7, "incPAD": 34, "incPDD": 2}}
	var character := SceneFlow.new_character({}, 122, func(path: String) -> Dictionary: return imgs.get(path, {}))
	return _file("paladin.json", JSON.stringify(character))


func _tool(script: String, args: PackedStringArray) -> Dictionary:
	var output: Array = []
	var status := OS.execute(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", script, "--"] + Array(args), output, true)
	return {"status": status, "text": "\n".join(output)}


func _record(text: String) -> Dictionary:
	for line: String in text.split("\n"):
		if line.begins_with("BALANCE "):
			return JSON.parse_string(line.substr(8))
	return {}


func test_run_flags_carry_job_122_and_the_error_names_a_disabled_job() -> void:
	var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys", "--job=122", "--seed=3"]))
	assert_eq(int(parsed.options.job), 122)
	assert_eq(RunLauncher.options_from_args({"job": "122"}).job, 122)
	assert_eq(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()), "", "shipped Paladin is playable")
	DataRepo.patch = PATCH.duplicate(true)
	assert_true(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()).contains("not playable"))
	DataRepo.patch = {}
	assert_eq(SceneFlow.forced_job_error({"job": 212}, DataRepo.load_all()), "")
	assert_eq(SceneFlow.forced_job_error({"job": 112}, DataRepo.load_all()), "")


func test_balance_run_accepts_job_122_and_refuses_an_explicitly_disabled_job() -> void:
	if not require_cache():
		return
	var patch := _file("paladin_disabled.json", JSON.stringify(PATCH))
	var ok := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--seed=1", "--cap=0.016666667", "--job=122"]))
	assert_eq(ok.status, 0, ok.text)
	var record := _record(ok.text)
	assert_false(record.is_empty(), "a record was printed")
	if not record.is_empty():
		assert_eq(int(record.job), 122)
		assert_eq(record.missing, [])
	var refused := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--cap=0.016666667", "--job=122", "--patch=" + patch]))
	assert_eq(refused.status, 2)
	assert_true(refused.text.contains("not playable"), refused.text)
	assert_true(_record(refused.text).is_empty())


func test_job_212_with_a_paladin_character_and_job_122_with_an_fp_character_are_errors() -> void:
	if not require_cache():
		return
	var paladin := _paladin_file()
	var base := PackedStringArray(["--stage=henesys", "--cap=0.016666667"])
	var a := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=212", "--character=" + paladin]))
	assert_eq(a.status, 2, a.text)
	assert_true(a.text.contains("does not match the character's job 122"), a.text)
	var b := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=122",
		"--character=" + ProjectSettings.globalize_path(FP_FIXTURE)]))
	assert_eq(b.status, 2, b.text)
	assert_true(b.text.contains("does not match the character's job 212"), b.text)
	var same := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=122", "--character=" + paladin]))
	assert_eq(same.status, 0, same.text)
	assert_eq(int(_record(same.text).job), 122, "a Paladin character runs as a Paladin")


func test_a_paladin_character_file_needs_no_job_flag() -> void:
	if not require_cache():
		return
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--cap=0.016666667", "--character=" + _paladin_file()]))
	assert_eq(run.status, 0, run.text)
	assert_eq(int(_record(run.text).job), 122, "the job comes from the character")


func test_the_fixture_tool_makes_a_shipped_paladin_and_refuses_a_disabled_job() -> void:
	if not require_cache():
		return
	var patch := _file("paladin_disabled.json", JSON.stringify(PATCH))
	var out := ProjectSettings.globalize_path(work_dir.path_join("paladin_kit.json"))
	var args := PackedStringArray(["--out=" + out, "--revision=0123456789012345678901234567890123456789", "--job=122",
		"--kit=1322004,1002001,1082002,1040010,1060002", "--tiers=2", "--label=test"])
	var refused := _tool("res://tools/character_fixture.gd", args + PackedStringArray(["--patch=" + patch]))
	assert_eq(refused.status, 2, refused.text)
	assert_true(refused.text.contains("not playable"), refused.text)
	assert_false(FileAccess.file_exists(out))
	var made := _tool("res://tools/character_fixture.gd", args)
	assert_eq(made.status, 0, made.text)
	var errors := PackedStringArray()
	var character := DataRepo.load_character(out, errors)
	assert_eq(errors, PackedStringArray())
	if character.is_empty():
		return
	assert_eq(int(character.job_id), 122)
	assert_eq(character.cleared_regions, ["ellinia", "henesys", "kerning", "perion"], "--tiers=2 (the compatibility alias) clears the four Victoria regions")
	assert_eq(int(character.equipment.worn.weapon.id), 1322004)
	assert_false(character._doc.has("patch"), "shipped Paladin needs no patch")


func test_the_committed_fixture_is_a_format_three_paladin_with_a_blunt_weapon_and_tier_two() -> void:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(PALADIN_FIXTURE, errors)
	assert_eq(errors, PackedStringArray())
	if character.is_empty():
		return
	assert_eq(int(character.format), 3)
	assert_eq(int(character.job_id), 122)
	assert_eq(int(character.tiers_unlocked), 2, "tier 2 is unlocked")
	assert_eq(CharacterSnapshot.validation_error(character), "")
	assert_eq(String(character._doc.revision).length(), 40)
	assert_eq(int(character._doc.job), 122)
	assert_false(character._doc.has("patch"), "the shipped playable fixture needs no external patch")
	assert_eq(int(character.equipment.worn.weapon.id), 1322004, "a Lv25 Mace")
	assert_eq(WeaponInfo.family(1322004), "blunt")
	assert_eq(Equipment.worn_ids(character.equipment.worn), [1002001, 1040010, 1060002, 1072001, 1082002, 1322004])
	assert_eq(character.scrolls, {})
	assert_eq(int(character.mesos), 0)


func test_the_fixture_and_a_fresh_paladin_start_with_power_strike_in_slot_one_and_rush_learned() -> void:
	var fixture: Dictionary = DataRepo.load_json(PALADIN_FIXTURE)
	fixture.erase("_doc")
	for character: Dictionary in [fixture, DataRepo.load_json(_paladin_file())]:
		var setup := RF.with_basic_attack(RF.setup("quiet", 317, RF.quiet_data()))
		var w := RF.world_from(setup, character.duplicate(true))
		assert_eq(w.job_id(), 122, "the job comes from the character")
		assert_eq(String(w.loadout.order[0]), "power_strike", "slot 1")
		assert_true(w.loadout.has("rush_paladin"), "Rush is learned at round start")
		assert_eq(w.book.slot("rush_paladin"), "mobility", "outside the slots")
	var forced := RF.with_basic_attack(RF.setup("quiet", 317, RF.quiet_data()))
	forced["job"] = 122
	var w2 := RunWorld.new(forced)
	assert_eq(String(w2.loadout.order[0]), "power_strike")
	assert_true(w2.loadout.has("rush_paladin"))


func test_the_fixture_starts_a_paladin_round_without_a_job_flag() -> void:
	if not require_cache():
		return
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=sleepywood", "--seed=2", "--cap=0.016666667",
		"--character=" + ProjectSettings.globalize_path(PALADIN_FIXTURE)]))
	assert_eq(run.status, 0, run.text)
	var record := _record(run.text)
	assert_false(record.is_empty(), "a record was printed")
	if record.is_empty():
		return
	assert_eq(int(record.job), 122, "the job comes from the character")
	assert_eq(record.start_character.cleared_regions, ["ellinia", "henesys", "kerning", "perion"], "the fixture's tier 2 migrates to the four Victoria regions")
	assert_eq(record.missing, [])
	assert_eq(record.warnings, [])
