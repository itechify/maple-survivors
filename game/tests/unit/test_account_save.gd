extends TestCase
## The Account block of the save (#115, spec #34): an optional top-level `account` key, FORMAT stays 2 (seams.md);
## a save without it is an empty account. NX from a finished round is credited inside the same atomic write as the
## round-boundary snapshot or the run archive.

const SAVE_TESTS := preload("res://tests/unit/test_save_data.gd")

var save_path := test_dir("account_save/save.json")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))


func after_each() -> void:
	TestCase.remove_tree(save_path.get_base_dir())


func _write_file(value: Variant) -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()


func test_file_without_account_loads_an_empty_account_and_saves_it_back() -> void:
	_write_file({"format": 3, "best": {}, "runs": {}, "slots": [SAVE_TESTS.snapshot(), null, null], "history": []})
	var save := SaveData.new(save_path)
	assert_eq(save.account, {"nx": 0, "owned": []})
	assert_eq(save.slot(0).name, "Maple1", "the file still loads in full")
	assert_false(FileAccess.file_exists(save_path + ".bad"))
	assert_eq(save.save_file(), OK)
	var written: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	assert_eq(int(written.format), 3)
	assert_eq(Account.normalized(written.account), Account.empty())


func test_format_one_converts_to_an_empty_account() -> void:
	_write_file({"format": 1, "best": {}, "runs": {"henesys": 3}})
	var converted := SaveData.new(save_path)
	assert_eq(converted.account, {"nx": 0, "owned": []})
	assert_eq(Account.normalized(JSON.parse_string(FileAccess.get_file_as_string(save_path)).account), Account.empty())


func test_account_round_trips_and_is_detached() -> void:
	var save := SaveData.new(save_path)
	assert_eq(save.set_account({"nx": 1234, "owned": [1812002, 9990000]}), OK)
	var loaded := SaveData.new(save_path)
	assert_eq(loaded.account, {"nx": 1234, "owned": [1812002, 9990000]})
	assert_true(loaded.account.nx is int and loaded.account.owned[0] is int, "JSON floats come back as ints")
	var copy: Dictionary = loaded.account
	copy.nx = 5
	copy.owned.clear()
	assert_eq(loaded.account.nx, 1234, "callers get a detached view")
	assert_eq(loaded.create_slot(SAVE_TESTS.snapshot()), 0)
	assert_eq(SaveData.new(save_path).account, {"nx": 1234, "owned": [1812002, 9990000]}, "other writes keep it")


func test_malformed_accounts_are_rejected_and_corrupt_files_preserved() -> void:
	var save := SaveData.new(save_path)
	for bad: Variant in [{"nx": -1, "owned": []}, {"nx": 1.5, "owned": []}, {"nx": "5", "owned": []},
			{"nx": 0}, {"nx": 0, "owned": [1, 1]}, {"nx": 0, "owned": ["a"]}, {"nx": 0, "owned": [-3]}, [], 7]:
		assert_eq(save.set_account(bad), ERR_INVALID_DATA, JSON.stringify(bad))
	assert_eq(save.account, {"nx": 0, "owned": []})
	var broken := {"format": 3, "best": {}, "runs": {}, "slots": [null, null, null], "history": [],
		"account": {"nx": -4, "owned": []}}
	_write_file(broken)
	var loaded := SaveData.new(save_path)
	assert_eq(loaded.account, {"nx": 0, "owned": []})
	assert_eq(FileAccess.get_file_as_string(save_path + ".bad"), JSON.stringify(broken),
		"the bad block is preserved like any corrupt file")


func test_round_nx_is_credited_in_the_same_write_as_the_slot_for_every_round_ending() -> void:
	var save := SaveData.new(save_path)
	save.set_account({"nx": 10, "owned": [5000000]})
	assert_eq(save.create_slot(SAVE_TESTS.snapshot()), 0)
	var boundary := SAVE_TESTS.snapshot()
	boundary.rounds_played = 1
	assert_eq(save.finish_round(0, boundary, "cleared", "2026-10-16",
		{"stage": "henesys", "cleared": true, "level": 20, "nx_awarded": 140}), OK)
	var loaded := SaveData.new(save_path)
	assert_eq(loaded.account, {"nx": 150, "owned": [5000000]})
	assert_eq(int(loaded.slot(0).rounds_played), 1)
	assert_eq(loaded.update_slot(0, boundary), OK, "a hub save credits nothing")
	assert_eq(loaded.account.nx, 150)
	assert_eq(loaded.finish_round(0, boundary, "died", "2026-10-16", {"stage": "henesys", "level": 21, "nx_awarded": 60}), OK)
	assert_eq(loaded.finish_round(0, boundary, "quit", "2026-10-16", {"stage": "henesys", "level": 3, "nx_awarded": 5}), OK)
	var ended := SaveData.new(save_path)
	assert_eq(ended.account.nx, 215, "a death and a quit pay too")
	assert_eq(ended.history.size(), 3)
	assert_eq(ended.slot(0).name, "Maple1", "the character stays")


func test_deleting_a_character_credits_nothing() -> void:
	var save := SaveData.new(save_path)
	save.set_account({"nx": 10, "owned": []})
	assert_eq(save.create_slot(SAVE_TESTS.snapshot()), 0)
	assert_eq(save.delete_slot(0, "2026-10-16"), OK)
	assert_eq(SaveData.new(save_path).account.nx, 10)


func test_failed_writes_do_not_credit_nx() -> void:
	var save := SaveData.new(save_path)
	assert_eq(save.create_slot(SAVE_TESTS.snapshot()), 0)
	var temporary := ProjectSettings.globalize_path(save_path + ".tmp")
	assert_eq(DirAccess.make_dir_absolute(temporary), OK)
	assert_ne(save.finish_round(0, SAVE_TESTS.snapshot(), "died", "2026-10-16", {"stage": "henesys", "nx_awarded": 40}), OK)
	assert_ne(save.set_account({"nx": 7, "owned": []}), OK)
	assert_eq(save.account.nx, 0)
	assert_eq(DirAccess.remove_absolute(temporary), OK)
