extends TestCase
## `--job=312` through the tools (spec #332, B12 #344): the run flags, balance_run, the fixture tool, the committed Bowmaster
## fixture and a `--character` of another job. Bowmaster ships `playable: false` until B13, so these mirror the flip with a
## patch file (`DataRepo.patch` in process, `--patch=` in a subprocess). Subprocess tests that play a round need the cache
## (`require_cache()`); the data-level checks run in CI.

const PLAYABLE := {"jobs_survivor": {"jobs": {"312": {"playable": true}}}}
const FP_FIXTURE := "res://tests/fixtures/characters/fp_arch_mage.json"
const BOW_FIXTURE := "res://tests/fixtures/characters/bowmaster_t2.json"
## The tier-1 bow kit: Battle Bow (reqLevel 25) and the Bowman-bit hat (30), shoes (20) and gloves (15), the starter top and bottom.
const KIT := [1452000, 1002163, 1072025, 1082012, 1040002, 1060002]

var work_dir := TestCase.test_dir("bowmaster_selection")


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


## A Bowmaster (312) character file in the creation outfit (War Bow) with synthetic item stats.
func _bowmaster_file() -> String:
	var imgs := {}
	for id: int in [1040002, 1060002, 1072001, 1452002]:
		imgs[AvatarRenderer.part_img_path(id)] = {"info": {"tuc": 7, "incPAD": 25, "incPDD": 2}}
	var character := SceneFlow.new_character({}, 312, func(path: String) -> Dictionary: return imgs.get(path, {}))
	return _file("bowmaster.json", JSON.stringify(character))


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


func test_run_flags_name_312_and_refuse_it_until_it_is_playable() -> void:
	var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys", "--job=312", "--seed=3"]))
	assert_eq(int(parsed.options.job), 312)
	assert_eq(RunLauncher.options_from_args({"job": "312"}).job, 312)
	assert_true(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()).contains("not playable"), "shipped Bowmaster is not playable until B13")
	DataRepo.patch = PLAYABLE.duplicate(true)
	assert_eq(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()), "")
	assert_eq(SceneFlow.forced_job_error({"job": 212}, DataRepo.load_all()), "", "and --job=212 still is")
	assert_eq(DataRepo.jobs(DataRepo.load_all()).default_job(), 212, "three playable jobs, the default stays 212")


func test_balance_run_accepts_312_with_a_patch_and_refuses_it_without() -> void:
	if not require_cache():
		return
	var patch := _file("bow_playable.json", JSON.stringify(PLAYABLE))
	var base := PackedStringArray(["--stage=henesys", "--seed=1", "--cap=0.016666667", "--job=312"])
	var refused := _tool("res://tools/balance_run.gd", base)
	assert_eq(refused.status, 2, refused.text)
	assert_true(refused.text.contains("not playable"), refused.text)
	assert_true(_record(refused.text).is_empty())
	var ok := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--patch=" + patch]))
	assert_eq(ok.status, 0, ok.text)
	var record := _record(ok.text)
	assert_false(record.is_empty(), "a record was printed")
	if not record.is_empty():
		assert_eq(int(record.job), 312)


func test_job_212_with_a_bowmaster_character_and_job_312_with_an_arch_mage_character_are_errors() -> void:
	if not require_cache():
		return
	var patch := PackedStringArray(["--patch=" + _file("bow_playable.json", JSON.stringify(PLAYABLE))])
	var bow := _bowmaster_file()
	var base := PackedStringArray(["--stage=henesys", "--cap=0.016666667"]) + patch
	var a := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=212", "--character=" + bow]))
	assert_eq(a.status, 2, a.text)
	assert_true(a.text.contains("does not match the character's job 312"), a.text)
	var b := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=312",
		"--character=" + ProjectSettings.globalize_path(FP_FIXTURE)]))
	assert_eq(b.status, 2, b.text)
	assert_true(b.text.contains("does not match the character's job 212"), b.text)
	var same := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=312", "--character=" + bow]))
	assert_eq(same.status, 0, same.text)
	assert_eq(int(_record(same.text).job), 312, "a Bowmaster character runs as a Bowmaster")


