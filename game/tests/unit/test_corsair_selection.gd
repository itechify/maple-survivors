extends TestCase
## `--job=522` through the tools (spec #384, C14 #398): the run flags, balance_run, the fixture tool, the committed Corsair
## fixture and a `--character` of another job. Corsair ships `playable: true` (C15 #399); the refusal cases turn it off again
## with a patch file (`--patch=` / `DataRepo.patch`).
## Subprocess tests that play a round need the cache (`require_cache()`); the data-level checks run in CI.

const UNPLAYABLE := {"jobs_survivor": {"jobs": {"522": {"playable": false}}}}
const FP_FIXTURE := "res://tests/fixtures/characters/fp_arch_mage.json"
const COR_FIXTURE := "res://tests/fixtures/characters/corsair_t2.json"
## The tier-1 gun kit: the Lv25 pistol 1492003 (same reqLevel as the F/P staff) and the closest all-job hat (25), shoes (21) and gloves (10) the cache holds (it has no Pirate-bit armour), the starter top and bottom.
const KIT := [1492003, 1002096, 1072017, 1082002, 1040002, 1060002]

var work_dir := TestCase.test_dir("corsair_selection")


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


## A Corsair (522) character file in the creation outfit (Pistol) with synthetic item stats.
func _corsair_file() -> String:
	var imgs := {}
	for id: int in [1040002, 1060002, 1072001, 1492000]:
		imgs[AvatarRenderer.part_img_path(id)] = {"info": {"tuc": 7, "incPAD": 10, "incPDD": 2}}
	var character := SceneFlow.new_character({}, 522, func(path: String) -> Dictionary: return imgs.get(path, {}))
	return _file("corsair.json", JSON.stringify(character))


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


func test_run_flags_name_522_and_accept_it_unless_a_patch_turns_it_off() -> void:
	var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys", "--job=522", "--seed=3"]))
	assert_eq(int(parsed.options.job), 522)
	assert_eq(RunLauncher.options_from_args({"job": "522"}).job, 522)
	assert_eq(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()), "", "shipped: playable")
	assert_eq(SceneFlow.forced_job_error({"job": 212}, DataRepo.load_all()), "")
	assert_eq(DataRepo.jobs(DataRepo.load_all()).default_job(), 212, "the default stays 212")
	DataRepo.patch = UNPLAYABLE.duplicate(true)
	assert_true(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()).contains("not playable"))
	assert_eq(DataRepo.jobs(DataRepo.load_all()).default_job(), 212, "and with Corsair unplayable")


func test_balance_run_accepts_shipped_522_and_refuses_it_with_a_patch_that_turns_it_off() -> void:
	if not require_cache():
		return
	var patch := _file("corsair_unplayable.json", JSON.stringify(UNPLAYABLE))
	var base := PackedStringArray(["--stage=henesys", "--seed=1", "--cap=0.016666667", "--job=522"])
	var refused := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--patch=" + patch]))
	assert_eq(refused.status, 2, refused.text)
	assert_true(refused.text.contains("not playable"), refused.text)
	assert_true(_record(refused.text).is_empty())
	var ok := _tool("res://tools/balance_run.gd", base)
	assert_eq(ok.status, 0, ok.text)
	var record := _record(ok.text)
	assert_false(record.is_empty(), "a record was printed")
	if not record.is_empty():
		assert_eq(int(record.job), 522)


func test_job_212_with_a_corsair_character_and_job_522_with_an_arch_mage_character_are_errors() -> void:
	if not require_cache():
		return
	var corsair := _corsair_file()
	var base := PackedStringArray(["--stage=henesys", "--cap=0.016666667"])
	var a := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=212", "--character=" + corsair]))
	assert_eq(a.status, 2, a.text)
	assert_true(a.text.contains("does not match the character's job 522"), a.text)
	var b := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=522",
		"--character=" + ProjectSettings.globalize_path(FP_FIXTURE)]))
	assert_eq(b.status, 2, b.text)
	assert_true(b.text.contains("does not match the character's job 212"), b.text)
	var same := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=522", "--character=" + corsair]))
	assert_eq(same.status, 0, same.text)
	assert_eq(int(_record(same.text).job), 522, "a Corsair character runs as a Corsair")


