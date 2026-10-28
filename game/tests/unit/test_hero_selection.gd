extends TestCase
## `--job=112` through the tools (spec #296, H9 #305): the run flags, balance_run, the fixture tool and a `--character` of the
## other job. Hero is `playable: false` in the shipped data until H10, so the accepting cases mirror the data with
## `DataRepo.patch` (in-process) or `--patch=<file>` (the tools' own flag); the refusing ones run against the shipped data.

const PATCH := {"jobs_survivor": {"jobs": {"112": {"playable": true}}}}
const FP_FIXTURE := "res://tests/fixtures/characters/fp_arch_mage.json"

var work_dir := TestCase.test_dir("hero_selection")


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


## A Hero (112) character file in the creation outfit with synthetic item stats.
func _hero_file() -> String:
	var imgs := {}
	for id: int in [1040002, 1060002, 1072001, 1302000]:
		imgs[AvatarRenderer.part_img_path(id)] = {"info": {"tuc": 7, "incPAD": 17, "incPDD": 2}}
	var character := SceneFlow.new_character({}, 112, func(path: String) -> Dictionary: return imgs.get(path, {}))
	return _file("hero.json", JSON.stringify(character))


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


func test_run_flags_carry_job_112_and_the_error_names_the_unplayable_job() -> void:
	var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys", "--job=112", "--seed=3"]))
	assert_eq(int(parsed.options.job), 112)
	assert_eq(RunLauncher.options_from_args({"job": "112"}).job, 112)
	var data := DataRepo.load_all()
	assert_true(SceneFlow.forced_job_error(parsed.options, data).contains("not playable"), "shipped Hero: H10 flips it")
	DataRepo.patch = PATCH.duplicate(true)
	assert_eq(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()), "", "--job=112 is valid once Hero is playable")
	assert_eq(SceneFlow.forced_job_error({"job": 212}, DataRepo.load_all()), "", "and --job=212 still is")


func test_balance_run_accepts_job_112_once_hero_is_playable_and_refuses_it_before() -> void:
	if not require_cache():
		return
	var patch := _file("hero_playable.json", JSON.stringify(PATCH))
	var ok := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--seed=1", "--cap=0.016666667", "--job=112", "--patch=" + patch]))
	assert_eq(ok.status, 0, ok.text)
	var record := _record(ok.text)
	assert_false(record.is_empty(), "a record was printed")
	if not record.is_empty():
		assert_eq(int(record.job), 112)
		assert_eq(record.missing, [])
	var refused := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--cap=0.016666667", "--job=112"]))
	assert_eq(refused.status, 2)
	assert_true(refused.text.contains("not playable"), refused.text)
	assert_true(_record(refused.text).is_empty())


func test_job_212_with_a_hero_character_and_job_112_with_an_arch_mage_character_are_errors() -> void:
	if not require_cache():
		return
	var patch := _file("hero_playable.json", JSON.stringify(PATCH))
	var hero := _hero_file()
	var base := PackedStringArray(["--stage=henesys", "--cap=0.016666667"])
	var a := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=212", "--character=" + hero]))
	assert_eq(a.status, 2, a.text)
	assert_true(a.text.contains("does not match the character's job 112"), a.text)
	var b := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=112", "--patch=" + patch,
		"--character=" + ProjectSettings.globalize_path(FP_FIXTURE)]))
	assert_eq(b.status, 2, b.text)
	assert_true(b.text.contains("does not match the character's job 212"), b.text)
	var same := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=112", "--patch=" + patch, "--character=" + hero]))
	assert_eq(same.status, 0, same.text)
	assert_eq(int(_record(same.text).job), 112, "a Hero character runs as a Hero")


func test_a_hero_character_file_needs_no_job_flag() -> void:
	if not require_cache():
		return
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--cap=0.016666667", "--character=" + _hero_file()]))
	assert_eq(run.status, 0, run.text)
	assert_eq(int(_record(run.text).job), 112, "the job comes from the character")


func test_the_fixture_tool_makes_a_hero_with_patch_and_refuses_it_without() -> void:
	if not require_cache():
		return
	var patch := _file("hero_playable.json", JSON.stringify(PATCH))
	var out := ProjectSettings.globalize_path(work_dir.path_join("hero_kit.json"))
	var args := PackedStringArray(["--out=" + out, "--revision=0123456789012345678901234567890123456789", "--job=112",
		"--kit=1302000,1002001,1082002,1040010", "--tiers=2", "--label=test"])
	var refused := _tool("res://tools/character_fixture.gd", args)
	assert_eq(refused.status, 2, refused.text)
	assert_true(refused.text.contains("not playable"), refused.text)
	assert_false(FileAccess.file_exists(out))
	var made := _tool("res://tools/character_fixture.gd", args + PackedStringArray(["--patch=" + patch]))
	assert_eq(made.status, 0, made.text)
	var errors := PackedStringArray()
	var character := DataRepo.load_character(out, errors)
	assert_eq(errors, PackedStringArray())
	if character.is_empty():
		return
	assert_eq(int(character.job_id), 112)
	assert_eq(int(character.tiers_unlocked), 2)
	var worn := Equipment.worn_ids(character.equipment.worn)
	for id: int in [1302000, 1002001, 1082002, 1040010]:
		assert_true(id in worn, "%d is worn" % id)
	assert_eq(int(character.equipment.worn.weapon.id), 1302000)
	assert_eq(character._doc.patch, "hero_playable.json", "the _doc records the patch the fixture was made with")
