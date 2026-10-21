extends TestCase
## Persistent-save ownership uses disposable files; tool saves deliberately remain independent of that ownership.

const SAVE_TEST := preload("res://tests/unit/test_save_data.gd")
var save_path := test_dir("save_writer/save.json")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))


func after_each() -> void:
	TestCase.remove_tree(save_path.get_base_dir())


func test_second_persistent_session_cannot_erase_the_owners_character() -> void:
	var script: GDScript = load("res://scripts/core/save_data.gd")
	var first: SaveData = script.new(save_path, true)
	var second: SaveData = script.new(save_path, true)
	assert_eq(first.create_slot(SAVE_TEST.snapshot("TabOne")), 0)
	var bytes := FileAccess.get_file_as_string(save_path)
	assert_eq(second.set_account({"nx": 20, "owned": []}), ERR_ALREADY_IN_USE)
	assert_eq(second.save_file(), ERR_ALREADY_IN_USE)
	assert_eq(FileAccess.get_file_as_string(save_path), bytes)
	first = null
	var takeover: SaveData = script.new(save_path, true)
	assert_eq(takeover.slot(0).get("name"), "TabOne", "takeover reloads committed state")
	assert_eq(takeover.set_account({"nx": 30, "owned": []}), OK)
	assert_eq(takeover.slot(0).get("name"), "TabOne")


func test_dead_pid_lock_is_recovered_and_custom_tool_files_do_not_take_the_lock() -> void:
	var lock_path := ProjectSettings.globalize_path(save_path + ".lock")
	assert_eq(DirAccess.make_dir_absolute(lock_path), OK)
	var file := FileAccess.open(lock_path.path_join("2147483647.crashed.owner"), FileAccess.WRITE)
	file.store_string("synthetic crashed process")
	file.close()
	var script: GDScript = load("res://scripts/core/save_data.gd")
	var save: SaveData = script.new(save_path, true)
	assert_eq(save.create_slot(SAVE_TEST.snapshot()), 0)
	var tool_path := save_path.get_base_dir().path_join("driver_save.json")
	var tool_a := SaveData.new(tool_path)
	var tool_b := SaveData.new(tool_path)
	assert_eq(tool_a.save_file(), OK)
	assert_eq(tool_b.save_file(), OK)
	assert_false(DirAccess.dir_exists_absolute(tool_path + ".lock"))
	assert_eq(save.set_account({"nx": 10, "owned": []}), OK)
