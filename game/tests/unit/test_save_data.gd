extends TestCase
## SaveData's public persistence and character-slot lifecycle, using process-private scratch files only.

var save_path := test_dir("save_v2/save.json")
const RF := preload("res://tests/fixtures/run_fixtures.gd")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))


func after_each() -> void:
	TestCase.remove_tree(save_path.get_base_dir())


func test_format_one_converts_bests_and_counts_on_disk() -> void:
	var legacy := {"format": 1, "best": {"henesys_hg1": {"cleared": true, "level": 35, "kills": 4200}},
		"runs": {"henesys_hg1": 8, "tree_that_grew_1": 2}}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var expected: Dictionary = JSON.parse_string(JSON.stringify(legacy))
	var save := SaveData.new(save_path)
	assert_eq(save.best_for("henesys_hg1"), expected.best.henesys_hg1)
	assert_eq(save.runs_for("henesys_hg1"), 8)
	assert_eq(save.runs_for("tree_that_grew_1"), 2)
	var converted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	assert_eq(int(converted.format), 2)
	assert_eq(converted.get("slots"), [null, null, null])
	assert_eq(converted.get("history"), [])
	assert_eq(converted.best, expected.best)
	assert_eq(converted.runs, expected.runs)


func test_corrupt_files_survive_replacement_and_repeated_corruption() -> void:
	for text: String in ["{broken first save", "{broken second save"]:
		var file := FileAccess.open(save_path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var save := SaveData.new(save_path)
		assert_true(save.best.is_empty())
		assert_eq(save.runs_for("henesys_hg1"), 0)
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
	boundary.phase = "free_market"
	boundary.rounds_played = 1
	var summary := {"stage": "henesys_hg1", "cleared": true, "level": 35}
	assert_ne(save.update_slot(0, boundary, summary), OK)
	assert_ne(save.end_run(0, "victory", "2026-10-16", boundary, summary), OK)
	assert_eq(save.create_slot(snapshot("Other2")), -1)
	assert_false(save.record(summary), "legacy record also reports a write failure")
	assert_ne(save.last_error, OK)
	assert_eq(int(save.slot(0).rounds_played), 0)
	assert_eq(save.slot(1), {})
	assert_eq(save.history, [])
	assert_eq(save.best_for("henesys_hg1"), {})
	assert_eq(save.runs_for("henesys_hg1"), 0)
	assert_eq(FileAccess.get_file_as_string(save_path), bytes)
	assert_eq(DirAccess.remove_absolute(temporary), OK)
	assert_eq(save.end_run(0, "victory", "2026-10-16", boundary, summary), OK)
	var loaded := SaveData.new(save_path)
	assert_eq(loaded.slot(0), {})
	assert_eq(loaded.history.size(), 1)
	assert_eq(loaded.runs_for("henesys_hg1"), 1)
	# Debris from an interrupted next write never replaces the committed save on load.
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	file.store_string("{half-written")
	file.close()
	assert_eq(SaveData.new(save_path).history, loaded.history)


func test_missing_primary_recovers_the_last_complete_save_after_interrupted_replacement() -> void:
	var save := SaveData.new(save_path)
	assert_eq(save.create_slot(snapshot()), 0)
	var boundary: Dictionary = save.slot(0)
	boundary.phase = "free_market"
	assert_eq(save.update_slot(0, boundary), OK)
	assert_true(FileAccess.file_exists(save_path + ".bak"), "a complete previous save survives replacement")
	# Godot's Windows rename removes the destination first. Simulate a crash in that gap.
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path)), OK)
	var recovered := SaveData.new(save_path)
	assert_eq(String(recovered.slot(0).get("name", "")), "Maple1")
	assert_eq(String(recovered.slot(0).get("phase", "")), "map_select")
	assert_eq(recovered.last_error, OK)
	assert_true(FileAccess.file_exists(save_path), "the primary is restored on recovery")
	assert_eq(SaveData.new(save_path).slot(0), recovered.slot(0))


func test_invalid_primary_recovers_backup_without_rotating_rejected_bytes() -> void:
	var save := SaveData.new(save_path)
	assert_eq(save.create_slot(snapshot()), 0)
	assert_eq(save.save_file(), OK)
	var good := FileAccess.get_file_as_string(save_path)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string('{"format":2,"best":{},"runs":{},"slots":[{},null,null],"history":[]}')
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


static func snapshot(name: String = "Maple1") -> Dictionary:
	return {"name": name, "look": {"skin": 0, "face": 20000, "hair": 30030, "equips": [1040002]},
		"created": "2026-10-16T12:00:00Z", "character": RF.quiet_world().character_snapshot(),
		"tier": 0, "phase": "map_select", "rounds_played": 0, "tiers_cleared": 0}


func test_slot_create_update_reload_preserves_character_and_round_seed() -> void:
	var save := SaveData.new(save_path)
	var boundary := snapshot()
	assert_eq(save.create_slot(boundary), 0)
	boundary.phase = "round"
	boundary.stage = "henesys_hg1"
	boundary.round_seed = 2026
	boundary.character.exp = 17
	boundary.character.player_mods = {"max_hp": [0.0, 1.123456789012345]}
	assert_eq(save.update_slot(0, boundary), OK, SaveData.validation_error(boundary))
	var loaded := SaveData.new(save_path)
	var expected: Dictionary = JSON.parse_string(JSON.stringify(boundary, "", true, true))
	assert_eq(loaded.slot(0), expected, "all carried fields and precise modifiers survive JSON")
	assert_eq(int(loaded.slot(0).round_seed), 2026, "continue replays the selected seed")
	assert_eq(loaded.slot(1), {})
	# Callers cannot mutate a boundary without a successful update.
	boundary.character.exp = 99
	var copy: Dictionary = loaded.slot(0)
	copy.look.equips.clear()
	copy.character.exp = 100
	assert_eq(int(save.slot(0).character.exp), 17)
	assert_eq(loaded.slot(0).look.equips, [1040002.0])
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