func test_a_corsair_character_file_needs_no_job_flag() -> void:
	if not require_cache():
		return
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--cap=0.016666667",
		"--character=" + _corsair_file()]))
	assert_eq(run.status, 0, run.text)
	assert_eq(int(_record(run.text).job), 522, "the job comes from the character")


func test_the_fixture_tool_makes_a_corsair_from_shipped_data_and_refuses_it_with_a_patch_that_turns_it_off() -> void:
	if not require_cache():
		return
	var out := ProjectSettings.globalize_path(work_dir.path_join("corsair_kit.json"))
	var args := PackedStringArray(["--out=" + out, "--revision=0123456789012345678901234567890123456789", "--job=522",
		"--kit=" + ",".join(KIT.map(func(id: int) -> String: return str(id))), "--tiers=2", "--label=test"])
	var patch := _file("corsair_unplayable.json", JSON.stringify(UNPLAYABLE))
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
	assert_eq(int(character.job_id), 522)
	assert_eq(int(character.tiers_unlocked), 2)
	assert_eq(int(character.equipment.worn.weapon.id), 1492003)
	assert_false(character._doc.has("patch"), "no patch was needed")


func test_the_committed_fixture_is_a_format_three_corsair_with_the_tier_one_gun_kit() -> void:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(COR_FIXTURE, errors)
	assert_eq(errors, PackedStringArray())
	if character.is_empty():
		return
	assert_eq(int(character.format), CharacterSnapshot.FORMAT)
	assert_eq(int(character.job_id), 522)
	assert_eq(int(character.tiers_unlocked), 2, "tier 2 is open")
	assert_eq(CharacterSnapshot.validation_error(character), "")
	var worn := Equipment.worn_ids(character.equipment.worn)
	worn.sort()
	var want := KIT.duplicate()
	want.sort()
	assert_eq(worn, want, "exactly the kit is worn")
	assert_eq(WeaponInfo.family(int(character.equipment.worn.weapon.id)), "gun", "a gun in hand, otherwise the bullets have no sprite")
	assert_eq(int(character.equipment.worn.weapon.stats.incPAD), 27, "the Lv25 pistol's canonical PAD")
	assert_true(character.equipment.inventory.is_empty(), "the kit is what is worn")
	assert_true(character.scrolls.is_empty() and int(character.mesos) == 0, "unscrolled, no mesos")
	assert_eq(character._doc.job, 522)
	assert_eq((character._doc.kit as Array).map(func(id: Variant) -> int: return int(id)), KIT, "JSON parses ids as floats")
	assert_true(String(character._doc.revision).length() == 40)
	assert_true(String(character._doc.by).begins_with("spec384/"))


func test_the_fixture_gear_is_wearable_by_a_corsair_and_its_gun_fires_bullets() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: int in KIT:
		var img := lib.img(AvatarRenderer.part_img_path(id))
		assert_true(img != null, "%d is in the cache" % id)
		if img != null:
			assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 522}), "", "a Corsair can wear %d" % id)
	var data := DataRepo.load_all()
	assert_eq(Ammo.item_for(data.ammo, "gun", 522, 1), 2330000, "a gun at Lv1 fires the first bullets")
	assert_eq(Ammo.item_for(data.ammo, "gun", 522, 18), 2330001, "steps up to the Split Bullet at Lv18")
	assert_eq(Ammo.item_for(data.ammo, "gun", 522, 35), 2330002, "and to the Mighty Bullet at Lv35")



func test_a_one_off_round_from_the_fixture_has_bullets_and_no_missing_assets() -> void:
	if not require_cache():
		return
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--seed=1", "--cap=20",
		"--character=" + ProjectSettings.globalize_path(COR_FIXTURE)]))
	assert_eq(run.status, 0, run.text)
	var record := _record(run.text)
	assert_false(record.is_empty())
	if not record.is_empty():
		assert_eq(int(record.job), 522)
		assert_eq(record.missing, [], "the gun gives ammo: no bullet sprite lookup fails")
