extends TestCase
## SaveData's public persistence and character-slot lifecycle, using process-private scratch files only.

var save_path := test_dir("save_v2/save.json")
const RF := preload("res://tests/fixtures/run_fixtures.gd")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))


func after_each() -> void:
	TestCase.remove_tree(save_path.get_base_dir())


## A format-2 run snapshot as spec #32/#33 saved it: the whole build in `character`, a phase and a saved round.
static func format2_slot(name: String = "Old1", stage: String = "tree_that_grew_1") -> Dictionary:
	return {"name": name, "created": "2026-10-16T12:00:00Z", "tier": 1, "phase": "round", "rounds_played": 2,
		"tiers_cleared": 1, "stage": stage, "round_seed": 243,
		"character": {"format": 2, "level": 38, "exp": 17, "job_id": 210, "attributes": {}, "base_attributes": {},
			"earned_ap": 0, "base_hp": 100.0, "skills": {}, "skill_order": [], "player_mods": {}, "card_ranks": {},
			"fortune": 0.0, "base_fortune": 0.0, "look": {"skin": 0, "face": 20000, "hair": 30030},
			"equipment": {"worn": {}, "inventory": []}, "scrolls": {}, "mesos": 99}}


func test_a_format_two_save_moves_its_characters_to_the_history_unmigrated() -> void:
	var legacy := {"format": 2, "best": {"henesys": {"level": 20, "cleared": true}}, "runs": {"henesys": 2},
		"slots": [format2_slot("Old1"), null, format2_slot("Old2", "henesys")],
		"history": [{"name": "Ended1", "job_id": 200, "job_name": "Magician", "level": 38,
			"tiers_cleared": 1, "rounds_played": 2, "ending": "died", "stage": "henesys", "date": "2026-10-21"}],
		"account": {"nx": 700, "owned": [1000001]}}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var loaded := SaveData.new(save_path)
	assert_eq(loaded.last_error, OK)
	assert_eq(loaded.slots, [null, null, null], "no old character survives as a living one")
	assert_eq(loaded.history.size(), 3, "the old entry plus the two retired characters")
	assert_eq(loaded.history[0].name, "Ended1")
	assert_eq(JSON.parse_string(JSON.stringify(loaded.history[1])), {"name": "Old1", "job_id": 210.0, "job_name": "Wizard (Fire, Poison)",
		"level": 38.0, "stage": "ellinia", "ending": "retired", "date": "2026-10-16T12:00:00Z"})
	assert_eq(loaded.history[2].name, "Old2")
	assert_eq(loaded.history[2].stage, "henesys")
	assert_eq(loaded.best_for("henesys").level, 20, "bests, counts and the account carry over")
	assert_eq(loaded.runs_for("henesys"), 2)
	assert_eq(int(loaded.account.nx), 700)
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	assert_eq(int(disk.format), 3, "rewritten as format 3")
	assert_eq(disk.slots, [null, null, null])
	assert_eq(SaveData.new(save_path).history, JSON.parse_string(JSON.stringify(loaded.history)), "loading again changes nothing")
	assert_eq(JSON.parse_string(FileAccess.get_file_as_string(save_path)), disk)
	assert_eq(loaded.create_slot(snapshot("Old1")), 0, "a retired character's name and slot are free again")


func test_a_stored_tiers_unlocked_counter_becomes_the_cleared_set_on_load() -> void:
	var tier_one := snapshot("Tier1Char")
	tier_one.character.erase("cleared_regions")
	tier_one.character["tiers_unlocked"] = 1
	var tier_two := snapshot("Tier2Char")
	tier_two.character.erase("cleared_regions")
	tier_two.character["tiers_unlocked"] = 2
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": 3, "best": {}, "runs": {}, "slots": [tier_one, tier_two, null], "history": []}))
	file.close()
	var loaded := SaveData.new(save_path)
	assert_eq(loaded.last_error, OK)
	assert_eq(loaded.slot(0).character.cleared_regions, [])
	assert_eq(loaded.slot(1).character.cleared_regions, ["ellinia", "henesys", "kerning", "perion"])
	assert_false(loaded.slot(1).character.has("tiers_unlocked"))
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	assert_false(disk.slots[1].character.has("tiers_unlocked"), "the file is rewritten with the set")
	assert_eq(JSON.parse_string(FileAccess.get_file_as_string(save_path)), disk)