func test_ending_each_run_frees_its_slot_and_persists_exactly_one_history_entry() -> void:
	var save := SaveData.new(save_path)
	for ending: String in ["died", "victory", "deleted"]:
		var run := snapshot()
		run.phase = "round"
		run.stage = "dark_cave"
		run.round_seed = 7
		run.character.job_id = 210
		run.character.level = 38
		run.rounds_played = 2
		run.tiers_cleared = 1
		assert_eq(save.create_slot(run), 0, "ended slots can be reused: " + SaveData.validation_error(run))
		assert_eq(save.end_run(0, ending, "2026-10-16T13:00:00Z"), OK)
		assert_eq(save.slot(0), {})
		assert_eq(save.end_run(0, ending, "2026-10-16T13:00:00Z"), ERR_INVALID_PARAMETER)
	var loaded := SaveData.new(save_path)
	assert_eq(loaded.slots, [null, null, null])
	assert_eq(loaded.history.size(), 3)
	for index in 3:
		assert_eq(loaded.history[index], {"name": "Maple1", "job_id": 210.0,
			"job_name": "Wizard (Fire, Poison)", "level": 38.0, "tiers_cleared": 1.0,
			"rounds_played": 2.0, "ending": ["died", "victory", "deleted"][index], "stage": "dark_cave",
			"date": "2026-10-16T13:00:00Z"})
	var detached := loaded.history
	detached.clear()
	assert_eq(loaded.history.size(), 3)


func test_finished_rounds_update_bests_counts_and_final_history_together() -> void:
	var save := SaveData.new(save_path)
	var boundary := snapshot()
	assert_eq(save.create_slot(boundary), 0)
	var first := {"stage": "henesys_hg1", "cleared": true, "time": 967.8, "level": 38,
		"job_id": 210, "job_name": "Wizard (Fire, Poison)", "kills": 4200, "seed": 1}
	boundary.phase = "free_market"
	boundary.tier = 1
	boundary.rounds_played = 1
	boundary.tiers_cleared = 1
	boundary.stage = "henesys_hg1"
	boundary.character.level = 38
	boundary.character.job_id = 210
	assert_eq(save.update_slot(0, boundary, first), OK, SaveData.validation_error(boundary))
	var loaded := SaveData.new(save_path)
	assert_eq(loaded.runs_for("henesys_hg1"), 1)
	assert_eq(int(loaded.best_for("henesys_hg1").kills), 4200)
	var last := {"stage": "dark_cave", "cleared": false, "time": 350.0, "level": 45, "kills": 1200}
	boundary.stage = "dark_cave"
	boundary.rounds_played = 2
	boundary.character.level = 45
	assert_eq(loaded.end_run(0, "died", "2026-10-16", boundary, last), OK)
	loaded = SaveData.new(save_path)
	assert_eq(loaded.slot(0), {})
	assert_eq(int(loaded.history[0].level), 45, "history uses the final character, not its old boundary")
	assert_eq(int(loaded.history[0].rounds_played), 2)
	assert_eq(loaded.runs_for("dark_cave"), 1)
	assert_eq(loaded.runs_for("henesys_hg1"), 1)
	assert_eq(int(loaded.best_for("dark_cave").level), 45)


func test_invalid_snapshots_and_duplicate_living_names_cannot_replace_characters() -> void:
	var save := SaveData.new(save_path)
	assert_eq(save.create_slot(snapshot()), 0)
	var bytes := FileAccess.get_file_as_string(save_path)
	assert_eq(save.create_slot(snapshot("maple1")), -1, "living names are unique without case")
	var invalid: Array[Dictionary] = [
		{"character": {}}, {"character": {"format": {}}}, {"name": "A!"}, {"created": ""},
		{"tier": -1}, {"tier": 0.5}, {"phase": "mid_round"}, {"look": []},
		{"rounds_played": -1}, {"tiers_cleared": "one"},
		{"phase": "round", "stage": "henesys_hg1"},
		{"phase": "round", "stage": "", "round_seed": 3},
		{"phase": "round", "stage": "henesys_hg1", "round_seed": 2.5},
		{"look": {"position": Vector2.ZERO}}, {"look": {"scale": INF}}]
	for patch: Dictionary in invalid:
		var bad := snapshot("Other2")
		bad.merge(patch, true)
		assert_eq(save.create_slot(bad), -1, "invalid creation: " + str(patch))
		assert_eq(save.update_slot(0, bad), ERR_INVALID_DATA)
		assert_eq(save.end_run(0, "died", "2026-10-16", bad), ERR_INVALID_DATA)
	assert_eq(save.end_run(0, "quit", "2026-10-16"), ERR_INVALID_PARAMETER)
	assert_eq(save.end_run(0, "died", ""), ERR_INVALID_PARAMETER)
	assert_eq(FileAccess.get_file_as_string(save_path), bytes)
	assert_eq(save.slots.size(), 3)
	assert_eq(save.history, [])


func test_malformed_save_shapes_are_preserved_without_loading_partial_characters() -> void:
	var valid := {"format": 2, "best": {}, "runs": {}, "slots": [snapshot(), null, null], "history": []}
	var cases: Array = [[], {"format": {}}, {"format": 99}, {"format": 2.5},
		{"format": 2, "slots": "bad"}]
	for patch: Dictionary in [{"slots": [snapshot()]}, {"slots": [{}, null, null]},
		{"slots": [snapshot(), snapshot("maple1"), null]}, {"history": {}}, {"history": [{}]},
		{"best": []}, {"runs": {"henesys_hg1": []}}]:
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
