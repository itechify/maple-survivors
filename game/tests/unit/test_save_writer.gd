extends TestCase
## Persistent-save ownership uses disposable files; tool saves deliberately remain independent of that ownership.

const SAVE_TEST := preload("res://tests/unit/test_save_data.gd")
var save_path := test_dir("save_writer/save.json")
var now := 1000000.0


func persistent_save() -> SaveData:
	var script: GDScript = load("res://scripts/core/save_data.gd")
	return script.new(save_path, true, func() -> float: return now)


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))


func after_each() -> void:
	TestCase.remove_tree(save_path.get_base_dir())


func test_second_persistent_session_cannot_erase_the_owners_character() -> void:
	var first := persistent_save()
	var second := persistent_save()
	assert_eq(first.create_slot(SAVE_TEST.snapshot("TabOne")), 0)
	var bytes := FileAccess.get_file_as_string(save_path)
	assert_eq(second.set_account({"nx": 20, "owned": []}), ERR_ALREADY_IN_USE)
	assert_eq(second.save_file(), ERR_ALREADY_IN_USE)
	assert_eq(FileAccess.get_file_as_string(save_path), bytes)
	var flow := SceneFlow.new()
	flow.host = Node.new()
	flow.deferred_swaps = false
	flow.save = second
	flow.goto_character_select()
	assert_eq(flow.current_name, "error")
	assert_true(String(flow.current.message).contains("another window"))
	assert_true(String(flow.current.message).contains("30 seconds"), "crash recovery notice explains retry delay")
	flow.host.free()
	flow.free()
	first = null
	var takeover := persistent_save()
	assert_eq(takeover.slot(0).get("name"), "TabOne", "takeover reloads committed state")
	assert_eq(takeover.set_account({"nx": 30, "owned": []}), OK)
	assert_eq(takeover.slot(0).get("name"), "TabOne")


func test_custom_tool_files_do_not_take_the_lock() -> void:
	var save := persistent_save()
	assert_eq(save.create_slot(SAVE_TEST.snapshot()), 0)
	var tool_path := save_path.get_base_dir().path_join("driver_save.json")
	var tool_a := SaveData.new(tool_path)
	var tool_b := SaveData.new(tool_path)
	assert_eq(tool_a.save_file(), OK)
	assert_eq(tool_b.save_file(), OK)
	assert_false(DirAccess.dir_exists_absolute(tool_path + ".lock"))
	assert_eq(save.set_account({"nx": 10, "owned": []}), OK)


func test_live_lease_refused_and_crashed_lease_takeable_only_after_ttl() -> void:
	# Keep the abandoned object alive: no destructor/clean release simulates a crashed owner without killing a process.
	var abandoned := persistent_save()
	assert_eq(abandoned.create_slot(SAVE_TEST.snapshot("TabOne")), 0)
	now += 29.0
	assert_eq(persistent_save().writer_error, ERR_ALREADY_IN_USE)
	now += 1.0
	var recovered := persistent_save()
	assert_eq(recovered.writer_error, OK, "lease expires at the 30-second boundary")
	assert_eq(recovered.slot(0).get("name"), "TabOne", "takeover reloads the last committed snapshot")
	assert_eq(recovered.set_account({"nx": 40, "owned": []}), OK)
	assert_eq(abandoned.save_file(), ERR_ALREADY_IN_USE)
	abandoned = null
	assert_eq(recovered.save_file(), OK, "old destructor cannot remove the new owner's lease")


func test_renewal_and_successful_writes_extend_the_lease() -> void:
	var save := persistent_save()
	now += 25.0
	assert_eq(save.call("renew_writer"), OK)
	now += 25.0
	assert_eq(persistent_save().writer_error, ERR_ALREADY_IN_USE, "renewed lease is still live")
	assert_eq(save.set_account({"nx": 10, "owned": []}), OK)
	now += 25.0
	assert_eq(persistent_save().writer_error, ERR_ALREADY_IN_USE, "successful write renews ownership")
	assert_eq(save.save_file(), OK)
	now += 25.0
	assert_eq(persistent_save().writer_error, ERR_ALREADY_IN_USE, "unchanged successful save also renews")


func test_lost_lease_owner_is_permanently_read_only_and_flow_shows_notice() -> void:
	var sleeping := persistent_save()
	assert_eq(sleeping.create_slot(SAVE_TEST.snapshot("TabOne")), 0)
	now += 30.0
	var takeover := persistent_save()
	assert_eq(takeover.set_account({"nx": 40, "owned": []}), OK)
	var bytes := FileAccess.get_file_as_string(save_path)
	assert_eq(sleeping.set_account({"nx": 999, "owned": []}), ERR_ALREADY_IN_USE)
	assert_eq(sleeping.writer_error, ERR_ALREADY_IN_USE)
	assert_eq(sleeping.account.nx, 0, "failed stale mutation cannot change memory")
	assert_eq(FileAccess.get_file_as_string(save_path), bytes)
	var flow := SceneFlow.new()
	flow.host = Node.new()
	flow.deferred_swaps = false
	flow.save = sleeping
	# Polling is what notices ownership loss during an otherwise idle round/menu.
	flow.call("_renew_save_lease")
	assert_eq(flow.current_name, "error")
	assert_true(String(flow.current.message).contains("another window"))
	flow.host.free()
	flow.free()
	takeover = null
	assert_eq(sleeping.save_file(), ERR_ALREADY_IN_USE, "ownership loss cannot silently reacquire stale state")
	var fresh := persistent_save()
	assert_eq(fresh.account.nx, 40)


func test_clean_release_allows_immediate_takeover() -> void:
	var save := persistent_save()
	assert_eq(save.create_slot(SAVE_TEST.snapshot("TabOne")), 0)
	save = null
	assert_false(DirAccess.dir_exists_absolute(save_path + ".lock"))
	var next := persistent_save()
	assert_eq(next.writer_error, OK)
	assert_eq(next.slot(0).get("name"), "TabOne")