func test_legacy_region_keys_migrate_bests_counts_and_history_on_disk() -> void:
	var legacy := {"format": 2,
		"best": {"henesys_hg1": {"stage": "henesys_hg1", "level": 35}, "henesys": {"level": 20}},
		"runs": {"henesys_hg1": 8, "henesys": 2, "dark_cave": 3},
		"slots": [format2_slot("Old1", "tree_that_grew_1"), null, null],
		"history": [{"name": "Ended1", "job_id": 200, "job_name": "Magician", "level": 38,
			"tiers_cleared": 1, "rounds_played": 2, "ending": "died", "stage": "dark_cave", "date": "2026-10-21"}]}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var loaded := SaveData.new(save_path)
	assert_eq(loaded.last_error, OK)
	assert_eq(loaded.history[1].stage, "ellinia")
	assert_eq(loaded.best_for("henesys").level, 35)
	assert_eq(loaded.best_for("henesys_hg1").stage, "henesys")
	assert_eq(loaded.runs_for("henesys"), 10)
	assert_eq(loaded.runs_for("dark_cave"), 3)
	assert_eq(loaded.history[0].stage, "sleepywood")
	var migrated := FileAccess.get_file_as_string(save_path)
	for old: String in ["henesys_hg1", "tree_that_grew_1", "dark_cave"]:
		assert_false(migrated.contains(old), "legacy key removed: " + old)
	assert_eq(FileAccess.get_file_as_string(save_path), migrated, "migration is idempotent")


func test_format_one_converts_bests_and_counts_on_disk() -> void:
	var legacy := {"format": 1, "best": {"henesys": {"cleared": true, "level": 35, "kills": 4200}},
		"runs": {"henesys": 8, "ellinia": 2}}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var expected: Dictionary = JSON.parse_string(JSON.stringify(legacy))
	var save := SaveData.new(save_path)
	assert_eq(save.best_for("henesys"), expected.best.henesys)
	assert_eq(save.runs_for("henesys"), 8)
	assert_eq(save.runs_for("ellinia"), 2)
	var converted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	assert_eq(int(converted.format), 3)
	assert_eq(converted.get("slots"), [null, null, null])
	assert_eq(converted.get("history"), [])
	assert_eq(converted.best, expected.best)
	assert_eq(converted.runs, expected.runs)