func test_a_bowmaster_character_file_needs_no_job_flag() -> void:
	if not require_cache():
		return
	var patch := _file("bow_playable.json", JSON.stringify(PLAYABLE))
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--cap=0.016666667",
		"--patch=" + patch, "--character=" + _bowmaster_file()]))
	assert_eq(run.status, 0, run.text)
	assert_eq(int(_record(run.text).job), 312, "the job comes from the character")


func test_the_fixture_tool_makes_a_bowmaster_with_a_patch_and_refuses_without() -> void:
	if not require_cache():
		return
	var patch := _file("bow_playable.json", JSON.stringify(PLAYABLE))
	var out := ProjectSettings.globalize_path(work_dir.path_join("bow_kit.json"))
	var args := PackedStringArray(["--out=" + out, "--revision=0123456789012345678901234567890123456789", "--job=312",
		"--kit=" + ",".join(KIT.map(func(id: int) -> String: return str(id))), "--tiers=2", "--label=test"])
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
	assert_eq(int(character.job_id), 312)
	assert_eq(int(character.tiers_unlocked), 2)
	assert_eq(int(character.equipment.worn.weapon.id), 1452000)
	assert_eq(String(character._doc.patch), "bow_playable.json", "the patch that was needed is recorded")


func test_the_committed_fixture_is_a_format_three_bowmaster_with_the_tier_one_bow_kit() -> void:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(BOW_FIXTURE, errors)
	assert_eq(errors, PackedStringArray())
	if character.is_empty():
		return
	assert_eq(int(character.format), CharacterSnapshot.FORMAT)
	assert_eq(int(character.job_id), 312)
	assert_eq(int(character.tiers_unlocked), 2, "tier 2 is open")
	assert_eq(CharacterSnapshot.validation_error(character), "")
	var worn := Equipment.worn_ids(character.equipment.worn)
	worn.sort()
	var want := KIT.duplicate()
	want.sort()
	assert_eq(worn, want, "exactly the kit is worn")
	assert_eq(WeaponInfo.family(int(character.equipment.worn.weapon.id)), "bow", "a bow in hand, otherwise ammo is 0 and the arrow sprite is missing")
	assert_true(character.equipment.inventory.is_empty(), "the kit is what is worn")
	assert_eq(character._doc.job, 312)
	assert_eq((character._doc.kit as Array).map(func(id: Variant) -> int: return int(id)), KIT, "JSON parses ids as floats")
	assert_true(String(character._doc.revision).length() == 40)
	assert_true(String(character._doc.by).begins_with("spec332/"))


func test_the_fixture_gear_is_wearable_by_a_bowmaster_and_its_bow_fires_ammo() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: int in KIT:
		var img := lib.img(AvatarRenderer.part_img_path(id))
		assert_true(img != null, "%d is in the cache" % id)
		if img != null:
			assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 312}), "", "a Bowmaster can wear %d" % id)
	var data := DataRepo.load_all()
	assert_true(Ammo.item_for(data.ammo, "bow", 312, 1) > 0, "a bow at Lv1 has ammo")


func test_a_one_off_round_from_the_fixture_has_arrows_and_no_missing_assets() -> void:
	if not require_cache():
		return
	var patch := _file("bow_playable.json", JSON.stringify(PLAYABLE))
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--seed=1", "--cap=20",
		"--patch=" + patch, "--character=" + ProjectSettings.globalize_path(BOW_FIXTURE)]))
	assert_eq(run.status, 0, run.text)
	var record := _record(run.text)
	assert_false(record.is_empty())
	if not record.is_empty():
		assert_eq(int(record.job), 312)
		assert_eq(record.missing, [], "the bow gives ammo: no `Consume/0000.img/00000000/bullet` lookup fails")
