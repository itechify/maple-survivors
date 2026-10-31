extends TestCase
## `--job=412` through the tools (spec #383, NL11 #410): the run flags, balance_run, the fixture tool, the committed Night Lord
## fixture and a `--character` of another job. Night Lord ships `playable: true` since NL12 #411, so every accepting case uses the
## shipped data and the refusing cases make it unplayable again with a patch file (`--patch=` / `DataRepo.patch`).
## Subprocess tests that play a round need the cache (`require_cache()`); the data-level checks run in CI.

const UNPLAYABLE := {"jobs_survivor": {"jobs": {"412": {"playable": false}}}}
const FP_FIXTURE := "res://tests/fixtures/characters/fp_arch_mage.json"
const NL_FIXTURE := "res://tests/fixtures/characters/night_lord_t2.json"
## The tier-1 claw kit: Meba (reqLevel 25) and the Thief-bit hat (30), shoes (20) and gloves (15), the starter top and bottom.
const KIT := [1472007, 1002171, 1072022, 1082029, 1040002, 1060002]

var work_dir := TestCase.test_dir("night_lord_selection")


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


## A Night Lord (412) character file in the creation outfit (Garnier) with synthetic item stats.
func _night_lord_file() -> String:
	var imgs := {}
	for id: int in [1040002, 1060002, 1072001, 1472000]:
		imgs[AvatarRenderer.part_img_path(id)] = {"info": {"tuc": 7, "incPAD": 10, "incPDD": 2}}
	var character := SceneFlow.new_character({}, 412, func(path: String) -> Dictionary: return imgs.get(path, {}))
	return _file("night_lord.json", JSON.stringify(character))


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


func test_run_flags_name_412_accept_it_and_refuse_it_when_unplayable() -> void:
	var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys", "--job=412", "--seed=3"]))
	assert_eq(int(parsed.options.job), 412)
	assert_eq(RunLauncher.options_from_args({"job": "412"}).job, 412)
	assert_eq(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()), "", "shipped playable")
	assert_eq(SceneFlow.forced_job_error({"job": 212}, DataRepo.load_all()), "")
	assert_eq(DataRepo.jobs(DataRepo.load_all()).default_job(), 212, "the default stays 212 with Night Lord playable")
	DataRepo.patch = UNPLAYABLE.duplicate(true)
	assert_true(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()).contains("not playable"), "unplayable again")
	assert_eq(DataRepo.jobs(DataRepo.load_all()).default_job(), 212)


func test_balance_run_accepts_shipped_412_and_refuses_it_with_an_unplayable_patch() -> void:
	if not require_cache():
		return
	var patch := _file("nl_unplayable.json", JSON.stringify(UNPLAYABLE))
	var base := PackedStringArray(["--stage=henesys", "--seed=1", "--cap=0.016666667", "--job=412"])
	var refused := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--patch=" + patch]))
	assert_eq(refused.status, 2, refused.text)
	assert_true(refused.text.contains("not playable"), refused.text)
	assert_true(_record(refused.text).is_empty())
	var ok := _tool("res://tools/balance_run.gd", base)
	assert_eq(ok.status, 0, ok.text)
	var record := _record(ok.text)
	assert_false(record.is_empty(), "a record was printed")
	if not record.is_empty():
		assert_eq(int(record.job), 412)


func test_job_212_with_a_night_lord_character_and_job_412_with_an_arch_mage_character_are_errors() -> void:
	if not require_cache():
		return
	var nl := _night_lord_file()
	var base := PackedStringArray(["--stage=henesys", "--cap=0.016666667"])
	var a := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=212", "--character=" + nl]))
	assert_eq(a.status, 2, a.text)
	assert_true(a.text.contains("does not match the character's job 412"), a.text)
	var b := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=412",
		"--character=" + ProjectSettings.globalize_path(FP_FIXTURE)]))
	assert_eq(b.status, 2, b.text)
	assert_true(b.text.contains("does not match the character's job 212"), b.text)
	var same := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=412", "--character=" + nl]))
	assert_eq(same.status, 0, same.text)
	assert_eq(int(_record(same.text).job), 412, "a Night Lord character runs as a Night Lord")