func test_format_one_ignores_unvalidated_fields_from_later_formats() -> void:
	var legacy := {"format": 1, "best": {}, "runs": {"henesys": 3},
		"slots": [{}], "history": 7, "account": 42}
	var file := FileAccess.open(save_path + ".import", FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var loaded := SaveData.new(save_path)
	assert_eq(loaded.last_error, OK)
	assert_eq(loaded.slots, [null, null, null])
	assert_eq(loaded.history, [])
	assert_eq(loaded.account, Account.empty())
	assert_eq(loaded.runs_for("henesys"), 3)
	assert_eq(SaveData.new(save_path).slots, [null, null, null])


func test_corrupt_files_survive_replacement_and_repeated_corruption() -> void:
	for text: String in ["{broken first save", "{broken second save"]:
		var file := FileAccess.open(save_path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var save := SaveData.new(save_path)
		assert_true(save.best.is_empty())
		assert_eq(save.runs_for("henesys"), 0)
		assert_eq(FileAccess.get_file_as_string(save_path), text, "load preserves the original")
		assert_eq(save.save_file(), OK)
		var fresh: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		assert_eq(fresh.slots, [null, null, null])
	assert_eq(FileAccess.get_file_as_string(save_path + ".bad"), "{broken first save")
	assert_eq(FileAccess.get_file_as_string(save_path + ".bad.1"), "{broken second save")


func test_failed_writes_keep_the_previous_file_slots_history_and_bests() -> void:
	var save := SaveData.new(save_path)
	var boundary := snapshot()
	assert_eq(save.create_slot(boundary), 0)
	var bytes := FileAccess.get_file_as_string(save_path)
	# A real filesystem boundary failure, without mocking SaveData's implementation.
	var temporary := ProjectSettings.globalize_path(save_path + ".tmp")
	assert_eq(DirAccess.make_dir_absolute(temporary), OK)
	boundary.rounds_played = 1
	var summary := {"stage": "henesys", "cleared": true, "level": 35}
	assert_ne(save.update_slot(0, boundary), OK)
	assert_ne(save.finish_round(0, boundary, "cleared", "2026-10-16", summary), OK)
	assert_eq(save.create_slot(snapshot("Other2")), -1)
	assert_false(save.record(summary), "legacy record also reports a write failure")
	assert_ne(save.last_error, OK)
	assert_eq(int(save.slot(0).rounds_played), 0)
	assert_eq(save.slot(1), {})
	assert_eq(save.history, [])
	assert_eq(save.best_for("henesys"), {})
	assert_eq(save.runs_for("henesys"), 0)
	assert_eq(FileAccess.get_file_as_string(save_path), bytes)
	assert_eq(DirAccess.remove_absolute(temporary), OK)
	assert_eq(save.finish_round(0, boundary, "cleared", "2026-10-16", summary), OK)
	var loaded := SaveData.new(save_path)
	assert_eq(int(loaded.slot(0).rounds_played), 1, "the character stays after its round")
	assert_eq(loaded.history.size(), 1)
	assert_eq(loaded.runs_for("henesys"), 1)
	# Debris from an interrupted next write never replaces the committed save on load.
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	file.store_string("{half-written")
	file.close()
	assert_eq(SaveData.new(save_path).history, loaded.history)


func test_missing_primary_recovers_the_last_complete_save_after_interrupted_replacement() -> void:
	var save := SaveData.new(save_path)
	assert_eq(save.create_slot(snapshot()), 0)
	var boundary: Dictionary = save.slot(0)
	boundary.rounds_played = 1
	assert_eq(save.update_slot(0, boundary), OK)
	assert_true(FileAccess.file_exists(save_path + ".bak"), "a complete previous save survives replacement")
	# Godot's Windows rename removes the destination first. Simulate a crash in that gap.
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path)), OK)
	var recovered := SaveData.new(save_path)
	assert_eq(String(recovered.slot(0).get("name", "")), "Maple1")
	assert_eq(int(recovered.slot(0).get("rounds_played", -1)), 0)
	assert_eq(recovered.last_error, OK)
	assert_true(FileAccess.file_exists(save_path), "the primary is restored on recovery")
	assert_eq(SaveData.new(save_path).slot(0), recovered.slot(0))


func test_invalid_primary_recovers_backup_without_rotating_rejected_bytes() -> void:
	var save := SaveData.new(save_path)
	assert_eq(save.create_slot(snapshot()), 0)
	assert_eq(save.save_file(), OK)
	var good := FileAccess.get_file_as_string(save_path)
	assert_eq(DirAccess.copy_absolute(save_path, save_path + ".bak"), OK)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string('{"format":3,"best":{},"runs":{},"slots":[{},null,null],"history":[]}')
	file.close()
	var recovered := SaveData.new(save_path)
	assert_eq(recovered.slot(0).get("name"), "Maple1")
	assert_eq(FileAccess.get_file_as_string(save_path + ".bak"), good)
	assert_eq(recovered.save_file(), OK)
	assert_eq(FileAccess.get_file_as_string(save_path + ".bak"), good)
	assert_eq(SaveData.new(save_path).slot(0).get("name"), "Maple1")


