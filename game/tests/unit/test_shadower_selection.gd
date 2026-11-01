extends TestCase
## `--job=422` through the tools (spec #425, SH13 #438): the run flags, balance_run, the fixture tool, the committed Shadower
## fixture and a `--character` of another job. Shadower is playable since SH14 #439, so every accepting case runs on the shipped
## data and the refusing cases use an "unplayable" patch (`--patch=` for the tools, `DataRepo.patch` in-process). Subprocess tests that play a round need the cache (`require_cache()`); the data-level checks run in CI.

const UNPLAYABLE := {"jobs_survivor": {"jobs": {"422": {"playable": false}}}}
const FP_FIXTURE := "res://tests/fixtures/characters/fp_arch_mage.json"
const SH_FIXTURE := "res://tests/fixtures/characters/shadower_t2.json"
## The tier-1 dagger kit: Iron Dagger (reqLevel 25, PAD 40) and the Thief-bit hat (30), shoes (20) and gloves (15), the starter top and bottom.
const KIT := [1332010, 1002171, 1072022, 1082029, 1040002, 1060002]

var work_dir := TestCase.test_dir("shadower_selection")


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


func _unplayable_patch() -> String:
	return _file("sh_unplayable.json", JSON.stringify(UNPLAYABLE))


## A Shadower (422) character file in the creation outfit (the Razor) with synthetic item stats.
func _shadower_file() -> String:
	var imgs := {}
	for id: int in [1040002, 1060002, 1072001, 1332005]:
		imgs[AvatarRenderer.part_img_path(id)] = {"info": {"tuc": 7, "incPAD": 20, "incPDD": 2}}
	var character := SceneFlow.new_character({}, 422, func(path: String) -> Dictionary: return imgs.get(path, {}))
	return _file("shadower.json", JSON.stringify(character))


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


func test_run_flags_name_422_accept_it_and_keep_212_the_default() -> void:
	var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys", "--job=422", "--seed=3"]))
	assert_eq(int(parsed.options.job), 422)
	assert_eq(RunLauncher.options_from_args({"job": "422"}).job, 422)
	assert_eq(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()), "", "shipped: Shadower is playable")
	assert_eq(SceneFlow.forced_job_error({"job": 212}, DataRepo.load_all()), "")
	assert_eq(DataRepo.jobs(DataRepo.load_all()).default_job(), 212, "the default stays 212 with Shadower playable")
	DataRepo.patch = UNPLAYABLE.duplicate(true)
	assert_true(SceneFlow.forced_job_error(parsed.options, DataRepo.load_all()).contains("not playable"), "refused through the unplayable patch")


func test_balance_run_accepts_shipped_422_and_refuses_it_with_the_unplayable_patch() -> void:
	if not require_cache():
		return
	var base := PackedStringArray(["--stage=henesys", "--seed=1", "--cap=0.016666667", "--job=422"])
	var refused := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--patch=" + _unplayable_patch()]))
	assert_eq(refused.status, 2, refused.text)
	assert_true(refused.text.contains("not playable"), refused.text)
	assert_true(_record(refused.text).is_empty())
	var ok := _tool("res://tools/balance_run.gd", base)
	assert_eq(ok.status, 0, ok.text)
	var record := _record(ok.text)
	assert_false(record.is_empty(), "a record was printed")
	if not record.is_empty():
		assert_eq(int(record.job), 422)


func test_job_212_with_a_shadower_character_and_job_422_with_an_arch_mage_character_are_errors() -> void:
	if not require_cache():
		return
	var sh := _shadower_file()
	var base := PackedStringArray(["--stage=henesys", "--cap=0.016666667"])
	var a := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=212", "--character=" + sh]))
	assert_eq(a.status, 2, a.text)
	assert_true(a.text.contains("does not match the character's job 422"), a.text)
	var b := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=422",
		"--character=" + ProjectSettings.globalize_path(FP_FIXTURE)]))
	assert_eq(b.status, 2, b.text)
	assert_true(b.text.contains("does not match the character's job 212"), b.text)
	var same := _tool("res://tools/balance_run.gd", base + PackedStringArray(["--job=422", "--character=" + sh]))
	assert_eq(same.status, 0, same.text)
	assert_eq(int(_record(same.text).job), 422, "a Shadower character runs as a Shadower")


func test_a_shadower_character_file_needs_no_job_flag() -> void:
	if not require_cache():
		return
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--cap=0.016666667",
		"--character=" + _shadower_file()]))
	assert_eq(run.status, 0, run.text)
	assert_eq(int(_record(run.text).job), 422, "the job comes from the character")


func test_the_fixture_tool_makes_a_shadower_and_refuses_it_with_the_unplayable_patch() -> void:
	if not require_cache():
		return
	var out := ProjectSettings.globalize_path(work_dir.path_join("sh_kit.json"))
	var args := PackedStringArray(["--out=" + out, "--revision=0123456789012345678901234567890123456789", "--job=422",
		"--kit=" + ",".join(KIT.map(func(id: int) -> String: return str(id))), "--cleared=4", "--label=test"])
	var refused := _tool("res://tools/character_fixture.gd", args + PackedStringArray(["--patch=" + _unplayable_patch()]))
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
	assert_eq(int(character.job_id), 422)
	assert_eq(character.cleared_regions, ["ellinia", "henesys", "kerning", "perion"], "--cleared=4 clears the four Victoria regions")
	assert_eq(int(character.equipment.worn.weapon.id), 1332010)
	assert_false(character._doc.has("patch"), "the shipped data needs no patch")