func test_a_night_lord_character_file_needs_no_job_flag() -> void:
	if not require_cache():
		return
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--cap=0.016666667",
		"--character=" + _night_lord_file()]))
	assert_eq(run.status, 0, run.text)
	assert_eq(int(_record(run.text).job), 412, "the job comes from the character")


func test_the_fixture_tool_makes_a_night_lord_from_shipped_data_and_refuses_it_when_unplayable() -> void:
	if not require_cache():
		return
	var out := ProjectSettings.globalize_path(work_dir.path_join("nl_kit.json"))
	var args := PackedStringArray(["--out=" + out, "--revision=0123456789012345678901234567890123456789", "--job=412",
		"--kit=" + ",".join(KIT.map(func(id: int) -> String: return str(id))), "--tiers=2", "--label=test"])
	var patch := _file("nl_unplayable.json", JSON.stringify(UNPLAYABLE))
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
	assert_eq(int(character.job_id), 412)
	assert_eq(character.cleared_regions, ["ellinia", "henesys", "kerning", "perion"], "--tiers=2 (the compatibility alias) clears the four Victoria regions")
	assert_eq(int(character.equipment.worn.weapon.id), 1472007)
	assert_false(character._doc.has("patch"), "shipped Night Lord needs no patch")


func test_the_committed_fixture_is_a_format_three_night_lord_with_the_tier_one_claw_kit() -> void:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(NL_FIXTURE, errors)
	assert_eq(errors, PackedStringArray())
	if character.is_empty():
		return
	assert_eq(int(character.format), CharacterSnapshot.FORMAT)
	assert_eq(int(character.job_id), 412)
	assert_eq(int(character.tiers_unlocked), 2, "tier 2 is open")
	assert_eq(CharacterSnapshot.validation_error(character), "")
	var worn := Equipment.worn_ids(character.equipment.worn)
	worn.sort()
	var want := KIT.duplicate()
	want.sort()
	assert_eq(worn, want, "exactly the kit is worn")
	assert_eq(WeaponInfo.family(int(character.equipment.worn.weapon.id)), "claw", "a claw in hand, otherwise the stars have no sprite")
	assert_eq(int(character.equipment.worn.weapon.stats.incPAD), 16, "the Meba's canonical PAD")
	assert_true(character.equipment.inventory.is_empty(), "the kit is what is worn")
	assert_true(character.scrolls.is_empty() and int(character.mesos) == 0, "unscrolled, no mesos")
	assert_eq(character._doc.job, 412)
	assert_eq((character._doc.kit as Array).map(func(id: Variant) -> int: return int(id)), KIT, "JSON parses ids as floats")
	assert_true(String(character._doc.revision).length() == 40)
	assert_true(String(character._doc.by).begins_with("spec383/"))


func test_the_fixture_gear_is_wearable_by_a_night_lord_and_its_claw_throws_stars() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for id: int in KIT:
		var img := lib.img(AvatarRenderer.part_img_path(id))
		assert_true(img != null, "%d is in the cache" % id)
		if img != null:
			assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 412}), "", "a Night Lord can wear %d" % id)
	var data := DataRepo.load_all()
	assert_eq(Ammo.item_for(data.ammo, "claw", 412, 1), 2070015, "a claw at Lv1 throws the Beginner Thief's stars")
	assert_eq(Ammo.item_for(data.ammo, "claw", 412, 60), 2070006, "and steps up to Ilbi by Lv60")


func test_a_one_off_round_from_the_fixture_has_stars_and_no_missing_assets() -> void:
	if not require_cache():
		return
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--seed=1", "--cap=20",
		"--character=" + ProjectSettings.globalize_path(NL_FIXTURE)]))
	assert_eq(run.status, 0, run.text)
	var record := _record(run.text)
	assert_false(record.is_empty())
	if not record.is_empty():
		assert_eq(int(record.job), 412)
		assert_eq(record.missing, [], "the claw gives ammo: no star sprite lookup fails")