func test_staged_invalid_imports_leave_both_committed_files_unchanged() -> void:
	var save := SaveData.new(save_path)
	assert_eq(save.create_slot(snapshot()), 0)
	assert_eq(save.set_account({"nx": 7, "owned": []}), OK)
	var primary := FileAccess.get_file_as_string(save_path)
	var backup := FileAccess.get_file_as_string(save_path + ".bak")
	var candidates: Array = []
	var base: Dictionary = JSON.parse_string(primary)
	var bad := base.duplicate(true)
	bad.slots[0] = {}
	candidates.append(bad)
	bad = base.duplicate(true)
	bad.account = {"nx": -1, "owned": []}
	candidates.append(bad)
	bad = base.duplicate(true)
	bad.history = [{}]
	candidates.append(bad)
	bad = base.duplicate(true)
	bad.format = 999
	candidates.append(bad)
	for candidate: Dictionary in candidates:
		var file := FileAccess.open(save_path + ".import", FileAccess.WRITE)
		file.store_string(JSON.stringify(candidate))
		file.close()
		var loaded := SaveData.new(save_path)
		assert_eq(loaded.slot(0).get("name"), "Maple1")
		assert_eq(FileAccess.get_file_as_string(save_path), primary)
		assert_eq(FileAccess.get_file_as_string(save_path + ".bak"), backup)
		assert_false(FileAccess.file_exists(save_path + ".import"), "rejection is consumed, not retried next launch")
		assert_eq(loaded.save_file(), OK)
		assert_eq(FileAccess.get_file_as_string(save_path), primary)
		assert_eq(FileAccess.get_file_as_string(save_path + ".bak"), backup)


func test_valid_staged_import_is_validated_and_promoted_once() -> void:
	var save := SaveData.new(save_path)
	assert_eq(save.create_slot(snapshot()), 0)
	var original := FileAccess.get_file_as_string(save_path)
	var candidate: Dictionary = JSON.parse_string(original)
	candidate.slots[0].name = "Import1"
	var file := FileAccess.open(save_path + ".import", FileAccess.WRITE)
	file.store_string(JSON.stringify(candidate))
	file.close()
	var loaded := SaveData.new(save_path)
	assert_eq(loaded.slot(0).get("name"), "Import1")
	assert_eq(FileAccess.get_file_as_string(save_path + ".bak"), original)
	assert_false(FileAccess.file_exists(save_path + ".import"))
	assert_eq(SaveData.new(save_path).slot(0), loaded.slot(0))


func test_failed_import_promotion_blocks_mutations_until_the_candidate_is_consumed() -> void:
	var save := SaveData.new(save_path)
	assert_eq(save.create_slot(snapshot()), 0)
	var primary := FileAccess.get_file_as_string(save_path)
	var candidate: Dictionary = JSON.parse_string(primary)
	candidate.slots[0].name = "Import1"
	var file := FileAccess.open(save_path + ".import", FileAccess.WRITE)
	file.store_string(JSON.stringify(candidate))
	file.close()
	assert_eq(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(save_path + ".tmp")), OK)
	var loaded := SaveData.new(save_path)
	assert_ne(loaded.last_error, OK)
	assert_eq(loaded.slot(0).get("name"), "Maple1")
	assert_eq(FileAccess.get_file_as_string(save_path), primary)
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + ".tmp")), OK)
	assert_ne(loaded.set_account({"nx": 12, "owned": []}), OK, "pending import must not replay over subsequent mutations")
	assert_eq(FileAccess.get_file_as_string(save_path), primary)
	assert_eq(SaveData.new(save_path).slot(0).get("name"), "Import1", "a restart can retry the promotion safely")


static func snapshot(name: String = "Maple1") -> Dictionary:
	return {"name": name, "created": "2026-10-16T12:00:00Z", "rounds_played": 0,
		"character": RF.quiet_world().character_snapshot()}


func test_slot_create_update_reload_preserves_the_format_three_character() -> void:
	var save := SaveData.new(save_path)
	var boundary := snapshot()
	boundary.character.mesos = 4321
	boundary.character.scrolls = {"2043700": 3}
	boundary.character.cleared_regions = ["henesys"]
	boundary.character.look = {"skin": 0, "face": 20000, "hair": 30030}
	assert_eq(save.create_slot(boundary), 0, SaveData.validation_error(boundary))
	boundary.rounds_played = 1
	boundary.character.mesos = 5000
	assert_eq(save.update_slot(0, boundary), OK, SaveData.validation_error(boundary))
	var loaded := SaveData.new(save_path)
	var expected: Dictionary = JSON.parse_string(JSON.stringify(boundary, "", true, true))
	assert_eq(loaded.slot(0), expected, "everything the character keeps survives JSON")
	assert_eq(int(loaded.slot(0).character.format), 3)
	var keys: Array = loaded.slot(0).keys()
	keys.sort()
	assert_eq(keys, ["character", "created", "name", "rounds_played"], "no phase, tier, stage or round seed is saved")
	assert_eq(loaded.slot(1), {})
	# Callers cannot mutate a boundary without a successful update.
	boundary.character.mesos = 99
	var copy: Dictionary = loaded.slot(0)
	copy.character.look.clear()
	assert_eq(int(save.slot(0).character.mesos), 5000)
	assert_eq(loaded.slot(0).character.look.hair, 30030.0)
	assert_false(FileAccess.file_exists(save_path + ".tmp"), "temporary is consumed by replacement")


