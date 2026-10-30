extends TestCase
## `--job=132` through the tools (spec #348, D10 #358): the run flags, balance_run, the fixture tool, a `--character` of the
## other job, the committed fixture and a one-off round from it. All shipped jobs are playable; the refusal cases disable the
## Dark Knight with a patch. Subprocess tests need the cache and SKIP without it (a SKIP proves nothing).

const PATCH := {"jobs_survivor": {"jobs": {"132": {"playable": false}}}}
const FP_FIXTURE := "res://tests/fixtures/characters/fp_arch_mage.json"
const KNIGHT_FIXTURE := "res://tests/fixtures/characters/dark_knight_t2.json"

var work_dir := TestCase.test_dir("dark_knight_selection")


func before_each() -> void:
	TestCase.remove_tree(work_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(work_dir))


func after_each() -> void:
	DataRepo.patch = {}


func _file(file_name: String, text: String) -> String:
	var path := ProjectSettings.globalize_path(work_dir.path_join(file_name))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


## A Dark Knight (132) character file in the creation outfit with synthetic item stats.
func _knight_file() -> String:
	var imgs := {}
	for id: int in [1040002, 1060002, 1072001, 1432000]:
		imgs[AvatarRenderer.part_img_path(id)] = {"info": {"tuc": 7, "incPAD": 32, "incPDD": 2}}
	var character := SceneFlow.new_character({}, 132, func(path: String) -> Dictionary: return imgs.get(path, {}))
	return _file("knight.json", JSON.stringify(character))


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


func test_run_flags_accept_132_and_refuse_a_disabled_dark_knight() -> void:
	var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys", "--job=132", "--seed=3"]))
	assert_eq(int(parsed.options.job), 132)
	assert_eq(RunLauncher.options_from_args({"job": "132"}).job, 132)
	assert_eq(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()), "")
	DataRepo.patch = PATCH.duplicate(true)
	assert_true(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()).contains("not playable"))
	assert_eq(SceneFlow.forced_job_error({"job": 112}, DataRepo.load_all()), "", "Hero still is")
	assert_eq(SceneFlow.forced_job_error({"job": 212}, DataRepo.load_all()), "", "and so is the Arch Mage")


func test_balance_run_accepts_shipped_132_and_refuses_a_disabled_dark_knight() -> void:
	if not require_cache():
		return
	var patch := _file("dk_disabled.json", JSON.stringify(PATCH))
	var ok := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--seed=1", "--cap=0.016666667", "--job=132"]))
	assert_eq(ok.status, 0, ok.text)
	var record := _record(ok.text)
	assert_false(record.is_empty(), "a record was printed")
	if not record.is_empty():
		assert_eq(int(record.job), 132)
		assert_eq(record.missing, [])
	var refused := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--cap=0.016666667", "--job=132", "--patch=" + patch]))
	assert_eq(refused.status, 2)
	assert_true(refused.text.contains("not playable"), refused.text)
	assert_true(_record(refused.text).is_empty())


func test_job_212_with_a_dark_knight_character_and_job_132_with_an_arch_mage_character_are_errors() -> void:
	if not require_cache():
		return
	var knight := _knight_file()
	var base := PackedStringArray(["--stage=henesys", "--cap=0.016666667"])
	var a := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=212", "--character=" + knight]))
	assert_eq(a.status, 2, a.text)
	assert_true(a.text.contains("does not match the character's job 132"), a.text)
	var b := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=132",
		"--character=" + ProjectSettings.globalize_path(FP_FIXTURE)]))
	assert_eq(b.status, 2, b.text)
	assert_true(b.text.contains("does not match the character's job 212"), b.text)
	var same := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=132", "--character=" + knight]))
	assert_eq(same.status, 0, same.text)
	assert_eq(int(_record(same.text).job), 132, "a Dark Knight character runs as a Dark Knight")


func test_a_dark_knight_character_file_needs_no_job_flag() -> void:
	if not require_cache():
		return
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--cap=0.016666667", "--character=" + _knight_file()]))
	assert_eq(run.status, 0, run.text)
	assert_eq(int(_record(run.text).job), 132, "the job comes from the character")


func test_the_fixture_tool_makes_a_shipped_dark_knight_and_refuses_a_disabled_one() -> void:
	if not require_cache():
		return
	var patch := _file("dk_disabled.json", JSON.stringify(PATCH))
	var out := ProjectSettings.globalize_path(work_dir.path_join("dk_kit.json"))
	var args := PackedStringArray(["--out=" + out, "--revision=0123456789012345678901234567890123456789", "--job=132",
		"--kit=1432000,1002001,1082002,1040010", "--tiers=2", "--label=test"])
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
	assert_eq(int(character.job_id), 132)
	assert_eq(character.cleared_regions, ["ellinia", "henesys", "kerning", "perion"], "--tiers=2 (the compatibility alias) clears the four Victoria regions")
	assert_eq(int(character.equipment.worn.weapon.id), 1432000)
	assert_false(character._doc.has("patch"), "the shipped Dark Knight needs no patch")


# --- the committed fixture -----------------------------------------------------------------------------------------------

func test_the_dark_knight_fixture_is_format_three_from_a_diagnostic_tier_one_clear() -> void:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(KNIGHT_FIXTURE, errors)
	assert_eq(errors, PackedStringArray())
	assert_false(character.is_empty())
	if character.is_empty():
		return
	assert_eq(int(character.format), 3)
	assert_eq(int(character.job_id), 132)
	assert_eq(int(character.tiers_unlocked), 2)
	assert_eq(CharacterSnapshot.validation_error(character), "")
	var families: Array = DataRepo.load_all().jobs_survivor.jobs["132"].weapon_families
	assert_true(WeaponInfo.family(int(character.equipment.worn.weapon.id)) in families, "a spear or pole arm is worn")
	for id: int in Equipment.worn_ids(character.equipment.worn):
		assert_true(WeaponInfo.family(id) != "shield", "a Dark Knight wears no shield")
	assert_eq(character._doc.stage, "henesys")
	assert_eq(int(character._doc.seed), 1)
	assert_eq(character._doc.policy, "bot")
	assert_eq(character._doc.outcome, "CLEARED")
	assert_eq(int(character._doc.job), 132)
	assert_true(character._doc.invulnerable, "diagnostic fixture, never survival evidence")
	assert_eq(String(character._doc.revision).length(), 40)
	assert_false(character._doc.has("patch"), "the Dark Knight ships playable")
	for gone: String in ["level", "exp", "skills", "card_ranks", "attributes", "base_hp"]:
		assert_false(character.has(gone), "the fixture carries no " + gone)


func test_a_one_off_round_from_the_fixture_starts_a_dark_knight_with_spear_crusher_and_rush() -> void:
	if not require_cache():
		return
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=sleepywood", "--cap=0.016666667",
		"--character=" + ProjectSettings.globalize_path(KNIGHT_FIXTURE)]))
	assert_eq(run.status, 0, run.text)
	var record := _record(run.text)
	assert_false(record.is_empty())
	if record.is_empty():
		return
	assert_eq(int(record.job), 132)
	assert_eq(record.missing, [])
	assert_eq(record.warnings, [])
	assert_true(record.skills.has("spear_crusher"), "Spear Crusher is in slot 1")
	assert_true(record.skills.has("rush_dark_knight"), "Rush is on its key")
