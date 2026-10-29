extends TestCase
## Bishop (232) through the tools (spec #372, BS9 #381; the Bishop copy of test_il_selection): run flags, balance_run, fixture
## generation, mismatched characters and the committed fixture. Bishop is `playable: false` until BS10, so a patch that makes it
## playable (the one the fixture was made with) is passed wherever the job must be accepted, and the refusals run on the shipped data.

const PATCH := {"jobs_survivor": {"jobs": {"232": {"playable": true}}}}
const FP_FIXTURE := "res://tests/fixtures/characters/fp_arch_mage.json"
const BISHOP_FIXTURE := "res://tests/fixtures/characters/bishop_t2.json"

var work_dir := TestCase.test_dir("bishop_selection")


func before_each() -> void:
	TestCase.remove_tree(work_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(work_dir))


func after_each() -> void:
	DataRepo.patch = {}


## Absolute path of a file with `text` in the test directory.
func _file(file_name: String, text: String) -> String:
	var path := ProjectSettings.globalize_path(work_dir.path_join(file_name))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


func _patch_file() -> String:
	return _file("bishop_playable.json", JSON.stringify(PATCH))


## A Bishop (232) character file in the creation outfit with synthetic item stats.
func _bishop_file() -> String:
	var imgs := {}
	for id: int in [1040002, 1060002, 1072001, 1372005]:
		imgs[AvatarRenderer.part_img_path(id)] = {"info": {"tuc": 7, "incMAD": 17, "incPDD": 2}}
	var character := SceneFlow.new_character({}, 232, func(path: String) -> Dictionary: return imgs.get(path, {}))
	return _file("bishop.json", JSON.stringify(character))


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


func test_run_flags_carry_job_232_and_the_error_names_the_unplayable_job() -> void:
	var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys", "--job=232", "--seed=3"]))
	assert_eq(int(parsed.options.job), 232)
	assert_eq(RunLauncher.options_from_args({"job": "232"}).job, 232)
	assert_true(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()).contains("not playable"), "shipped Bishop is unplayable until BS10")
	DataRepo.patch = PATCH.duplicate(true)
	assert_eq(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()), "", "playable through the data alone")
	DataRepo.patch = {}
	for job: int in [212, 112, 222]:
		assert_eq(SceneFlow.forced_job_error({"job": job}, DataRepo.load_all()), "", "%d stays playable" % job)


func test_balance_run_accepts_job_232_with_the_playable_patch_and_refuses_it_without() -> void:
	if not require_cache():
		return
	var patch := _patch_file()
	var ok := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--seed=1", "--cap=0.016666667", "--job=232", "--patch=" + patch]))
	assert_eq(ok.status, 0, ok.text)
	var record := _record(ok.text)
	assert_false(record.is_empty(), "a record was printed")
	if not record.is_empty():
		assert_eq(int(record.job), 232)
		assert_eq(record.missing, [])
	var refused := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--cap=0.016666667", "--job=232"]))
	assert_eq(refused.status, 2)
	assert_true(refused.text.contains("not playable"), refused.text)
	assert_true(_record(refused.text).is_empty())


func test_job_212_with_a_bishop_character_and_job_232_with_an_fp_character_are_errors() -> void:
	if not require_cache():
		return
	var bishop := _bishop_file()
	var base := PackedStringArray(["--stage=henesys", "--cap=0.016666667", "--patch=" + _patch_file()])
	var a := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=212", "--character=" + bishop]))
	assert_eq(a.status, 2, a.text)
	assert_true(a.text.contains("does not match the character's job 232"), a.text)
	var b := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=232",
		"--character=" + ProjectSettings.globalize_path(FP_FIXTURE)]))
	assert_eq(b.status, 2, b.text)
	assert_true(b.text.contains("does not match the character's job 212"), b.text)
	var same := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=232", "--character=" + bishop]))
	assert_eq(same.status, 0, same.text)
	assert_eq(int(_record(same.text).job), 232, "a Bishop character runs as a Bishop")