func test_full_slots_reject_fourth_character_without_changing_the_save() -> void:
	var save := SaveData.new(save_path)
	for index in 3:
		assert_eq(save.create_slot(snapshot("Maple%d" % index)), index)
	var bytes := FileAccess.get_file_as_string(save_path)
	assert_eq(save.create_slot(snapshot("Maple4")), -1)
	assert_ne(save.last_error, OK)
	assert_eq(FileAccess.get_file_as_string(save_path), bytes)
	assert_eq(SaveData.new(save_path).slots.size(), 3)
	assert_eq(save.slot(-1), {})
	assert_eq(save.slot(3), {})
	assert_eq(save.update_slot(3, snapshot()), ERR_INVALID_PARAMETER)


func test_deleting_a_character_frees_its_slot_and_archives_one_history_entry() -> void:
	var save := SaveData.new(save_path)
	for round in 2:
		var run := snapshot()
		run.character.job_id = 210
		assert_eq(save.create_slot(run), 0, "a deleted slot can be reused: " + SaveData.validation_error(run))
		assert_eq(save.delete_slot(0, "2026-10-16T13:00:00Z"), OK)
		assert_eq(save.slot(0), {})
		assert_eq(save.delete_slot(0, "2026-10-16T13:00:00Z"), ERR_INVALID_PARAMETER)
	var loaded := SaveData.new(save_path)
	assert_eq(loaded.slots, [null, null, null])
	assert_eq(loaded.history.size(), 2)
	assert_eq(loaded.history[0], {"name": "Maple1", "job_id": 210.0, "job_name": "Wizard (Fire, Poison)",
		"level": 1.0, "stage": "", "ending": "deleted", "date": "2026-10-16T13:00:00Z"})
	var detached := loaded.history
	detached.clear()
	assert_eq(loaded.history.size(), 2)


func test_every_round_keeps_its_character_and_adds_one_history_entry_with_bests_counts_and_nx() -> void:
	var save := SaveData.new(save_path)
	var boundary := snapshot()
	assert_eq(save.create_slot(boundary), 0)
	var first := {"stage": "henesys", "cleared": true, "time": 967.8, "level": 38,
		"job_id": 212, "job_name": "Arch Mage (Fire, Poison)", "kills": 4200, "seed": 1, "nx_awarded": 300}
	boundary.rounds_played = 1
	boundary.character.mesos = 777
	boundary.character.cleared_regions = ["henesys"]
	assert_eq(save.finish_round(0, boundary, "cleared", "2026-10-16T13:00:00Z", first), OK, SaveData.validation_error(boundary))
	var loaded := SaveData.new(save_path)
	assert_eq(loaded.runs_for("henesys"), 1)
	assert_eq(int(loaded.best_for("henesys").kills), 4200)
	assert_eq(int(loaded.account.nx), 300)
	assert_eq(int(loaded.slot(0).character.mesos), 777, "the character keeps what the round gave")
	assert_eq(loaded.slot(0).character.cleared_regions, ["henesys"], "the cleared set is written in the same single write")
	var last := {"stage": "sleepywood", "cleared": false, "time": 350.0, "level": 45, "kills": 1200, "nx_awarded": 50}
	boundary.rounds_played = 2
	assert_eq(loaded.finish_round(0, boundary, "died", "2026-10-16T14:00:00Z", last), OK)
	loaded = SaveData.new(save_path)
	assert_eq(loaded.slot(0).name, "Maple1", "a death does not end the character")
	assert_eq(int(loaded.slot(0).rounds_played), 2)
	assert_eq(loaded.history.size(), 2, "one entry per round")
	assert_eq(loaded.history[0], {"name": "Maple1", "job_id": 212.0, "job_name": "Arch Mage (Fire, Poison)", "level": 38.0,
		"stage": "henesys", "ending": "cleared", "date": "2026-10-16T13:00:00Z"})
	assert_eq(loaded.history[1].ending, "died")
	assert_eq(loaded.history[1].stage, "sleepywood")
	assert_eq(int(loaded.history[1].level), 45, "the level reached, from the round")
	assert_eq(loaded.runs_for("sleepywood"), 1)
	assert_eq(loaded.runs_for("henesys"), 1)
	assert_eq(int(loaded.best_for("sleepywood").level), 45)
	assert_eq(int(loaded.account.nx), 350)