func test_the_committed_fixture_is_a_format_three_shadower_with_the_tier_one_dagger_kit() -> void:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(SH_FIXTURE, errors)
	assert_eq(errors, PackedStringArray())
	if character.is_empty():
		return
	assert_eq(int(character.format), CharacterSnapshot.FORMAT)
	assert_eq(int(character.job_id), 422)
	assert_eq(character.cleared_regions, ["ellinia", "henesys", "kerning", "perion"], "the four first regions cleared (Sleepywood open)")
	assert_eq(CharacterSnapshot.validation_error(character), "")
	var worn := Equipment.worn_ids(character.equipment.worn)
	worn.sort()
	var want := KIT.duplicate()
	want.sort()
	assert_eq(worn, want, "exactly the kit is worn")
	assert_eq(WeaponInfo.family(int(character.equipment.worn.weapon.id)), "dagger", "a dagger in hand")
	assert_eq(int(character.equipment.worn.weapon.stats.incPAD), 40, "the Iron Dagger's canonical PAD")
	assert_true(character.equipment.inventory.is_empty(), "the kit is what is worn")
	assert_true(character.scrolls.is_empty() and int(character.mesos) == 0, "unscrolled, no mesos")
	assert_eq(character._doc.job, 422)
	assert_false(character._doc.has("patch"), "regenerated with the shipped data (SH14): no playable patch")
	assert_eq((character._doc.kit as Array).map(func(id: Variant) -> int: return int(id)), KIT, "JSON parses ids as floats")
	assert_true(String(character._doc.revision).length() == 40)
	assert_true(String(character._doc.by).begins_with("spec425/"))


func test_the_fixture_gear_is_wearable_by_a_shadower_at_the_tier_one_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var levels := {1332010: 25, 1002171: 30, 1072022: 20, 1082029: 15}
	for id: int in KIT:
		var img := lib.img(AvatarRenderer.part_img_path(id))
		assert_true(img != null, "%d is in the cache" % id)
		if img != null:
			assert_eq(Equipment.requirement_error(img.root.get("info", {}), {"job_id": 422}), "", "a Shadower can wear %d" % id)
			if levels.has(id):
				assert_eq(int(img.root.info.reqLevel), levels[id], "%d keeps the tier-1 reqLevel" % id)


## SH14 #439: a tool round with `--job=422` and no `--character` wears the creation Razor, which no other starter list holds (it is not a
## MakeCharInfo option or a drop), so the setup must load its canonical info or Double Stab has no reach and the round kills nothing.
func test_the_setup_loads_the_creation_razor_of_every_playable_job() -> void:
	var data := DataRepo.load_all()
	var ids := DataRepo.starter_equipment_ids(data)
	var jobs := DataRepo.jobs(data)
	for job: int in jobs.playable_jobs():
		assert_true(jobs.creation_weapon(job) in ids, "the creation weapon of %d is loaded" % job)
	assert_true(1332005 in ids, "the Razor")


func test_a_dagger_gives_no_ammo_so_the_fixture_round_needs_no_projectile_sprite() -> void:
	var data := DataRepo.load_all()
	assert_eq(Ammo.item_for(data.ammo, "dagger", 422, 1), 0, "a dagger throws nothing")


func test_a_one_off_round_from_the_fixture_has_no_missing_assets() -> void:
	if not require_cache():
		return
	var run := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--seed=1", "--cap=20",
		"--character=" + ProjectSettings.globalize_path(SH_FIXTURE)]))
	assert_eq(run.status, 0, run.text)
	var record := _record(run.text)
	assert_false(record.is_empty())
	if not record.is_empty():
		assert_eq(int(record.job), 422)
		assert_eq(record.missing, [], "the dagger skills' art all resolves")


## SH14 #439: the record of a Shadower round carries the `shadower` measurement block (meso charge mean / peak, Dark Sight windows,
## casts and hits per skill, Smokescreen zones, negated hits); any other job's record has no such key, so its bytes are unchanged.
func test_a_shadower_record_carries_the_measurement_block_and_other_jobs_do_not() -> void:
	if not require_cache():
		return
	var sh := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--seed=1", "--cap=20", "--job=422",
		"--character=" + ProjectSettings.globalize_path(SH_FIXTURE)]))
	assert_eq(sh.status, 0, sh.text)
	var record := _record(sh.text)
	assert_true(record.has("shadower"), "a Shadower record has the block")
	if record.has("shadower"):
		var block: Dictionary = record.shadower
		for key: String in ["charge_mean", "charge_peak", "dark_sight_windows", "casts", "hits", "assassinate_crits", "zones", "negated_hits"]:
			assert_true(block.has(key), "the block has %s: %s" % [key, block])
		assert_true(float(block.charge_mean) >= 0.0 and int(block.charge_peak) <= 10)
	var bare := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--seed=1", "--cap=60", "--job=422"]))
	assert_eq(bare.status, 0, bare.text)
	var bare_record := _record(bare.text)
	if bare_record.has("shadower"):
		assert_true(int(bare_record.shadower.casts.get("double_stab", 0)) > 0, "a bare Shadower (the Razor) casts Double Stab: %s" % bare_record.shadower)
	var fp := _tool("res://tools/balance_run.gd", PackedStringArray(["--stage=henesys", "--seed=1", "--cap=5",
		"--character=" + ProjectSettings.globalize_path(FP_FIXTURE)]))
	assert_eq(fp.status, 0, fp.text)
	assert_false(_record(fp.text).has("shadower"), "an F/P record is unchanged")