func test_a_bishop_character_file_needs_no_job_flag() -> void:
	if not require_cache():
		return
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--cap=0.016666667",
		"--patch=" + _patch_file(), "--character=" + _bishop_file()]))
	assert_eq(run.status, 0, run.text)
	assert_eq(int(_record(run.text).job), 232, "the job comes from the character")


func test_the_fixture_tool_makes_a_bishop_with_the_patch_and_refuses_without_it() -> void:
	if not require_cache():
		return
	var out := ProjectSettings.globalize_path(work_dir.path_join("bishop_kit.json"))
	var args := PackedStringArray(["--out=" + out, "--revision=0123456789012345678901234567890123456789", "--job=232",
		"--kit=1382002,1002013,1072019,1082019", "--tiers=2", "--label=test"])
	var refused := _tool("res://tools/character_fixture.gd", args)
	assert_eq(refused.status, 2, refused.text)
	assert_true(refused.text.contains("not playable"), refused.text)
	assert_false(FileAccess.file_exists(out))
	var made := _tool("res://tools/character_fixture.gd", args + PackedStringArray(["--patch=" + _patch_file()]))
	assert_eq(made.status, 0, made.text)
	var errors := PackedStringArray()
	var character := DataRepo.load_character(out, errors)
	assert_eq(errors, PackedStringArray())
	if character.is_empty():
		return
	assert_eq(int(character.job_id), 232)
	assert_eq(int(character.tiers_unlocked), 2)
	var worn := Equipment.worn_ids(character.equipment.worn)
	for id: int in [1382002, 1002013, 1072019, 1082019]:
		assert_true(id in worn, "%d is worn" % id)
	assert_eq(int(character.equipment.worn.weapon.id), 1382002)
	assert_eq(String(character._doc.patch), "bishop_playable.json", "the playable patch is recorded")


func test_the_committed_fixture_is_a_format_three_bishop_with_the_tier_one_kit() -> void:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(BISHOP_FIXTURE, errors)
	assert_eq(errors, PackedStringArray())
	if character.is_empty():
		return
	assert_eq(int(character.format), 3)
	assert_eq(int(character.job_id), 232)
	assert_eq(int(character.tiers_unlocked), 2, "tier 2 is unlocked")
	assert_eq(CharacterSnapshot.validation_error(character), "")
	assert_eq(String(character._doc.revision).length(), 40)
	var kit: Array = character._doc.kit.map(func(id: Variant) -> int: return int(id))
	assert_eq(kit, [1382002, 1002013, 1072019, 1082019, 1040002, 1060002], "the same tier-1 kit as the F/P fixture")
	assert_eq(int(character._doc.job), 232)
	assert_eq(String(character._doc.patch), "bishop_playable.json", "made while Bishop is unplayable: the patch is recorded")
	assert_eq(Equipment.worn_ids(character.equipment.worn), [1002013, 1040002, 1060002, 1072019, 1082019, 1382002])
	var fp: Dictionary = DataRepo.load_json(FP_FIXTURE)
	assert_eq(character.equipment, fp.equipment, "the gear is F/P's (a Bishop wears the same wands and staves)")
	assert_eq(character.scrolls, {})
	assert_eq(int(character.mesos), 0)


func test_the_fixture_starts_a_bishop_round_without_a_job_flag() -> void:
	if not require_cache():
		return
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=sleepywood", "--seed=2", "--cap=0.016666667",
		"--patch=" + _patch_file(), "--character=" + ProjectSettings.globalize_path(BISHOP_FIXTURE)]))
	assert_eq(run.status, 0, run.text)
	var record := _record(run.text)
	assert_false(record.is_empty(), "a record was printed")
	if record.is_empty():
		return
	assert_eq(int(record.job), 232, "the job comes from the character")
	assert_eq(int(record.start_character.tiers_unlocked), 2)
	assert_eq(record.missing, [])
	assert_eq(record.warnings, [])