func test_invalid_snapshots_and_duplicate_living_names_cannot_replace_characters() -> void:
	var save := SaveData.new(save_path)
	assert_eq(save.create_slot(snapshot()), 0)
	var bytes := FileAccess.get_file_as_string(save_path)
	assert_eq(save.create_slot(snapshot("maple1")), -1, "living names are unique without case")
	var invalid: Array[Dictionary] = [
		{"character": {}}, {"character": {"format": {}}}, {"name": "A!"}, {"created": ""},
		{"rounds_played": -1}, {"rounds_played": 0.5}, {"character": {"format": 2}},
		{"character": {"format": 1, "job_id": 0, "beginner_weapon": 0, "look": {}}},
		{"character": {"format": 3, "job_id": 212, "look": {}, "equipment": Equipment.empty_state(),
			"scrolls": {}, "mesos": 0, "cleared_regions": "henesys"}},
		{"character": {"format": 3, "job_id": 212, "look": {}, "equipment": Equipment.empty_state(),
			"scrolls": {}, "mesos": 0, "tiers_unlocked": 0}},
		{"character": {"format": 3, "job_id": 212, "look": {"position": Vector2.ZERO},
			"equipment": Equipment.empty_state(), "scrolls": {}, "mesos": 0, "cleared_regions": []}},
		{"character": {"format": 3, "job_id": 212, "look": {"scale": INF},
			"equipment": Equipment.empty_state(), "scrolls": {}, "mesos": 0, "cleared_regions": []}}]
	for patch: Dictionary in invalid:
		var bad := snapshot("Other2")
		bad.merge(patch, true)
		assert_eq(save.create_slot(bad), -1, "invalid creation: " + str(patch))
		assert_eq(save.update_slot(0, bad), ERR_INVALID_DATA)
		assert_eq(save.finish_round(0, bad, "died", "2026-10-16", {"stage": "henesys"}), ERR_INVALID_DATA)
	assert_eq(save.finish_round(0, snapshot(), "retired", "2026-10-16", {}), ERR_INVALID_PARAMETER, "not a round ending")
	assert_eq(save.finish_round(0, snapshot(), "died", "", {}), ERR_INVALID_PARAMETER)
	assert_eq(save.delete_slot(0, ""), ERR_INVALID_PARAMETER)
	assert_eq(FileAccess.get_file_as_string(save_path), bytes)
	assert_eq(save.slots.size(), 3)
	assert_eq(save.history, [])


func test_malformed_save_shapes_are_preserved_without_loading_partial_characters() -> void:
	var valid := {"format": 3, "best": {}, "runs": {}, "slots": [snapshot(), null, null], "history": []}
	var cases: Array = [[], {"format": {}}, {"format": 99}, {"format": 3.5},
		{"format": 3, "slots": "bad"}]
	for patch: Dictionary in [{"slots": [snapshot()]}, {"slots": [{}, null, null]},
		{"slots": [snapshot(), snapshot("maple1"), null]}, {"history": {}}, {"history": [{}]},
		{"best": []}, {"runs": {"henesys": []}}]:
		var bad := valid.duplicate(true)
		bad.merge(patch, true)
		cases.append(bad)
	for index in cases.size():
		var path := save_path.get_base_dir().path_join("bad_%d.json" % index)
		var bytes := JSON.stringify(cases[index])
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(bytes)
		file.close()
		var save := SaveData.new(path)
		assert_eq(save.slots, [null, null, null], "bad file %d starts empty" % index)
		assert_eq(save.history, [])
		assert_eq(FileAccess.get_file_as_string(path + ".bad"), bytes)
		assert_eq(save.save_file(), OK)
