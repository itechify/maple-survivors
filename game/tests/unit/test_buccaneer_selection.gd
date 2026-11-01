extends TestCase
## `--job=512` through the tools (spec #412, B11 #423): the run flags, balance_run, the fixture tool, the committed fixture and
## a `--character` of another job. Buccaneer ships playable; the refusal cases disable it with an explicit patch.

const PATCH := {"jobs_survivor": {"jobs": {"512": {"playable": false}}}}
const FP_FIXTURE := "res://tests/fixtures/characters/fp_arch_mage.json"
const BUC_FIXTURE := "res://tests/fixtures/characters/buccaneer_t2.json"
const KNUCKLE := 1482000

var work_dir := TestCase.test_dir("buccaneer_selection")


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


## A Buccaneer (512) character file in the creation outfit with synthetic item stats.
func _buccaneer_file() -> String:
	var imgs := {}
	for id: int in [1040002, 1060002, 1072001, KNUCKLE]:
		imgs[AvatarRenderer.part_img_path(id)] = {"info": {"tuc": 7, "incPAD": 18, "incPDD": 2}}
	var character := SceneFlow.new_character({}, 512, func(path: String) -> Dictionary: return imgs.get(path, {}))
	return _file("buccaneer.json", JSON.stringify(character))


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


func test_run_flags_carry_job_512_and_the_error_names_the_unplayable_job() -> void:
	var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys", "--job=512", "--seed=3"]))
	assert_eq(int(parsed.options.job), 512)
	assert_eq(RunLauncher.options_from_args({"job": "512"}).job, 512)
	assert_eq(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()), "", "shipped Buccaneer is playable")
	DataRepo.patch = PATCH.duplicate(true)
	assert_true(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()).contains("not playable"))
	assert_eq(SceneFlow.forced_job_error({"job": 212}, DataRepo.load_all()), "")
	assert_eq(SceneFlow.forced_job_error({"job": 112}, DataRepo.load_all()), "")


func test_balance_run_accepts_job_512_and_refuses_an_explicitly_disabled_job() -> void:
	if not require_cache():
		return
	var patch := _file("buccaneer_disabled.json", JSON.stringify(PATCH))
	var ok := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--seed=1", "--cap=0.016666667", "--job=512"]))
	assert_eq(ok.status, 0, ok.text)
	var record := _record(ok.text)
	assert_false(record.is_empty(), "a record was printed")
	if not record.is_empty():
		assert_eq(int(record.job), 512)
		assert_eq(record.missing, [])
	var refused := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--cap=0.016666667", "--job=512", "--patch=" + patch]))
	assert_eq(refused.status, 2)
	assert_true(refused.text.contains("not playable"), refused.text)
	assert_true(_record(refused.text).is_empty())


func test_job_212_with_a_buccaneer_character_and_job_512_with_an_fp_character_are_errors() -> void:
	if not require_cache():
		return
	var buc := _buccaneer_file()
	var base := PackedStringArray(["--stage=henesys", "--cap=0.016666667"])
	var a := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=212", "--character=" + buc]))
	assert_eq(a.status, 2, a.text)
	assert_true(a.text.contains("does not match the character's job 512"), a.text)
	var b := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=512",
		"--character=" + ProjectSettings.globalize_path(FP_FIXTURE)]))
	assert_eq(b.status, 2, b.text)
	assert_true(b.text.contains("does not match the character's job 212"), b.text)
	var same := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=512", "--character=" + buc]))
	assert_eq(same.status, 0, same.text)
	assert_eq(int(_record(same.text).job), 512, "a Buccaneer character runs as a Buccaneer")


func test_a_buccaneer_character_file_needs_no_job_flag() -> void:
	if not require_cache():
		return
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--cap=0.016666667", "--character=" + _buccaneer_file()]))
	assert_eq(run.status, 0, run.text)
	assert_eq(int(_record(run.text).job), 512, "the job comes from the character")


func test_the_fixture_tool_makes_a_shipped_buccaneer_and_refuses_a_disabled_job() -> void:
	if not require_cache():
		return
	var patch := _file("buccaneer_disabled.json", JSON.stringify(PATCH))
	var out := ProjectSettings.globalize_path(work_dir.path_join("buccaneer_kit.json"))
	var args := PackedStringArray(["--out=" + out, "--revision=0123456789012345678901234567890123456789", "--job=512",
		"--kit=1482001,1002001,1082002,1040010", "--tiers=2", "--label=test"])
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
	assert_eq(int(character.job_id), 512)
	assert_eq(character.cleared_regions, ["ellinia", "henesys", "kerning", "perion"], "--tiers=2 (the compatibility alias) clears the four Victoria regions")
	var worn := Equipment.worn_ids(character.equipment.worn)
	for id: int in [1482001, 1002001, 1082002, 1040010]:
		assert_true(id in worn, "%d is worn" % id)
	assert_eq(int(character.equipment.worn.weapon.id), 1482001)
	assert_false(character._doc.has("patch"), "shipped Buccaneer needs no patch")


func test_the_committed_fixture_is_a_format_three_buccaneer_from_a_god_henesys_clear() -> void:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(BUC_FIXTURE, errors)
	assert_eq(errors, PackedStringArray())
	if character.is_empty():
		return
	assert_eq(int(character.format), 3)
	assert_eq(int(character.job_id), 512)
	assert_eq(int(character.tiers_unlocked), 2, "the clear unlocks tier 2")
	assert_eq(CharacterSnapshot.validation_error(character), "")
	var doc: Dictionary = character._doc
	assert_eq(int(doc.job), 512)
	assert_eq(int(doc.seed), 1)
	assert_eq(String(doc.policy), "bot")
	assert_eq(String(doc.stage), "henesys")
	assert_eq(String(doc.outcome), "CLEARED")
	assert_true(bool(doc.invulnerable), "a diagnostic clear (god), not survival evidence")
	assert_eq(String(doc.revision).length(), 40)
	assert_false(doc.has("patch"), "the shipped playable fixture needs no patch")
	var tree := _tree()
	var families: Array = tree.weapon_families(512)
	assert_eq(families, ["knuckle"])
	var weapon_id := int(character.equipment.worn.weapon.id)
	assert_eq(weapon_id / 1000, 1482, "the worn weapon is a knuckle (%d)" % weapon_id)


func _tree() -> JobTree:
	var data := DataRepo.load_all()
	return JobTree.from_data(data.jobs, data.jobs_survivor)


func test_the_fixture_starts_a_buccaneer_round_without_a_job_flag() -> void:
	if not require_cache():
		return
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=sleepywood", "--seed=2", "--cap=0.016666667",
		"--character=" + ProjectSettings.globalize_path(BUC_FIXTURE)]))
	assert_eq(run.status, 0, run.text)
	var record := _record(run.text)
	assert_false(record.is_empty(), "a record was printed")
	if record.is_empty():
		return
	assert_eq(int(record.job), 512, "the job comes from the character")
	assert_eq(record.start_character.cleared_regions, ["ellinia", "henesys", "kerning", "perion"], "the fixture's tier 2 migrates to the four Victoria regions")
	assert_eq(record.missing, [])
	assert_eq(record.warnings, [])
